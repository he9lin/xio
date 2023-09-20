defmodule ZIO.FiberRuntime do
  use GenServer

  alias ZIO.Stack

  @enforce_keys [:stack, :env_stack, :current_zio, :loop, :observers, :result]
  defstruct [:stack, :env_stack, :current_zio, :loop, :observers, :result]

  def start_link() do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_) do
    state = %__MODULE__{
      stack: [],
      env_stack: [],
      current_zio: nil,
      loop: true,
      observers: [],
      result: nil
    }

    {:ok, state}
  end

  def start(pid, zio) do
    GenServer.cast(pid, {:update_current_zio, zio})

    task = Task.async(fn ->
      run_loop(pid)
    end)

    {pid, task}
  end

  def add_observer(pid, observer) do
    GenServer.cast(pid, {:add_observer, observer})
  end

  def resume(pid, zio) do
    GenServer.cast(pid, {:resume, zio})
    run_loop(pid)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def update_state(pid, state) do
    GenServer.cast(pid, {:update_state, state})
  end

  def await(pid) do
    ZIO.async(fn register ->
      #dbg("Try add observer")
      add_observer(pid, fn exit ->
        #dbg("exit: #{inspect exit}")
        register.(ZIO.succeed(fn -> exit end))
      end)
    end)
  end

  def join({pid, task}) do
    #dbg("join task #{inspect task} with pid #{inspect pid}")
    await(pid) |> ZIO.flat_map(&ZIO.done/1)
  end

  def handle_cast({:update_current_zio, zio}, state) do
    {:noreply, %{state | current_zio: zio}}
  end

  def handle_cast({:add_observer, observer}, state) do
    if is_nil(state.result) do
      new_observers = state.observers ++ [observer]
      new_state = %{state | observers: new_observers}
      #dbg("ADD OBSERVER (#{inspect self()})=> state: #{inspect new_state}")
      {:noreply, new_state}
    else
      observer.(state.result)
      {:noreply, state}
    end
  end

  def handle_cast({:resume, zio}, state) do
    if is_nil(state.result) do
      state = %{state | current_zio: zio, loop: true}
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:update_state, state}, _state) do
    {:noreply, state}
  end

  def handle_cast(:start, state) do
    run_loop(self(), state)

    {:noreply, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def run_loop(pid, %__MODULE__{loop: false, result: result, current_zio: current_zio}) do
    #dbg("STOPPED LOOP on (#{inspect pid}) with result: #{inspect result} AND current_zio: #{inspect current_zio}")
    # Process.exit(pid, :normal)
    nil
  end

  def run_loop(pid, %__MODULE__{stack: stack, current_zio: current_zio} = state) do
    #dbg("current_zio (#{inspect pid}): #{inspect current_zio}")
    try do
      case current_zio do
        %ZIO.Succeed{thunk: thunk} ->
          continue(pid, state, thunk.())

        %ZIO.SucceedNow{value: value} ->
          continue(pid, state, value)

        %ZIO.FlatMap{zio: zio, cont: cont} ->
          stack = Stack.push(stack, cont)
          update_state(pid, %{state | stack: stack, current_zio: zio})

        %ZIO.Async{register: register} ->
          register.(fn zio ->
            #dbg("RESUMING with zio: #{inspect zio}")
            resume(pid, zio)
          end)
          update_state(pid, %{state | current_zio: nil, loop: false})

        %ZIO.Fold{zio: zio, failure: _failure, success: _success} = fold ->
          stack = Stack.push(stack, fold)
          update_state(pid, %{state | stack: stack, current_zio: zio})

        %ZIO.Fail{e: e} ->
          with_error_handler(pid, state, e)
      end
    rescue
      e in [ExUnit.AssertionError] ->
        raise e

      e ->
        if Enum.empty?(stack) do
          raise e
        else
          #dbg(e)
          # TODO: Add stack information
          update_state(pid, %{state | current_zio: ZIO.die(e)})
        end
    end

    run_loop(pid)
  end

  def run_loop(pid) do
    state = get_state(pid)
    run_loop(pid, state)
  end

  defp continue(pid, %__MODULE__{stack: _stack, observers: _observers} = _state, a) do
    %__MODULE__{stack: stack, observers: observers} = state = get_state(pid)

    case stack do
      [] ->
        #dbg("COMPLETED LOOP #{inspect pid}: notify obervers and set loop to false")
        #dbg("OBSERVERS: #{inspect observers}")

        result = ZIO.Exit.succeed(a)
        #dbg("EXIT RESULT: #{inspect result}")
        observers |> Enum.each(fn observer -> observer.(result) end)

        new_state = %{state | loop: false, result: result, observers: []}
        update_state(pid, new_state)

      [cont | rest] ->
        # cont can be a Fold or (any -> zio)
        # will refactor with Continuation
        new_state =
          case cont do
            %ZIO.Fold{} ->
              %{state | stack: rest, current_zio: cont.success.(a)}

            _ ->
              %{state | stack: rest, current_zio: cont.(a)}
          end

        update_state(pid, new_state)
    end
  end

  defp with_error_handler(pid, %{stack: stack, observers: observers} = state, e) do
    case Stack.pop(stack) do
      {nil, []} ->
        result = %ZIO.Exit.Failure{cause: e.()}
        observers |> Enum.each(fn observer -> observer.(result) end)
        update_state(pid, %{state | stack: [], loop: false, result: result, observers: []})

      {%ZIO.Fold{} = error_handler, stack} ->
        zio = error_handler.failure.(e.())
        update_state(pid, %{state | stack: stack, current_zio: zio})

      {_, stack} ->
        new_state = %{state | stack: stack}
        update_state(pid, new_state)
        with_error_handler(pid, new_state, e)
    end
  end
end
