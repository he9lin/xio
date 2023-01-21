defmodule ZIOTest do
  use ExUnit.Case, async: true
  alias ZIO.Env

  test "run flat_map" do
    ZIO.return(1)
    |> ZIO.flat_map(fn x -> ZIO.return(x + 1) end)
    |> assert_zio_success(2)
  end

  test "run flat_map with succeed" do
    ZIO.return(1)
    |> ZIO.flat_map(fn x -> ZIO.succeed(fn -> x + 1 end) end)
    |> assert_zio_success(2)
  end

  test "run map" do
    ZIO.return(1)
    |> ZIO.map(&(&1 + 1))
    |> assert_zio_success(2)
  end

  test "run with result" do
    result =
      ZIO.return(1)
      |> ZIO.map(&(&1 + 1))
      |> ZIO.run(fn x -> x end)
    assert result == %ZIO.Exit.Success{value: 2}
  end

  test "run map_error" do
    ZIO.return(1)
    |> ZIO.map_error(&(&1 + 1))
    |> assert_zio_success(1)
  end

  test "run map_error with error" do
    ZIO.fail(1)
    |> ZIO.map_error(&(&1 + 1))
    |> assert_zio_failure(%ZIO.Cause.Fail{error: 2})
  end

  test "run zip_with" do
    ZIO.return(1)
    |> ZIO.zip_with(ZIO.return(2), &(&1 + &2))
    |> assert_zio_success(3)
  end

  test "run zip_right" do
    ZIO.return(1)
    |> ZIO.zip_right(ZIO.return(2))
    |> assert_zio_success(2)
  end

  test "run ~> operator" do
    import ZIO.Operator

    ZIO.return(1)
    ~> ZIO.return(2)
    |> assert_zio_success(2)
  end

  test "run zip" do
    ZIO.return(1)
    |> ZIO.zip(ZIO.return(2))
    |> ZIO.zip(ZIO.return(3))
    |> assert_zio_success({1, 2, 3})
  end

  test "run repeat" do
    ZIO.print_line("Hello")
    |> ZIO.repeat(3)
    |> assert_zio_success(nil)
  end

  test "monad do block" do
    require ZIO

    zipped_zio = 
      ZIO.return(8) 
      |> ZIO.zip(ZIO.return("HE"))
      |> ZIO.zip(ZIO.return("LLO"))

    zio =
      ZIO.m do
        x <- ZIO.return(1)
        y <- ZIO.return(2)
        tuple <- zipped_zio
        z <- ZIO.return(x + y)
        return({z, tuple})
      end

    assert_zio_success(zio, {3, {8, "HE", "LLO"}})
  end

  test "fail" do
    ZIO.fail("Failed!")
    |> ZIO.flat_map(ZIO.print_line("Should not be printed"))
    |> assert_zio_failure(%ZIO.Cause.Fail{error: "Failed!"})
  end

  test "fail with catch all" do
    ZIO.fail("Failed!")
    |> ZIO.flat_map(ZIO.print_line("Should not be printed"))
    |> ZIO.catch_all(fn _ -> ZIO.return(1) end)
    |> assert_zio_success(1)
  end

  test "die" do
    ZIO.return("OK")
    |> ZIO.flat_map(fn _ -> raise("Oh oh") end)
    |> assert_zio_failure(%ZIO.Cause.Die{throwable: %RuntimeError{message: "Oh oh"}})
  end

  test "die with catch all" do
    import ZIO.Operator

    ZIO.return("OK")
    |> ZIO.flat_map(fn _ -> raise("Oh oh") end)
    |> ZIO.catch_all(fn e -> ZIO.print_line("CATCH IT: #{inspect(e)}") end)
    |> ZIO.fold_cause_zio(
      fn c ->
        ZIO.print_line("Recovered from a cause #{inspect(c)}") ~> ZIO.return(1)
      end,
      fn _ -> ZIO.return(0) end
    )
    |> assert_zio_success(1)
  end

  test "ensuring" do
    ZIO.fail("Failed!")
    |> ZIO.ensuring(ZIO.print_line("Ensuring"))
    |> ZIO.flat_map(ZIO.print_line("Should not see me"))
    |> assert_zio_failure(%ZIO.Cause.Fail{error: "Failed!"})
  end

  test "provide" do
    zio = ZIO.access_zio(fn n -> ZIO.return(n + 1) end)
    zio 
    |> ZIO.provide(1) 
    |> assert_zio_success(2)
  end

  test "provide with fail" do
    zio = ZIO.access_zio(fn n -> ZIO.return(n + 1) end)
    zio 
    |> ZIO.flat_map(fn _ -> ZIO.fail("Failed!") end)
    |> ZIO.provide(1) 
    |> assert_zio_failure(%ZIO.Cause.Fail{error: "Failed!"})
  end

  test "environment" do
    require ZIO

    zio =
      ZIO.m do
        env <- ZIO.environment()
        _ <- ZIO.print_line("Hello #{env}")
        return env
      end

    zio
    |> ZIO.provide("World")
    |> assert_zio_success("World")
  end

  test "access specific environment" do
    require ZIO

    zio =
      ZIO.m do
        env <- ZIO.environment(:http_client)
        _ <- ZIO.print_line("Hello #{env}")
        return env
      end

    zio
    |> ZIO.provide(Env.new(:http_client, "World"))
    |> assert_zio_success("World")
  end

  test "environment with failure" do
    require ZIO

    zio =
      ZIO.m do
        env <- ZIO.environment()
        _ <- ZIO.print_line("Hello #{env}")
        return env
      end

    zio
    |> assert_zio_failure(%ZIO.Cause.Die{throwable: %RuntimeError{message: "No environment provided"}})
  end

  test "filter" do
    [1,2,3]
    |> ZIO.filter(fn x -> ZIO.return(x > 1) end)
    |> assert_zio_success([2,3])
  end

  test "find" do
    [1,2,3,4,5,6]
    |> ZIO.find(fn x -> ZIO.return(x > 3) end)
    |> assert_zio_success(4)
  end

  test "each" do
    [1,2,3]
    |> ZIO.each(fn x -> ZIO.print_line(x) end)
    |> assert_zio_success(nil)
  end

  test "tap_error" do
    ZIO.fail("Failed!")
    |> ZIO.tap_error(fn e -> ZIO.print_line("Error: #{e}") end)
    |> assert_zio_failure(%ZIO.Cause.Fail{error: "Failed!"})
  end

  def assert_zio_success(zio, expected) do
    zio
    |> ZIO.run(fn v -> 
      assert v == ZIO.return(expected)
    end)
  end

  def assert_zio_failure(zio, expected) do
    zio
    |> ZIO.run(fn v -> 
      cause = v.e.()
      assert cause == expected
    end)
  end

  def assert_zio(zio, expected_zio) do
    zio
    |> ZIO.run(fn v -> 
      assert v == expected_zio
    end)
  end
end
