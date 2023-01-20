defmodule ZIO.Cause do
  defmodule Fail do
    @derive Jason.Encoder
    defstruct [:error]
    @type t(error) :: %__MODULE__{error: error}
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

  @type t(error) :: Fail.t(error) | Die.t() | Interrupt.t()
end
