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
    if Application.get_env(:kv, :create_cluster) do
      topologies = Application.get_env(:libcluster, :topologies)

      [
        {Cluster.Supervisor, [topologies, [name: Kv.ClusterSupervisor]]},
        Kv.NodesPoller
      ]
    else
      []
    end
  end
end
