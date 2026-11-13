defmodule Flux.Auth.SSO.Domain do
  @moduledoc """
  An email domain claimed by a single sign-on configuration.

  A claim does nothing until it is verified by publishing a DNS TXT record. Only
  verified domains route sign-ins to an identity provider or let it vouch for a
  user, which stops one organization from claiming addresses another one owns.
  """

  @type t :: %__MODULE__{
          id: term(),
          domain: String.t(),
          txt_record_name: String.t(),
          txt_record_value: String.t(),
          verified_at: DateTime.t() | nil
        }

  defstruct [:id, :domain, :txt_record_name, :txt_record_value, :verified_at]

  @spec verified?(t()) :: boolean()
  def verified?(%__MODULE__{verified_at: nil}), do: false
  def verified?(%__MODULE__{}), do: true
end
