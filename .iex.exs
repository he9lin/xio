require ZIO

defmodule ZIOExt do
  require ZIO

  def speak_with_delay(message, delay) do
    ZIO.succeed(fn ->
      :timer.sleep(delay)
      IO.puts(message)
    end)
  end

  def zip_with_par(zio1, zio2, f) do
    ZIO.m do
      left <- ZIO.fork(zio1)
      right <- ZIO.fork(zio2)
      a <- ZIO.FiberRuntime.join(left)
      b <- ZIO.FiberRuntime.join(right)

      return f.(a, b)
    end
  end

  def run() do
    speak_with_delay("Hello", 3000)
    |> zip_with_par(speak_with_delay("World", 5000), fn _, _ -> nil end)
  end
end
