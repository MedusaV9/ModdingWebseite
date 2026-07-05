# BAPBAP Modding

Single-page marketing site for **BAPBAP Modding** — a community modding project
for the Steam game BAPBAP. It showcases the BAPHub mod catalog, community game
modes (Boss Rush, Battle Royale Playtest, Version Time Machine) and the BAPBAP
Nexus launcher. Built with Vite, React 19, TypeScript, and Tailwind CSS v4 in a
dark gaming aesthetic (pink/red gradient accents, Archivo Black / Teko / Inter).

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

- `src/components/` — reusable UI (Navbar, Footer, Marquee, GradientButton, SectionHeading, Badge, ModCard)
- `src/sections/` — page sections (Hero, Mods, GameModes, Launcher, HowItWorks, Community)
- `src/hooks/` — `useReveal` scroll-reveal hook (IntersectionObserver, respects `prefers-reduced-motion`)
- `src/data/` — **all site content lives here**: `mods.ts` (BAPHub catalog), `modes.ts` (game modes/tracks), `launcher.ts` (Nexus features + changelog), `links.ts` (external URLs). Edit these files to change what the page shows — no component changes needed.

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
