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
    assert license.valid_until == nil
    assert license.node_count == nil
  end

  test "Flux.License facade reports community tier and denies Pro/EE features" do
    assert Flux.License.tier() == :community
    refute Flux.License.has_feature?(:s3_sink)
    refute Flux.License.has_feature?(:rabbit_mq_queue)
    refute Flux.License.has_feature?(:advanced_ai)
    refute Flux.License.has_feature?(:sso)
    refute Flux.License.has_feature?(:audit_log)
  end
end
