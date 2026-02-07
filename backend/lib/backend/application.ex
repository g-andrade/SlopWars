defmodule Backend.Application do
  @moduledoc false

  use Application

  @obfuscating_prefix "/fhampuaqm7vdq5niuzo3okajq4"

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:backend, :port, 8080)

    static_dir = :code.priv_dir(:backend) |> to_string()

    dispatch =
      :cowboy_router.compile([
        {:_, [
          {"#{@obfuscating_prefix}/ws", Backend.WebsocketHandler, %{}},
          {"#{@obfuscating_prefix}/debug", :cowboy_static, {:file, static_dir <> "/static/debug.html"}},
          {"#{@obfuscating_prefix}/models/[...]", :cowboy_static, {:dir, static_dir <> "/static/models"}},
          {"#{@obfuscating_prefix}/images/[...]", :cowboy_static, {:dir, static_dir <> "/static/images"}},
          {"#{@obfuscating_prefix}/placeholders/[...]", :cowboy_static, {:dir, static_dir <> "/static/placeholders"}}
        ]}
      ])

    {:ok, _} =
      :cowboy.start_clear(:http, [{:port, port}], %{env: %{dispatch: dispatch}})

    children = [
      {Registry, keys: :unique, name: Backend.GameRegistry},
      Backend.Matchmaker,
      {DynamicSupervisor, name: Backend.GameRoomSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
