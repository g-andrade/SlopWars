defmodule Backend.GameRoom do
  @moduledoc """
  GenServer managing a single game between two players.

  Lifecycle: :prompting → :generating_assets → :playing → :game_over
  """

  use TypedStruct

  ########

  typedstruct do
    field(:room_id, String.t, enforce: true)
    field(:phase, phase, enforce: true)
    field(:players, %{required(1) => player, required(2) => player}, enforce: true)
    field(:towers, %{required(1) => nil | number, required(2) => nil | number}, enforce: true)
    field(:pending_assets, %{reference => pending_asset}, enforce: true)
  end

  @typep phase :: :prompting | :generating_assets | :playing | :game_over

  ##

  defmodule Player do
    typedstruct do
      field(:pid, pid, enforce: true)
      field(:prompt, nil | String.t, enforce: true)
      field(:build, nil | map, enforce: true)
    end
  end

  @typep player :: Player.t

  ##

  defmodule PendingAsset do
    typedstruct do
      field(:player_number, pos_integer, enforce: true)
      field(:name, String.t(), enforce: true)
      field(:progress, number, enforce: true)
    end
  end

  @type pending_asset :: PendingAsset.t

  ########

  use GenServer
  require Logger

  def start_link({room_id, player1_pid, player2_pid}) do
    GenServer.start_link(__MODULE__, {room_id, player1_pid, player2_pid},
      name: via(room_id)
    )
  end

  def submit_prompt(room_id, player_number, prompt) do
    GenServer.cast(via(room_id), {:submit_prompt, player_number, prompt})
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

    state = %__MODULE__{
      room_id: room_id,
      phase: :prompting,
      players: %{
        1 => %Player{pid: player1_pid, prompt: nil, build: nil},
        2 => %Player{pid: player2_pid, prompt: nil, build: nil}
      },
      towers: %{1 => nil, 2 => nil},
      pending_assets: %{}
    }

    Logger.notice("[Room #{room_id}] Game created")
    {:ok, state}
  end

  @impl true
  def handle_cast({:submit_prompt, player_number, prompt}, %__MODULE__{phase: :prompting} = state) do
    Logger.notice("[Room #{state.room_id}] Player #{player_number} submitted prompt")

    player = %Player{} = Map.fetch!(state.players, player_number)
    player = %{player | prompt: prompt}
    state = %{state | players: %{state.players | player_number => player}}

    broadcast(state, %{"type" => "prompt_received", "player_number" => player_number})

    if both_prompts_in?(state) do
      broadcast(state, %{"type" => "both_prompts_in"})
      broadcast(state, %{"type" => "analyzing"})
      handle_analysis(state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:submit_prompt, _player_number, _prompt}, state) do
    {:noreply, state}
  end

  def handle_cast({:relay_to_opponent, from_player, message}, %__MODULE__{phase: :playing} = state) do
    to_player = opponent(from_player)
    relay = Map.put(message, "player_number", from_player)
    send(state.players[to_player].pid, {:game_msg, relay})
    {:noreply, state}
  end

  def handle_cast({:relay_to_opponent, _from_player, _message}, state) do
    {:noreply, state}
  end

  def handle_cast({:tower_hp_update, from_player, hp}, %__MODULE__{phase: :playing} = state) do
    target_player = opponent(from_player)
    hp = max(0, hp)

    state = %{state | towers: %{state.towers | target_player => hp}}

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

  def handle_cast({:player_disconnected, player_number}, %__MODULE__{} = state) do
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
  def handle_info({await_ref, status}, %__MODULE__{pending_assets: pending_assets} = state) 
  when is_map_key(pending_assets, await_ref) 
  do
    pending_asset = %PendingAsset{} = Map.fetch!(pending_assets, await_ref)

    case status do
      {:progress, percentage} ->
        pending_asset = %{pending_asset | progress: percentage}
        state = %{state | pending_assets: %{pending_assets | await_ref => pending_asset}}

        notify_assets_progress(state)
        {:noreply, state}

      {:done, files} ->
        [%Backend.AssetManager.FileInfo{} = file_info] = Enum.filter(files, fn %Backend.AssetManager.FileInfo{} = file_info -> file_info.name === "base_basic_pbr.glb" end)

        notify_asset_ready(state, pending_asset, file_info.url)
        state = %{state | pending_assets: Map.delete(pending_assets, await_ref)}

        notify_assets_progress(state)

        if map_size(state.pending_assets) === 0 do
          Logger.notice("[Room #{state.room_id}] Build assets generated, game starting")
          broadcast(state, %{"type" => "playing"})
          {:noreply, %{state | phase: :playing}}
        else
          {:noreply, state}
        end

      :error ->
        broadcast(state, %{"type" => "error", "message" => "Error generating assets"})
        {:stop, :error_generating_assets, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %__MODULE__{} = state) do
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

  defp both_prompts_in?(%__MODULE__{} = state) do
    state.players[1].prompt != nil and state.players[2].prompt != nil
  end

  defp handle_analysis(%__MODULE__{} = state) do
    prompt1 = state.players[1].prompt
    prompt2 = state.players[2].prompt

    case Backend.ASB.analyze_both(prompt1, prompt2) do
      {:ok, build1, build2} ->
        player1 = %Player{} = state.players[1]
        player2 = %Player{} = state.players[2]

        player1 = %{player1 | build: build1}
        player2 = %{player2 | build: build2}

        broadcast(state, %{"type" => "generating_assets"})

        send(player1.pid, {:game_msg, %{
            "type" => "builds_ready",
            "your_build" => build1,
            "opponent_build" => build2
        }})

        send(player2.pid, {:game_msg, %{
            "type" => "builds_ready",
            "your_build" => build2,
            "opponent_build" => build1
        }})

        state = %{state |
          phase: :generating_assets,
          players: %{state.players | 1 => player1, 2 => player2},
          towers: %{state.towers | 1 => build1["tower_hp"], 2 => build2["tower_hp"]}
        }

        state = 
          state
          |> start_generating_asset(1, "bomb", build1["bomb_description"])
          |> start_generating_asset(2, "bomb", build2["bomb_description"])
          |> start_generating_asset(1, "tower", build1["tower_description"])
          |> start_generating_asset(2, "tower", build2["tower_description"])
          |> start_generating_asset(1, "shield", build1["shield_description"])
          |> start_generating_asset(2, "shield", build2["shield_description"])

        {:noreply, state}
        
      {:error, reason} ->
        Logger.error("Failed to analyze prompts: #{inspect reason}")
        broadcast(state, %{"type" => "error", "message" => "Failed to analyze prompts"})
        {:stop, :normal, %{state | phase: :game_over}}
    end
  end

  defp start_generating_asset(%__MODULE__{phase: :generating_assets} = state, player_number, name, description) do
    {:await, await_ref} = Backend.AssetManager.async_generate(description)

    pending_asset = %PendingAsset{player_number: player_number, name: name, progress: 0.0}

    %{state | pending_assets: Map.put(state.pending_assets, await_ref, pending_asset)}
  end

  defp opponent(1), do: 2
  defp opponent(2), do: 1

  defp find_player_by_pid(%__MODULE__{} = state, pid) do
    Enum.find(state.players, fn {_num, player} -> player.pid == pid end)
  end

  defp broadcast(%__MODULE__{} = state, message) do
    Enum.each(state.players, fn {_num, player} ->
      send(player.pid, {:game_msg, message})
    end)
  end

  ###
  
  defp notify_asset_ready(%__MODULE__{} = state, %PendingAsset{} = pending_asset, url) do
    broadcast(state, {:asset_ready, pending_asset.player_number, pending_asset.name, url})
  end

  defp notify_assets_progress(%__MODULE__{pending_assets: pending_assets} = state) do
    list = Map.values(pending_assets)
    {p1_assets, p2_assets} = Enum.split_with(list, &(&1.player_number === 1))

    overall_progress = assets_collective_progress(list)
    p1_progress = assets_collective_progress(p1_assets)
    p2_progress = assets_collective_progress(p2_assets)

    Logger.notice(
      """
      [Match] Asset generation progress:
      * overall: #{overall_progress}
      * player1: #{p1_progress}
      * player2: #{p2_progress}
      """)

    broadcast(state, %{
      "type" => "assets_progress", 
      "overall" => overall_progress,
      "player1" => p1_progress,
      "player2" => p2_progress
    })
  end

  defp assets_collective_progress([]), do: 100.0

  defp assets_collective_progress(list) do
    sum = list |> Enum.map(&(&1.progress)) |> Enum.sum()

    sum / length(list)
  end
end
