defmodule DataPool.State do
  @moduledoc """
  The internal state of the DataPool GenServer.
  """
  alias EQueue, as: Queue
  @empty_queue Queue.new

  defstruct consumers: @empty_queue,
            producers: @empty_queue,
            data: @empty_queue,
            size: 0,
            max_size: 20,
            status: :ok
  
  @type status :: :ok | :done | :halt

  @type t :: %__MODULE__{
    consumers: Queue.t,
    producers: Queue.t,
    data: Queue.t,
    size: pos_integer,
    max_size: pos_integer,
    status: status
  }
end
