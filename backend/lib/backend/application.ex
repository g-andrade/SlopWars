defmodule Backend.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:backend, :port, 8080)

    static_dir = :code.priv_dir(:backend) |> to_string()

    dispatch =
      :cowboy_router.compile([
        {:_, [
          {"/ws", Backend.WebsocketHandler, %{}},
          {"/debug", :cowboy_static, {:file, static_dir <> "/static/debug.html"}}
        ]}
      ])

    {:ok, _} =
      :cowboy.start_clear(:http, [{:port, port}], %{env: %{dispatch: dispatch}})

    children =
      if Application.get_env(:backend, :mistral_api_key) do
        [Backend.Mistral.AgentServer]
      else
        []
      end

    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
