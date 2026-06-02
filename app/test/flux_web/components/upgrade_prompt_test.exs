defmodule FluxWeb.Components.UpgradePromptTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FluxWeb.Components.UpgradePrompt

  test "default size renders a header and CTA link" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :s3_sink)
    assert html =~ "S3"
    assert html =~ "Flux Pro"
    assert html =~ "href=\"https://flux.dev/pricing\""
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

  test "unknown feature atom falls back to a human-readable label" do
    html = render_component(&UpgradePrompt.upgrade_prompt/1, feature: :mystery_future_feature)
    assert html =~ "mystery future feature"
  end
end
