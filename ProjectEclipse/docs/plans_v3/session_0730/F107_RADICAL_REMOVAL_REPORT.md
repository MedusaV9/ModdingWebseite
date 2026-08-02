# F-107 Teil 4 — Radikal-Entfernung: Godrays + Near-Motes raus, Kiel aus Holz

Anschluss an `F107_UMBRAL_QUAD_REPORT.md` (Teil 3, inkl. Runde 2). Entscheidung nach
drei gescheiterten Tuning-Runden: Die beiden verbliebenen Producer der „lila Dinger am
Bildrand" werden ERSATZLOS ENTFERNT statt weiter getunt, und der steinerne
Kiel-/Ballast-Dither unter dem Schiff wird durch einen hölzernen, sich nach unten
verjüngenden Unterwasserrumpf ersetzt (Schiffs-v3 + Versions-Bump).

Beweis-Frames der Abnahme, die die Entscheidung ausgelöst haben: `/tmp/fin_frame_16.png`,
`/tmp/fin_frame_20.png` (große runde lila Kreise = Bokeh-Motes), `/tmp/fin_frame_88.png`
(Kapsel-Cluster oben links = Godray-Schäfte), `/tmp/fin_frame_96.png`,
`/tmp/fin_frame_100.png` (Kapsel + Kreise am linken Rand). Grundproblem: die Umgebung
rendert mit llvmpipe (Software-GL) — große additive Quads quantisieren im 8-bit-Target
zu harten Iso-Alpha-Stufen und lesen NIE als Licht, egal wie weich die Textur ist.
Teil 3 hatte die Kanten-Physik (Power-Law + Dither) und das Stacking gefixt; die
Restwahrnehmung „hartkantige lila Kapsel/Scheibe" blieb.

---

## 1. Aufgabe A — GODRAYS + NEAR_MOTES komplett entfernt

### 1.1 Gelöscht (Dateien)

| Datei | Was es war |
|---|---|
| `src/main/resources/assets/eclipse/quasar/emitters/limbo_godray.json` | Quasar-Emitter der Welt-Raum-Godray-Schäfte |
| `src/main/resources/assets/eclipse/quasar/emitters/limbo_motes_near.json` | Quasar-Emitter der Near-Focus-Bokeh-Motes |
| `src/main/resources/assets/eclipse/textures/particle/limbo_godray_shaft.png` | dedizierte 64×256-Schacht-Textur (nur von limbo_godray referenziert) |
| `src/main/resources/assets/eclipse/textures/particle/limbo_mote_bokeh.png` | dedizierte 128×128-Bokeh-Textur (nur von limbo_motes_near referenziert) |
| `tools/art/gen_limbo_godray_shaft.py` | Generator der Schacht-Textur |
| `tools/art/gen_limbo_mote_bokeh.py` | Generator der Bokeh-Textur |

Referenz-Audit (rg über `src/`): `eclipse:limbo_godray` und `eclipse:limbo_motes_near`
wurden AUSSCHLIESSLICH von `LimboAmbience` gespawnt; die beiden Texturen ausschließlich
von ihren Emitter-JSONs; die Generator-Skripte von nichts. `FxDevCommands` (`/eclipsefx`)
listet nur generische Vorschläge (enthielt `limbo_motes`, nie die beiden gelöschten IDs)
— zählt nicht als Referenz. Kein anderes Ambience-System, keine Cutscene nutzt sie.
Verbleibende Erwähnungen sind historische Doku (`docs/plans_v3/...`) und die bewusste
Removal-Notiz in der `LimboAmbience`-Javadoc.

### 1.2 `LimboAmbience.java` (Client-seitig!)

- `GODRAYS`-Window (Ring 14–28, maxLive 2, Sway ±0.9) und `NEAR_MOTES`-Window
  (Ring 4.5–8, Garnish-Tier) samt Konstanten (`LIMBO_GODRAY`, `LIMBO_MOTES_NEAR`,
  `ROLL_PERIOD_SECONDS`) und ihren kompletten Javadoc-Historien entfernt.
  `WINDOWS` = {MOTES, FOG, FOGBANKS, MOTHS}.
- Mitentfernt, weil nur diese zwei Windows sie nutzten: die v4-Roll-Sway-Maschinerie
  (`swayAmplitude`, `sway()`, `Live`-Record mit Base/Phase → Deque hält jetzt direkt
  `ParticleEmitter`) und der Garnish-Tier-Schalter (`skipUnderReducedFx`).
- KEIN Ersatz-Emitter. Ambience der Szene kommt weiterhin aus: Fog/Fogbank (weiche
  128px-Sprites, Teil-2-Clearance-Garantien), Fern-Motes, Moths, Spire-Embers,
  Wasser-Shader, Laternen. Die **Screen-Space-Godrays des `eclipse:limbo`-Post-Passes
  (`GodrayDir`-Uniform) bleiben unangetastet** — sie waren nie der Producer.

### 1.3 Fern-Motes hart gekappt (`limbo_motes.json`)

Soll: Größe (base+variation) ≤ 0.35, Alpha-Peak ≤ 0.05, Wind ≤ 0.0006 mit `veil:drag` 0.96.

| Parameter | vorher | nachher | Status |
|---|---|---|---|
| base_particle_size + variation | 0.055 + 0.03 = 0.085 | unverändert | war schon ≤ 0.35 |
| Alpha-Peak (2 Stützpunkte) | **0.28** | **0.05** | gekappt |
| wind_speed / veil:drag | 0.0006 / 0.96 | unverändert | war schon konform |

Nebenwirkung (dokumentiert, akzeptiert): `eclipse:limbo_motes` wird auch vom
`EclipseDeathScreen` als „slow ash"-Loop und von `HeraldFerrymanFxRows`-Doku erwähnt —
der Death-Screen-Ash wird durch den Alpha-Cap ebenfalls deutlich leiser. Das ist mit
„nur winzige ferne Staubpunkte" konsistent und führt keinen neuen Effekt ein.

## 2. Aufgabe B — Kiel/Ballast: Holz statt Stein, Rumpf statt Plattform

### 2.1 Befund

`GhostShipBuilder.hullShell` verkleidete ALLES unterhalb der Wasserlinie mit
`barnacle()`: positionsgehashter Dither aus 18% `mud_bricks`, 28% `blackstone`, Rest
`dark_oak_planks` — auf dem kompletten flachen Kielboden (y=46, bis 9 Blöcke breit,
39 lang) und den Bilge-Wänden (y=47–48). Durchs semi-transparente violette Wasser las
der helle Stein-Dither als flache Stein-Plattform unter dem Boot (Waterline y=48,
Kiel y=46, Deck y=51).

### 2.2 Lösung: Schiffs-v3-Unterwasserrumpf (nicht ersatzlos entfernen)

Der Kielboden ist NICHT reine Deko — er versiegelt die hohle Bilge nach unten (das
abgedichtete Envelope, auf dem die P3-Sink/Restore-Mathematik aufsetzt). Ersatzloses
Entfernen hätte die Bilge geflutet. Daher: Material-Swap + Formgebung:

- **Bilge-Wände (y 47–48)**: statt Barnacle-Stein jetzt dieselbe Haut wie über Wasser —
  `dark_oak_planks`, Rippen-Spalten (jede 4. x-Spalte) als `dark_oak_log` durchgehend
  bis zum Kiel. Heckspiegel/Bugkappe (|x|=19) Planken.
- **Kielboden (y=46)**: `dark_oak_planks`, pro Seite **einen Block eingerückt**
  (halfWidth−1); die Kimm-Ecken (|z| = halfWidth) werden explizit **Wasser** gesetzt.
  Der Rumpf verjüngt sich dadurch sichtbar nach unten — Silhouette „Schiffsboden",
  nicht „Slab". Versiegelung bleibt beweisbar intakt: jede Bilge-Luftzelle hat weiter
  Vollholz unter sich (eingerückter Boden trägt genau die Innenzellen) und neben sich
  (Wände in voller Höhe); die Wasser-Ecken liegen AUSSERHALB des Envelopes, über ihnen
  sitzt die Wand.
- `barnacle()` ersatzlos gelöscht. Heckpfosten/Ruder (x=−20/−21) waren schon Holz.
  `LimboSeascape` platziert Blackstone/Obsidian nur an den drei Spires 120–260 Blöcke
  entfernt — unterm Schiff kommt kein Stein mehr vor.
- Explizites Wasser-Setzen (statt Zelle überspringen) ist der Migrations-Trick: so
  überschreibt ein Re-Run von `build()` die alten Stein-Ecken in place (§3).

## 3. Live-Welt-Applikation

### 3.1 Bevorzugt: Versions-Bump (implementiert — Weg (a))

`ShipVersionData.VERSION_V3 = 3` neu; `GhostShipBuilder.buildIfNeeded` no-op't jetzt
erst ab v3. Migrationspfad je Bestand:

- **v2-Welt (der Live-Stand)**: beim nächsten Serverstart mit dem neuen Build läuft
  `build()` OHNE Clear erneut durch — deterministisch, alle über-Wasser-Zellen sind
  Same-State-No-ops, nur das Unterwasser-Delta wird geschrieben (Stein→Holz,
  Kimm-Ecken→Wasser) — und stempelt v3.
  Log-Beleg: `Ghost ship v3 migrated from v2 (wooden tapered underhull) in
  eclipse:limbo at waterline y=48 ...`.
- v1/Legacy: unverändert Clear + Voll-Rebuild (jetzt direkt auf v3).
- Ferryman-Guard bleibt: Rebuild wird übersprungen, solange ein Ferryman lebt
  (Retry beim nächsten Start).
- Abwärtskompatibel: `ShipLanterns`/`RespawnDoorApi` gaten auf `>= VERSION_V2`.

**Es ist also nichts weiter nötig als: neuen Build deployen + Server neu starten.**
(Client braucht den neuen Build ebenfalls — die Emitter-Entfernung ist Client-Code.)

### 3.2 Alternative ohne Neustart: RCON-Fills (Weg (b), konvergent zu v3)

Falls die laufende Welt VOR dem Deploy optisch angeglichen werden soll (alter Jar,
Version bleibt v2 — der spätere v3-Boot schreibt dann Same-State-No-ops). Waterline
y=48, Kiel y=46; halfWidth: |x|≤12→4, 13–15→3, 16–17→2, 18–19→1; Rippen-Spalten
x ∈ {−16,−12,−8,−4,0,4,8,12,16}.

```
# Bilge-Wände y 47–48 -> Planken
execute in eclipse:limbo run fill -12 47 4 12 48 4 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -12 47 -4 12 48 -4 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 13 47 3 15 48 3 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 13 47 -3 15 48 -3 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -15 47 3 -13 48 3 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -15 47 -3 -13 48 -3 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 16 47 2 17 48 2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 16 47 -2 17 48 -2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -17 47 2 -16 48 2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -17 47 -2 -16 48 -2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 18 47 1 18 48 1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 18 47 -1 18 48 -1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -18 47 1 -18 48 1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -18 47 -1 -18 48 -1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 19 47 -1 19 48 1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -19 47 -1 -19 48 1 minecraft:dark_oak_planks
# Rippen-Spalten y 47–48 -> Log (Achse y = default)
execute in eclipse:limbo run fill -12 47 4 -12 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill -12 47 -4 -12 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill -8 47 4 -8 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill -8 47 -4 -8 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill -4 47 4 -4 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill -4 47 -4 -4 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 0 47 4 0 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 0 47 -4 0 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 4 47 4 4 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 4 47 -4 4 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 8 47 4 8 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 8 47 -4 8 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 12 47 4 12 48 4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 12 47 -4 12 48 -4 minecraft:dark_oak_log
execute in eclipse:limbo run fill 16 47 2 16 48 2 minecraft:dark_oak_log
execute in eclipse:limbo run fill 16 47 -2 16 48 -2 minecraft:dark_oak_log
execute in eclipse:limbo run fill -16 47 2 -16 48 2 minecraft:dark_oak_log
execute in eclipse:limbo run fill -16 47 -2 -16 48 -2 minecraft:dark_oak_log
# Kielboden y=46 -> Planken (eingerückt)
execute in eclipse:limbo run fill -12 46 -3 12 46 3 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 13 46 -2 15 46 2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -15 46 -2 -13 46 2 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 16 46 -1 17 46 1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -17 46 -1 -16 46 1 minecraft:dark_oak_planks
execute in eclipse:limbo run fill 18 46 0 19 46 0 minecraft:dark_oak_planks
execute in eclipse:limbo run fill -19 46 0 -18 46 0 minecraft:dark_oak_planks
# Kimm-Ecken y=46 -> Wasser (der Taper)
execute in eclipse:limbo run fill -12 46 4 12 46 4 minecraft:water
execute in eclipse:limbo run fill -12 46 -4 12 46 -4 minecraft:water
execute in eclipse:limbo run fill 13 46 3 15 46 3 minecraft:water
execute in eclipse:limbo run fill 13 46 -3 15 46 -3 minecraft:water
execute in eclipse:limbo run fill -15 46 3 -13 46 3 minecraft:water
execute in eclipse:limbo run fill -15 46 -3 -13 46 -3 minecraft:water
execute in eclipse:limbo run fill 16 46 2 17 46 2 minecraft:water
execute in eclipse:limbo run fill 16 46 -2 17 46 -2 minecraft:water
execute in eclipse:limbo run fill -17 46 2 -16 46 2 minecraft:water
execute in eclipse:limbo run fill -17 46 -2 -16 46 -2 minecraft:water
execute in eclipse:limbo run fill 18 46 1 19 46 1 minecraft:water
execute in eclipse:limbo run fill 18 46 -1 19 46 -1 minecraft:water
execute in eclipse:limbo run fill -19 46 1 -18 46 1 minecraft:water
execute in eclipse:limbo run fill -19 46 -1 -18 46 -1 minecraft:water
```

(Solids zuerst, Wasser zuletzt. Die Godray-/Near-Mote-Entfernung selbst ist NICHT per
RCON erreichbar — sie ist Client-Code + Client-Ressourcen; ein Client mit altem Build
spawnt sie weiter. Deshalb ist Weg (a) der einzige vollständige.)

## 4. Gates

- `./gradlew compileJava processResources --offline -q` → **exit 0 (grün)**; in
  `build/resources/main/...` verifiziert: die beiden Emitter-JSONs + Texturen sind raus,
  `limbo_motes.json` trägt Alpha 0.05.
- Keine Textur regeneriert (nur gelöscht bzw. unverändert gelassen).
- Referenz-Audit §1.1; `keelY` wird von keinem anderen System gelesen (P3-Sink/Rescue
  arbeiten ab Deckhöhe `waterline+3`).

## 5. Abnahme-Kriterium fürs nächste Video

Nach Deploy (Server + Client neuer Build) und einem Serverstart darf in Limbo
**nirgendwo mehr** zu sehen sein:

1. Violette Kapseln / Kapsel-Queues / gelappte Kapsel-Cluster am Himmel oder Bildrand
   (Godray-Schäfte — Emitter existiert nicht mehr).
2. Große runde violette Scheiben/Kreise, einzeln oder als Traube, in Deck-/Mastnähe
   oder am Bildrand beim Schwenk (Bokeh-Motes — Emitter existiert nicht mehr).
3. Eine helle flache Stein-Plattform unter dem Schiff durchs Wasser (Kiel/Bilge sind
   jetzt dunkles Eichenholz, nach unten verjüngt; bei y=46–48 dürfen nur noch dunkle
   Holztöne liegen).

Weiterhin sichtbar (gewollt): weiche Fog-/Fogbank-Schleier, WINZIGE schwache
Staub-Punkte (Fern-Motes, Alpha 0.05), Moths an den Soul-Laternen, Spire-Embers,
Screen-Space-Godrays am Eclipse-Disc, Wasser-Caustics/Glints.
