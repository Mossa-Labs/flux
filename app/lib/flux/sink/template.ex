defmodule Flux.Sink.Template do
  @moduledoc """
  `{field}` interpolation for sink templates (email subjects and bodies, file
  names, message text).

  A placeholder is a dot-path into the record being delivered:

      iex> Flux.Sink.Template.interpolate("Order {order.id} is {status}", %{
      ...>   "order" => %{"id" => 42},
      ...>   "status" => "late"
      ...> })
      "Order 42 is late"

  Values render as text: strings as-is, numbers and booleans via `to_string/1`,
  maps and lists as JSON. A path that resolves to nothing renders as an empty
  string. Text that is not a well-formed placeholder (`{ }`, `{a b}`) is left
  alone, so templates can contain literal braces.

  The template itself is trusted — an operator wrote it — but the record is
  not, so the context-specific variants escape what they substitute:

    * `interpolate_html/2` HTML-escapes every value.
    * `interpolate_header/2` collapses line breaks, so a value cannot add a mail
      header.
  """

  @placeholder ~r/\{([A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)*)\}/

  @doc "Interpolates `{dot.path}` placeholders with values from `data`."
  @spec interpolate(String.t(), map()) :: String.t()
  def interpolate(template, data) when is_binary(template) do
    Regex.replace(@placeholder, template, fn _match, path -> data |> fetch(path) |> render() end)
  end

  @doc """
  Like `interpolate/2`, but HTML-escapes each substituted value. The template's
  own markup passes through untouched.
  """
  @spec interpolate_html(String.t(), map()) :: String.t()
  def interpolate_html(template, data) when is_binary(template) do
    Regex.replace(@placeholder, template, fn _match, path ->
      data
      |> fetch(path)
      |> render()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
    end)
  end

  @doc """
  Like `interpolate/2`, for a single-line header such as an email subject: line
  breaks and other control characters — in the substituted values *and* the
  template — become spaces, and runs of whitespace collapse.
  """
  @spec interpolate_header(String.t(), map()) :: String.t()
  def interpolate_header(template, data) when is_binary(template) do
    template
    |> interpolate(data)
    |> String.replace(~r/[\x00-\x1F\x7F]+/, " ")
    |> String.replace(~r/\s{2,}/, " ")
    |> String.trim()
  end

  defp fetch(data, path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(data, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  defp render(nil), do: ""
  defp render(value) when is_binary(value), do: value
  defp render(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp render(value) when is_atom(value), do: Atom.to_string(value)

  defp render(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end
end
