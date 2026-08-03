defmodule FluxWeb.Router do
  @moduledoc "Router for the FluxWeb application, defining all routes and pipelines."
  use FluxWeb, :router

  import FluxWeb.UserAuth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {FluxWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_scope_for_user)
    # After the scope, so an authenticated request brands from its own org and a
    # signed-out one falls back to the deployment's.
    plug(FluxWeb.Plugs.Branding)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_authenticated do
    plug(:accepts, ["json"])
    plug(FluxWeb.Plugs.ApiAuth)
    # Per-org IP allowlist — runs right after auth so the org is known, and
    # before the burst valve so blocked IPs don't consume rate budget (MOS-588).
    plug(FluxWeb.Plugs.IpAllowlist)
    # Burst safety valve — runs after auth so it can key on the API key (MOS-450).
    plug(FluxWeb.Plugs.BurstLimiter)
  end

  scope "/", FluxWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
  end

  # Branding assets (MOS-483). Deliberately NOT :browser — that pipeline fetches a
  # session and resolves the current user from a token, i.e. a database round-trip
  # on an asset requested by every page load, including the sign-in page where
  # there is no session to fetch. Content-addressed URLs, so responses cache
  # immutably.
  pipeline :branding_asset do
    plug(:accepts, ["css", "png", "html"])
    plug(:put_secure_browser_headers)
  end

  scope "/branding", FluxWeb do
    pipe_through(:branding_asset)

    get("/theme/:digest", BrandingController, :theme)
  end

  # Unauthenticated health probe (for load balancers).
  scope "/", FluxWeb.API do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  # API routes with authentication
  scope "/api", FluxWeb.API do
    pipe_through(:api_authenticated)

    post("/webhooks/:source", WebhookController, :create)

    get("/pipelines", PipelineController, :index)
    post("/pipelines", PipelineController, :create)
    post("/pipelines/import", PipelineController, :import)
    get("/pipelines/:id", PipelineController, :show)
    get("/pipelines/:id/export", PipelineController, :export)
    post("/pipelines/:id/start", PipelineController, :start)
    post("/pipelines/:id/stop", PipelineController, :stop)
    get("/pipelines/:id/versions", PipelineVersionController, :index)
    post("/pipelines/:id/rollback", PipelineVersionController, :rollback)

    get("/sinks", SinkController, :index)

    get("/usage", UsageController, :show)

    # Audit logs (Enterprise-gated via require_feature(:audit_log))
    get("/audit-logs", AuditLogController, :index)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:flux, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: FluxWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes

  scope "/", FluxWeb do
    pipe_through([:browser, :require_authenticated_user])

    # Builder uses minimal layout (no sidebar, full screen canvas)
    # NOTE: Must come BEFORE :dashboard routes so /pipelines/builder doesn't match /pipelines/:id
    live_session :builder,
      on_mount: [
        {FluxWeb.UserAuth, :require_authenticated},
        {FluxWeb.UserAuth, :require_mfa_enrollment}
      ],
      layout: {FluxWeb.Layouts, :builder} do
      live("/pipelines/builder", PipelineLive.Builder, :new)
      live("/pipelines/:id/builder", PipelineLive.Builder, :edit)
    end

    live_session :dashboard,
      on_mount: [
        {FluxWeb.UserAuth, :require_authenticated},
        {FluxWeb.UserAuth, :require_mfa_enrollment}
      ],
      layout: {FluxWeb.Layouts, :dashboard} do
      live("/dashboard", DashboardLive.Index, :index)

      # Pipelines
      live("/pipelines", PipelineLive.Index, :index)
      live("/pipelines/:id", PipelineLive.Show, :show)

      # Sinks
      live("/sinks", SinkLive.Index, :index)
      live("/sinks/new", SinkLive.Form, :new)
      live("/sinks/:id/edit", SinkLive.Form, :edit)

      # Intelligence
      live("/intelligence/signals", AnomalyLive.Index, :index)

      # Observability — freshness SLO / volume baseline / schema drift (Pro-gated)
      live("/observability", ObservabilityLive.Index, :index)

      # PII redaction dashboard (Enterprise-gated)
      live("/redaction", PIILive.Index, :index)

      # System settings (owner only; 403 + redirect when unauthorized)
      live("/system/settings", SystemSettingsLive, :index)

      # Dead-letter queue management (owner only + Pro-gated)
      live("/system/dlq", DLQLive.Index, :index)

      # Alerting & notifications (owner only + Pro-gated)
      live("/system/alerts", AlertsLive.Index, :index)

      # Audit log (owner only + Enterprise-gated)
      live("/system/audit-logs", AuditLogLive.Index, :index)

      # Settings (sudo mode enforced at module level in Settings LiveView)
      live("/users/settings", UserLive.Settings, :edit)
      live("/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email)
    end

    # Audit log export (owner only + Enterprise-gated; controller streams a file download)
    get("/system/audit-logs/export", AuditLogExportController, :export)

    post("/users/update-password", UserSessionController, :update_password)
  end

  scope "/", FluxWeb do
    pipe_through([:browser])

    live_session :current_user,
      on_mount: [{FluxWeb.UserAuth, :mount_current_scope}] do
      live("/users/register", UserLive.Registration, :new)
      live("/users/log-in", UserLive.Login, :new)
      # Second-factor (TOTP) challenge — kept off the "/users/log-in/:token" path
      # so it isn't shadowed by the magic-link route.
      live("/users/two-factor", UserLive.TotpChallenge, :new)
      live("/users/log-in/:token", UserLive.Confirmation, :new)
    end

    post("/users/log-in", UserSessionController, :create)
    post("/users/two-factor", UserSessionController, :verify_totp)
    delete("/users/log-out", UserSessionController, :delete)
  end
end
