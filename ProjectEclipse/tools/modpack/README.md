# tools/modpack — dev pack fetcher + distributable `.mrpack` generator

Two stdlib-only Python scripts:

- `fetch_dev_mods.py` — fills `run/mods` / `run/mods-client` for local dev runs (exact jars
  from the README "Server pack" matrix).
- `build_mrpack.py` — builds the **distributable** event pack as a Modrinth `.mrpack`
  (plans_v5 D9), driven by `pack_manifest.json`.

## Building the pack

```
./gradlew build                          # produces build/libs/eclipse-<version>.jar
python3 tools/modpack/build_mrpack.py    # writes dist/eclipse-event-<version>.mrpack
python3 tools/modpack/build_mrpack.py --verify   # CI-friendly: sha512-checks every reference
```

What lands where:

| Artifact | Content |
|---|---|
| `dist/eclipse-event-<v>.mrpack` | `modrinth.index.json` (download references: URL + sha1/sha512 + size + client/server env per mod, pinned `minecraft 1.21.1` / `neoforge 21.1.238`) + `overrides/` |
| `overrides/mods/eclipse-<v>.jar` | The Eclipse jar itself (ARR but ours — the only mod jar embedded) |
| `overrides/config/eclipse/` | Default config seeds (from `run/config/eclipse`) |
| `overrides/MANUAL_INSTALL.md` | Operator note for the two non-CDN mods (Aeronautics bundle, Sable) |
| `tools/modpack/mods_manifest.json` | Committed inventory: exact name + version + URL + sha512 per mod (regenerated on every build) |

`dist/` is gitignored — **commit the generator, never the pack binary**.

## Why an `.mrpack` instead of a mods zip?

A zip full of jars would redistribute Sophisticated Backpacks/Core (ARR), Simple Voice Chat
(custom/ARR), Supplementaries ("public redistribution prohibited") and Create's restricted
assets — all explicitly forbidden (see `docs/BUNDLING.md`). The `.mrpack` format ships only
*references* (official Modrinth download URLs plus hashes); the launcher downloads each jar
from its rightful host at install time. Same one-click result as a zip, zero license
violations, and hash-pinned so nobody can swap a jar unnoticed. The committed
`mods_manifest.json` is the human-readable equivalent if you just want the list.

## Importing the pack

- **Modrinth App**: File → *Add instance* → *From file* → pick the `.mrpack`.
- **Prism Launcher / ATLauncher / MultiMC forks**: *Add Instance* → *Import* → select the
  `.mrpack` (Prism imports mrpack natively).
- After import, follow `MANUAL_INSTALL.md` inside the instance folder for the two
  operator-supplied jars, then join the event server.

## Is a separate Forgified Fabric API install needed? **No.**

The `fabric_api_base`, `fabric_block_view_api_v2`, `fabric_renderer_api_v1` and
`fabric_rendering_data_attachment_v1` mod ids that show up on clients are **Forgified Fabric
API sub-modules jarJar'd INSIDE the Sodium and Iris NeoForge builds** (verified by unpacking
the jars — see `docs/BUNDLING.md`, "Nested (jar-in-jar) mod ids"). No pack mod depends on a
standalone Forgified Fabric API, so there is nothing to install; the ids are allowlisted in
the mod checker and appear automatically when the optional Sodium/Iris extras are present.
Installing a standalone FFAPI would only add an unknown mod to your report — don't.

Likewise EMI, Mouse Tweaks, Veil and GeckoLib are embedded inside the Eclipse jar itself —
never install them separately (`mods_manifest.json` marks them `embedded-in-eclipse-jar`).
