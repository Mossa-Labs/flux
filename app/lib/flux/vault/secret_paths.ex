defmodule Flux.Vault.SecretPaths do
  @moduledoc """
  Behaviour for a taxonomy of secret locations within a JSONB config column.

  An implementation names *where* the secrets sit in a given value. The same
  paths drive encryption at rest (`Flux.Vault.EncryptedConfig`) and the
  redaction layer that masks the value on the way out, so a value is only ever
  decrypted at a location that is also masked.

  Each path is a list usable with `get_in/2` and `put_in/3`: string keys, or
  `Access.at/1` to step into a list (e.g. the nodes of a pipeline's steps).
  """

  @doc "Returns the secret paths present in `value`."
  @callback paths(value :: map()) :: [list()]
end
