defmodule FluxWeb.Components.UpgradePrompt do
  @moduledoc """
  Shared UI component for features gated behind Flux Pro / Enterprise.

  Rendered whenever a LiveView or controller receives a
  `{:error, {:pro_required, feature}}` result from a stub adapter or
  a license check.

      <.upgrade_prompt feature={:s3_sink} />
      <.upgrade_prompt feature={:rabbit_mq_queue} size={:compact} />
  """

  use Phoenix.Component

  alias FluxWeb.CoreComponents

  attr :feature, :atom,
    required: true,
    doc: "the Pro/EE feature atom, e.g. :s3_sink, :rabbit_mq_queue, :advanced_ai"

  attr :size, :atom,
    values: [:default, :compact],
    default: :default,
    doc: "use :compact inside forms/tables; :default for full callouts"

  attr :upgrade_url, :string,
    default: "https://flux.dev/pricing",
    doc: "override the upgrade CTA URL (e.g. for self-hosted billing portal)"

  def upgrade_prompt(%{size: :compact} = assigns) do
    assigns = assign(assigns, :label, feature_label(assigns.feature))

    ~H"""
    <div class="flex items-center gap-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
      <CoreComponents.icon name="hero-sparkles" class="size-4 shrink-0" />
      <span>
        <span class="font-medium">{@label}</span>
        requires Flux Pro.
        <.link href={@upgrade_url} class="font-semibold underline hover:no-underline">Upgrade</.link>
      </span>
    </div>
    """
  end

  def upgrade_prompt(assigns) do
    assigns = assign(assigns, :label, feature_label(assigns.feature))

    ~H"""
    <div class="rounded-lg border border-amber-300 bg-gradient-to-br from-amber-50 to-orange-50 p-6 shadow-sm">
      <div class="flex items-start gap-4">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-amber-200 text-amber-900">
          <CoreComponents.icon name="hero-sparkles" class="size-5" />
        </div>
        <div class="flex-1">
          <h3 class="text-base font-semibold text-amber-950">
            {@label} is a Flux Pro feature
          </h3>
          <p class="mt-1 text-sm text-amber-900/80">
            Unlock {@label} and the rest of the Pro suite to scale your pipelines beyond the Community tier.
          </p>
          <div class="mt-4 flex flex-wrap items-center gap-4">
            <.link
              href={@upgrade_url}
              class="inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-amber-700"
            >
              View pricing <CoreComponents.icon name="hero-arrow-right" class="size-4" />
            </.link>
            <.link
              navigate="/system/settings"
              class="text-sm font-medium text-amber-900 underline hover:no-underline"
            >
              Already have a license? Activate it
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp feature_label(:s3_sink), do: "S3 / object storage sink"
  defp feature_label(:snowflake_sink), do: "Snowflake sink"
  defp feature_label(:bigquery_sink), do: "BigQuery sink"
  defp feature_label(:kafka_sink), do: "Kafka sink"
  defp feature_label(:rabbit_mq_queue), do: "RabbitMQ queue backend"
  defp feature_label(:kafka_queue), do: "Kafka queue backend"
  defp feature_label(:dlq), do: "Dead-letter queue"
  defp feature_label(:advanced_ai), do: "Advanced anomaly detection"
  defp feature_label(:live_signals), do: "Live Signals monitoring"
  defp feature_label(:cron_polling), do: "Scheduled (cron) polling"
  defp feature_label(:org_rbac), do: "Organization-centric RBAC"
  defp feature_label(:api_key_scopes), do: "Fine-grained API key scopes"
  defp feature_label(:usage_metering), do: "Usage metering & quotas"
  defp feature_label(:sso), do: "SSO / SAML / OIDC"
  defp feature_label(:audit_log), do: "Audit logging"
  defp feature_label(:white_label), do: "White-label branding"
  defp feature_label(:mfa), do: "Multi-factor authentication"
  defp feature_label(:pro_sink), do: "This sink type"
  defp feature_label(:pro_queue), do: "This queue backend"
  defp feature_label(other), do: other |> Atom.to_string() |> String.replace("_", " ")
end
