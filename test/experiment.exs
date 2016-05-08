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
