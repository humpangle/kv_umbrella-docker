import Config

routing_table =
  if config_env() == :prod do
    "ROUTING_TABLE"
    |> System.fetch_env!()
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  else
    [{?a..?z, node()}]
  end

config :kv,
  routing_table: routing_table
