# WB-BUNDLE wiring notes — P5-W10

## Integration asks

- Merge `docs/plans_v3/langdrop/WB-BUNDLE.json` into both real locale files. This worker did
  not edit shared lang assets.
- No `EclipseMod.java`, `network/**`, `sounds.json`, EMI plugin or metadata-template edit is
  required. `PackBootstrap`, `AntiCheatCheck`, `ModGateIds` and `DevModcheckCommands` are
  event-bus subscribers; the existing `C2SModlistPayload` handler already calls
  `AntiCheatCheck.handleModlist`.
- Keep EMI pinned to **1.1.18+1.21.1** for this wave. Plan §2.15 says 1.1.22, but the worker
  instruction explicitly froze `dev.emi:emi-neoforge:1.1.18+1.21.1`; the implementation and
  bootstrap manifest follow the later explicit instruction. The EMI plugin owner must compile
  against the same version.
- C19 entries (End's Delight 2.6.1, Create Confectionery 1.1.2, Create: Connected 1.3.2) are
  allowlisted optional proposals only. The generated id-gate defaults already seal their whole
  namespaces behind existing day keys (`end`, `farmersdelight`, `create`), but the orchestrator
  must approve and install the jars before treating them as shipped pack content.

## Self-registering surfaces

| Class | Event / hook | Result |
|---|---|---|
| `PackBootstrap` | client `ScreenEvent.Opening` at LOWEST | Wraps the final title screen with the itemized pack warning once per launch |
| `AntiCheatCheck` | existing login/report/timeout events | Strict allowlist or legacy blocklist evaluation; generated extended `anticheat.json` |
| `ModGateIds` | server start/stop + `DevReloadRegistry` | Generates and hot-reloads `config/eclipse/modgate_ids.json` |
| `DevModcheckCommands` | `RegisterCommandsEvent` | Merged `/dev modcheck` root and `DevCommandRegistry` docs |

The client warning checks versions from `assets/eclipse/bootstrap.json`. The unchanged network
payload carries ids only, so server-side connection enforcement cannot authenticate versions.

## Maven coordinate evidence (no Gradle was run by this worker)

The existing BlameJared repository returns 404 for the requested EMI coordinate. The added,
content-filtered repositories and exact artifacts returned HTTP 200 on 2026-07-23:

```bash
curl -L -o /dev/null -s -w '%{http_code}\n' \
  'https://maven.terraformersmc.com/releases/dev/emi/emi-neoforge/1.1.18+1.21.1/emi-neoforge-1.1.18+1.21.1.pom'
curl -L -o /dev/null -s -w '%{http_code}\n' \
  'https://maven.terraformersmc.com/releases/dev/emi/emi-neoforge/1.1.18+1.21.1/emi-neoforge-1.1.18+1.21.1-api.jar'
curl -L -o /dev/null -s -w '%{http_code}\n' \
  'https://api.modrinth.com/maven/maven/modrinth/mouse-tweaks/1.21-2.26.1-neoforge/mouse-tweaks-1.21-2.26.1-neoforge.pom'
```

Expected coordinate mapping:

```text
compileOnly  dev.emi:emi-neoforge:1.1.18+1.21.1:api
jarJar       dev.emi:emi-neoforge:1.1.18+1.21.1
jarJar       maven.modrinth:mouse-tweaks:1.21-2.26.1-neoforge
```

## Required orchestrator verification

This worker was explicitly forbidden to execute Gradle. After merge:

1. Run `./gradlew dependencyInsight --dependency emi-neoforge --configuration runtimeClasspath`
   and the equivalent for `mouse-tweaks`; confirm exactly one selected version each.
2. Run `./gradlew clean build`. Inspect the Eclipse jar's `META-INF/jarjar/metadata.json` and
   nested jars; confirm EMI 1.1.18, Mouse Tweaks 2.26.1, GeckoLib 4.9.2 and Veil 4.3.0.
3. Run a dedicated server with the full README server pack. Confirm `Done`, then execute
   `/dev modcheck` and `/dev modcheck snapshot`; rerun `/dev modcheck` and confirm the snapshot
   passes itself.
4. Run a client with only the built Eclipse jar. Confirm nested EMI/Mouse Tweaks/GeckoLib load
   and the missing-external-mod warning appears. Confirm the German locale button reads
   “Trotzdem fortfahren”.
5. Run the full client pack and join the server. Then add one unknown id (the M7 litematica
   case) and confirm the local itemized warning plus server disconnect. Flip
   `modlistMode` to `blocklist` and confirm legacy behavior remains.
6. Edit `modgate_ids.json` with `create:*_casing`, map it to a locked test key, reload, and
   verify use/place/pickup/craft/inventory sweep behavior. Unlock the key and verify immediate
   reversal.

Risk to watch: ModDevGradle's jarJar wrapper must accept the Mouse Tweaks dependency sourced
from `runtimeOnly`. If dependency insight/build rejects that notation, use
`jarJar(implementation(...))` (the established Veil/GeckoLib form); Mouse Tweaks has no Eclipse
compile-time references either way.
