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
| EMI | 1.1.18+1.21.1 | MIT | Yes | Permissive QoL mod; exact build matches the EMI plugin contract | [TerraformersMC Maven](https://maven.terraformersmc.com/releases/dev/emi/emi-neoforge/1.1.18+1.21.1/) / [Modrinth](https://modrinth.com/mod/emi/version/1.1.18+1.21.1+neoforge) |
| Mouse Tweaks | 2.26.1 (NeoForge 1.21/1.21.1) | BSD-3-Clause | Yes | Permissive, client-only QoL mod; its nested jar retains client-side metadata | [Modrinth](https://modrinth.com/mod/mouse-tweaks/version/1.21-2.26.1-neoforge) |
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
| Photon | unresolved | Unresolved | No | The named project is ambiguous (shaderpack vs library); do not distribute until identity and license are verified | None approved |
| Axiom | 1.21.1 line is Fabric-only | ARR | N/A | No compatible NeoForge artifact and redistribution is not permitted | [Modrinth](https://modrinth.com/mod/axiom) |

The resulting Eclipse jar is not a true “one jar” pack. Create assets, Supplementaries,
Sophisticated, Voice Chat and Aeronautics are legal blockers; nesting them would not change
their licenses.

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
  with the running server's actual set while preserving optional client entries.

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
