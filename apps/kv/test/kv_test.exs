defmodule KvTest do
  use ExUnit.Case, async: true

  require Logger
  alias Kv.{Cmd, Reg}

  @moduletag :capture_log

  doctest Cmd

  @range_dev_node ?a..?m
  @range_test_node ?n..?z

  setup_all %{module: module} do
    current = Application.get_env(:kv, :routing_table)

    nodes =
      if dev_node_as_string = System.get_env("DEV_NODE") do
        dev_node = dev_node_as_string |> String.to_atom()

        Node.connect(dev_node)
        :global.sync()
        test_node = node()

        Logger.warning(fn ->
          [
            "Module [",
            to_string(module),
            "] -- This node ",
            to_string(test_node),
            " is connected to dev node: ",
            dev_node_as_string,
            " (a.k.a other node)"
          ]
        end)

        routing_table = [
          {@range_dev_node, dev_node},
          {@range_test_node, test_node}
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

        Task.Supervisor.async(
          {Kv.RouterTaskSupervisor, dev_node},
          Application,
          :put_env,
          [:kv, :routing_table, routing_table]
        )
        |> Task.await()

        Application.put_env(:kv, :routing_table, routing_table)

        [dev_node: dev_node, test_node: test_node]
      else
        []
      end

    on_exit(fn ->
      Application.put_env(:kv, :routing_table, current)
    end)

    nodes
  end

  describe "routing" do
    @describetag :distributed

    @tag capture_log: false
    test "route/4 - succeeds", %{dev_node: dev_node, test_node: test_node} do
      assert dev_node ==
               Cmd.route(
                 "#{<<Enum.random(97..109)::8>>}1",
                 Kernel,
                 :node,
                 []
               )

      assert test_node ==
               Cmd.route(
                 "#{<<Enum.random(110..122)::8>>}1",
                 Kernel,
                 :node,
                 []
               )
    end

    test "route/4 - fails" do
      assert_raise(
        RuntimeError,
        ~r/11/,
        fn -> Cmd.route("11", Kernel, :node, []) end
      )
    end
  end

  describe "kv" do
    setup context do
      start_supervised!({Reg, name: context.test}, restart: :temporary)
      :ok
    end

    test "kv ops", %{test: reg} do
      bucket_name = "shopping"
      item = "milk"

      assert {:error, _} = Reg.lookup(reg, bucket_name)
      assert {:ok, pid1} = Reg.create(reg, bucket_name)
      assert {:ok, ^pid1} = Reg.lookup(reg, bucket_name)
      assert :ok == Kv.done(pid1)
      catch_exit(Kv.get(pid1, item))
      Process.sleep(1)
      assert {:error, _} = Reg.lookup(reg, bucket_name)

      {:ok, pid2} = Reg.create(reg, bucket_name)
      assert nil == Kv.get(pid2, item)
      Process.exit(pid2, :kill)
      catch_exit(Kv.get(pid2, item))
      Process.sleep(1)

      assert {:ok, pid3} = Reg.lookup(reg, bucket_name)
      refute pid3 == pid2
    end
  end
end
