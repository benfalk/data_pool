defmodule DataPoolTest do
  use ExUnit.Case, async: true
  doctest DataPool
  doctest Collectable.DataPool

  setup do
    {:ok, data} = DataPool.start_link
    {:ok, pid: data}
  end
    

  test "things pop off and on", context do
    assert DataPool.push(context.pid, :it) == nil
    assert DataPool.pop(context.pid) == :it
  end

  test "you can overfill it and pull from it", context do
    Task.async fn ->
      1..50 |> Enum.map(&DataPool.push(context.pid, &1))
    end
    result = 101..150 |> Enum.map(fn _ -> DataPool.pop(context.pid) end)
    assert result == 1..50 |> Enum.to_list
  end

  test "you can overfill it with multiple producers", context do
    Task.async fn ->
      1..50 |> Enum.map(&DataPool.push(context.pid, &1))
    end
    Task.async fn ->
      51..100 |> Enum.map(&DataPool.push(context.pid, &1))
    end
    result = 1..100 |> Enum.map(fn _ -> DataPool.pop(context.pid) end) |> Enum.sort
    assert result == 1..100 |> Enum.to_list
  end

  test "when empty, it will pull from producers as added", context do
    task = Task.async fn ->
      1..10 |> Enum.map(fn _ -> DataPool.pop(context.pid) end)
    end
    11..20 |> Enum.each(&DataPool.push(context.pid, &1))
    assert Task.await(task) == 11..20 |> Enum.to_list 
  end

  test "with a size of zero, when changed it should empty", context do
    DataPool.update_max_size(context.pid, 0)
    task = Task.async fn ->
      1..3 |> Enum.map(fn _ -> DataPool.pop(context.pid) end)
    end
    Task.async fn ->
      1..3 |> Enum.each(fn x -> DataPool.push(context.pid, x) end)
    end
    DataPool.update_max_size(context.pid, 1)
    assert Task.await(task) == [1, 2, 3]
  end
end
