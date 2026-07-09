defmodule FluxWeb.Components.UpgradePromptTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FluxWeb.Components.UpgradePrompt

  test "default size renders a header and CTA link" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :s3_sink)
    assert html =~ "S3"
    assert html =~ "Flux Pro"
    assert html =~ "href=\"https://fluxdata.tech/pricing\""
  end

  test "compact size renders the CTA inline with Upgrade link" do
    html =
      render_component(&UpgradePrompt.upgrade_prompt/1, feature: :rabbit_mq_queue, size: :compact)

    assert html =~ "RabbitMQ"
    assert html =~ "Upgrade"
  end

  test "honors a custom upgrade_url" do
    html =
      render_component(&UpgradePrompt.upgrade_prompt/1,
        feature: :sso,
        upgrade_url: "https://acme.internal/billing"
      )

    assert html =~ "https://acme.internal/billing"
  end

  test "renders the Amazon SQS source label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :sqs_source)
    assert html =~ "Amazon SQS source"
    assert html =~ "Flux Pro"
  end

  test "renders the Amazon Kinesis source label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :kinesis_source)
    assert html =~ "Amazon Kinesis source"
    assert html =~ "Flux Pro"
  end

  test "renders the Redis sink label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :redis_sink)
    assert html =~ "Redis sink"
    assert html =~ "Flux Pro"
  end

  test "renders the MongoDB sink label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :mongodb_sink)
    assert html =~ "MongoDB sink"
    assert html =~ "Flux Pro"
  end

  test "unknown feature atom falls back to a human-readable label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :mystery_future_feature)
    assert html =~ "mystery future feature"
  end

  test "shows the 'Activate it' link when license activation is supported" do
    html =
      render_component(&UpgradePrompt.upgrade_prompt/1,
        feature: :usage_metering,
        activation_supported: true
      )

    assert html =~ "Already have a license? Activate it"
    assert html =~ "href=\"/system/settings\""
  end

  test "hides the 'Activate it' link when license activation is unsupported" do
    # Community builds can't apply a signed key, so the link would be a dead end.
    html =
      render_component(&UpgradePrompt.upgrade_prompt/1,
        feature: :usage_metering,
        activation_supported: false
      )

    refute html =~ "Activate it"
    # The upgrade CTA is still offered.
    assert html =~ "View pricing"
  end
end
