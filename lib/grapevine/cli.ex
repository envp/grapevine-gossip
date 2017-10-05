defmodule Grapevine.CLI do
  @moduledoc """
  CLI for grapevine app
  """
  alias Grapevine.Simulator
  alias Grapevine.Util.{Benchmark, Helpers}

  require Logger

  def main([num_nodes, topology, algorithm]) do
    {num_nodes, ""} = Integer.parse(num_nodes)

    topology = Helpers.atom_for(:topology, topology)
    algorithm = Helpers.atom_for(:algorithm, algorithm)

    if Enum.any?([topology, algorithm], &is_nil(&1)) do
      exit({:error, "Arguments must be: <numNodes> <topology> <algorithm>"})
    end

    # Set up the named printing process
    Process.register(spawn(fn -> Helpers.print_loop end), :printer)

    Simulator.start_link({topology, algorithm})
    Logger.debug "Populating topology \"#{topology}\" with #{num_nodes} gossiping nodes"
    Simulator.populate(num_nodes)
    time_delta = Benchmark.measure(fn ->
      Simulator.simulate(0)
      Simulator.await
    end
    )
    IO.puts time_delta
  end
  def main(_), do: Logger.error "Arguments must be: <numNodes> <topology> <algorithm>"
end
