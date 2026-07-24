# FFIX-C wiring notes (final-eval ECONOMY/REACHABILITY fixes per FINAL-DOPA-SOL)

## What shipped (self-contained code/default changes)

1. **Altar milestone deadlock** — `core/config/EclipseConfig.defaultMilestones()` reordered
   to a non-circular ladder (L1 copper/coal, L2 iron/amethyst, L3 gold/redstone,
   L4 herald core + diamond/pearls/obsidian, L5 netherite/quartz blocks; emerald blocks
   dropped entirely) and `worldgen/ore/OreConfig` default unlock stages fixed
   (iron 2→0, overworld gold 2→1, Nether quartz + Nether gold 2→1, diamond 3→2;
   netherite deliberately stays Nether stage 2 = day 10). FINAL-DOPA-SOL §3 / blocker P0-1.
2. **Shard double-spend** — `economy/ShardEconomy.deposit` now credits the TEAM POOL only
   (was: personal balance AND pool per physical shard). Personal balances are funded only
   by direct rewards (goals/quests/contracts/admin). Per-player banked contribution stays
   visible via the existing `shards_banked` analytics counter → Shard Banker award (fired
   from `ritual/AltarBlock`'s SHARD_BANK signal, untouched). FINAL-DOPA-SOL §3 / P1-6.
3. **Wand XP curve** — `wand/WandConfig` default `levelCosts` 120/260/450/700 →
   **600/1800/3600/6000** (both the `parse` fallback array and `defaultsJson`).
   FINAL-DOPA-SOL §4 / P1-4.
4. **Contracts** — `contracts/ContractConfig`: `hunterSkillsMul` 1.5→**2.0**,
   `hunterDamageMul` 1.10→**1.15**, `hunterTempHearts` 1→**2**, `targetSkillsMul`
   0.75→**0.6** (target keeps the −15% `targetDamageMul` 0.85); wrong-kill values
   unchanged; `autoDaily` default **true** at the shipped 25% real / 5% prank odds
   (both `defaultJson` and the `parse` fallbacks). FINAL-DOPA-SOL §5 / P1-5.
5. **Bestiary reachability** — `progression/bestiary/BestiaryTiers`:
   `deckhand` + `the_other` moved to SIGHTING progression (kill lane still counts);
   late-stage-only families (`fog_revenant`, `storm_hound`, `fog_colossus`,
   `eclipse_cultist`, `pale_sentinel`, `deckhand`) get T2/T3 **2/5** (was 3/10);
   `the_other` T3 = **6**; `gazer` per-id sighting range **40 blocks**
   (`BestiaryService.scanAround` now queries one widened box and filters back per id —
   plain encounters stay 16 blocks). `rift_warden` verified already in `BOSS_IDS`
   (first kill = T3), no change needed. FINAL-DOPA-SOL §6 / P1-3.
6. **T2 Fortune's Echo** — `skills/SkillTreeConfig` `double_ore_drop_chance` 0.02→**0.03**
   (+ node description text en/de, which is config-embedded, not a lang key).
   FINAL-DOPA-SOL §2: the sibling eval (FINAL-DOPA-FABLE) confirms the proc trio is
   presented as the core mining-loop jackpot beat, so the eval's "if intended as a
   frequent jackpot beat, raise to 3–4%" condition holds. Skill curve itself untouched
   (L12 ≈ 4 h anchor holds; L15 at ~6.7 h left as-is per the eval).

## Lang

- `docs/plans_v3/langdrop/FFIX-C.json` → merge `shop.eclipse.deposited_pool`
  (en: "Banked %1$s shard(s) into the team pool — pool: %2$s" /
  de: "%1$s Splitter in den Team-Pool gebankt — Pool: %2$s") into
  `assets/eclipse/lang/en_us.json` + `de_de.json`. No other keys.
- The old `shop.eclipse.deposited` key ("… du: %2$s · Pool: %3$s") is now UNREFERENCED
  by code and can be retired from both lang files at the next sweep (leaving it is
  harmless).

## Operational note for the integrator (IMPORTANT)

All six fixes change **authored defaults** of file-backed configs
(`config/eclipse/milestones.json`, `ores.json`, `wand.json`, `contracts.json`,
`skilltree.json`). Defaults are only WRITTEN on first run — an existing dev/staging world
keeps its stale on-disk copies. For existing saves, delete those five files (or hand-edit
the changed values) and run `/eclipse reload` + `/dev reload`; fresh installs need nothing.
`ores.json` unlock stages apply to not-yet-generated terrain only — already-swept annuli
keep their ore population (fine for fresh event worlds, misleading on old test worlds).

## Out of FFIX-C scope — flagged for owners (all from FINAL-DOPA-SOL)

1. **P0-2: `RiftWardenEntity.summonAt` still has no production caller.** The bestiary
   boss threshold (1 kill = T3) is correct but moot until the Collapsed Vault boss room
   triggers the summon. Suggested seam: a proximity marker service à la
   `entity/boss/fog/FogBankMarker` armed by `worldgen/structure/dungeon/CollapsedVaultBuilder`
   (see `wiring/P6-W910_wiring.md` for the originally documented ask).
2. **Contract skill-multiplier stacking is last-write-wins** (`ContractModifierService`
   overwrites the single SkillsApi multiplier per grant). With the stronger 2.0×/0.6×
   values, a hunter-success + wrong-kill overlap now diverges more visibly; eval §5
   recommends recomputing one effective multiplier from all active ledger rows.
3. **Glitched-mob doc mismatch**: `GlitchConfig.minDay` (day 3) vs the handbook's day-8
   intro — align one of the two (eval bestiary fix #5).
