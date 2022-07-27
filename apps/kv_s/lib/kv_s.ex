defmodule KvS do
  require Logger

  import Kv.Cmd

  def start(port) do
    {:ok, s} =
      :gen_tcp.listen(
        port,
        [
          :binary,
          packet: :line,
          active: false,
          reuseaddr: true
        ]
      )

    loop(s)
  end

  defp loop(s) do
    {:ok, cs} = :gen_tcp.accept(s)
    {:ok, pid} = Task.Supervisor.start_child(:kv_s_ts, fn -> accept(cs) end)
    :ok = :gen_tcp.controlling_process(cs, pid)

    loop(s)
  end

  defp accept(s) do
    msg =
      with {:ok, l} <- :gen_tcp.recv(s, 0),
           {:ok, cmd} <- parse(l),
           do: run(cmd)

    write(s, msg)

    accept(s)
  end

  defp write(s, {:ok, t}), do: :gen_tcp.send(s, t)

  defp write(s, {:error, :unknown}), do: :gen_tcp.send(s, "unknown\r\n")

  defp write(_, {:error, :closed}) do
    Logger.info("Client closed conn - goodbye!")
    exit(:normal)
  end

  defp write(_s, {:error, error}) do
    error = inspect(error)
    Logger.info(["Unexpected error: ", error])
    exit(error)
  end
end
