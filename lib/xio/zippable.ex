defmodule ZIO.Zippable do
  def zip({a, b}, c) do
    {a, b, c}
  end

  def zip({a, b, c}, d) do
    {a, b, c, d}
  end

  def zip({a, b, c, d}, e) do
    {a, b, c, d, e}
  end
  
  def zip({a, b, c, d, e}, f) do
    {a, b, c, d, e, f}
  end

  def zip({a, b, c, d, e, f}, g) do
    {a, b, c, d, e, f, g}
  end

  def zip({a, b, c, d, e, f, g}, h) do
    {a, b, c, d, e, f, g, h}
  end

  def zip({a, b, c, d, e, f, g, h}, i) do
    {a, b, c, d, e, f, g, h, i}
  end

  def zip({a, b, c, d, e, f, g, h, i}, j) do
    {a, b, c, d, e, f, g, h, i, j}
  end

  def zip({a, b, c, d, e, f, g, h, i, j}, k) do
    {a, b, c, d, e, f, g, h, i, j, k}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k}, l) do
    {a, b, c, d, e, f, g, h, i, j, k, l}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l}, m) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l, m}, n) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m, n}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l, m, n}, o) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m, n, o}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l, m, n, o}, p) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p}, q) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q}
  end

  def zip({a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q}, r) do
    {a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r}
  end

  def zip(a, b) do
    {a, b}
  end
end
