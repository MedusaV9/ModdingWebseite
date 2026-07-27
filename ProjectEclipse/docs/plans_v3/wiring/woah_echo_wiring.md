# WOAH-05 ECHO-HAIN — Verdrahtung / geteilte Dateien

Feature-Code lebt komplett in `woah/echogrove` (+ Client in `client/echo` und
`client/entity/echo` — der `GhostPlayerRenderer`-Muster-Ort). Hier steht, was an
geteilten Dateien angefasst wurde (minimal-additiv, frisch gelesen) und was
BEWUSST für den Hauptagenten offen bleibt.

## Angefasste geteilte Dateien (sanktionierte Ausnahmen)

1. **`woah/WoahFeatures.java`** — zwei Zeilen unter dem Anker
   `// --- WOAH-05 echo grove: mod-bus registrations go here ---`:
   `EchoGroveEntities.register(modEventBus)` (eigene DeferredRegister-Klasse, weil
   `ghosts/GhostEntities.java` gesperrt ist) und
   `EchoGroveItems.register(modEventBus)` (eigene DeferredRegister-Klasse, weil
   `registry/EclipseItems.java` gesperrt ist). Sonst NICHTS außerhalb des Ankers.

## Bewusst NICHT angefasst (Feature funktioniert ohne)

2. **`worldgen/DiscMapDefaults.java`** (gesperrt) — die Landmark-Zeile
   `eclipse:echo_grove, 0, 310, 30, 4` ist zentral BEREITS eingetragen;
   `EchoGroveLayout.landmarkXZ()` liest die frozen Row aus `DiscMapData`
   (Fallback: gespiegelte Konstanten `FALLBACK_X=0`/`FALLBACK_Z=310`, nur
   Kollisionswarnung im Log via `EchoGroveSites.onServerStarted`).
3. **`network/fx/FxCues.java`** (gesperrt) — die vier Cue-Ids leben als Konstanten
   in `woah/echogrove/EchoGroveCues.java` via `FxCues.cue("woah_echo_flood")` /
   `…bloom_rain` / `…whisper` / `…orb_collect`; die drei Loop-Row-Ids
   (`woah_echo_ground_fog`/`spores`/`tree_lights`) in `client/echo/EchoPhotonFxRows`.
   Wire-Format identisch; der Hauptagent KANN sie später als `FxCues.CUE_ECHO_*`
   einziehen (reine Aufräumarbeit).
4. **`network/EclipsePayloads.java`** (gesperrt) — nicht nötig:
   `woah/echogrove/EchoGrovePayloads` registriert `S2CEchoGrovePayload` in einer
   EIGENEN Versionsgruppe (`v1woahecho`) über einen eigenen
   `RegisterPayloadHandlersEvent`-Registrar (das `network/altar/AltarPayloads`-
   Muster). Captions/FX reiten die bestehenden `S2CCaptionPayload`/`FxPayloads`-
   Schienen.
5. **`registry/EclipseItems.java`** (gesperrt) — `memory_mote` (UNCOMMON, Glint,
   stacksTo 5) + `echo_blossom` (EPIC, Glint, stacksTo 1, Regen-Puls-Trinket)
   registriert stattdessen `woah/echogrove/EchoGroveItems`. Modelle
   `assets/eclipse/models/item/{memory_mote,echo_blossom}.json` + Texturen
   (`tools/skins/gen_echo_textures.py`) liegen bei. Umzug nach `EclipseItems`
   später möglich (Registry-Namen bleiben).
6. **`ghosts/GhostEntities.java` / `ghosts/GhostsState.java`** (gesperrt) — die drei
   Entity-Typen (`echo_ghost`, `echo_ghost_wolf`, `memory_orb`) registriert
   `woah/echogrove/EchoGroveEntities` (inkl. eigenem
   `EntityAttributeCreationEvent`-Subscriber); Persistenz läuft über die EIGENE
   SavedData `eclipse_echo_grove.dat` (`EchoGroveState`, `GhostsState`-Vorbild).
7. **`registry/EclipseSounds.java` + `assets/eclipse/sounds.json`** (gesperrt) —
   KEINE neuen Events; Spieluhr-Motiv wird server-sequenziert aus
   `NOTE_BLOCK_CHIME`/`NOTE_BLOCK_BELL` (Plan-§6.1-Fallback, ab Tag eins), Flüstern
   reused `AMBIENT_GAZER_WHISPER`, Belohnung `AWARD_STING`. Inventar +
   aufgeschobene Row-Definitionen: `woah_echo_sounds.json` (daneben).
8. **`assets/eclipse/lang/en_us.json`/`de_de.json`** (gesperrt) — alle Keys in
   `docs/plans_v3/langdrop/woah_echo.json` (en_us + de_de, inkl. der 5
   Lore-Fragmente `echo.eclipse.memory.0–4`). Ohne Merge zeigen Captions/Items/
   Dev-Feedback rohe Keys — funktional, aber hässlich.
9. **`veilfx/PhotonMobFx.java`** (geteilte statische Listen) — Orb-Attach-Loops
   verwaltet stattdessen `client/echo/EchoOrbGlowFx` (eigener Tick, nearest-8-Cap,
   `PhotonBridge.ensureAttachedFx`-Schiene).
10. **`music/EclipseMusicSounds.java` / `music/MusicCues.java`** (gesperrt) — kein
    ECHO_GROVE-Rung; kommt erst mit `music/echo_grove.ogg` (siehe
    `woah_echo_sounds.json`, deferred).

## Brigadier-Hinweis

`EchoGroveDevCommands` hängt sein `echo`-Subtree an den geteilten
`/dev woah`-Literal (Brigadier merged separate `register`-Aufrufe — dieselbe
Konvention wie `ChronoStasisDevCommands`/`ResonanceDevCommands`); der Leaf-Name
`echo` ist exklusiv belegt.

## Datapack-Oberflächen

- `data/eclipse/echo_scenes/*.json` — 5 Szenen; Server lädt sie bei
  `ServerStartedEvent` über den ResourceManager, Code-Defaults als Fallback
  (Datapacks können Szenen überschreiben/ergänzen).
- `data/eclipse/loot_table/event/echo_grove_finale.json` — referenzielle
  Loot-Table der Finale-Belohnung (der Drop selbst läuft programmatisch in
  `EchoFinaleSequence.dropReward`, damit kein LootContext-Boilerplate nötig ist).
