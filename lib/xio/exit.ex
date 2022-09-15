defmodule ZIO.Exit do
  alias ZIO.Cause

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
