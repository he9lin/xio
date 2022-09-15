defmodule ZIO.Cause do
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
