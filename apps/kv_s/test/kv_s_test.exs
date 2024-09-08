defmodule KvSTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  setup_all do
    Application.put_env(:kv, :routing_table, [{?a..?z, node()}])
    :ok
  end

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

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    %{socket: socket}
  end

  test "server", %{socket: socket} do
    bucket_name = "shopping"
    item = "milk"

    assert "\r\n" == send_and_receive(socket, "\r\n")
    assert "ok\r\n" = send_and_receive(socket, "CREATE #{bucket_name}\r\n")
    assert "ok\r\n" == send_and_receive(socket, "PUT #{bucket_name} #{item} 1\r\n")
    assert "1\r\n" == send_and_receive(socket, "GET #{bucket_name} #{item}\r\n")
    assert "ok\r\n" == send_and_receive(socket, "")
    assert "ok\r\n" == send_and_receive(socket, "DEL #{bucket_name} #{item}\r\n")
    assert "Unknown error\r\n" == send_and_receive(socket, "DEL #{bucket_name} #{item} t\r\n")
  end

  defp send_and_receive(socket, text) do
    :ok = :gen_tcp.send(socket, text)
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data
  end
end
