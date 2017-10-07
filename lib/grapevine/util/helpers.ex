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
        Logger.debug value
    end
    print_loop()
  end

  def enumerate_rows(enumerable, row_len) do
    Enum.chunk_every(enumerable, row_len)
  end

  defp transpose([[] | _]), do: []
  defp transpose(mat) do
    [:lists.map(&hd(&1), mat) | transpose(:lists.map(&tl(&1), mat))]
  end

  def enumerate_cols(enumerable, row_len) do
    # All hail haskell
    # http://stackoverflow.com/questions/5389254/transposing-a-2-dimensional-matrix-in-erlang
    transpose(enumerate_rows(enumerable, row_len))
  end
end
