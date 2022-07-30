defmodule KvSTest do
  use ExUnit.Case

  @moduletag capture_log: true

  setup do
    port = KvS.Application.get_port_if_should_start_server()

    {:ok, s} =
      :gen_tcp.connect(
        '127.0.0.1',
        port,
        [
          :binary,
          packet: :line,
          active: false,
          reuseaddr: true
        ]
      )

    on_exit(fn -> :gen_tcp.close(s) end)

    %{s: s}
  end

  test "server", %{s: s} do
    assert "\r\n" == p(s, "\r\n")
    assert "ok\r\n" == p(s, "CREATE n\r\n")
    assert "ok\r\n" == p(s, "PUT n i 1\r\n")
    assert "1\r\n" == p(s, "GET n i\r\n")
    assert "ok\r\n" == p(s, "")
    assert "ok\r\n" == p(s, "DEL n i\r\n")
    assert "Unknown error\r\n" == p(s, "DEL n i t\r\n")
  end

  defp p(s, t) do
    :ok = :gen_tcp.send(s, t)
    {:ok, d} = :gen_tcp.recv(s, 0)
    d
  end
end
