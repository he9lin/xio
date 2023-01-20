defmodule ZIO.Env do
  alias __MODULE__

  @enforce_keys [:env]
  defstruct [:env]

  @type t :: %__MODULE__{ env: map }

  def blank() do
    %__MODULE__{
      env: %{}
    }
  end

  @spec new(atom, module) :: t
  def new(key, value) when is_atom(key) do
    %Env{env: %{key => value}}
  end

  def new(map) when is_map(map) do
    %Env{env: map}
  end

  def put(%__MODULE__{env: env} = m, key, value) when is_atom(key) do
    %{ m | env: Map.put(env, key, value) }
  end

  def get(%__MODULE__{env: env}, key) when is_atom(key) do
    case Map.fetch(env, key) do
      {:ok, value} -> value
      :error -> raise "Dependency #{inspect key} not found"
    end
  end

  def merge(%__MODULE__{} = env_1, %__MODULE__{} = env_2) do
    %Env{env: Map.merge(env_1.env, env_2.env)}
  end

  def from_json(str) when is_binary(str) do
    str
    |> Jason.decode!()
    |> from_json()
  end

  def from_json(map) when is_map(map) do
    map
    |> Enum.reduce(blank(), fn {key, value}, acc ->
      put(acc, String.to_atom(key), Module.concat([value]))
    end)
  end

  defmodule Operators do
    @spec Env.t() <|> Env.t() :: Env.t()
    def %Env{env: env_1} <|> %Env{env: env_2} do
      %Env{env: Map.merge(env_1, env_2)}
    end
  end

  defimpl Jason.Encoder, for: __MODULE__ do
    alias ZIO.Env

    def encode(%Env{env: value}, opts) do
      Jason.Encode.map(value, opts)
    end
  end
end
