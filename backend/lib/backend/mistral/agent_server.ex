defmodule Backend.Mistral.AgentServer do
  @moduledoc """
  GenServer that manages a Mistral image-generation agent.
  Creates the agent on init and spawns async tasks for image generation.
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
    api_key = Application.fetch_env!(:backend, :mistral_api_key)
    Logger.notice("[Mistral] Creating agent...")

    case Client.create_agent(api_key) do
      {:ok, %{"id" => agent_id}} ->
        Logger.notice("[Mistral] agent created")
        {:ok, %{agent_id: agent_id, api_key: api_key}}

      {:error, reason} ->
        {:stop, {:failed_to_create_agent, reason}}
    end
  end

  @impl true
  def handle_cast({:generate_image, prompt, caller_pid}, state) do
    %{agent_id: agent_id, api_key: api_key} = state

    Logger.notice("[Mistral] Generating image for prompt #{inspect prompt}")

    Task.start(fn ->
      result = generate_image_task(api_key, agent_id, prompt)
      Logger.notice("[Mistral] Image generation result: #{inspect result}")
      send(caller_pid, {:image_result, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private

  defp generate_image_task(api_key, agent_id, prompt) do
    with {:ok, conversation} <- Client.create_conversation(api_key, agent_id, prompt),
         {:ok, file_id} <- extract_file_id(conversation),
         {:ok, binary} <- Client.download_file(api_key, file_id) do
      {:ok, Base.encode64(binary)}
    else
      {:error, reason} -> {:error, "Image generation failed: #{inspect(reason)}"}
    end
  end

  defp extract_file_id(%{"outputs" => outputs}) do
    # Find a message.output entry with a tool_file chunk in its content
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
