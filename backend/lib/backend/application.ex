defmodule Backend.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:backend, :port, 8080)

    dispatch =
      :cowboy_router.compile([
        {:_, [
          {"/ws", Backend.WebsocketHandler, %{}}
        ]}
      ])

    {:ok, _} =
      :cowboy.start_clear(:http, [{:port, port}], %{env: %{dispatch: dispatch}})

    children = []

    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
