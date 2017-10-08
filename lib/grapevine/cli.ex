defmodule Grapevine.CLI do
  @moduledoc """
  CLI for grapevine app
  """
  alias Grapevine.Simulator
  alias Grapevine.Util.Helpers

  require Logger

  def block_till_converged do
    unless Simulator.converged?(), do: block_till_converged()
  end

  def main([num_nodes, topology, algorithm]), do: main([num_nodes, topology, algorithm, "0"])
  def main([num_nodes, topology, algorithm, failure_rate]) do
    {num_nodes, ""} = Integer.parse(num_nodes)
    {failure_rate, ""} = Float.parse(failure_rate)

    topology = Helpers.atom_for(:topology, topology)
    algorithm = Helpers.atom_for(:algorithm, algorithm)

    if Enum.any?([topology, algorithm], &is_nil(&1)) do
      exit({:error, "Arguments must be: <numNodes> <topology> <algorithm>"})
    end

    # Set up the named printing process
    Process.register(spawn(fn -> Helpers.print_loop end), :printer)

    Simulator.start_link({topology, algorithm})
    Logger.info "Populating topology \"#{topology}\" with #{num_nodes} nodes"
    Simulator.populate(num_nodes, failure_rate)

    # Start simulation
    case algorithm do
      :gossip -> Simulator.inject_rumour(0)
      :psum   -> Simulator.inject_psum(0, %{s: 0, w: 0})
      _ -> nil
    end
    block_till_converged()

    # case algorithm do
    #   :gossip -> IO.puts "#{topology},#{algorithm},#{Simulator.get_node_count},#{Simulator.sim_time}"
    #   :psum   -> IO.puts "#{topology},#{algorithm},#{Simulator.get_node_count},#{Simulator.sim_time},#{Simulator.get_ratio}"
    #   _ -> nil
    # end
    IO.puts Simulator.sim_time
  end
  def main(_), do: Logger.error "Arguments must be: <numNodes> <topology> <algorithm>"
end
