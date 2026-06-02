defmodule Flux.License.Providers.CommunityTest do
  use ExUnit.Case, async: true

  alias Flux.License.Providers.Community

  test "tier/0 returns :community" do
    assert Community.tier() == :community
  end

  test "fetch/0 returns a license with community tier and no features" do
    assert {:ok, license} = Community.fetch()
    assert license.tier == :community
    assert license.features == []
  end

  test "entitled?/1 denies every Pro/EE feature" do
    refute Community.entitled?(:s3_sink)
    refute Community.entitled?(:rabbit_mq_queue)
    refute Community.entitled?(:advanced_ai)
    refute Community.entitled?(:sso)
    refute Community.entitled?(:audit_log)
  end

  test "Flux.License facade delegates to the configured provider" do
    assert Flux.License.tier() == :community
    refute Flux.License.entitled?(:s3_sink)
  end
end
