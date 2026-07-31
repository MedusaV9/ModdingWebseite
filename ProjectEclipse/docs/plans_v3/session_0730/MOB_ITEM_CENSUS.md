# MOB/ITEM-ZENSUS (F-098) — Vollständiger Bestand + priorisierter Modell-Polish-Wellen-Plan

**Auftrag (F-098, 30.07.):** Jedes Custom-Mob und jedes Custom-Item bekommt ein eigenes
Subagent-Team (Planner→Ideen→mehrfache Polish-Iterationen) inkl. Blockbench/GeckoLib-
Modell-Verbesserungen. Dieses Dokument ist der Zensus + Wellen-Plan; Schwester-Dokument
ist `FX_CENSUS_WAVE13.md` (FX-Seite, Welle 13 — dessen Datei-Besitz gilt WEITER und wird
hier nirgends verletzt).

**Methode (alles verifiziert, nichts aus dem Gedächtnis):** rg über alle Entity-/Item-
Registrare (`ENTITIES.register`, `ITEMS.register`, `IClientItemExtensions`), Python-Parse
über ALLE `.geo.json`/`.animation.json` (Bones/Cubes/Keyframes/Loop-Flags, Einmal-Skript,
nicht committet), Review von `EclipseGeoRenderer`/`EclipseGeoMob`/`EclipseGeoMonster`,
`EclipseEntityRenderers`, `PhotonMobFx`/`MobPhotonFxRows`/`BossPhotonFxRows`/
`HeraldFerrymanFxRows`, `sounds.json`-Key-Scan, `docs/plans_v3/handoff/
P6_geckolib_conventions.md` (FROZEN-Contract), `scripts/geckolib_gen/`-Painter-Bestand,
B2_MOB_REPORT (Welle-13-Stand).

## Gesamtzahlen

| Kategorie | Bestand |
|---|---|
| Custom-Entity-Typen | **30** registriert (19 GeckoLib-Geo · 6 Code-Modell (`EclipseEntityRenderers`) · 3 Player-Modell-Wiederverwendung (Ghosts/Echo) · 2 Sprite/Sonstige (`memory_orb`, `herald_shard`)) |
| GeckoLib-Geo-Dateien | **27** `.geo.json` (19 entity + 2 block [`altar`, `respawn_door`] + 6 item) |
| Animations-Dateien | **27** `.animation.json` mit **126 Animationen** (101 entity + 9 block + 16 item) |
| Custom-Items (Hand-Registrare) | **~26** Registrierungen (davon 6 GeckoLib-3D-Items mit BEWLR, ~17 Sprite-Items, 3 BlockItems `grave`/`altar`/`respawn_door`) — plus Masse-BlockItems: **188** `classic_*` (Xbox-Ära) + Worldgen-/PaleGarden-Blöcke |
| Painter-Skripte | **19** unter `scripts/geckolib_gen/mobs/` + **6** unter `scripts/geckolib_gen/items/` + 2 Ausreißer (`scripts/skin_gen/backrooms_wanderer.py`, `tools/woahdome/gen_glitch_emitter_textures.py`) |
| Eigene Mob-Sound-Events | **nur 11 von 87** Sound-Events gehören Mobs (Herald 4, Ferryman 2, Gazer 1, 4× Boss-Musik) — ALLE anderen Mobs recyceln Vanilla-Sounds im Entity-Code |

Härtester Befund vorweg: **beide Nicht-GeckoLib-Bosse (Herald, Ferryman) haben
handgecodete Vanilla-Modelle ohne Keyframe-Animationen**, während Trash-Mobs wie der
Glitched Tick voll GeckoLib-animiert sind. Die Prioritätenpyramide ist invertiert.

---

## §1 Mob-Zensus — GeckoLib-Linie (19 Entities)

Alle laufen über die FROZEN-Basen `EclipseGeoMob`/`EclipseGeoMonster` (zwei Controller:
`base` = idle/walk-Loop, `action` = triggerbare One-Shots via `triggerAction()`, Server-
seitig gefeuert, GeckoLib synct selbst) + `EclipseGeoRenderer` (wrappt
`DefaultedEntityGeoModel`: EIN String-Id löst `geo/entity/<id>.geo.json` +
`animations/entity/<id>.animation.json` + `textures/entity/<id>.png` auf; Opt-ins
`withGlowmask()`/`withUprightDeath()`/`withTranslucency()`).

Spalten: B/C = Bones/Cubes, Tex = Canvas (+G = `_glowmask.png` vorhanden, +Alt =
Alt-Skin), Anims = Anzahl (Namen ohne Präfix `animation.<id>.`), FX = Photon-Anbindung
(Row-Owner in Klammern — Welle-13-Datei-Besitz!).

| Mob (Klasse) | Rolle | B/C | Tex | Anims | FX-Anbindung | Ist-Bewertung (was fehlt/schwach) |
|---|---|---|---|---|---|---|
| **Fog Tyrant** (`boss/fog/FogTyrantEntity`, Renderer `fogboss/FogTyrantRenderer` mit Custom-Layern) | BOSS | 25/35 | 128²+G | **10**: idle, stride, attack, lance_volley, storm_step_out/in, crown_call, squall, enrage, death(3.5s/115kf) | `tyrant_fog_arms`, `step_out/in`, `squall→blind_burst`, `death_implosion`, `statue_idle` (Rows: `BossPhotonFxRows` = **W13-A5-Besitz**) | Bestes Sheet des Bestands, ABER: `cloak_back`/`cloak_mid` nur 2 Mantel-Segmente (keine Nachschwing-Physik), keine Trail-Locator-Bones an `lance_left/right` (Photon-Entity-Lanes zielen auf den Root), death nicht auf die A5-Implosionskette getimt, dokumentiertes Scythe-Detach beim Statue-Handoff (F-081..087), Sounds = Vanilla-Warden-Recycling |
| **Rift Warden** (`boss/rift/RiftWardenEntity`, eigener `AutoGlowingGeoLayer`-Sub) | BOSS | 21/21 | 128²+G | **9**: idle, walk, attack, volley(100kf), blink_out/in, summon, stagger, death(3.0s/111kf) | `warden_eye_laser` (Telegraph), `warden_glitch_orbit` (Stagger) (Rows: `BossPhotonFxRows` = A5; Laser-Fix = **A4**) | Solide; schwach: blink_out/in ohne Scale-Warp (Teleport liest als Fade statt Glitch-Stretch), idle ohne „Atmung" der Riss-Platten, kein eigener Sound |
| **Fog Colossus** (`fog/FogColossusEntity`) | Elite | 18/22 | 128²+G | 6: idle, walk, attack, slam(78kf), roar, death | **KEINE dedizierte .fx** (einziger Elite ohne Body-FX) | 18 Bones für einen „Colossus" = zu starr; slam ist gut, aber roar ohne Kiefer-/Brust-Bones, walk ohne Gewichtsverlagerung (Masse-Gesetz: schwer = tief + langsam gilt auch für Anim!), FX-Lücke |
| **Storm Hound** (`fog/StormHoundEntity`) | Elite-Rudel | 22/22 | 64²+G | **7**: idle, walk, attack, charge_windup, lunge(98kf), howl(91kf), death | `hound_lunge_windup`/`hound_dash_trail` via `ChargedLungeGoal` (Rows: `MobPhotonFxRows` = **W13-B2**, frisch) | Gutes Sheet; schwach: kein sprint/run-Zyklus getrennt von walk, howl ohne Schulterblatt-Anhebung, Fell = flat weave |
| **Fog Revenant** (`fog/FogRevenantEntity`) | Sturm-Mob | 22/22 | 64²+G | 5: idle, walk, attack, cast_blind(77kf), death | `revenant_fog_ribbons` Loop (B2, frisch) | idle nur 20kf auf 20 Bones (1 kf/Bone = steif), Robe-Säume statisch obwohl die FX-Ribbons an ihnen „ziehen" sollen |
| **Pale Sentinel** (`pale/PaleSentinelEntity`) | Gebiets-Mob | 20/22 | 64²+G | 6: idle, walk, freeze, attack, death, bloom | `sentinel_petal_orbit` + `sentinel_alert` (B2) | freeze (die Signatur-Mechanik!) ist nur 19kf-Loop — kein Einfrier-ÜBERGANG; bloom nett aber ohne Petal-Bones fürs Orbit-Pairing |
| **Eclipse Cultist** (`dungeon/EclipseCultistEntity`) | Dungeon-Trash (häufigster Gegner-Kontakt!) | **13/11** | 64²+G | 5: idle, walk, cast(64kf), attack, death | nur `shadow_bolt_impact` (Projektil); **kein Body-FX** | 11 Cubes für den meistgesehenen Gegner; Robe = 1 Cube, keine Hood-Glow-Anbindung, cast gut getimt aber ohne Ärmel-Flare |
| **Shadow Bolt** (`dungeon/ShadowBoltProjectile`, `GeoEntityRenderer` direkt) | Projektil | 3/4 | 32²+G | 1: idle | Impact-fx vorhanden | OK für Projektil; Spin via Molang möglich statt statisch |
| **Glitched Husk** (`glitch/GlitchedHuskEntity`) | Glitch-Familie | 11/11 | 64²+G+Alt | 5: idle(55kf!), walk(74kf), attack, glitch_blink, death | Familien-Row „corruption drips" (`GlitchedMonster`-Match, B2) | Dichte Keyframes auf wenig Modell: 11 Cubes können den Jitter nicht verkaufen; Shard-Bones (`shard_torso`, `head_shard`, `jaw_shard`) existieren aber ohne Detach-Beat |
| **Glitched Hound** (`glitch/GlitchedHoundEntity`) | Glitch-Familie | 16/16 | 64²+G+Alt | 5: idle, walk, attack(69kf), glitch_blink(62kf), death | Familien-Drips + `glitch_pop` | solide Mitte; glitch_blink könnte Bone-Scale-Pops nutzen (aktuell nur Rotation) |
| **Glitched Tick** (`glitch/GlitchedTickEntity`) | Glitch-Familie | 8/13 | 64²+G+Alt | 5: idle, walk, attack, latch, death | Familien-Drips | latch (Signatur!) nur 22kf/0.5s — das Anklammern liest nicht; sonst rollengerecht klein |
| **Glitched Wanderer** (`backrooms/GlitchedWandererEntity`) | Backrooms-Stalker | 11/11 | 64²+G+Alt | **7**: idle, walk, attack, glitch_blink, death, sprint, notice | `wanderer_static_shroud` Loop (B2) | notice/sprint-Paar ist gut (Horror-Beat); 11 Cubes + Painter liegt NICHT in `geckolib_gen/mobs/` (siehe §7-Falle F-11) |
| **Deckhand** (`DeckhandEntity`, Limbo-NPC) | Limbo-Crew | 16/15 | 64²+G | **7**: row, idle_sag, walk, rise, attack, death, tilt | `deckhand_soul_flame`/`_soul_flare` (B2); Ruder = `limbo.OarAnimator`-Displays (F-003) | row/tilt einzigartig gut; rise (aus dem Deck aufstehen) ohne Planken-Staub-Cue, Gesicht ohne glow-Differenzierung — die ersten NPCs die JEDER Spieler sieht |
| **Wizard Orin** (`wizard/WizardOrinEntity`) | Händler-NPC | 18/18 | 64²+G | **7**: idle(64kf), walk, greet, trade, star_call(67kf), hurt, death | **KEINE .fx** (star_call hat keinen Photon-Partner!) | star_call schreit nach Stern-FX-Pairing; Bart/Robe statisch; kein eigener Sound (Villager-Recycling) |
| **Drift Lantern** (`ambient/DriftLanternEntity`, P6-Pilot) | Ambient | 9/10 | 64²+G | 5: idle, walk, attack, flicker, death | keine (bewusst? Ambient) | Pilot-Qualität ok; flicker könnte Photon-Glow-Puls-Cue spiegeln; Kette/Aufhängung fehlt im Modell |
| **Soul Wisp** (`ferryman/finale/SoulWispEntity`) | Finale-Schwarm | **7/6** | **32²**+G | 4: idle, walk, attack, **death(1 Bone/6kf!)** | Arena-/Portal-FX sind Area-Cues, kein Entity-FX | Schwächstes Kampf-Mob-Modell: 6 Cubes, 32²-Canvas, death = Nicht-Ereignis — im FINALE, wo alle hinschauen |
| **Portal Gate** (`ferryman/finale/PortalGateEntity`) | Tag-14-Setpiece | 8/11 | **512²**+G | **2**: idle(4kf!), unlock(6s/39kf) | Portal-FX über `FerrymanFinaleFxRows` (**W13-A3**) | 512²-Canvas auf 11 Cubes = Texel-Verschwendung; idle mit 4 Keyframes für DAS Endgame-Objekt; unlock ok aber ohne Keystone-Shimmer-Bones |
| **Portal Key** (`ferryman/finale/PortalKeyEntity`) | Finale-Schlüssel | 5/8 | 64²+G | 2: idle, fly(5kf) | — | §5 des FX-Zensus nennt UNLOCK als schwächsten Finale-Beat — der Schlüssel selbst hat keine Dreh-/Einrast-Animation (nur idle+fly) |
| **Glitch Emitter** (`woah/mansiondome/DomeEmitterEntity`, Renderer im woah-Paket) | Dome-Kern | 18/16 | 128²+G | 3: idle, hit, death | Dome-FX über Woah-Rows (**W13-C3-Nähe**) | hit(10kf) minimal; idle könnte Molang-Dauerrotation der Ringe nutzen; Painter liegt in `tools/woahdome/` (Falle F-11) |

**Statuen-Frage (worldgen):** Die Tyrant-Statue (`entity/boss/fog/TyrantStatue`) ist
KEIN Geo-Modell, sondern eine **BlockDisplay-Assemblage** (polished-blackstone-Palette,
Awaken über 60t) — Modell-Teams fassen sie nicht als Geo an; der Scythe-Handoff-Fix ist
ein Display+Geo-Koordinationspunkt (Paket MA1, §5).

## §2 Mob-Zensus — Code-Modell-Linie (Vanilla-Renderer, KEIN Geo/Anim-JSON)

Alle sechs registrieren Layer + Renderer im SHARED `client/entity/EclipseEntityRenderers.java`
(Konflikt-Gesetz §5-G2). Animation = prozedural in `setupAnim` (Code), d.h. kein
Keyframe-Polish möglich ohne Konversion oder Code-Arbeit.

| Mob | Rolle | Modell (Zeilen) | Textur | FX-Anbindung | Ist-Bewertung |
|---|---|---|---|---|---|
| **Herald** (`boss/HeraldEntity`) | **BOSS Tag 4** | `HeraldModel` (324 Z., Code) | `herald.png`, **kein Glowmask** | `herald_summon_pillar`, `glyph_swirl`, `shard_trail`, `roar_shockwave` (**W13-A4**); 4 eigene Sound-Events + Musik | **Schwächster Boss-Body im Spiel**: kein Keyframe-Sheet, kein Glowmask, kein scripted death; §5 des FX-Zensus fordert Silhouetten-Reveal im Pillar — ohne Geo-Modell gibt es nichts zu revealen |
| **Ferryman** (`boss/FerrymanEntity`) | BOSS Tag 14 | `FerrymanModel` (370 Z., Code) | `ferryman.png`, kein Glowmask | Kneel-Corona, Laternen-Schwarm, Ruder-Riss (**W13-A4/A3**); Bell+Ambient-Sounds | Dichtestes Code-Modell (Boot/Ruder/Laterne), aber: Ruder-Sweep und Kneel sind FX-getimt ohne Bone-Anim darunter; death/Finale-Handoff ohne Modell-Beat |
| **Gazer** (`GazerEntity`) | Psycho-Ambient | `GazerModel` (191 Z.) | `gazer.png` | `gazer_gaze_beam` (B2 hat den Quer-zum-Blick-Bug gefixt!) + `gazer_tether_snap`; 1 Whisper-Sound | Auge/Iris nicht separat animierbar (Code-Rotation only); Blick-Thema verdient Iris-Dilatation + Lid-Bones = Konversions-Kandidat |
| **Umbral Stalker** (`UmbralStalkerEntity`) | Nacht-Jäger | `UmbralStalkerModel` (158 Z.) | `umbral_stalker.png` | keine dedizierte .fx | Dünnster Kampf-Mob der Code-Linie: kein Anim-Sheet, kein FX, kein Sound — dabei DER Nacht-Terror |
| **Sunmote** (`SunmoteEntity`) | Freundlicher Ambient | `SunmoteModel` (85 Z.) | `sunmote.png` | keine | Kleinstes Code-Modell; als „Licht-Wesen" ohne Glow-Layer ironisch dunkel |
| **The Other** (`TheOtherEntity`) | Doppelgänger | **Vanilla `HumanoidModel`** + Fragment-Cubes | `the_other.png` (Player-Skin-UV) | `other_dread_aura` | **BEWUSST Vanilla-Humanoid** — muss Spieler-Silhouette exakt matchen (Anonymitäts-/Mimikry-Design, Kommentar in `EclipseEntityRenderers`). NICHT konvertieren (Gesetz §5-G7); Polish nur an Fragment-Cubes/Aura |

**Player-Modell-Wiederverwendung (bewusst, nicht konvertieren):** `LogoutGhostEntity`
(`GhostPlayerRenderer`, an `ghost_grade`-Veil gekoppelt), `EchoGhost`/`EchoGhostWolf`
(Vergangenheits-Echos, eigene Texturen `echo_ghost*.png`), `MemoryOrb` (flacher
`EntityRenderer`). `HeraldShardProjectile` rendert als skaliertes Item-Sprite
(`ThrownItemRenderer`, umbral-shard-Textur) — bewusst billig, ok.

---

## §3 Item-Zensus

### 3.1 GeckoLib-3D-Items (6) — die Hero-Lane

Muster: `GeoItem` + `models/item/<id>.json` = `builtin/entity` (nur display-Transforms) +
BEWLR via `IClientItemExtensions.getCustomRenderer()` (lazy, in `WandClientExtensions` /
`ItemsAClientExtensions` / `ItemsBClientExtensions`). Assets: `geo/item/<id>.geo.json` +
`animations/item/<id>.animation.json` + Texturen unter `textures/item/<unterordner>/`
(mit Glowmask; Painter in `scripts/geckolib_gen/items/`).

| Item | Registrierung | B/C | Anims | Ist-Bewertung |
|---|---|---|---|---|
| **Eclipse Wand** (`wand/WandItems.ECLIPSE_WAND`, `EclipseWandItem`) | `wand/` | **36/26** (inkl. `p_riss/glut/stern_s1..3`-Pfad-Bones) | 5: idle(8s), use, levelup, awaken, stall | Ausgebautestes Item: 4 Textur-Sets (base/glut/riss/stern) + Pfad-Segment-Bones. Schwäche: EIN `use` für alle drei Pfade (kein Pfad-Charakter im Handling), levelup/awaken animieren nur 2 Bones |
| **Arm Artifact** (`EclipseItems.ARM_ARTIFACT`) | ITEMS-A | 6/10 | 2: idle, open | open(22kf) ok; idle 9kf/6s = träge für DAS Menü-Artefakt; kein Puls bei neuen Einträgen |
| **Heart Extractor** (`EclipseItems.HEART_EXTRACTOR`) | ITEMS-A | 6/8 | **4**: idle, channel, extract, refuse | Bestes Anim-Set der Items (channel-Loop + refuse!); idle nur 2kf; extract könnte Herzkammer-Bone-Snap vertragen |
| **Revive Sigil** (`EclipseItems.REVIVE_SIGIL`) | ITEMS-B | **3/5** | 2: idle(3kf!), ritual | **Das emotionalste Item (Wiederbelebung) hat das dünnste Modell**: 3 Bones, idle praktisch statisch, ritual 11kf ohne Bruch-/Verbrauchs-Beat |
| **Herald's Lure** (`EclipseItems.HERALDS_LURE`) | ITEMS-B | 7/10 | 2: idle(4kf/4.8s), offering | offering(23kf) ok; idle statisch trotz Beschwörungs-Rolle; kein Glow-Crescendo Richtung Boss-Spawn |
| **Storm Heart** (`EclipseItems.STORM_HEART`) | ITEMS-B | 10/18 | **1**: idle | **Nur EINE Animation** trotz 10 Bones und Boss-Reliquien-Status — kein Herzschlag-Puls, kein use/socket/awaken-Beat |

### 3.2 Sprite-Items (2D-Pixel-Art)

Registriert in `registry/EclipseItems` (+ Ausreißer): `heart_fragment`, `glitch_shard`,
`umbral_shard` (`UmbralShardItem`), `vitae_shard`, `umbral_pick`, `umbral_blade`,
`compass_of_watcher` (**32 Frame-Modelle/Texturen** `_00.._31`, `WatcherCompassItem`),
`grave_dowser` (ebenfalls 32 Frames), `herald_core`, `ferryman_toll`, `fog_core`,
`fog_cloak_trim`, `wizard_catalyst` (`wizard/WizardEntities`), `chrono_core`
(`woah/chronostasis`), `memory_mote`, `echo_blossom` (`woah/echogrove`), `display_wand`
(`devtools/`, Dev-only). BlockItems: `grave`, `altar`, `respawn_door` (GeckoLib-Block-
Modelle!), + `WorldgenBlocks`/`PaleGardenBlocks`-BlockItems + **188 `classic_*`**
(`classicblocks/ClassicBlockList.ENTRIES`, Xbox-Ära-Feature).

**Bewertungs-GESETZ (AGENTS.md):** die kleinen Pixel-Icons sind **finale, generierte
Kunst — KEINE Platzhalter**. Item-Teams dürfen 2D-Icons NICHT „verbessern". Legitime
3D-Kandidaten sind nur Items, die prominent GEHALTEN/BENUTZT werden und heute flach sind:
`umbral_blade`/`umbral_pick` (Held-in-Hand-Dauerpräsenz) und `ferryman_toll` (Finale-
Übergabe-Moment) — als Vorschlag, nicht als Pflicht (§5 Welle M-D, optional-Paket).

**Falle:** `models/item/fog_tendril.json` ist KEIN Item — es ist die **Photon-MeshData-
Emissionsgeometrie** für `tyrant_fog_arms` (Kommentar im JSON; geladen via
`ModelFactory.getUnBakedModel`). Gehört FX-seitig W13-A5. Nie „aufräumen".

---

## §4 Modell-Datei-Zensus — die schwächsten Modelle

Ranking nach (Bones × Keyframe-Dichte) ÷ Sichtbarkeit. Vollständige Zahlen in §1/§3.

| Rang | Modell | Befund | Sichtbarkeit |
|---|---|---|---|
| 1 | `portal_gate.geo.json` | 11 Cubes auf 512²-Canvas, idle = **4 Keyframes** | Tag-14-Finale — maximal |
| 2 | `soul_wisp.geo.json` | 6 Cubes, 32², death = 1 Bone/6 kf | Finale-Schwarm — hoch |
| 3 | `revive_sigil.geo.json` (Item) | 3 Bones/5 Cubes, idle 3 kf | jeder Revive — hoch |
| 4 | `storm_heart.geo.json` (Item) | 10 Bones aber **1 Animation** | Boss-Drop — hoch |
| 5 | `portal_key.geo.json` | 5 Bones, fly = 5 kf, kein unlock-Beat | Finale-UNLOCK — hoch |
| 6 | `eclipse_cultist.geo.json` | 11 Cubes für den häufigsten Gegner | Dungeon — hoch |
| 7 | `glitched_husk.geo.json` | 11 Cubes tragen 55–74-kf-Anims nicht | Glitch-Zonen — mittel |
| 8 | `shadow_bolt.geo.json` | 1 Anim (Projektil — bewusst klein) | mittel |
| 9 | `glitch_emitter.geo.json` | hit = 10 kf, 3 Anims | Dome-Event — mittel |
| 10 | `drift_lantern.geo.json` | Pilot-Standard, ohne Aufhängung | Ambient — niedrig |

Nicht im Ranking, weil KEINE Geo-Dateien existieren (= eigentliche Spitzenreiter der
Schwäche): **Herald, Ferryman, Gazer, Umbral Stalker, Sunmote** (Code-Modelle, §2).

Block-Geos zum Vergleich (gesund): `altar` 15/30 auf 256×128 mit 5 Anims (48-kf-idle),
`respawn_door` 6/14 mit 4 Anims — beide von W13-A7/AltarModelRenderer-Umfeld tangiert,
siehe Konflikt-Gesetz.

---

## §5 Priorisierte Team-Wellen (konfliktfrei, Format nach FX-Zensus §7)

### Konflikt-Gesetz (VOR der Team-Aufteilung lesen)

1. **Konflikt-Einheit „Mob"** = Entity-Klasse(n) + Renderer-Klasse + `geo/entity/<id>.geo.json`
   + `animations/entity/<id>.animation.json` + `textures/entity/<id>*.png` + Painter-Skript
   (`scripts/geckolib_gen/mobs/<id>.py`) + `docs/uv/<id>.md`. Zwei Teams NIE am selben Mob.
   Familien, die sich Registrar/Renderer-Klassen teilen, sind EIN Team
   (Glitch-Trio `GlitchEntities`/`GlitchRenderers`, Finale-Trio `FinaleEntities`/`FinaleRenderers`).
2. **`EclipseEntityRenderers.java` ist SHARED** (6 Code-Mobs + herald_shard). Konversions-
   Teams registrieren ihren neuen Geo-Renderer in einer EIGENEN
   `@EventBusSubscriber(Dist.CLIENT)`-Klasse (Muster `AmbientRenderers` inkl.
   `isBound()`-Guard) und liefern die Lösch-Zeile für die alte Registrierung als
   Patch-Snippet an den **Integrator** (gleiches Muster wie FxCues/langdrop).
3. **FROZEN und für ALLE tabu:** `EclipseGeoMob`/`EclipseGeoMonster`/`EclipseGeoAnimations`/
   `EclipseGeoRenderer` (Basis-Contract), `scripts/geckolib_gen/validate_geo.py` +
   `paint_lib.py`. Änderungswünsche → Integrator. `registerControllers` ist final:
   genau ZWEI Controller (`base`+`action`) — keine dritten Controller erfinden.
4. **FX-Dateien gehören den Welle-13-Teams** (`.fx`/Generator/Registrar-Besitz aus
   FX_CENSUS §7 gilt weiter): A5 = `fx/boss/tyrant_*`+`BossPhotonFxRows`, A4 =
   Herald/Warden/Ferry-Boss-fx, A3 = Ferryman-Finale-fx, B2 = `mobs_fx.py`/`scare_fx.py`/
   `MobPhotonFxRows`, F-096 = Sturm. Mob-Teams liefern der FX-Seite **Bone-/Locator-Namen
   und Anim-Timings** (Koordinations-Snippet im Team-Report), fassen aber NIE deren
   Generatoren/Rows an. Neue Body-FX-Wünsche (Colossus, Orin) = Cue-Snippet + Wunsch-Spec
   an den B2-Owner bzw. neue eigene Registrar-Klasse nach PH-CORE-Contract.
5. **Statue/Displays:** `TyrantStatue` (BlockDisplays) gehört zum Paket MA1 (Handoff-Fix),
   aber NUR die Java-Seite — der `statue_idle`-fx bleibt A5.
6. **Shared-JSON-Gesetze:** Lang nur via `docs/plans_v3/langdrop/<PKG>.json`;
   **`sounds.json` analog behandeln**: Teams liefern `docs/plans_v3/sounddrop/<PKG>.json`
   (Event-Keys + OGG-Pfade), der Integrator merged — nie direkt editieren. Vanilla-Sound-
   Layering IM eigenen Entity-Code ist dagegen frei (Team-Besitz).
7. **Nicht konvertieren (Design-Gesetz):** The Other (Spieler-Silhouetten-Mimikry),
   LogoutGhost/EchoGhost/EchoGhostWolf (Player-Modell ist der Punkt), HeraldShard
   (Item-Sprite bewusst). Polish dort nur additiv (Fragmente, Layer, FX-Wünsche).
8. **Texturen nur über Painter-Driver regenerieren** (deterministisch, Seed-fixiert,
   ein Lauf schreibt Albedo+Glowmask — `AutoGlowingTexture` hard-failt bei
   Canvas-Mismatch). Hand-gemalte PNGs sind verboten; AI-Art ersetzt später an
   identischen Pfaden/Größen.

### Welle M-A — Bosse + Finale (höchste Sichtbarkeit, 6 Pakete, alle parallel)

| Team | Paket | Datei-Besitz (exklusiv) | Konkrete Upgrade-Ideen |
|---|---|---|---|
| **MA1** | **Fog Tyrant** | `entity/boss/fog/*` (inkl. `TyrantStatue`-Java), `client/entity/fogboss/*`, `geo/animations/textures fog_tyrant*`, `mobs/fog_tyrant.py`, `docs/uv/fog_tyrant.md` | (a) **Scythe/Lance-Trail-Locator-Bones** (`trail_lance_l/r` an den Spitzen) für A5s Photon-Entity-Lanes; (b) Mantel: `cloak_back/mid` → 4-Segment-Kette mit Nachschwing-Keyframes (catmullrom); (c) **death (3.5s) auf die A5-Implosionskette timen** (Kollaps hält Silhouette bis zum Fresnel-Snap, Timing-Tabelle an A5); (d) Scythe-Detach beim Statue-Handoff fixen: Statue-Display-Vanish 2t nach Step-Out-Fog (F-081..087); (e) storm_step_out/in mit `robe_tatter_*`-Flare |
| **MA2** | **Rift Warden** | `entity/boss/rift/*`, `client/entity/rift/*`, Assets `rift_warden*`, `mobs/rift_warden.py` | blink_out/in mit Bone-Scale-Warp (Glitch-Stretch, ±X-Squash vor dem Vanish); idle: Riss-Platten „atmen" via Molang-Sinus; volley: Schulter-Recoil pro Salve, getimt auf `warden_eye_laser`-Raycast-Fix (A4 liefert die Beam-Zeit) |
| **MA3** | **Herald-GeckoLib-Konversion** (Flaggschiff) | `entity/boss/HeraldEntity`, `client/entity/Herald{Model,Renderer}` (Löschung via Snippet), NEU: `geo/animations/textures herald*`, `mobs/herald.py`, eigene Renderer-Registrar-Klasse | Neues Geo ~24 Bones (Hörner/Schulter-Schilde/Glyphen-Orbit-Locators/`glow_*`-Adern); Sheet: idle, walk, attack, summon_rise (auf die 9.5s-Pillar-Sequenz), roar (auf `roar_shockwave`), shard_volley, death; **Silhouetten-Reveal möglich machen** (§5-FX-Zensus: Boss kondensiert IM Pillar — braucht das neue Modell als Photon-Model-Renderer-Quelle); Glowmask (bisher keiner!) |
| **MA4** | **Ferryman-GeckoLib-Konversion** | `entity/boss/FerrymanEntity`, `client/entity/Ferryman{Model,Renderer}` (Snippet), NEU: Assets `ferryman*`, `mobs/ferryman.py`, eigene Registrar-Klasse | Geo mit **Ruder-Bone-Kette + Laternen-Locator** (Anker für `ferry_lantern_swarm`/`ferry_oar_tear` — Timings an A4/A3); Anims: idle_row, kneel (auf `CUE_FERRY_KNEEL_CORONA`), oar_sweep (auf `CUE_FERRY_OAR_SWEEP`), harvest, death/Finale-Handoff; Boot als eigene Bone-Gruppe mit Wellengang-Molang |
| **MA5** | **Finale-Props-Trio** (portal_gate + portal_key + soul_wisp) | `ferryman/finale/{PortalGate,PortalKey,SoulWisp}Entity`, `client/entity/finale/*`, Assets + `mobs/{portal_gate,portal_key,soul_wisp}.py` | Gate: idle → Atmungs-Bogen + Keystone-Shimmer-Bones (512²-Canvas endlich nutzen: Runen-Detailtextur); **Key: `unlock_turn`-Anim mit 3 Bart-Glyphen-Klick-Beats** (löst die schwächste Finale-Stelle aus FX-Zensus §5, Timing-Snippet an A3); Wisp: +Trail-Bone, +`panic_scatter`-Anim, death → 3-Bone-Zerfall statt 1-Bone-Fade |
| **MA6** | **Fog Colossus + Storm Hound** (Fog-Eliten) | `entity/fog/{FogColossus,StormHound}Entity` + `ChargedLungeGoal`, `client/entity/fog/{FogColossus,StormHound}Renderer`, Assets, `mobs/{fog_colossus,storm_hound}.py` | Colossus: walk mit Gewichtsverlagerung (Masse-Gesetz), roar +Kiefer/Brust-Bones, **Body-FX-Wunsch-Spec an B2** (einziger Elite ohne .fx — Vorschlag: `colossus_slam_dust` + Nebelkragen-Loop); Hound: separater sprint-Zyklus, howl mit Schulterblatt-Anhebung, lunge-Timing-Tabelle an B2 (`hound_dash_trail` `inheritVelocity`-Nutzung) |

### Welle M-B — Limbo/NPC/häufige Gegner (6 Pakete)

| Team | Paket | Datei-Besitz | Upgrade-Ideen |
|---|---|---|---|
| **MB1** | Deckhand (Limbo) | `entity/DeckhandEntity`, `client/entity/DeckhandRenderer`, `limbo/OarAnimator` (Java), Assets, `mobs/deckhand.py` | rise-Anim mit Planken-Staub-Cue-Wunsch (Snippet an B2, `deckhand_soul_flare` existiert schon), Gesichts-Glow-Differenzierung im Glowmask-Painter, row-Sync mit OarAnimator-Displays verifizieren (F-003-Fix nicht regressen) |
| **MB2** | Wizard Orin | `entity/wizard/*` (inkl. `wizard_catalyst`-Item-Zeile), `client/entity/wizard/*`, Assets, `mobs/wizard_orin.py` | star_call bekommt Photon-Partner-WUNSCH (neue eigene Registrar-Klasse `WizardFxRows` nach PH-CORE, Cue-Snippet an Integrator — Stern-Fall aus `gen_player_fx.py`-Familie NICHT anfassen, eigenes Child-fx spec'en); Bart/Robe-Sway via Molang; trade-Anim an Menü-Open koppeln |
| **MB3** | Eclipse Cultist + Shadow Bolt (Dungeon-Familie) | `entity/dungeon/*`, `client/entity/dungeon/*`, Assets, `mobs/{eclipse_cultist,shadow_bolt}.py` | Cultist: Robe 1→4 Cubes + Ärmel-Flare im cast, Hood-`glow_`-Bone; Bolt: Molang-Dauerspin + Taumel Richtung Ziel; Body-FX-Wunsch (Hood-Glut-Loop) an B2 |
| **MB4** | Glitch-Trio (husk+hound+tick — EIN Team, shared Registrar!) | `entity/glitch/*`, `client/entity/glitch/*`, Assets aller drei (+Alt-Skins), `mobs/glitched_{husk,hound,tick}.py`, `glitch_lib.py` | Shard-Detach-Beats: `shard_torso`/`head_shard`/`jaw_shard` bekommen glitch_blink-Scale-Pops + 1-Frame-Versatz-Keyframes; tick-latch auf 0.8s strecken mit Bein-Klammer-Kette; Familien-Kohärenz-Pass (alle drei nutzen dieselbe Jitter-Frequenz) |
| **MB5** | Glitched Wanderer (Backrooms) | `backrooms/GlitchedWandererEntity`, `client/backrooms/*`, Assets, `scripts/skin_gen/backrooms_wanderer.py` | notice→sprint-Kette ist der Horror-Beat: notice mit Kopf-Snap (0.1s) + Halte-Frame; Painter-Skript nach `geckolib_gen/mobs/` umziehen (Konsistenz, Integrator-Absprache); Shroud-Loop-Bone-Anker für B2s `wanderer_static_shroud` |
| **MB6** | Pale Sentinel + Fog Revenant | `entity/pale/*` + `entity/fog/FogRevenantEntity`, zugehörige Renderer, Assets, `mobs/{pale_sentinel,fog_revenant}.py` | Sentinel: **freeze-ÜBERGANG** (0.3s Erstarrungs-Anim statt Loop-Schnitt) + Petal-Locator-Bones fürs B2-Orbit-Pairing; Revenant: idle 20→50kf (Saum-Wellen, catmullrom), Robe-Säume als 2-Segment-Ketten damit die fog_ribbons „ziehen" können |

### Welle M-C — Code-Modell-Konversionen + Ambient (5 Pakete)

| Team | Paket | Datei-Besitz | Upgrade-Ideen |
|---|---|---|---|
| MC1 | Gazer-Konversion | `entity/GazerEntity`, `client/entity/Gazer{Model,Renderer}` (Snippet an Integrator), NEU Assets+Painter, eigene Registrar-Klasse | Geo mit Iris-/Lid-Bones (Blick-Thema!): idle-Iris-Drift, `gaze_lock`-Anim (Pupille dilatiert) getimt auf `gazer_gaze_beam` (B2-Fix beachten: Beam läuft jetzt lokal +X), `tether_snap`-Zucken |
| MC2 | Umbral-Stalker-Konversion | analog MC1 für `umbral_stalker` | Geo mit Schulter-Buckel + Kriech-Sprint-Doppelgang; `stalk_low`-Pose (Nacht-Terror liest über Silhouette); FX-Wunsch-Spec (Schatten-Schlieren) an B2 |
| MC3 | Sunmote + Drift Lantern (Ambient-Paar) | `entity/SunmoteEntity` + `client/entity/Sunmote*` (Konversion, Snippet), `entity/ambient/*` + Assets beider, Painter | Sunmote: Mini-Geo (8 Bones, Strahlen-Kranz + `glow_core`) — als „Licht-Wesen" ENDLICH Glowmask; Lantern: Aufhängungs-Kette + flicker-Anim an Photon-Glow-Puls-Wunsch koppeln; `isMoving()`-Falle beachten (beide sind Drifter — eigenes Positions-Delta im `handleBaseState`, Drift-Lantern-Muster) |
| MC4 | The Other + Ghost/Echo-Familie (NUR Polish, Gesetz §5-G7) | `entity/TheOtherEntity`, `client/entity/TheOther*`, `ghosts/*`, `client/entity/ghost/*`, `woah/echogrove`-Renderer | Fragment-Cubes bei Aggro: Orbital-Stagger statt Gleichtakt; Ghost-Reveal-Layer-Feinschliff; KEINE Geometrie-Änderung an der Humanoid-Silhouette |
| MC5 | Glitch Emitter (Dome) | `woah/mansiondome/*` (Entity+Renderer), Assets, `tools/woahdome/gen_glitch_emitter_textures.py` | Ring-Dauerrotation via Molang (`query.anim_time`), hit 10→30kf mit Ring-Desync, death-Kollaps auf DomeShatter-Displays getimt (C3-Absprache) |

### Welle M-D — Items (4 Pakete)

| Team | Paket | Datei-Besitz | Upgrade-Ideen |
|---|---|---|---|
| MD1 | Eclipse Wand | `wand/`-Java (ohne FX-Rows!), `geo/animations item eclipse_wand*`, `textures/item/wand/*`, `items/eclipse_wand.py`, `client/wand/WandClientExtensions` | **Pro-Pfad-use-Varianten** (`use_glut` Peitschhieb / `use_riss` Riss-Zug / `use_stern` Stich nach oben — `p_*`-Bones existieren schon!); levelup/awaken von 2 auf 8+ Bones erweitern; stall mit sichtbarem „Verschlucken". FX bleibt W13-A1/A2! |
| MD2 | ITEMS-A-Paar (arm_artifact + heart_extractor) | Assets+Painter beider, `client/item/ItemsAClientExtensions` + Renderer-Klassen | Artifact: idle-Puls bei ungelesenen Einträgen (Bone-Scale 1.0→1.04), open mit Seiten-Fächer; Extractor: extract mit Kammer-Snap-Bone + refuse-Kopfschütteln verstärken |
| MD3 | ITEMS-B-Trio (revive_sigil + heralds_lure + storm_heart) | Assets+Painter aller drei, `client/item/ItemsBClientExtensions` + Renderer | Sigil: 3→7 Bones (Glyphen-Ring), `ritual_charge`-Loop + `shatter`-Verbrauchs-Anim (auf ReviveRitual-Ticks, Cue-Wunsch an B6-Owner); Lure: Glow-Crescendo-idle (Molang-Sinus auf `glow_*`), offering-Wurf-Vorbereitung; **Storm Heart: heartbeat-idle (10 Bones nutzen!), `socket`/`awaken`-Anims** — mit F-096 abstimmen (Sturm-Thema), FX-Seite tabu |
| MD4 | Block-Geo-Paar + 3D-Kandidaten (OPTIONAL) | `geo/animations block {altar,respawn_door}*`, `client/altarmodel/*`, `limbo/door/*`-Renderer; Vorschlags-Spec für `umbral_blade`/`umbral_pick`/`ferryman_toll`-3D | Altar NUR nach A7-Absprache (Mesh-Emission `altar_corona_idle` hängt am Monument!); Tür: locked_shudder-Verstärkung; 3D-Sprite-Konversionen nur als Spec ans nächste Planning (AGENTS.md-Gesetz: Icons sind finale Kunst — Konversion ergänzt, ersetzt nicht) |

**Reihenfolge:** M-A zuerst (MA3/MA4-Konversionen sind die größten Brocken und
blockieren nichts anderes — sofort starten); M-B parallel dazu voll fahrbar (disjunkte
Dateien); M-C nach M-A (Integrator-Snippets für `EclipseEntityRenderers` bündeln — G2);
M-D jederzeit parallel (Items berühren keine Entity-Dateien). MD3 darf wegen der
Schwäche-Ranks (§4) in die erste Startgruppe vorgezogen werden.

**Eval-Gate (F-099, wie FX-Zensus):** Nach jeder Welle Sol-Eval; „zu simpel"-Befunde
erzeugen Nach-Polish-Runden im selben Datei-Besitz.

---

## §6 Blockbench/GeckoLib-Workflow OHNE GUI (für alle Executor-Teams)

Vollständiger FROZEN-Contract: `docs/plans_v3/handoff/P6_geckolib_conventions.md` —
hier das Destillat + Zensus-Ergänzungen. GeckoLib **4.9.2** (jar-in-jar, läuft
Client+Server), Pfade sind die OLD-Style-GeckoLib-4-Pfade, NICHT das
`geckolib/models`-Layout der GeckoLib-5-Wiki!

### 6.1 Datei-Format-Regeln (valide per Hand editierbar)

**`.geo.json`** (`format_version "1.12.0"`):
```json
{ "format_version": "1.12.0",
  "minecraft:geometry": [ {
    "description": { "identifier": "geometry.<id>", "texture_width": 64, "texture_height": 64 },
    "bones": [
      { "name": "root", "pivot": [0,0,0] },
      { "name": "body", "parent": "root", "pivot": [0,10,0], "rotation": [0,0,0],
        "cubes": [ { "origin": [-4,6,-2], "size": [8,8,4], "uv": [0,16], "inflate": 0.25 } ] }
    ] } ] }
```
- Einheiten: 16 px = 1 Block; `origin` = Ecke (Minimum), `pivot` = Drehpunkt in Weltachsen.
- UV: Box-UV `uv:[u,v]` ODER Per-Face-Map; Canvas-Größe MUSS zur Textur passen
  (64² Standard; 128² nur `fog_colossus`/`rift_warden`/`fog_tyrant`/`respawn_door`
  — neue Ausnahmen mit dem Integrator klären).
- **Bone-Hierarchie-Gesetze (FROZEN):** Root heißt `root`; Head-Tracking-Bone MUSS exakt
  `head` heißen (GeckoLib targetet genau diesen Namen, nur wenn der Renderer mit
  `turnsHead=true` gebaut ist); Angriffs-Gliedmaßen `arm_left/arm_right` bzw.
  `leg_fl/fr/bl/br`; Emissiv-Geometrie unter `glow_`-Präfix-Bones (der Painter nimmt
  die automatisch in die Glowmask).
- **Render-Reihenfolge = Datei-Reihenfolge** (Eltern vor Kindern): glühender Kern INNEN
  vor transluzenter Schale AUSSEN listen (`drift_lantern.geo.json`: `glow_flame` vor
  `cage`), sonst blendet die Schale falsch.

**`.animation.json`** (`format_version "1.8.0"`):
```json
{ "format_version": "1.8.0",
  "animations": {
    "animation.<id>.<name>": {
      "loop": true,                       // true | false | "hold_on_last_frame"
      "animation_length": 2.0,           // Sekunden
      "bones": { "<bone>": {
        "rotation": {
          "0.0": [0,0,0],
          "0.5": { "post": [0,-25,0], "lerp_mode": "catmullrom" },
          "2.0": [0,0,0] },
        "position": { "0.0": [0,0,0] },   // Model-Pixel
        "scale": "math.sin(query.anim_time * 180) * 0.05 + 1.0"  // Molang erlaubt!
      } } } } }
```
- Rotation in GRAD, Position in Model-Pixeln, Keys sind Sekunden-Strings.
- Interpolation: Standard linear; `{"post": [...], "lerp_mode": "catmullrom"}` für
  weiche Kurven (Mantel/Organik). Statische Kanäle als nacktes Array.
- **Molang** überall: `query.anim_time` = SEKUNDEN seit Anim-Start, `math.sin` nimmt
  GRAD — `math.sin(query.anim_time * 120) * 6` loopt nahtlos über 3 s. Der billigste Weg
  zu „lebendig" ohne Keyframe-Flut (Dauerrotationen, Atmung, Flackern).
- Anim-Id-Schema PFLICHT: `animation.<geoId>.<name>` — `geoId()` der Entity-Klasse keyt
  Assets UND Anim-Ids. Mindest-Set pro Mob: `idle`, `walk`, `attack`, 1 Special, `death`.

### 6.2 Wie das Projekt lädt (verifiziert an `EclipseGeoRenderer`/`EclipseGeoMonster`)

- `EclipseGeoRenderer` wrappt `DefaultedEntityGeoModel<>(ResourceLocation("eclipse", geoId), turnsHead)`
  → EIN String löst das Asset-Tripel auf. Items analog: `GeoItem` + `builtin/entity`-
  Item-Modell (nur display-Transforms) + BEWLR über `IClientItemExtensions` (lazy!),
  Muster `ItemsAClientExtensions`.
- Controller-Contract (final!): `base` (idle/walk, Blend default 4t, via
  `handleBaseState` überschreibbar) + `action` (Transition 0, NUR `triggerableAnim`-
  One-Shots aus `registerActionTriggers`). Kampf-Code feuert serverseitig
  `this.triggerAction("<name>")` — GeckoLib synct über den eigenen Channel, KEINE
  Payloads bauen.
- Death-Konvention (3 Teile, sonst Vanilla-Umkipper): `death` aus `die()` triggern
  (Basis-Default hält den letzten Frame), `tickDeath()` mit Sheet-Länge überschreiben
  (Ende: `broadcastEntityEvent(POOF)` + `remove(KILLED)`), Renderer `withUprightDeath()`.
- Bekannte Laufzeit-Fallen: `state.isMoving()` triggert bei setPos-Drifter NIE (eigenes
  Positions-Delta lesen — Drift-Lantern-Muster); Partial-Alpha-Albedo braucht
  `withTranslucency()`; `AutoGlowingTexture` hard-failt bei Glowmask≠Albedo-Canvas.

### 6.3 Texturen — NUR über den Painter regenerieren

Pro Mob ein deterministischer Pillow-Driver `scripts/geckolib_gen/mobs/<id>.py`
(Items: `items/<id>.py`; Seed fixiert, ein Lauf schreibt `<id>.png` UND
`<id>_glowmask.png`). Materialien: `flat/weave/wood/metal/glass/flame/kelp`.
Glowmask-Regeln: nur emissive Pixel, Rest transparent, gleiche Canvas;
Innen-Glow durch transluzente Schale wird depth-rejected — Shine-Through in die
SCHALEN-Glowmask malen (`drift_lantern.py::cage_glow`). Emissive Regionen auch im
Albedo hell halten (Iris dimmt Glow-Layer).

### 6.4 Validierungs-Weg (es gibt KEINE Unit-Tests — AGENTS.md)

1. **Offline-Validator (Pflicht, das ist unser „Loader-Test"):**
   `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` — BEIDE Dateien in einem
   Aufruf (cross-checkt Anim-Bone-Namen gegen die Geo!); druckt Bone-Baum +
   Keyframe-Statistik; 0 Errors Pflicht, Warnings = Judgement.
2. Painter-Driver laufen lassen, beide PNGs eyeballen (8× nearest-neighbor).
3. `./gradlew build` (strict, compilet auch die Entity-/Renderer-Seite).
4. **Client-Sichtprüfung (Assets laden NUR im Client!):** `runClient` → Welt →
   `/summon eclipse:<id> ~2 ~ ~` → Screenshot front/side/¾ + 1 Screenshot pro Anim
   (walk durch Locken, attack durch Getroffenwerden, Special via `triggerAction`-Pfad
   bzw. Debug-Command, death via `/kill`). Missing-Asset-Fehler im Log nennen den
   exakten Pfad. llvmpipe: 20–40 s Wartezeiten, Screenshots statt Video (AGENTS.md).
   Ein `runServer`-Boot validiert Geo-JSONs NICHT (nur Registrierung/Attributes) —
   für Server-Seite reicht `python3 tools/rcon/rcon.py "summon eclipse:<id> ..."` als
   Spawn-Smoke, die Optik braucht den Client.
5. `docs/uv/<id>.md` committen (Art-Brief + Palette + Emissiv-Regionen + Generator-Cmd).
6. Items zusätzlich: `/give @p eclipse:<id>` via RCON + First-/Third-Person +
   GUI-Screenshot (BEWLR rendert ALLE Perspektiven inkl. GUI).

---

## §7 Risiken/Fallen (beim Zensus gefunden — Executor-Teams lesen das ZUERST)

| # | Falle | Konsequenz |
|---|---|---|
| F-1 | `models/item/fog_tendril.json` ist Photon-MeshData (tyrant_fog_arms), KEIN Item | Nie löschen/umbenennen; Besitz W13-A5 |
| F-2 | `EclipseEntityRenderers.java` shared von 6 Code-Mobs + herald_shard | Konversions-Teams: eigene Registrar-Klasse + Lösch-Snippet an Integrator (G2) |
| F-3 | `registerControllers` final, Controller-Namen `base`/`action` frozen | Keine dritten Controller; neue Anims als Triggerables in `registerActionTriggers` |
| F-4 | FX-Dateien/Registrare gehören Welle-13-Teams (A3/A4/A5/B2/F-096) | Mob-Teams liefern Bones/Timings als Snippet, fassen nie `.fx`/Rows an (G4) |
| F-5 | The Other + Ghost/Echo-Familie nutzen BEWUSST Spieler-Geometrie (Anonymitäts-Design) | Nicht konvertieren (G7) |
| F-6 | AGENTS.md: Pixel-Icons + Hero-Art sind FINALE Kunst | Keine 2D-„Verbesserungen"; Mob-Texturen nur via deterministische Painter (G8) |
| F-7 | `AutoGlowingTexture` hard-failt bei Glowmask-Canvas-Mismatch; Herald/Ferryman/Gazer/Stalker/Sunmote haben heute GAR KEINE Glowmask | Painter-Lauf regeneriert immer BEIDE PNGs; Konversionen liefern Glowmask mit |
| F-8 | `sounds.json` + lang-JSONs sind shared; Mob-Sound-Identität fehlt fast überall (nur 9/87 Events) | sounddrop-/langdrop-Snippets an Integrator (G6); Vanilla-Layering im eigenen Entity-Code ist frei; echte OGG-SFX = eigenes Audio-Paket (siehe AUDIT_REVERIFY G-2-Muster) |
| F-9 | `state.isMoving()` triggert bei tick-getriebenen Drifters nie | MC3 (Sunmote/Lantern), Soul Wisp: eigenes Positions-Delta (6.2) |
| F-10 | Tyrant-„Statue" ist BlockDisplay-Assemblage, kein Geo; Scythe-Detach dokumentiert | Handoff-Fix ist Java+Timing (MA1), `statue_idle`-fx bleibt A5 |
| F-11 | Painter-Ausreißer: `backrooms_wanderer.py` liegt in `scripts/skin_gen/`, Glitch-Emitter-Painter in `tools/woahdome/` | Besitz trotzdem exklusiv beim jeweiligen Team; Umzug nur mit Integrator-Absprache |
| F-12 | 512²-Canvas des Portal Gate vs. 11 Cubes | Bei Geo-Ausbau UV-Layout neu planen BEVOR Textur-Painter läuft (Canvas-Größe ändern = Glowmask mit ändern) |
| F-13 | Altar-Geo hängt an W13-A7-Mesh-Emission (`altar_corona_idle` emittiert vom Monument) | MD4 nur nach A7-Absprache; Bone-Umbenennungen brechen die Mesh-Referenz |
| F-14 | Kein Test-Task; `runServer` lädt keine Client-Assets | Der einzige „Loader-Test" ist `validate_geo.py` + `runClient`-Sichtprüfung (6.4) |

---

## §8 Arbeits-Checkliste pro Executor-Team

1. Geo/Anim editieren (6.1-Regeln) → `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>`
   (beide Dateien, 0 Errors).
2. Painter-Driver laufen lassen (nie PNGs hand-malen), beide PNGs eyeballen.
3. `./gradlew build` (strict) — bei Java-Änderungen Pflicht vor jedem Client-Start.
4. `runClient` → `/summon eclipse:<id>` bzw. `/give` → Screenshot-Serie pro Anim
   (llvmpipe: 20–40 s Wartezeit). Bosse/Sequenzen: `/eclipsefx sequence <id> <phase>` bzw.
   RCON-`/dev`-Kommandos (AGENTS.md).
5. FX-Koordination: Bone-/Locator-Namen + Anim-Timing-Tabelle als Snippet in den
   Team-Report; NIE fremde Generatoren/Rows anfassen.
6. Shared-Dateien: langdrop/sounddrop/Registrar-Snippets an den Integrator; frozen
   Basen unangetastet.
7. `docs/uv/<id>.md` aktualisieren/committen; Report unter
   `docs/plans_v3/session_0730/<TEAM>_REPORT.md` (B2-Muster: verifizierte Grundlagen
   zuerst, nichts aus dem Gedächtnis).
