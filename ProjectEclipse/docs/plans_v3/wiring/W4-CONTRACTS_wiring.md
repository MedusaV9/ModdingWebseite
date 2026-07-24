# W4-CONTRACTS wiring — KILL CONTRACTS (IDEA-20)

## Registration

No shared JAVA file was edited (`EclipseMod.java`, `EclipsePayloads.java`, `EclipseGuiLayers.java`,
lang JSONs, `sounds.json`, `registry/EclipseSounds`, `music/MusicCues` all untouched). One shared
RESOURCE was edited, as explicitly sanctioned by the brief: `eclipse.client.mixins.json` gained the
`HumanoidArmorLayerMixin` entry (armor blackout needs a render-layer cancel; there is no event for it).

| Class | Bus / discovery | Role |
|---|---|---|
| `contracts/ContractService` | GAME | State machine `IDLE → SCHEDULED → ANNOUNCED(omen) → ACTIVE → resolved → IDLE`. Daily odds roll at rollover PRE (config-gated, default OFF), fairness draw, kill/ghost detection, ceremonies, music seam, login/logout edges, crash resume on `ServerStartedEvent`. Registers `ReloadHooks` id `contracts` + `EclipseSignals.onDayRollover` itself. |
| `contracts/ContractState` | — | SavedData `eclipse_contracts.dat` (overworld): phase, mode (REAL/PRANK), pair UUIDs, absolute window epochs, per-day roll latch, ghost-hit counter, pair-cooldown history, outcome tallies. Pair is committed BEFORE any reveal is sent — a crash never re-rolls a different target. |
| `contracts/ContractConfig` | — | `config/eclipse/contracts.json` (BuffConfig pattern; defaults below). `/dev contract odds|window` mutate the live snapshot only (transient until reload/restart). |
| `contracts/ContractModifierService` | GAME | Per-day per-player ledger (SavedData `eclipse_contract_modifiers.dat`): DAMAGE_MUL, GRUDGE (vs one UUID), TEMP_HEARTS (transient `eclipse:contract_hearts` attribute modifier on MAX_HEALTH), SKILLS_MUL (via `SkillsApi.setSecretMultiplier`), AWARD_VOID. Everything expires at the next day rollover; hearts/skills reapply on login/respawn/clone. |
| `network/contracts/ContractPayloads` | MOD (`RegisterPayloadHandlersEvent`, version `contracts1`) | S2C: `contracts/reveal` (role + targetUuid + windowTicks + replay), `contracts/state` (window flag + deadline, broadcast, pair-free), `contracts/resolve` (private beat byte). Client dispatch uses lazy fully-qualified references in handler bodies — the `EclipsePayloads` house pattern, dedicated-server safe. |
| `client/contracts/ContractClientState` | GAME (CLIENT) | Window-flag cache; deadline re-anchored to the local clock on receipt. Single gate read by the armor mixin + overlay. Cleared on level unload. |
| `client/contracts/ContractRevealOverlay` | MOD+GAME (CLIENT) | Self-registered GUI layer (`eclipse:contract_reveal`, above vignette layers): hunter roulette → real face → red X stamp + shake + sting + typewriter oath; target "DU WIRST GEJAGT" warning; resolution beats (FULFILLED/LAPSED/SURVIVED/PRANK/WITHDRAWN); persistent top-right mini-marker (X-face for the hunter, pulsing GEJAGT for the target, bare countdown for bystanders); subtle window vignette for everyone. |
| `client/contracts/ContractRouletteStrip` | — | Deterministic strip physics — a faithful replica of `client/awards/RouletteStrip` (package-private there, so not importable) drawing uniform heads only. |
| `client/mixin/HumanoidArmorLayerMixin` | mixin (`eclipse.client.mixins.json`) | Cancels `HumanoidArmorLayer#render` at HEAD for `AbstractClientPlayer` targets while `ContractClientState.windowActive()`. Explicit LivingEntity descriptor (the `Entity` overload in the class file is the synthetic bridge). GeckoLib mobs/armor stands unaffected; render-only, slots/protection untouched. |
| `devtools/dev/DevContractCommands` | GAME | `/dev contract ...` (perm 2), 6 `DevCommandRegistry` docs (`contract.*`, category EVENT), registered from the static initializer. Merges into the existing `/dev` literal. |

## Commands

- `/dev contract start [hunter] [target]` — force a REAL contract (short 5 s dev omen); no args = fairness auto-draw.
- `/dev contract prank` — force a PRANK round: every online player gets the hunted ceremony, nobody is hunted.
- `/dev contract stop` — ACTIVE resolves as EXPIRED; SCHEDULED/ANNOUNCED cancel silently.
- `/dev contract status` — phase/mode, countdowns, pair (ops eyes ONLY — the single place names resolve), odds, outcome tallies, live modifier count.
- `/dev contract odds <pct>` / `/dev contract window <minutes>` — transient live-config overrides.

All mutations use the standard `dev.eclipse.audit` broadcast + `[DEV AUDIT]` log line.

## Config defaults (`config/eclipse/contracts.json`)

`autoDaily=false` (dev-triggered until an operator arms it), `realChancePct=25`, `prankChancePct=5`,
`windowMinutes=30`, `omenSeconds=60`, window start drawn 30–240 min into the day, `minOnlineForReal=4`
(degrades a REAL roll to PRANK below that), `pairCooldownDays=3`, `proximityWeighting=true`,
`ghostKillHits=3`, `ghostPayoutPct=60`, `prankConsolationShards=2`.
Ledger: SUCCESS → hunter 1.5× skills + 1.10× damage + 1 temp heart + 12 shards + 400 XP
(`hunterGlobalBuffId` empty by default — set a `TimedBuffApi` id to add a global buff);
target 0.75× skills + 0.85× damage. EXPIRED → survivor 250 XP + 4 shards. WRONG_KILL →
killer 0.80× damage + 0.5× skills + award-void; victim −1 temp heart + 1.35× grudge damage
vs the killer. Everything expires at the next rollover.

## Design decisions (read before extending)

- **Face-only anonymity breach**: no name ever crosses the wire — the hunter payload carries the
  target UUID only; the client resolves UUID → `SkinManager.getOrLoad(new GameProfile(uuid, ""))`
  itself. This bypasses `AbstractClientPlayerMixin` legitimately: that mixin hooks
  `AbstractClientPlayer.getSkin`, not the SkinManager, so world models stay uniform while the HUD
  overlay shows the one real face. Fallback: uniform face if session servers don't answer.
- **Resolution matrix extensions** (the brief defined SUCCESS/EXPIRED/WRONG_KILL; two edges needed
  defining): target dies to anything that is NOT the hunter → **VOIDED** (nobody profits — the
  system refuses to be an executioner); target kills the hunter → **TABLES_TURNED** (the full
  hunter advantage flips to the target, the dead hunter takes the target disadvantage). WRONG_KILL
  is non-terminal: Blutschuld/Vergeltung apply and the window keeps running.
- **Temp hearts never touch LIVES**: `EclipseAttachments.LIVES` is a hard invariant; the ±heart
  effects are a transient, never-serialized `AttributeModifier` (`eclipse:contract_hearts`) that
  `ContractModifierService` reapplies on login/respawn/clone and strips at rollover. Clamped so a
  victim can never drop below one heart.
- **Ghost path**: `LogoutGhostEntity.hurt()` returns false (invulnerable by design), so a "kill"
  is a banishment ritual — `ghostKillHits` strikes counted via `AttackEntityEvent` (rising pitch
  ticks per hit), then SUCCESS at `ghostPayoutPct` payout and the ghost is discarded.
- **PRANK has zero tells by construction**: prank rounds send the IDENTICAL target-role payload,
  mark-vignette and music to every player that a real target gets; music therefore plays for all
  "targets" in both modes (a hunter-only cue would out the round as real to bystanders).
- **Pause awareness**: deadlines are absolute `EclipseClock` epochs; while `RealtimeDayApi.isPaused`
  the tick loop shifts every pending deadline forward by the frozen span (the XboxEventService
  timeMutate philosophy) instead of comparing against a frozen clock.
- **Fairness draw** (omen time, online players only): excludes spectators, banned players,
  cutscene-frozen players and 0-lives hunters; targets need ≥2 lives (a contract death must sting,
  never end a run). Same-pair cooldown `pairCooldownDays`, no back-to-back target repeats,
  same-dimension-and-<400 m pairs weighted 2× when `proximityWeighting` is on.
- **Analytics**: `AnalyticsApi` is read-only (no `addMetric`), so outcome tallies live in
  `ContractState` and surface via `/dev contract status` — no shared-file edit.
- **Award-void seam**: `ContractModifierService.isAwardVoided(server, uuid, day)` is implemented
  and tracked, but `awards/AwardService` is shared and was NOT edited — see integrator ask 3.

## Verification performed (no gradle, per rules)

- All 13 new/changed java files compile via a `javac -sourcepath` harness against the repo's cached
  NeoForge 21.1.238 merged jar (exit 0). Only warnings: the deprecated `EventBusSubscriber.bus`
  element — identical to the `GrowthPayloads` pattern file, kept for convention.
- Langdrop `W4-CONTRACTS.json`: 47 keys, en/de parity + `%s` arg-count parity asserted by script;
  every key referenced from code and no orphans; no collision with existing lang JSONs
  (`dev.eclipse.audit` reused, not redefined).
- Mixin target verified against the jar via `javap`: single non-bridge
  `render(PoseStack, MultiBufferSource, int, LivingEntity, float×6)` — descriptor pinned.
- NOT done here: `./gradlew build`/`runClient`/`runServer` (forbidden this pass) — mixin apply,
  payload round-trip, SavedData persistence and the ceremonies still need one integrator smoke boot.

## Integrator asks

1. Merge `docs/plans_v3/langdrop/W4-CONTRACTS.json` via `python3 tools/langmerge/merge_langdrops.py`.
2. **Music — nothing to wire in code**: `MusicCues.KILL_CONTRACT` ("kill_contract", looping,
   linger 100) and `EclipseMusicSounds.KILL_CONTRACT` already exist (W4-BOSSJUICE). Outstanding
   are only that wave's asset asks: the `music.kill_contract` entry in `sounds.json` + the OGG at
   `assets/eclipse/sounds/music/kill_contract.ogg`. Until they land, `ContractService` soft-guards
   (`MusicCues.play` returns false → one DEBUG line, windows stay silent).
3. **Award-void one-liner** (shared `awards/AwardService`, deliberate ask instead of an edit):
   at the top of `queueReward(MinecraftServer, UUID, String, AwardConfig.Reward)` add
   `if (dev.projecteclipse.eclipse.contracts.ContractModifierService.isAwardVoided(server, player, dev.projecteclipse.eclipse.core.state.EclipseWorldState.get(server).getDay())) return;`
   — a wrong-killer's day awards are then actually withheld. Without it, AWARD_VOID is tracked
   (visible in `/dev contract status`) but not enforced.
4. Smoke boot (2 clients): `/dev contract start A B` → A gets roulette → real face → X + oath,
   B gets GEJAGT warning, both hear the cue (once the OGG lands), EVERYONE's armor disappears;
   A kills B → fulfilled banner + tallies; relog mid-window → marker resyncs. Then
   `/dev contract prank` on 2+ clients → both get the warning, window end shows "No one was
   hunting you. Today." Wrong-kill: `/dev contract start A B`, A kills C → Blutschuld lines,
   C hits A for visibly more damage, contract still ACTIVE.
5. `/dev docs export` picks up the 6 new registry entries automatically. No new `DevCategory`
   (shared enum) — everything sits under EVENT.

## Risks

- **Skin fetch needs outbound session-server access** on the hunter's client; offline-mode or
  blocked egress falls back to the uniform face (ceremony still reads, the X still stamps —
  degraded, not broken).
- **`MusicCues.stop(player)` stops the whole custom music channel** (no per-cue stop exists): if
  another forced cue is somehow playing for the hunter/target at resolution it is faded too. The
  situation ladder re-asserts its rung on the next evaluation, so the damage is a few silent seconds.
- **Armor blackout is cosmetic-only and global for players**: it also hides the LOCAL player's own
  armor (inventory screen included) during the window — intended reading, but worth a changelog
  line so players don't report it as a bug.
- **`LivingIncomingDamageEvent` multipliers stack multiplicatively** with other damage-mutating
  handlers (order-independent since they multiply `amount`); grudge (1.35×) on top of Blutschuld
  (0.80×) intentionally nets ~1.08× if the same pair fights again — bounded by design.
- **Ghost dependency**: the offline-target path assumes `LogoutGhostService` spawned a ghost for
  the target (it does for mid-game combat logouts, not for lobby phases); if no ghost exists the
  window simply expires → EXPIRED, the safe outcome.
- **Transient dev overrides** (`odds`, `window`) silently revert on `/dev reload`/restart —
  documented in the command feedback, but operators should persist real tuning in `contracts.json`.
- **Pair history growth**: pruned by `pairCooldownDays`, so the SavedData stays O(recent pairs).
