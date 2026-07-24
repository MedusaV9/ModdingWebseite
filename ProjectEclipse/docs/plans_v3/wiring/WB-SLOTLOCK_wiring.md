# WB-SLOTLOCK wiring — sealed-slot visuals, view-distance pin apply, theater cleanup

## Registration

No `EclipseMod.java` or `EclipsePayloads.java` edit is required:

| Class | Bus | Role |
|---|---|---|
| `network/invlock/InvLockPayloads` | MOD | Registers `S2CInvLockPayload` (`eclipse:invlock/state`) on its own registrar, version group `"invlock1"` (GrowthPayloads pattern). Do NOT also register it in `EclipsePayloads` — duplicate registration throws at startup. |
| `progression/InvLockSync` | GAME | Additive sender hook: login send + 1 Hz poll (phase-offset tick 7) with per-player change detection. `PhaseInventoryLock` is untouched. |
| `client/invlock/InvLockClientState` | GAME (client) | Payload cache + materialize-in bookkeeping + logout clear. Dispatched lazily from `InvLockPayloads` (fully-qualified reference, `FxPayloads` pattern) — dedicated-server safe. |
| `client/invlock/InvLockOverlay` | GAME (client) | Void-slot painting, row-edge padlock hint, click/key blocking. |

## Slot semantics (wire contract)

`S2CInvLockPayload.lockedBits` is a bitset over `Inventory` container slots 0–40,
computed server-side from `PhaseInventoryLock` truth: `main_inventory` locked → bits
9–35 **except 17** (the `ArtifactSlotLock` pinned-artifact exemption, B16 — slot 17 keeps
`InventorySlotDecor`'s frame and is never voided); `armor` locked → bits 36–40; hotbar
never. Non-survival/adventure players get an all-clear (the sweeps skip them; the
gamemode change is picked up by the same 1 Hz poll). `mainUnlockDay`/`armorUnlockDay`
are tooltip hints only (earliest day plan listing the key, `-1` when only altar
milestones grant it — the client then shows the generic "Still sealed" line).

## Deliberate deviations from the plan text

- The void painting rides `ContainerScreenEvent.Render.Foreground` (the
  `InventorySlotDecor` precedent), **not** `ScreenEvent.Render.Post`: Foreground fires
  above slot items + the vanilla hover highlight but *below* tooltips and the carried
  stack, with the pose already at the container origin. `Render.Post` fires after
  `renderTooltip`, so a tooltip crossing the voided grid would be painted over. Covers
  are raised to z 200 (above item z 150, below carried 232 / tooltip 400) so a
  mid-sync stray item can never poke through.
- Beyond the requested `MouseButtonPressed.Pre` cancel, `MouseButtonReleased.Pre`
  (drag-drop release into a voided slot) and `KeyPressed.Pre` (hotbar-swap keys +
  offhand key while hovering a voided slot) are cancelled too — the number-key swap
  bypasses mouse clicks entirely and would flash an item beneath the cover for up to
  one sweep second otherwise.

## Known gaps (server-covered, accepted)

- A quick-craft **drag** that merely passes over voided slots is not cancelled per-slot
  (vanilla `mouseDragged` has no per-slot event); the release either lands on a voided
  slot (cancelled) or elsewhere. Any residue that does slip through is reversed by the
  `PhaseInventoryLock` 1 Hz sweep — this layer is visual/UX only.
- The creative screen is excluded (own scrolled grid, fake slot indices; creative
  players are never swept anyway).
- Toggling into creative sends an all-clear payload; the client suppresses the unlock
  sting/animation for it (local gamemode check), and re-seals silently on switching back.

## ViewDistanceClient (P5-W34 limitation closed)

`cutscene/client/ViewDistanceClient` now applies a positive `S2CViewDistancePayload`
**exactly** (clamped 2–32, so pins can LOWER the client render distance) while
`allowServerRenderDistance` is on; with it off it falls back to the original upward-only
cinematic semantics gated by `cinematicViewDistance`; with both off the request is held
but nothing is touched. Both toggles are live: a 1 Hz tick check re-applies/restores on a
config flip (and ONLY on a flip — a player moving the vanilla slider mid-override is not
fought). Restore-on-unpin, logout restore and the crash-recovery marker are unchanged;
options.txt is never permanently mutated. `DevViewDistance` needed no edit — its P5-W34
wiring "cross-worker limitation" paragraph is now obsolete.

**Caveat for the integrator**: pins and cinematic pushes share one wire shape, so while
`allowServerRenderDistance` is on a *cinematic* push below the player's setting now also
lowers it for the session. In practice `ViewDistanceService` pushes ≥ server view
distance + 4 (≤ 16) and `DevViewDistance` defers pins during cinematics, so this only
affects players rendering further than the pushed value — if that matters, split the
payload with an `exact` flag in a follow-up wave.

## GlitchErrorTheater (P3-W8 swap points executed)

- Private §2.1 palette mirrors → `EclipseUiTheme` constants (identical values, zero
  visual change).
- `playGlitchBurst()` body → `UiSounds.error()` per the P3-W8 wiring instruction; the
  suite owns the `uiSounds` gate, `uiSoundVolume` scaling and the §2.3 procedural
  fallback while `ui.error_glitch` is not yet registered.

## Integration actions

1. Merge `docs/plans_v3/langdrop/WB-SLOTLOCK.json` into both shipped language files
   (2 keys × 2 locales, `gui.eclipse.invlock.*`).
2. Nothing else — no new sounds (reuses `ui.unlock_sting`), no new textures (the padlock
   glyph is fill-built), no config keys.
