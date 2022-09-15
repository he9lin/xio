defmodule ZIO.Fiber do
  use GenServer

  defmodule FiberState do
    alias ZIO.Exit

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
