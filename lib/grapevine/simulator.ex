defmodule Grapevine.Simulator do
  @moduledoc """
  Simulates various types of Gossip topologies and algorithms
  """
  use GenServer

  require Integer

  alias Grapevine.GossipNode
  alias Grapevine.Util.Helpers

  # require Logger

  defstruct topology: nil,
            algorithm: nil,
            num_nodes: nil,
            pool: [],
            pool_status: nil,
            converged: false,
            start_time: nil,
            end_time: nil

  ## Client API
  def start_link({topology, algorithm}) do
    GenServer.start_link(__MODULE__, {topology, algorithm}, name: __MODULE__)
  end

  def sim_time do
    GenServer.call(__MODULE__, :sim_time)
  end

  def converged? do
    # Massive timeout of 1000s for simulation only!
    GenServer.call(__MODULE__, :did_converge, 1_000_000)
  end

  def populate(num_nodes) do
    GenServer.call(__MODULE__, {:populate, num_nodes}, 1_000_000)
  end

  def inject_rumour(start_idx, rumour \\ :r) do
    GenServer.cast(__MODULE__, {:inject, start_idx, rumour})
  end

  def inject_psum(start_idx, %{s: s, w: w}) do
    GenServer.cast(__MODULE__, {:start_psum, start_idx, %{s: s, w: w}})
  end

  def get_node_count do
    GenServer.call(__MODULE__, :count_nodes)
  end

  def get_ratio do
    GenServer.call(__MODULE__, :get_ratio)
  end

  # Given a list of GossipNodes, connects them to form a fully connected graph
  # Complexity: Quadratic in number of nodes
  defp mesh_init(:full, node_list) do
    for nd <- node_list do
      GossipNode.set_peers(nd, List.delete(node_list, nd))
    end
  end

  defp mesh_init(:line, node_list) do
    for [n1, n2] <- Enum.chunk_every(node_list, 2, 1) do
      GossipNode.add_peers(n1, [n2])
      GossipNode.add_peers(n2, [n1])
    end
  end

  defp mesh_init(:planar, node_list) do
    # n x n mesh
    n = node_list |> length |> :math.pow(0.5) |> round
    # Connect horizontal line mesh
    for row <- Helpers.enumerate_rows(node_list, n) do
      mesh_init(:line, row)
    end

    # Connect vertical line mesh
    for col <- Helpers.enumerate_cols(node_list, n) do
      mesh_init(:line, col)
    end
  end

  defp mesh_init(:imp2D, node_list) do
    # Intialize planar connections
    mesh_init(:planar, node_list)

    for nd <- node_list do
      peers = GossipNode.get_peers(nd)
      # Add a single random peer
      GossipNode.add_peers(nd, [Enum.random(node_list -- peers)])
    end
  end

  ## Server API
  def init({topology, algorithm}) do
    Process.flag(:trap_exit, true)
    {:ok, %{%__MODULE__{} | topology: topology, algorithm: algorithm}}
  end

  def handle_call(:sim_time, _from, state) do
    {:reply, :timer.now_diff(state.end_time, state.start_time) / 1_000, state}
  end

  def handle_call(:count_nodes, _from, state) do
    {:reply, state.num_nodes, state}
  end

  def handle_call({:populate, num_nodes}, _from, state) do
    # Round up to nearest square
    num_nodes = if state.topology in [:planar, :imp2D] do
      num_nodes |> :math.pow(0.5) |> :math.ceil |> :math.pow(2) |> round
    else
      num_nodes
    end

    if is_pid(Process.whereis(:printer)) do
      send :printer, {:print, "<plotty: draw, #{num_nodes}>"}
    end

    pool = for idx <- 1..num_nodes, do: GossipNode.start_link(idx - 1, state.algorithm)

    # Each process in the pool starts with status :active
    pool_status = List.duplicate(:active, num_nodes)

    # Initialize a specific topology
    mesh_init(state.topology, pool)

    # Return process pool as a response
    {:reply, pool, %{state | num_nodes: num_nodes, pool: pool, pool_status: pool_status}}
  end

  def handle_call(:did_converge, _from, state) do
    {:reply, state.converged, state}
  end

  def handle_call(:get_ratio, _from, state) do
    ratios = state.pool_status
    |> Enum.with_index
    |> Enum.map(fn {e, idx} -> if e == :inactive, do: idx end)
    |> Enum.filter(fn idx -> !is_nil(idx) end)
    |> Enum.map(fn idx -> :lists.nth(idx + 1, state.pool) end)
    |> Enum.map(fn pid -> GossipNode.get_ratio(pid) end)

    mean = Enum.sum(ratios) / length(ratios)
    # median = if Integer.is_even(length(ratios)) do
    #   0.5 * (:lists.nth(div(length(ratios), 2), Enum.sort(ratios)) + :lists.nth(div(length(ratios), 2) + 1, Enum.sort(ratios)))
    # else
    #   :lists.nth(div(length(ratios) + 1, 2) + 1, Enum.sort(ratios))
    # end
    # variance = (ratios |> Enum.map(&:math.pow((&1 - mean), 2)) |> Enum.sum) / length(ratios)
    # min = Enum.min(ratios)
    # max = Enum.max(ratios)
    # ratio = ratios |> Enum.filter(fn r -> abs(r - mean) < variance end)
    # ratio = Enum.sum(ratio) / length(ratio)
    {:reply, mean, state}
  end

  def handle_cast({:inject, start_idx, rumour}, state) do
    chosen_one = :lists.nth(start_idx + 1, state.pool)
    GossipNode.relay(chosen_one, :gossip, rumour)
    {:noreply, %{state | start_time: :os.timestamp()}}
  end

  def handle_cast({:start_psum, start_idx, %{s: s, w: w}}, state) do
    chosen_one = :lists.nth(start_idx + 1, state.pool)
    GossipNode.relay(chosen_one, :psum, %{s: s, w: w})
    {:noreply, %{state | start_time: :os.timestamp()}}
  end

  def handle_info({:status, node_idx, status}, state) do
    counts = state.pool_status
    |> Enum.reduce(%{}, fn x, acc -> Map.update(acc, x, 1, &(&1 + 1)) end)

    {did_converge, end_time} = unless state.converged do
      send :printer, {:print, "<plotty: #{status}, #{node_idx + 1}>"}
      frac_active =   (counts[:active] || 0) / state.num_nodes
      frac_inactive = (counts[:inactive] || 0) / state.num_nodes
      # frac_infected = (counts[:infected] || 0) / state.num_nodes

      converge = case state.algorithm do
        :gossip -> frac_inactive > 0.5 || frac_active < 0.01
        # First node that converges
        :psum   -> frac_inactive > 0.5 #status == :inactive
      end
      # IO.write "#{inspect {frac_active, frac_infected, frac_inactive}}\n"
      et = if converge, do: :os.timestamp(), else: nil

      {converge, et}
    else
      {state.converged, state.end_time}
    end
    # IO.write(inspect {converge, et, counts, state.algorithm})
    {:noreply, %{state | converged: did_converge,
                         end_time: end_time,
                         pool_status: List.update_at(state.pool_status, node_idx, fn _ -> status end)}}
  end
end
