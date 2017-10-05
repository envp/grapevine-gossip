defmodule Grapevine.Simulator do
  @moduledoc """
  Simulates various types of Gossip topologies and algorithms
  """
  use GenServer

  alias Grapevine.GossipNode

  # require Logger

  defstruct topology: nil, algorithm: nil, num_nodes: nil, pool: [], pool_status: []

  ## Client API
  def start_link({topology, algorithm}) do
    GenServer.start_link(__MODULE__, {topology, algorithm}, name: __MODULE__)
  end


  def populate(num_nodes) do
    if is_pid(Process.whereis(:printer)) do
      send :printer, {:print, "<plotty: draw, #{num_nodes}>"}
    end
    GenServer.call(__MODULE__, {:populate, num_nodes})
  end

  def simulate(start_idx, rumour \\ :r) do
    GenServer.cast(__MODULE__, {:simulate, start_idx, rumour})
  end

  def await do
    unless converged?() do
      await()
    end
  end

  def converged? do
    GenServer.call(__MODULE__, :converged)
  end

  # Given a list of GossipNodes, connects them to form a fully connected graph
  # Complexity: Quadratic in number of nodes
  defp mesh_init(:full, nodes) do
    for nd <- nodes do
      GossipNode.update_neighbours(nd, List.delete(nodes, nd))
    end
  end

  defp mesh_init(:line, nodes) do
    []
  end

  defp mesh_init(:planar, nodes) do
    []
  end

  defp mesh_init(:imp2D, nodes) do
    []
  end

  ## Server API
  def init({topology, algorithm}) do
    {:ok, %{%__MODULE__{} | topology: topology, algorithm: algorithm}}
  end

  def handle_call({:populate, num_nodes}, _from, state) do

    pool = for idx <- 1..num_nodes, do: elem(GossipNode.start_link(idx - 1, state.algorithm), 1)

    # Each process in the pool starts with status :active
    pool_status = List.duplicate(:active, num_nodes)

    # Initialize a specific topology
    mesh_init(state.topology, pool)

    # Return process pool as a response
    {:reply, pool, %{state | num_nodes: num_nodes, pool: pool, pool_status: pool_status}}
  end

  def handle_call(:converged, _from, state) do
    {:reply, Enum.all?(state.pool_status, fn x -> x in [:infected, :inactive] end), state}
  end

  def handle_cast({:simulate, start_idx, rumour}, state) do
    chosen_one = hd state.pool
    GossipNode.spread(chosen_one, :gossip, rumour)
    {:noreply, state}
  end

  def handle_info({:status, node_idx, status}, state) do
    if is_pid(Process.whereis(:printer)) do
      send :printer, {:print, "<plotty: #{status}, #{node_idx + 1}>"}
    end
    {:noreply, %{state | pool_status: List.update_at(state.pool_status, node_idx, fn _ -> status end)}}
  end
end
