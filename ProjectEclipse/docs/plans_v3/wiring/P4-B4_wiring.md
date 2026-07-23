# P4-B4 wiring notes (integrator)

Worker **P4-B4** owns `skills/**` (R3: custom XP, curve, skills.json, 21-node tree, perks,
payload server side, advancement bridge, persistence, anti-abuse) and `gametest/skills/**`.
Apply the hub changes below after the wave merges — B4 did not edit foreign files.

## network/EclipsePayloads.java (required, one line)

A1 left `handleSkillNodeBuy` as a no-op stub. Wire it to the server handler:

```java
private static void handleSkillNodeBuy(final C2SSkillNodeBuyPayload payload, final IPayloadContext context) {
    if (context.player() instanceof ServerPlayer player) {
        dev.projecteclipse.eclipse.skills.SkillService.handleNodeBuy(payload, player);
    }
}
```

`SkillService.handleNodeBuy` re-validates everything server-side (cost, prereqs, ownership);
the payload is a pure request. Until wired, `/skills buy <node>` is a fully equivalent path.

## Lang JSONs (required)

Merge `docs/plans_v3/langdrop/P4-B4.json` — 21 keys × en_us/de_de (level-up + buy feedback,
procmsg toggle, 5 proc lines + `[hide]` link, 6 admin command lines).

**Not in the langdrop by design:** skill node titles/descriptions live inline as
`{"en": …, "de": …}` in `skilltree.json` (hot-reloadable content, server picks per player
locale via `LangService`, client GUI receives both locales in `S2CSkillTreePayload` JSON).

## gametest/GameTestSupport.java (A1 — recommended fix)

`mockSurvivalPlayer` casts `helper.makeMockPlayer(GameType)` to `ServerPlayer`, but the
vanilla method returns a bare `Player` subclass → **ClassCastException at runtime** for any
test using the helper. NeoForge's patched `helper.makeMockServerPlayerInLevel()` is the
working alternative (real `ServerPlayer` + embedded-channel connection, joins the player
list, deprecated-but-only-option in 1.21.1). B4's stateful tests
(`SkillSystemGameTests`) call it directly and are unaffected.

## Sibling dependencies (no action if those land as planned)

- **P4-B3 advancements**: bridge grants `eclipse:event/skill_10|skill_25|skill_40` at those
  levels (warn-once if the JSONs are absent) and pays skill XP for every `eclipse:` advancement
  earned, resolved from `xp.advancements` in skills.json (exact id → id with `event/` stripped
  → `default`). Keep table ids in sync with B3's advancement file names.
- **P4-B5 placed-block tracker**: `SkillPerks.isPlaced` reads A1's `PlacedBlockData`
  attachment directly (same O(1) bit test as B9's `PlacedBlockCheck`). Once B5's
  `PlacedBlockTracker` helper lands, all three call sites can converge on it.
- **P4-B9 timed buffs**: XP pipeline multiplies `TimedBuffApi.Holder.get().multiplier(server,
  "skill_xp")` — NO_OP (×1) until B9's service assigns the holder.

## EclipseSignals gaps (A1, optional later wave)

No `trade`/`breed` lanes exist, so `SkillService` subscribes to `TradeWithVillagerEvent` and
`BabyEntitySpawnEvent` directly. If A1 adds signal lanes later, migrate those two listeners.

## ExhaustionScaler (A1, optional later wave)

`ExhaustionScaler` factors are server-global (`Supplier<Float>`, no player parameter), so T3
Iron Stomach runs its own per-player exhaustion snapshot sweep inside `SkillPerks` (composes
multiplicatively with B9's global half-hunger buff). If A1 adds per-player factors, T3 can
move onto the shared scaler.

## Consumer surface (frozen)

| Consumer | Call |
|---|---|
| P4-B2 quest rewards | `SkillsApi.addXp(player, "quest", spec.reward.skillXp)` |
| P4-C1 sidebar | `SkillsApi.getLevel(server, uuid)` / `getTotalXp` / `getUnspentPoints` |
| P5-W4 admin commands | reference impl already in `/eclipse-skills` (perm 3): `xp add/set`, `mult set` (secret — source-only feedback, DEBUG log), `points add`, `tree reset`, `reload` |
| R11 rewards | `SkillsApi.addPoints(player, n)` (bonus points, level tracking untouched) |
| Anyone | `SkillsApi.setSecretMultiplier(server, uuid, f)` — clamped [0,100], never synced/broadcast |

## P3-W9 client contract (payload schemas)

- `S2CSkillStatePayload(level, totalXp, xpIntoLevel, xpForLevel, points, unspent,
  ownedNodes[], procMsgEnabled, secretMultiplierActive)` — sent on login, on every level-up /
  buy / toggle, else coalesced ≤1 per 20t. `secretMultiplierActive` is **hard-false** on the
  wire (anonymity).
- `S2CSkillTreePayload(json)` — canonical tree JSON at login + config reload:
  `{"branches":{id:{en,de}}, "nodes":[{id, branch, cost, requires[], title:{en,de},
  desc:{en,de}, effect, value, duration, cooldown}]}`.
- `S2CSkillProcPayload(procId, magnitude)` — proc ids: `double_ore`, `bonus_ore`,
  `bonus_shard`, `smelt_xp`, `double_loot`. Server already plays `eclipse:skill.proc` +
  optional clickable chat line; client adds flash/toast from this payload.
- `C2SSkillNodeBuyPayload(nodeId)` — send from the tree GUI; server validates and answers
  with a fresh state payload (+ action-bar feedback).
- Sounds `eclipse:skill.proc` / `eclipse:skill.levelup` registered by A1 (subtitles in A1
  langdrop).

## Self-registering (no EclipseMod change)

`SkillService`, `SkillPerks`, `AdvancementXpBridge`, `SkillCommands` — all
`@EventBusSubscriber(modid)`. Config reload joins `ReloadHooks.register("skills", …)` on
server start; statics reset on `ServerStoppedEvent`.
