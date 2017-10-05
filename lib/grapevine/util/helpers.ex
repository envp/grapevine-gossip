defmodule Grapevine.Util.Helpers do
  @moduledoc """
  Module containing generic helper functions
  """

  require Logger

  def atom_for(:topology, topology) do
    case topology do
      "full"  -> :full
      "2D"    -> :planar
      "line"  -> :line
      "imp2D" -> :imp2D
      _       -> nil
    end
  end

  def atom_for(:algorithm, algorithm) do
    case algorithm do
      "gossip"    -> :gossip
      "push-sum"  -> :psum
      _           -> nil
    end
  end

  def print_loop do
    receive do
      {:print, value} ->
        Logger.info value
    end
    print_loop()
  end
end
