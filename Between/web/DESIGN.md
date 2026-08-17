# Between — Liquid Glass Design Contract

Rules for page agents restyling `web/src/pages/**` and remaining components. The design system
lives in `src/index.css` (materials, motion, ergonomics) + `src/components/ui.tsx` (primitives).
Tailwind v4, CSS-first. No new npm deps, no CSS-in-JS, no framer-motion.

## Materials

| Class | What | Use for |
|---|---|---|
| `.glass` | translucent panel, 20px blur + saturate, hairline, specular top edge, ambient shadow | cards (`Card` already is one), section panels, sidebar/rails |
| `.glass-strong` | more opaque, 28px blur, deeper shadow | modals, command palette, toasts, top/bottom bars, drawers, sheets |
| `.glass-subtle` | translucent tint + hairline + sheen, **no blur** (cheap) | chips, badges, small controls, list-row accents — safe anywhere |
| `.sheen` | specular top inset only | add the glass edge to a colored/custom element |

- All knobs are theme vars (`--glass-*`), auto-adjusted for light themes via `html[data-theme-dark]`
  (set by `applyTheme`). Never hard-code rgba surfaces — glass must work on all 7 themes.
- Material classes live in `@layer components`: **Tailwind utilities always override them**
  (e.g. `glass border-x-0 border-t-0` for a flush bar, `glass bg-surface` to opt out of translucency).
- No-`backdrop-filter` browsers automatically get near-opaque panels; don't add own fallbacks.
- Don't nest `.glass` inside `.glass` more than one level; prefer `.glass-subtle` for inner elements.

## Performance budget (hard rules)

- `backdrop-filter` (i.e. `.glass`/`.glass-strong`) ONLY on chrome-level surfaces: sidebar, topbar,
  bottom dock, cards, modals, palette, toasts. NEVER on per-row list items, table rows, or tiny
  elements — use `.glass-subtle`/`.sheen` there (blur-free by design).
- Aim for ≤ ~8 blurred surfaces per view. No `will-change`. No infinite animations except
  `.pulse-dot`/spinners.
- Sanctioned exceptions: the `.app-bg` `ambient-drift` backdrop animation — desktop-only (≥64rem),
  transform-only (composited), and gated behind `prefers-reduced-motion: no-preference` — and the
  `.skeleton` shimmer sweep (transient: skeletons unmount when content arrives; same transform-only
  + reduced-motion gating). Don't add more.

## Motion

- `.fade-in-up` — page/section entry (0.35s, soft ease-out). Route content is already wrapped in it
  by `Layout`; use it inside pages for late-loading sections.
- `.scale-in` — modals/popovers (springy, 0.3s). Transform-origin: center; override with `origin-*`.
- `.slide-up-sheet` — mobile bottom sheets. `.slide-in-left` — side drawers. `.fade-in` — overlays/backdrops.
- Motion classes are `@utility` definitions → variant-capable: `sm:scale-in`, `max-sm:fade-in`, …
  (Modal does `slide-up-sheet sm:scale-in`). No arbitrary `[animation:…]` overrides needed.
- `.stagger` — put on a grid/list CONTAINER whose children carry `.fade-in-up` (or `.scale-in`);
  children get +40ms each, capped at 8. Use for card grids, not long tables.
- `.pressable` — springy press (scale 0.97) + its own multi-prop transition. All ui.tsx controls have
  it. Do NOT combine with `transition-*` utilities (they override its transition shorthand).
- Entry animations use `backwards` fill on purpose — a retained transform would trap
  `position: fixed` descendants (modals). Keep it that way for new keyframes.
- `prefers-reduced-motion: reduce` globally collapses all animations/transitions (spinners exempt).
  Never add motion that bypasses this (no JS-driven animation loops).

## Fluid type & the px→rem rule

- Root font-size is fluid: `clamp(13.5px, 12.6px + 0.22vw, 16px)`. Everything in rem breathes.
- Arbitrary text sizes MUST be rem, not px: `text-[13px]` → `text-[0.8125rem]`,
  `text-[11px]` → `text-[0.6875rem]`, `text-[15px]` → `text-[0.9375rem]`, `text-[10px]` → `text-[0.625rem]`.
  Named sizes (`text-xs`…) are already rem. Exception: mono/terminal text may stay px.
- Numbers that update live (stats, uptimes, counters): add `.tabular` (tabular-nums).
- Titles: `font-display font-bold tracking-tight` (SF-style stack; `.font-display` already tightens
  letter-spacing to −0.02em).
- Micro-labels: ALL content micro-labels (field labels, stat/metric captions, form-section
  headings) use the `.microlabel` component class — `text-[0.6875rem] font-semibold uppercase
  tracking-[0.08em] text-muted` (`Field`'s label already is one). Override per instance with
  utilities if needed (`microlabel text-accent`). The tinier `0.625rem`/`tracking-[0.14em]`
  variant is reserved for chrome ONLY (nav section labels, palette group headers, dock labels) —
  never for page content, and never invent a third spec.

## Spacing, radius, layout

- Radius scale: `rounded-2xl` cards/panels · `rounded-xl` controls/inputs/nav items ·
  `rounded-full` pills/badges/segmented/docks · `rounded-lg` ONLY for nested micro-elements
  under 32px (kbd chips, sm buttons, tiny icon chips, checkbox). `rounded-md`/`rounded-sm`
  never. Don't invent other radii.
- Spacing rhythm: ONE gutter per page. Dashboard-class pages (Dashboard, Servers, Catalog,
  Blueprints): card grids `gap-4`, sections `mb-6`. Dense detail pages (server-detail tabs,
  admin/settings): `gap-3` grids, `mb-5` sections. Never mix two gutters between adjacent
  rows/sections of one page.
- Page content container comes from `Layout` (`max-w-7xl`, fluid padding, bottom padding for the
  mobile dock). Don't add own max-width wrappers unless a page needs a narrower column.
- Tablet band (`md:` 768–1023, still mobile chrome): step density up instead of stretching phone
  layouts — compact stat strips go back to 4-up (`md:grid-cols-4`), the dashboard 2:1 split starts
  at `md:grid-cols-3`, toasts become right-aligned `md:w-80` cards, drawer `md:w-80`, dock `md:max-w-md`.
- Full-bleed bars: `glass-strong border-x-0 border-t-0` (or `border-b-0` for bottom bars).
- Safe areas: `.safe-top`/`.safe-bottom` on a wrapper WITHOUT its own padding on that side
  (env() replaces padding utilities); inner element carries the visual padding.

## Touch & focus

- Touch targets: `@media (pointer: coarse)` bumps `.ui-control` to min-height 44px and `.icon-btn`
  to min-width 44px. ui.tsx applies these classes; add `ui-control` to any custom interactive
  control you build in a page.
- Focus standard: `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40`
  on every interactive element (already in all ui.tsx primitives). Inputs use `focus:` ring instead.
- Icon-only buttons need `aria-label` — prefer `IconButton` which enforces it.

## Primitives (ui.tsx) — same APIs as before, plus:

- `SegmentedControl` — iOS segmented tabs.
  `<SegmentedControl options={[{ value: 'a', label: 'A', icon? }]} value={v} onChange={setV} size?='sm'|'md' />`
  Equal-width segments, animated thumb, radiogroup semantics. Use for view switches (grid/list,
  tab-like filters), NOT for navigation (use NavLink) or forms (use Select).
- `IconButton` — `<IconButton label={t('…')} variant?='ghost'|'glass' size?='sm'|'md'>{icon}</IconButton>`
  for toolbars; `label` becomes aria-label + title.
- `Button`: primary = accent gradient + glow, secondary = glassy, all pressable + focus-ringed.
  `Card` = `.glass rounded-2xl` (merge className to extend/opt out). `Badge` = glass-subtle pill
  (color it via className: `bg-success/10 text-success border-success/30`). `Toggle` = iOS switch.
- `Checkbox` — glass checkbox, replaces every native `input[type=checkbox]`:
  `<Checkbox checked={v} onChange={(e) => setV(e.target.checked)} label?='Read-only' disabled? />`.
  A real controlled `<input type="checkbox">` (native onChange/ChangeEvent contract) skinned as an
  18px glass-subtle `rounded-lg` square with an accent-gradient fill + check when checked.
  `label` renders an inline text label; pass `aria-label` when omitting it. `className` extends
  the outer `<label>` wrapper.
- Combine `Card` + `card-hover` for interactive/clickable cards (lift + accent border + press).
- Actions embedded in a `CardHeader` (per-card Save etc.) are ALWAYS `size="sm"` — one scale for
  header chrome on every surface (panel settings, server Settings/Config).
- Display overrides on primitives (Badge etc.): same-layer display utilities resolve by STYLESHEET
  order, not className order — hide responsively with additive `max-sm:hidden`, never by fighting
  the base (`hidden sm:inline-flex` via className is unreliable).
- Input/Select/TextArea have base `w-full`; `w-*` via className is equally unreliable — size them
  with a wrapper width (`max-w-xs`) or `min-w-*` instead. Do not change the components.
- `IconButton` takes `loading` (spinner replaces the icon + disables), same contract as `Button`.
- `Chip` — filter/category pill: `<Chip active={v === x} onClick={…}>label</Chip>`. Glass-subtle
  idle, accent-tint active, `aria-pressed`, `type="button"`. Use for filter bars, not navigation.
- `Skeleton` — loading placeholder: `<Skeleton className="h-4 w-40 rounded-full" />`. Glass-subtle
  block with a shimmer sweep (static under reduced motion), base radius rounded-xl, blur-free (safe
  per row). Compose content-shaped loaders that mirror the real layout (see DashboardSkeleton /
  ServerCardSkeleton / ServerDetailSkeleton) so the content swap doesn't jump. Use for the initial
  load of full surfaces; keep `Spinner` for buttons and small inline waits. Always `aria-hidden`;
  put `aria-busy` on the loading wrapper.
- `EmptyState` takes an optional `body`: with it, `title` renders as a heading and `body` as the
  muted line — use for inviting zero states with CTAs (see Servers' first-run empty state).

## Tables on mobile

Pick one per table:
1. Wrap in `<div className="table-scroll">` — horizontal scroll, trailing-edge fade on touch
   screens. Good for dense admin tables (audit log, users).
2. Convert to stacked cards below `sm:` (`hidden sm:table` + a `sm:hidden` card list). Prefer this
   for primary content (server lists) where each row has an obvious card shape.
Never let a table blow up page width — `main` scrolls vertically only.

## Overlays (owned by other agents, expectations)

- Modal: `.glass-strong rounded-2xl`, backdrop `bg-black/50 backdrop-blur-sm .fade-in`; animation is
  `slide-up-sheet sm:scale-in` (bottom sheet below `sm:` with `rounded-t-2xl .safe-bottom`).
- Toasts: `.glass-strong rounded-xl .fade-in-up`, bottom-right desktop; above the dock on mobile
  (dock occupies bottom ~5.5rem + safe-area).
- Command palette: `.glass-strong rounded-2xl .scale-in origin-top`.

## Theming & tokens

- Use ONLY token utilities: `bg-surface`, `bg-elevated`, `text-text`, `text-muted`, `border-line`,
  `accent`/`accent2`, `success`/`warn`/`danger`, and alpha variants (`bg-accent/15`). Never hex.
- Tertiary metadata may be de-emphasized with `text-muted/70`; sub-AA contrast is accepted ONLY for
  redundant/decorative metadata (duplicated or purely ornamental info), never for sole information.
- Legacy classes still exist and are retuned — keep using them: `app-bg`, `text-gradient`,
  `btn-gradient`, `card-hover`, `glow-success`, `pulse-dot`, `console-scroll`. New: `glow-accent`
  (accent shadow for primary/branded elements).
- Console surfaces (Terminal/Shell scrollback) use the fixed dark `--console-bg` token via
  `bg-(--console-bg)` — the one deliberate theme-invariant surface. `.console-scroll` also carries
  a low-alpha white scrollbar thumb tuned to it (readable on light themes too).
- ALL text rendered on a console surface must be theme-invariant too: use the pinned
  `--console-text*` tokens (`text-(--console-text)`, `-dim` for timestamps/empty states,
  `-stderr`/`-system`/`-input`/`-install` for stream styles) — never `text-text`/`text-muted`/
  theme accents there (near-black on light themes → black-on-black).
- Global thin/themed scrollbars live in `@layer base` — utilities beat them without `!`:
  hide with `[scrollbar-width:none] [&::-webkit-scrollbar]:hidden`.
- Don't touch `themes.ts` values; if a theme needs a glass tweak, it goes through `--glass-*` vars.

## i18n

- All UI strings via `t('key')`; en.ts is the source of truth, de.ts must mirror every key.
- Reuse existing keys. Only add new keys when your brief explicitly grants it — append at the END
  of both files, natural German (not machine-literal).

## Do / Don't

- DO test every change on `slate-light` (Daylight) AND one dark theme + `carbon` (pure black).
- DO keep `.console-scroll` semantics (overflow-anchor/scroll-behavior) untouched.
- DON'T add px font sizes, new radii, new fonts, shadows with hard-coded dark rgba (use vars).
- DON'T put blur on elements that repeat per row; DON'T animate `height`/`width`/`top`/`left` —
  transform/opacity only.
- DON'T introduce local `useEffect` scroll/resize listeners for styling — CSS first.
