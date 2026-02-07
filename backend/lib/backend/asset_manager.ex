defmodule Backend.AssetManager do
  use GenServer

  alias Backend.Hyper3D.Client

  require Logger

  use TypedStruct

  import ExUnit.Assertions

  # Constants

  @max_ongoing_jobs 4

  @poll_interval_ms :timer.seconds(5)

  # Types

  typedstruct do
    field(:dev_mode?, boolean, enforce: true)
    field(:jobs, [job], enforce: true)
    field(:poll_timer, reference, enforce: true)
  end

  defmodule Job do
    typedstruct do
      field(:id, integer(), enforce: true)
      field(:await_ref, nil | reference(), enforce: true)
      field(:prompt, String.t(), enforce: true)
      field(:status, :enqueued | :ongoing | :done, enforce: true)
      field(:enqueued_ts, nil | DateTime.utc_now(), enforce: true)
      field(:requester_pids, [pid()], enforce: true)
      field(:task_uuid, nil | String.t(), enforce: true)
      field(:subscription_key, nil | String.t(), enforce: true)
      field(:last_polled, nil | DateTime.t, enforce: true)
      field(:files, nil | [Backend.AssetManager.FileInfo.t], enforce: true)
    end
  end

  defmodule FileInfo do
    typedstruct do
      field(:name, String.t, enforce: true)
      field(:url, String.t, enforce: true)
    end
  end

  @type job :: Job.t

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def async_generate(prompt) do
    {:await, _await_ref} = GenServer.call(__MODULE__, {:async_generate, prompt, self()})
  end

  # Callbacks

  @impl true
  def init(_) do
    poll_timer = schedule_poll()

    if dev_mode?() do
      Logger.notice("[Assets] Starting in dev mode (placeholder)")
      {:ok, %__MODULE__{dev_mode?: true, jobs: [placeholder_job()], poll_timer: poll_timer}}
    else
      _ = api_key!()
      Logger.notice("[Assets] Starting in real mode")
      {:ok, %__MODULE__{dev_mode?: false, jobs: load_jobs(), poll_timer: poll_timer}}
    end
  end

  @impl true
  def handle_call({:async_generate, prompt, requester_pid}, from, state) do
    await_ref = make_ref()
    GenServer.reply(from, {:await, await_ref})

    if state.dev_mode? do
      [placeholder] = state.jobs
      notify_job_progress([requester_pid], await_ref, 50.0)
      notify_job_completed([requester_pid], await_ref, placeholder)
      {:noreply, state}
    else
      state = enqueue_new_job(state, prompt, requester_pid, await_ref)
      state = refresh(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, %__MODULE__{} = state) do
    state = state |> poll() |> refresh()
    {:noreply, state}
  end

  ## Internal

  defp dev_mode? do
    Application.fetch_env!(:backend, :dev_mode)
  end

  defp api_key! do
    Application.fetch_env!(:backend, :hyper3d_api_key)
  end

  defp schedule_poll() do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end

  defp placeholder_job() do
    files_dir = Path.join(:code.priv_dir(:backend) |> to_string(), "static/placeholders/incredible_bear")

    files =
      files_dir
      |> File.ls!()
      |> Enum.map(
        fn filename ->
          rel_url = "placeholders/incredible_bear/#{filename}"
          %FileInfo{
            name: filename,
            url: rel_url
          }
        end)

    %Job{
      id: -1,
      await_ref: nil,
      prompt: "---",
      status: :done,
      enqueued_ts: nil,
      requester_pids: [],
      task_uuid: nil,
      subscription_key: nil,
      last_polled: nil,
      files: files
    }
  end

  defp load_jobs() do
    dir = models_dir()
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.reduce(
      [],
      fn subdir, acc ->
        path = Path.join(dir, subdir)

        with true <- File.dir?(path),
             {:ok, job = %Job{}} = load_job(path) do

          if Enum.any?(acc, &(&1.id === job.id)) do
            Logger.error("Skipping job from #{inspect path} with repeated id #{job.id}")
            acc
          else
            [job | acc]
          end
        else
          false ->
            acc
          {:error, :enoent} ->
            acc
          {:error, reason} ->
            Logger.error("Error loading job from path #{inspect path}: #{inspect reason}")
            acc
        end
      end)
  end

  defp models_dir do
    Path.join(:code.priv_dir(:backend) |> to_string(), "static/models")
  end

  defp load_job(dir) do
    status_path = Path.join(dir, "status.json")

    with {:ok, bin_content} <- File.read(status_path),
         {:ok, json_content} <- Jason.decode(bin_content),
         {:ok, attributes} <- load_job_attributes(json_content) do
      {:ok, %Job{
        id: attributes.id,
        await_ref: nil,
        prompt: attributes.prompt,
        status: attributes.status,
        enqueued_ts: attributes.enqueued_ts,
        requester_pids: [],
        task_uuid: attributes.task_uuid,
        subscription_key: attributes.subscription_key,
        last_polled: nil,
        files: attributes.files
      }}
    else
      {:error, :enoent} ->
        {:error, :not_a_job}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_job_attributes(%{
    "id" => id,
    "prompt" => prompt,
    "status" => status,
    "enqueued_ts" => enqueued_ts,
    "task_uuid" => task_uuid,
    "subscription_key" => subscription_key,
    "files" => files
  }) when is_integer(id) and is_binary(prompt) and status in ["ongoing", "done"] and is_binary(enqueued_ts) and is_binary(task_uuid) and is_binary(subscription_key) do
    with {:ok, loaded_files} <- load_job_files(files),
         {:ok, loaded_enqueued_ts, _} <- DateTime.from_iso8601(enqueued_ts) do
      {:ok, %{
          id: id,
          prompt: prompt,
          status: status,
          enqueued_ts: loaded_enqueued_ts,
          task_uuid: task_uuid,
          subscription_key: subscription_key,
          files: loaded_files
        }}
    else

      {:error, :invalid_format} ->
         {:error, {:enqueued_ts, enqueued_ts}}

      {:error, reason} ->
        {:error, {:files, reason}}
    end
  end

  defp load_job_attributes(json) do
    {:error, {:bad_attributes, json}}
  end

  defp load_job_files(files) when is_list(files) do
    try do
      files
      |> Enum.filter(&(&1 !== "status.json"))
      |> Enum.map(&load_job_file_info!/1)
    catch
      :error, reason ->
        {:error, reason}
    else
      list ->
        {:ok, list}
    end
  end

  defp load_job_file_info!(%{"name" => name, "url" => url}) when is_binary(name) and is_binary(url) do
    %FileInfo{
      name: name,
      url: url
    }
  end
    
  ## Internal

  defp enqueue_new_job(%__MODULE__{} = state, prompt, requester_pid, await_ref) do
    job = %Job{
      id: new_job_id(state.jobs),
      await_ref: await_ref,
      prompt: prompt,
      status: :enqueued,
      enqueued_ts: DateTime.utc_now(),
      requester_pids: [requester_pid],
      task_uuid: nil,
      subscription_key: nil,
      last_polled: nil,
      files: []
    }

    %{state | jobs: [job | state.jobs]}
  end

  defp new_job_id([]), do: 1
  defp new_job_id(jobs), do: Enum.max_by(jobs, &(&1.id)).id + 1

  defp refresh(%__MODULE__{} = state) do
    frequencies = status_frequencies(state)

    cond do
      frequencies.enqueued > 0 and frequencies.ongoing < @max_ongoing_jobs ->
        start_job(state)

      true ->
        state
    end
  end

  defp start_job(%__MODULE__{} = state) do
    job = %Job{} = next_job_to_start!(state.jobs)
    assert job.status === :enqueued

    case Client.generate(api_key!(), job.prompt) do
      {:ok, %{uuid: task_uuid, subscription_key: subscription_key}} ->
        job = %{job | status: :ongoing, task_uuid: task_uuid, subscription_key: subscription_key}
        save_job_to_disk(job)
        update_job(state, job)

      {:error, reason} ->
        Logger.error("Error starting job #{job.id}: #{inspect reason}")
        notify_job_failed(job.requester_pids, job.await_ref, job)
        remove_job(state, job)
    end
  end

  ############

  defp poll(%__MODULE__{} = state) do
    assert Process.cancel_timer(state.poll_timer) === false
    state = %{state | poll_timer: Process.send_after(self(), :poll, @poll_interval_ms)}

    case state.jobs |> Enum.filter(&(&1.status === :ongoing)) |> Enum.min_by(&job_polling_priority/1, &<=/2, fn -> nil end) do
      nil ->
        state

      %Job{} = job ->
        assert job.subscription_key !== nil
        job = %{job | last_polled: DateTime.utc_now()}
        state = update_job(state, job)

        case Client.check_status(api_key!(), job.subscription_key) do
          {:ongoing, percentage} ->
            notify_job_progress(job.requester_pids, job.await_ref, percentage)
            Logger.notice("Job #{job.id} ongoing (#{inspect percentage}%)")
            state

          {:done, :ok} ->
            case Client.download_results(api_key!(), job.task_uuid) do
              {:ok, json_file_infos} ->
                Logger.notice("Job #{job.id} is done")
                job = %{job | 
                  status: :done, 
                  files: files_from_json_response!(json_file_infos)
                }
                notify_job_completed(job.requester_pids, job.await_ref, job)

                save_job_to_disk(job)

                update_job(state, job)

              {:error, reason} ->
                Logger.error("Failed to download results for job #{job.id}: #{inspect reason}")

                state
            end

          {:done, :error} ->
            Logger.error("Job #{job.id} failed")
            notify_job_failed(job.requester_pids, job.await_ref, job)

            remove_job_from_disk(job)
            remove_job(state, job)

          {:error, reason} ->
            Logger.error("Failed to poll job #{job.id}: #{inspect reason}")
            state
        end
    end
  end

  defp job_polling_priority(%Job{} = job) do
    assert job.status === :ongoing

    if job.last_polled === nil do
      [1, DateTime.to_unix(job.enqueued_ts, :millisecond)]
    else
      [2, DateTime.to_unix(job.last_polled, :millisecond)]
    end
  end

  defp files_from_json_response!(json_file_infos) do
    Enum.map(
      json_file_infos,
      fn %{"name" => name, "url" => url} when is_binary(name) and is_binary(url) ->
        %FileInfo{name: name, url: url}
      end)
  end

  ##############

  defp save_job_to_disk(%Job{} = job) do
    dir = Path.join(models_dir(), Integer.to_string(job.id))
    File.mkdir_p!(dir)

    json_attributes = %{
      "id" => job.id,
      "prompt" => job.prompt,
      "status" => job.status,
      "enqueued_ts" => DateTime.to_iso8601(job.enqueued_ts),
      "task_uuid" => job.task_uuid,
      "subscription_key" => job.subscription_key,
      "files" => file_infos_to_json(job.files)
    }

    status_path = Path.join(dir, "status.json")
    File.write!(status_path, Jason.encode!(json_attributes))
  end

  defp file_infos_to_json(files) do
    Enum.map(
      files,
      fn %FileInfo{} = file_info ->
        %{ 
          "name" => file_info.name,
          "url" => file_info.url
        }
      end)
  end

  ##############

  defp remove_job_from_disk(%Job{} = job) do
    dir = Path.join(models_dir(), Integer.to_string(job.id))
    File.mkdir_p!(dir)

    status_path = Path.join(dir, "status.json")
    _ = File.rm(status_path)
  end

  ##############

  defp update_job(state, job) do
    %{state | jobs: update_job_recur(state.jobs, job)}
  end

  defp update_job_recur([job_b = %Job{} | next], %Job{} = job) do
    if job_b.id === job.id do
      [job | next]
    else
      [job_b | update_job_recur(next, job)]
    end
  end

  defp remove_job(%__MODULE__{} = state, %Job{} = job) do
    {[_], jobs} = Enum.split(state.jobs, &(&1.id === job.id))
    %{state | jobs: jobs}
  end

  defp next_job_to_start!(jobs) do
    jobs
    |> Enum.filter(&(&1.status === :enqueued))
    |> Enum.min_by(&(&1.enqueued_ts), DateTime)
  end

  defp status_frequencies(%__MODULE__{} = state) do
    Map.merge(
      %{enqueued: 0, ongoing: 0, done: 0,},
      state.jobs |> Enum.map(&(&1.status)) |> Enum.frequencies()
    )
  end

  defp notify_job_progress(requester_pids, await_ref, percentage) do
    Enum.each(requester_pids, &send(&1, {await_ref, {:progress, percentage}}))
  end

  defp notify_job_completed(requester_pids, await_ref, %Job{status: :done, files: files}) do
    Enum.each(requester_pids, &send(&1, {await_ref, {:done, files}}))
  end

  defp notify_job_failed(requester_pids, await_ref, %Job{status: status}) when status in [:enqueued, :ongoing] do
    Enum.each(requester_pids, &send(&1, {await_ref, :error}))
  end
end
