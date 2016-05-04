defmodule DataPool.StreamBuffer do
  @moduledoc """
  Provides a greedy buffer in your stream which can be used to fill
  up data from upstream provider resources.  This is most useful
  when pulling sets from an API or database and want to always keep
  the IO with the resource upstream busy until you have a significant
  amount of buffer full to work with.
  """

  @type max_timeout :: pos_integer | :infinity


  def buffer(stream, buffer_size, timeout \\ :infinity) when(buffer_size) > 0 do
    start_fun = fn ->
      {:ok, pool} = DataPool.start_link
      {:ok, agent} = Agent.start_link(fn -> true end)
      DataPool.update_max_size(pool, buffer_size)

      consumer = Task.async(fn ->
        stream
        |> Stream.transform(agent, fn i, a ->
          if Agent.get(a, &(&1)), do: {[i], a}, else: {:halt, a}
        end)
        |> Stream.each(fn i -> DataPool.push(pool, {:item, i}, timeout) end)
        |> Stream.run

        DataPool.push(pool, :stop)
      end)

      %{pool: pool, consumer: consumer, agent: agent}
    end

    next_fun = fn %{pool: pool} = res ->
      case DataPool.pop(pool, timeout) do
        {:item, i} -> {[i], res}
        :stop -> {:halt, res}
      end
    end

    after_fun = fn %{consumer: consumer, agent: agent, pool: pool} ->
      Agent.update(agent, fn _ -> false end)
      Task.await(consumer, timeout)
      DataPool.stop(pool)
      Agent.stop(agent)
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end
end
