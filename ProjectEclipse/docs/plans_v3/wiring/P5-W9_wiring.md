# P5-W9 wiring notes (integrator)

Worker **P5-W9** owns the Xbox event runtime: `xboxevent/**`, `devtools/dev/DevXboxCommands.java`,
the three datapack dimensions, and the bundled world zips. **No `EclipseMod.java`,
`EclipsePayloads.java`, or `FxPayloads.java` edit is required** — everything below
self-registers.

## Self-registering (no hub change)

| Class | Bus / event | What it does |
|---|---|---|
| `XboxWorldInstaller` | game bus, `ServerAboutToStartEvent` | Lazy-extracts the bundled zips into `dimensions/eclipse/xbox_<id>/` (sha256-gated, reset-marker aware) |
| `XboxEventService` | game bus: `ServerStartedEvent` (crash resume), `ServerTickEvent.Post`, `LivingDeathEvent` @ HIGHEST, `PlayerLoggedIn/OutEvent`, `ServerStoppedEvent` (cache clear) | Event lifecycle, timer, entry/exit, death protection, reward |
| `XboxEventService.Setup` | MOD bus, `FMLCommonSetupEvent` | `ClassicChestLoot.setProvider(XboxEventService::lootFor)` + `XboxEventConfig.bootstrap()` |
| `XboxPayloads` | MOD bus, `RegisterPayloadHandlersEvent` | Own registrar version group `"xbox1"` — `EclipsePayloads` stays untouched (plan §1.5 convention) |
| `DevXboxCommands` | game bus, `RegisterCommandsEvent` (second `literal("dev")` root, perm 2 — Brigadier merges) + handbook docs via static init into `DevCommandRegistry` | `/dev xboxevent start/stop/status/time/portal/lockout/reward/reset` |
| `XboxLeaveCommand` | game bus, `RegisterCommandsEvent` | `/xboxleave` (+`confirm`), permission 0, doc entry `xboxleave` |
| `XboxEventConfig` | — | Reload hook self-registered: `DevReloadRegistry.register("xboxevent.json", …)` → picked up by `/dev reload` |

`DevCategory.XBOX` and the `dev.eclipse.category.xbox` lang key landed with P5-W1 — no change.

## Langdrop

`docs/plans_v3/langdrop/P5-W9.json` — **60 keys × (en_us + de_de)**: announcements, enter/exit
messages, clickable leave line, lockout, bossbar title (`bossbar.eclipse.xbox`), all
`/dev xboxevent` feedback, 9 handbook doc keys. World display names
(`eclipse.xboxworld.<id>.name`) are P5-W7's and are already merged.

## P3-W11 contract (timer overlay + portal transition) — FROZEN

### `S2CXboxTimerPayload` (`eclipse:xbox/timer`, S2C)

| Field | Codec | Meaning |
|---|---|---|
| `endsAtEpochMillis` | VAR_LONG | Wall-clock end of the event window |
| `serverNowEpochMillis` | VAR_LONG | Server clock at send (client offset base) |
| `worldId` | STRING_UTF8 | `tu1 \| tu12 \| tu14` |
| `active` | BOOL | `false` = hide the overlay (sent on exit / event end) |

Client-side remaining time = `endsAtEpochMillis - (System.currentTimeMillis() + clockOffset)`
where `clockOffset = serverNowEpochMillis - receiveWallClock` (same technique as P3's sidebar).
Sent: on entry, on every `/dev xboxevent time` mutation, every 20 s (drift guard) to players
**inside** the dimension only, plus one final `active=false` on exit. The default handler
caches into `XboxPayloads.TimerClientState` (pure data, dedicated-server-safe) — the overlay
may read that or take over the handling.

### `C2SXboxAckPayload` (`eclipse:xbox/ack`, C2S)

`overlayCapable: BOOL` — send `true` once after receiving the first timer payload; the server
then removes that player from the W9 **bossbar fallback** (`bossbar.eclipse.xbox`). Vanilla
clients never send it and keep the bossbar.

### Portal transition seam

The entry/exit glitch payload (`S2CPortalFxPayload{style, holdTicks}`) is **owned by P3-W11**
(plan §4.3 — a P5-local duplicate payload id is forbidden). Frozen values:
`XboxPayloads.TRANSITION_STYLE = "eclipse:xbox_glitch"`, `XboxPayloads.TRANSITION_HOLD_TICKS = 30`.

Wiring once W11's payload exists (one line, W11 side or integration pass):

```java
XboxPayloads.setPortalTransitionSender(player ->
        PacketDistributor.sendToPlayer(player, new S2CPortalFxPayload(
                XboxPayloads.TRANSITION_STYLE, XboxPayloads.TRANSITION_HOLD_TICKS)));
```

W9 calls `XboxPayloads.sendPortalTransition(player)` right before every cross-dimension
teleport (entry, death return, leave, timeout, stop) — it silently no-ops until the sender is
installed, so nothing breaks in the interim. The client controller maps the style to P2's
`TransitionFx.playPortalEnter(18)` / `playPortalExit(24)` (already landed, verbatim per
P2-W8 wiring).

## W11 optional cleanup: rift FX constants

`XboxPortal` sends `S2CFxEventPayload` with **locally constructed** ids
`eclipse:fx/rift_open|close` (byte-identical to `FxPayloads.FX_RIFT_OPEN/FX_RIFT_CLOSE`) and
params per P2-W8 wiring (`a` = tear width 5.0, `b` = 1 portal style / 0 on close, sent at the
portal center, range 128). Local ids because `FxPayloads`' client dispatch references sibling
P2 packages still in flight this wave (`stormfx.StormFxClient`, `client.ShipDoorGlow`,
`cutscene.client.*`), which would break the isolated xboxevent compile. Once P2's client stack
fully lands, swap the two constants + `PacketDistributor.sendToPlayersNear` for
`FxPayloads.sendFxEvent(level, FxPayloads.FX_RIFT_OPEN, center, 5.0F, 1.0F, 128.0D)` — purely
cosmetic, ids and wire bytes identical.

## P4 death-pipeline note (lives system)

W9 cancels `LivingDeathEvent` at **HIGHEST** priority for players inside Xbox dimensions
(full heal + teleport back — no drops, no death screen, no lives/hearts logic downstream,
since cancelled events do not reach lower-priority listeners). Any P4 listener registered with
`receiveCanceled = true` (e.g. analytics) MUST consult
`XboxEventApi.isProtectedDeath(player)` and skip lives/heart deductions when it returns true.
The reward path calls `TimedBuffApi.Holder.get().start(server, buffId, minutes)` — B9's
Holder indirection, no wiring.

## Known foreign-file issue (NOT touched by W9 — for W1/W11)

`devtools/dev/DevRoot.java:92` fails compilation:

```
error: unreported exception CommandSyntaxException; must be caught or declared to be thrown
        return sendHelp(context, null, 1);
```

`openHandbookOrHelp` is used as a `Command<CommandSourceStack>` lambda body and calls
`sendHelp(…)` which `throws CommandSyntaxException`; the enclosing method does not declare it.
One-line fix on W1's side (declare `throws CommandSyntaxException` on `openHandbookOrHelp` —
the `Command` functional interface already permits it). Everything else in `devtools/dev`
compiles clean with W9's files.

## Gametests

`gametest/xboxevent/XboxEventGameTests.java` — 7 tests on P4-A1's harness (state-machine NBT
round-trip, instance-scoped lockouts, crash resume past `endsAt`, payload round-trips,
manifest/dimension agreement, loot decode + vanilla-disc invariant, duration parsing). No
wiring; runs with the standard gametest harness.
