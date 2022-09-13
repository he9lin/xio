defmodule ZIO do
  defmodule Succeed do
    defstruct [:value]
    @type t :: %__MODULE__{value: term}
  end

  defmodule Effect do
    defstruct [:thunk]
    @type t :: %__MODULE__{thunk: term}
  end

  defmodule FlatMap do
    defstruct [:zio, :cont]
    @type t :: %__MODULE__{cont: term}
  end

  defmodule Async do
    defstruct [:register]

    # (A => Any) => Any
    @type t :: %__MODULE__{register: term}
  end

  defmodule Fork do
    defstruct [:zio]
    @type t :: %__MODULE__{zio: term}
  end

  defmodule Fiber do
    use GenServer

    defmodule State do
      defstruct [:maybe_result, :callbacks]
    end

    def start_link(state \\ %State{maybe_result: nil, callbacks: []}) do
      GenServer.start_link(__MODULE__, state)
    end

    def init(state), do: {:ok, state}

    def handle_cast({:add_callback, callback}, state) do
      {:noreply, %State{state | callbacks: state.callbacks ++ [callback]}}
    end

    def handle_cast({:set_maybe_result, res}, state) do
      {:noreply, %State{state | maybe_result: res}}
    end

    def handle_call(:callbacks, _from, state) do
      {:reply, state.callbacks, state}
    end

    def handle_call(:maybe_result, _from, state) do
      {:reply, state.maybe_result, state}
    end

    defstruct [:zio, :pid, :task]

    def start(zio) do
      {:ok, pid} = start_link()

      task = Task.async(fn ->
        ZIO.run(zio, fn x ->
          GenServer.cast(pid, {:set_maybe_result, x})
          callbacks = GenServer.call(pid, :callbacks)

          callbacks
          |> Enum.each(fn callback -> callback.(x) end)
        end)
      end)

      %__MODULE__{zio: zio, pid: pid, task: task}
    end

    def join(%__MODULE__{pid: pid, task: task}) do
      Task.await(task)
      maybe_result = GenServer.call(pid, :maybe_result)
      case maybe_result do
        nil ->
          ZIO.async(fn complete ->
            GenServer.cast(pid, {:add_callback, complete})
          end)

        x ->
          Process.exit(pid, :normal)
          ZIO.succeed_now(x)
      end
    end
  end

  use Monad

  def succeed_now(value) do
    %Succeed{value: value}
  end

  def return(value) do
    succeed_now(value)
  end

  def succeed(callback) do
    %Effect{thunk: callback}
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
    zip_with(zio1, zio2, fn x1, x2 -> {x1, x2} end)
  end

  def repeat(zio, n) do
    if n == 0 do
      succeed_now(nil)
    else
      zip_with(zio, repeat(zio, n - 1), fn _, _ -> nil end)
    end
  end

  def print_line(message) do
    succeed(fn -> IO.puts(message) end)
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

    run_loop(state)
  end

  defp run_loop(%State{loop: false}) do
    :ok
  end

  defp run_loop(%State{current_zio: current_zio, stack: stack, callback: callback} = state) do
    state =
      case current_zio do
        %Succeed{value: value} ->
          complete(state, value)

        %Effect{thunk: thunk} ->
          value = thunk.()
          complete(state, value)

        %FlatMap{zio: zio, cont: cont} ->
          stack = List.insert_at(stack, 0, cont)
          %State{state | stack: stack, current_zio: zio}

        %Async{register: register} ->
          if Enum.empty?(stack) do
            register.(callback)
            %{state | loop: false}
          else
            register.(fn a ->
              current_zio = succeed_now(a)

              run_loop(%State{state | current_zio: current_zio, loop: true})
            end)

            %{state | loop: false}
          end

        %Fork{zio: zio} ->
          fiber = Fiber.start(zio)
          complete(state, fiber)
      end

    run_loop(state)
  end

  defp complete(%State{stack: stack, callback: callback} = state, value) do
    if Enum.empty?(stack) do
      callback.(value)
      %{state | loop: false}
    else
      [cont | rest] = stack
      current_zio = cont.(value)
      %{state | stack: rest, current_zio: current_zio}
    end
  end
end
