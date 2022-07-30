import Config

{routing_table, secret} =
  if config_env() == :prod do
    routing_table =
      "ROUTING_TABLE"
      |> System.fetch_env!()
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    secret = System.fetch_env!("RELEASE_COOKIE")

    {routing_table, secret}
  else
    routing_table = [{?a..?z, node()}]

    secret = "abc"

    {routing_table, secret}
  end

config :kv,
  routing_table: routing_table

libcluster_debug =
  case System.get_env("DEBUG_LIB_CLUSTER") do
    nil ->
      false

    "" ->
      false

    _ ->
      true
  end

config :libcluster,
  debug: libcluster_debug,
  topologies: [
    kv_gossip: [
      strategy: Elixir.Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_if: "192.168.1.1",
        multicast_addr: "233.252.1.32",
        multicast_ttl: 1,
        secret: secret
      ]
    ]
  ]
