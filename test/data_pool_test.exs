defmodule DataPoolTest do
  use ExUnit.Case, async: true
  doctest DataPool
  doctest Collectable.DataPool
  doctest DataPool.Buffer

  setup do
    {:ok, pool} = DataPool.start_link
    {:ok, pool: pool}
  end
    

  test "things pop off and on", context do
    assert DataPool.push(context.pool, :it) == :ok
    assert DataPool.pop(context.pool) == {:ok, :it}
  end

  test "you can overfill it and pull from it", context do
    Task.async fn ->
      1..50 |> Enum.map(&DataPool.push(context.pool, &1))
    end
    result = 101..150 |> Enum.map(fn _ -> DataPool.pop(context.pool) end)
    assert result == 1..50 |> Enum.map(&({:ok, &1}))
  end

  test "you can overfill it with multiple producers", context do
    Task.async fn ->
      1..50 |> Enum.map(&DataPool.push(context.pool, &1))
    end
    Task.async fn ->
      51..100 |> Enum.map(&DataPool.push(context.pool, &1))
    end
    result = 1..100 |> Enum.map(fn _ -> DataPool.pop(context.pool) end) |> Enum.sort
    assert result == 1..100 |> Enum.map(&({:ok, &1}))
  end

  test "when empty, it will pull from producers as added", context do
    task = Task.async fn ->
      1..10 |> Enum.map(fn _ -> DataPool.pop(context.pool) end)
    end
    11..20 |> Enum.each(&DataPool.push(context.pool, &1))
    assert Task.await(task) == 11..20 |> Enum.map(&({:ok, &1}))
  end

  test "with a size of zero, when changed it should empty", context do
    DataPool.update_max_size(context.pool, 0)
    task = Task.async fn ->
      1..3 |> Enum.map(fn _ -> DataPool.pop(context.pool) end)
    end
    Task.async fn ->
      1..3 |> Enum.each(fn x -> DataPool.push(context.pool, x) end)
    end
    DataPool.update_max_size(context.pool, 1)
    assert Task.await(task) == [ok: 1, ok: 2, ok: 3]
  end

  test "items waiting to push or pool get right reply when status changes", %{pool: pool} do
    DataPool.update_max_size(pool, 0)
    pushes = Task.async fn ->
      Enum.map(1..3, &DataPool.push(pool, &1))
    end
    pulls = Task.async fn ->
      Enum.map(1..3, fn _ -> DataPool.pop(pool) end)
    end
    DataPool.update_status(pool, :halt)
    assert Task.await(pulls) == [:halt, :halt, :halt]
    assert Task.await(pushes) == [:halt, :halt, :halt]
  end

  test "pool will return `:done` after all items have been taken after flagged", %{pool: pool} do
    Enum.each(1..2, &DataPool.push(pool, &1))
    DataPool.update_status(pool, :done)
    assert Enum.map(1..3, fn _ -> DataPool.pop(pool) end) == [{:ok, 1}, {:ok, 2}, :done]
  end

  test "filling up the buffer, then marking as done alerts consumer", %{pool: pool} do
    DataPool.update_max_size(pool, 2)
    task = Task.async fn ->
      1..3 |> Enum.map(&DataPool.push(pool, &1))
    end
    :timer.sleep 20
    DataPool.update_status(pool, :done)
    results = Task.await(task)
    assert results == [:ok, :ok, :done]
  end
end
