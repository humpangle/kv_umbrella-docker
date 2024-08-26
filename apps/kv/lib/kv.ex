defmodule Kv do
  use Agent

  require Logger

  def start_link(_) do
    Agent.start_link(fn -> %{} end)
  end

  def put(bucket_name, item, value),
    do: Agent.update(bucket_name, &Map.put(&1, item, value))

  def get(bucket_name, item),
    do: Agent.get(bucket_name, &Map.get(&1, item))

  def del(bucket_name, item),
    do: Agent.update(bucket_name, &Map.delete(&1, item))

  defdelegate done(bucket_name), to: Agent, as: :stop
end

defmodule Kv.Reg do
  use GenServer

  ## Client API

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, opts)
  end

  def create(reg, bucket_name), do: GenServer.call(reg, {:create, bucket_name})

  def lookup(reg, bucket_name) do
    case :ets.lookup(reg, bucket_name) do
      [{_, pid}] ->
        {:ok, pid}

      _ ->
        {:error, :unknown}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(reg) do
    _table_ref =
      :ets.new(reg, [
        :set,
        :protected,
        :named_table,
        read_concurrency: true,
        write_concurrency: :auto,
        keypos: 1
      ])

    refs = %{}
    state = {reg, refs}
    {:ok, state}
  end

  @impl true
  def handle_call({:create, bucket_name}, _from, {reg, _} = state) do
    {state, pid} =
      case lookup(reg, bucket_name) do
        {:error, _} ->
          do_create(state, bucket_name)

        {:ok, pid} ->
          {state, pid}
      end

    {:reply, {:ok, pid}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, {reg, refs} = state) do
    state =
      case Map.pop(refs, ref) do
        {nil, _} ->
          state

        {bucket_name, refs} ->
          :ets.delete(reg, bucket_name)
          state = {reg, refs}

          case reason do
            :normal ->
              state

            _ ->
              {state, _} = do_create(state, bucket_name)
              state
          end
      end

    {:noreply, state}
  end

  defp do_create({reg, refs} = _state, bucket_name) do
    {:ok, pid} = DynamicSupervisor.start_child(Kv.DynamicSupervisor, Kv)
    refs = Map.put(refs, Process.monitor(pid), bucket_name)
    :ets.insert(reg, {bucket_name, pid})
    state = {reg, refs}
    {state, pid}
  end
end

defmodule Kv.Cmd do
  require Logger

  alias Kv.Reg

  @doc ~S"""
  What does function do?.

  ## Examples

  Test with comment:

        iex> Kv.Cmd.parse("CREATE doc_bucket_name\r\n")
        {:ok, {:create, "doc_bucket_name"}}

        iex> Kv.Cmd.parse("PUT doc_bucket_name item value\r\n")
        {:ok, {:put, "doc_bucket_name", "item", "value"}}

        iex> Kv.Cmd.parse("GET doc_bucket_name item\r\n")
        {:ok, {:get, "doc_bucket_name", "item"}}

        iex> Kv.Cmd.parse("DEL doc_bucket_name item\r\n")
        {:ok, {:del, "doc_bucket_name", "item"}}

        iex> Kv.Cmd.parse("\r\n")
        {:ok, :newline}

  Test with comment:

        iex> Kv.Cmd.parse("PUT doc_bucket_name item\r\n")
        {:error, :unknown}

  """

  def parse(line) do
    parsed =
      case String.split(line) do
        ["CREATE", bucket_name] ->
          {:ok, {:create, bucket_name}}

        ["PUT", bucket_name, item, value] ->
          {:ok, {:put, bucket_name, item, value}}

        ["GET", bucket_name, item] ->
          {:ok, {:get, bucket_name, item}}

        ["DEL", bucket_name, item] ->
          {:ok, {:del, bucket_name, item}}

        [] ->
          {:ok, :newline}

        _ ->
          {:error, :unknown}
      end

    Logger.info(fn ->
      [
        "Message to parse: ",
        line,
        "Parsed result: ",
        inspect(parsed)
      ]
    end)

    parsed
  end

  def run(cmd)

  def run(:newline), do: {:ok, "\r\n"}

  def run({:create, bucket_name}) do
    route(bucket_name, Reg, :create, [Reg, bucket_name])
    {:ok, "ok\r\n"}
  end

  def run({:get, bucket_name, item}) do
    lookup(bucket_name, fn pid ->
      value = Kv.get(pid, item)
      {:ok, "#{value}\r\nok\r\n"}
    end)
  end

  def run({:del, bucket_name, item}) do
    lookup(bucket_name, fn pid ->
      Kv.del(pid, item)
      {:ok, "ok\r\n"}
    end)
  end

  def run({:put, bucket_name, item, value}) do
    lookup(bucket_name, fn pid ->
      Kv.put(pid, item, value)
      {:ok, "ok\r\n"}
    end)
  end

  defp lookup(bucket_name, cb) do
    with {:ok, pid} <- route(bucket_name, Reg, :lookup, [Reg, bucket_name]) do
      cb.(pid)
    end
  end

  def route(bucket_name, mod, fun, args, referrer_node \\ nil) do
    table = Application.fetch_env!(:kv, :routing_table)

    first_char_of_bucket =
      String.first(bucket_name)
      |> String.to_charlist()
      |> hd()

    {_, node_that_corresponds_to_bucket} =
      Enum.find(table, fn {list, _} -> first_char_of_bucket in list end) ||
        raise "No server is available to serve bucket named: #{inspect(bucket_name)}.
                 Available servers: #{inspect(table)}\n\n"

    this_node = node()

    if node_that_corresponds_to_bucket == this_node do
      Logger.info(fn ->
        [
          "Executing on this node: ",
          inspect(this_node),
          "",
          if(
            referrer_node,
            do: ["\nReferrer node: ", inspect(referrer_node)],
            else: []
          )
        ]
      end)

      apply(mod, fun, args)
    else
      Logger.info(fn ->
        ["Will execute on other node: ", inspect(node_that_corresponds_to_bucket), ""]
      end)

      {Kv.RouterTaskSupervisor, node_that_corresponds_to_bucket}
      |> Task.Supervisor.async(
        __MODULE__,
        :route,
        [bucket_name, mod, fun, args, this_node]
      )
      |> Task.await()
    end
  end
end
