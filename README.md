# BAPBAP Modding

Multi-page fan site (v3) for **BAPBAP Modding** — a community modding project
for the Steam game BAPBAP. It showcases the BAPHub mod catalog, community game
modes (Boss Rush, Battle Royale Playtest, Version Time Machine), the BAPBAP
Nexus launcher, the in-launcher radio, a getting-started guide and modder
publishing docs. Built with Vite, React 19, TypeScript, and Tailwind CSS v4 in
a dark gaming aesthetic (pink/red gradient accents, Archivo Black / Teko /
Inter, sharp corners and hard offset shadows).

## Features

- **EN/DE language switcher** — the whole UI ships in English and German.
  All UI strings live in a typed i18n layer (`src/i18n/`): `en.ts` defines
  the `Dict` shape, `de.ts` must `satisfies Dict`, so a missing key in either
  language fails `tsc -b`. Components read strings via the `useI18n()` hook;
  the choice persists in `localStorage` (`bapbap-locale`), updates
  `<html lang>` and re-localizes titles/meta per route. Site *data*
  (mod catalog, changelog, track names in `src/data/`) stays English by
  design.
- **Installable PWA with offline app shell** — `public/manifest.webmanifest`
  plus a hand-written service worker (`public/sw.js`, no dependencies).
  Navigations are network-first (HTML never goes stale), content-hashed
  `/assets/` files and Google Fonts are cache-first, and remote mod
  thumbnails are deliberately never cached (the initials tile is the designed
  offline fallback). The SW registers in production builds only — dev on
  :5173 stays SW-free.
- **Card visuals gallery** — all 28 launcher `visual.preset` card effects
  rendered live in pure CSS on `/modders`: pick a swatch, preview it on the
  effect test card, copy the manifest snippet.
- **Creator filter & profiles** — `/mods` filters by creator (derived from
  the catalog in `src/lib/authors.ts`, composable with search/type/tags/sort
  through URL params), and `/community` shows creator credit cards linking to
  each creator's filtered catalog.
- **Command palette** — global fuzzy search over mods, pages and actions.
  Opens with `/` or `Ctrl/Cmd+K` (or the search button in the navbar);
  navigate with `↑`/`↓`, `Enter` to open, `Esc` to close.
- **Radio visualizer deck** — animated equalizer, transport controls,
  scrubber and auto-advance for the 15-track soundtrack station (no audio
  files ship with the site; full playback lives in the launcher).
- **SVG brand kit** — hand-drawn `Emblem`, `BrandMark`, angular `Icon` set and
  comic stickers in `src/components/brand/`, no icon library.
- **Route code-splitting** — every page is a `React.lazy` chunk behind a
  shared `PageLoader`, so the initial bundle stays lean.
- **Fullscreen mobile nav** — staggered overlay menu with focus trap, body
  scroll lock and Escape-to-close.
- **A11y** — skip-to-content link, `aria-current` nav state, global pink
  `:focus-visible` outline, and all motion gated behind
  `prefers-reduced-motion`.
- **Per-route meta** — every page sets its own localized title/description/OG
  tags via `usePageMeta`; a default social preview image lives at
  `public/assets/og-image.png`.

## Routes

Routing uses react-router-dom v7 with **HashRouter** — the site is deployed as
static files with no SPA fallback, so hash URLs are the only way deep links
like `/#/mods/<id>` survive a refresh (a `BrowserRouter` deep link would 404).
Routes are declared in `src/App.tsx`:

| Route         | Page                                                    |
| ------------- | ------------------------------------------------------- |
| `/`           | Home (hero, featured mods, modes/launcher teasers)      |
| `/mods`       | Full BAPHub catalog with search, filters and sorting    |
| `/mods/:id`   | Mod detail (meta, version history, related mods)        |
| `/modes`      | Game modes & tracks, Boss Rush, BR bundle, Time Machine |
| `/launcher`   | BAPBAP Nexus download, requirements, full changelog     |
| `/radio`      | The 15-track in-launcher soundtrack station             |
| `/guide`      | Getting started: 6-step install walkthrough + FAQ       |
| `/modders`    | BAPHub publishing guide (manifest format, visuals)      |
| `/community`  | Discord banner, trailer, credits, disclaimer            |
| anything else | 404                                                     |

## Quickstart

```bash
npm install
npm run dev     # dev server on http://localhost:5173
```

## Scripts

| Script            | What it does                                  |
| ----------------- | --------------------------------------------- |
| `npm run dev`     | Start the Vite dev server with HMR            |
| `npm run build`   | Type-check (`tsc -b`) and build to `dist/`    |
| `npm run lint`    | Lint with [oxlint](https://oxc.rs) (not ESLint) |
| `npm run preview` | Serve the production build on port 4173       |

## Project structure

- `src/App.tsx` — HashRouter route table with `React.lazy` per route; `src/Layout.tsx` — shared shell (skip link, Navbar, Footer, CommandPalette, Suspense/PageLoader)
- `src/main.tsx` — app bootstrap + production-only service-worker registration
- `src/i18n/` — the typed EN/DE layer: `en.ts` (source of truth for the `Dict` shape), `de.ts` (`satisfies Dict` — a missing key fails the build), `context.ts` (`useI18n`, locale detection, `bapbap-locale` storage key), `LanguageProvider.tsx`
- `src/pages/` — one component per route (Home, ModsPage, ModDetailPage, ModesPage, LauncherPage, RadioPage, GuidePage, ModdersPage, CommunityPage, NotFound)
- `src/components/` — reusable UI (Navbar, Footer, CommandPalette, LanguageSwitcher, RadioPlayer, PresetShowcase, Marquee, GradientButton, SectionHeading, Badge, ModCard, ModImage, ModeArt, PageLoader, ScrollToTop)
- `src/components/brand/` — the SVG brand kit (`Emblem`, `BrandMark`, `Icon`, `Sticker`)
- `src/sections/` — home-page sections (Hero, HowItWorks)
- `src/hooks/` — `useReveal` (scroll reveal with optional stagger), `useCountUp` (animated stats), `useClipboard` (copy affordances), `usePageMeta` (per-route title/description/OG tags); all respect `prefers-reduced-motion` where relevant
- `src/lib/` — small helpers: `randomMod.ts` (`randomModId()` behind every "Surprise me"), `formatDuration.ts`, `authors.ts` (creator list derived from the catalog — drives the `/mods` creator filter and `/community` credits)
- `src/data/` — **all site content lives here**: `mods.ts` (BAPHub catalog), `modes.ts` (game modes/tracks), `launcher.ts` (Nexus features + changelog), `radio.ts` (soundtrack station), `versions.ts` (archived builds), `bundles.ts` (game-mode bundles), `presets.ts` (the 28 card-visual preset ids for the gallery), `links.ts` (external URLs). Data stays English by design. Edit these files to change what the pages show — no component changes needed.
- `public/manifest.webmanifest` + `public/sw.js` — PWA install manifest and the hand-written offline app-shell service worker (network-first HTML, cache-first hashed assets/fonts, remote thumbnails never cached; bump `CACHE` in `sw.js` when precached files change)

## Asset drop-in convention

The site renders fine with no local art — visuals are CSS gradients, inline
SVG, or remote images with graceful fallbacks. Real art can be dropped into
`public/assets/` later using these filenames (no code changes needed, see
`public/assets/README.md`):

| File                    | Used for                                          |
| ----------------------- | ------------------------------------------------- |
| `logo.svg`              | Navbar logo (replaces the text wordmark)          |
| `hero-art.png`          | Hero section character art                        |
| `og-image.png`          | Social preview image (Open Graph / Twitter card)  |
| `icon-512.png`          | PWA icon 512×512 (`any` + `maskable`), generated from `scripts/icon-template.html` |
| `icon-192.png`          | PWA icon 192×192, generated                       |
| `apple-touch-icon.png`  | iOS home-screen icon 180×180, generated           |
| `mods/<mod-id>.png`     | Per-mod card image overrides (falls back to the remote BAPHub thumbnail, then a styled placeholder) |

The `og-image.png` and the three icon files are generated with headless
Chrome from `scripts/og-template.html` / `scripts/icon-template.html` — the
exact commands are documented in `public/assets/README.md`.
