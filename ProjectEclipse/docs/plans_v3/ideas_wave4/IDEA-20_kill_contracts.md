# IDEA-20 — KILL CONTRACTS ("Blutvertrag" / Daily Kill-Aufträge)

Collector 20/20, Eclipse Event ideas wave 4. Read-only pass over the live codebase; every hook
below names a real class/payload/config that exists today. No code was changed.

**Focus:** daily kill-contract events. A hunter is secretly assigned a target. Killer earns a
massive day-advantage; victim suffers a massive day-disadvantage. One PRANK variant where
*everyone* is told "you are hunted today". 30-minute event window. Armor rendered invisible
during the window (no gear tells). The target's **real Minecraft head** — the one thing the
anonymity suite normally erases — is shown X-marked on the hunter's screen at event start.
Wrong kills are punished, but the wrongly-killed victim gets revenge teeth. Plus odds, dev
commands, fairness, ceremonies, edge cases.

**Why this lands in THIS mod:** Eclipse's whole identity layer is scorched earth — uniform skin
(`client/mixin/AbstractClientPlayerMixin`), no nametags, no tab list, no chat, no signs
(README §"Anonymity — what is blocked and how"). A system that *deliberately* leaks exactly ONE
real face, to exactly ONE player, for exactly 30 minutes, weaponizes that anonymity instead of
just enforcing it. The drama point is the breach itself.

---

## 0. Grounding — systems this design plugs into (verified in source)

| System | Anchor | What we use it for |
|---|---|---|
| Day rollover bus | `core/signal/EclipseSignals.onDayRollover(...)`, `DayRolloverPhase.PRE/POST` | draw the contract day, resolve expiry at day end (same pattern `awards/AwardService` uses at line ~58) |
| Real-time day clock | `progression/realtime/RealtimeDayApi` (`arm/pause/addMillis/status`), `core/time/EclipseClock.epochMillis()` | place the 30-min window inside the real-time day; pause-aware |
| Timed-window event template | `xboxevent/XboxEventService` (`start/stop`, `resumeOnBoot` crash resume, T-5/T-1 warnings, `ExitReason`, persisted `XboxEventState`) | the contract window lifecycle copies this proven shape |
| Timed buffs | `buffs/TimedBuffApi.start(server,id,minutes,magnitude)`, config `config/eclipse/buffs.json`, `/dev buff give` | global-flavor effects; per-player advantage needs the new `ContractModifierService` (idea 6) |
| Skills | `skills/SkillsApi.addXp(player,sourceKey,base)`, `setSecretMultiplier(server,uuid,factor)` | the "massive day-advantage" backbone — a secret XP multiplier already exists and is per-player |
| Awards | `awards/AwardService.queueReward/deliverPending`, `AwardConfig.Reward(skillXp,shards,items)`, `S2CAwardRevealPayload` (UUID-only by design) | reward delivery + a new daily award category |
| Roulette head strip | `client/awards/RouletteStrip` (uses `PlayerFaceRenderer`, deterministic ease-out landing, day-seeded shuffle) | the visual grammar for the X-marked head reveal |
| Mark vignette | `client/hud/MarkVignetteOverlay.trigger(ticks)` fed by `S2CShakePayload` ("only the marked player is ever sent it") | the hunted-feeling pulse; already reused by `drama/WitnessedLossService` and `HeraldEntity` |
| Announcements | `network/S2CAnnouncePayload(titleKey,subtitleKey,style)` → `client/hud/AnnouncementOverlay` (+`TypewriterLine`, `MarqueeText`) | ceremony banners |
| Death hook pattern | `drama/FirstBloodService.onLivingDeath` (single-fire `SavedData`, bell + `S2CShakePayload` world shake) | kill detection + resolution ceremony template |
| Lives & death flow | `registry/EclipseAttachments.LIVES` (default 5), `lives/DeathFlowHooks` (observe-only, `onRevived`), `BanService`, `GraveBlock` | "massive but not run-ending": contracts NEVER touch `LIVES` |
| Bonus hearts | `hearts/HeartsService` (`MIN_HEARTS 0`, `MAX_HEARTS 7`, `apply(player)`) | temp heart up/down as part of advantage/disadvantage |
| Shard economy | `economy/ShardEconomy`, `EclipseAttachments.SHARDS`, `economy/WatcherCompassItem` (needle → nearest player, never says who) | payouts; tracking-hint item precedent |
| Analytics | `analytics/AnalyticsApi.value/top`, `AnalyticsKeys` (`KILL_TOTAL`, `DEATH`, `PREFIX_KILL "kill:"`) | fairness weights + new contract keys |
| Logout ghosts | `ghosts/LogoutGhostService`, `LogoutGhostEntity`, `S2CGhostRevealPayload(ghostEntityId,ownerName,ticks)` | the offline-target edge case is already half-solved |
| Voice | `voice/EclipseVoicePlugin` (intercepts `MicrophonePacketEvent` etc.), `VoiceMuteApi.setForceMuted/setGlobalMuted` | reveal hush + proximity whisper garnish |
| Player render layers | `client/entity/player/PlayerLayerHandler`, `EclipsedPlayerGlowLayer`; skin mixin `AbstractClientPlayerMixin` | armor blackout lives here |
| HUD chrome | `client/hud/DayTimerLayer`, `BossbarSkin` + `S2CBossbarStylePayload`, `hud/SidebarSyncService.markDirty` | window countdown + sidebar row |
| Dev commands | `devtools/dev/DevCommandRegistry.register(DevCommandDoc...)` (frozen after boot), `/dev docs export` | the `/dev contract` tree self-documents into `docs/DEV_COMMANDS.md` |
| i18n | `docs/plans_v3/langdrop/<PKG>.json`, merged by `tools/langmerge/merge_langdrops.py` (en/de parity enforced) | ship `langdrop/IDEA-20.json`; NEVER hand-edit lang files |

New server module proposed: `dev.projecteclipse.eclipse.contracts` —
`ContractService`, `ContractState extends SavedData` (pattern: `FirstBloodService.FirstBloodState`),
`ContractConfig` (JSON in `config/eclipse/contracts.json`, reloaded by `/dev reload`, pattern:
`buffs/BuffConfig`), `ContractModifierService` (per-player timed modifiers), payloads
`S2CContractRevealPayload`, `S2CContractStatePayload`, client `client/contracts/` overlays.

---

## 1. The full loop (one contract day)

```
Day N-1 rollover (DayRolloverPhase.PRE)
 └─ ContractService rolls the dice (odds table §2): NONE / REAL / PRANK
    Assignment computed + committed to ContractState (crash-safe, like AwardService.resolveDay)

Day N, window T0 (config: offset into the real-time day, e.g. minute 240 ± jitter)
 ├─ T0-60s  OMEN: purple horizon flash (client/drama/HorizonLightning pattern), low bell,
 │          AnnouncementOverlay "eclipse.contract.omen" — no info about who/what
 ├─ T0      REVEAL CEREMONY (idea 2):
 │          hunter(s): X-marked REAL head animation + typewriter oath
 │          target (REAL round): MarkVignetteOverlay pulse + "DU WIRST GEJAGT"
 │          everyone (PRANK round): the target treatment, nobody gets a head
 │          ALL players: armor blackout ON (idea 3), bossbar skin "contract", 30:00 timer
 ├─ T0..T30 HUNT: warm/cold pings every 90s to hunter (idea 7), paranoia pings to target
 ├─ Resolution (whichever first):
 │    a) hunter kills target        → SUCCESS ceremony (idea 9), advantage/disadvantage (idea 6)
 │    b) window expires             → EXPIRY ceremony; target gains "Survivor" minor advantage
 │    c) anyone kills a NON-target  → WRONG-KILL justice (idea 5) — contract keeps running
 │    d) target dies to environment/mob → contract VOIDED, hunter gets consolation nothing
 │    e) target kills hunter        → TABLES-TURNED: target gets the full killer advantage
 └─ T30     armor blackout OFF, bossbar restored, analytics committed, sidebar row cleared

Day N rollover (POST) — expired/void contracts logged; award category "Vollstrecker" (idea 9)
counts contract stats into the daily awards roulette.
```

Crash safety: `ContractState` persists phase + deadline epoch (`EclipseClock.epochMillis()`);
`resumeOnBoot` semantics copied from `XboxEventService.onServerStarted` — a window whose
deadline passed while the server was down resolves as EXPIRY on boot, mid-window restarts
re-sync overlays from `S2CContractStatePayload` on login.

---

## 2. Odds ("Chancen") — config `contracts.json`, all knobs hot-reloadable

| Roll (per day, at rollover) | Default | Notes |
|---|---|---|
| No contract day | 45% | silence is what makes contract days loud |
| REAL contract, 1 hunter → 1 target | 30% | the standard drama |
| REAL, 2 hunters → same target ("Doppelvertrag") | 10% | hunters do NOT know about each other; first blood wins, second hunter gets nothing |
| PRANK round ("Der Tag der Angst") | 12% | EVERYONE gets the "you are hunted" treatment; **nobody is hunted** (see idea 4 for the variant debate) |
| INVERTED ("Alle jagen einen") | 3% | everyone is a hunter of ONE target; target gets 2× survivor reward; unlock only after day 7 |
| Window start | random minute in [180, 480] of the real-time day, ±20 min jitter | avoids clock-camping |
| Window length | 30 min (pause-aware via `RealtimeDayApi.isPaused`) | |
| Same pair cooldown | 3 days | no repeat hunter→target pairing |
| Min online players for REAL | 4 | below that, auto-degrade to PRANK or NONE |

---

## 3. The 12 ideas, ranked

### #1 — `ContractService`: the crash-safe contract state machine (the spine)
Server module `contracts/ContractService` + `ContractState extends SavedData`
(`data/eclipse_contracts.dat`, pattern `FirstBloodService.FirstBloodState` / `EclipseWorldState`).
Phases: `IDLE → DRAWN(day N-1) → OMEN → ACTIVE(deadline) → RESOLVED(outcome)`.
Draw at `EclipseSignals.onDayRollover(..., PRE)` exactly like `AwardService` (commit-before-
reveal so a crash never re-rolls a different target — same reasoning as the documented
"resolved record is committed before any reward delivery" contract in `AwardService.resolveDay`).
Window scheduling reads `RealtimeDayApi` (`isArmed/isPaused`) and stores an absolute
`EclipseClock.epochMillis()` deadline; tick handler mirrors `XboxEventService.onServerTick`
(T-5/T-1 warnings, re-armed after `timeMutate`). Kill detection: high-priority
`LivingDeathEvent` listener, same registration style as `FirstBloodService.onLivingDeath`,
matching `event.getSource().getEntity() instanceof ServerPlayer`. Outcome enum
`{SUCCESS, EXPIRED, VOIDED, TABLES_TURNED, WRONG_KILL(side-effect, non-terminal)}`.
**Hooks:** `EclipseSignals`, `RealtimeDayApi`, `EclipseClock`, `SavedData`, `LivingDeathEvent`,
`XboxEventService` (shape only). **Dev:** everything in idea 12 drives this class.

### #2 — The X-marked real-head reveal ("Das Gesicht") — the anonymity breach
At T0 the hunter's screen plays a 6-second overlay: a scrolling strip of identical uniform
heads (visual quote of `client/awards/RouletteStrip`, same ease-out-quart landing math)
decelerates… and the landing head **resolves into the target's REAL skin face**, then a
blood-red X stamps over it (two diagonal swipes, `GuiGraphics` quads + `S2CShakePayload`-style
screen kick), with `TypewriterLine` typing the oath: *"Dieser. Heute. 30 Minuten."*
**The trick that makes it work:** `AbstractClientPlayerMixin` only intercepts
`AbstractClientPlayer#getSkin` — entity rendering. A HUD overlay that fetches the skin via
`Minecraft.getInstance().getSkinManager()` from a `GameProfile` sent in the new
`S2CContractRevealPayload(targetProfile, mode, ticks)` bypasses the uniform-skin mixin
entirely; `PlayerFaceRenderer.draw` (already imported by `RouletteStrip`) renders the real
face. Server sends the payload ONLY to hunters (mirror of the "only the marked player is ever
sent it" rule documented on `S2CShakePayload`). No name is ever shown — face only; names stay
dead. Register the overlay in `client/EclipseGuiLayers` next to `MarkVignetteOverlay.LAYER_ID`.
**Hooks:** new `S2CContractRevealPayload` in `network/EclipsePayloads`, `PlayerFaceRenderer`,
`RouletteStrip` math, `client/handbook/GlitchText` for a glitch-in effect, `EclipseUiTheme`.

### #3 — Armor blackout ("Blindes Eisen") — 30 minutes of no gear tells
While a window is ACTIVE, every player's armor renders invisible on OTHER players' clients
(own inventory view unchanged — you still see your own slots). Implementation: client-side
gate in `client/entity/player/PlayerLayerHandler` (which already owns player layer surgery for
`EclipsedPlayerGlowLayer`): suppress `HumanoidArmorLayer` (+ elytra is already dead via the
skin mixin's null elytra texture) when the flag from `S2CContractStatePayload` is set. Held
items stay visible (weapon choice remains a read — deliberate: total blindness kills fights,
armor blindness kills *pre-fight target selection*). Server remains authoritative: this is a
render veto only, damage calc untouched, so no anticheat surface. Fold the same flag into
`anticheat` expectations if it ever validates render mods.
**Hooks:** `PlayerLayerHandler`, new client flag cache `client/contracts/ContractClientState`,
`S2CContractStatePayload`, layer suppression precedent: `EclipsedPlayerGlowLayer`.

### #4 — PRANK round "Der Tag der Angst" — sold identically, resolves as theater
12% of days, EVERY player gets the full target treatment: `MarkVignetteOverlay.trigger`
pulses, "DU WIRST GEJAGT" announcement, armor blackout, the 30:00 bossbar — and **no hunter
exists**. Recommended resolution of the "nobody or everybody?" question: **nobody is hunted**,
because (a) "everyone hunts everyone" collapses into a deathmatch that torches the lives
economy (`EclipseAttachments.LIVES` default 5 is precious), and (b) the payoff of a prank is
the exhale. At T30 the expiry ceremony plays a unique reveal: *"Niemand hat dich gejagt.
Heute."* + a tiny consolation (e.g. +2 shards via `ShardEconomy`) for everyone who *stayed
online* through the window — paying players for enduring fear, and making the prank read as
part of the game, not a troll. Crucially the prank keeps REAL rounds honest: being told
"you are hunted" carries no information, so targets can never be sure. Keep a config variant
`prank.mode = "nobody" | "everybody_marked_one_random_head"` — the second shows every player a
DIFFERENT random real head (faces leak, but they're noise), for late-event chaos days.
**Hooks:** `MarkVignetteOverlay`, `S2CAnnouncePayload` style `"contract_prank"`,
`client/drama/LastMinuteHush` (audio duck during the fake reveal), `ShardEconomy`.

### #5 — Wrong-kill justice: "Blutschuld" & "Vergeltung" (the asymmetric pair)
If during an ACTIVE window any player kills someone who is NOT their assigned target (or kills
while holding no contract at all):
- **Killer gets Blutschuld (blood guilt), rest of the real-time day:** Weakness-class debuff:
  −20% outgoing damage, skills earn at 0.5× (`SkillsApi.setSecretMultiplier(server, uuid, 0.5f)`
  — the API literally exists for silent per-player multipliers), and their next daily-award
  eligibility is voided (skip their UUID in `AwardService` candidate collection for day N).
- **Victim gets the bruise + the knife:** on respawn they carry a mild disadvantage (−1 temp
  heart via `HeartsService.apply` toward `MIN_HEARTS`, mining fatigue I for 20 min) **but**
  a directed grudge: +35% damage dealt **only against their wrong murderer**, until the next
  day rollover. Implemented in a `LivingIncomingDamageEvent` listener keyed on
  (attackerUUID == storedMurdererUUID) in `ContractModifierService` — no attribute leak, no
  visible particle, so the murderer never knows the knife exists until it cuts.
Both are announced ONLY to the two involved (typewriter, style `"contract_guilt"`), plus an
anonymous global thunderclap (`level.playSound` + `S2CShakePayload` broadcast, FirstBlood's
bell grammar) so the server *knows something unjust happened* without knowing who.
Wrong kills do NOT terminate the contract — the real hunter is still out there.
**Hooks:** `SkillsApi.setSecretMultiplier`, `HeartsService`, `LivingIncomingDamageEvent`,
new analytics keys (idea 12), `AwardService` candidate filter.

### #6 — The prize/penalty ledger: massive but never run-ending
Design rule (hard invariant, enforce in code review): **contracts never add/remove
`EclipseAttachments.LIVES`, never trigger `BanService`, never drop below
`HeartsService.MIN_HEARTS`+1 effective.** Day-advantage/-disadvantage packages, all expiring
at next rollover (delivered through `ContractModifierService`, offline-safe via
`AwardService.queueReward` + `deliverPending(player)` on login):
- **Killer ("Vollstrecker") advantage:** skills at 2.5× (`setSecretMultiplier`), +1 temp heart
  (`HeartsService`, capped `MAX_HEARTS 7`), +12 umbral shards (`EclipseAttachments.SHARDS`),
  ore/shard-drop favor by reusing the existing global buff ids `"ore_drops"`/`"shard_drops"`
  as *per-player* multipliers inside `ContractModifierService` (config-mirrored from
  `buffs.json` magnitudes), and a cosmetic: their next kill of the day replays the FirstBlood
  bell for them alone.
- **Victim ("Gezeichneter") disadvantage:** skills at 0.5×, −1 temp heart, hunger drains 1.5×
  (inverse of the existing `"buff_half_hunger"` effect id in `BuffEffects`), grave spawns one
  chunk further (flavor param into `lives/GraveBlock` placement), and their sidebar shows a
  scar icon all day (`SidebarSyncService.markDirty`). NOT stacked with the normal death costs
  they already paid — `DeathFlowHooks` stays observe-only and untouched.
- **Survivor (target at expiry):** skills 1.5×, +4 shards, title "Überlebt." — smaller than
  killer's prize so hunting stays worth the risk.
**Hooks:** `ContractModifierService` (new, ticks in `ServerTickEvent.Post`, persisted in
`ContractState`), `SkillsApi`, `HeartsService`, `ShardEconomy`, `AwardService.queueReward`.

### #7 — Warm/cold hunt pings ("Witterung") — tension without a wallhack
Every 90 s during ACTIVE, the hunter gets a distance-bucketed sensory ping, never a direction:
≥300 m "kalt" (single low wood knock), 150–300 m "lau" (double knock), 50–150 m "warm"
(heartbeat pair + faint vignette warm tint), <50 m "heiß" (fast heartbeat + `MarkVignetteOverlay`
micro-pulse 10 t). Same-dimension check; different dimension = flatline tone. Precedent for
"points but never names": `economy/WatcherCompassItem` (nearest player needle, "paranoia is
the product"). The target gets the mirror crumbs at HALF rate with one bucket less precision —
enough to feed dread, not enough to confirm. Optional config `pings.compass_synergy=true`:
while ACTIVE, a held Watcher Compass points at the *contract target* instead of nearest player
(item suddenly matters on contract days; 8-shard item gets a spike day).
**Hooks:** new `S2CContractPingPayload(bucket)` (client plays sound via
`client/contracts/ContractPingFx`), `WatcherCompassItem.inventoryTick` target override,
`MarkVignetteOverlay.trigger`.

### #8 — Fairness engine: who may be drawn ("Die Trommel")
Weighted draw over `AnalyticsApi.onlineOrKnownUuids`, all weights in `contracts.json`:
- **Lives-aware:** players at 1 life (read `EclipseAttachments.LIVES`) are excluded as
  *targets* (a contract death must sting, not end a run); still eligible as hunters.
- **Proximity-aware:** pairs currently within 400 m get 2× pair-weight (a hunt that can
  physically happen inside 30 min); cross-dimension pairs 0.25×.
- **Heat-aware:** heavy killers (day-window `AnalyticsApi.value(server, day, uuid,
  AnalyticsKeys.KILL_TOTAL)` high) drift toward being TARGETS; repeat victims
  (`AnalyticsKeys.DEATH` high) drift toward being HUNTERS — the system self-balances drama.
- **Participation:** must have ≥20 min playtime today (`AnalyticsKeys.PLAYTIME_S`) to be drawn
  at all; fresh joiners (day-1 `FIRST_OVERWORLD_JOIN`) immune both directions for one day.
- **Cooldowns:** same hunter→target pair 3 days; being target twice in a row impossible.
Draw is seeded `worldSeed ^ day` (same determinism philosophy as the RouletteStrip's
day+category seed) so `/dev contract preview` shows tomorrow deterministically and
`/dev contract reroll` bumps a salt — mirroring `AwardService.preview/reroll` exactly.
**Hooks:** `AnalyticsApi`, `AnalyticsKeys`, `EclipseAttachments.LIVES/FIRST_OVERWORLD_JOIN`,
`AwardService.preview/reroll` as the command-shape template.

### #9 — Resolution ceremonies + the "Vollstrecker" award category
Three distinct endings, each a server-wide beat (grammar stolen from `FirstBloodService`:
one sound + one shake + one banner, never a name):
- **SUCCESS:** world-wide deep bell (FirstBlood's `BELL_PITCH 0.5F` an octave lower), global
  `S2CShakePayload`, banner *"Der Vertrag ist erfüllt."* The killer privately sees the target's
  real head again — X now solid red, stamped "ERFÜLLT" (`GlitchText` decay-in). The victim's
  death screen (client/death package) gets one extra line: *"Es war ein Vertrag."* — they
  learn their death was bought, not random. THAT line is the best story-generator in the
  system.
- **EXPIRY:** soft sunrise chord, banner *"Der Vertrag ist verfallen."*; hunter privately sees
  the head crumble to uniform-skin gray (anonymity resealing itself — inverse of the reveal).
- **WRONG-KILL (non-terminal):** global thunder, no banner — the server hears injustice but
  isn't told (idea 5 handles the private messaging).
Awards integration: new `AwardConfig.Category` entries in the daily roulette —
`"vollstrecker"` (metric: new analytics key `contract_success`) and `"entkommen"`
(metric `contract_survived`), reward-table tier "combat" (`400 XP / 4 shards` default per
`AwardConfig` line ~182). They only appear in the strip on days a contract resolved, which
makes award night itself leak yesterday's drama.
**Hooks:** `S2CAnnouncePayload` styles `"contract_success"/"contract_expiry"`,
`S2CShakePayload` broadcast, `client/death` screen line injection, `AwardConfig.Data`
categories, `AnalyticsSampler` increments.

### #10 — Voice choreography: the hush and the whisper
Two touches through the existing SVC seam (`voice/EclipseVoicePlugin`, the ONLY class allowed
to import the Voice Chat API — keep it that way):
- **Reveal hush:** during the 6 s ceremony, `VoiceMuteApi.setGlobalMuted(server, true)` then
  restore prior per-player states (`isEntryMuted` respected). The server going dead-silent
  while every screen flashes is the moment everyone remembers. Client-side,
  `client/drama/LastMinuteHush` already knows how to duck ambient audio — reuse for the
  non-voice layers.
- **Proximity whisper (config-gated, default ON):** while the hunter is <50 m ("heiß" bucket),
  `MicrophonePacketEvent` packets *from the target* reaching *the hunter* get a −6 dB gain
  drop and light bit-crush (opus payload transform in the plugin). The target sounds slightly
  wrong to their hunter — subliminal, deniable, terrifying in retrospect. Never applied in
  reverse (the target must not detect the hunter via audio artifacts).
Voice stays otherwise untouched: anonymity of voices is already the players' own problem
(voice IS the one identity channel Eclipse deliberately leaves open), and the contract system
must not close it — recognizing your friend's voice and *still not knowing if they hold your
contract* is the game.
**Hooks:** `EclipseVoicePlugin.onMicrophonePacket`, `VoiceMuteApi`, `LastMinuteHush`.

### #11 — Edge cases: offline targets, ghosts, and every ugly branch
- **Target logs out mid-window:** `ghosts/LogoutGhostService` already spawns a persistent,
  hittable `LogoutGhostEntity` for leavers. Rule: the ghost IS the target. Hunter kills the
  ghost → contract SUCCESS at 60% payout (victim's disadvantage applies on their next login
  via the queued-modifier path, `AwardService.queueReward`-style). The existing
  `S2CGhostRevealPayload(ghostEntityId, ownerName, ticks)` even lets us flash the ghost for
  the hunter for 3 s at "heiß" range — a one-time position hint that punishes log-dodging.
- **Hunter logs out:** window keeps running; no proxy. Expiry as normal (their loss).
- **Target dies to environment/mobs/other players:** VOIDED (idea 5 covers the other-player
  case as wrong-kill for that killer); hunter gets nothing, target's estate untouched —
  `lives/InheritanceService` and `GraveBlock` behave exactly as any death.
- **Target at 1 life at draw time:** excluded by idea 8; if they DROP to 1 life mid-window
  (heart loss elsewhere), contract auto-voids with a private note to the hunter: *"Der
  Vertrag wurde zurückgezogen."* — the system visibly refuses to be an executioner.
- **Cutscene/freeze overlap:** if `cutscene.FreezeService` holds players (gathers), the window
  start is deferred until the lock clears (poll the `CUTSCENE_LOCK` attachment; it's transient
  by design).
- **Realtime pause:** deadline is stored as remaining-millis while `RealtimeDayApi.isPaused()`,
  identical to how the xbox window survives `timeMutate`.
- **Server restart mid-window:** `ContractState` + `resumeOnBoot` (idea 1); deadline passed
  during downtime → EXPIRY on boot, ceremonies replayed in compressed form (banner only).
- **Revive interaction:** a contract-killed player revived via `ritual/ReviveRitual`
  (`DeathFlowHooks.onRevived`) keeps the day-disadvantage — revival restores life, not dignity.
**Hooks:** `LogoutGhostService.isValid`, `S2CGhostRevealPayload`, `InheritanceService`,
`EclipseAttachments.CUTSCENE_LOCK`, `RealtimeDayApi`, `DeathFlowHooks.onRevived`.

### #12 — Dev commands, analytics keys, gametests — the ops layer
`/dev contract` tree, registered via `DevCommandRegistry.register(DevCommandDoc...)` from a
static initializer (freeze-before-boot rule respected), style copied from `DevBuffCommands`;
`/dev docs export` then self-documents it into `docs/DEV_COMMANDS.md`:

| Command | Effect | perm |
|---|---|---|
| `/dev contract status` | phase, pair (ops-eyes only), deadline, odds snapshot | 2 |
| `/dev contract preview [day]` | deterministic next draw (mirrors `/eclipse awards preview`) | 2 |
| `/dev contract reroll` | salt-bump tomorrow's draw | 2 · caution |
| `/dev contract start <hunter> <target> [minutes]` | force a REAL window now | 2 · caution |
| `/dev contract prank [minutes]` | force a PRANK window | 2 · caution |
| `/dev contract resolve <success\|expire\|void>` | force-resolve current window | 2 · caution |
| `/dev contract reveal <player>` | replay the head-reveal overlay for one client (FX test, no state) | 2 |
| `/dev contract odds <key> <value>` | live-tune an odds knob for this instance (cf. `/dev xboxevent reward set`) | 2 |
| `/dev contract wrongkill <killer> <victim>` | simulate the justice path | 2 · caution |

New `AnalyticsKeys`: `contract_success`, `contract_survived`, `contract_wrong_kill`,
`contract_target_s` (seconds survived while targeted) — all static keys so
`AnalyticsKeys.isStaticKey` and the awards metric resolver accept them; incremented through
the same `AnalyticsSampler` path as `KILL_TOTAL`. GameTests in `gametest/contracts/` mirroring
the per-feature convention (`gametest/awards`, `gametest/buffs`, ...): draw determinism,
wrong-kill modifier math, ghost-target resolution, crash-resume. Config file row for the
`/dev reload` table: `contracts.json`. Lang: ship `docs/plans_v3/langdrop/IDEA-20.json`
(en_us + de_de, parity enforced by `tools/langmerge/merge_langdrops.py`) — keys under
`eclipse.contract.*` / `dev.eclipse.contract.*`.

---

## 4. Deliberate design stances (so reviewers argue with the right things)

1. **The head reveal shows a face, never a name.** Names stay dead everywhere; the breach is
   visual only, and only toward hunters. This preserves the letter of every blocker in the
   anonymity table while violating its spirit exactly once — which is the point.
2. **Prank rounds default to "nobody is hunted".** "Everybody hunted" is a deathmatch and the
   lives economy can't pay for it. The scare + the exhale + a stayed-online consolation is
   the safer, funnier shape; the chaos variant stays behind a config flag.
3. **Wrong kills don't end the contract.** Ending it would let targets hire a friendly
   "wrong-killer" as a 1-heart escape hatch. Instead the real hunter remains live and the
   wrong-killer eats Blutschuld — griefing the system is strictly worse than playing it.
4. **Contracts never touch permanent lives.** Advantage/disadvantage lives entirely in the
   skills/hearts/shards/drops layer and expires at rollover. Massive ≠ irreversible.
5. **Armor blackout is client-render only, server stays authoritative.** No combat math
   changes, no anticheat surface, and it composes safely with the existing glow layer.
