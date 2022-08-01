import Config

libcluster_debug =
  case System.get_env("DEBUG_LIB_CLUSTER") do
    nil ->
      false

    "" ->
      false

    _ ->
      true
  end

secret = if config_env() == :prod, do: System.fetch_env!("RELEASE_COOKIE"), else: "abc"

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
