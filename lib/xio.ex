defmodule ZIO do
  use Monad

  @type zio :: term
  @type error :: term

  defmodule Cause do
    defmodule Fail do
      defstruct [:error]
      @type t :: %__MODULE__{error: term}
    end

    defmodule Die do
      defstruct [:throwable]
      @type t :: %__MODULE__{throwable: term}
    end

    defmodule Interrupt do
      defstruct []
      @type t :: %__MODULE__{}
    end

    def die(throwable), do: %Die{throwable: throwable}
    def fail(error), do: %Fail{error: error}

    @type t :: Fail.t() | Die.t() | Interrupt.t()
  end

  defmodule Exit do
    defmodule Success do
      defstruct [:value]
      @type t :: %__MODULE__{value: term}
    end

    defmodule Failure do
      defstruct [:cause]
      @type t :: %__MODULE__{cause: Cause.t()}
    end

    def succeed(value) do
      %Success{value: value}
    end

    def fail(error) do
      %Failure{cause: %Cause.Fail{error: error}}
    end

    def die(throwable) do
      %Failure{cause: %Cause.Die{throwable: throwable}}
    end
  end

  defmodule SucceedNow do
    defstruct [:value]
    @type t :: %__MODULE__{value: term}
  end

  defmodule Suceeed do
    defstruct [:thunk]
    @type t :: %__MODULE__{thunk: term}
  end

  defmodule FlatMap do
    defstruct [:zio, :cont]
    @type t :: %__MODULE__{cont: term}
  end

  defmodule Async do
    defstruct [:register]

    @type register :: ((any -> any) -> any)
    @type t :: %__MODULE__{register: register}
  end

  defmodule Fork do
    defstruct [:zio]
    @type t :: %__MODULE__{zio: term}
  end

  defmodule Fail do
    @type e :: (() -> Cause.t())

    defstruct [:e]
    @type t :: %__MODULE__{e: e}
  end

  defmodule Fold do
    defstruct [:zio, :failure, :success]

    @type zio :: term
    @type failure :: (Cause.t() -> zio)
    @type success :: (term -> zio)

    @type t :: %__MODULE__{zio: term, failure: failure, success: success}
  end

  defmodule Provide do
    defstruct [:zio, :env]
  end

  defmodule Access do
    @type env :: term
    @type zio :: term
    @type f :: (env -> zio)

    defstruct [:f]
    @type t :: %__MODULE__{f: f}
  end

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

  def async(register) do
    %Async{register: register}
  end

  def fork(zio) do
    %Fork{zio: zio}
  end

  def bind(zio, cont) do
    flat_map(zio, cont)
  end

  def map(zio, f) do
    flat_map(zio, fn x -> succeed_now(f.(x)) end)
  end

  def as(zio, value) do
    map(zio, fn _ -> value end)
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

  defmodule Operator do
    def zio1 ~> zio2 do
      ZIO.zip_right(zio1, zio2)
    end
  end

  def zip(zio1, zio2) do
    zip_with(zio1, zio2, fn x1, x2 -> ZIO.Zippable.zip(x1, x2) end)
  end

  def repeat(zio, n) do
    if n == 0 do
      succeed_now(nil)
    else
      zip_with(zio, repeat(zio, n - 1), fn _, _ -> nil end)
    end
  end

  def provide(zio, env) do
    %Provide{zio: zio, env: env}
  end

  def print_line(message) do
    succeed(fn -> IO.puts(message) end)
  end

  defmodule Fiber do
    use GenServer

    defmodule FiberState do
      defmodule Done do
        defstruct [:exit]
        @type t :: %__MODULE__{exit: Exit.t()}
      end

      defmodule Running do
        @type callback :: (Exit.t() -> any)

        defstruct [:callbacks]
        @type t :: %__MODULE__{callbacks: [callback]}
      end

      @type t :: Done.t() | Running.t()
    end

    alias FiberState.{Done, Running}

    def start_link(state \\ %Running{callbacks: []}) do
      GenServer.start_link(__MODULE__, state)
    end

    def init(state), do: {:ok, state}

    def handle_cast({:add_callback, callback}, state) do
      {:noreply, %{state | callbacks: state.callbacks ++ [callback]}}
    end

    def handle_cast({:set_state, state}, _state) do
      {:noreply, state}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    defstruct [:zio, :pid, :task]

    def start(zio) do
      {:ok, pid} = start_link()

      task =
        Task.async(fn ->
          ZIO.run(zio, fn exit ->
            %Running{callbacks: callbacks} = GenServer.call(pid, :get_state)
            GenServer.cast(pid, {:set_state, %Done{exit: exit}})
            callbacks
            |> Enum.each(fn callback -> callback.(exit) end)
          end)
        end)

      %__MODULE__{zio: zio, pid: pid, task: task}
    end

    def await(%__MODULE__{pid: pid, task: task}, continue) do
      Task.await(task)
      state = GenServer.call(pid, :get_state)

      case state do
        %Done{exit: exit} ->
          Process.exit(pid, :normal)
          continue.(exit)

        %Running{} ->
          GenServer.cast(pid, {:add_callback, continue})
      end
    end

    def join(%__MODULE__{} = fiber) do
      ZIO.async(fn continue ->
        await(fiber, continue)
      end)
      |> ZIO.flat_map(&ZIO.done/1)
    end
  end

  defmodule State do
    @enforce_keys [:stack, :current_zio, :loop, :callback]
    defstruct stack: [], current_zio: nil, loop: true, callback: nil
  end

  def run(xio, callback) do
    state = %State{
      stack: [],
      current_zio: xio,
      loop: true,
      callback: callback
    }

    resume(state)
  end

  defp resume(%State{loop: false}) do
    :ok
  end

  defp resume(%State{current_zio: current_zio, stack: stack, callback: callback} = state) do
    state =
      try do
        case current_zio do
          %SucceedNow{value: value} ->
            continue(state, value)

          %Suceeed{thunk: thunk} ->
            continue(state, thunk.())

          %FlatMap{zio: zio, cont: cont} ->
            stack = push_stack(stack, cont)
            %State{state | stack: stack, current_zio: zio}

          %Async{register: register} ->
            if Enum.empty?(stack) do
              register.(fn a ->
                complete(callback, Exit.succeed(a))
              end)

              %{state | loop: false}
            else
              register.(fn a ->
                current_zio = succeed_now(a)

                %State{state | current_zio: current_zio, loop: true}
                |> resume()
              end)

              %{state | loop: false}
            end

          %Fork{zio: zio} ->
            fiber = Fiber.start(zio)
            continue(state, fiber)

          %Fold{zio: zio, failure: _failure, success: _success} = fold ->
            stack = push_stack(stack, fold)
            %{state | stack: stack, current_zio: zio}

          %Fail{e: e} ->
            with_error_handler(state, e)
        end
      rescue
        e ->
          %{state | current_zio: die(e)}
      end

    resume(state)
  end

  def with_error_handler(%State{stack: stack, callback: callback} = state, e) do
    case pop_stack(stack) do
      {nil, []} ->
        complete(callback, %Exit.Failure{cause: e.()})
        %{state | loop: false}

      {%Fold{} = error_handler, stack} ->
        %{state | stack: stack, current_zio: error_handler.failure.(e.())}

      {_, stack} ->
        with_error_handler(%{state | stack: stack}, e)
    end
  end

  # Cont: Any => ZIO
  defp continue(%State{stack: stack, callback: callback} = state, value) do
    if Enum.empty?(stack) do
      complete(callback, Exit.succeed(value))
      %{state | loop: false}
    else
      [cont | rest] = stack
      current_zio = cont.(value)
      %{state | stack: rest, current_zio: current_zio}
    end
  end

  defp complete(callback, exit) do
    callback.(exit)
  end

  defp push_stack(stack, value) do
    List.insert_at(stack, 0, value)
  end

  defp pop_stack([cont | rest]) do
    {cont, rest}
  end

  defp pop_stack([]) do
    {nil, []}
  end
end
