defmodule FluxWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # Request body exceeded the 10 MB cap (MOS-450). Mirror the API error shape
  # ({error, message}) used by FallbackController / the limiter responses.
  def render("413.json", _assigns) do
    %{error: "payload_too_large", message: "Request body exceeds the 10 MB limit."}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
