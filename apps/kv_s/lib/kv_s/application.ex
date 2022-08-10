defmodule KvS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Task.Supervisor, name: :kv_s_ts}
      ] ++
        start_server()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KvS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_server() do
    if port = get_port_if_should_start_server() do
      [{Task, fn -> KvS.start(port) end}]
    else
      []
    end
  end

  def get_port_if_should_start_server do
    case System.get_env("NO_START_SERVER") do
      val when is_nil(val) or val == "" ->
        System.fetch_env!("PORT")
        |> String.to_integer()

      _ ->
        nil
    end
  end
end
