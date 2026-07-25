# Eclipse mod bundling and pack policy

Eclipse uses NeoForge jar-in-jar only where the whole dependency may legally be redistributed.
A technical ability to nest a jar is not permission to redistribute it. Mods marked external
must remain separate official downloads in the event pack.

## Bundled and external inventory

| Mod | Pinned version | License | jarJar | Why | Official download/source |
|---|---:|---|:---:|---|---|
| Eclipse Event | 2.1.0 | ARR | main jar | Project artifact, not a dependency | This repository |
| Veil | 4.3.0 | LGPL-3.0 | Yes | Redistribution permitted; required VFX runtime already embedded | [BlameJared Maven](https://maven.blamejared.com/foundry/veil/) / [source](https://github.com/FoundryMC/Veil) |
| GeckoLib | 4.9.2 | MIT | Yes | Permissive license; required animation runtime | [GeckoLib Maven](https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/) / [source](https://github.com/bernie-g/geckolib) |
| EMI | 1.1.24+1.21.1 | MIT | Yes | Permissive QoL mod; exact build matches the EMI plugin contract (newest +1.21.1 neoforge build, verified resolvable 2026-07) | [TerraformersMC Maven](https://maven.terraformersmc.com/releases/dev/emi/emi-neoforge/1.1.24+1.21.1/) / [Modrinth](https://modrinth.com/mod/emi/version/1.1.24+1.21.1+neoforge) |
| Mouse Tweaks | 2.26.1 (NeoForge 1.21/1.21.1) | BSD-3-Clause | Yes | Permissive, client-only QoL mod; its nested jar retains client-side metadata. No newer 1.21.1 NeoForge build exists (checked 2026-07: 2.28/2.30 target 1.21.5+ only) | [Modrinth](https://modrinth.com/mod/mouse-tweaks/version/1.21-2.26.1-neoforge) |
| Create | 6.0.10 | MIT code; restricted/ARR art assets | No | The full jar contains assets not cleared for redistribution | [Modrinth](https://modrinth.com/mod/create) |
| Create: Crafts & Additions | 1.6.0 | MIT | No | Legally bundleable, but remains beside its external Create dependency for pack consistency | [Modrinth](https://modrinth.com/mod/createaddition) |
| Farmer's Delight | 1.21.1-1.3.2 | MIT | No | Legally bundleable; kept external for pack consistency and jar size | [Modrinth](https://modrinth.com/mod/farmers-delight) |
| Supplementaries | 1.21.1-3.8.3 | Custom, public redistribution prohibited | No | License does not permit rebundling | [Modrinth](https://modrinth.com/mod/supplementaries) |
| Moonlight Lib | 1.21.1-3.1.1 | LGPL with additional clauses | No | External dependency of Supplementaries; keep with its parent mod | [Modrinth](https://modrinth.com/mod/moonlight) |
| Sophisticated Backpacks | 1.21.1-3.25.71.1997 | ARR | No | Redistribution not permitted | [CurseForge](https://www.curseforge.com/minecraft/mc-mods/sophisticated-backpacks) |
| Sophisticated Core | 1.21.1-1.4.77.2173 | ARR | No | Redistribution not permitted; external Backpacks library | [CurseForge](https://www.curseforge.com/minecraft/mc-mods/sophisticated-core) |
| Simple Voice Chat | 1.21.1-2.6.16 | Custom/ARR | No | Redistribution not permitted | [Modrinth](https://modrinth.com/plugin/simple-voice-chat) |
| Create: Aeronautics bundle (Aeronautics, Simulated, Offroad) | 1.3.0 | Simulated Project License; no redistribution | No | Private bundled build is not on a public CDN and its license forbids rebundling; install the authorized event-pack jar manually | Event-pack operator source; project id [oWaK0Q19](https://modrinth.com/project/oWaK0Q19) is informational only |
| Sable | 2.0.3 | PolyForm Shield 1.0.0 | No | Notice-based distribution may be possible, but noncompete terms and mixin risk make external installation the safe policy | Official Sable release source supplied by the event-pack operator |
| Sodium | 0.8.12+mc1.21.1 | LGPL-3.0 | No | Optional client performance extra; never belongs on the dedicated server | [Modrinth](https://modrinth.com/mod/sodium) |
| Iris | 1.8.14-beta.1+mc1.21.1 | LGPL-3.0 | No | Optional client shader extra; never belongs on the dedicated server | [Modrinth](https://modrinth.com/mod/iris) |
| End's Delight | 2.6.1+neoforge.1.21.1 | MIT | No (proposed) | C19 optional content; keep external with Farmer's Delight until the orchestrator approves the pack addition | [Modrinth](https://modrinth.com/mod/ends-delight/version/2.6.1+neoforge.1.21.1) |
| Create Confectionery | 1.1.2 | MIT | No (proposed) | C19 optional content; external alongside Create for pack consistency | [Modrinth](https://modrinth.com/mod/create-confectionery/version/1.1.2) |
| Create: Connected | 1.3.2-mc1.21.1 | AGPL-3.0-or-later plus notices | No (proposed) | C19 optional content; a separate jar preserves mere aggregation and its source/license notices | [Modrinth](https://modrinth.com/mod/create-connected/version/1.3.2-mc1.21.1) / [source](https://github.com/hlysine/create_connected) |
| Photon | mc1.21.1-2.1.5-neoforge | GPL-3.0 (Modrinth lists "LicenseRef-Custom", but the linked LICENSE file and the jar's mods.toml both say GPL-3.0 — verified 2026-07) | No | Identity RESOLVED: Modrinth `photon-editor` (id `gzevkJbM`, Low Drag MC/KilaBash, "Photon, a VFX library") with current NeoForge 1.21.1 builds. GPL-3.0 is copyleft — nesting it inside the ARR Eclipse jar is a license-compat trap, so it stays an OPTIONAL external install consumed via the reflection-only `veilfx/PhotonBridge` (see below) | [Modrinth](https://modrinth.com/mod/photon-editor/version/mc1.21.1-2.1.5-neoforge) / [Modrinth Maven](https://api.modrinth.com/maven/maven/modrinth/photon-editor/mc1.21.1-2.1.5-neoforge/photon-editor-mc1.21.1-2.1.5-neoforge.pom) (verified resolvable 2026-07) |
| LDLib2 | mc1.21.1-2.2.29-neoforge | LGPL-3.0-only | No | Required runtime dependency of Photon (its mods.toml pins `ldlib2 [2.2.24,)`); rides with the optional Photon install only | [Modrinth](https://modrinth.com/mod/ldlib) (slug `ldlib`, mod id `ldlib2`) |
| Axiom | 1.21.1 line is Fabric-only | ARR | N/A | No compatible NeoForge artifact and redistribution is not permitted | [Modrinth](https://modrinth.com/mod/axiom) |

The resulting Eclipse jar is not a true “one jar” pack. Create assets, Supplementaries,
Sophisticated, Voice Chat and Aeronautics are legal blockers; nesting them would not change
their licenses.

## Nested (jar-in-jar) mod ids — and the Forgified Fabric API question

Several external pack jars nest their own jar-in-jar mods. NeoForge registers every nested
mod in the global ModList, so these ids show up in modlist reports and MUST be allowlisted or
they are flagged UNKNOWN even on a perfectly correct install (the v5 bug report). Verified by
unpacking the dev pack (`run/mods`, `run/mods-client`):

| Host jar | Nested mod ids |
|---|---|
| Sodium 0.8.12 (NeoForge) | `fabric_api_base`, `fabric_block_view_api_v2`, `fabric_renderer_api_v1`, `fabric_rendering_data_attachment_v1` (“Forgified Fabric API …” sub-modules) |
| Iris 1.8.14-beta.1 (NeoForge) | the same four `fabric_*` sub-modules |
| Supplementaries 3.8.3 | `mixinsquared` |
| Create 6.0.10 | `flywheel`, `ponder` |
| Sable 2.0.3 | `sablecompanion`, `veil` (dedupes with our newer embedded Veil) |
| Create: Crafts & Additions 1.6.0 | `sablecompanion` |
| Moonlight 3.1.1 | `codecui` |
| Aeronautics bundle | `aeronautics`, `simulated`, `offroad` |

All of these are allowlisted (`AntiCheatCheck.defaults()` + `assets/eclipse/bootstrap.json`).

**Does the pack need a standalone Forgified Fabric API install? NO.** The only `fabric_*`
ids in the pack come from the sub-modules jarJar'd INSIDE the Sodium and Iris NeoForge
builds; no pack mod declares a dependency on a standalone Forgified Fabric API. There is
nothing to download or add to the pack — the ids only needed allowlisting.

## Security model (honest note)

**Server-side JSON configs cannot be bypassed by clients.** `config/eclipse/*.json` lives on
the server filesystem and is read only by server code; clients never see or influence it —
only people with server file access (who are already trusted) can edit it. Plain-JSON format
is a convenience for operators, not a security property; AUTHORITY is what matters. The one
client-trusting surface is the modlist self-report (`C2SModlistPayload`) — a deterrent by
design, not a wall. The "may continue on mismatch" decision is server-authoritative
(`anticheat.json` `allowContinueOnMismatch`, default disconnect), and the server sends its
policy hash on login so client-manifest drift is logged. Full analysis + C2S handler audit:
`docs/plans_v3/plans_v5/security_model.md`.

The generated `modgate_ids.json` safely pre-gates the optional C19 proposals even before they
are installed: `ends_delight:* → end` (day 12), `create_confectionery:* → farmersdelight`
(day 4), and `createconnected:* → create` (day 3). Missing namespaces are harmless.

## Runtime checks

- `assets/eclipse/bootstrap.json` is the baked client manifest. On the first title screen,
  unknown, missing, blocklisted or version-mismatched mods are itemized. The
  `allowContinueOnMismatch` manifest flag controls whether **“Continue anyway / Trotzdem
  fortfahren”** is offered.
- `config/eclipse/anticheat.json` is generated/migrated with `modlistMode`,
  `allowedMods`, `requiredMods`, `optionalMods`, the legacy substring blocklist and a download
  hint. `allowlist` rejects missing/extra ids; `blocklist` retains the old behavior. The
  substring blocklist always applies.
- The existing network payload reports ids only, so the server checks exact ids while the
  client bootstrap checks manifest versions. This remains an honest-client deterrent.
- `/dev modcheck` reports loaded versions, allowlist differences, namespace/id gate state and
  all jarJar bundles. `/dev modcheck snapshot` (permission 3) replaces the runtime allowlist
  with the running server's actual set while preserving optional client entries, and ALSO
  writes `bootstrap.json.suggested` next to the server dir in the baked-manifest shape so
  `assets/eclipse/bootstrap.json` can be regenerated without drifting from the allowlist.
- `anticheat.json` additionally carries `allowContinueOnMismatch` (server-authoritative
  mismatch verdict, default `false` = disconnect) and `devBypassUuids` (UUIDs or
  `name:<Player>` pins, e.g. Sonic0810) whose identities skip mod-set enforcement and may use
  `/dev` without op — see the security note below.

### Modrinth pack (.mrpack)

The distributable pack artifact is a **Modrinth `.mrpack`**, generated by
`tools/modpack/build_mrpack.py` from the pinned inventory in
`tools/modpack/pack_manifest.json` (see `tools/modpack/README.md` for usage). The `.mrpack`
format REFERENCES every publicly hosted mod by official download URL + sha512/sha1 hash
instead of redistributing jars — which sidesteps every ARR/no-redistribution blocker in the
table above (Sophisticated*, Simple Voice Chat, Supplementaries, Create assets). Only content
that is ours or explicitly redistributable rides in the pack's `overrides/` folder: the
Eclipse jar itself (ARR but ours) and the default `config/eclipse/` seeds. Mods that are not
on a public CDN or whose license policy forbids referencing a rehost (the Aeronautics bundled
build; Sable per its PolyForm Shield policy) are listed in a generated
`overrides/MANUAL_INSTALL.md` for the operator — exactly the external-install policy above,
now machine-shipped. A giant mods **zip is deliberately NOT committed**: it would either
violate the ARR licenses (if it contained the jars) or be worse than the `.mrpack` (if it
did not); the committed, reviewable equivalents are the generator plus
`tools/modpack/mods_manifest.json` (exact name+version+URL+hash per mod).

### Photon (optional VFX layer) — final verdict (D12, evidence 2026-07)

The v3 "unresolved/ambiguous" row was STALE. Facts, all re-verified against the live
Modrinth API and the published jar:

- **Identity:** Modrinth project `photon-editor` (id `gzevkJbM`), author KilaBash /
  Low Drag MC — "Photon, a VFX library" with a Unity-style in-game effect editor.
- **NeoForge 1.21.1 builds exist and are current:** latest `mc1.21.1-2.2.0-neoforge`
  (2026-07-21, adds a required KilaGraph dependency); we target **`2.1.5`** (2026-06-26,
  no Modrinth-declared dependency — but its `neoforge.mods.toml` REQUIRES
  `ldlib2 [2.2.24,)`, so an install is always Photon + LDLib2).
- **License:** GPL-3.0 (Modrinth labels it "LicenseRef-Custom-License", but the linked
  LICENSE file is verbatim GPLv3 and the jar metadata says "GPL-3.0 license"). Copyleft:
  never jarJar it into the ARR Eclipse jar — external install or `.mrpack` URL reference.
- **Adoption shipped:** `veilfx/PhotonBridge` — **pure reflection, no compile-time or
  Gradle dependency** (the Modrinth Maven coordinate
  `maven.modrinth:photon-editor:mc1.21.1-2.1.5-neoforge` was verified resolvable, but the
  build deliberately stays dependency-free; the three reflected API points were verified
  by `javap` against the published 2.1.5 jar: `FXHelper.getFX(ResourceLocation)`,
  `new BlockEffectExecutor(FX, Level, BlockPos)`, `start()`). Everything is behind
  `ModList.get().isLoaded("photon")` plus the `photonFx` client-config toggle (and
  `reducedFx`); absence of Photon is a silent no-op with the existing Quasar visuals
  unchanged.
- **Enhanced flagship moments (2):** the altar level-up (layered over the
  `altar_levelup_ring` Quasar cue) and the expansion rift glow (layered over `RiftFx`
  tears). Photon effects are DATA authored in its in-game editor (compressed-NBT
  `assets/eclipse/fx/<id>.fx` files); the mod ships the hook points, and effect authors
  drop `altar_levelup.fx` / `expansion_rift_glow.fx` into a resource pack. Until such an
  asset exists the bridge logs one INFO per id and stays Quasar-only.
- **Dev runtime:** `tools/modpack/fetch_dev_mods.py` fetches Photon 2.1.5 + LDLib2 2.2.29
  into `run/mods-client` AND `run/mods` as best-effort OPTIONAL entries (a miss never
  fails the script). Allowlist rows `photon`/`ldlib2`/`kilagraph` (all `"*"`, optional)
  are in `AntiCheatCheck.defaults()` + `assets/eclipse/bootstrap.json`.
- **Operator note — server install is REQUIRED for Photon-equipped clients (PH-CORE):**
  photon 2.1.5 and ldlib2 2.2.29 both register NeoForge network channels **without**
  `.optional()`, and the 21.1 negotiator fails the handshake in both directions for
  non-optional channels (verified against 21.1.238 sources — see
  `docs/plans_v3/plans_v5/photon/INTEGRATION.md` §2 Verdict C). Consequence: a client
  running Photon+LDLib2 is disconnected (`multiplayer.disconnect.incompatible`) by a
  server that lacks them, BEFORE the Eclipse modcheck ever runs. Operator default when
  Photon-equipped clients are expected: install the photon+ldlib2 pair on the dedicated
  server too (external install, never redistributed — GPL policy above holds; the
  server-side load is crash-safe: photon's mixins are all client-array, LDLib2 carries
  modest common mixins). Keep server+client pinned to the same photon build via
  `tools/modpack/mods_manifest.json`. Alternatives: keep Photon a singleplayer/dev-only
  extra, or land the upstream `.optional()` PR.
- **Open risk (pre-authorized fallback):** Photon 2.x and Veil 4.3.0 both hook render
  pipelines; if in-game testing shows mixin conflicts, flip `photonFx=false` by default
  and record the logs here. Not yet observed — runtime testing needs a GL client.

## NeoForge early loading window (client installs & dev runs)

What is actually configurable on NeoForge 21.1 (FML loader 4.0.43 — keys verified from
`FMLConfig$ConfigValue` in the shipped jar; there is **no `darkMode` fml.toml key**, that
is a Forge-ism):

- `config/fml.toml`: `earlyWindowControl` (true = FML owns the boot window; disabling it
  loses the loading progress UI and "can be bad for mods that rely on new GL features" —
  keep it ON; it has NOTHING to do with our in-game `EclipseLoadingScreen`, which only
  swaps the vanilla world-join/dimension screens much later), `earlyWindowProvider`
  (`"fmlearlywindow"` is the only shipped provider), `earlyWindowWidth`/`earlyWindowHeight`
  (we set 1024×576 in the dev run for a tidier 16:9 boot window), `earlyWindowFBScale`,
  `earlyWindowMaximized`, `earlyWindowSkipGLVersions`, `earlyWindowSquir` (easter egg).
- **Dark scheme:** the early window picks `ColourScheme.BLACK` when the env var
  `FML_EARLY_WINDOW_DARK` is set (any value) OR when the vanilla `options.txt` has
  `darkMojangStudiosBackground:true` (which also darkens the Mojang loading overlay —
  recommended for the Eclipse look; we ship it in the dev-run `run/options.txt`). Only
  two schemes exist (default RED, BLACK) — a custom dark-purple palette is not a config
  option.
- **Window title** is hardcoded (`"Minecraft: NeoForge Loading..."`) — the mod
  `displayName` does not appear there.
- **Custom `ImmediateWindowProvider` verdict: NOT feasible from this mod.** The provider
  is `ServiceLoader`-discovered on the FML **boot module layer** before mod discovery
  (verified in `ImmediateWindowHandler`); a provider inside a regular mod jar is never
  seen. Shipping one would require a separate boot-layer library installed next to FML —
  high-risk, rejected per the config+docs fallback. Operators who want the dark boot
  window on player installs should document `darkMojangStudiosBackground:true` /
  `FML_EARLY_WINDOW_DARK=1` in the pack install notes.

## Adding a mod to the pack

1. Verify the exact NeoForge 1.21.1 artifact, mod id, version, complete license (including
   assets) and official download URL. Default to external unless redistribution is explicit.
2. Add the id/version to `assets/eclipse/bootstrap.json`. Put mandatory client+server mods in
   `requiredMods`; put client extras and unapproved content proposals in `optionalMods`.
   Mirror the shipped default in `AntiCheatCheck.defaults()`, then use
   `/dev modcheck snapshot` on the final full server pack.
3. Gate a whole content mod in `config/eclipse/modgate.json` (`gatedNamespaces` plus
   `unlockKeys`). Gate only selected ids in `config/eclipse/modgate_ids.json`, using an exact
   namespace and path glob such as `create:*_casing`. Never gate a library namespace.
4. Add the progression key to the appropriate day/milestone content. Confirm both locked and
   unlocked behavior for item use, placement, pickup, crafting and inventory sweeps.
5. If recipes/items would leak spoilers, add them to `#eclipse:emi_hidden` or the EMI runtime
   gate owned by the EMI integration. Reindex EMI and test before/after unlock.
6. For a jarJar candidate, add only the resolving official Maven repository, use an exact
   version constraint, inspect the built nested jar and retain the dependency's license/notice.
   Run the full dedicated-server/client compatibility matrix before shipping.
