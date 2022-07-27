defmodule Kv do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end)
  end

  def put(n, i, v), do: Agent.update(n, &Map.put(&1, i, v))
  def get(n, i), do: Agent.get(n, &Map.get(&1, i))
  def del(n, i), do: Agent.update(n, &Map.delete(&1, i))
  defdelegate done(n), to: Agent, as: :stop
end

defmodule Kv.Reg do
  use GenServer

  ## Client API

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, opts)
  end

  def create(reg, n), do: GenServer.call(reg, {:create, n})

  def lookup(reg, n) do
    case :ets.lookup(reg, n) do
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
  def handle_call({:create, n}, _from, {reg, _} = state) do
    {state, pid} =
      case lookup(reg, n) do
        {:error, _} ->
          do_create(state, n)

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

        {n, refs} ->
          :ets.delete(reg, n)
          state = {reg, refs}

          case reason do
            :normal ->
              state

            _ ->
              {state, _} = do_create(state, n)
              state
          end
      end

    {:noreply, state}
  end

  defp do_create({reg, refs} = _state, n) do
    {:ok, pid} = DynamicSupervisor.start_child(:kv_ds, Kv)
    refs = Map.put(refs, Process.monitor(pid), n)
    :ets.insert(reg, {n, pid})
    state = {reg, refs}
    {state, pid}
  end
end

defmodule Kv.Cmd do
  alias Kv.Reg

  @doc ~S"""
  What does function do?.

  ## Examples

  Test with comment:

        iex> Kv.Cmd.parse("CREATE n\r\n")
        {:ok, {:create, "n"}}

        iex> Kv.Cmd.parse("PUT n i v\r\n")
        {:ok, {:put, "n", "i", "v"}}

        iex> Kv.Cmd.parse("GET n i\r\n")
        {:ok, {:get, "n", "i"}}

        iex> Kv.Cmd.parse("DEL n i\r\n")
        {:ok, {:del, "n", "i"}}

        iex> Kv.Cmd.parse("\r\n")
        {:ok, :newline}

  Test with comment:

        iex> Kv.Cmd.parse("PUT n i\r\n")
        {:error, :unknown}

  """

  def parse(line) do
    case String.split(line) do
      ["CREATE", n] ->
        {:ok, {:create, n}}

      ["PUT", n, i, v] ->
        {:ok, {:put, n, i, v}}

      ["GET", n, i] ->
        {:ok, {:get, n, i}}

      ["DEL", n, i] ->
        {:ok, {:del, n, i}}

      [] ->
        {:ok, :newline}

      _ ->
        {:error, :unknown}
    end
  end

  def run(cmd)

  def run(:newline), do: {:ok, "\r\n"}

  def run({:create, n}) do
    route(n, Reg, :create, [Reg, n])
    {:ok, "ok\r\n"}
  end

  def run({:get, n, i}) do
    lookup(n, fn pid ->
      v = Kv.get(pid, i)
      {:ok, "#{v}\r\nok\r\n"}
    end)
  end

  def run({:del, n, i}) do
    lookup(n, fn pid ->
      Kv.del(pid, i)
      {:ok, "ok\r\n"}
    end)
  end

  def run({:put, n, i, v}) do
    lookup(n, fn pid ->
      Kv.put(pid, i, v)
      {:ok, "ok\r\n"}
    end)
  end

  defp lookup(n, cb) do
    with {:ok, pid} <- route(n, Reg, :lookup, [Reg, n]), do: cb.(pid)
  end

  def route(n, mod, fun, args) do
    table = Application.fetch_env!(:kv, :routing_table)

    first = String.first(n) |> String.to_charlist() |> hd()

    {_, selected_node} =
      Enum.find(table, fn {list, _} -> first in list end) ||
        raise "no #{inspect(n)}"

    if selected_node == node() do
      apply(mod, fun, args)
    else
      {:kv_ts, selected_node}
      |> Task.Supervisor.async(__MODULE__, :route, [n, mod, fun, args])
      |> Task.await()
    end
  end
end
