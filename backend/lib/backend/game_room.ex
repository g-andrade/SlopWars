defmodule Backend.GameRoom do
  @moduledoc """
  GenServer managing a single game between two players.

  Lifecycle: :prompting → :analyzing → :playing → :game_over
  """

  use GenServer
  require Logger

  def start_link({room_id, player1_pid, player2_pid}) do
    GenServer.start_link(__MODULE__, {room_id, player1_pid, player2_pid},
      name: via(room_id)
    )
  end

  def submit_prompt(room_id, player_number, prompt, base_url) do
    GenServer.cast(via(room_id), {:submit_prompt, player_number, prompt, base_url})
  end

  def relay_to_opponent(room_id, from_player, message) do
    GenServer.cast(via(room_id), {:relay_to_opponent, from_player, message})
  end

  def tower_hp_update(room_id, from_player, hp) do
    GenServer.cast(via(room_id), {:tower_hp_update, from_player, hp})
  end

  def player_disconnected(room_id, player_number) do
    GenServer.cast(via(room_id), {:player_disconnected, player_number})
  end

  defp via(room_id) do
    {:via, Registry, {Backend.GameRegistry, room_id}}
  end

  @impl true
  def init({room_id, player1_pid, player2_pid}) do
    Process.monitor(player1_pid)
    Process.monitor(player2_pid)

    state = %{
      room_id: room_id,
      phase: :prompting,
      base_url: nil,
      players: %{
        1 => %{pid: player1_pid, prompt: nil, build: nil},
        2 => %{pid: player2_pid, prompt: nil, build: nil}
      },
      towers: %{1 => nil, 2 => nil}
    }

    Logger.notice("[Room #{room_id}] Game created")
    {:ok, state}
  end

  @impl true
  def handle_cast({:submit_prompt, player_number, prompt, base_url}, %{phase: :prompting} = state) do
    Logger.notice("[Room #{state.room_id}] Player #{player_number} submitted prompt")

    state =
      state
      |> put_in([:players, player_number, :prompt], prompt)
      |> then(fn s -> if s.base_url == nil, do: %{s | base_url: base_url}, else: s end)

    broadcast(state, %{"type" => "prompt_received", "player_number" => player_number})

    if both_prompts_in?(state) do
      broadcast(state, %{"type" => "both_prompts_in"})
      broadcast(state, %{"type" => "analyzing"})
      start_analysis(state)
      {:noreply, %{state | phase: :analyzing}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:submit_prompt, _player_number, _prompt, _base_url}, state) do
    {:noreply, state}
  end

  def handle_cast({:relay_to_opponent, from_player, message}, %{phase: :playing} = state) do
    to_player = opponent(from_player)
    relay = Map.put(message, "player_number", from_player)
    send(state.players[to_player].pid, {:game_msg, relay})
    {:noreply, state}
  end

  def handle_cast({:relay_to_opponent, _from_player, _message}, state) do
    {:noreply, state}
  end

  def handle_cast({:tower_hp_update, from_player, hp}, %{phase: :playing} = state) do
    target_player = opponent(from_player)
    hp = max(0, hp)
    state = put_in(state, [:towers, target_player], hp)

    broadcast(state, %{
      "type" => "tower_hp",
      "player_number" => from_player,
      "target_player_number" => target_player,
      "hp" => hp
    })

    if hp <= 0 do
      broadcast(state, %{
        "type" => "game_over",
        "winner_number" => from_player,
        "reason" => "tower_destroyed"
      })

      {:stop, :normal, %{state | phase: :game_over}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:tower_hp_update, _from_player, _hp}, state) do
    {:noreply, state}
  end

  def handle_cast({:player_disconnected, player_number}, state) do
    winner = opponent(player_number)
    Logger.notice("[Room #{state.room_id}] Player #{player_number} disconnected, player #{winner} wins")

    send(state.players[winner].pid, {:game_msg, %{
      "type" => "game_over",
      "winner_number" => winner,
      "reason" => "opponent_disconnected"
    }})

    {:stop, :normal, %{state | phase: :game_over}}
  end

  @impl true
  def handle_info({:asb_results, results}, %{phase: :analyzing} = state) do
    case results do
      {{:ok, build1}, {:ok, build2}} ->
        state =
          state
          |> put_in([:players, 1, :build], build1)
          |> put_in([:players, 2, :build], build2)
          |> put_in([:towers, 1], build1["tower_hp"])
          |> put_in([:towers, 2], build2["tower_hp"])

        send(state.players[1].pid, {:game_msg, %{
          "type" => "builds_ready",
          "your_build" => build1,
          "opponent_build" => build2
        }})

        send(state.players[2].pid, {:game_msg, %{
          "type" => "builds_ready",
          "your_build" => build2,
          "opponent_build" => build1
        }})

        Logger.notice("[Room #{state.room_id}] Builds ready, game starting")
        {:noreply, %{state | phase: :playing}}

      _ ->
        broadcast(state, %{"type" => "error", "message" => "Failed to analyze prompts"})
        {:stop, :normal, %{state | phase: :game_over}}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case find_player_by_pid(state, pid) do
      nil ->
        {:noreply, state}

      {disconnected, _} ->
        winner = opponent(disconnected)

        if state.phase != :game_over do
          Logger.notice("[Room #{state.room_id}] Player #{disconnected} connection lost")

          send(state.players[winner].pid, {:game_msg, %{
            "type" => "game_over",
            "winner_number" => winner,
            "reason" => "opponent_disconnected"
          }})

          {:stop, :normal, %{state | phase: :game_over}}
        else
          {:noreply, state}
        end
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private --

  defp both_prompts_in?(state) do
    state.players[1].prompt != nil and state.players[2].prompt != nil
  end

  defp start_analysis(state) do
    room_pid = self()
    base_url = state.base_url
    prompt1 = state.players[1].prompt
    prompt2 = state.players[2].prompt

    Task.start(fn ->
      result1 = Backend.ASB.analyze(prompt1, base_url)
      result2 = Backend.ASB.analyze(prompt2, base_url)
      send(room_pid, {:asb_results, {result1, result2}})
    end)
  end

  defp opponent(1), do: 2
  defp opponent(2), do: 1

  defp find_player_by_pid(state, pid) do
    Enum.find(state.players, fn {_num, player} -> player.pid == pid end)
  end

  defp broadcast(state, message) do
    Enum.each(state.players, fn {_num, player} ->
      send(player.pid, {:game_msg, message})
    end)
  end
end
