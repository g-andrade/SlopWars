defmodule Backend.Mistral.AgentServer do
  @moduledoc """
  GenServer that manages a Mistral image-generation agent.
  In dev mode, returns random placeholder images with a simulated delay.
  """

  use GenServer

  alias Backend.Mistral.Client

  require Logger

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def generate_image(prompt, caller_pid) do
    GenServer.cast(__MODULE__, {:generate_image, prompt, caller_pid})
  end

  # Callbacks

  @impl true
  def init(_) do
    if dev_mode?() do
      Logger.notice("[Mistral] Starting in dev mode (placeholders)")
      {:ok, %{dev_mode: true, last_placeholder: nil}}
    else
      api_key = Application.fetch_env!(:backend, :mistral_api_key)
      Logger.notice("[Mistral] Creating agent...")

      case Client.create_agent(api_key) do
        {:ok, %{"id" => agent_id}} ->
          Logger.notice("[Mistral] agent created")
          {:ok, %{dev_mode: false, agent_id: agent_id, api_key: api_key}}

        {:error, reason} ->
          {:stop, {:failed_to_create_agent, reason}}
      end
    end
  end

  @impl true
  def handle_cast({:generate_image, prompt, caller_pid}, %{dev_mode: true} = state) do
    Logger.notice("[Dev] Generating placeholder for prompt #{inspect(prompt)}")

    {filename, state} = pick_placeholder(state)

    Task.start(fn ->
      delay = round(1000 * (12 + :rand.uniform() * (30 - 12)))
      Logger.notice("[Dev] Simulating #{div(delay, 1000)}s delay...")
      Process.sleep(delay)
      send(caller_pid, {:image_result, {:ok, "placeholders/#{filename}"}})
    end)

    {:noreply, state}
  end

  def handle_cast({:generate_image, prompt, caller_pid}, state) do
    %{agent_id: agent_id, api_key: api_key} = state

    Logger.notice("[Mistral] Generating image for prompt #{inspect(prompt)}")

    Task.start(fn ->
      result = generate_image_task(api_key, agent_id, prompt)
      Logger.notice("[Mistral] Image generation result: #{inspect(result)}")
      send(caller_pid, {:image_result, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private — dev mode

  defp dev_mode?, do: Application.get_env(:backend, :dev_mode, false)

  defp pick_placeholder(state) do
    dir = Path.join(:code.priv_dir(:backend) |> to_string(), "static/placeholders")

    files =
      case File.ls(dir) do
        {:ok, entries} -> Enum.filter(entries, &String.ends_with?(&1, [".jpg", ".png"]))
        _ -> []
      end

    candidates = List.delete(files, state.last_placeholder)
    chosen = if candidates == [], do: Enum.random(files), else: Enum.random(candidates)

    {chosen, %{state | last_placeholder: chosen}}
  end

  # Private — production

  defp generate_image_task(api_key, agent_id, prompt) do
    with {:ok, conversation} <- Client.create_conversation(api_key, agent_id, prompt),
         {:ok, file_id} <- extract_file_id(conversation),
         {:ok, binary} <- Client.download_file(api_key, file_id),
         {:ok, filename} <- save_image(binary) do
      {:ok, "images/#{filename}"}
    else
      {:error, reason} -> {:error, "Image generation failed: #{inspect(reason)}"}
    end
  end

  defp save_image(binary) do
    dir = Path.join(:code.priv_dir(:backend) |> to_string(), "static/images")
    File.mkdir_p!(dir)
    filename = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower) <> ".jpg"
    path = Path.join(dir, filename)

    case File.write(path, binary) do
      :ok -> {:ok, filename}
      {:error, reason} -> {:error, "Failed to save image: #{inspect(reason)}"}
    end
  end

  defp extract_file_id(%{"outputs" => outputs}) do
    outputs
    |> Enum.flat_map(fn
      %{"type" => "message.output", "content" => content} when is_list(content) -> content
      _ -> []
    end)
    |> Enum.find_value({:error, "No image file found in response"}, fn
      %{"type" => "tool_file", "file_id" => file_id} -> {:ok, file_id}
      _ -> nil
    end)
  end

  defp extract_file_id(response) do
    {:error, "Unexpected response structure: #{inspect(response)}"}
  end
end
