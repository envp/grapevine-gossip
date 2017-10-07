defmodule Grapevine.GossipNode do
  @moduledoc """
  Module representing a single gossiping node
  """
  use GenServer

  require Logger

  defstruct idx: nil,
            peers: [],
            algorithm: nil,
            count: 0,
            saturation: 10,
            status: :active,
            data: %{s: nil, w: 1},
            psum_saturation: 3

  @resend_delay 100

  ## Client API
  def start_link(idx, algorithm) do
    {:ok, pid} = GenServer.start_link(__MODULE__, {idx, algorithm})
    pid
  end

  def set_peers(pid, peer_pids) do
    GenServer.cast(pid, {:set_peers, peer_pids})
  end

  def add_peers(pid, peer_pids) do
    GenServer.cast(pid, {:add_peers, peer_pids})
  end

  def get_peers(pid) do
    GenServer.call(pid, :get_peers, 1_000_000)
  end

  def get_status(pid) do
    GenServer.call(pid, :get_status, 1_000_000)
  end

  def get_ratio(pid) do
    GenServer.call(pid, :get_ratio, 1_000_000)
  end

  def relay(pid, :gossip, rumour) do
    GenServer.cast(pid, {:gossip, rumour})
    # Keep transmitting until saturated
    Process.send_after(pid, {:resend, :gossip, rumour}, @resend_delay)
  end

  def relay(pid, :psum, %{s: s, w: w}) do
    GenServer.cast(pid, {:psum, %{s: s, w: w}})

    Process.send_after(pid, {:resend, :psum}, @resend_delay)
  end

  # Picks a random peer and relays a message to it
  def transmit(:gossip, data, state) do
    cond do
      state.status in [:active, :infected] and state.peers != [] ->
        # chosen_one = Enum.random(Enum.filter(state.peers, fn e -> get_status(e) != :inactive end))
        chosen_one = Enum.random(state.peers)
        relay(chosen_one, :gossip, data)

        if state.count + 1 >= state.saturation do
          for pid <- state.peers do
            send pid, {:remove_peer, self()}
          end
          %{state | count: state.count + 1, status: :inactive}
        else
          %{state | count: state.count + 1, status: :infected}
        end
        state.status in [:active, :infected] ->
          %{state | count: state.count + 1, status: :inactive}
        state.status == :inactive ->
          state
    end
  end

  def transmit(:psum, %{s: s, w: w}, state) do
    # Update local sum values
    new_data = %{s: 0.5 * (state.data.s + s), w: 0.5 * (state.data.w + w)}
    cond do
      state.status in [:active, :infected] and state.peers != [] ->
        change = abs(new_data.s / new_data.w - state.data.s / state.data.w)
        count = if change < 1.0e-10, do: state.count + 1, else: 0
        chosen_one = Enum.random(state.peers)
        relay(chosen_one, :psum, new_data)
        cond do
          count >= state.psum_saturation ->
            for pid <- state.peers do
              send pid, {:remove_peer, self()}
            end
            %{state | count: count, status: :inactive, data: new_data}
          true ->
            %{state | count: count, status: :infected, data: new_data}
        end
      state.peers == [] ->
        %{state | status: :inactive}
      state.status == :inactive ->
        # chosen_one = Enum.random(state.peers)
        # relay(chosen_one, :psum, %{s: 2*s, w: 2*w})
        state
    end
  end

  ## Server API
  def init({idx, algorithm}) do
    {:ok, %{%__MODULE__{} | idx: idx,
                            algorithm: algorithm,
                            status: :active,
                            data: %{s: idx + 1, w: 1}}}
  end

  def handle_call(:get_peers, _from, node_state) do
    {:reply, node_state.peers, node_state}
  end

  def handle_call(:get_status, _from, node_state) do
    {:reply, node_state.status, node_state}
  end

  def handle_call(:get_ratio, _from, node_state) do
    {:reply, node_state.data.s / node_state.data.w, node_state}
  end

  # Add peers unidirectionally
  def handle_cast({:set_peers, peers}, node_state) do
    new_state = %{node_state | peers: :lists.filter(&(!is_nil(&1)), peers)}
    {:noreply, new_state}
  end

  def handle_cast({:add_peers, peers}, node_state) do
    new_state = %{node_state |
      peers: node_state.peers ++ :lists.filter(
        fn x -> !is_nil(x) && x not in node_state.peers end, peers
      )
    }
    {:noreply, new_state}
  end

  def handle_cast({:gossip, rumour}, node_state) do
    new_state = transmit(:gossip, rumour, node_state)
    if new_state.status != node_state.status do
      send Grapevine.Simulator, {:status, new_state.idx, new_state.status}
    end
    {:noreply, new_state}
  end

  def handle_cast({:psum, %{s: s, w: w}}, node_state) do
    new_state = transmit(:psum, %{s: s, w: w}, node_state)
    # if w > 0, do: IO.write("#{inspect {new_state.status, s/w}}\n")
    if new_state.status != node_state.status do
      send Grapevine.Simulator, {:status, new_state.idx, new_state.status}
    end
    {:noreply, new_state}
  end

  def handle_info({:resend, :gossip, data}, node_state) do
    new_state = transmit(:gossip, data, node_state)
    if new_state.status != node_state.status do
      send Grapevine.Simulator, {:status, new_state.idx, new_state.status}
    end
    Process.send_after(self(), {:resend, :gossip, data}, @resend_delay)

    {:noreply, new_state}
  end

  def handle_info({:resend, :psum}, node_state) do
    new_state = transmit(:psum, node_state.data, node_state)
    if new_state.status != node_state.status do
      send Grapevine.Simulator, {:status, new_state.idx, new_state.status}
    end
    Process.send_after(self(), {:resend, :psum}, @resend_delay)

    {:noreply, new_state}
  end

  def handle_info({:remove_peer, pid}, node_state) do
    {:noreply, %{node_state | peers: List.delete(node_state.peers, pid)}}
  end
end
