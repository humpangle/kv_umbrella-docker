defmodule KvTest do
  use ExUnit.Case

  alias Kv.{Cmd, Reg}

  doctest Cmd

  @moduletag capture_log: true

  @range_a ?a..?m
  @range_b ?n..?z

  setup_all do
    current = Application.get_env(:kv, :routing_table)

    nodes =
      if a = System.get_env("OTHER_NODE") do
        a = a |> String.to_atom()

        Node.connect(a)
        # Process.sleep(1000)

        :global.sync()

        b = node()

        routing_table = [
          {@range_a, a},
          {@range_b, b}
        ]

        # Why don't we hardcode the routing table in config/test.exs? Because
        # the test node name is dynamic. But why does the test node name need
        # to be dynamic? Why not use a static node name (since test node was
        # started with --sname)? Because dev node was started with --name and
        # the host part of the name is dynamic (it is the docker compose
        # service name). But the test service name is known simply as `t`, sure
        # we can hardcode that? We can do that, but what if we want to change
        # the docker-compose service name or we wish to use another networking
        # infrastructure such as kubernetes? Then it means any time we change
        # our networking infrastructure, we need to touch our application code.

        {:kv_ts, a}
        |> Task.Supervisor.async(
          Application,
          :put_env,
          [:kv, :routing_table, routing_table]
        )
        |> Task.await()

        Application.put_env(:kv, :routing_table, routing_table)

        [a: a, b: b]
      else
        []
      end

    on_exit(fn ->
      Application.put_env(:kv, :routing_table, current)
    end)

    nodes
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
