import Config

routing_table =
  if config_env() == :prod do
    [
      {?a..?m, :"server_storage@ex-p"},
      {?n..?z, :"storage@ex-p"},
    ]
  else
    [{?a..?z, node()}]
  end

config :kv,
  routing_table: routing_table
