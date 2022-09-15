defmodule ZIO.Stack do
  def push(stack, value) do
    List.insert_at(stack, 0, value)
  end

  def pop([cont | rest]) do
    {cont, rest}
  end

  def pop([]) do
    {nil, []}
  end
end
