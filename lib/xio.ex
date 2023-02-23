defmodule ZIO do
  use Monad

  alias ZIO.{Cause, Exit, Stack}

  ## ADTs

  defmodule SucceedNow do
    defstruct [:value]
    @type t(value) :: %__MODULE__{value: value}
  end

  defmodule Suceeed do
    defstruct [:thunk]
    @type t :: %__MODULE__{thunk: term}
  end

  defmodule FlatMap do
    defstruct [:zio, :cont]
    @type t :: %__MODULE__{cont: term}
  end

  defmodule Fail do
    @type inner(error) :: (() -> Cause.t(error))

    defstruct [:e]
    @type t(error) :: %__MODULE__{e: inner(error)}
  end

  defmodule Fold do
    defstruct [:zio, :failure, :success]

    @type zio :: term
    @type failure(error) :: (Cause.t(error) -> zio)
    @type success(value) :: (term -> ZIO.io(value))

    @type t(error, value) :: %__MODULE__{zio: term, failure: failure(error), success: success(value)}
  end

  defmodule Provide do
    defstruct [:zio, :env]

    @type t(env) :: %__MODULE__{zio: term, env: env}
  end

  defmodule Access do
    @type env :: term
    @type zio :: term
    @type f :: (env -> zio)

    defstruct [:f]
    @type t :: %__MODULE__{f: f}
  end

  @type zio(env, error, value) :: SucceedNow.t(value) | Succeed.t | FlatMap.t | Fail.t(error) | Fold.t(error, value) | Provide.t(env) | Access.t
  @type uio(env, value) :: zio(env, any, value)
  @type io(value) :: uio(any, value)

  @type zio :: term
  @type error :: term

  ## Combinators

  def succeed_now(value) do
    %SucceedNow{value: value}
  end

  def return(value) do
    succeed_now(value)
  end

  def succeed(callback) do
    %Suceeed{thunk: callback}
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

  defmodule RetryStrategy do
    defstruct [:max_retries, :schedule, :retry_count, :on_errors]

    @type schedule_unit :: :milliseconds | :seconds | :minutes | :hours | :days
    @type schedule :: {:fixed, pos_integer, schedule_unit} | {:exponential, pos_integer, pos_integer, schedule_unit}

    def new(max_retries, schedule) do
      new(max_retries, schedule, [])
    end

    def new(max_retries, schedule, on_errors) do
      on_errors = List.wrap(on_errors)
      %__MODULE__{max_retries: max_retries, schedule: schedule, retry_count: 0, on_errors: on_errors}
    end

    def match_on_errors?(%__MODULE__{on_errors: []}, _error) do
      true
    end

    def match_on_errors?(%__MODULE__{on_errors: on_errors}, error) do
      case error do
        %{__struct__: struct} -> Enum.member?(on_errors, struct)
        error_msg when is_binary(error_msg) -> Enum.member?(on_errors, error_msg)
        _ -> false
      end
    end

    def exceeded?(%__MODULE__{max_retries: max_retries, retry_count: retry_count}) do
      retry_count >= max_retries
    end

    def increment(%__MODULE__{retry_count: retry_count} = strategy) do
      %__MODULE__{strategy | retry_count: retry_count + 1}
    end

    def next_delay(%__MODULE__{schedule: schedule, retry_count: retry_count}) do
      case schedule do
        {:exponential, base, rand, unit} ->
          base_seconds = round(:math.pow(2, retry_count + base))
          rand_seconds = :rand.uniform(rand)
          (base_seconds + rand_seconds) * to_milliseconds(unit)
        {:fixed, num, unit} -> 
          retry_count * num * to_milliseconds(unit)
      end
    end

    defp to_milliseconds(unit) do
      case unit do
        :milliseconds -> 1
        :seconds -> 1000
        :minutes -> 60 * 1000
        :hours -> 60 * 60 * 1000
        :days -> 24 * 60 * 60 * 1000
      end
    end
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
      f.(item) |> ZIO.flat_map(fn x ->
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

  def run(xio, callback) do
    state = %State{
      stack: [],
      env_stack: [],
      current_zio: xio,
      loop: true,
      callback: callback,
      result: nil
    }

    resume(state)
  end

  def run_zio(xio) do
    case run(xio, fn x -> x end) do
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

  defp resume(%State{loop: false, result: result}) do
    result
  end

  defp resume(%State{current_zio: current_zio, stack: stack, env_stack: env_stack} = state) do
    state =
      try do
        case current_zio do
          %SucceedNow{value: value} ->
            continue(state, value)

          %Suceeed{thunk: thunk} ->
            continue(state, thunk.())

          %FlatMap{zio: zio, cont: cont} ->
            stack = Stack.push(stack, cont)
            %State{state | stack: stack, current_zio: zio}

          %Fold{zio: zio, failure: _failure, success: _success} = fold ->
            stack = Stack.push(stack, fold)
            %{state | stack: stack, current_zio: zio}

          %Fail{e: e} ->
            with_error_handler(state, e)

          %Provide{zio: zio, env: env} ->
            env_stack = Stack.push(env_stack, env)
             
            ensuring_zio = succeed(fn -> 
              { env, _env_stack } = Stack.pop(env_stack) 
              env
            end)

            current_zio =  zio |> ensuring(ensuring_zio)
            %{state | env_stack: env_stack, current_zio: current_zio}

          %Access{f: f} ->
            case env_stack do
              [head | _] ->
                current_zio = f.(head)
                %{state | current_zio: current_zio}
              _ ->
                raise "No environment provided"
            end
        end
      rescue
        e in ExUnit.AssertionError ->
          raise e
        e ->
          if Enum.empty?(stack) do
            raise e
          else
            %{state | current_zio: die(e)}
          end
      end

    resume(state)
  end

  defp continue(%State{stack: stack, callback: callback} = state, value) do
    if Enum.empty?(stack) do
      result = Exit.succeed(value)
      complete(callback, result)
      %{state | loop: false, result: result}
    else
      # cont can be a Fold or (any -> zio)
      [cont | rest] = stack
      case cont do
        %Fold{} ->
          %{state | stack: rest, current_zio: cont.success.(value)}

        _ ->
          %{state | stack: rest, current_zio: cont.(value)}
      end
    end
  end

  defp complete(callback, exit) do
    callback.(ZIO.done(exit))
  end

  defp with_error_handler(%State{stack: stack, callback: callback} = state, e) do
    case Stack.pop(stack) do
      {nil, []} ->
        result = %Exit.Failure{cause: e.()}
        complete(callback, result)
        %{state | loop: false, result: result}

      {%Fold{} = error_handler, stack} ->
        %{state | stack: stack, current_zio: error_handler.failure.(e.())}

      {_, stack} ->
        with_error_handler(%{state | stack: stack}, e)
    end
  end
end
