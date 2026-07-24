# W4-BESTIARY wiring — progressive mob knowledge (kills unlock weaknesses)

Worker: W-BESTIARY. Kills of `eclipse:` mobs unlock deeper handbook bestiary info per
player: **T0 unseen** (silhouette + scrambled name) → **T1 encountered** (name + base
lore) → **T2 hunter, 3 kills** (field notes: hunting pattern + spawn grounds) →
**T3 slayer, 10 kills** (WEAKNESSES, info-only — no combat perk per scope).

## Files

New (server, `progression/bestiary/**` ownership):

- `progression/bestiary/BestiaryTiers.java` — shared tier math (thresholds, per-id
  overrides). No MC imports; used by server AND client so both always agree.
- `progression/bestiary/BestiaryState.java` — per-save SavedData
  (`data/eclipse_bestiary.dat`, overworld storage, `AnalyticsState` pattern): player UUID
  → mob id → lifetime count, plus the per-player encountered set.
- `progression/bestiary/BestiaryService.java` — kill-lane consumer + proximity encounter
  scan + login sync + tier-up sends.

New (network, own registrar):

- `network/bestiary/S2CBestiaryPayload.java` — byte-lean full snapshot
  (`(path, varint count, byte tier)` per KNOWN mob only; T0 ids are absent) + optional
  tier-up marker. ~350 bytes late-game.
- `network/bestiary/BestiaryPayloads.java` — self-registering MOD-bus registrar, version
  group `bestiary1`, id prefix `eclipse:bestiary/`. Do NOT also register in
  `EclipsePayloads` (duplicate registration throws at startup).

New (client):

- `client/progression/ClientBestiaryCache.java` — `ClientUnlockCache` pattern: static
  init installs the `BestiaryPayloads` consumer, logout resets. Tier-up moment =
  `UiSounds.unlockSting()` + action-bar caption ("Bestiary updated: Storm Hound —
  weaknesses revealed", en+de).

Edited:

- `client/handbook/tabs/BestiaryTab.java` — v2 tier-aware cards: T0 silhouette +
  GlitchText, unlock pips I/II/III, kill/sighting counter, "next entry at N kills" hint,
  T3 weakness section with the DANGER accent bar. Day-gating replaced by knowledge-tier
  gating (you learn creatures by hunting, not by waiting); the intro day stays as a lore
  line on unlocked cards. Roster gained `wizard_orin` (day 11 slot; entry tolerates the
  W4-WIZARD family being unwired — it just stays T0). Variable card heights, text layout
  cached against (width, lang generation, bestiary generation).

Langdrop: `docs/plans_v3/langdrop/W4-BESTIARY.json` (en+de) — `.behavior` + `.weakness`
for all 17 shipped mobs, full T1–T3 set for `wizard_orin`, and the new
`gui.eclipse.handbook.bestiary.*` UI keys (tier-up captions, counters, hints, section
labels). Existing `.name`/`.lore` keys are untouched and stay the T1 layer.

## Wiring asks (integrator)

1. **Merge the langdrop** into `assets/eclipse/lang/{en_us,de_de}.json`. Everything else
   is self-registering (`@EventBusSubscriber` classes only — `EclipseMod`,
   `EclipsePayloads` untouched). Until the merge, the tab degrades gracefully: missing
   `.behavior`/`.weakness` render the DIM "records pending" line, never raw keys.
2. Nothing else. No config keys, no registry entries, no new assets.

## Design decisions (read before re-balancing)

- **Kills ride the `EclipseSignals.onMobKilled` lane** (registered once on
  `ServerStartedEvent`, `AnalyticsService` pattern) — NO new `LivingDeathEvent`
  subscriber (P4 §2.0 rule 6). The lane already filters to tracked
  survival/adventure players.
- **Encounters (T0 → T1)**: a slow proximity scan — every 40 ticks (phase 27, off the
  0/13/20/50 sweeps), one 16-block AABB query per tracked player. Kills also mark
  encountered, so a long-range snipe still unlocks T1. No damage-event subscriber was
  added: no damage lane exists on `EclipseSignals`, and damage almost always implies
  proximity within a scan period.
- **Boss override** (`herald`, `ferryman`, `rift_warden`, `fog_tyrant`): first kill =
  full dossier (T2 and T3 thresholds are both 1). 3/10 kills is unreachable for
  once-per-world set pieces.
- **Sighting override** (`gazer`, `wizard_orin`): progress counts THROTTLED SIGHTINGS
  (one per mob id per 60 s, from the same proximity scan) instead of kills — the gazer
  vanishes when damaged (no kill lane will ever fire), and Orin is a unique neutral NPC.
  UI labels flip to "Sightings"; thresholds stay 3/10. The cooldown ledger is in-memory
  (a restart may forgive one cooldown — harmless).
- **Sync policy**: full snapshot on login + on every progress change (also mid-tier, so
  the kill counter stays live). Tier-ups piggyback on the same payload; multiple
  tier-ups in one scan pass celebrate only the highest.
- **Zero cost when closed**: client work is a volatile map swap per payload; the tab
  rebuilds its text layout only when width/lang/snapshot generation change.

## Sample weakness texts (of 17 authored — all checked against entity code)

- **Pale Sentinel**: "Its bark hardens under observation: while frozen it takes only
  HALF damage — but a statue cannot swing back. Keep every eye on it and grind it down
  in perfect safety; the halved blade is slow, but the unwatched stride is lethal. Never
  trade full damage for a glance away." (`FROZEN_DAMAGE_FACTOR = 0.5F`)
- **Storm Hound**: "The lunge is locked the instant the crouch ends — a single sidestep
  dodges the entire line. If it misses or slams a wall, the hound stands sparking and
  helpless for two full seconds." (`ChargedLungeGoal`: direction locks at windup end,
  `STAGGER_TICKS = 40`)
- **Fog Colossus**: "The slam is announced a full second before it lands, and the
  shockwave HUGS THE GROUND: beyond three blocks from the fists, a well-timed jump
  clears it entirely. Inside those three blocks there is no dodge at all."
  (`GroundSlamGoal`: airborne victims beyond `INNER_RADIUS = 3` are skipped)

## Risks

- **Thresholds are frozen in code** (`BestiaryTiers`), not config — a deliberate
  scope cut. If P4 wants tunables, lift them into `eclipse-common.toml` later.
- **The proximity scan credits spectating bystanders** standing near someone else's
  fight with T1 encounters (by design: "got within 16 blocks"), but T2+ still requires
  personal kills.
- **`wizard_orin` copy risk**: his item is named from `WizardEntities` javadoc
  ("Sun-Core Catalyst"); if W4-WIZARD ships a different display name, touch up
  `bestiary.eclipse.wizard_orin.weakness` in the langdrop.
- **Boss re-kills**: bosses jump T1 → T3 on the first kill; if a server re-summons
  bosses often and wants a slower ladder, change the override in `BestiaryTiers` only.
- **Sighting AFK farming**: a player idling near Orin accrues one sighting per minute
  (T3 after 10 minutes of presence). Accepted — it reads as "studying him".
