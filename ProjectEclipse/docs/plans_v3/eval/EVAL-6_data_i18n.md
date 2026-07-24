# EVAL-6 — Data / content / i18n audit

Scope: static, read-only audit of lang files, `data/eclipse` JSONs, `assets/eclipse` (models,
geo/animations, sounds, credits), config defaults (goals/quests trigger ids, awards ↔
analytics keys) and docs claims. No Gradle task was run; `scripts/geckolib_gen/validate_geo.py`
(read-only, stdlib) was executed on all geo/animation files. Line references are approximate.

## Methodology / what was verified clean

- **Lang parity:** `en_us.json` and `de_de.json` both parse, both contain exactly **1401 keys**,
  zero one-sided keys, zero duplicate keys (checked with `object_pairs_hook`), zero `%s`
  placeholder-arity mismatches, no mojibake.
- **Missing keys:** all **468 distinct** literal keys used via `Component.translatable("…")`,
  `EclipseLang.tr("…")` and `EclipseLang.trString("…")` resolve. Apparent misses are all either
  vanilla keys (`menu.singleplayer`, `title.multiplayer.disabled*`, `narrator.screen.title` in
  `EclipseTitleScreen`) or dynamic prefixes whose full suffix sets were verified:
  `gui.eclipse.loading.tip.1–8` (`TIP_COUNT = 8`), `gui.eclipse.artifact.rules.line1–10`
  (`RULE_LINE_COUNT = 10`), `gui.eclipse.handbook.tab.<8 tab ids>`,
  `gui.eclipse.handbook.revival.step1–3.{title,text,math}`, `gui.eclipse.settings.*`
  (all toggle/slider/enum/section keys incl. `.tip` variants),
  `dev.eclipse.anticheat.{threshold,level,action}.*`, `message.eclipse.skill.proc.<5 proc ids>`,
  `bestiary.eclipse.<id>.{name,lore}` for the full `BestiaryTab.CREATURES` roster.
- **German quality (30-string random sample + targeted checks):** natural, idiomatic German;
  no machine-translation artifacts. Address form is a coherent scheme, not an accident:
  ihr-form for advancements/broadcasts (all 18 advancement descriptions), du-form for personal
  UI/messages (76 keys). All `Sie` hits are third-person pronouns, not formal address.
- **Data JSONs:** all **68** files under `data/eclipse/**` parse. Advancements: all parents
  exist, all icons are registered items, `announce_to_chat` is `false` on all 18,
  `sends_telemetry_event` false. Recipes: every `eclipse:` ingredient/result
  (`heart_extractor`, `heralds_lure`, `revive_sigil`, `vitae_shard_glitch`) is registered in
  `EclipseItems`. Tags: `tags/entity_type/glitched.json` values ⊆ registered entity ids
  (`GlitchEntities`); all 178 `tags/item/emi_hidden.json` ids are registered
  (`EclipseItems`/`DevToolItems`/`ClassicBlockItems` with `ItemKind != NONE`); tier gear tags
  are vanilla ids. Loot tables: structurally valid; `eclipse:replant` in
  `storm_cache`/`rift_warden`/`fog_tyrant` resolves to `data/eclipse/enchantment/replant.json`
  (whose `description` key `enchantment.eclipse.replant` exists in both lang files).
  Dimensions reference existing dimension types (`eclipse:limbo`, `eclipse:xbox_classic`).
- **Assets:** all **206** `assets/eclipse/**` JSONs parse. All 107 model JSONs' `eclipse:`
  texture refs resolve to PNGs; no missing `eclipse:` parent models; all 13 blockstates
  reference existing models. `validate_geo.py`: **14/14** geo+animation pairs PASS, 0 errors,
  0 warnings (13 entities + `respawn_door` block). All 13 GeckoLib entity textures exist at
  `textures/entity/<id>.png`. `sounds.json`: 47 events, every `eclipse:` file entry has its
  `.ogg` on disk (incl. all 8 `music/*.ogg`), zero orphan oggs. `credits.json` well-formed;
  all 5 `titleKey`s exist in both langs; music entries ↔ `sounds/music/*.ogg` match 1:1.
- **Config defaults:** goals/quests defaults build triggers from the `TriggerType` enum
  (compile-time safe — no invalid ids possible). All 24 default award metrics are valid
  `AnalyticsKeys` static categories or `kill:`/`mine:`/`craft:` dynamic keys.
  `analytics.eclipse.category.<id>` lang keys exist for all 22 static categories in both
  locales. Altar deposit purposes in defaults (`MILESTONE`, `OFFERING`) match
  `EclipseSignals.AltarDepositPurpose`.
- **Docs:** CREDITS.md's 8 music tracks match `credits.json` + disk; bundled versions in
  CREDITS.md / `docs/BUNDLING.md` / `bootstrap.json` / `build.gradle` / `gradle.properties`
  are mutually consistent (Eclipse 2.1.0, Veil 4.3.0, GeckoLib 4.9.2, EMI 1.1.18+1.21.1,
  Mouse Tweaks 2.26.1); `tools/classicblocks/provenance.json` exists; `modgate_ids.json`
  pre-gating claims match `ModGateIds.java`/`AntiCheatCheck.java`.

## Critical

None found in the audited scope.

## Medium

### M1 — Default goals reference team beats that no code ever fires

- **Files:** `progression/goals/GoalConfig.java` (~659 `d11_revive` →
  `beat("player_revived")`, ~713 `d14_crossing` → `beat("crossing_survived")`);
  `progression/goals/QuestEngine.java` (~549–580 `evaluateBuiltinBeat`);
  `progression/GoalTracker.java` (~72/77).
- **Why:** the only production `completeTeamBeat` emitters are `GoalTracker`
  (`herald_summoned`, `finale_begun`) and `QuestEngine`'s built-ins (`altar_level_*`,
  `shard_pool_*`, `all_hearts_*`, `herald_defeated`, `ferryman_defeated`, `dragon_defeated`).
  `player_revived` and `crossing_survived` fall to `evaluateBuiltinBeat`'s `default -> false`
  and are fired by nothing — the revive ritual and the ferryman crossing never call
  `QuestApi.completeTeamBeat`. `goalsComment()` even advertises them as
  "External engine beats", but the shims don't exist.
- **Impact:** the day-11 main "revive a player" and day-14 main "survive the crossing"
  default goals can only complete via admin `/eclipse goals tick`; the authored event arc
  silently stalls for players on those days.

### M2 — German glossary drift for the core progression item ("Umbral Shard")

- **File:** `assets/eclipse/lang/de_de.json`.
- **Why:** the item is named **"Umbrasplitter"** (`item.eclipse.umbral_shard`) but other
  player-facing strings use **"Umbralsplitter"**
  (`advancement.eclipse.event.first_shard.description`) and **"Umbral-Splitter"**
  (`award.eclipse.reward.shards`, `message.eclipse.skill.proc.bonus_shard`,
  `award.eclipse.stat.…banker` line). Three spellings of the event's central currency.
- **Impact:** players cannot reliably match quest/award text to the inventory item name;
  looks unpolished in the most-seen strings of the mod.

### M3 — Same creature, two different German names (bestiary vs entity/nameplate)

- **File:** `assets/eclipse/lang/de_de.json`.
- **Why:** `entity.eclipse.deckhand` = "Decksmann" but `bestiary.eclipse.deckhand.name` =
  "Deckhand" (untranslated); `entity.eclipse.umbral_stalker` = "Umbra-Pirscher" but
  `bestiary.eclipse.umbral_stalker.name` = "Schattenpirscher"; minor: `entity.eclipse.gazer`
  = "Starrer" vs bestiary "Der Starrer".
- **Impact:** the handbook bestiary card and the mob's nameplate/death message disagree,
  which reads as two different creatures (especially Umbra-Pirscher vs Schattenpirscher).

## Low

### L1 — Orphaned and out-of-sync `award.eclipse.category.*` lang family

- **Files:** both lang files; `awards/AwardConfig.java` (~180–290).
- **Why:** no Java code reads `award.eclipse.category.*` — award titles/stat lines come from
  the `Localized` EN/DE strings embedded in `awards.json` defaults. The lang family (21 keys
  ×2 locales) is dead weight and already diverged: missing `merchant`, `mainstay`,
  `side_seeker`, `personal_best`; contains `best_offering` (plus `award.eclipse.stat.best_offering`)
  which is not a default category.
- **Impact:** none at runtime today; misleads translators/future workers into editing keys
  that do nothing.

### L2 — Stale `_p4_hook`/`_doc` claims that `eclipse:replant` is unregistered

- **Files:** `data/eclipse/loot_table/fog_storm/storm_cache.json` (~38),
  `loot_table/entities/rift_warden.json` (~3, 40), `loot_table/entities/fog_tyrant.json` (~3, 40).
- **Why:** comments say the enchantment "is registered by P4; entry degrades gracefully if
  absent" — it is present at `data/eclipse/enchantment/replant.json`, so the caveat is stale.
- **Impact:** doc rot only; the entries resolve fine.

### L3 — CREDITS.md points at a machine-local absolute path

- **File:** `CREDITS.md` (~61).
- **Why:** "Integrity hashes and the full staging ledger are in
  `/workspace/xbox_staging/SOURCES_AND_LICENSES.md`" — that path is outside the repository
  and only exists on the original staging machine; anyone cloning the repo gets a dead
  reference for exactly the licensing-sensitive artifact (Xbox world binaries, whose
  redistribution CREDITS.md itself flags as uncleared).
- **Impact:** provenance/licensing evidence is not reproducible from the repo.

### L4 — README "Known limitations" bullets are stale

- **File:** `README.md` (Known limitations, ~1330; Layout, ~1300).
- **Why:** "the two OGG sound events are minimal placeholders" — `sounds.json` now has 47
  events over 28 oggs including 8 licensed, credited music tracks; "textures … are
  placeholder programmer-art" predates the 13 painted GeckoLib entity textures and the MIT
  classic-texture import; the Layout section still says "the five mob classes" while ~20
  entity types are registered across 9 registrars.
- **Impact:** doc rot; misleads new contributors about asset completeness.

### L5 — 10 shipped mobs have bestiary lore but are absent from the bestiary roster

- **Files:** `client/handbook/tabs/BestiaryTab.java` (~44–51 `CREATURES`),
  both lang files (`bestiary.eclipse.*`).
- **Why:** lang ships name+lore pairs for 17 creatures, but the handbook roster lists only 7
  (v2 arc + drift lantern). `eclipse_cultist`, `fog_colossus`, `fog_revenant`, `fog_tyrant`,
  `glitched_hound/husk/tick`, `pale_sentinel`, `rift_warden`, `storm_hound` are registered,
  spawnable entities whose finished bestiary text is invisible in game. The class doc frames
  the roster as append-per-mob ("adding future mobs is one roster line"), so this looks like
  roster lag rather than intent.
- **Impact:** finished, translated content players never see; the P6 mobs never unlock a
  bestiary card.

## Quick wins (top 3)

1. **Fire the two missing beats** (fixes M1): call
   `QuestApi.completeTeamBeat(server, "player_revived")` where the revive ritual completes
   (`ritual/ReviveRitual`) and `…, "crossing_survived")` at the ferryman-crossing survival
   point — both are one-line shims exactly like `GoalTracker.BEAT_HERALD_SUMMONED`.
2. **Unify the shard glossary + creature names in `de_de.json`** (fixes M2/M3): pick
   "Umbrasplitter" (the item name) and update the 3–4 divergent strings; align
   `bestiary.eclipse.deckhand.name` → "Decksmann" and pick one of
   "Umbra-Pirscher"/"Schattenpirscher" for both keys. Pure lang-file edits, no code.
3. **Sweep the dead/stale metadata** (fixes L1/L2/L4): delete (or sync) the
   `award.eclipse.category.*`/`award.eclipse.stat.*` orphan block in both lang files, drop the
   three `_p4_hook` replant caveats, and refresh the README placeholder-audio/texture and
   "five mob classes" bullets.
