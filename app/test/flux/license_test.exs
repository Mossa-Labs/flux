defmodule Flux.LicenseTest do
  # async: false — swaps the global license provider.
  use ExUnit.Case, async: false

  import Flux.LicenseHelpers

  describe "default (community) build" do
    test "tier/0 is :community and Pro features are denied" do
      assert Flux.License.tier() == :community
      refute Flux.License.has_feature?(:s3_sink)
      refute Flux.License.has_feature?(:advanced_ai)
      refute Flux.License.has_feature?(:org_rbac)
    end
  end

  describe "with_license_tier/2" do
    test "pro tier grants pro features but denies enterprise-only" do
      with_license_tier(:pro, fn ->
        assert Flux.License.tier() == :pro
        assert Flux.License.has_feature?(:s3_sink)
        assert Flux.License.has_feature?(:rabbit_mq_queue)
        assert Flux.License.has_feature?(:advanced_ai)
        assert Flux.License.has_feature?(:live_signals)
        # :org_rbac is "Pro+", so it is entitled at the Pro tier.
        assert Flux.License.has_feature?(:org_rbac)
        refute Flux.License.has_feature?(:sso)
        refute Flux.License.has_feature?(:mfa_enforcement)
      end)
    end

    test "enterprise tier grants everything" do
      with_license_tier(:enterprise, fn ->
        assert Flux.License.has_feature?(:s3_sink)
        assert Flux.License.has_feature?(:sso)
        assert Flux.License.has_feature?(:org_rbac)
      end)
    end

    test "restores the previous provider afterwards" do
      with_license_tier(:enterprise, fn -> :ok end)
      assert Flux.License.tier() == :community
    end
  end

  describe "entitled?/1" do
    test "is an alias for has_feature?/1" do
      with_license_tier(:pro, fn ->
        assert Flux.License.entitled?(:s3_sink) == Flux.License.has_feature?(:s3_sink)
        assert Flux.License.entitled?(:sso) == Flux.License.has_feature?(:sso)
      end)
    end
  end

  describe "activation (MOS-451)" do
    setup do
      prev = Application.get_env(:flux, Flux.License)

      on_exit(fn ->
        if prev,
          do: Application.put_env(:flux, Flux.License, prev),
          else: Application.delete_env(:flux, Flux.License)

        Application.delete_env(:flux, :test_activation_license)
        Application.delete_env(:flux, :test_activation_result)
      end)

      :ok
    end

    test "community build does not support activation" do
      refute Flux.License.activation_supported?()
      assert Flux.License.apply_license("anything") == {:error, :unsupported}
      assert Flux.License.status() == :active
    end

    test "delegates apply_license to an activation-capable provider" do
      Application.put_env(:flux, Flux.License, provider: Flux.LicenseActivationTestProvider)

      assert Flux.License.activation_supported?()
      assert {:ok, %{tier: :pro}} = Flux.License.apply_license("good-token")

      Application.put_env(:flux, :test_activation_result, {:error, :invalid_signature})
      assert Flux.License.apply_license("bad-token") == {:error, :invalid_signature}
    end

    test "status/0 reflects the provider's reported status" do
      Application.put_env(:flux, Flux.License, provider: Flux.LicenseActivationTestProvider)

      Application.put_env(:flux, :test_activation_license, %{
        tier: :pro,
        features: [],
        org: "Acme",
        valid_until: nil,
        node_count: 1,
        status: :grace
      })

      assert Flux.License.status() == :grace
    end
  end
end
