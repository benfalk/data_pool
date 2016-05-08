defmodule DataPool.Buffer do
  import Task, only: [async: 1, await: 2]
  @moduledoc """
  Provides a greedy buffer which pulls from upstream to keep it busy
  until the buffer is full.  This can significantly shorten the total
  time of a stream process by keeping expensive parts of the stream
  working.
  """

  @doc """
  Pipe this between streams to buffer between them

  ## Example

      iex> 1..3
      ...> |> Stream.map(fn i -> i * 2 end)
      ...> |> DataPool.Buffer.buffer(1)
      ...> |> Stream.take(2)
      ...> |> Enum.to_list
      [2,4]
  """
  @spec buffer(Enumerable.t, pos_integer, timeout) :: Stream.t
  def buffer(stream, size, timeout \\ :infinity) do
    start_fun = fn ->
      pool = build_pool(size, timeout)
      task = async fn ->
        Stream.run(buffered_pool_stream(stream, pool))
        DataPool.update_status(pool, :done)
      end
      %{pool: pool, task: task}
    end

    next_fun = fn state ->
      case DataPool.pop(state.pool) do
        {:ok, item} -> {[item], state}
        :done -> {:halt, state}
        :halt -> {:halt, state}
      end
    end

    end_fun = fn state ->
      DataPool.update_status(state.pool, :done)
      await(state.task, timeout)
      DataPool.stop(state.pool)
    end

    Stream.resource(start_fun, next_fun, end_fun)
  end

  defp build_pool(size, timeout) do
    {:ok, pool} = DataPool.start_link
    DataPool.update_max_size(pool, size)
    %{ pool | default_timeout: timeout }
  end

  defp buffered_pool_stream(stream, pool) do
    Stream.transform stream, pool, fn item, acc ->
      case DataPool.push(acc, item) do
        :ok   -> {[], acc}
        :done -> {:halt, acc}
        :halt -> {:halt, acc}
      end
    end
  end
end
