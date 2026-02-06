defmodule Backend.WebsocketHandler do
  @behaviour :cowboy_websocket

  @impl true
  def init(req, state) do
    host = :cowboy_req.host(req)
    port = :cowboy_req.port(req)
    base_url = "http://#{host}:#{port}"
    {:cowboy_websocket, req, Map.put(state, :base_url, base_url)}
  end

  @impl true
  def websocket_init(state) do
    {:ok, state}
  end

  @impl true
  def websocket_handle({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "ping"}} ->
        reply = Jason.encode!(%{"type" => "pong"})
        {:reply, {:text, reply}, state}

      {:ok, %{"type" => "generate_image", "prompt" => prompt}} ->
        Backend.Mistral.AgentServer.generate_image(prompt, self())
        reply = Jason.encode!(%{"type" => "generating", "prompt" => prompt})
        {:reply, {:text, reply}, state}

      {:ok, decoded} ->
        {:reply, {:text, Jason.encode!(%{"type" => "echo", "data" => decoded})}, state}

      {:error, _} ->
        {:reply, {:text, Jason.encode!(%{"type" => "error", "message" => "invalid json"})}, state}
    end
  end

  def websocket_handle({:ping, payload}, state) do
    {:reply, {:pong, payload}, state}
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  @impl true
  def websocket_info({:image_result, {:ok, filename}}, state) do
    url = "#{state.base_url}/#{filename}"
    reply = Jason.encode!(%{"type" => "image_result", "url" => url})
    {:reply, {:text, reply}, state}
  end

  def websocket_info({:image_result, {:error, message}}, state) do
    reply = Jason.encode!(%{"type" => "error", "message" => message})
    {:reply, {:text, reply}, state}
  end

  def websocket_info(_info, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, _state) do
    :ok
  end
end
