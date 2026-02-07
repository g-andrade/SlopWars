defmodule Backend.Hyper3D.Client do
  @moduledoc """
  Stateless HTTP wrapper around Hyper3D Rodin Gen-2 API for text-to-3D model generation.

  Flow:
    1. `generate/3` — submit a text prompt, get back a task UUID and subscription key
    2. `check_status/2` — poll with subscription key until all jobs are "Done"
    3. `download/2` — fetch download URLs for the generated model files

  For convenience, `generate_and_poll/3` wraps the full flow: submit, poll until done,
  and return download URLs.
  """

  require Logger

  @base_url "https://api.hyper3d.com/api/v2"
  #@poll_interval_ms 5_000
  #@max_poll_attempts ceil(10 * 60 * 1000 / @poll_interval_ms)

  @default_tier "Sketch"
  @default_mesh_mode "Quad"
  @default_format "glb"

  @doc """
  Full generation flow: submit prompt, poll until done, return download URLs.

  Returns `{:ok, files}` or `{:error, reason}`.
  """
#  def generate_and_poll(base_url, prompt, opts \\ []) do
#    case Application.fetch_env!(:backend, :dev_mode) do
#      true ->
#        dir = Path.join(:code.priv_dir(:backend) |> to_string(), "static/placeholders/medieval_castle_sketch")
#
#        dir
#        |> File.ls!()
#        |> Enum.map(
#          fn filename ->
#            %{
#              "name" => filename,
#              "url" => "#{base_url}/placeholders/medieval_castle_sketch/#{URI.encode(filename)}"
#            }
#          end)
#
#      false ->
#        api_key = Application.fetch_env!(:backend, :hyper3d_api_key)
#
#        with {:ok, %{uuid: uuid, subscription_key: sub_key}} <- generate(api_key, prompt, opts),
#             _ = Logger.notice("[Hyper3D] Task submitted: #{uuid}"),
#             :ok <- poll_until_done(api_key, sub_key, opts),
#             {:ok, results} <- download_results(api_key, uuid) do
#          {:ok, results}
#        end
#    end
#  end

  def generate(api_key, prompt, opts \\ []) do
    tier = Keyword.get(opts, :tier, @default_tier)
    mesh_mode = Keyword.get(opts, :mesh_mode, @default_mesh_mode)
    #quality = Keyword.get(opts, :quality, "low")
    format = Keyword.get(opts, :format, @default_format)

    Req.post("#{@base_url}/rodin",
      form_multipart: [
        tier: tier,
        prompt: prompt,
        mesh_mode: mesh_mode,
        # quality: quality,
        # quality_override: 20_000,
        geometry_file_format: format
      ],
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 30_000
    )
    |> handle_generate_response()
  end

  def check_status(api_key, subscription_key) do
    Req.post("#{@base_url}/status",
      json: %{subscription_key: subscription_key},
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 15_000
    )
    |> handle_status_response()
  end

  def download_results(api_key, task_uuid) do
    Req.post("#{@base_url}/download",
      json: %{task_uuid: task_uuid},
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 15_000
    )
    |> handle_download_response()
  end

  # -- Private -----------------------------------------------------------------

#  defp poll_until_done(api_key, subscription_key, opts) do
#    interval = Keyword.get(opts, :poll_interval_ms, @poll_interval_ms)
#    max_attempts = Keyword.get(opts, :max_poll_attempts, @max_poll_attempts)
#    do_poll(api_key, subscription_key, interval, max_attempts, 0)
#  end
#
#  defp do_poll(_api_key, _subscription_key, _interval, max_attempts, attempt)
#  when attempt >= max_attempts do
#    {:error, :poll_timeout}
#  end
#
#  defp do_poll(api_key, subscription_key, interval, max_attempts, attempt) do
#    case check_status(api_key, subscription_key) do
#      {:ok, jobs} ->
#        statuses = Enum.map(jobs, & &1["status"])
#        Logger.debug("[Hyper3D] Poll ##{attempt + 1}: #{inspect(statuses)}")
#
#        cond do
#          Enum.all?(statuses, &(&1 == "Done")) ->
#            :ok
#
#          Enum.any?(statuses, &(&1 == "Failed")) ->
#            {:error, :generation_failed}
#
#          true ->
#            Process.sleep(interval)
#            do_poll(api_key, subscription_key, interval, max_attempts, attempt + 1)
#        end
#
#      {:error, _} = error ->
#        error
#    end
#  end

  defp handle_generate_response({:ok, %Req.Response{status: status, body: body}})
  when status in 200..299 do
    case body do
      %{"uuid" => uuid, "jobs" => %{"subscription_key" => sub_key}} ->
        {:ok, %{uuid: uuid, subscription_key: sub_key}}

      _ ->
        {:error, "Unexpected response structure: #{inspect(body)}"}
    end
  end

  defp handle_generate_response({:ok, %Req.Response{status: status, body: body}}) do
    error = get_in(body, ["error"]) || "HTTP #{status}"
    {:error, "Hyper3D generation failed: #{error} — #{inspect(body)}"}
  end

  defp handle_generate_response({:error, reason}), do: {:error, reason}

  defp handle_status_response({:ok, %Req.Response{status: status, body: body}})
  when status in 200..299 do
    case body do
      %{"jobs" => jobs} when is_list(jobs) -> 
        statuses = Enum.map(jobs, & &1["status"])
        count_done = Enum.count(statuses, &(&1 === "Done"))

        cond do
          count_done === length(jobs) ->
            {:done, :ok}

          Enum.any?(statuses, &(&1 == "Failed")) ->
            {:done, :error}
          
          true ->
            progress = 100 * count_done / length(jobs)
            {:ongoing, progress}
        end
      _ -> 
        {:error, "Unexpected status response: #{inspect(body)}"}
    end
  end

  defp handle_status_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "HTTP #{status}: #{inspect(body)}"}
  end

  defp handle_status_response({:error, reason}), do: {:error, reason}

  defp handle_download_response({:ok, %Req.Response{status: status, body: body}})
  when status in 200..299 do
    case body do
      %{"list" => files} when is_list(files) -> {:ok, files}
      _ -> {:error, "Unexpected download response: #{inspect(body)}"}
    end
  end

  defp handle_download_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "HTTP #{status}: #{inspect(body)}"}
  end

  defp handle_download_response({:error, reason}), do: {:error, reason}
end
