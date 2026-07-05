# ModdingWebseite — BAPBAP Modding

A multi-page marketing/community website for **BAPBAP Modding** (a fan-made community modding project for the Steam roguelike party game *BAPBAP*). Built with **Vite + React + TypeScript + Tailwind CSS v4** as a static SPA. Primary community CTA is the Discord `discord.gg/BAPBAPMods`.

## Cursor Cloud specific instructions

- **Node**: use the nvm-provided Node (v22.x). If `node`/`npm` are not on `PATH` in a fresh shell, run `source ~/.nvm/nvm.sh` first. The package manager is **npm** (there is a `package-lock.json`; do not use yarn/pnpm).
- **Run the app (dev)**: `npm run dev` serves on `http://localhost:5173`. There is no backend — it's a purely static frontend, so no DB/env vars/services are required.
- **Other scripts**: `npm run build` (`tsc -b` in strict mode + `vite build`), `npm run preview` (serves the production build on `http://localhost:4173`).
- **Lint gotcha**: `npm run lint` runs **oxlint**, NOT eslint (this is what the current `create-vite` react-ts template ships). There is a `.oxlintrc.json`, no `eslint.config.js`.
- **Routing**: the site is multi-page via react-router-dom v7 **HashRouter** (deliberate — the static host has no SPA fallback, so only `/#/...` deep links survive refresh). Routes live in `src/App.tsx`, page components in `src/pages/`, and the shared Navbar/Footer shell in `src/Layout.tsx`.
- **Content lives in data files**: all site content (mod catalog, game modes, launcher features/changelog, radio track list, archived builds, bundles, external links) is hardcoded in `src/data/` (`mods.ts`, `modes.ts`, `launcher.ts`, `radio.ts`, `versions.ts`, `bundles.ts`, `links.ts`). Edit these to update the catalog — pages in `src/pages/` (and the home sections in `src/sections/`) render from them.
- **Assets are optional / drop-in**: the site renders fully with no local image assets (visuals are CSS gradients/SVG). Real art can be dropped into `public/assets/` using the filenames documented in `public/assets/README.md` (`logo.svg`, `hero-art.png`, `og-image.png`, `mods/<mod-id>.png`). Mod cards try a local `/assets/mods/<id>.png` first, then fall back to a remote `raw.githubusercontent.com` thumbnail, then to a generated initials tile — so mod thumbnails depend on outbound network access unless local overrides are added.
