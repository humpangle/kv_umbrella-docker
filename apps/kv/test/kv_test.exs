defmodule KvTest do
  use ExUnit.Case

  alias Kv.{Cmd, Reg}

  doctest Cmd

  @moduletag capture_log: true

  setup_all do
    current = Application.get_env(:kv, :routing_table)

    [a, b] =
      [1, 2]
      |> Enum.map(&String.to_atom(System.get_env("NODE#{&1}", "nil")))

    Application.put_env(:kv, :routing_table, [
      {?a..?m, a},
      {?n..?z, b}
    ])

    on_exit(fn ->
      Application.put_env(:kv, :routing_table, current)
    end)

    [a: a, b: b]
  end

  @tag :distributed
  test "route/4", %{a: a, b: b} do
    assert a ==
             Cmd.route(
               "#{<<Enum.random(97..109)::8>>}1",
               Kernel,
               :node,
               []
             )

    assert b ==
             Cmd.route(
               "#{<<Enum.random(110..122)::8>>}1",
               Kernel,
               :node,
               []
             )

    assert_raise(
      RuntimeError,
      ~r/11/,
      fn -> Cmd.route("11", Kernel, :node, []) end
    )
  end

  describe "kv" do
    setup context do
      start_supervised!({Reg, name: context.test}, restart: :temporary)
      :ok
    end

    test "kv ops", %{test: reg} do
      n = "shopping"
      i = "milk"
      assert {:error, _} = Reg.lookup(reg, n)
      assert {:ok, pid1} = Reg.create(reg, n)
      assert {:ok, ^pid1} = Reg.lookup(reg, n)
      assert :ok == Kv.done(pid1)
      catch_exit(Kv.get(pid1, i))
      Process.sleep(1)
      assert {:error, _} = Reg.lookup(reg, n)

      {:ok, pid2} = Reg.create(reg, n)
      assert nil == Kv.get(pid2, i)
      Process.exit(pid2, :kill)
      catch_exit(Kv.get(pid2, i))
      Process.sleep(1)

      assert {:ok, pid3} = Reg.lookup(reg, n)
      refute pid3 == pid2
    end
  end
end
