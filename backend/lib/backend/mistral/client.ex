defmodule Backend.Mistral.Client do
  @moduledoc """
  Stateless HTTP wrapper around Mistral Agents API endpoints.
  """

  @base_url "https://api.mistral.ai"

  def create_agent(api_key) do
    Req.post("#{@base_url}/v1/agents",
      json: %{
        model: "mistral-medium-latest",
        name: "image-generator",
        tools: [%{type: "image_generation"}]
      },
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 30_000
    )
    |> handle_response()
  end

  def create_conversation(api_key, agent_id, prompt) do
    Req.post("#{@base_url}/v1/conversations",
      json: %{
        agent_id: agent_id,
        inputs: prompt,
        stream: false
      },
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 120_000
    )
    |> handle_response()
  end

  def download_file(api_key, file_id) do
    Req.get("#{@base_url}/v1/files/#{file_id}/content",
      headers: [{"authorization", "Bearer #{api_key}"}],
      receive_timeout: 60_000
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, "HTTP #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "HTTP #{status}: #{inspect(body)}"}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end
end
