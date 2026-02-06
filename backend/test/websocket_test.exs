defmodule Backend.WebsocketTest do
  use ExUnit.Case

  @port 8080

  test "websocket ping/pong via JSON message" do
    {:ok, conn_pid} = :gun.open(~c"localhost", @port)
    {:ok, :http} = :gun.await_up(conn_pid)

    stream_ref = :gun.ws_upgrade(conn_pid, "/ws")

    receive do
      {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
        :ok
    after
      1000 -> flunk("WebSocket upgrade timeout")
    end

    # Send a JSON ping message
    :gun.ws_send(conn_pid, stream_ref, {:text, Jason.encode!(%{"type" => "ping"})})

    # Expect a JSON pong response
    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, msg}} ->
        assert Jason.decode!(msg) == %{"type" => "pong"}
    after
      1000 -> flunk("Pong response timeout")
    end

    :gun.close(conn_pid)
  end

  test "websocket protocol-level ping/pong" do
    # Note: Gun 2.x handles ping/pong frames at the protocol level.
    # The pong response may not be delivered to the process mailbox.
    # We verify the connection stays alive and can exchange messages after ping.
    {:ok, conn_pid} = :gun.open(~c"localhost", @port)
    {:ok, :http} = :gun.await_up(conn_pid)

    stream_ref = :gun.ws_upgrade(conn_pid, "/ws")

    receive do
      {:gun_upgrade, ^conn_pid, ^stream_ref, ["websocket"], _headers} ->
        :ok
    after
      1000 -> flunk("WebSocket upgrade timeout")
    end

    # Send a protocol-level ping frame
    :gun.ws_send(conn_pid, stream_ref, {:ping, "hello"})

    # Small delay to allow ping/pong exchange
    Process.sleep(50)

    # Verify connection still works by sending a JSON message
    :gun.ws_send(conn_pid, stream_ref, {:text, Jason.encode!(%{"type" => "ping"})})

    receive do
      {:gun_ws, ^conn_pid, ^stream_ref, {:text, msg}} ->
        assert Jason.decode!(msg) == %{"type" => "pong"}
    after
      1000 -> flunk("Message after ping timeout")
    end

    :gun.close(conn_pid)
  end
end
