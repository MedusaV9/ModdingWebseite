# P6 bestiary entries — handoff for the BestiaryTab worker (P3)

**From:** P6-W56. **Consumer:** whoever reworks `client/handbook/tabs/BestiaryTab.java` (P3-owned file — P6 never edits it).

All `bestiary.eclipse.<id>.name` / `.lore` keys (en+de, full 2–3-line lore) are in
`docs/plans_v3/langdrop/P6-W56.json` — the table below carries the **shortened 1-line lore**
for layout planning plus the data the tab needs (`Creature(id, introDay)` list) and a
silhouette description per §4.3 (silhouettes are code-drawn by P3).

Intro days are frozen per plan §2.8. Danger tier scale: **0 ambient · 1 common · 2 elite ·
3 mini-boss · 4 boss** (render as skull pips or similar at P3's discretion).

| id | name en / de | 1-line lore en | 1-line lore de | intro day | tier |
|---|---|---|---|---|---|
| `drift_lantern` | Drift Lantern / Treiblaterne | Soul-flames caged in glass, adrift above the dead sea. | Seelenflammen in Glaskäfigen, treibend über der toten See. | 1 | 0 |
| `fog_revenant` | Fog Revenant / Nebel-Wiedergänger | A robe with no body drifting the storm scars — when the wisps flare, you go blind. | Eine Robe ohne Körper in den Sturmnarben — flammen die Irrlichter auf, erblindest du. | 6 | 1 |
| `storm_hound` | Storm Hound / Sturmhund | Pack hunter of the fog storms; the howl is a courtesy, the charge is not. | Rudeljäger der Nebelstürme; das Heulen ist Höflichkeit, der Sturmlauf nicht. | 6 | 1 |
| `glitched_husk` | Glitched Husk / Glitch-Hülle | The new land came back wrong — do not wait for it to finish loading. | Das neue Land kam falsch zurück — warte nicht, bis es fertig geladen hat. | 8 | 1 |
| `glitched_hound` | Glitched Hound / Glitch-Hund | A hunter stitched from misplaced frames; the jaw arrives before the head. | Ein Jäger aus verrutschten Einzelbildern; der Kiefer kommt vor dem Kopf an. | 8 | 1 |
| `glitched_tick` | Glitched Tick / Glitch-Zecke | Shard-mites boiling out of unstable ground in threes; the swarm is a countdown. | Splittermilben, die zu dritt aus instabilem Boden quellen; der Schwarm ist ein Countdown. | 8 | 1 |
| `fog_colossus` | Fog Colossus / Nebelkoloss | Slow the way a landslide is slow — when both fists rise, move. | Langsam, wie ein Erdrutsch langsam ist — heben sich beide Fäuste, lauf. | 9 | 2 |
| `eclipse_cultist` | Eclipse Cultist / Eklipsen-Kultist | They wore the hooded uniform before you did — by choice. | Sie trugen die Kapuzenuniform vor dir — freiwillig. | 9 | 1 |
| `pale_sentinel` | Pale Sentinel / Fahler Wächter | Utterly still while watched; every glance away is a stride you will not hear. | Vollkommen still, solange man hinsieht; jeder Blick zur Seite ist ein lautloser Schritt. | 10 | 2 |
| `rift_warden` | Rift Warden / Risswächter | Half a knight, half a wound in the world — and the wound holds the swords. | Ein halber Ritter, halb eine Wunde in der Welt — und die Wunde hält die Klingen. | 10 | 3 |
| `fog_tyrant` | Fog Tyrant / Nebeltyrann | When a storm grows old enough, it grows a king. | Wird ein Sturm alt genug, wächst ihm ein König. | 12 | 4 |

## Silhouette notes (1 line each, for the code-drawn icons)

- `drift_lantern` — glass-cage cube head with inner flame, 4 staggered hanging tendrils (jellyfish read).
- `fog_revenant` — tall legless robe cone hovering, long claw arms, asymmetric coral shelf on ONE shoulder.
- `storm_hound` — lean low quadruped, swept-back split-jaw head, 3 spine shards along the back, whip tail.
- `glitched_husk` — humanoid zombie outline with cubes split/offset off-axis (shoulder floats detached, half face displaced).
- `glitched_hound` — quadruped outline datamoshed: jaw offset ahead of the skull, one leg frame-skipped.
- `glitched_tick` — small flat mite, body split into 2–3 offset shards; draw as a trio cluster if space allows.
- `fog_colossus` — hulking round-shouldered gorilla-brute, tiny sunken head, massive flat-knuckle arms, coral shelves on back.
- `eclipse_cultist` — hunched hooded robe, 3 small floating rune pages orbiting one hand, knife in the other.
- `pale_sentinel` — 2.6-block lanky tree-revenant: stilt legs, arms past knees ending in root claws, twig-antler crown.
- `rift_warden` — vertical half/half: polished knight silhouette on one side, jagged rift void on the other, swords floating in the void half.
- `fog_tyrant` — mountain-shouldered husk whose upper half dissolves into a fog crown; caged core in the chest cavity.

## Notes

- ids are the frozen registry ids (all `eclipse:` namespace). The glitched family is **three separate
  entity types** (`glitched_husk`/`glitched_hound`/`glitched_tick`), not one id with `Kind` NBT — the
  registrar (`GlitchConfig` defaults) and spawners already use the split ids; the bestiary should too.
- All three glitched entries share intro day 8 (they arrive with the first fresh ring after day 8).
- `drift_lantern` is limbo-only ambience (tier 0, harmless, killable); intro day 1 because every player
  sees limbo on day 1.
- Lore voice: dread-tinged second person, one practical survival hint folded into each entry
  (per plan §2.8) — the full versions in the langdrop keep that structure.
