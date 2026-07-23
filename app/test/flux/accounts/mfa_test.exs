defmodule Flux.Accounts.MfaTest do
  use Flux.DataCase, async: true

  import Flux.AccountsFixtures

  alias Flux.Accounts.Mfa

  defp enroll(user) do
    %{secret: secret} = Mfa.start_enrollment(user)
    code = NimbleTOTP.verification_code(secret)
    {:ok, backup_codes} = Mfa.confirm_enrollment(user, secret, code)
    {secret, backup_codes}
  end

  describe "start_enrollment/1" do
    test "returns a secret and otpauth uri without persisting" do
      user = user_fixture()
      assert %{secret: secret, otpauth_uri: uri} = Mfa.start_enrollment(user)
      assert is_binary(secret)
      assert uri =~ "otpauth://totp/"
      assert uri =~ "issuer=Flux"
      # Not yet enrolled.
      refute Mfa.mfa_enabled?(user)
      assert Mfa.get_user_mfa(user) == nil
    end
  end

  describe "confirm_enrollment/3" do
    test "enables MFA and returns 10 backup codes for a valid code" do
      user = user_fixture()
      %{secret: secret} = Mfa.start_enrollment(user)
      code = NimbleTOTP.verification_code(secret)

      assert {:ok, backup_codes} = Mfa.confirm_enrollment(user, secret, code)
      assert length(backup_codes) == 10
      assert Enum.all?(backup_codes, &is_binary/1)
      assert Mfa.mfa_enabled?(user)
    end

    test "rejects an invalid code" do
      user = user_fixture()
      %{secret: secret} = Mfa.start_enrollment(user)

      assert {:error, :invalid_code} = Mfa.confirm_enrollment(user, secret, "000000")
      refute Mfa.mfa_enabled?(user)
    end
  end

  describe "verify_totp/2" do
    test "accepts a current code and rejects a wrong one" do
      user = user_fixture()
      {secret, _} = enroll(user)

      assert Mfa.verify_totp(user, NimbleTOTP.verification_code(secret))
      refute Mfa.verify_totp(user, "000000")
    end

    test "returns false when the user is not enrolled" do
      refute Mfa.verify_totp(user_fixture(), "123456")
    end
  end

  describe "verify_backup_code/2 (single-use)" do
    test "accepts a code once then rejects it on reuse" do
      user = user_fixture()
      {_secret, [code | _]} = enroll(user)

      assert :ok = Mfa.verify_backup_code(user, code)
      assert Mfa.backup_codes_remaining(user) == 9
      assert :error = Mfa.verify_backup_code(user, code)
    end

    test "rejects an unknown code" do
      user = user_fixture()
      enroll(user)
      assert :error = Mfa.verify_backup_code(user, "not-a-real-code")
    end
  end

  describe "regenerate_backup_codes/1" do
    test "replaces the old set, invalidating prior codes" do
      user = user_fixture()
      {_secret, [old_code | _]} = enroll(user)

      assert {:ok, new_codes} = Mfa.regenerate_backup_codes(user)
      assert length(new_codes) == 10
      refute old_code in new_codes
      assert :error = Mfa.verify_backup_code(user, old_code)
      assert :ok = Mfa.verify_backup_code(user, hd(new_codes))
    end
  end

  describe "disable/1" do
    test "removes the MFA record" do
      user = user_fixture()
      enroll(user)
      assert Mfa.mfa_enabled?(user)

      assert {:ok, _} = Mfa.disable(user)
      refute Mfa.mfa_enabled?(user)
      assert Mfa.get_user_mfa(user) == nil
    end
  end

  describe "encryption at rest" do
    test "secret and backup codes are stored encrypted, bound to the user" do
      user = user_fixture()
      enroll(user)
      record = Mfa.get_user_mfa(user)

      assert %{"encrypted" => true, "ciphertext" => _} = record.secret
      assert %{"encrypted" => true, "ciphertext" => _} = record.backup_codes
    end
  end
end
