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
          Kv.Reg,
          Kv.NodesPoller
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kv.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_setup_libcluster do
    # We don't want to set up libcluster in test
    if System.get_env("NO_AUTO_NODE_JOIN", "") == "" do
      topologies = Application.get_env(:libcluster, :topologies)

      [
        {Cluster.Supervisor, [topologies, [name: Kv.ClusterSupervisor]]}
      ]
    else
      []
    end
  end
end
