defmodule FluxWeb.UserLive.Login do
  @moduledoc "LiveView for user login via single sign-on, magic link or password."
  use FluxWeb, :live_view

  alias Flux.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <%!--
        A white-label deployment's own words to its users. Rendered from the
        deployment's branding rather than the scope: there is no session here, so
        there is no organization to read it from. See Flux.Branding on the
        single-organization assumption that makes this well-defined.
        --%>
        <p
          :if={msg = Flux.Branding.for_deployment().login_message}
          class="text-center text-sm text-base-content/70"
        >
          {msg}
        </p>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <%!--
        Single sign-on first when it's available: in an organization that has
        it, this is the path most people should take. Discovery is by email
        domain, so it works however many organizations share the deployment.
        A plain HTTP post (no phx-submit): the next stop is the identity
        provider.

        Custom Tailwind rather than daisyUI component classes (see CLAUDE.md),
        on the theme's colour tokens so it follows light/dark and a branded
        accent colour. The button passes its own class, which replaces the core
        button's daisyUI defaults.
        --%>
        <div
          :if={@sso_available}
          id="sso-login"
          class="rounded-xl border border-base-content/10 bg-base-200/60 p-4 transition-colors hover:border-primary/30"
        >
          <div class="mb-3 flex items-center gap-2">
            <span class="flex size-8 items-center justify-center rounded-full bg-primary/10 text-primary">
              <.icon name="hero-building-office-2" class="size-4" />
            </span>
            <div>
              <p class="text-sm font-semibold">Sign in with SSO</p>
              <p class="text-xs text-base-content/60">Use your company's identity provider.</p>
            </div>
          </div>
          <.form :let={f} for={@sso_form} id="login_form_sso" action={~p"/sso/start"}>
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Work email"
              autocomplete="email"
              placeholder="you@company.com"
              required
            />
            <.button
              class="inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded-lg bg-primary px-3.5 py-2 text-sm font-semibold text-primary-content transition-colors hover:bg-primary/90 active:bg-primary/80 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary/50"
              phx-disable-with="Redirecting…"
            >
              Continue with SSO <span aria-hidden="true">→</span>
            </.button>
          </.form>
        </div>

        <div
          :if={@sso_available}
          id="sso-login-divider"
          class="flex items-center gap-3 py-1 text-xs text-base-content/50"
        >
          <span class="h-px flex-1 bg-base-content/10" aria-hidden="true"></span>
          <span class="shrink-0">or use a password or email link</span>
          <span class="h-px flex-1 bg-base-content/10" aria-hidden="true"></span>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">or</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="email"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Log in and stay logged in <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Log in only this time
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       sso_form: to_form(%{"email" => email}, as: "sso"),
       sso_available: Flux.Auth.SSO.available?(),
       trigger_submit: false
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    # SSO-enforced members are skipped silently: the reply below is identical
    # either way, so it gives nothing away about who must use SSO.
    if (user = Accounts.get_user_by_email(email)) && Flux.Auth.SSO.password_login_allowed?(user) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )

      scope = Flux.Accounts.Scope.for_user(user)

      Flux.Audit.log(%{
        actor: scope,
        organization_id: scope.organization_id,
        action: :magic_link_sent,
        resource_type: :user,
        resource_id: user.id
      })
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:flux, Flux.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
