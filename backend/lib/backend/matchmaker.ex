defmodule Backend.Matchmaker do
  @moduledoc """
  Singleton GenServer that pairs players into game rooms.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def join_queue(player_pid, player_id) do
    GenServer.call(__MODULE__, {:join_queue, player_pid, player_id})
  end

  def leave_queue(player_pid) do
    GenServer.cast(__MODULE__, {:leave_queue, player_pid})
  end

  @impl true
  def init(_) do
    {:ok, %{waiting: nil}}
  end

  @impl true
  def handle_call({:join_queue, player_pid, player_id}, _from, %{waiting: nil} = state) do
    Logger.notice("[Matchmaker] Player #{player_id} queued, waiting for opponent")
    {:reply, {:ok, :waiting}, %{state | waiting: {player_pid, player_id}}}
  end

  def handle_call({:join_queue, player2_pid, player2_id}, _from, %{waiting: {player1_pid, player1_id}} = state) do
    room_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    Logger.notice("[Matchmaker] Match found! #{player1_id} vs #{player2_id} -> room #{room_id}")

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Backend.GameRoomSupervisor,
        %{
          id: :game_room,
          start: {Backend.GameRoom, :start_link, [{room_id, player1_pid, player2_pid}]},
          restart: :temporary
        }
      )

    send(player1_pid, {:matched, room_id, 1})

    {:reply, {:ok, :matched, room_id, 2}, %{state | waiting: nil}}
  end

  @impl true
  def handle_cast({:leave_queue, player_pid}, %{waiting: {pid, _id}} = state) when pid == player_pid do
    Logger.notice("[Matchmaker] Player left queue")
    {:noreply, %{state | waiting: nil}}
  end

  def handle_cast({:leave_queue, _player_pid}, state) do
    {:noreply, state}
  end
end
