defmodule Grapevine.GossipNode do
  @moduledoc """
  Module representing a single gossiping node
  """
  use GenServer

  require Logger

  defstruct idx: nil, neighbours: {}, algorithm: nil, count: 0, saturation: 10, status: nil

  ## Client API
  def start_link(idx, algorithm) do
    GenServer.start_link(__MODULE__, {idx, algorithm})
  end

  def update_neighbours(pid, neighhours) do
    GenServer.cast(pid, {:update, neighhours})
  end

  def spread(pid, :gossip, rumour) do
    GenServer.cast(pid, {:gossip, rumour})
  end

  ## Server API
  def init({idx, algorithm}) do
    {:ok, %{%__MODULE__{} | idx: idx, algorithm: algorithm, status: :active}}
  end

  def handle_cast({:update, pids}, node) do
    {:noreply, %{node | neighbours: pids}}
  end

  def handle_cast({:gossip, rumour}, node) do
    if node.status not in [:inactive, :dead] do
      chosen_one = Enum.random(node.neighbours)
      __MODULE__.spread(chosen_one, :gossip, rumour)

      if node.count + 1 >= node.saturation do
        send Grapevine.Simulator, {:status, node.idx, :inactive}
        {:noreply, %{node | count: node.count + 1, status: :inactive}}
      else
        if node.status == :active do
          send Grapevine.Simulator, {:status, node.idx, :infected}
        end
        {:noreply, %{node | count: node.count + 1, status: :infected}}
      end
    else
      {:noreply, node}
    end
  end
end
