defmodule Kv.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: :kv_ts},
      {DynamicSupervisor, name: :kv_ds, strategy: :one_for_one},
      Kv.Reg
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kv.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
