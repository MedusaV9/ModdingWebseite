# WB-SKILLS wiring handoff (P3-W9: skill tree GUI + XP HUD + level-up celebration)

## Files delivered (all NEW, all in `client/skills/`)

| File | Purpose |
|---|---|
| `SkillTreeModel.java` | Parses the `S2CSkillTreePayload` JSON from `ClientStateCache.skillTreeJson` (re-parsed only on change); tier auto-layout (row = prerequisite depth, column = branch, sibling fan-out); node states (OWNED/AVAILABLE/LOCKED) from the synced owned-node list; cosmetic item-icon table with per-branch fallback. |
| `SkillTreeWidget.java` | Pan/zoom canvas (0.75–1.5 zoom, drag pan, clamped to content, offscreen culling): node tiles + prerequisite edges that light up per state, draw-in wipes on unlock, purchase flash + expanding glow ring, available-node breathing pulse, pending-purchase padlock. |
| `SkillTreeScreen.java` | Quiet-Eclipse frame: header (level · XP · unspent ◇), canvas, detail footer with buy button; buy flow sends `C2SSkillNodeBuyPayload`, locks the node PENDING until the `S2CSkillStatePayload` refresh confirms (celebration + `ui.skill_buy`) or a 60t failsafe releases it; hover tooltip with exact numbers; 5t fade/rise open-close; ESC/K/mouse-bind close (B8 parity). |
| `SkillKeybind.java` | Default **K**, `key.categories.eclipse`, IN_GAME context; self-registered (nested mod-bus registrar) + game-bus `consumeClick()` poll. |
| `InventorySkillButton.java` | 16x16 "✦" button injected into `InventoryScreen` via `ScreenEvent.Init.Post`, anchored above the slot-17 artifact; re-anchors from `getGuiLeft()/getGuiTop()` every frame (recipe-book toggle re-centers without re-init); glyph brightens while unspent points wait; dedupe-guarded. |
| `SkillXpBarLayer.java` | Slim 2px 182-wide accent strip 2px above the vanilla XP bar + level numeral in the free column right of the bar; ~6t eased fill, gain pulse toward white + leading spark, 5t full-bar sweep then refill-from-empty on level-up; gated on `showCustomXpBar`, F1, spectator, and "no skill sync yet". |
| `LevelUpOverlay.java` | Center-screen "LEVEL n" glyph, purple glitch-in/out (GlitchText scramble resolve, chromatic ghosts, breathing hold, underline), `ui.level_up`, one `eclipse:unlock_burst` Quasar flourish (`spawnOrFallback`); queues multi-level jumps; login sync never celebrates; gated on `levelUpCelebrations`. |
| `SkillProcToast.java` | Toast mini-line above the hotbar for `S2CSkillProcPayload` (consume-and-clear of `ClientStateCache.lastSkillProcId`); intercepts the server's proc CHAT line (`ClientChatReceivedEvent.System`, matched by `message.eclipse.skill.proc.*` key): drops it when `procMessages=false`, else re-styles it in place with [hide] → `/eclipse-ui procs off`. |
| `SkillClientCommands.java` | Client `/eclipse-ui procs [on\|off]`: flips `EclipseClientConfig.PROC_MESSAGES` via `set()+save()` (B13-sanctioned path). |

## Already wired in this worker (no integrator action needed)

- **GUI layers self-register** via their own `RegisterGuiLayersEvent` subscribers
  (`EclipseGuiLayers` is frozen this wave): `skill_xp_bar` above `EXPERIENCE_BAR`
  (so hearts/food still draw over the strip), `skill_proc_toast` above `BOSS_OVERLAY`,
  `skill_level_up` above all. None are letterbox-whitelisted — cutscene HUD suppression
  is supposed to hide all three ( `LevelUpOverlay` additionally defers queued playback
  while `CameraDirector.isHudSuppressed()`).
- **Keybind + inventory button + client command self-register** (mod/game bus subscribers).
- **Zero server edits**: `network/**`, `skills/**`, `registry/**`, lang assets, sounds
  untouched. Client never predicts purchases; `ClientStateCache` is the only data source.

## Optional consolidation asks (one-liners, at the owner's leisure)

- `EclipseGuiLayers` owner MAY move the three layer registrations into the central file
  (delete the three nested `Registrar` classes when doing so). Not required.
- W2's `StatusTab` MAY add a "skill tree" link per the plan ledger — this worker did not
  touch handbook files.

## Lang merge

Merge `docs/plans_v3/langdrop/WB-SKILLS.json` into both locale assets (`en_us` + `de_de`).
Includes the keybind name `key.eclipse.skills` and the `commands.eclipse.procs.*` set from
the plan's W9 ledger. Node titles/descriptions need NO lang keys — the tree JSON carries
baked `{en,de}` literals (`SkillTreeConfig` `Localized` objects), picked client-side via
`EclipseLang.locale()`.

## Risks / edge cases (accepted, documented in code)

- **Proc collapse**: two `S2CSkillProcPayload`s inside one client tick collapse into one
  toast (the cache stores only the latest proc; no sequence counter, `network/**` frozen).
- **Buy-failure resolution**: a refused purchase has no explicit failure payload; the
  pending lock releases after 60t (the server already showed the reason on the action bar).
- **Chat interception**: matching is by translatable key prefix, so a future server
  restyle of the proc line still gets caught; a server sending baked literals instead
  would bypass the gate (falls back to vanilla behavior, nothing breaks).
- **RUN_COMMAND → client command** verified against this tree's NeoForge:
  `ClientPacketListener.sendCommand/sendUnsignedCommand` both try
  `ClientCommandHandler.runCommand` first (plan §6's SUGGEST_COMMAND fallback not needed).
- **Icons are client-side cosmetic** (payload carries none); unknown node ids degrade to
  branch icons, unknown proc ids to humanized text, malformed tree JSON to an empty tree
  with a hint line — never a crash.

## Test steps (dev, singleplayer)

1. `K` (or the ✦ button above the artifact slot in the inventory) → tree opens instantly;
   ESC/K closes with the 5t fade. Empty-state hint appears if no server sync yet.
2. `/eclipse-skills points add @s 5` → header ◇ updates; root nodes pulse; buy button
   enables; click UNLOCK → pending "…" + padlock → confirm flash + ring + line draw-in +
   `ui.skill_buy`; reopen → persists (server truth).
3. `/eclipse-skills xp add @s 30` → XP strip eases up + pulse + spark; enough XP for a
   level → full-bar sweep, numeral flash, center-screen "LEVEL n" glitch glyph +
   `ui.level_up` + burst. `/eclipse-skills xp add @s 1000` → celebrations queue.
4. Mine natural ore with T2 owned until a proc fires → toast above hotbar + chat line;
   click [hide] → `procMessages=false`, further procs show toast only;
   `/eclipse-ui procs on` restores.
5. F1 hides bar/toast/glyph; cutscene (`/eclipse-cutscene ...`) suppresses them; guiScale
   2/3: header degrades gracefully, canvas pans, tooltip clamps on-screen.
