---
version: alpha
name: Flux
description: Flux's dark-canvas product design system — a Linear-derived surface ladder with a single lavender-blue accent, hairline borders, and dense product UI.
colors:
  # Surface ladder
  canvas: "#010102"
  surface-1: "#08090b"
  surface-2: "#0e1014"
  surface-3: "#16181d"
  surface-4: "#1e2127"
  # Hairlines
  hairline: "#23252a"
  hairline-strong: "#2e3036"
  hairline-tertiary: "#1a1c20"
  # Text
  ink: "#f7f8f8"
  ink-muted: "#d0d6e0"
  ink-subtle: "#8a8f98"
  ink-tertiary: "#62666d"
  # Brand & accent
  primary: "#5e6ad2"
  primary-hover: "#828fff"
  primary-focus: "#5e69d1"
  on-primary: "#ffffff"
  brand-secure: "#7a7fad"
  # Semantic
  semantic-success: "#27a644"
  semantic-overlay: "rgba(1, 1, 2, 0.6)"
  # Inverse (white-on-dark CTAs)
  inverse-canvas: "#ffffff"
  inverse-surface-1: "#f4f5f8"
  inverse-surface-2: "#eceef2"
  inverse-ink: "#08090b"
typography:
  display-xl:
    fontFamily: Inter
    fontSize: 80px
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: -3px
  display-lg:
    fontFamily: Inter
    fontSize: 56px
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: -1.8px
  display-md:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: -1px
  headline:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: -0.6px
  card-title:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: -0.4px
  subhead:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: -0.2px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: -0.1px
  body:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: -0.05px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0
  caption:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0
  button:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: 0
  eyebrow:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: 0.4px
  mono:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0
rounded:
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  xxl: 24px
  pill: 9999px
  full: 9999px
spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 96px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: 8px 14px
  button-primary-hover:
    backgroundColor: "{colors.primary-hover}"
  button-primary-pressed:
    backgroundColor: "{colors.primary-focus}"
  button-secondary:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: 8px 14px
  button-tertiary:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: 8px 14px
  button-inverse:
    backgroundColor: "{colors.inverse-canvas}"
    textColor: "{colors.inverse-ink}"
    typography: "{typography.button}"
    rounded: "{rounded.md}"
    padding: 8px 14px
  feature-card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 24px
  pricing-card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 24px
  pricing-card-featured:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 24px
  product-screenshot-card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.xl}"
    padding: 24px
  testimonial-card:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body-lg}"
    rounded: "{rounded.lg}"
    padding: 32px
  cta-banner:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.headline}"
    rounded: "{rounded.lg}"
    padding: 48px
  text-input:
    backgroundColor: "{colors.surface-1}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 8px 12px
  status-badge:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.ink-muted}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: 2px 8px
  top-nav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    height: 56px
  footer:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink-subtle}"
    typography: "{typography.caption}"
    padding: 64px 32px
---

# Flux Design System

Flux's product surface is a **dark-canvas system derived from Linear's marketing design**. The canvas (`{colors.canvas}` #010102) is essentially pure black with a faint blue tint. On top sits a four-step surface ladder (`{colors.surface-1}` through `{colors.surface-4}`) for cards, panels, and lifted tiles, with hairline borders running from `{colors.hairline}` (#23252a) up through `{colors.hairline-strong}` and `{colors.hairline-tertiary}`. Light gray text (`{colors.ink}` #f7f8f8) carries the body and headlines.

The single chromatic accent is **Flux lavender-blue** `{colors.primary}` (#5e6ad2) — used on the brand mark, focus rings, and the primary CTA button. A lighter hover state (`{colors.primary-hover}` #828fff) and a focus-tinted variant (`{colors.primary-focus}` #5e69d1) extend the same hue. Flux avoids saturated greens, oranges, reds, etc. on chrome surfaces — the only semantic color in marketing-grade UI is `{colors.semantic-success}` (#27a644) for status pills and the rare success indicator. (The in-product issue/pipeline status palette is a separate concern — see Known Gaps.)

Display type runs **Inter** at weight 500–700 with negative letter-spacing scaling from -3.0px at 80px down to 0 at body. The body family is also Inter, and **JetBrains Mono** is reserved for code snippets and ID/status tokens.

The page rhythm is **dense product screenshots** — Flux leads with high-fidelity captures of the product UI (pipeline list, builder canvas, dashboard) framed in `{colors.surface-1}` panels with `{rounded.xl}` 16px corners. The chrome is intentionally minimal so the app screenshots do the heavy lifting.

**Key Characteristics:**
- **Dark-canvas system** — `{colors.canvas}` (#010102) is the deepest dark surface.
- **Lavender-blue brand accent** (`{colors.primary}` #5e6ad2) — used scarcely on brand mark, focus, and the primary CTA.
- Four-step surface ladder (canvas → surface-1 → surface-2 → surface-3 → surface-4) carries hierarchy without shadow.
- Display tracking pulls aggressively negative (-3.0px at 80px); body holds at -0.05px.
- Cards use `{rounded.lg}` 12px corners with 1px hairline borders — never pill, rarely 16px.
- **Product UI screenshots** dominate. The chrome is a dark frame for the app.
- No second chromatic color. No atmospheric gradients. No spotlight cards.

## Colors

### Brand & Accent
- **Lavender-Blue** (`{colors.primary}`): The signature Flux accent — primary CTA, brand mark, link emphasis.
- **Lavender Hover** (`{colors.primary-hover}`): Lighter lavender (#828fff) — hovered state of the primary CTA.
- **Lavender Focus** (`{colors.primary-focus}`): Focus-ring tint (#5e69d1) — focused inputs, focused buttons.
- **Brand Secure** (`{colors.brand-secure}`): Muted lavender-gray (#7a7fad) — used in security/compliance surfaces.

### Surface
- **Canvas** (`{colors.canvas}`): Default page background — #010102, near-pure black with a faint blue tint.
- **Surface 1** (`{colors.surface-1}`): One step above canvas — feature cards, pricing cards, product screenshot panels.
- **Surface 2** (`{colors.surface-2}`): Two steps above — featured cards, hovered cards.
- **Surface 3** (`{colors.surface-3}`): Three steps above — sub-nav, dropdown menus.
- **Surface 4** (`{colors.surface-4}`): Four steps above — deepest lifted surface.
- **Hairline** (`{colors.hairline}`): 1px borders on cards and dividers.
- **Hairline Strong** (`{colors.hairline-strong}`): Stronger 1px borders — input focus rings, featured cards.
- **Hairline Tertiary** (`{colors.hairline-tertiary}`): Tertiary borders for nested surfaces.
- **Inverse Canvas** (`{colors.inverse-canvas}`): Pure white — surface of the inverse pill CTA on a small set of section openers.
- **Inverse Surface 1 / 2** (`{colors.inverse-surface-1}`, `{colors.inverse-surface-2}`): Steps above inverse canvas.

### Text
- **Ink** (`{colors.ink}`): All headlines and emphasized body type — light gray #f7f8f8.
- **Ink Muted** (`{colors.ink-muted}`): Secondary type at #d0d6e0 — meta info on hero panels.
- **Ink Subtle** (`{colors.ink-subtle}`): Tertiary type at #8a8f98 — deselected tabs, footer columns.
- **Ink Tertiary** (`{colors.ink-tertiary}`): Quaternary at #62666d — disabled, footnotes.

### Semantic
- **Success Green** (`{colors.semantic-success}`): Status pills, success indicators. The only semantic color on chrome surfaces.
- **Overlay** (`{colors.semantic-overlay}`): Near-black overlay scrim for modals.

## Typography

### Font Family

- **Inter** — the Flux sans (display + text). Carries `{typography.display-xl}` through `{typography.caption}`. Fallback `SF Pro Display, -apple-system, system-ui, Segoe UI, Roboto`.
- **JetBrains Mono** — the Flux mono. Used for code snippets, status, and ID tokens. Fallback `ui-monospace, SF Mono, Menlo`.

Flux treats display and body as one continuous voice; the size change is silent.

### Hierarchy

| Token | Size | Weight | Line Height | Letter Spacing | Use |
|---|---|---|---|---|---|
| `{typography.display-xl}` | 80px | 600 | 1.05 | -3.0px | Largest hero headline |
| `{typography.display-lg}` | 56px | 600 | 1.10 | -1.8px | Section opener headlines |
| `{typography.display-md}` | 40px | 600 | 1.15 | -1.0px | Sub-section headlines |
| `{typography.headline}` | 28px | 600 | 1.20 | -0.6px | Tier titles, CTA banner heading |
| `{typography.card-title}` | 22px | 500 | 1.25 | -0.4px | Feature card title |
| `{typography.subhead}` | 20px | 400 | 1.40 | -0.2px | Lead body, intro paragraphs |
| `{typography.body-lg}` | 18px | 400 | 1.50 | -0.1px | Hero subhead, lead paragraphs |
| `{typography.body}` | 16px | 400 | 1.50 | -0.05px | Default body |
| `{typography.body-sm}` | 14px | 400 | 1.50 | 0 | Card body, footer columns |
| `{typography.caption}` | 12px | 400 | 1.40 | 0 | Captions, meta, status |
| `{typography.button}` | 14px | 500 | 1.20 | 0 | All button labels |
| `{typography.eyebrow}` | 13px | 500 | 1.30 | 0.4px | Section eyebrow (slight positive tracking) |
| `{typography.mono}` | 13px | 400 | 1.50 | 0 | JetBrains Mono for code / tokens |

### Principles

- **Aggressive negative tracking on display** (-3.0px at 80px ≈ 4% of size).
- **Single voice from display to body.** display-xl at 600 → body at 400 — same family, narrower weights.
- **Eyebrow uses positive tracking** (+0.4px) — contrast against the negative-tracked display marks the eyebrow as taxonomy.
- **Mono only in code contexts.** JetBrains Mono lives inside product screenshots and ID/status tokens — not on chrome.

## Layout

### Spacing System

- **Base unit**: 4px.
- **Tokens**: `{spacing.xxs}` 4px · `{spacing.xs}` 8px · `{spacing.sm}` 12px · `{spacing.md}` 16px · `{spacing.lg}` 24px · `{spacing.xl}` 32px · `{spacing.xxl}` 48px · `{spacing.section}` 96px.
- Card interior padding: `{spacing.lg}` 24px on feature/pricing cards; `{spacing.xl}` 32px on testimonial cards; `{spacing.xxl}` 48px on CTA banners.
- Button padding: 8px vertical · 14px horizontal — compact button spec.
- Form input padding: 8px vertical · 12px horizontal.

### Grid & Container

- Max content width sits around 1280px.
- Card grids are 3-up at desktop, 2-up at tablet, 1-up at mobile.
- Product screenshot panels span full content width — they're the protagonist.

### Whitespace Philosophy

The dark canvas IS the whitespace. Sections separate by lift onto surface-1 panels, not by gaps in white. Within a panel, generous `{spacing.lg}` 24px gaps between content blocks; `{spacing.section}` 96px between sections.

## Elevation & Depth

| Level | Treatment | Use |
|---|---|---|
| 0 (flat) | No shadow, no border | Default for body type, hero text, footer |
| 1 (lift) | `{colors.surface-1}` background on canvas, 1px `{colors.hairline}` | Default cards, product panels |
| 2 (surface-2 lift) | `{colors.surface-2}` background, 1px `{colors.hairline-strong}` | Featured cards, hovered cards |
| 3 (surface-3 lift) | `{colors.surface-3}` background | Sub-nav, dropdown menus |
| 4 (focus ring) | 2px `{colors.primary-focus}` outline at 50% opacity | Focused input, focused button |

Depth is carried by surface ladder + hairline borders. Flux resists drop shadows on dark almost entirely.

### Decorative Depth

- **Product UI screenshots** dominate as decorative depth.
- **No atmospheric gradients, no spotlight cards.**
- **Subtle white edge highlight** on the top edge of lifted panels — gives the dark surface a faint "pixel rendered" feel.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.xs}` | 4px | Small chips, status badges |
| `{rounded.sm}` | 6px | Inline tags |
| `{rounded.md}` | 8px | All buttons, form inputs |
| `{rounded.lg}` | 12px | Pricing cards, feature cards, testimonial cards |
| `{rounded.xl}` | 16px | Product screenshot panels |
| `{rounded.xxl}` | 24px | Oversized CTA banners (rare) |
| `{rounded.pill}` | 9999px | Tab toggles, status pills |
| `{rounded.full}` | 9999px | Avatar circles |

### Photography & Illustration Geometry

- Product UI screenshots dominate; they sit in `{rounded.xl}` 16px tiles with `{spacing.lg}` 24px outer padding.
- Customer/logo tiles render at small sizes (~24px logo height) on `{colors.canvas}` with no border.
- Avatar circles in testimonial cards use `{rounded.full}` at 32–40px sizes.

## Components

### Buttons

**`button-primary`** — Lavender CTA, the default primary across all pages. Background `{colors.primary}`, text `{colors.on-primary}`, type `{typography.button}`, padding 8px 14px, rounded `{rounded.md}`. Hover → `{colors.primary-hover}`; pressed → `{colors.primary-focus}`.

**`button-secondary`** — Charcoal button for secondary CTAs. Background `{colors.surface-1}`, text `{colors.ink}`, 1px `{colors.hairline}` border, rounded `{rounded.md}`.

**`button-tertiary`** — Plain text button. Background `{colors.canvas}`, text `{colors.ink}`, rounded `{rounded.md}`.

**`button-inverse`** — White-on-dark inverse CTA. Background `{colors.inverse-canvas}`, text `{colors.inverse-ink}`, rounded `{rounded.md}`.

### Cards & Containers

**`feature-card`** / **`pricing-card`** — Background `{colors.surface-1}`, text `{colors.ink}`, rounded `{rounded.lg}`, padding 24px, 1px `{colors.hairline}` border.

**`pricing-card-featured`** — Surface lift to `{colors.surface-2}` with a `{colors.hairline-strong}` border; otherwise identical.

**`product-screenshot-card`** — The dominant card type, framing a high-fidelity Flux app screenshot. Background `{colors.surface-1}`, rounded `{rounded.xl}`, padding 24px.

**`testimonial-card`** — Customer quote with avatar. Background `{colors.surface-1}`, type `{typography.body-lg}`, rounded `{rounded.lg}`, padding 32px.

**`cta-banner`** — Closing CTA panel. Background `{colors.surface-1}`, type `{typography.headline}`, rounded `{rounded.lg}`, padding 48px.

### Inputs & Forms

**`text-input`** — Background `{colors.surface-1}`, text `{colors.ink}`, rounded `{rounded.md}`, padding 8px 12px, 1px `{colors.hairline}` border. Focused state keeps the same surface; the focus ring is a 2px `{colors.primary-focus}` outline at 50% opacity.

### Status & Navigation

**`status-badge`** — Background `{colors.surface-2}`, text `{colors.ink-muted}`, type `{typography.caption}`, rounded `{rounded.pill}`, padding 2px 8px.

**`top-nav`** — Sticky dark bar, Flux wordmark left, nav links centered, `button-secondary` + `button-primary` pair right. Background `{colors.canvas}`, type `{typography.body-sm}`, height 56px.

**`footer`** — Dense link grid on `{colors.canvas}` with the Flux wordmark left. Text `{colors.ink-subtle}`, type `{typography.caption}`, padding 64px 32px.

## Do's and Don'ts

### Do
- Reserve `{colors.canvas}` (#010102) as the system's anchor surface — the faint blue tint is intentional.
- Use `{colors.primary}` lavender ONLY for: brand mark, primary CTA, focus ring, link emphasis.
- Use the four-step surface ladder for hierarchy. Avoid skipping levels.
- Pair display weight 600 with body weight 400 — resist 700+ display weights.
- Apply negative letter-spacing aggressively on display.
- Use product UI screenshots as the protagonist of every section.
- Compose CTAs with `{rounded.md}` 8px corners.

### Don't
- Don't ship a light-mode marketing surface.
- Don't use lavender as a section background or card fill.
- Don't introduce a second chromatic accent (orange, pink, green) on chrome.
- Don't add atmospheric gradients or spotlight cards.
- Don't pill-round CTAs.
- Don't use `#000000` true black as the canvas.
- Don't combine multiple bright accents in product screenshot mockups.

## Responsive Behavior

### Breakpoints

| Name | Width | Key Changes |
|---|---|---|
| Desktop-XL | 1440px | Default desktop layout |
| Desktop | 1280px | Card grid 3-up maintained |
| Tablet | 1024px | Card grid 3-up → 2-up |
| Mobile-Lg | 768px | Comparison becomes accordion; nav hamburger |
| Mobile | 480px | Single-column; display-xl scales 80px → ~36px |

### Touch Targets
- CTAs hold ≥40px tap height across viewports.
- Tab pills hold ≥36px tap height; touch viewports grow to ≥44px.
- Form inputs hold ≥44px tap target on touch.

### Collapsing Strategy
- **Top nav**: links collapse to hamburger below 768px.
- **Card grids**: 3-up → 2-up at 1024px → 1-up below 768px.
- **Display type**: `{typography.display-xl}` 80px scales toward `{typography.display-md}` 40px on mobile.

### Image Behavior
- Product UI screenshots maintain aspect ratio and never crop.
- Logo marquees may collapse from 6-up to 3-up below 768px.

## Iteration Guide

1. Focus on ONE component at a time and reference it by its `components:` token name.
2. When introducing a section, decide first which surface lift it lives on.
3. Default body to `{typography.body}` at weight 400.
4. Run `npx @google/design.md lint DESIGN.md` after edits.
5. Add new variants as separate component entries.
6. Treat lavender as scarce: brand mark, primary CTA, focus, link emphasis.
7. Lead every section with a product UI screenshot.

## Known Gaps

- The surface-1..4 and hairline-strong/tertiary values are derived (Linear's canonical ladder lives in private `--color-bg-level-*` CSS variables); the documented hex values here are Flux's source of truth.
- Form-field error and validation styling beyond the focus ring is not yet documented.
- Light mode is intentionally undocumented — Flux does not ship a light marketing surface. The app retains a functional light theme that is outside this spec.
- The in-product status palette (pipeline active/paused/stopped, priorities, labels) uses a richer color set (success/warning/error) that lives in product surfaces, not on chrome.
- Flux's substitute fonts are **Inter** (display/text) and **JetBrains Mono** (mono); both are open-source and self-hosted.
