# MC2 — Umbral-Stalker-GeckoLib-Konversion (F-098 Welle M-C)

**Status:** FERTIG — `validate_geo` 2/2 PASS (0 Errors / 0 Warnings), Painter-Rerun
byte-identisch (md5 geprüft), `./gradlew compileJava` grün. Ergebnisse §6,
Integrator-Snippets §7, B2-FX-Wunsch-Spec §8, Selbstkritik + Polish-Pässe §9.

**Datei-Besitz (Zensus §5, Zeile MC2):** `entity/UmbralStalkerEntity`,
`client/entity/UmbralStalker{Model,Renderer}` (Löschung via §7-Snippet), NEU:
`geo/animations/textures umbral_stalker*`, `scripts/geckolib_gen/mobs/umbral_stalker.py`,
`client/entity/stalker/` (eigenes Unterpaket), `docs/uv/umbral_stalker.md`, dieser Report.
**Nicht angefasst:** `EclipseEntityRenderers.java` (SHARED, G2), `EclipseEntities.java`,
FROZEN-Basen, `validate_geo.py`/`paint_lib.py`, `tools/photon/**`, `assets/eclipse/fx/**`,
Lang-Dateien, `client/entity/gazer/**` (MC1).

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

- **Ist-Zustand (Zensus §2, Code-Modell-Linie):** `UmbralStalkerEntity extends Monster`
  (Wolf-Kit + Morgengrauen-Flucht + Loot), `UmbralStalkerModel` (11-Cube
  `HierarchicalModel`: Body 8×7×14, Head 7×6×8, 2 Kiefer-Shards, 4 Beine 3×8×3, 3
  Spine-Shards), `UmbralStalkerRenderer` (`MobRenderer` + `RenderType.eyes`-Layer). Kein
  Glowmask, kein Keyframe-Sheet, kein GeckoLib.
- **Hitbox:** `EclipseEntities.UMBRAL_STALKER` = 0.9×1.2, eyeHeight 0.85, MobCategory MISC,
  clientTrackingRange 10 — **unverändert**, das neue Geo ist darauf gebaut.
  Attribute (20 HP / 4 dmg / speed 0.32 / follow 40) liegen in der SHARED
  `EclipseEntities` und bleiben dort.
- **Vorbilder komplett gelesen:** MA3 (Herald) + MA4 (Ferryman) für den Konversions-Ablauf,
  `storm_hound` (Geo/Anim/Painter/`EclipseGeoMonster`-Nutzung/Sprint-Gate) als
  Quadruped-Muster, `client/entity/gazer/` (MC1, Schwester-Zeile) für den Registrar.
- **FROZEN respektiert:** `EclipseGeoMonster` (Controller `base`+`action` final, nur
  `handleBaseState`/`registerActionTriggers`/`walkAnim` überschrieben),
  `EclipseGeoRenderer`, `EclipseGeoAnimations`, `paint_lib.py`, `validate_geo.py`.
- **GeckoLib 4.9.2 Bytecode nachgelesen** (nicht die Wiki-Doku), zwei Stellen zählen:
  `DefaultedEntityGeoModel.setCustomAnimations` (Head-Tracking-Falle, §9.3) und
  `BakedAnimationsAdapter.addSplineArgs` (Loop-Naht-Mathematik, §9.1).

## 1. Bone-Hierarchie (28 Bones / 27 Cubes)

```
root
└─ body (0,11,0)                 Rumpf 7×6×12
   ├─ hump (0,13,-3)             SCHULTER-BUCKEL: Masse 6×5×7 (+5°) + Kamm-Kappe 4×2×5 (+9°)
   │                             -> DIE Silhouette; Knochen-Kiel als 2px-Grat über beide Cubes
   ├─ glow_spine_a/b/c           3 Kristall-Shards 2×4×2 / 2×3×2 / 2×2×2, -18°/-26°/-34°
   ├─ neck (0,13,-5.5)           Hals 4×4×4 — trägt JEDE animierte Kopf-Neigung/-Drehung (§9.3)
   │  └─ head (0,12,-8.5)        Schädel 6×5×5 + Schnauze 4×3×3; heißt exakt `head`
   │     │                       -> GeckoLib-Head-Tracking (turnsHead=true)
   │     ├─ jaw (0,9.5,-13.5)    Unterkiefer 4×2×4, violette Innenmaul-Oberseite
   │     ├─ tusk_l (2.5,9,-15.5) Knochen-Säbel 1×3×1 — bewusst NICHT emissiv
   │     └─ tusk_r
   ├─ scapula_l (3,12.5,-4)      Schulterblatt 1×4×5, Elternteil des Vorderbeins
   │  └─ leg_fl -> leg_fl_lower  2×5×3 / 2×5×2
   ├─ scapula_r -> leg_fr -> leg_fr_lower
   ├─ haunch_l (2.5,12,4)        Keule 3×5×5
   │  └─ leg_bl -> leg_bl_lower
   ├─ haunch_r -> leg_br -> leg_br_lower
   ├─ tail_a -> tail_b -> tail_c Peitschenschwanz 2×2×5 / 2×2×4 / 1×1×4, -14°/-10°/-6°
   ├─ fx_smear_l (3.5,11,-2)     ┐ cube-lose FX-Anker für B2 (§8)
   └─ fx_smear_r (-3.5,11,-2)    ┘
```

Über die reine Alt-Modell-Parität hinaus gehen genau: (a) der **Buckel** (2 Cubes) — der
Auftrag; (b) `neck` als eigener Bone — erzwungen durch die Head-Tracking-Falle; (c)
Schulterblätter + Keulen + zweigliedrige Beine — nötig, damit Kriechen und Sprint
überhaupt zwei verschiedene Gangarten sein können (das alte Modell hatte 4 starre
Ein-Cube-Beine); (d) 2 cube-lose FX-Anker für B2.

**Modell-Ausmaße:** 8×19×36 px = 0.50×1.19×2.25 Blöcke. Länger als die 0.9-Hitbox, aber
**kürzer als der akzeptierte Präzedenzfall** `storm_hound` (0.56×1.12×**2.66**) — Quadrupeden
in diesem Repo ragen konventionsgemäß aus ihrer Hitbox heraus.

**Basis-Rotationen** tragen nur `glow_spine_*` und `tail_*` (Fächerung/Bogen); Buckel und
Kamm tragen ihre Ruhe-Neigung in CUBE-Rotationen → alle Anim-Keys bleiben saubere
null-basierte Deltas.

## 2. Animation-Sheet (`animation.umbral_stalker.*`, format 1.8.0)

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 4.0 s | true | Molang-Atmung (body ×90°/s), Buckel-Wogen, `neck`-Keyframes schauen sich langsam um, Shard-Puls, Schwanz-Wedeln |
| `stalk_low` | 3.0 s | true | **Lauerhaltung**: Rumpf ~2 px tiefer, Schulterblätter über die Topline gezogen, Kopf auf Schulterhöhe abgesenkt, Beine gebeugt, Schwanz flach und zuckend — der Buckel ist der höchste Punkt |
| `crawl` | 1.2 s | true | **Gangart A**: bauchtiefer Vier-Takt-Schleichgang, Diagonalpaare, kaum Vertikalbewegung, Wirbelsäulen-Wellen über `body`-yRot |
| `sprint` | 0.5 s | true | **Gangart B**: gestreckter Galopp mit zwei Flugphasen, Rumpf hebt sich, Buckel pumpt (`hump`-scale), Kiefer offen, Shards flackern doppelfrequent |
| `attack` | 0.5 s | false | Coil → Vorwärts-Satz → Biss (Kiefer + Hauer) → Recoil, endet in Ruhelage |
| `hurt` | 0.3 s | false | Kurzes Zucken/Wegdrehen, endet in Ruhelage |
| `death` | 1.4 s | hold_on_last_frame | Vorwärts-Kollaps auf die Brust, asymmetrisch (Root-Yaw +6°, Body-Roll +7°), Beine knicken nach außen weg, Shards flackern in zwei Stufen aus |

**Loop-Perioden (alle ganzzahlig pro Loop-Länge):**

| Anim | Länge | Molang-Frequenzen | Umdrehungen |
|---|---|---|---|
| idle | 4.0 s | 90 / 180 °/s | 1.0 / 2.0 |
| stalk_low | 3.0 s | 120 / 240 °/s | 1.0 / 2.0 |
| crawl | 1.2 s | 300 / 600 °/s | 1.0 / 2.0 |
| sprint | 0.5 s | 720 / 1440 °/s | 1.0 / 2.0 |

Die One-Shots (`attack`/`hurt`) enthalten **kein** Molang — jeder ihrer Kanäle endet
exakt auf der Ruhelage (`[0,0,0]` bzw. Scale `[1,1,1]`), maschinell geprüft (§6.3).

## 3. Java-Konversion

### 3.1 Zustands-Wechsel Kriechen ↔ Sprint (der eigentliche Auftrag)

Der Aggro-/Speed-Zustand im Code ist **`isAggressive()`** — `MeleeAttackGoal(this, 1.3D,
true)` setzt es, und es liegt auf dem Vanilla-`LivingEntity`-Flag-Byte, wird also von
selbst zum Client gesynct (kein eigener `EntityDataAccessor` nötig). Zweite Quelle: die
**Morgengrauen-Flucht** — die setzt `setTarget(null)`, damit fällt `isAggressive()` weg,
obwohl der Stalker gerade am schnellsten rennt. Dafür gibt es einen neuen synchronisierten
Boolean `DATA_FLEEING`.

Daraus wird eine **Vier-Zustands-Haltungsmaschine** auf dem eingefrorenen `base`-Controller
(kein dritter Controller):

```java
boolean hunting = this.sprintHold > 0;   // Aggro-Latch, client-only
boolean bolting = this.isFleeing();      // synced
if (state.isMoving()) {
    return state.setAndContinue(hunting || bolting ? sprintAnim() : walkAnim());
}
return state.setAndContinue(hunting && !bolting ? stalkLowAnim() : idleAnim());
```

- `walkAnim()` ist überschrieben und liefert **`crawl`** (die dokumentierte
  Substitutions-Stelle der FROZEN-Basis — es gibt bewusst keine `walk`-Anim).
- `stalk_low` spielt genau dann, wenn der Stalker ein Ziel hält und **steht** — das ist
  der Moment, in dem der Spieler die Silhouette liest, bevor der Mob loslegt.
- `sprintHold` ist eine **8-Tick-Hysterese** (Storm-Hound-Präzedenz):
  `MeleeAttackGoal` löscht `isAggressive()` für einen Tick, sobald `LeapAtTargetGoal`
  übernimmt oder der Pfad neu berechnet wird. Ohne Latch würde der Controller mitten im
  Schritt zwischen Kriechen und Sprint hin- und herblenden.
- Wer flieht, **lauert nicht** — beim Stehenbleiben mitten in der Flucht fällt die Maschine
  auf `idle` statt `stalk_low` zurück.

### 3.2 One-Shots + Tod

`registerActionTriggers` ergänzt `attack` und `hurt` (beide `once`) zum geerbten
`death` (`hold`). Verdrahtung: `doHurtTarget` → `attack`; `hurt(...)` → `hurt`, geschützt
mit `isAlive()` (bei tödlichem Schlag ruft `super.hurt` intern schon `die()` auf, das
`death` triggert — ohne die Wache würde der Flinch die Todes-Anim überschreiben);
`die()` → `death`. Neu ist ein `tickDeath()`-Override mit
`DEATH_ANIM_TICKS = 28` (= exakt die 1.4 s der `death`-Anim) plus Soul-Sputtern und
abschließendem `EntityEvent.POOF` — der Renderer setzt `withUprightDeath()`, weil die
Anim den Sturz selbst fährt und Vanillas Seitwärts-Kippen doppelt rotieren würde.

### 3.3 Altklassen

`UmbralStalkerModel` und `UmbralStalkerRenderer` werden **nicht gelöscht** (rg-geprüft: die
SHARED `EclipseEntityRenderers` referenziert beide — G2), sondern `@Deprecated` mit
Verweis auf die Nachfolger. Die drei Client-Anim-Hooks am Entity
(`stalkAmount`/`headLower`/`shardPulse`) bleiben ebenfalls `@Deprecated` erhalten, damit das
alte Modell weiter kompiliert; die Löschung gehört dem Integrator (§7).

## 4. Painter (`scripts/geckolib_gen/mobs/umbral_stalker.py`, Seed `0x0B5A17E4`)

Palette: Haut `#221A2E` (vertikale Maserung, hash-gedithert gegen `#16111F`, seltene
fast-schwarze "Slick"-Flecken), Kopf `#2A2038`, Schnauze `#1C1626`, Kiefer `#120E19`,
**kaltes** Knochen-Paar `#8B8398`/`#CCC3D6` (bewusst violettgrau — der Mob besitzt kein
warmes Pixel), Riss/Glow `#6B3FD4`, Shard-Kern `#E4D4FF` → Spitze `#8A5CFF`, Innenmaul
`#C6A6FF`, Augen `#C08CFF`.

Emissiv (Glowmask, 275 px): `glow_spine_*` (Auto-Präfix), **Buckel-Kiel**,
`scapula_*`-Kämme, Flanken-Risse (α 165), Augen-Pinpricks (auf die ≥ 6 px breite
Schädel-Nordfläche gegated, damit die Schnauze keine leuchtenden Nüstern bekommt),
Innenmaul, Schwanzspitze. Hauer bleiben dunkel — sie sind das einzige nicht-leuchtende
helle Ding am Mob, damit der Biss gegen das Shard-Licht liest.

## 5. Assets/Doku

`docs/uv/umbral_stalker.md` komplett neu geschrieben (Storm-Hound-Muster: Bone/Cube/UV-
Tabelle, Art-Brief, Glowmask-Liste, Head-Tracking-Warnung, Painter-Kommando).

## 6. Ergebnisse

### 6.1 Dateien

**NEU:**

| Datei | Inhalt |
|---|---|
| `src/main/resources/assets/eclipse/geo/entity/umbral_stalker.geo.json` | 28 Bones / 27 Cubes, 64×64, Hierarchie exakt wie §1 |
| `src/main/resources/assets/eclipse/animations/entity/umbral_stalker.animation.json` | 7 Anims (§2) |
| `src/main/resources/assets/eclipse/textures/entity/umbral_stalker_glowmask.png` | ERSTER Stalker-Glowmask, 64², 275 Mask-Pixel |
| `scripts/geckolib_gen/mobs/umbral_stalker.py` | deterministischer Painter, Albedo + Glowmask in EINEM Lauf |
| `src/main/java/.../client/entity/stalker/UmbralStalkerGeoRenderer.java` | `EclipseGeoRenderer`-Sub: turnsHead, `withGlowmask()`, `withUprightDeath()`, shadowRadius 0.6 (Parität) |
| `src/main/java/.../client/entity/stalker/UmbralStalkerRenderers.java` | Registrar, `EventPriority.LOWEST` + `isBound()`-Guard |

**GEÄNDERT:**

| Datei | Änderung |
|---|---|
| `src/main/java/.../entity/UmbralStalkerEntity.java` | `extends EclipseGeoMonster`; `geoId()`; `walkAnim()`→`crawl`; Vier-Zustands-`handleBaseState` + `sprintHold`-Latch; `DATA_FLEEING` synced; `attack`/`hurt`-Trigger registriert und verdrahtet; `die()`→`death` + `tickDeath()` (28 t, Soul-Sputter, POOF); die 3 alten Client-Anim-Hooks `@Deprecated` (bleiben nur für das Altmodell). AI-Kit, Morgengrauen-Flucht, Loot, Sounds UNBERÜHRT |
| `src/main/resources/assets/eclipse/textures/entity/umbral_stalker.png` | alter 11-Cube-Placeholder → neues GeckoLib-Sheet, 2088 Albedo-Pixel |
| `src/main/java/.../client/entity/UmbralStalkerModel.java` | `@Deprecated` + Hinweis, dass die PNG jetzt das neue UV-Layout trägt |
| `src/main/java/.../client/entity/UmbralStalkerRenderer.java` | `@Deprecated` (der `RenderType.eyes`-Pass ist durch den Glowmask ersetzt) |
| `docs/uv/umbral_stalker.md` | komplett neu auf das 28-Bone-Geo |

**GELÖSCHT:** nichts. (Der alte Placeholder-Painter ist die geteilte
`scripts/placeholder_gen/EntitySkinPlaceholder.java`, kein Stalker-eigenes Skript — sie
gehört MC2 nicht und wird nicht angefasst; der Integrator entfernt die Stalker-Zeile dort
zusammen mit dem §7-Snippet, falls gewünscht.)

### 6.2 Zahlen

- 28 Bones / 27 Cubes; UV-Belegung 2088/4096 px (51.0 %), **0 Überlappungen,
  0 Pixel außerhalb des Canvas** (eigener Check — `validate_geo` testet Overlap nicht).
- Hitbox 0.9×1.2 unverändert; Modell 0.50×1.19×2.25 Blöcke.
- Anims: idle 4.0 · stalk_low 3.0 · crawl 1.2 · sprint 0.5 · attack 0.5 · hurt 0.3 ·
  death 1.4 s (hold) = 28 t, deckt `DEATH_ANIM_TICKS` exakt.

### 6.3 Validierung (wörtlich; volle Transkripte in den Artefakten
`mc2_validate_and_compile.txt` und `mc2_revalidation_forced_compile.txt`)

```
=== GEO  .../umbral_stalker.geo.json
    identifier geometry.umbral_stalker  canvas 64x64  28 bones  27 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM .../umbral_stalker.animation.json
    7 animation(s): ...idle, ...stalk_low, ...crawl, ...sprint, ...attack, ...hurt, ...death
  -> PASS (0 error(s), 0 warning(s))

============================================================
validate_geo: 2/2 file(s) passed — all good
```

Painter-Determinismus (2 Läufe hintereinander, identisch):

```
895631b031bd1e991d66e3a474938a59  .../textures/entity/umbral_stalker.png
ce836580c9a2b99519d8b17d60d911df  .../textures/entity/umbral_stalker_glowmask.png
```

Compile — bewusst **erzwungen** (Gradle hasht Inhalte, `touch` und selbst ein
`FROM-CACHE`-Treffer beweisen nichts; deshalb `build/classes/java/main` gelöscht und der
Build-Cache abgeschaltet, damit wirklich jede Quelle neu übersetzt wird):

```
$ rm -rf build/classes/java/main && ./gradlew compileJava --no-build-cache
100 warnings
BUILD SUCCESSFUL in 6s
2 actionable tasks: 1 executed, 1 up-to-date

$ ... | grep -i -E "stalker|error:"
(keine Treffer)

$ ls build/classes/java/main/dev/projecteclipse/eclipse/client/entity/stalker/
UmbralStalkerGeoRenderer.class
UmbralStalkerRenderers.class
```

Die 100 Warnungen sind ausnahmslos die vorbestehenden NeoForge-`EventBusSubscriber.Bus`-
Removal-Hinweise aus `veilfx/**` u. a. — **keine einzige** stammt aus einer MC2-Datei
(der Grep über den kompletten Compile-Output ist leer).

Zusatz-Audit (eigenes Skript, siehe §9):

```
geometry.umbral_stalker 64x64: 2088 px used (51.0%), 0 px outside canvas, 0 overlapping pairs
audit clean: loop seams, one-shot rest poses, head-tracking trap
```

## 7. Patch-Snippets für den Integrator (SHARED `EclipseEntityRenderers.java`, G2)

**Löschen (drei Zeilen), im SELBEN Commit `UmbralStalkerModel.java` +
`UmbralStalkerRenderer.java` entfernen** (Zeile 1 ist die letzte Referenz auf
`UmbralStalkerModel`; der Renderer referenziert seinerseits `UMBRAL_STALKER_LAYER` —
einzeln gelöscht bricht der Build):

```java
// client/entity/EclipseEntityRenderers.java — Zeile 25:
    public static final ModelLayerLocation UMBRAL_STALKER_LAYER = layer("umbral_stalker");
// … onRegisterLayerDefinitions, Zeile 43:
        event.registerLayerDefinition(UMBRAL_STALKER_LAYER, UmbralStalkerModel::createBodyLayer);
// … onRegisterRenderers, Zeile 53:
        event.registerEntityRenderer(EclipseEntities.UMBRAL_STALKER.get(), UmbralStalkerRenderer::new);
```

Im selben Aufwasch können die drei `@Deprecated` Client-Anim-Hooks am Entity weg
(`stalkAmount`, `headLower`, `shardPulse`) — sie existieren nur noch für das Altmodell.

Bis dahin ist NICHTS kaputt: `UmbralStalkerRenderers` registriert mit
`EventPriority.LOWEST` nach der Shared-Klasse (last-write-wins) — der Geo-Renderer
gewinnt deterministisch, die alte Layer-Definition wird nur ungenutzt gebacken.

**Canvas:** `umbral_stalker` = 64×64 (Standard-Mob-Linie), keine Zensus-Ausnahme nötig.

**Lang/Sounds:** KEINE neuen Keys (`entity.eclipse.umbral_stalker` existiert in
`en_us`/`de_de`, alle Sounds sind Vanilla-`SoundEvents`) → **kein langdrop nötig**,
`docs/plans_v3/langdrop/MC2-STALKER.json` entfällt bewusst.

## 8. FX-Wunsch-Spec an B2 — Schatten-Schlieren beim Sprint (NICHT von MC2 gebaut)

```
ENTITY   eclipse:umbral_stalker — GeckoLib geo "umbral_stalker" (64² Sheet + Glowmask).
         Bone-Frame = Entity-Yaw (body); `head` folgt dem Head-Tracking.

TRIGGER  Nur während der Jagd-Gangart. Client-lesbar ohne neues Paket:
           LivingEntity#isAggressive()  ||  UmbralStalkerEntity#isFleeing()
         (beide synced) UND horizontale Geschwindigkeit > ~0.14 B/t.
         Das ist exakt das Gate, auf dem der `sprint`-Loop läuft — kein zweiter
         Zustand, keine Desynchronisation zwischen Anim und FX.

ANKER    Zwei cube-lose Locator-Bones im Geo, eigens dafür angelegt:
           fx_smear_l  pivot ( 3.5, 11, -2)   rechte/linke Flanke auf Schulterhöhe,
           fx_smear_r  pivot (-3.5, 11, -2)   direkt hinter dem Schulter-Buckel
         Beide sind Kinder von `body`, machen also Rumpf-Heben, -Rollen und die
         Galopp-Wellen mit; im Sprint-Loop hebt/senkt sich `body` um ±1 px bei 2 Hz —
         die Schlieren atmen damit von selbst.
         Zusatz-Anker falls eine dritte Spur gewünscht ist: `tail_c` (Peitschenspitze,
         schnellster Punkt am Mob) und `glow_spine_b` (Rückenmitte).

WUNSCH   "Schatten-Schlieren": kein Partikel-Konfetti, sondern 2 kurze, nachhängende
         Schleif-Bänder, die den Weg der Flanken nachzeichnen —
           Länge      ~0.8-1.2 B, Lebensdauer 5-8 t (bei 0.5 s Galopp-Loop bleiben
                      so ~2 Schlieren gleichzeitig sichtbar)
           Farbe      Umbral-Familie: Kern #6B3FD4 -> Rand #221A2E, additiv am Kopf,
                      zum Schwanz hin in Alpha auslaufend (die Schliere soll DUNKLER
                      als die Umgebung enden — der Mob zieht Schatten, kein Licht)
           Breite     1.5-2 px am Anker, verjüngt auf 0
           Ausrichtung tangential zur Bewegung, NICHT billboarded zur Kamera —
                      der Effekt muss aus der Seitenansicht am stärksten sein, weil
                      der Spieler den Stalker seitlich vorbeirennen sieht
           Dichte     1 Band pro Anker; bei reducedFx auf 1 Band gesamt (nur fx_smear_l)
                      oder ganz aus — der Mob bleibt ohne FX vollständig lesbar
                      (Glowmask trägt die Silhouette).
GEGEN-   Nicht an die Beine hängen: die Vorderläufe bewegen sich im Galopp mit ~90 px/s
ANZEIGE  und würden aus den Schlieren ein Rad machen. Nicht an `head`: der Bone wird
         vom Head-Tracking überschrieben und die Schliere würde beim Umschauen springen.
```

## 9. Selbstkritik + Polish-Pässe

### 9.1 Polish-Pass 1 — die Loop-Naht des Sprints war messbar kaputt (BUG, gefixt)

Die geforderte Bedingung "f · len ≡ 0 mod 360" war von Anfang an erfüllt (§2) und die
Keyframe-**Werte** bei t=0 und t=len waren exakt gleich (gemessene Klaffung 0.0000 px).
Trotzdem ruckelte der Galopp. Ursache im 4.9.2-Bytecode nachgelesen:
`BakedAnimationsAdapter.addSplineArgs` **klemmt** die Catmull-Rom-Kontrollpunkte am ersten
und letzten Keyframe (`p0 := p1`, `p3 := p2`). Die Naht ist also nur dann tangenten-stetig,
wenn die erste und die letzte Sekanten-Steigung gleich sind — und die sind sie nie, wenn
die Naht auf einem **Gang-Extremum** liegt (dort kehrt die Geschwindigkeit um).

Gemessen habe ich das, was das Auge sieht: den Sprung der Pro-Frame-Verschiebung
(60 fps, schlechtester Bone-Pivot), einmal am Wrap-Frame und einmal über den Rest des
Zyklus.

| Anim | Wrap-Frame vorher | Zyklus-Max | Wrap nachher |
|---|---|---|---|
| idle | 0.060 px | 0.019 px | unverändert (unsichtbar) |
| stalk_low | 0.023 px | 0.008 px | unverändert (unsichtbar) |
| crawl | 0.422 px | 0.108 px | unverändert (0.03 Blöcke — unter der Sichtbarkeitsschwelle) |
| **sprint** | **3.767 px** | 1.412 px | **0.497 px** (Zyklus-Max 1.897) |

3.77 px = 0.24 Blöcke Extra-Versatz in einem Frame, zweimal pro Sekunde — das ist ein
sichtbarer Tick. **Fix:** der ganze Sprint-Zyklus ist um Δ = 0.22 s **rotiert** worden, so
dass die Naht mitten im Schwung statt auf der vollen Vorderbein-Streckung liegt. Rotation
heißt: jeder authored Pose-Wert bleibt exakt erhalten, nur die Key-Zeiten wandern (plus
ein einziger interpolierter Naht-Key pro Kanal), und die Molang-Sinus bekommen die
passende konstante Phase (`+ f·Δ`, z. B. 720 °/s → +158.4°) aufaddiert, damit Rumpf,
Buckel, Hals, Schwanz und Shards mitwandern. Der Wrap-Frame ist danach der
**zweitruhigste** Frame des ganzen Zyklus (Rang 29/30).
Zum Vergleich der Hausnorm — `storm_hound` (MA6, akzeptiert) mit demselben Messwerkzeug:
sprint Wrap 2.671 px / Zyklus-Max 1.156 px. Der Stalker liegt jetzt deutlich darunter.

> **Repo-weiter Befund für die Integration:** dieses Naht-Verhalten betrifft **jede**
> looping GeckoLib-Anim im Mod, nicht nur den Stalker. Wer schnelle Loops autort, sollte
> die Naht nie auf ein Bewegungs-Extremum legen. Das Messwerkzeug ist bewusst
> throwaway (nicht committet, es gehört MC2 nicht), die Methode steht hier.

### 9.2 Polish-Pass 2 — Bodenkontakt und der Buckel als Hut

- **Fußdurchdringung:** alle vier Pfoten über den ganzen Zyklus vermessen. Sprint jetzt
  max. −0.22 px unter Boden (vorher −0.36), Kriechen/Lauern sauber. Die Rotation aus §9.1
  hat das Planting nicht verschlechtert (nachgemessen, siehe Tabelle im Transkript).
- **Todes-Pose:** liegt am Ende bei y −0.72 px (0.045 Blöcke) und ragt 1.2 px seitlich
  aus der Hitbox — beides tolerabel und deutlich besser als der erste Entwurf (seitliche
  Rolle: 0.65 Blöcke im Boden, 1.4 Blöcke aus der Hitbox), der deshalb komplett durch
  einen Vorwärts-Kollaps ersetzt wurde.
- **Der Buckel las sich als Hut.** Erster Painter-Wurf malte die komplette Kamm-Kappe
  knochenfarben — im Render saß ein beiges Tablett auf dem Mob. Zwei Korrekturen:
  (a) Knochen-Palette von warmem Elfenbein `#D8D0C0` auf kaltes `#CCC3D6` gezogen (der
  Nacht-Terror darf kein warmes Pixel haben); (b) der Kiel ist jetzt ein **2 px breiter
  Grat** die Kammmitte entlang plus die oberste Reihe der Seitenflächen, statt einer
  vollflächigen Platte — der Knochen drückt durch die Haut, statt aufzuliegen.
- **Flanken-Risse** waren eine fast gerade weiße Linie (28 % der Riss-Pixel liefen auf den
  Shard-Kern). Jetzt bricht der Kanal in 22 % der Spalten ab und nur ~10 % der Pixel
  flackern hell → es liest als Riss, nicht als aufgemalter Streifen.

### 9.3 Head-Tracking-Falle (Zensus §7) — geprüft, nicht nur beachtet

`DefaultedEntityGeoModel.setCustomAnimations` **setzt** (nicht: addiert) nach dem
Animations-Pass `head.rotX = headPitch` und `head.rotY = netHeadYaw`. Jede authored
Kopf-Neigung/-Drehung wird also stillschweigend verworfen. Deshalb trägt der Stalker
einen eigenen **`neck`**-Bone, der die gesamte animierte Kopfbewegung fährt; `head` bekommt
ausschließlich Z-Roll (Kopfschieflegen). Das Audit-Skript prüft das maschinell über alle
7 Anims — kein einziger Keyframe schreibt ein von 0 verschiedenes head-X/Y.

### 9.4 Was ich nicht gelöst habe / offene Punkte

1. **Die Naht bleibt prinzipiell C1-unstetig.** Sie ist jetzt kleiner als die natürliche
   Beschleunigung des Zyklus, aber GeckoLibs geklemmte Kontrollpunkte lassen eine exakt
   glatte Wiederholung nicht zu. Wer es perfekt will, müsste das Sheet auf ein
   gleichmäßiges Key-Raster umschreiben (gemessen: worst-corner 1.65 statt 1.90 px) — der
   Gewinn rechtfertigte den Verlust an Hand-Editierbarkeit nicht.
2. **`crawl` ist nicht auf `stalk_low` phasengekoppelt.** Beim Übergang
   Lauern → Kriechen blendet der `base`-Controller über 4 Ticks; das ist sauber, aber die
   Beine starten nicht garantiert im nächstgelegenen Schritt. GeckoLib bietet dafür ohne
   eigenen Controller keine Handhabe.
3. **`stalk_low` ist an "aggro + steht" gebunden.** Ein langsam anpirschender Stalker
   (der sich bewegt) spielt `crawl`, nicht `stalk_low`. Wenn Design lieber ein
   Geschwindigkeits-Gate will (z. B. `stalk_low` bis 0.06 B/t), ist das eine Zeile in
   `handleBaseState` — ich habe bewusst das binäre, synchronisationsfreie Gate gewählt.
4. **Die Todes-Pose ist ein Kollaps, kein Kadaver.** Der Rumpf fällt 4.3 px; ein wirklich
   flach liegendes Tier bräuchte ~7 px und komplett weggeklappte Beine, was das
   Fuß-Planting neu zu lösen zwingt. Die aktuelle Pose liest im Render als "auf die Brust
   gestürzt" — für 28 Ticks vor dem POOF ausreichend, aber ausbaufähig.
5. **Kein Client-Run.** Es gab in dieser Session keinen laufenden Minecraft-Client;
   alle Posen sind mit einem Offline-Rasterizer geprüft, der GeckoLibs Transform-Kette
   (`BakedModelFactory$Builtin.constructBone/constructCube`, `RenderUtil.prepMatrixForBone`,
   Rotation additiv auf die Bind-Pose, Position/Scale absolut) und die
   Catmull-Rom-Auswertung 1:1 nachbaut — verifiziert gegen den 4.9.2-Bytecode. Ein
   In-Game-Blick auf Buckel-Silhouette und Glowmask-Helligkeit bei Licht 0 wäre trotzdem
   die letzte Instanz.
6. **`fx_smear_*` sind leer.** Sie sind nur Anker; ohne B2 passiert dort nichts (und der
   Mob ist ohne FX vollständig lesbar — das war Absicht, siehe §8).
