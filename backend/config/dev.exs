import Config

config :backend, dev_mode: true

import_config "#{config_env()}_secrets.exs"
