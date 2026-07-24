# WB-ROULETTE wiring notes — daily-awards head roulette overlay (P3-W10)

No shared hub file was edited: not `EclipseMod.java`, not `network/**`, not `registry/**`,
not `awards/**` (server), not `client/ClientStateCache.java`, not
`client/EclipseGuiLayers.java`, no lang assets, no `sounds.json`.

## Files

- `client/awards/AwardsOverlay.java` — queue + phase machine + card/summary rendering +
  ESC/sneak skips; self-registers its GUI layer (`eclipse:awards_roulette`,
  `registerAboveAll`) via its own `RegisterGuiLayersEvent` subscriber (FML 4 auto-routes
  mod-bus vs game-bus listeners, so one `@EventBusSubscriber` class carries both).
- `client/awards/RouletteStrip.java` — deterministic strip physics + head rendering.
- `client/awards/package-info.java`
- lang handoff: `docs/plans_v3/langdrop/WB-ROULETTE.json` (5 keys, en+de:
  `gui.eclipse.awards.header/summary/you/shared/skip_hint`)

## Trigger path — NO hook line needed in `ClientStateCache`

`EclipsePayloads.handleAwardReveal` (main thread) already caches the payload into
`ClientStateCache.awardRevealDay` / `awardCategories`. `AwardsOverlay` polls the cached
list **instance** once per client tick and reacts to it changing — zero shared-file edits,
zero per-frame cost beyond one reference compare.

If the integrator later prefers a push trigger, the exact diff (in `EclipsePayloads`, the
payload owner's file — still not `ClientStateCache`) would be:

```java
    private static void handleAwardReveal(S2CAwardRevealPayload payload, IPayloadContext context) {
        ClientStateCache.awardRevealDay = payload.day();
        ClientStateCache.awardCategories = payload.categories();
+       dev.projecteclipse.eclipse.client.awards.AwardsOverlay.onPayloadCached();
    }
```

(`onPayloadCached()` would just call the same internal poll; the polling version ships and
works without it, so this is optional and NOT required for merge.)

## Payload contract actually consumed (defensive parsing)

- The checked-in frozen `S2CAwardRevealPayload.Category` is
  `id/titleEn/titleDe/rewardTextEn/rewardTextDe/candidates{uuid,value}/winners[]` — there is
  **no** standalone `winnerIndex`/`statLine` field. Per `P4-B6_wiring.md`, B6 packs
  `title + "\n" + statLine` into the title fields; the overlay splits on the FIRST newline
  (no newline → title only, stat row stays empty; extra newlines are flattened to spaces).
  If the payload owner ever adds explicit fields, only `AwardsOverlay.buildReveals` changes.
- Ties: `winners.size() > 1` (all UUIDs tied at best value, `AwardMath.resolve`). The strip
  lands on `winners[0]`; co-winner heads fan out beside it with the localized
  `gui.eclipse.awards.shared` ("geteilt (n)") note.
- The client picks en/de literals via `EclipseLang.locale()` and renders the server strings
  verbatim (server strings are already bilingual literals; nothing is re-translated).

## Anonymity decisions (read before changing)

- The payload carries **UUIDs only** (its javadoc: "P3 renders anonymized heads") and every
  player wears one uniform skin (`client/mixin/AbstractClientPlayerMixin`). All roulette
  heads therefore render the SAME bundled face —
  `eclipse:textures/entity/eclipsed_player.png` — which is correct by design, not a skin
  fallback. The path literal is duplicated in `RouletteStrip.UNIFORM_SKIN` (mixins must not
  be referenced from regular code); keep the two in sync if the skin ever moves.
- No names are invented client-side: candidate/winner labels are `GlitchText` shimmer. The
  only readable identity is the localized `gui.eclipse.awards.you` ("DU"/"YOU") when the
  LOCAL player is among the winners — client-local knowledge, no leak.
- Candidate display order is shuffled with a `day + categoryId` seed (identical on every
  client), so the server's best-first candidate sorting leaks no ranking.

## Behavior contract

- Overlay, not a screen: input is never captured. One bounded exception: while the show is
  running (pre-summary), an ESC-opened vanilla `PauseScreen` (exact class, from gameplay
  only) is cancelled ONCE and skips to the summary card. Sneak press fast-forwards one
  reveal; ESC/sneak in the summary ends it.
- `F1` (`hideGui`) hides the layer while state keeps advancing; pause freezes the state;
  the cutscene letterbox delays show start (queue) and its existing HUD suppression hides
  the un-whitelisted layer mid-show.
- Dedup/queue: one show per day (login replays, the P2 cinematic-seam re-broadcast and
  payload spam collapse), queue cap 3 behind an active show/cutscene, hard 75 s failsafe.
- Late join: payloads cached within the first 5 s of being in-world (the login replay path
  in `AwardService.onPlayerLoggedIn`) are marked handled and never played.
- `reducedFx`: pre-landed strip (spin skipped), no flare/pop overshoot, instant text,
  longer read hold. Timing (full FX): ~0.9 s intro + per category 4.0 s spin + 0.5 s land +
  ~1–1.5 s stat typewriter + 0.9 s reward settle + 2 s hold + fade ≈ 8.8 s → ≈ 26–27 s for
  three categories (task's "~25s"), plus the skippable summary card.

## Sounds / FX

- `UiSounds.rouletteTick(pitch)` (max one per game tick; pitch falls with strip speed,
  rises slightly over the last fifth) and `UiSounds.rouletteWin()` (at the reward
  materialization beat). Both events + subtitles are already in `EclipseSounds` /
  `sounds.json` / lang (W1 ledger, merged) — no registry asks.
- `assets/eclipse/quasar/emitters/roulette_flare.json` is a WORLD-SPACE Quasar emitter and
  cannot sit behind a fixed screen-space overlay, so the robust option ships: a code-drawn
  screen-space flare (rotating warm→purple rays + glow quads) mirroring the emitter's
  gradient (`#FFF3C4 → #FFD166 → #C77DFF → #7B2CBF`). The emitter stays available to P2
  for any world-space award moment; no asset was touched.
- The reward "purple glitch" is a per-character `GlitchText` scramble-settle (settled
  prefix in `ACCENT`, re-rolling tail in `ACCENT_DEEP`) plus sparse flicker rects — the
  committed client fallback for P2's optional `eclipse:award_glitch` post flash.

## Merge asks (small, none blocking)

1. **P5 dev command** (in `EclipseCommands`/`AwardCommands`, both not P3-editable): a
   permission-2 `/eclipse awards send` (or `/eclipse-awards send`) that calls the existing
   public seam `AwardService.sendRevealNow(server)`. Needed for convenient in-game testing:
   `/eclipse-awards resolve` + relog does NOT replay (login-time payloads are suppressed by
   the late-join rule, and the server marks the reveal seen). One-liner:
   `.then(Commands.literal("send").executes(ctx -> { AwardService.sendRevealNow(ctx.getSource().getServer()); return 1; }))`
2. **Langdrop merge**: `docs/plans_v3/langdrop/WB-ROULETTE.json` (5 keys, en+de parity).
   Until merged, the five frame strings render as raw keys; all payload strings render
   regardless.

## Risks

- **ESC reinterpretation**: bounded to the running show; if the boss dislikes it, deleting
  the `onScreenOpening` handler degrades gracefully (sneak skip remains).
- **Dimension change during a broadcast**: if `minecraft.level` momentarily nulls while a
  reveal arrives (rare teleport windows), the state reset could swallow that payload; the
  P2 cinematic-seam re-broadcast (`sendRevealNow` is re-send-safe) covers it.
- **Frozen-payload drift**: if A1 later adds explicit `statLine`/`winnerIndex` fields, only
  `buildReveals` needs the mechanical update (parsing is isolated there).
