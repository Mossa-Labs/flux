defmodule Flux.Pipeline.Steps.Script do
  @moduledoc """
  Script step for executing user-defined Lua transformations.

  The Lua script must define a `transform` function that takes a table
  and returns a transformed table:

  ```lua
  function transform(data)
    data.processed_at = os.time()
    return data
  end
  ```

  Config options:
  - `code`: Lua source code
  - `timeout_ms`: Execution timeout in milliseconds (default: 5000)

  Security:
  - File I/O disabled
  - Network access disabled
  - Limited to safe stdlib functions
  """

  @behaviour Flux.Pipeline.Step

  @default_timeout 5000

  @impl true
  def execute(data, config) when is_map(data) and is_map(config) do
    code = Map.get(config, "code")
    timeout = Map.get(config, "timeout_ms", @default_timeout)

    cond do
      is_nil(code) or code == "" ->
        {:error, "Script step requires 'code' in config"}

      true ->
        execute_lua(data, code, timeout)
    end
  end

  def execute(_data, _config) do
    {:error, "Invalid data or config format"}
  end

  defp execute_lua(data, code, timeout) do
    task =
      Task.async(fn ->
        try do
          run_lua(data, code)
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, "Script execution timed out after #{timeout}ms"}
    end
  end

  defp run_lua(data, code) do
    state = :luerl.init()

    state = restrict_stdlib(state)

    {lua_data, state} = :luerl.encode(data, state)
    {:ok, state} = :luerl.set_table_keys(["data"], lua_data, state)

    full_code = """
    #{code}
    return transform(data)
    """

    case :luerl.do(full_code, state) do
      {:ok, [result], new_state} ->
        {:ok, lua_to_elixir(:luerl.decode(result, new_state))}

      {:ok, [], _new_state} ->
        {:ok, data}

      {:lua_error, reason, _state} ->
        {:error, format_lua_error(reason)}

      {:error, reason, _state} ->
        {:error, format_lua_error(reason)}

      error ->
        {:error, "Lua execution failed: #{inspect(error)}"}
    end
  end

  defp restrict_stdlib(state) do
    dangerous_globals = [
      "io",
      "file",
      "loadfile",
      "dofile",
      "load",
      "require",
      "package"
    ]

    Enum.reduce(dangerous_globals, state, fn name, acc ->
      {:ok, new_acc} = :luerl.set_table_keys([name], nil, acc)
      new_acc
    end)
  end

  defp lua_to_elixir(data) when is_list(data) do
    if Keyword.keyword?(data) or table_like?(data) do
      data
      |> Enum.map(fn {k, v} -> {lua_key_to_elixir(k), lua_to_elixir(v)} end)
      |> Map.new()
    else
      Enum.map(data, &lua_to_elixir/1)
    end
  end

  defp lua_to_elixir(data) when is_binary(data), do: data
  defp lua_to_elixir(data) when is_number(data), do: data
  defp lua_to_elixir(data) when is_boolean(data), do: data
  defp lua_to_elixir(nil), do: nil
  defp lua_to_elixir(data), do: data

  defp lua_key_to_elixir(key) when is_binary(key), do: key
  defp lua_key_to_elixir(key) when is_number(key), do: to_string(trunc(key))
  defp lua_key_to_elixir(key), do: to_string(key)

  defp table_like?(list) do
    Enum.all?(list, fn
      {_, _} -> true
      _ -> false
    end)
  end

  defp format_lua_error({:lua_error, error, _stack}) do
    "Lua error: #{inspect(error)}"
  end

  defp format_lua_error(error) do
    "Lua error: #{inspect(error)}"
  end
end
