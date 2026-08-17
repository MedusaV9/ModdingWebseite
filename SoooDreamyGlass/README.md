# BAPBAP Modding

Multi-page fan site (v1.0) for **BAPBAP Modding** — a community modding project
for the Steam game BAPBAP. It showcases the BAPHub mod catalog, community game
modes (Boss Rush, Battle Royale Playtest, Version Time Machine), the BAPBAP
Nexus launcher, the in-launcher radio, a getting-started guide and modder
publishing docs. Built with Vite, React 19, TypeScript, and Tailwind CSS v4 in
a dark gaming aesthetic (pink/red gradient accents, Archivo Black / Teko /
Inter).

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

- `src/App.tsx` — HashRouter route table; `src/Layout.tsx` — shared Navbar/Footer shell
- `src/pages/` — one component per route (Home, ModsPage, ModDetailPage, ModesPage, LauncherPage, RadioPage, GuidePage, ModdersPage, CommunityPage, NotFound)
- `src/components/` — reusable UI (Navbar, Footer, Marquee, GradientButton, SectionHeading, Badge, ModCard, ModImage, ScrollToTop)
- `src/sections/` — home-page sections (Hero, HowItWorks, plus legacy single-page sections)
- `src/hooks/` — `useReveal` scroll-reveal hook (IntersectionObserver, respects `prefers-reduced-motion`), `usePageTitle`
- `src/data/` — **all site content lives here**: `mods.ts` (BAPHub catalog), `modes.ts` (game modes/tracks), `launcher.ts` (Nexus features + changelog), `radio.ts` (soundtrack station), `versions.ts` (archived builds), `bundles.ts` (game-mode bundles), `links.ts` (external URLs). Edit these files to change what the pages show — no component changes needed.

## Asset drop-in convention

The site renders fine with no local art — visuals are CSS gradients, inline
SVG, or remote images with graceful fallbacks. Real art can be dropped into
`public/assets/` later using these filenames (no code changes needed, see
`public/assets/README.md`):

| File                 | Used for                                          |
| -------------------- | ------------------------------------------------- |
| `logo.svg`           | Navbar logo (replaces the text wordmark)          |
| `hero-art.png`       | Hero section character art                        |
| `og-image.png`       | Social preview image (Open Graph / Twitter card)  |
| `mods/<mod-id>.png`  | Per-mod card image overrides (falls back to the remote BAPHub thumbnail, then a styled placeholder) |
