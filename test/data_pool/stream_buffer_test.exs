defmodule DataPool.StreamBufferTest do
  use ExUnit.Case, async: true
  alias DataPool.Buffer, as: StreamBuffer

  test "finishing early works" do
    results = 1..100
    |> StreamBuffer.buffer(2)
    |> Stream.take(5)
    |> Enum.to_list

    assert results == [1, 2, 3, 4, 5]
  end

  test "exausting upstream works" do
    results = 1..5
    |> StreamBuffer.buffer(2)
    |> Enum.to_list

    assert results == [1, 2, 3, 4, 5]
  end

  test "empty list works as expected" do
    results = []
    |> StreamBuffer.buffer(5)
    |> Enum.to_list

    assert results == []
  end

  test "upstream resource cleanup is called" do
    {:ok, agent} = Agent.start_link(fn -> :before end)

    results = Stream.resource(
      fn -> 
        Agent.update(agent, fn _ -> :dirty end)
        agent
      end,
      fn a ->
        {[1], a}
      end,
      fn a ->
        Agent.update(a, fn _ -> :clean end)
      end
    )
    |> StreamBuffer.buffer(2)
    |> Stream.take(5)
    |> Enum.to_list

    assert results == [1, 1, 1, 1, 1]
    assert Agent.get(agent, &(&1)) == :clean
  end
end
