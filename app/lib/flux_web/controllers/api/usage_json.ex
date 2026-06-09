defmodule FluxWeb.API.UsageJSON do
  @moduledoc "JSON rendering for the usage-metering API."

  def show(%{usage: usage}) do
    %{data: usage(usage)}
  end

  defp usage(usage) do
    %{
      period: period(Map.get(usage, :period)),
      metrics: Map.get(usage, :metrics, %{}),
      quota: Map.get(usage, :quota, %{})
    }
  end

  defp period(nil), do: nil
  defp period(%{start: start_date, end: end_date}), do: %{start: start_date, end: end_date}
end
