<!--
  GENERATED FILE — DO NOT EDIT.
  Source: ai-context/_shared.md + ai-context/flux.overlay.md
  Regenerate: scripts/gen_ai_context.sh
-->

# Flux - AI Assistant Guidelines

## Project Overview

Flux is a self-hosted, high-performance ETL/ELT platform for dynamic data pipelining. It combines the reliability of the BEAM (Erlang VM) with modern stream processing capabilities.

### Tech Stack

- **Backend**: Phoenix 1.8, LiveView, Elixir
- **Frontend**: Tailwind CSS v4, React Flow (lazy-loaded on `/pipelines/builder`)
- **Database**: Postgres 18
- **Queue**: RabbitMQ (production) / In-memory (development)
- **Processing**: Broadway, Oban (scheduler), Nx (AI/ML)
- **Auth**: Argon2 password hashing

### Architecture

**Control Plane (FluxWeb)**: Management, configuration, and visibility via Phoenix LiveView.

**Data Plane (FluxEngine)**: Execution and processing via Broadway pipelines.

### UI stack: Phoenix first, React only for builder

- **Prefer Phoenix** for all UI changes: LiveView, LiveView function components, core components (`<.form>`, `<.input>`, `<.icon>`, `<.button>`, `<.modal>`, `<.table>`, etc.), Layouts, HEEx, `Phoenix.Component` (form/inputs_for/to_form), phx-hook for JS, and Tailwind CSS.
- **Use React only** for the existing **canvas / flow chart** on `/pipelines/builder` (React Flow). Do not add new React routes or app-wide React UI.

## Project Guidelines

- Run `mix precommit` when done with changes and fix any issues
- Use `:req` (Req) for HTTP requests - avoid `:httpoison`, `:tesla`, `:httpc`

## Phoenix 1.8 Guidelines

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all content
- `Layouts` module is aliased in `flux_web.ex` - no need to re-alias
- For `current_scope` errors: move routes to proper `live_session` and pass `current_scope` to `<Layouts.app>`
- `<.flash_group>` is **forbidden** outside `layouts.ex`
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons - never use `Heroicons` modules
- Use imported `<.input>` component for form inputs

## Tailwind CSS v4 Guidelines

- **No `tailwind.config.js` needed** - uses new import syntax in `app.css`:
  ```css
  @import "tailwindcss" source(none);
  @source "../css";
  @source "../js";
  @source "../../lib/flux_web";
  ```
- **Never** use `@apply` in raw CSS
- Write custom Tailwind components instead of using daisyUI
- Only `app.js` and `app.css` bundles are supported
- Import vendor deps into app.js/app.css - no external script src or link href
- **Never** write inline `<script>` tags in templates

## Elixir Guidelines

- Lists **do not support index access** - use `Enum.at/2`, pattern matching, or `List` functions
- Variables are immutable but rebindable - bind `if`/`case`/`cond` results:
  ```elixir
  # VALID
  socket = if connected?(socket), do: assign(socket, :val, val), else: socket

  # INVALID - rebinding inside if doesn't work
  if connected?(socket), do: socket = assign(socket, :val, val)
  ```
- **Never** nest multiple modules in the same file
- **Never** use map access (`changeset[:field]`) on structs - use `my_struct.field` or `Ecto.Changeset.get_field/2`
- Use standard library for date/time - avoid extra deps except `date_time_parser` for parsing
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate functions end in `?` (not `is_` prefix)
- OTP primitives require names: `{DynamicSupervisor, name: Flux.MyDynamicSup}`
- Use `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration

## Mix Guidelines

- Read docs with `mix help task_name` before using tasks
- Debug test failures: `mix test test/my_test.exs` or `mix test --failed`
- **Avoid** `mix deps.clean --all` unless necessary

## Test Guidelines

- **Always** use `start_supervised!/1` to start processes
- **Avoid** `Process.sleep/1` and `Process.alive?/1` - use `Process.monitor/1`:
  ```elixir
  ref = Process.monitor(pid)
  assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  ```
- Use `:sys.get_state/1` to synchronize before next call

## Ecto Guidelines

- **Always** preload associations when accessed in templates
- Remember `import Ecto.Query` in `seeds.exs`
- Schema fields use `:string` type even for `:text` columns
- `validate_number/2` does **not** support `:allow_nil`
- Use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields set programmatically (e.g., `user_id`) must **not** be in `cast` calls
- Use `mix ecto.gen.migration migration_name` for migrations

## Phoenix Router Guidelines

- `scope` blocks include an optional alias prefixed to all routes
- Don't create your own `alias` for route definitions:
  ```elixir
  scope "/admin", FluxWeb.Admin do
    live "/users", UserLive, :index  # Points to FluxWeb.Admin.UserLive
  end
  ```
- `Phoenix.View` is not used

## HEEx Template Guidelines

- **Always** use `~H` or `.html.heex` files - never `~E`
- Use `Phoenix.Component.form/1` and `inputs_for/1` - never `Phoenix.HTML.form_for`
- Use `to_form/2` for forms: `assign(socket, form: to_form(...))`
- Add unique DOM IDs to key elements for testing
- **Never** use `else if` or `elsif` - use `cond` or `case`
- Use `phx-no-curly-interpolation` for literal curly braces in code blocks
- Class lists require `[...]` syntax with conditionals:
  ```heex
  <a class={["px-2 text-white", @flag && "py-5", if(@cond, do: "border-red-500", else: "border-blue-100")]}>
  ```
- Use `{...}` for attribute interpolation, `<%= %>` for block constructs in tag bodies
- Use `<%!-- comment --%>` for HEEx comments
- **Never** use `<% Enum.each %>` - use `<%= for item <- @collection do %>`

## LiveView Guidelines

- **Never** use deprecated `live_redirect`/`live_patch` - use `<.link navigate={}>` and `push_navigate/push_patch`
- **Avoid** LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix: `FluxWeb.WeatherLive`

### Streams

- **Always** use streams for collections:
  ```elixir
  stream(socket, :messages, [new_msg])           # append
  stream(socket, :messages, items, reset: true)  # reset
  stream(socket, :messages, [new_msg], at: -1)   # prepend
  stream_delete(socket, :messages, msg)          # delete
  ```
- Template pattern:
  ```heex
  <div id="messages" phx-update="stream">
    <div :for={{id, msg} <- @streams.messages} id={id}>{msg.text}</div>
  </div>
  ```
- Streams are **not** enumerable - refetch and reset for filtering
- For empty states, use Tailwind: `<div class="hidden only:block">No items</div>`

### JavaScript Interop

- With `phx-hook`, also set `phx-update="ignore"` if hook manages DOM
- **Always** provide unique DOM id with `phx-hook`
- Use colocated hooks with `:type={Phoenix.LiveView.ColocatedHook}` - names must start with `.`
- External hooks go in `assets/js/` and are passed to LiveSocket constructor
- **Always** rebind socket on `push_event/3`

### Forms

- **Always** use `to_form/2` assigned form with `<.input>` component
- **Never** access changeset directly in template - only use `@form`
- Template pattern:
  ```heex
  <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
    <.input field={@form[:field]} type="text" />
  </.form>
  ```

## Pull Request Notes

When generating **Pull Request notes**, **PR description**, or similar:

- **Always** use GitHub-flavored Markdown so it renders correctly on GitHub.
- **Use Mermaid diagrams** when they add clarity: flowcharts for flows/processes, sequence diagrams for request flows, state diagrams for state machines. Keep diagrams valid so they render on GitHub.
- **Do not** list changed files or a file-by-file summary in the PR note; focus on *what* and *why*, not *which files* (reviewers see the diff). Summarize goals, breaking changes, config/migration steps, and how to test.

## UI/UX Design Guidelines

- Produce world-class UI with focus on usability and aesthetics
- Implement subtle micro-interactions (hover effects, smooth transitions)
- Ensure clean typography, spacing, and layout balance
- Focus on delightful details: hover effects, loading states, page transitions

## Repository Scope — Community Edition (public, Apache 2.0)

This is the **public** Flux repository. It ships the **Community Edition only** and is licensed Apache 2.0.

- **Never add Pro or Enterprise code here.** Advanced AI (the `Flux.AI.Detector` anomaly provider), the S3 sink, the RabbitMQ queue, SSO / audit / MFA, billing, and other commercial features ship in the separate **Flux Pro / Enterprise** edition, maintained privately by the Flux team. Anything intended to be license-gated must **never** enter this repo's git history — once published under Apache 2.0 it cannot be made proprietary again.
- **Extend via behaviours + the registry, never by hard-coding adapters:**
  - Sinks implement `Flux.Sink.Adapter` and register through `Flux.Sink.Registry`.
  - Queues implement `Flux.Queue.Adapter` and register through `Flux.Queue.Registry`.
  - Pipeline steps, auth strategies, and license providers follow the same pattern (`Flux.Pipeline.Step`, `Flux.Auth.Strategy`, `Flux.License.Provider`).
- Community adapters self-register at boot in `Flux.Registrations`. Pro/EE slots are filled by **stub adapters** (`Flux.Sink.Adapters.Stub`, `Flux.Queue.Adapters.Stub`) that return `{:error, :pro_required}` and surface an upgrade prompt — they must fail cleanly, never crash at compile or config time.
- External contributors work **only** against this repo. See `CONTRIBUTING.md`.

## AI Context Files

`CLAUDE.md` and `AGENTS.md` in this repo are **generated** — do not edit them directly.

- Source fragments live in `ai-context/`: `_shared.md` (shared engineering conventions) + `flux.overlay.md` (this file, public-only).
- Regenerate with `scripts/gen_ai_context.sh`; CI / `mix precommit` runs `scripts/gen_ai_context.sh --check`.
- `_shared.md` is the source of truth for shared conventions and is also used by the commercial edition; if you change it, the maintainers handle re-syncing. Never put Pro/EE or commercial-strategy content in `_shared.md` — it is public by definition.
