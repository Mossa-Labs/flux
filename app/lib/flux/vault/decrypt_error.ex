defmodule Flux.Vault.DecryptError do
  @moduledoc """
  Raised when an encrypted value cannot be decrypted — typically a wrong or
  rotated encryption key, or tampered ciphertext.
  """
  defexception message: "could not decrypt value (wrong key or tampered ciphertext)"
end
