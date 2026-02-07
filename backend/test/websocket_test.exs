defmodule Backend.WebsocketTest do
  use ExUnit.Case

  @port 8080
  @prefix "/fhampuaqm7vdq5niuzo3okajq4"

  defp connect_ws do
    {:ok, conn_pid} = :gun.open(~c"localhost", @port)
    {:ok, :http} = :gun.await_up(conn_pid)
    stream_ref = :gun.ws_upgrade(conn_pid, "#{@prefix}/ws")

    receive do
      {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} -> :ok
    after
      1000 -> flunk("WebSocket upgrade timeout")
    end

    {conn_pid, stream_ref}
  end

  defp send_json(conn_pid, stream_ref, msg) do
    :gun.ws_send(conn_pid, stream_ref, {:text, Jason.encode!(msg)})
  end

  defp recv_json(conn_pid, stream_ref, timeout \\ 1000) do
    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, msg}} ->
        Jason.decode!(msg)
    after
      timeout -> flunk("Response timeout")
    end
  end

  test "ping/pong" do
    {conn, ref} = connect_ws()
    send_json(conn, ref, %{"type" => "ping"})
    assert recv_json(conn, ref) == %{"type" => "pong"}
    :gun.close(conn)
  end

  test "join queue returns queued" do
    {conn, ref} = connect_ws()
    send_json(conn, ref, %{"type" => "join_queue"})
    assert recv_json(conn, ref) == %{"type" => "queued"}
    :gun.close(conn)
  end

  test "two players get matched" do
    {conn1, ref1} = connect_ws()
    {conn2, ref2} = connect_ws()

    send_json(conn1, ref1, %{"type" => "join_queue"})
    assert %{"type" => "queued"} = recv_json(conn1, ref1)

    send_json(conn2, ref2, %{"type" => "join_queue"})
    msg2 = recv_json(conn2, ref2)
    assert %{"type" => "matched", "player_number" => 2, "room_id" => room_id} = msg2

    # Player 1 also gets matched notification
    msg1 = recv_json(conn1, ref1)
    assert %{"type" => "matched", "player_number" => 1, "room_id" => ^room_id} = msg1

    :gun.close(conn1)
    :gun.close(conn2)
  end

  test "full game flow: match, prompts, builds" do
    {conn1, ref1} = connect_ws()
    {conn2, ref2} = connect_ws()

    # Match
    send_json(conn1, ref1, %{"type" => "join_queue"})
    recv_json(conn1, ref1)
    send_json(conn2, ref2, %{"type" => "join_queue"})
    recv_json(conn2, ref2)
    recv_json(conn1, ref1)

    # Submit prompts
    send_json(conn1, ref1, %{"type" => "submit_prompt", "prompt" => "No prisoners!"})
    # Both get prompt_received
    p1_ack = recv_json(conn1, ref1)
    assert %{"type" => "prompt_received", "player_number" => 1} = p1_ack
    p2_sees_p1 = recv_json(conn2, ref2)
    assert %{"type" => "prompt_received", "player_number" => 1} = p2_sees_p1

    send_json(conn2, ref2, %{"type" => "submit_prompt", "prompt" => "Happy days!"})

    # Collect all messages until builds_ready (order may vary)
    messages = collect_messages(conn1, ref1, 24, 5000)

    types = Enum.map(messages, & &1["type"])
    assert "prompt_received" in types
    assert "both_prompts_in" in types
    assert "analyzing" in types
    assert "generating_assets" in types
    assert "builds_ready" in types
    assert "assets_progress" in types
    assert "asset_ready" in types
    assert "playing" in types

    builds_msg = Enum.find(messages, & &1["type"] == "builds_ready")
    assert is_map(builds_msg["your_build"])
    assert is_map(builds_msg["opponent_build"])
    assert builds_msg["your_build"]["bomb_damage"] in 1..10
    assert builds_msg["your_build"]["tower_hp"] in 100..500
    assert builds_msg["your_build"]["shield_hp"] in 1..3

    :gun.close(conn1)
    :gun.close(conn2)
  end

  test "relay: player_update is forwarded to opponent" do
    {conn1, ref1, conn2, ref2} = match_two_players()
    advance_to_playing(conn1, ref1, conn2, ref2)

    # Player 1 sends player_update, player 2 should receive it
    send_json(conn1, ref1, %{"type" => "player_update", "position" => %{"x" => 1, "y" => 2, "z" => 3}, "rotation" => %{"x" => 0, "y" => 0, "z" => 0}})

    msg = recv_json(conn2, ref2, 2000)
    assert %{"type" => "player_update", "player_number" => 1, "position" => %{"x" => 1, "y" => 2, "z" => 3}} = msg

    :gun.close(conn1)
    :gun.close(conn2)
  end

  test "tower_hp: reports damage and triggers game_over at 0" do
    {conn1, ref1, conn2, ref2} = match_two_players()
    advance_to_playing(conn1, ref1, conn2, ref2)

    # Player 1 reports opponent tower HP = 50
    send_json(conn1, ref1, %{"type" => "tower_hp", "hp" => 50})
    msg1 = recv_json(conn1, ref1, 2000)
    assert %{"type" => "tower_hp", "player_number" => 1, "target_player_number" => 2, "hp" => 50} = msg1
    msg2 = recv_json(conn2, ref2, 2000)
    assert %{"type" => "tower_hp", "player_number" => 1, "target_player_number" => 2, "hp" => 50} = msg2

    # Player 1 reports opponent tower HP = 0 -> game_over
    send_json(conn1, ref1, %{"type" => "tower_hp", "hp" => 0})
    messages = collect_messages(conn1, ref1, 2, 2000)
    types = Enum.map(messages, & &1["type"])
    assert "tower_hp" in types
    assert "game_over" in types
    game_over = Enum.find(messages, & &1["type"] == "game_over")
    assert game_over["winner_number"] == 1
    assert game_over["reason"] == "tower_destroyed"

    :gun.close(conn1)
    :gun.close(conn2)
  end

  defp match_two_players do
    {conn1, ref1} = connect_ws()
    {conn2, ref2} = connect_ws()

    send_json(conn1, ref1, %{"type" => "join_queue"})
    recv_json(conn1, ref1)
    send_json(conn2, ref2, %{"type" => "join_queue"})
    recv_json(conn2, ref2)
    recv_json(conn1, ref1)

    {conn1, ref1, conn2, ref2}
  end

  defp advance_to_playing(conn1, ref1, conn2, ref2) do
    send_json(conn1, ref1, %{"type" => "submit_prompt", "prompt" => "Test 1"})
    # Drain prompt_received from both
    recv_json(conn1, ref1)
    recv_json(conn2, ref2)

    send_json(conn2, ref2, %{"type" => "submit_prompt", "prompt" => "Test 2"})

    # Drain all messages until builds_ready for both players
    _msgs1 = collect_until(conn1, ref1, "playing", 5000)
    _msgs2 = collect_until(conn2, ref2, "playing", 5000)
  end

  defp collect_until(conn_pid, stream_ref, target_type, timeout) do
    collect_until(conn_pid, stream_ref, target_type, timeout, [])
  end

  defp collect_until(conn_pid, stream_ref, target_type, timeout, acc) do
    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, msg}} ->
        decoded = Jason.decode!(msg)
        acc = [decoded | acc]
        if decoded["type"] == target_type do
          Enum.reverse(acc)
        else
          collect_until(conn_pid, stream_ref, target_type, timeout, acc)
        end
    after
      timeout -> Enum.reverse(acc)
    end
  end

  defp collect_messages(conn_pid, stream_ref, count, timeout) do
    collect_messages(conn_pid, stream_ref, count, timeout, [])
  end

  defp collect_messages(_conn_pid, _stream_ref, 0, _timeout, acc), do: Enum.reverse(acc)

  defp collect_messages(conn_pid, stream_ref, count, timeout, acc) do
    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, msg}} ->
        collect_messages(conn_pid, stream_ref, count - 1, timeout, [Jason.decode!(msg) | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
