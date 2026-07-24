# Eclipse security model — "configs are just .json" (plans_v5 D8)

The user's worry, verbatim: *"the configs are plain .json — anyone can just edit them and
bypass everything."* This document is the honest, code-verified answer, plus the hardening
that was actually shipped.

## 1. Server-side JSON configs CANNOT be bypassed by clients

`config/eclipse/*.json` (`anticheat.json`, `skills.json`, `goals.json`, `recipegate.json`, …)
live on the **server filesystem** and are read only by server code
(`EclipseConfig.loadOrCreate` and siblings resolve against `FMLPaths.CONFIGDIR` **of the
dedicated server process**). A client never sees these files, cannot request them, and cannot
edit them. The only people who can change them are people with server file access — and those
people are already fully trusted (they could swap the whole jar).

**Format is irrelevant to security; AUTHORITY is what matters.** A binary or encrypted config
read by the same server code would be exactly as secure — and exactly as editable by an admin.
"It's plain JSON" only affects how *convenient* the file is for the trusted operator.

## 2. What IS client-trusting today (the honest list, from code)

1. **`C2SModlistPayload` is a self-report.** A modified client can lie about its mod list.
   The `AntiCheatCheck` javadoc has always admitted this: it is a *"pack-integrity deterrent
   rather than a security boundary."* This is unfixable client-side **by design** — the server
   can never prove what code runs on a remote machine (the same limit every anticheat has).
2. **The baked `assets/eclipse/bootstrap.json`** (client-side manifest) decides
   `allowContinueOnMismatch` **locally** — a re-zipped jar can flip it. Harmless: it only
   changes whether the local title-screen warning offers "Continue anyway". The server check
   still runs at connection time and is the only real gate (see §3.1).
3. **`anticheat/AntiXrayConfig` + `OreExposureRules`** are fully server-side — nothing to
   harden; a client cannot influence which ore-exposure samples the server takes.

## 3. Real hardening delivered by this package

1. **Server-authoritative mismatch policy.** The effective "may continue with mismatch"
   decision now lives in the SERVER config (`anticheat.json` → `allowContinueOnMismatch`,
   default `false` = disconnect, preserving the historical behaviour).
   `AntiCheatCheck.handleModlist` applies it; the client manifest flag of the same name is
   demoted to a local-warning cosmetic. On login the server sends its verdict plus a
   **policy hash** (`AntiCheatCheck.policyHash()`, SHA-256 over the sorted
   allowed/required/optional/blocked sets) as two extra fields on the existing
   `S2COpStatusPayload` login packet (no new packet). The client compares the hash against its
   baked manifest and logs drift (`PackBootstrap.onServerPolicy`) — diagnostic only, the
   server already enforced before the packet is sent.
2. **C2S handler audit** (gold standard: `WandPowers.handleCast` — actor validation + full
   server-side re-validation). Checklist result:
   - `C2SConfigEditPayload` → `devtools.ConfigEditor.handleEdit`: **OK** — requires
     `hasPermissions(3)`, allowlists the file name, enforces the 64 KiB size cap server-side,
     re-validates + normalizes JSON against the config schemas before any disk write.
   - `C2SSkillNodeBuyPayload` → `SkillService.handleNodeBuy/buyNode`: **OK** — the server
     re-derives affordability/unlock state; the client only names a node id.
   - `C2SRebirthPayload` → `RebirthService.handleRebirthRequest`: **OK** — all preconditions
     and the whole transaction run server-side.
   - `C2SCutsceneStatePayload`/`C2SCutsceneReadyPayload` → `CutsceneService`: **OK** —
     ACK/skip bookkeeping only, validated against server cutscene state.
   - `C2SDisplayEditPayload` → `DisplayPayloads.handleEdit`: **OK** — requires
     `hasPermissions(2)` AND physically holding the display wand.
   - `C2SDevHandbookRequestPayload` → `DevHandbookPayloads.handleRequest`: **OK** — perm-2
     gate; **extended (1 small edit)** to also accept D7 dev-bypass identities so the same
     single policy (`/dev` gate) governs both entry points.
   - `C2SXboxAckPayload`, `C2SRespawnReadyPayload`, `C2SOpenArtifactPayload`,
     `C2SLocalePayload`: **OK** — capability flags/ACKs with no privileged effect.
   - Handbook run-commands: **OK** — validated by `DevCommandRegistry.matchSyntaxPrefix`
     before dispatch.
3. **The Sonic0810 / dev-UUID path** (implemented in D7, documented here as its trust model):
   `anticheat.json` → `devBypassUuids` accepts literal UUIDs or `"name:Sonic0810"` pins
   (resolved online-player-first, then via the server profile cache). A bypass identity gets
   exactly two things: (a) mod-set enforcement (modlist verdict + report timeout) is waived
   with an INFO log, and (b) `/dev` access at the permission-2 tier via `DevRoot.canUseDev`.
   It **never grants op**: permission-3 subcommands, `/eclipse` admin commands and every other
   vanilla permission check are untouched. The list is server config — clients cannot add
   themselves to it (see §1).

## 4. Summary for operators

- Nobody outside the server box can bypass anything by "editing JSON" — the JSONs that matter
  never leave the server.
- The one genuinely client-trusting surface (the modlist self-report) is a deterrent by
  design; treat it as a tripwire, not a wall. The server-side disconnect policy, the anti-xray
  heuristics and every gameplay validation stand independently of it.
- Keep `devBypassUuids` short and prefer literal UUIDs over name pins (names can be re-bought
  on Mojang accounts; UUIDs cannot).
