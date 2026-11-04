defmodule Flux.AWS.ServerCredentialsTest do
  # async: false — toggles the global :aws_server_credentials application env.
  use ExUnit.Case, async: false

  alias Flux.AWS.ServerCredentials

  setup do
    previous = Application.get_env(:flux, :aws_server_credentials)
    on_exit(fn -> Application.put_env(:flux, :aws_server_credentials, previous) end)
    :ok
  end

  @keys %{"access_key_id" => "AKIAUSER", "secret_access_key" => "secret"}

  describe "setting/0 and allowed?/0" do
    test "defaults to allowed" do
      Application.delete_env(:flux, :aws_server_credentials)
      assert ServerCredentials.setting() == :allowed
      assert ServerCredentials.allowed?()
    end

    test "reads :disabled" do
      Application.put_env(:flux, :aws_server_credentials, :disabled)
      assert ServerCredentials.setting() == :disabled
      refute ServerCredentials.allowed?()
    end

    test "treats any other value as allowed" do
      Application.put_env(:flux, :aws_server_credentials, "disabled")
      assert ServerCredentials.allowed?()
    end
  end

  describe "effective_auth_mode/1" do
    test "an explicit mode wins" do
      assert ServerCredentials.effective_auth_mode(Map.put(@keys, "auth_mode", "iam_role")) ==
               "iam_role"

      assert ServerCredentials.effective_auth_mode(%{"auth_mode" => "assume_role"}) ==
               "assume_role"
    end

    test "without a mode, both keys mean static and anything else iam_role" do
      assert ServerCredentials.effective_auth_mode(@keys) == "static"
      assert ServerCredentials.effective_auth_mode(%{}) == "iam_role"
      assert ServerCredentials.effective_auth_mode(%{"auth_mode" => ""}) == "iam_role"

      assert ServerCredentials.effective_auth_mode(%{"access_key_id" => "AKIAUSER"}) ==
               "iam_role"
    end
  end

  describe "uses_server_identity?/1" do
    test "iam_role always does, even with leftover keys" do
      assert ServerCredentials.uses_server_identity?(%{"auth_mode" => "iam_role"})
      assert ServerCredentials.uses_server_identity?(Map.put(@keys, "auth_mode", "iam_role"))
    end

    test "assume_role does only without base keys" do
      assert ServerCredentials.uses_server_identity?(%{"auth_mode" => "assume_role"})

      assert ServerCredentials.uses_server_identity?(%{
               "auth_mode" => "assume_role",
               "access_key_id" => "AKIAUSER",
               "secret_access_key" => "  "
             })

      refute ServerCredentials.uses_server_identity?(Map.put(@keys, "auth_mode", "assume_role"))
    end

    test "static never does, even with missing keys" do
      refute ServerCredentials.uses_server_identity?(%{"auth_mode" => "static"})
      refute ServerCredentials.uses_server_identity?(Map.put(@keys, "auth_mode", "static"))
    end

    test "a config with no mode follows the inferred mode" do
      assert ServerCredentials.uses_server_identity?(%{})
      refute ServerCredentials.uses_server_identity?(@keys)
    end
  end

  describe "check/1" do
    test "passes everything while allowed" do
      Application.put_env(:flux, :aws_server_credentials, :allowed)
      assert ServerCredentials.check(%{"auth_mode" => "iam_role"}) == :ok
    end

    test "refuses the server's identity while disabled" do
      Application.put_env(:flux, :aws_server_credentials, :disabled)

      assert ServerCredentials.check(%{"auth_mode" => "iam_role"}) ==
               {:error, ServerCredentials.disabled_message()}

      assert {:error, _} = ServerCredentials.check(%{"auth_mode" => "assume_role"})
      assert ServerCredentials.check(Map.put(@keys, "auth_mode", "assume_role")) == :ok
      assert ServerCredentials.check(Map.put(@keys, "auth_mode", "static")) == :ok
    end
  end
end
