defmodule DataPool do
  @moduledoc """
  Provides a blocking data storage and retrival data pool.  The basic idea
  behind DataPool is to allow producers to fill the pool up and block on
  adding more items once it's limit is reached.  On the flip side, consumers
  of the data block when the pool is empty.
  """
  alias EQueue, as: Queue
  use GenServer
  @empty_queue Queue.new

  defstruct consumers: @empty_queue,
            producers: @empty_queue,
            data: @empty_queue,
            size: 0,
            max_size: 20

  @type t :: %DataPool{
    consumers: Queue.t,
    producers: Queue.t,
    data: Queue.t,
    size: pos_integer,
    max_size: pos_integer
  }



  @doc """
  Returns the expected tuple `{:ok, pid}`

  ## Example

      iex> {:ok, pid} = DataPool.start_link
      iex> is_pid(pid)
      true
  """
  @spec start_link() :: {:ok, pid}
  def start_link do
    GenServer.start_link(__MODULE__, %__MODULE__{})
  end



  @doc """
  Returns the maximum amount of items that can be added to the pool before
  calls to `push` are blocked

  ## Example

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.max_size(pid)
      20
  """
  @spec max_size(pid) :: pos_integer
  def max_size(pid), do: GenServer.call(pid, :max_size)



  @doc """
  Dynamically changes the maximum size the pool will hold before producers
  are blocked

  ## Examples

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.update_max_size(pid, 243)
      iex> DataPool.max_size(pid)
      243
  """
  @spec update_max_size(pid, pos_integer) :: :ok
  def update_max_size(pid, size), do: GenServer.call(pid, {:update_max_size, size})



  @doc """
  Add an item to the pool to be processed by a consumer.  If the pool is at it's
  max limit this operation will block and wait until there is room available.

  ## Examples

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.push(pid, :it)
      nil

      iex> {:ok, pid} = DataPool.start_link
      iex> task = Task.async fn ->
      ...>   1..100 |> Enum.map(fn x -> DataPool.push(pid, x) end)
      ...> end
      iex> Task.yield(task, 100)
      nil

      iex> {:ok, pid} = DataPool.start_link
      iex> task = Task.async fn ->
      ...>   1..5 |> Enum.map(fn x -> DataPool.push(pid, x) end)
      ...> end
      iex> Task.yield(task, 100)
      {:ok, [nil, nil, nil, nil, nil]}
  """
  @spec push(pid, any) :: nil
  def push(pid, item), do: GenServer.call(pid, {:push, item})



  @doc """
  Returns an item out of the pool.  If the pool is empty this operation blocks
  and waits for an item to become available.

  ## Examples

      iex> {:ok, pid} = DataPool.start_link
      iex> task = Task.async fn ->
      ...>   DataPool.pop(pid)
      ...> end
      iex> Task.yield(task, 100)
      nil

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.push(pid, :it)
      iex> DataPool.pop(pid)
      :it
  """
  @spec pop(pid) :: any
  def pop(pid), do: GenServer.call(pid, :pop)



  @doc """
  Stops the pool, any outstanding push or pops from the pool are canceled

  ## Example

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.stop(pid)
      :ok
  """
  @spec stop(pid) :: :ok
  def stop(pid), do: GenServer.call(pid, :stop)


  @doc false
  def handle_call({:push, item}, pusher, state=%DataPool{size: size, max_size: max}) when size >= max do
    {:noreply, %DataPool{ state | producers: Queue.push(state.producers, {pusher, item}) }}
  end
  def handle_call({:push, item}, _, state=%DataPool{consumers: @empty_queue}) do
    {:reply, nil, %DataPool{ state | data: state.data |> Queue.push(item), size: state.size + 1 }}
  end
  def handle_call({:push, item}, _, state) do
    {:value, consumer, updated_consumers} = Queue.pop(state.consumers)
    GenServer.reply(consumer, item)
    {:reply, nil, %DataPool{ state | consumers: updated_consumers }}
  end


  @doc false
  def handle_call(:pop, consumer, state=%DataPool{data: @empty_queue}) do
    {:noreply, %DataPool{ state | consumers: state.consumers |> Queue.push(consumer) }}
  end
  def handle_call(:pop, _, state=%DataPool{producers: @empty_queue}) do
    {:value, item, new_data} = Queue.pop(state.data)
    {:reply, item, %DataPool{ state | data: new_data, size: state.size - 1 }}
  end
  def handle_call(:pop, _, state) do
    {:value, {pusher, item}, producers} = Queue.pop(state.producers)
    GenServer.reply(pusher, nil)
    {:value, reply_item, data} = Queue.pop(state.data)
    {:reply, reply_item, %DataPool{ state | producers: producers, data: Queue.push(data, item) }}
  end


  @doc false
  def handle_call(:stop, _, state) do
    {:stop, :normal, :ok, state}
  end


  @doc false
  def handle_call(:max_size, _, state), do: {:reply, state.max_size, state}


  @doc false
  def handle_call({:update_max_size, size}, _, state=%DataPool{producers: @empty_queue}) do
    {:reply, :ok, %DataPool{ state |> notify_any_consumers | max_size: size }}
  end
  def handle_call({:update_max_size, size}, _, state=%DataPool{max_size: current_size}) when size > current_size do
    new_state = state
      |> unblock_next_producers(size - current_size)
      |> notify_any_consumers
    {:reply, :ok, %DataPool{ new_state | max_size: size }}
  end
  def handle_call({:update_max_size, size}, _, state) do
    {:reply, :ok, %DataPool{ state | max_size: size }}
  end


  @doc false
  defp notify_any_consumers(state=%DataPool{consumers: @empty_queue}), do: state
  defp notify_any_consumers(state=%DataPool{data: @empty_queue}), do: state
  defp notify_any_consumers(state=%DataPool{}) do
    {:value, consumer, consumers} = Queue.pop(state.consumers)
    {:value, item, data} = Queue.pop(state.data)
    GenServer.reply(consumer, item)
    %DataPool{ state | data: data, consumers: consumers }
  end


  @doc false
  defp unblock_next_producers(state=%DataPool{producers: @empty_queue}, _), do: state
  defp unblock_next_producers(state, 0), do: state
  defp unblock_next_producers(state, amount) do
    {:value, {pusher, item}, producers} = Queue.pop(state.producers)
    GenServer.reply(pusher, nil)
    new_state = %DataPool{ state | producers: producers,
                                   data: Queue.push(state.data, item),
                                   size: state.size + 1 }
    unblock_next_producers(new_state, amount - 1)
  end
end
