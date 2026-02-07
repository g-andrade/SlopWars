import Config

if config_env() == :prod do
  config :backend,
    mistral_api_key:
      System.get_env("MISTRAL_API_KEY") ||
        raise("Missing required environment variable MISTRAL_API_KEY"),
    hyper3d_api_key:
      System.get_env("HYPER3D_API_KEY") ||
        raise("Missing required environment variable HYPER3D_API_KEY")
end

if port = System.get_env("PORT") do
  config :backend, port: String.to_integer(port)
end
