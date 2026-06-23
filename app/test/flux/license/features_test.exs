defmodule Flux.License.FeaturesTest do
  use ExUnit.Case, async: true

  alias Flux.License.Features

  test "community tier has no Pro/EE features" do
    assert Features.for_tier(:community) == []
  end

  test "tiers are cumulative: enterprise ⊇ pro ⊇ community" do
    community = MapSet.new(Features.for_tier(:community))
    pro = MapSet.new(Features.for_tier(:pro))
    enterprise = MapSet.new(Features.for_tier(:enterprise))

    assert MapSet.subset?(community, pro)
    assert MapSet.subset?(pro, enterprise)
  end

  test "pro includes the documented pro features (incl. Pro+ org RBAC) but not enterprise-only ones" do
    pro = Features.for_tier(:pro)

    assert :s3_sink in pro
    assert :rabbit_mq_queue in pro
    assert :advanced_ai in pro
    assert :live_signals in pro
    assert :cron_polling in pro
    assert :observability in pro
    # Org-centric RBAC is "Pro+", entitled from the Pro tier up.
    assert :org_rbac in pro

    refute :sso in pro
    refute :mfa in pro
  end

  test "enterprise includes enterprise-only features" do
    enterprise = Features.for_tier(:enterprise)

    assert :sso in enterprise
    assert :mfa in enterprise
    # Pro features remain available at the Enterprise tier (cumulative).
    assert :org_rbac in enterprise
  end

  test "tier_for_feature/1 returns the lowest entitling tier" do
    assert Features.tier_for_feature(:s3_sink) == :pro
    assert Features.tier_for_feature(:org_rbac) == :pro
    assert Features.tier_for_feature(:sso) == :enterprise
    assert Features.tier_for_feature(:nonexistent) == nil
  end

  test "all/0 equals the enterprise feature set" do
    assert Features.all() == Features.for_tier(:enterprise)
  end
end
