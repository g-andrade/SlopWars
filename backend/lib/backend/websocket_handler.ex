defmodule Backend.WebsocketHandler do
  @behaviour :cowboy_websocket

  use TypedStruct

  import ExUnit.Assertions

  ####

  if Mix.env() === :test do
    @ping_interval_ms 500
  else
    @ping_interval_ms 10_000
  end

  ####

  typedstruct do
    field(:base_url, String.t(), enforce: true)
    field(:player_id, String.t(), enforce: true)
    field(:status, atom, enforce: true)
    field(:room_id, nil | String.t(), enforce: true)
    field(:player_number, pos_integer, enforce: true)
    field(:ping_timer, reference, enforce: true)
  end

  ####

  @impl true
  def init(req, nil) do
    host = :cowboy_req.host(req)
    port = :cowboy_req.port(req)
    path = :cowboy_req.path(req)
    prefix = String.replace_trailing(path, "/ws", "")
    base_url = "http://#{host}:#{port}#{prefix}"
    player_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    new_state =
      %__MODULE__{
        base_url: base_url,
        player_id: player_id,
        status: :connected,
        room_id: nil,
        player_number: nil,
        ping_timer: Process.send_after(self(), :send_ping, @ping_interval_ms)
      }

    {:cowboy_websocket, req, new_state}
  end

  @impl true
  def websocket_init(state) do
    {:ok, state}
  end

  @impl true
  def websocket_handle({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "ping"}} ->
        reply(%{"type" => "pong"}, state)

      {:ok, %{"type" => "join_queue"}} ->
        handle_join_queue(state)

      {:ok, %{"type" => "submit_prompt", "prompt" => prompt}} ->
        handle_submit_prompt(prompt, state)

      {:ok, %{"type" => "player_update"} = msg} ->
        handle_relay(msg, state)

      {:ok, %{"type" => "shoot"} = msg} ->
        handle_relay(msg, state)

      {:ok, %{"type" => "tower_hp", "hp" => hp}} ->
        handle_tower_hp(hp, state)

      {:ok, decoded} ->
        reply(%{"type" => "echo", "data" => decoded}, state)

      {:error, _} ->
        reply(%{"type" => "error", "message" => "invalid json"}, state)
    end
  end

  def websocket_handle({:ping, payload}, state) do
    {:reply, {:pong, payload}, state}
  end

  def websocket_handle(:pong, state) do
    {:ok, state}
  end

  def websocket_handle(_frame, state) do
    {:ok, state}
  end

  @impl true
  def websocket_info({:matched, room_id, player_number}, %__MODULE__{} = state) do
    state = %{state | status: :in_game, room_id: room_id, player_number: player_number}
    reply(%{"type" => "matched", "room_id" => room_id, "player_number" => player_number}, state)
  end

  def websocket_info({:game_msg, payload}, state) when is_tuple(payload) do
    case payload do
      {:asset_ready, player_number, name, url} ->
        reply(
          %{
            "type" => "asset_ready", 
            "player_number" => player_number, 
            "name" => name, 
            "url" => resolve_url(url, state.base_url)
          },
          state)
    end
  end

  def websocket_info({:game_msg, payload}, state) do
    {:reply, {:text, Jason.encode!(payload)}, state}
  end

  def websocket_info(:send_ping, %__MODULE__{} = state) do
    assert Process.cancel_timer(state.ping_timer) === false
    state = %{state | ping_timer: Process.send_after(self(), :send_ping, @ping_interval_ms)}
    {:reply, :ping, state}
  end

  def websocket_info(_info, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _req, %__MODULE__{} = state) do
    case state.status do
      :in_queue ->
        Backend.Matchmaker.leave_queue(self())

      :in_game when state.room_id != nil and state.player_number != nil ->
        Backend.GameRoom.player_disconnected(state.room_id, state.player_number)

      _ ->
        :ok
    end

    :ok
  end

  # -- Private handlers --

  defp handle_join_queue(%__MODULE__{} = state) do
    case Backend.Matchmaker.join_queue(self(), state.player_id) do
      {:ok, :waiting} ->
        state = %{state | status: :in_queue}
        reply(%{"type" => "queued"}, state)

      {:ok, :matched, room_id, player_number} ->
        state = %{state | status: :in_game, room_id: room_id, player_number: player_number}
        reply(%{"type" => "matched", "room_id" => room_id, "player_number" => player_number}, state)
    end
  end

  defp handle_submit_prompt(prompt, %__MODULE__{} = state) do
    if state.status == :in_game and state.room_id != nil do
      Backend.GameRoom.submit_prompt(state.room_id, state.player_number, prompt)
      {:ok, state}
    else
      reply(%{"type" => "error", "message" => "not in a game"}, state)
    end
  end

  defp handle_relay(msg, %__MODULE__{} = state) do
    if state.status == :in_game and state.room_id != nil do
      Backend.GameRoom.relay_to_opponent(state.room_id, state.player_number, msg)
      {:ok, state}
    else
      reply(%{"type" => "error", "message" => "not in a game"}, state)
    end
  end

  defp handle_tower_hp(hp, %__MODULE__{} = state) do
    if state.status == :in_game and state.room_id != nil do
      Backend.GameRoom.tower_hp_update(state.room_id, state.player_number, hp)
      {:ok, state}
    else
      reply(%{"type" => "error", "message" => "not in a game"}, state)
    end
  end

  defp reply(message, state) do
    {:reply, {:text, Jason.encode!(message)}, state}
  end

  defp resolve_url(url, base_url) do
    if String.starts_with?(String.downcase(url), ["http://", "https://"]) do
      url
    else
      "#{base_url}/#{url}"
    end
  end
end
