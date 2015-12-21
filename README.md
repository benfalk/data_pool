# DataPool

A "backpressure" buffer pool that you can push and pop items from.  This
is handy when you have a heavy I/O bound task, you can have many producers
tasks dumping into the pool with `push` and the pool will block on push once
it fills up to it's maximum size.  Likewise you can have several consumer
tasks grabbing data out of the pool and will block on `pop` if the pool is
empty.

## Installation

  1. Add data_pool to your list of dependencies in `mix.exs`:

        def deps do
          [{:data_pool, "~> 0.0.1"}]
        end
