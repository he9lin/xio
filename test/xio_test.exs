defmodule ZIOTest do
  use ExUnit.Case, async: true

  def assert_zio(zio, expected) do
    zio
    |> ZIO.run(&assert(&1 == expected))
  end

  def assert_zio_succeed(zio, expected) do
    zio
    |> ZIO.run(& assert(&1 == ZIO.Exit.succeed(expected)))
  end

  test "run flat_map" do
    ZIO.return(1)
    |> ZIO.flat_map(fn x -> ZIO.return(x + 1) end)
    |> assert_zio_succeed(2)
  end

  test "run flat_map with succeed" do
    ZIO.return(1)
    |> ZIO.flat_map(fn x -> ZIO.succeed(fn -> x + 1 end) end)
    |> assert_zio_succeed(2)
  end

  test "run map" do
    ZIO.return(1)
    |> ZIO.map(&(&1 + 1))
    |> assert_zio_succeed(2)
  end

  test "run zip_with" do
    ZIO.return(1)
    |> ZIO.zip_with(ZIO.return(2), &(&1 + &2))
    |> assert_zio_succeed(3)
  end

  test "run zip_right" do
    ZIO.return(1)
    |> ZIO.zip_right(ZIO.return(2))
    |> assert_zio_succeed(2)
  end

  test "run ~> operator" do
    import ZIO.Operator

    ZIO.return(1)
    ~> ZIO.return(2)
    |> assert_zio_succeed(2)
  end

  test "run zip" do
    ZIO.return(1)
    |> ZIO.zip(ZIO.return(2))
    |> assert_zio_succeed({1, 2})
  end

  test "run repeat" do
    ZIO.print_line("Hello")
    |> ZIO.repeat(3)
    |> ZIO.run(& &1)
  end

  test "monad do block" do
    require ZIO

    zipped_zio = ZIO.return(8) |> ZIO.zip(ZIO.return("LO"))

    zio =
      ZIO.m do
        x <- ZIO.return(1)
        y <- ZIO.return(2)
        tuple <- zipped_zio
        z <- ZIO.return(x + y)
        return({z, tuple})
      end

    assert_zio_succeed(zio, {3, {8, "LO"}})
  end

  test "async" do
    require ZIO

    zio =
      ZIO.m do
        x <-
          ZIO.async(fn callback ->
            IO.puts("Long running task")
            :timer.sleep(500)
            callback.(10)
          end)

        y <-
          ZIO.async(fn callback ->
            IO.puts("Long running task")
            :timer.sleep(500)
            callback.(20)
          end)

        return({x, y})
      end

    assert_zio_succeed(zio, {10, 20})
  end

  test "fiber" do
    require ZIO

    async_zio =
      ZIO.async(fn callback ->
        IO.puts("Long running task")
        :timer.sleep(1000)
        callback.(:rand.uniform(99))
      end)

    zio =
      ZIO.m do
         fiber <- async_zio |> ZIO.fork()
        fiber2 <- async_zio |> ZIO.fork()
             _ <- ZIO.print_line("Doing something else")
             x <- ZIO.Fiber.join(fiber)
             y <- ZIO.Fiber.join(fiber2)
        return ZIO.Zippable.zip(x, y)
      end

    zio
    |> ZIO.run(&IO.inspect/1)
  end

  defmodule ZipPar do
    require ZIO

    def zip_par(zio1, zio2) do
      ZIO.m do
        f1 <- zio1 |> ZIO.fork()
        f2 <- zio2 |> ZIO.fork()
        x1 <- ZIO.Fiber.join(f1)
        x2 <- ZIO.Fiber.join(f2)

        return ZIO.Zippable.zip(x1, x2)
      end
    end
  end

  test "zip_par" do
    require ZIO

    async_zio =
      ZIO.async(fn callback ->
        IO.puts("Long running task")
        :timer.sleep(1000)
        callback.(:rand.uniform(99))
      end)

    async_zio
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZipPar.zip_par(async_zio)
    |> ZIO.run(&IO.inspect/1)
  end

  test "fail" do
    ZIO.fail("Failed!")
    |> ZIO.flat_map(ZIO.print_line("OH YEAH"))
    |> assert_zio(%ZIO.Exit.Failure{cause: %ZIO.Cause.Fail{error: "Failed!"}})
  end

  test "fail with catch all" do
    ZIO.fail("Failed!")
    |> ZIO.flat_map(ZIO.print_line("OH YEAH"))
    |> ZIO.catch_all(fn _ -> ZIO.return(1) end)
    |> assert_zio_succeed(1)
  end

  test "die" do
    ZIO.return("OK")
    |> ZIO.flat_map(fn _ -> raise("Oh oh") end)
    |> assert_zio(%ZIO.Exit.Failure{
      cause: %ZIO.Cause.Die{throwable: %RuntimeError{message: "Oh oh"}}
    })
  end

  test "die with catch all" do
    ZIO.return("OK")
    |> ZIO.flat_map(fn _ -> raise("Oh oh") end)
    |> ZIO.catch_all(fn e -> ZIO.print_line("CATCH IT: #{inspect(e)}") end)
    |> ZIO.fold_cause_zio(
      fn c ->
        ZIO.print_line("Recovered from a cause #{inspect(c)}") |> ZIO.zip_right(ZIO.return(1))
      end,
      fn _ -> ZIO.return(0) end
    )
    |> assert_zio_succeed(1)
  end

  test "ensuring" do
    ZIO.fail("Failed!")
    |> ZIO.ensuring(ZIO.print_line("Ensuring"))
    |> ZIO.flat_map(ZIO.print_line("OH YEAH"))
    |> ZIO.run(&IO.inspect/1)
  end
end
