defmodule KvS do
  require Logger

  import Kv.Cmd

  @unknown_error "Unknown error\r\n"

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

    Logger.info(fn ->
      [
        "Obtained a TCP server socket ",
        inspect(s)
      ]
    end)

    loop(s)
  end

  defp loop(s) do
    {:ok, cs} = :gen_tcp.accept(s)
    {:ok, pid} = Task.Supervisor.start_child(KvS.TaskSupervisor, fn -> accept(cs) end)
    :ok = :gen_tcp.controlling_process(cs, pid)

    Logger.info(fn ->
      [
        "TCP server socket ",
        inspect(s),
        " received client connection socket ",
        inspect(cs)
      ]
    end)

    loop(s)
  end

  defp accept(cs) do
    client_message = :gen_tcp.recv(cs, 0)

    Logger.info(fn ->
      [
        "Client socket ",
        inspect(cs),
        " sent message:",
        inspect(client_message)
      ]
    end)

    msg =
      with {:ok, l} <- client_message,
           {:ok, cmd} <- parse(l),
           do: run(cmd)

    write(cs, msg)

    accept(cs)
  end

  defp write(s, {:ok, t}), do: :gen_tcp.send(s, t)

  defp write(s, {:error, :unknown}), do: :gen_tcp.send(s, @unknown_error)

  defp write(_, {:error, :closed}) do
    Logger.info("Client closed connection - goodbye!")
    exit(:normal)
  end

  defp write(_s, {:error, error}) do
    error = inspect(error)
    Logger.info(["Unexpected error: ", error])
    exit(error)
  end
end
