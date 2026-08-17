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
- **`SoooDreamy/` subproject (branch `cursor/soodreamy-ab64`)**: an unrelated iOS couple app (SwiftUI, iOS 17+) + Node.js server living under `SoooDreamy/`; it does not touch the website. Read `SoooDreamy/UserFeedback.md` before iterating and keep server/client API changes in lockstep with `SoooDreamy/docs/API.md`.
- **SoooDreamy design charter (binding)**: read `SoooDreamy/DESIGN.md` BEFORE touching any SwiftUI view — it defines the 15 quality commandments, the named token system (glass levels, `Space`/`Radius`/`Theme.Motion`/`Typo`/`CoupleTint`) and the Noble test. `bash SoooDreamy/tools/charter_lint.sh` is a CI ratchet: the slop counters in `SoooDreamy/tools/charter_baseline.json` may only go down; lower them with `--update` in the same commit as your cleanup.
- **SoooDreamy server gate**: `cd SoooDreamy/server && npm ci && npm test` (node:test, no DB needed).
- **Swift 6 on Cursor Cloud / Ubuntu 24.04**: install the pinned toolchain once with:
  ```bash
  SWIFT_VERSION=6.0.3
  sudo apt-get update -qq
  sudo apt-get install -y libncurses6 libcurl4t64 libxml2 libsqlite3-0 libedit2 libpython3.12 libz3-4
  mkdir -p "$HOME/.local/swift"
  curl -fL "https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz" -o /tmp/swift.tar.gz
  tar -xzf /tmp/swift.tar.gz -C "$HOME/.local/swift" --strip-components=1
  export PATH="$HOME/.local/swift/usr/bin:$PATH"
  ```
  Add the final `export` to `~/.profile` for later shells. Then run `swift test --package-path SoooDreamy/ios`. `Package.swift` cherry-picks only Foundation-compatible sources, including all DE/EN localization tables.
- **Swift syntax gate**: `mapfile -d '' sources < <(git ls-files -z ':(glob)SoooDreamy/ios/**/*.swift'); for source in "${sources[@]}"; do swiftc -parse "$source"; done`. Parse each source separately because `scripts/GenerateIcon.swift` intentionally contains top-level script statements.
- **iOS build gate**: Linux cannot build the app target. `.github/workflows/sooodreamy.yml` runs the Node and Swift gates, builds the unsigned versioned IPA with XcodeGen on macOS, and captures DE/EN simulator screenshots. Verify the external release-farm run before accepting a version.
