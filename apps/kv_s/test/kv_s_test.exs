defmodule KvSTest do
  use ExUnit.Case

  @moduletag capture_log: true

  setup do
    port = KvS.Application.get_port_if_should_start_server()

    {:ok, socket} =
      :gen_tcp.connect(
        ~c"127.0.0.1",
        port,
        [
          :binary,
          packet: :line,
          active: false,
          reuseaddr: true
        ]
      )

    on_exit(fn -> :gen_tcp.close(socket) end)

    %{socket: socket}
  end

  test "server", %{socket: socket} do
    assert "\r\n" == p(socket, "\r\n")
    assert "ok\r\n" = p(socket, "CREATE n\r\n")
    assert "ok\r\n" == p(socket, "PUT n i 1\r\n")
    assert "1\r\n" == p(socket, "GET n i\r\n")
    assert "ok\r\n" == p(socket, "")
    assert "ok\r\n" == p(socket, "DEL n i\r\n")
    assert "Unknown error\r\n" == p(socket, "DEL n i t\r\n")
  end

  defp p(socket, text) do
    :ok = :gen_tcp.send(socket, text)
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end
end
