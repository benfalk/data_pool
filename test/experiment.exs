{:ok, pool} = DataPool.start_link

1..10
|> Stream.map(fn i ->
  :timer.sleep(400)
  IO.puts "#{i} >>>>>>"
  i
end)
|> DataPool.StreamBuffer.buffer(20)
|> Stream.each(fn i ->
  :timer.sleep(1000)
  IO.puts "            #{i} <<<<<<"
end)
|> Stream.run
