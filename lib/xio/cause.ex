defmodule ZIO.Cause do
  defmodule Fail do
    @derive Jason.Encoder
    @enforce_keys [:error]
    defstruct [:error]

    @type t(error) :: %__MODULE__{error: error}
  end

  defmodule Die do
    @derive Jason.Encoder
    @enforce_keys [:throwable]
    defstruct [:throwable]

    @type t :: %__MODULE__{throwable: term}
  end

  defmodule Interrupt do
    defstruct []

    @type t :: %__MODULE__{}
  end

  def die(throwable), do: %Die{throwable: throwable}
  def fail(error), do: %Fail{error: error}
  def interrupt(), do: %Interrupt{}

  @type t(error) :: Fail.t(error) | Die.t() | Interrupt.t()
end
