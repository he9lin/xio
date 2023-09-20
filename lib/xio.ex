defmodule ZIO do
  use Monad

  alias ZIO.{Cause, Exit, RetryStrategy}

  ## ADTs

  defmodule SucceedNow do
    @enforce_keys [:value]
    defstruct [:value]

    @type t(value) :: %__MODULE__{value: value}
  end

  defmodule Succeed do
    @enforce_keys [:thunk]
    defstruct [:thunk]

    @type t :: %__MODULE__{thunk: fun()}
  end

  defmodule FlatMap do
    @enforce_keys [:zio, :cont]
    defstruct [:zio, :cont]

    @type cont :: (term -> ZIO.zio())

    @type t :: %__MODULE__{zio: ZIO.zio(), cont: cont}
  end

  defmodule Fail do
    @type inner(error) :: (-> Cause.t(error))

    @enforce_keys [:e]
    defstruct [:e]
    @type t(error) :: %__MODULE__{e: inner(error)}
  end

  defmodule Fold do
    @enforce_keys [:zio, :failure, :success]
    defstruct [:zio, :failure, :success]

    @type failure(error) :: (Cause.t(error) -> ZIO.zio())
    @type success(value) :: (term -> ZIO.io(value))

    @type t(error, value) :: %__MODULE__{
            zio: ZIO.zio(),
            failure: failure(error),
            success: success(value)
          }
  end

  defmodule Provide do
    @enforce_keys [:zio, :env]
    defstruct [:zio, :env]

    @type t(env) :: %__MODULE__{zio: ZIO.zio(), env: env}
  end

  defmodule Access do
    @type env :: term
    @type f :: (env -> ZIO.zio())

    @enforce_keys [:f]
    defstruct [:f]
    @type t :: %__MODULE__{f: f}
  end

  defmodule Async do
    @enforce_keys [:register]
    defstruct [:register]

    @type register :: ((ZIO.zio() -> any) -> any)
    @type t :: %__MODULE__{register: register}
  end

  defmodule Fork do
    @enforce_keys [:zio]
    defstruct [:zio]

    @type t :: %__MODULE__{zio: ZIO.zio()}
  end

  @type zio(env, error, value) ::
          SucceedNow.t(value)
          | Succeed.t()
          | FlatMap.t()
          | Fail.t(error)
          | Fold.t(error, value)
          | Provide.t(env)
          | Access.t()
          | Async.t()
          | Fork.t()
  @type uio(env, value) :: zio(env, any, value)
  @type io(value) :: uio(any, value)
  @type zio :: io(any)

  @type error :: term

  ## Combinators

  def succeed_now(value) do
    %SucceedNow{value: value}
  end

  def return(value) do
    succeed_now(value)
  end

  def succeed(callback) when is_function(callback) do
    %Succeed{thunk: callback}
  end

  def flat_map(zio, cont) do
    %FlatMap{zio: zio, cont: cont}
  end

  def access_zio(f) do
    %Access{f: f}
  end

  def environment() do
    access_zio(fn env -> succeed_now(env) end)
  end

  def environment(dep_key) do
    access_zio(fn env ->
      specific_env = ZIO.Env.get(env, dep_key)
      succeed_now(specific_env)
    end)
  end

  def provide(zio, env) do
    %Provide{zio: zio, env: env}
  end

  def bind(zio, cont) do
    flat_map(zio, cont)
  end

  def map(zio, f) do
    flat_map(zio, fn x -> succeed_now(f.(x)) end)
  end

  def map_error(zio, f) do
    fold_zio(zio, fn cause -> fail(f.(cause)) end, fn x -> succeed_now(x) end)
  end

  def as(zio, value) do
    map(zio, fn _ -> value end)
  end

  def from_either({:ok, value}) do
    succeed_now(value)
  end

  def from_either({:error, error}) do
    fail(error)
  end

  @spec fold_cause_zio(zio, (Cause.t() -> zio), (term -> zio)) :: zio
  def fold_cause_zio(zio, failure, success) do
    %Fold{zio: zio, failure: failure, success: success}
  end

  @spec fold_zio(zio, (error -> zio), (term -> zio)) :: zio
  def fold_zio(zio, failure, success) do
    failure = fn failure_cause ->
      case failure_cause do
        %Cause.Fail{error: error} -> failure.(error)
        %Cause.Die{throwable: throwable} -> fail_cause(Cause.die(throwable))
      end
    end

    fold_cause_zio(
      zio,
      failure,
      success
    )
  end

  def handle_error(zio, f) do
    fold_zio(zio, f, fn x -> succeed_now(x) end)
  end

  def fail_cause(cause) do
    %Fail{e: fn -> cause end}
  end

  def fail(e) do
    fail_cause(%Cause.Fail{error: e})
  end

  def die(e) do
    fail_cause(%Cause.Die{throwable: e})
  end

  def done(%Exit.Success{value: value}) do
    succeed_now(value)
  end

  def done(%Exit.Failure{cause: cause}) do
    fail_cause(cause)
  end

  def fold(zio, failure, success) do
    fold_zio(
      zio,
      fn e -> succeed_now(failure.(e)) end,
      fn x -> succeed_now(success.(x)) end
    )
  end

  def catch_all(zio, handler) do
    fold_zio(
      zio,
      fn e -> handler.(e) end,
      fn x -> succeed_now(x) end
    )
  end

  def ensuring(zio, finalizer) do
    fold_cause_zio(
      zio,
      fn cause -> finalizer |> zip_right(fail_cause(cause)) end,
      fn x -> finalizer |> zip_right(succeed_now(x)) end
    )
  end

  def zip_with(zio1, zio2, f) do
    flat_map(zio1, fn x1 ->
      flat_map(zio2, fn x2 ->
        succeed_now(f.(x1, x2))
      end)
    end)
  end

  def zip_right(zio1, zio2) do
    zip_with(zio1, zio2, fn _, x2 -> x2 end)
  end

  def zip(zio1, zio2) do
    zip_with(zio1, zio2, fn x1, x2 -> ZIO.Zippable.zip(x1, x2) end)
  end

  def each(list, f) do
    list
    |> Enum.reverse()
    |> Enum.reduce(succeed_now(nil), fn x, acc ->
      zip_right(f.(x), acc)
    end)
  end

  def collect(list, f) do
    list
    |> Enum.reverse()
    |> Enum.reduce(succeed_now([]), fn x, acc ->
      zip_with(f.(x), acc, fn x, acc -> [x | acc] end)
    end)
  end

  def tap_error(zio, f) do
    fold_zio(zio, fn e -> f.(e) |> zip_right(fail(e)) end, fn x -> succeed_now(x) end)
  end

  def repeat(zio, n) do
    if n == 0 do
      succeed_now(nil)
    else
      zip_with(zio, repeat(zio, n - 1), fn _, _ -> nil end)
    end
  end

  def delay(zio, milliseconds) do
    succeed(fn ->
      :timer.sleep(milliseconds)
      :ok
    end)
    |> zip_right(zio)
  end

  def async(register) do
    %Async{register: register}
  end

  def fork(zio) do
    ZIO.succeed(fn ->
      {:ok, pid} = ZIO.FiberRuntime.start_link()
      ZIO.FiberRuntime.start(pid, zio)
    end)
  end

  def retry(zio, %RetryStrategy{} = rs) do
    fold_zio(
      zio,
      fn e ->
        if RetryStrategy.exceeded?(rs) || !RetryStrategy.match_on_errors?(rs, e) do
          fail(e)
        else
          rs = RetryStrategy.increment(rs)
          delay_duration = RetryStrategy.next_delay(rs)

          zio
          |> retry(rs)
          |> delay(delay_duration)
        end
      end,
      fn x -> succeed_now(x) end
    )
  end

  def filter(list, f) do
    list
    |> Enum.reverse()
    |> Enum.reduce(succeed_now([]), fn item, acc ->
      zip_with(f.(item), acc, fn x, acc ->
        if x do
          [item | acc]
        else
          acc
        end
      end)
    end)
  end

  def find(list, f) do
    index = 0
    loop(list, index, f)
  end

  def loop(list, index, f) do
    length = Enum.count(list)

    if index < length do
      item = Enum.at(list, index)

      f.(item)
      |> ZIO.flat_map(fn x ->
        if x do
          succeed_now(item)
        else
          loop(list, index + 1, f)
        end
      end)
    else
      succeed_now(nil)
    end
  end

  def print_line(message) do
    succeed(fn -> IO.puts(message) end)
  end

  defmodule State do
    @enforce_keys [:stack, :env_stack, :current_zio, :loop, :callback, :result]
    defstruct [:stack, :env_stack, :current_zio, :loop, :callback, :result]
  end

  # unsafeRunAsync

  def unsafe_run_async(zio) do
    {:ok, pid} = ZIO.FiberRuntime.start_link()
    ZIO.FiberRuntime.start(pid, zio)
  end

  def unsafe_run_sync(zio) do
    {:ok, pid} = ZIO.FiberRuntime.start_link()

    result_pid = self()

    final_zio =
      zio
      |> fold_cause_zio(
        fn cause ->
          ZIO.succeed(fn ->
            send(result_pid, {:result, %ZIO.Exit.Failure{cause: cause}})
          end)
        end,
        fn value ->
          ZIO.succeed(fn ->
            send(result_pid, {:result, %ZIO.Exit.Success{value: value}})
          end)
        end
      )

    ZIO.FiberRuntime.start(pid, final_zio)

    receive do
      {:result, result} ->
        result
    end
  end

  # A FiberRuntime takes zio and run
  def run_zio(zio) do
    case unsafe_run_sync(zio) do
      %ZIO.Exit.Success{value: value} -> {:ok, value}
      %ZIO.Exit.Failure{cause: cause} -> {:error, cause}
    end
  end

  def run_with(zio, %ZIO.Env{} = env) do
    zio
    |> provide(env)
    |> run_zio()
  end

  def run_with(zio, %{__struct__: _} = struct) do
    env =
      struct
      |> Map.from_struct()
      |> ZIO.Env.new()

    run_with(zio, env)
  end

  def run_with(zio, map) do
    env =
      map
      |> Enum.into(%{})
      |> ZIO.Env.new()

    run_with(zio, env)
  end
end
