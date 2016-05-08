defimpl Collectable, for: DataPool do
  @doc """
  Allows you to put items into a DataPool

      iex> {:ok, pool} = DataPool.start_link
      iex> 1..5 |> Enum.into(pool)
      iex> DataPool.size(pool)
      5
  """
  def into(pool=%DataPool{}), do: {pool, &into(&1, &2)}

  defp into(pool=%DataPool{}, {:cont, item}) do
    DataPool.push(pool, item)
    pool
  end
  defp into(pool=%DataPool{}, :done) do
    DataPool.update_status(pool, :done)
    pool
  end
  defp into(pool=%DataPool{}, :halt) do
    DataPool.update_status(pool, :halt)
    pool
  end
end
