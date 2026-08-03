defmodule Flux.MixProject do
  use Mix.Project

  # The release tag drives the version (MOS-586/MOS-596). This value does more
  # than label the app: it names the OTP release directory (`/app/releases/<vsn>`)
  # and sets RELEASE_VSN. An image tagged 0.2.1 previously shipped a release
  # directory called 0.2.0, because the tag reached the image's labels and
  # /etc/flux-release but never reached the compiler.
  #
  # Injecting it here rather than overriding `:build_info` downstream is what
  # keeps those surfaces from drifting apart again — they all derive from this
  # one value.
  #
  # The `case` rather than `||`: Docker's `ENV FOO=${BAR}` with an undeclared
  # build arg sets FOO to the EMPTY STRING, and "" is truthy in Elixir, so `||`
  # would stamp a blank version on every local build.
  @version (case String.trim(System.get_env("FLUX_VERSION") || "") do
              "" -> "0.2.0"
              version -> version
            end)

  def project do
    [
      app: :flux,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Flux.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp docs do
    [
      main: "Flux",
      extras: [
        "../docs/architecture_overview.md",
        "../docs/lua_scripting.md",
        "../docs/rbac.md",
        "../docs/operator_manual.md",
        "../docs/developer_guide.md"
      ],
      groups_for_modules: [
        Core: [Flux.Pipelines, Flux.Sinks, Flux.Permissions, Flux.Accounts, Flux.Structure],
        "Pipeline Engine": [
          Flux.Pipeline.Manager,
          Flux.Pipeline.Runner,
          Flux.Pipeline.Interpreter,
          Flux.Pipeline.Step,
          Flux.Pipeline.Steps.Filter,
          Flux.Pipeline.Steps.Map,
          Flux.Pipeline.Steps.Rename,
          Flux.Pipeline.Steps.Script,
          Flux.Pipeline.Metrics
        ],
        Queue: [Flux.Queue, Flux.Queue.Adapters.Memory],
        Sinks: [
          Flux.Sink,
          Flux.Sink.Adapters.HTTP,
          Flux.Sink.Adapters.Postgres
        ],
        "AI/ML": [Flux.AI.Scorer],
        Web: ~r/FluxWeb/
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.0"},
      # TOTP-based MFA: code generation/verification + QR for enrollment (MOS-591)
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.2"},
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:myxql, "~> 0.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      # Required by Swoosh.Adapters.SMTP — the transport an on-prem operator
      # configures via FLUX_SMTP_*. Without it that adapter cannot be used at all.
      {:gen_smtp, "~> 1.2"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:oban, "~> 2.17"},
      {:broadway, "~> 1.0"},
      {:nx, "~> 0.9"},
      {:luerl, "~> 1.2"},
      # Trustworthy client IP behind proxies + CIDR matching for the IP allowlist
      {:remote_ip, "~> 1.2"},
      {:inet_cidr, "~> 1.0"},
      # Testing & Documentation
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "cmd --cd assets npm install"
      ],
      "assets.build": ["compile", "tailwind flux", "esbuild flux", "esbuild flux_builder"],
      "assets.deploy": [
        "tailwind flux --minify",
        "esbuild flux --minify",
        "esbuild flux_builder --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "cmd ../scripts/gen_ai_context.sh --check",
        # This repo is public and Apache-2.0; a reference to the private edition
        # cannot be retracted once it is in a published history (MOS-595).
        "cmd ../scripts/check_no_private_refs.sh",
        "test"
      ]
    ]
  end
end
