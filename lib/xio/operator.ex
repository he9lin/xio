defmodule ZIO.Operator do
  def zio1 >>> zio2 do
    ZIO.zip_right(zio1, zio2)
  end

  def zio1 ~> zio2 do
    ZIO.flat_map(zio1, zio2)
  end
end
