defmodule Kv.NodesPoller do
  use GenServer

  @get_nodes_poll_interval_secs :timer.seconds(5)

  # Poll every 5 second for 1 hour to see if other nodes have joined.
  @get_nodes_count_timeout div(:timer.hours(1), @get_nodes_poll_interval_secs)

  ## Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_routing_table, do: GenServer.call(__MODULE__, :get_routing_table)

  ## GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state, {:continue, nil}}
  end

  @impl true
  def handle_call(:get_routing_table, _from, state) do
    {:reply, state.routing_table, state}
  end

  def handle_call(:get, _from, state) do
    {:reply, nil, state}
  end

  @impl true
  def handle_continue(_tag, _state) do
    routing_table =
      if Application.get_env(:kv, :fetch_nodes) do
        routing_table = get_nodes(0)

        Application.put_env(:kv, :routing_table, routing_table)

        routing_table
      else
        []
      end

    {:noreply, %{routing_table: routing_table}}
  end

  defp get_nodes(@get_nodes_count_timeout), do: split_nodes([])

  defp get_nodes(retries) do
    case Node.list() do
      [] ->
        Process.sleep(@get_nodes_poll_interval_secs)

        get_nodes(retries + 1)

      other_nodes ->
        split_nodes(other_nodes)
    end
  end

  defp split_nodes(other_nodes) do
    all_nodes =
      [node() | other_nodes]
      |> Enum.sort()

    length_nodes = length(all_nodes)
    count = div(26, length_nodes)

    ?a..?z
    |> Enum.chunk_every(count)
    |> Enum.zip(all_nodes)
  end
end
