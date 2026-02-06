defmodule Backend.WebsocketHandler do
  @behaviour :cowboy_websocket

  @impl true
  def init(req, state) do
    {:cowboy_websocket, req, state}
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
  def websocket_info({:image_result, {:ok, base64_image}}, state) do
    reply = Jason.encode!(%{"type" => "image_result", "image" => base64_image, "format" => "png"})
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
