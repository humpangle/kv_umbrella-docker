defmodule KvS do
  require Logger

  import Kv.Cmd

  @unknown_error "Unknown error\r\n"

  def start(port) do
    {:ok, listen_socket} =
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
        "Obtained a TCP listen socket ",
        inspect(listen_socket)
      ]
    end)

    loop(listen_socket)
  end

  defp loop(listen_socket) do
    {:ok, acceptor_socket} = :gen_tcp.accept(listen_socket)
    {:ok, pid} = Task.Supervisor.start_child(KvS.TaskSupervisor, fn -> accept(acceptor_socket) end)
    :ok = :gen_tcp.controlling_process(acceptor_socket, pid)

    Logger.info(fn ->
      [
        "TCP listen socket ",
        inspect(listen_socket),
        " receives client connection socket ",
        inspect(acceptor_socket)
      ]
    end)

    loop(listen_socket)
  end

  defp accept(acceptor_socket) do
    client_message = :gen_tcp.recv(acceptor_socket, 0)

    Logger.info(fn ->
      [
        "Acceptor socket ",
        inspect(acceptor_socket),
        " receives client message: ",
        inspect(client_message)
      ]
    end)

    msg =
      with {:ok, l} <- client_message,
           {:ok, cmd} <- parse(l),
           do: run(cmd)

    write(acceptor_socket, msg)

    accept(acceptor_socket)
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
