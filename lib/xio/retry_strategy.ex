defmodule ZIO.RetryStrategy do
  defstruct [:max_retries, :schedule, :retry_count, :on_errors]

  @type schedule_unit :: :milliseconds | :seconds | :minutes | :hours | :days
  @type schedule ::
          {:fixed, pos_integer, schedule_unit}
          | {:exponential, pos_integer, pos_integer, schedule_unit}

  def new(max_retries, schedule) do
    new(max_retries, schedule, [])
  end

  def new(max_retries, schedule, on_errors) when is_function(on_errors, 1) do
    %__MODULE__{
      max_retries: max_retries,
      schedule: schedule,
      retry_count: 0,
      on_errors: on_errors
    }
  end

  def new(max_retries, schedule, on_errors) do
    %__MODULE__{
      max_retries: max_retries,
      schedule: schedule,
      retry_count: 0,
      on_errors: List.wrap(on_errors)
    }
  end

  def match_on_errors?(%__MODULE__{on_errors: []}, _error) do
    true
  end

  def match_on_errors?(%__MODULE__{on_errors: on_errors}, error) when is_list(on_errors) do
    case error do
      %{__struct__: struct} -> Enum.member?(on_errors, struct)
      error_msg when is_binary(error_msg) -> Enum.member?(on_errors, error_msg)
      _ -> false
    end
  end

  def match_on_errors?(%__MODULE__{on_errors: on_errors}, error)
      when is_function(on_errors, 1) do
    on_errors.(error)
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
