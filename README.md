# DataPool

A "backpressure" buffer pool that you can push and pop items from.  This
is handy when you have a heavy I/O bound task, you can have many producers
tasks dumping into the pool with `push` and the pool will block on push once
it fills up to it's maximum size.  Likewise you can have several consumer
tasks grabbing data out of the pool and will block on `pop` if the pool is
empty.

## Example Code

```elixir
{:ok, pool} = DataPool.start_link

# Calls to push will bock after the pool has 5 items in the queue,
# the default is 20
DataPool.update_max_size(pool, 5)

# The pool has a status which it returns on every push letting you
# know what the state of the pool is, these can be :done, :halt, or
# :ok.  A blocked call to push will return with :done or :halt if
# the status changes while it's blocked.
:ok = DataPool.push(pool, :it)

# Just like with push, pop returns the state as well, during normal
# flow it returns the tuple {:ok, item}; however, it can also return
# :done, or :halt as well.
{:ok, :it} = DataPool.pop(pool)

:ok = DataPool.push(pool, "items are queued")
:ok = DataPool.push(pool, "first in, first out")
:ok = DataPool.push(pool, "last item")
DataPool.update_status(pool, :done)

DataPool.pop(pool) # {:ok, "items are queued"}
DataPool.pop(pool) # {:ok, "first in, first out"}
DataPool.pop(pool) # {:ok, "last item"}
DataPool.pop(pool) # :done

:done = DataPool.push(pool, "This won't go into the pool")
DataPool.stop(pool)
```

## Stream Buffer

Provides a handy mechinisim to buffer between items to speed up total run
time of a stream process without having to code up working with the data
pool. Here is an example script found in `test/experiment.exs` that mimics
two parts of a stream process that take some time:

``` elixir
1..10
|> Stream.map(fn i ->
  :timer.sleep(600)
  IO.puts "#{i} >>>>>>"
  i
end)
|> DataPool.Buffer.buffer(20)
|> Stream.each(fn i ->
  :timer.sleep(1000)
  IO.puts "            #{i} <<<<<<"
end)
|> Stream.run
```

Running with a measurement of time:
```
1 >>>>>>
2 >>>>>>
            1 <<<<<<
3 >>>>>>
4 >>>>>>
            2 <<<<<<
5 >>>>>>
            3 <<<<<<
6 >>>>>>
7 >>>>>>
            4 <<<<<<
8 >>>>>>
9 >>>>>>
            5 <<<<<<
10 >>>>>>
            6 <<<<<<
            7 <<<<<<
            8 <<<<<<
            9 <<<<<<
            10 <<<<<<

real    0m11.066s
user    0m0.456s
sys     0m0.096s
```

Running the same stream w/o the buffer:
```
1 >>>>>>
            1 <<<<<<
2 >>>>>>
            2 <<<<<<
3 >>>>>>
            3 <<<<<<
4 >>>>>>
            4 <<<<<<
5 >>>>>>
            5 <<<<<<
6 >>>>>>
            6 <<<<<<
7 >>>>>>
            7 <<<<<<
8 >>>>>>
            8 <<<<<<
9 >>>>>>
            9 <<<<<<
10 >>>>>>
            10 <<<<<<

real    0m16.487s
user    0m0.468s
sys     0m0.092s
```

## Installation

  1. Add data_pool to your list of dependencies in `mix.exs`:

        def deps do
          [{:data_pool, "~> 1.0.0"}]
        end
