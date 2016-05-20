defmodule DataPool do
  @moduledoc """
  Provides a blocking data storage and retrival data pool.  The basic idea
  behind DataPool is to allow producers to fill the pool up and block on
  adding more items once it's limit is reached.  On the flip side, consumers
  of the data block when the pool is empty.
  """
  alias DataPool.State
  alias EQueue, as: Queue
  use GenServer
  import GenServer, only: [call: 2, call: 3]
  @empty_queue Queue.new
  @type max_timeout :: pos_integer | :infinity

  defstruct pid: nil,
            default_timeout: :infinity

  @type t :: %__MODULE__{
    pid: pid,
    default_timeout: max_timeout
  }


  @doc """
  Returns the tuple `{:ok, %DataPool{}}` with a live pid queue that
  mantains the queue state

  ## Example

      iex> {:ok, pool} = DataPool.start_link
      iex> %DataPool{pid: pid} = pool
      iex> is_pid(pid)
      true
  """
  @spec start_link() :: {:ok, t}
  def start_link do
    case GenServer.start_link(__MODULE__, %State{}) do
      {:ok, pid} -> {:ok, %__MODULE__{pid: pid}}
      error -> raise error
    end
  end



  @doc """
  Returns the maximum amount of items that can be added to the pool before
  calls to `push` are blocked

  ## Example

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.max_size(pid)
      20
  """
  @spec max_size(t) :: pos_integer
  def max_size(%__MODULE__{pid: pid}), do: call(pid, :max_size)



  @doc """
  Dynamically changes the maximum size the pool will hold before producers
  are blocked

  ## Examples

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.update_max_size(pid, 243)
      iex> DataPool.max_size(pid)
      243
  """
  @spec update_max_size(t, pos_integer) :: :ok
  def update_max_size(%__MODULE__{pid: pid}, size), do: call(pid, {:update_max_size, size})



  @doc """
  Add an item to the pool to be processed by a consumer.  If the pool is at it's
  max limit this operation will block and wait until there is room available. Push
  should always return the the status of the pool, `:ok`, `:done`, or `:halt`.
  Items are not added when the state is anything but `:ok`

  ## Examples

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.push(pid, :it)
      :ok

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
      {:ok, [:ok, :ok, :ok, :ok, :ok]}
  """
  @spec push(t, any, max_timeout) :: State.status
  def push(%__MODULE__{pid: pid}, item, timeout), do: call(pid, {:push, item}, timeout)
  def push(pool=%__MODULE__{}, item), do: push(pool, item, pool.default_timeout)


  @doc """
  The current status of the pool, can be one of `:ok`, `:done`, or `:halt`

  ## Examples

      iex> {:ok, pool} = DataPool.start_link
      iex> DataPool.get_status(pool)
      :ok
  """
  @spec get_status(t) :: State.status
  def get_status(%__MODULE__{pid: pid}), do: call(pid, :get_status)

  @doc """
  Updates the pool with a new status

  ## Examples

      iex> {:ok, pool} = DataPool.start_link
      iex> DataPool.update_status(pool, :halt)
      iex> DataPool.get_status(pool)
      :halt
  """
  @spec update_status(t, State.status) :: State.t
  def update_status(%__MODULE__{pid: pid}, status), do: call(pid, {:update_status, status})



  @doc """
  Returns an item out of the pool.  If the pool is empty this operation blocks
  and waits for an item to become available. A normal return is in the form of a
  tuple looking like `{:ok, item}`, otherwise it will return the status of `:done`
  or `:halt`

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
      {:ok, :it}
  """
  @spec pop(t, max_timeout) :: {:ok, any} | :done | :halt
  def pop(%__MODULE__{pid: pid}, timeout), do: call(pid, :pop, timeout)
  def pop(pool=%__MODULE__{}), do: pop(pool, pool.default_timeout)



  @doc """
  Stops the pool, any outstanding push or pops from the pool are canceled

  ## Example

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.stop(pid)
      :ok
  """
  @spec stop(t) :: :ok
  def stop(%__MODULE__{pid: pid}), do: call(pid, :stop)

  @doc """
  Returns the amount of items in the pool

  ### Example

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.push(pid, :it)
      iex> DataPool.size(pid)
      1

      iex> {:ok, pid} = DataPool.start_link
      iex> DataPool.size(pid)
      0
  """
  @spec size(t) :: pos_integer
  def size(%__MODULE__{pid: pid}), do: call(pid, :size)


  @doc false
  def handle_call({:push, _}, _, state=%State{status: :done}) do
    {:reply, :done, state}
  end
  def handle_call({:push, _}, _, state=%State{status: :halt}) do
    {:reply, :halt, state}
  end
  def handle_call({:push, item}, pusher, state=%State{size: size, max_size: max}) when size >= max do
    {:noreply, %State{ state | producers: Queue.push(state.producers, {pusher, item}) }}
  end
  def handle_call({:push, item}, _, state=%State{consumers: @empty_queue}) do
    {:reply, :ok, %State{ state | data: state.data |> Queue.push(item), size: state.size + 1 }}
  end
  def handle_call({:push, item}, _, state) do
    {:value, consumer, updated_consumers} = Queue.pop(state.consumers)
    GenServer.reply(consumer, {:ok, item})
    {:reply, :ok, %State{ state | consumers: updated_consumers }}
  end


  @doc false
  def handle_call(:pop, _, state=%State{status: :halt}) do
    {:reply, :halt, state}
  end
  def handle_call(:pop, _, state=%State{status: :done, data: @empty_queue}) do
    {:reply, :done, state}
  end
  def handle_call(:pop, consumer, state=%State{data: @empty_queue}) do
    {:noreply, %State{ state | consumers: state.consumers |> Queue.push(consumer) }}
  end
  def handle_call(:pop, _, state=%State{producers: @empty_queue}) do
    {:value, item, new_data} = Queue.pop(state.data)
    {:reply, {:ok, item}, %State{ state | data: new_data, size: state.size - 1 }}
  end
  def handle_call(:pop, _, state) do
    {:value, {pusher, item}, producers} = Queue.pop(state.producers)
    GenServer.reply(pusher, state.status)
    {:value, reply_item, data} = Queue.pop(state.data)
    {:reply, {:ok, reply_item}, %State{ state | producers: producers, data: Queue.push(data, item) }}
  end


  @doc false
  def handle_call(:stop, _, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call(:size, _, state), do: {:reply, state.size, state}

  @doc false
  def handle_call(:max_size, _, state), do: {:reply, state.max_size, state}


  @doc false
  def handle_call({:update_max_size, size}, _, state=%State{producers: @empty_queue}) do
    {:reply, :ok, %State{ state |> notify_any_consumers | max_size: size }}
  end
  def handle_call({:update_max_size, size}, _, state=%State{max_size: max}) when size > max do
    new_state = state
    |> unblock_next_producers(size - max)
    |> notify_any_consumers
    {:reply, :ok, %State{ new_state | max_size: size }}
  end
  def handle_call({:update_max_size, size}, _, state) do
    {:reply, :ok, %State{ state | max_size: size }}
  end


  @doc false
  def handle_call(:get_status, _, state=%State{status: status}) do
    {:reply, status, state}
  end


  @doc false
  def handle_call({:update_status, :halt}, _, state) do
    state.consumers |> Enum.each(&GenServer.reply(&1, :halt))
    state.producers |> Enum.each(&GenServer.reply(&1, :halt))
    {:reply, :ok, %State{ state | status: :halt }}
  end
  def handle_call({:update_status, :done}, _, state=%State{data: @empty_queue}) do
    state.consumers |> Enum.each(&GenServer.reply(&1, :done))
    state.producers |> Enum.each(&GenServer.reply(&1, :done))
    {:reply, :ok, %State{ state | status: :done }}
  end
  def handle_call({:update_status, :done}, _, state) do
    state.producers |> Enum.each(&GenServer.reply(&1, :done))
    {:reply, :ok, %State{ state | status: :done }}
  end
  def handle_call({:update_status, status}, _, state) do
    {:reply, :ok, %State{ state | status: status }}
  end


  @doc false
  defp notify_any_consumers(state=%State{consumers: @empty_queue}), do: state
  defp notify_any_consumers(state=%State{data: @empty_queue}), do: state
  defp notify_any_consumers(state=%State{}) do
    {:value, consumer, consumers} = Queue.pop(state.consumers)
    {:value, item, data} = Queue.pop(state.data)
    GenServer.reply(consumer, {:ok, item})
    %State{ state | data: data, consumers: consumers }
  end


  @doc false
  defp unblock_next_producers(state=%State{producers: @empty_queue}, _), do: state
  defp unblock_next_producers(state, 0), do: state
  defp unblock_next_producers(state, amount) do
    {:value, {pusher, item}, producers} = Queue.pop(state.producers)
    GenServer.reply(pusher, state.status)
    new_state = %State{ state | producers: producers,
                                data: Queue.push(state.data, item),
                                size: state.size + 1 }
    unblock_next_producers(new_state, amount - 1)
  end
end
