# W4-TOGGLES wiring — action-toggle dev suite + voice changer

## Registration

No shared file was edited (`EclipseMod.java`, `EclipsePayloads.java`, lang JSONs, `DevCategory`
untouched). Everything self-registers:

| Class | Bus / discovery | Role |
|---|---|---|
| `admin/ToggleAction` | — | Action enum (build, mine, craft, pvp, move, interact, drop, pickup) with the early-out bitmask + lang-key helpers. Chat has NO toggle — it is already sealed by `anonymity/ChatBlocker`. |
| `admin/ActionTogglesState` | — | SavedData `eclipse_action_toggles.dat` (overworld storage): per-action global allow flag + per-player ALLOW/DENY tri-state overrides. All-allow default serializes to an empty tag. |
| `admin/ActionTogglesService` | GAME | Enforcement events + mutation API + lock-free active-bits cache + move-lock reconciliation + throttled action-bar deny hints. |
| `devtools/dev/DevToggleCommands` | GAME | `/dev toggle ...` (perm 2), 4 `DevCommandRegistry` docs (`toggle.*`, category PLAYERS). Merges into the existing `/dev` literal. |
| `voice/VoicePreset` | — | Preset enum (OFF, DEEP 0.8×, HIGH 1.25×, GHOST 0.9× + 6 Hz tremolo, GLITCH random 0.85–1.25× per frame). API-free. |
| `voice/VoiceDsp` | — | Pure `short[]` DSP (linear-interp resample + seam-crossfade window overlap, tremolo). API-free, standalone-testable. |
| `voice/VoiceChangerConfig` | GAME | `config/eclipse/voice_changer.json` (ProtectionConfig pattern, `ReloadHooks` id `voice_changer`): `enabled`, `playerSelectablePresets`, `frameBudgetMicros` (2000), `autoDisableStrikes` (5). |
| `voice/VoiceChangerState` | — | SavedData `eclipse_voice_changer.dat`: global default preset + per-player presets. |
| `voice/VoiceChangerService` | GAME | API-free broker: thread-safe runtime preset mirror for the voice thread, mutation API, DSP budget accounting + auto-disable kill switch. |
| `voice/VoiceChangerPlugin` | `@ForgeVoicechatPlugin` | The ONLY class importing `de.maxhenkel.voicechat.api` (same isolation contract as `EclipseVoicePlugin`). Second plugin id `eclipse_voice_changer` — Simple Voice Chat loads every annotated class, so the existing mute plugin was not edited. |
| `voice/VoiceChangerCommands` | GAME | `/voice <preset>` + `/voice reset` (perm 0, SELF only, config-whitelisted presets). |
| `devtools/dev/DevVoiceChangerCommands` | GAME | `/dev voice changer ...` (perm 2), 4 registry docs (`voice.changer.*`). Merges under DevPlayerCommands' existing `/dev voice` literal. |

## Commands

- `/dev toggle <action> global (on|off)` — on = allowed. Actions are Brigadier literals (tab completion).
- `/dev toggle <action> player <player> (allow|deny|clear)` — tri-state override, beats global.
- `/dev toggle status [player]` — global flags + override counts, or one player's effective/override table.
- `/dev toggle clearall` — everything back to allowed, overrides dropped, move-locks released.
- `/voice (off|deep|high|ghost|glitch)` — self preset (stored as a per-player override; `off` overrides a non-off global default); `/voice reset` clears the override. Gated by `voice_changer.json` `enabled` + `playerSelectablePresets`.
- `/dev voice changer <player> (<preset>|clear)`, `/dev voice changer default (<preset>|clear)`, `/dev voice changer status`, `/dev voice changer reset` (re-arms the budget kill switch).

All operator mutations use the standard `dev.eclipse.audit` broadcast + `[DEV AUDIT]` log line.

## Toggle enforcement decisions (read before extending)

- **Zero perf cost when idle**: every handler first reads one `volatile long` bitmask; a bit is
  set only while that action has a global deny or ≥1 player DENY override. All toggles off ⇒
  every event handler is a single field read + branch. The mask refreshes on server start and
  on every mutation (mutations only flow through `ActionTogglesService`).
- **craft**: `ItemCraftedEvent` is not cancellable — the crafted result is shrunk to 0 exactly
  like `progression/RecipeGate` (its result-slot-strip mechanism with an all-recipes predicate);
  ingredients are NOT consumed because the take never completes.
- **move**: reuses `cutscene/FreezeService.freeze/unfreeze/isFrozen` per the plan instead of
  duplicating the rubber-band. Consequences (deliberate, documented): a move-denied player is in
  full "statue mode" — the freeze also grants invulnerability and cancels interactions (that is
  what the FreezeService lock is). The lock is re-asserted each tick when the watchdog TTL
  (5 min), death, dimension change or relog releases it; toggling back to allow releases it
  immediately (command-path reconciliation, since the tick path early-outs once the bit clears).
  Caveat: the lock object is shared with cutscenes — if a cutscene freezes an already
  move-denied player, ownership blurs and clearing the toggle mid-cutscene would release the
  cutscene's lock too (cutscene TTL watchdogs still bound the damage; accepted for a dev tool).
- **pvp**: cancelled when EITHER side (attacker or victim) is pvp-denied — a denied player can
  neither attack nor be griefed. Two hooks: `AttackEntityEvent` (melee swing, earliest) +
  `LivingIncomingDamageEvent` (arrows/tridents/indirect, which never fire AttackEntityEvent).
  Layers cleanly with `protection/SpawnProtectionRules` (zone pvp) and `FreezeService` invuln:
  each cancels independently on its own predicate; order is irrelevant.
- **drop**: `ItemTossEvent` cancel destroys the stack (it already left the inventory), so the
  stack is returned via `placeItemBackInInventory` (`ArtifactSlotLock` precedent).
- **pickup**: `ItemEntityPickupEvent.Pre` + `TriState.FALSE` (`ModGate` precedent).
- **interact** covers all four right-click events (block/item/entity/entity-specific), the same
  cancel set FreezeService uses — "right-click use" without entity interact would leave villager
  trading open.
- **Exemptions**: spectators are always exempt; creative and ops are NOT — set a per-player
  ALLOW override for stage crew instead (explicit beats implicit; deliberate deviation from the
  RecipeGate/ModGate `isSurvival()` convention because these toggles are event-control, not
  progression).
- **Feedback**: localized action-bar hint per action (`message.eclipse.toggle.<action>`),
  throttled to 1 per 1.5 s per player (held right-click / standing on an item pile / shift-mass
  crafting cannot spam).

## Voice changer — what actually worked (honest notes)

- **API verified from the jars, not assumed**: `javap` on `voicechat-api-2.6.20` (gradle cache)
  and the full `voicechat-neoforge-1.21.1-2.6.16.jar` (run/mods) confirmed:
  `MicrophonePacketEvent extends PacketEvent<MicrophonePacket>`; `MicrophonePacket` exposes
  `getOpusEncodedData()`/**`setOpusEncodedData(byte[])`**, and the impl
  (`MicrophonePacketImpl`) mutates the underlying `MicPacket` — so an in-place decode→DSP→
  re-encode in the mic event transforms what every receiver hears (locational, group AND
  whisper packets all fan out from that one MicPacket). `ServerEvent.getVoicechat()` provides
  `createDecoder()`/`createEncoder()`. `PluginManager.dispatchEvent` stops iterating once an
  event is cancelled ⇒ packets muted by `EclipseVoicePlugin` never reach the DSP (the mic
  handler also registers at priority −100 to sort after the mute handler).
- **Per-speaker codec state**: opus codecs are stateful per stream — one lazily-created
  decoder+encoder pair per speaking player (`ConcurrentHashMap`), closed on
  `PlayerDisconnectedEvent` and `VoicechatServerStoppedEvent`. An empty opus payload is SVC's
  end-of-transmission marker: forwarded untouched, codec + tremolo state reset.
- **Threading**: `MicrophonePacketEvent` fires on SVC's packet thread, NOT the server thread.
  The voice thread therefore never touches SavedData/config-IO: presets live in a
  `ConcurrentHashMap` + volatile default inside `VoiceChangerService`, mirrored from
  `VoiceChangerState` on server start and on every command mutation.
- **DSP**: naive per-frame pitch shift — linear-interp resample by the pitch factor, then
  truncate (pitch<1) or loop with a ≤96-sample equal-gain seam crossfade (pitch>1) back to the
  960-sample frame. Frames are independent (no inter-frame overlap-add) ⇒ slight robotic
  graininess at frame edges, fully intelligible for 0.8–1.25×. Standalone harness results
  (960-sample 440 Hz frames, measured over 1 s of concatenated output): pitch ratios 0.779 /
  0.889 / 1.224 for targets 0.80 / 0.90 / 1.25; GLITCH provably jumps per frame; **measured
  DSP cost 12–59 µs/frame average** (opus re-encode will dominate in-game; still far below
  budget).
- **2 ms budget / auto-disable**: the plugin measures decode→DSP→encode with
  `System.nanoTime()`; `autoDisableStrikes` (default 5) CONSECUTIVE frames over
  `frameBudgetMicros` (default 2000) trip a global kill switch with a WARN log
  (`/dev voice changer reset` re-arms; healthy frames reset the strike counter). Consecutive—
  not single-frame—by design: the harness recorded isolated 4–25 ms JIT/GC outliers that would
  otherwise false-trip immediately.
- **Failure posture**: any DSP exception logs (10 s throttle) and passes the ORIGINAL packet
  through — the changer can break itself, never voice chat. With the effective preset OFF the
  handler costs one map read; the speaker never hears their own effect (SVC clients don't play
  back their own mic).
- **Not achieved / untested in-game**: actual audio listening (no gradle, no server/client run
  in this pass — see Verification), and the pitch shifter is not formant-preserving (it's the
  requested naive resampler, not a phase vocoder).

## Verification performed (no gradle, per rules)

- All 12 new files compile against the repo's NeoForge 21.1.238 merged jar +
  `voicechat-api-2.6.20` via a `javac` args harness (exit 0, `-nowarn` clean).
- `VoiceDsp`/`VoicePreset` exercised standalone (no MC classes needed): length invariance,
  pitch ratios, OFF-passthrough identity, overflow-free output, glitch randomness, µs/frame
  numbers above.
- Langdrop `W4-TOGGLES.json`: 38 keys, en/de parity asserted, every key referenced in code
  (incl. the 8 dynamic `message.eclipse.toggle.<action>` keys) covered, no collision with the
  existing lang JSONs.
- NOT done here: `./gradlew build`/`runServer`/`runClient` (forbidden this pass) — so command
  registration, SavedData round-trip and the audible result still need one integrator smoke
  boot.

## Integrator asks

1. Merge `docs/plans_v3/langdrop/W4-TOGGLES.json` via `python3 tools/langmerge/merge_langdrops.py`.
2. Standard smoke boot: `/dev toggle build global off` → place block denied w/ action-bar hint;
   `/dev toggle move player <p> deny` → statue mode; `/dev toggle clearall`. With SVC + a real
   mic: `/voice deep` and listen on a second client; `/dev voice changer status` after ~30 s of
   talking to sanity-check the worst-frame µs figure.
3. No new DevCategory was added (shared enum) — both command groups sit under PLAYERS. If a
   dedicated TOGGLES/VOICE rail is wanted later, that's a one-line shared-file change.
4. `/dev docs export` will pick up the 8 new registry entries automatically.

## Risks

- **FreezeService lock sharing** (move toggle ↔ cutscenes) as described above — bounded by the
  cutscene watchdog TTLs.
- **Voice changer CPU on a busy server**: cost is per SPEAKING player per 20 ms frame on SVC's
  packet thread; 10 simultaneous speakers ≈ 10× (decode+DSP+encode) ≈ low single-digit ms/frame
  worst case — the kill switch exists precisely for this; consider raising
  `frameBudgetMicros` only with measurement.
- **Opus decoder FEC/loss**: the per-player decoder sees the mutated stream boundaries only via
  the empty end-marker; packet loss mid-utterance degrades one frame (decoder resync), same as
  vanilla SVC plugins.
- **`/voice` self-service is per-player-override based**: a player's `off` beats a dev-set
  global default (intended: consent), but a dev PER-PLAYER preset can be overwritten by the
  player re-running `/voice` — if hard enforcement is ever needed, gate
  `playerSelectablePresets` to `[]` in the config and drive everything via `/dev voice changer`.
