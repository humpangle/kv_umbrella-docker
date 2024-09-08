defmodule Kv.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      maybe_setup_libcluster() ++
        [
          {Task.Supervisor, name: Kv.RouterTaskSupervisor},
          {DynamicSupervisor, name: Kv.DynamicSupervisor, strategy: :one_for_one},
          Kv.Reg
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kv.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_setup_libcluster do
    # We don't want to set up libcluster in test - we will join nodes manually, so here we control how nodes are
    # joined.
    if System.get_env("AUTO_JOIN_NODES") == "true" do
      libcluster_config = [
        kv_gossip: [
          strategy: Elixir.Cluster.Strategy.Gossip,
          config: [
            port: 45892,
            if_addr: "0.0.0.0",
            multicast_if: "192.168.2.1",
            multicast_addr: "233.252.1.32",
            multicast_ttl: 1,
            secret: System.fetch_env!("RELEASE_COOKIE")
          ]
        ]
      ]

      Application.put_all_env(libcluster: libcluster_config)

      [
        {Cluster.Supervisor, [libcluster_config, [name: Kv.ClusterSupervisor]]},
        Kv.NodesPoller
      ]
    else
      []
    end
  end
end
