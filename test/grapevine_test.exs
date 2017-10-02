defmodule GrapevineTest do
  use ExUnit.Case
  doctest Grapevine

  test "greets the world" do
    assert Grapevine.hello() == :world
  end
end
