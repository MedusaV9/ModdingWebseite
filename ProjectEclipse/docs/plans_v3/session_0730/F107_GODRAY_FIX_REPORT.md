# F-107 — Limbo-Godray-Fix („das lila Ding"): Report

User-Beschwerde (wörtlich): _„das Lila Ding beim limbo fixen (in der Aufnahme sieht man
das ganz klar dieses Ding was da so in Wellen ganz links am Rand kommt)"_

Root-Cause (Orchestrator, per In-Game-A/B verifiziert): der Quasar-Emitter
`eclipse:limbo_godray` stapelte bis zu 30 additive Quads (3 Emitter × 10 Partikel) aus
dem hellen 8×8-`purple_wisp.png` auf 6 ± 4 Blöcke große, velocity-gestreckte Billboards —
auf llvmpipe und in der User-Aufnahme eine blasse, gestufte, periodisch hereinschiebende
„Wand" am Bildrand statt subtiler Lichtschächte.

Hinweis zur Arbeitsbasis: Der Arbeitsbaum enthielt bereits einen **unkommitteten,
unvollständigen F-107-Ansatz** eines früheren Durchgangs (JSON-Retune + 64×256-Textur +
Generator unter `tools/quasar_textures/` + Javadoc-Absatz + eigener Report
`F107_LIMBO_VISUAL_FIXES_REPORT.md`, aber Window-Konstante unverändert). Dieser Ansatz
wurde geprüft (Kernbehauptungen gegen das Veil-Jar verifiziert, s. §1.2), übernommen und
vervollständigt: Window-Entschärfung, Schema-Konsistenz (`velocity_stretch_factor`
wieder aufgenommen), Generator an den Konventions-Ort `tools/art/` verschoben
(byte-identische Reproduktion verifiziert), Kommentar korrigiert; der Schwester-Report
wurde per Addendum + Faktenkorrekturen auf den Endzustand gebracht. Dort außerdem
wertvoll: die tiefe Bytecode-Root-Cause-Analyse (§2, u. a. Quad-Kante = 2×size,
Stretch = konstant ×(1+factor) — beide hier nachverifiziert) und das
**RCON-Abnahme-Drehbuch** (§7) für die visuelle Live-Abnahme durch den Orchestrator.

---

## 1. Entscheidung + Begründung

**Rettung als subtiler Akzent** (bevorzugte Richtung), NICHT Stilllegung. Drei Hebel:

1. **Dedizierte Godray-Textur** `limbo_godray_shaft.png` (64×256 RGBA, deterministisch
   generiert von `tools/art/gen_limbo_godray_shaft.py`): schmaler Gauß-Kern (~25 % der
   Quad-Breite), seitlich sehr weich auslaufend, oben+unten über ~22 % auf exakt 0
   ausblendend, **vorverdunkeltes** Violett direkt in den RGB-Kanälen (Kern #8C69C8,
   Rand #5A3C96 — beide unter halber Luminanz). Alle Randtexel tragen Alpha 0, damit die
   Quad-Kante nie eine sichtbare „Blatt"-Kante zeichnen kann.
2. **Emitter-JSON drastisch entschärft**: max. 4 statt 10 Quads, halbe Größe, kein
   face_velocity/Stretch mehr (die Textur macht die Länge, nicht der Stretch),
   Alpha-Peak 0.1 → 0.06, Farb-Gradient von Pastell-Lavendel auf dunkles Violett
   (#5F3D9E-Bereich, wie gefordert um #5A2E9E).
3. **Window in `LimboAmbience.java` entschärft** (minimal-invasiv, nur die
   GODRAYS-Konstante + Javadoc): max. 2 statt 3 gleichzeitige Emitter, Spawn-Ring
   10–24 → **14–28 Blöcke** (das F-088-FOG-Präzedens: ein Schacht kann nicht mehr direkt
   vor der Kamera parken). Kadenz (90–130 Ticks), Höhenband (8 ± 7) und Roll-Sway
   (±0.9) bleiben unverändert — das „in Wellen"-Timing selbst war nie das Problem,
   nur was pro Welle gezeichnet wurde.

Der Post-Shader (`pinwheel/shaders/program/limbo.fsh`) liefert die primären
Screen-Space-God-Rays weiter; der Quasar-Emitter ist danach wieder das, was er sein
sollte: ein sekundärer, volumetrischer Akzent in Mitteldistanz.

### 1.1 Warum die Wand jetzt physikalisch unmöglich ist

Additives Blending (Veil nutzt `ADDITIVE_TRANSPARENCY` = `SRC_ALPHA, ONE`) addiert pro
Quad `texRGB × tintRGB × texAlpha × tintAlpha`. Worst Case, alle Kerne perfekt
übereinander, hellster Kanal (Blau):

- **Vorher**: 30 Quads × (255/255 tex) × (1.0 tint, #C9A0FF) × (0.74 tex-α) × (0.1 tint-α)
  ≈ **2.2** → sättigt weit über 1.0 = blasse, fast opake Wand; Rot/Grün ähnlich hoch
  → Richtung Weiß-Rosa.
- **Nachher**: 8 Quads × (200/255 tex) × (0.62 tint, #5F3D9E) × (0.67 tex-α) × (0.06 tint-α)
  ≈ **0.16** → ein sanfter violetter Schimmer; Rot ≈ 0.06. Selbst der theoretische
  Worst Case (alle 8 Kerne deckungsgleich, was der 14–28-Block-Ring und die
  Zylinderstreuung praktisch ausschließen) bleibt eine Größenordnung unter der Wand
  und kann nie ins Blasse/Weiße driften — die Textur ist vorverdunkelt.

### 1.2 Verifizierte Nebenbefunde (gegen `veil-neoforge-1.21.1-4.3.0.jar` geprüft)

- `VeilRenderType` „quasar_particle" baut `TextureStateShard(location, blur=false,
  mipmap=false)` → **Nearest-Neighbor-Sampling**. Das 8×8-Sprite über einem
  viele-Blöcke-Quad zeigte deshalb sein Texelraster als harte Stufen (das „gestufte"
  in der Aufnahme). 64×256 ≈ 35 Texel/Block auf einem 7-Block-Schacht → glatt.
- `QuasarParticleData`-Codec: `velocity_stretch_factor` ist `optionalFieldOf`. Trotzdem
  explizit `0.0` gesetzt — alle 101 anderen Emitter-JSONs führen das Feld
  (Muster `impact_light.json`: `face_velocity: false` + `velocity_stretch_factor: 0.0`).

---

## 2. Geänderte/neue Dateien

| Datei | Art | Inhalt |
|---|---|---|
| `src/main/resources/assets/eclipse/quasar/emitters/limbo_godray.json` | geändert | Retune (Tabelle §3), Sprite-Wechsel auf `limbo_godray_shaft.png` |
| `src/main/resources/assets/eclipse/textures/particle/limbo_godray_shaft.png` | neu | 64×256 RGBA, dedizierte Schacht-Textur (Pixel-Belege §5.4) |
| `tools/art/gen_limbo_godray_shaft.py` | neu | deterministischer Generator (Stil/Ort wie `gen_wisp_white.py`); ersetzt den Vorarbeit-Standort `tools/quasar_textures/gen_godray.py` (entfernt), PNG byte-identisch reproduziert (md5 `e00ff6c3…` vor = nach) |
| `src/main/java/dev/projecteclipse/eclipse/veilfx/LimboAmbience.java` | geändert | nur GODRAYS-Window-Konstante + Javadoc (F-107-Absatz) |
| `docs/plans_v3/session_0730/F107_GODRAY_FIX_REPORT.md` | neu | dieser Report |
| `docs/plans_v3/session_0730/F107_LIMBO_VISUAL_FIXES_REPORT.md` | neu (Vor-Durchgang, aktualisiert) | Analyse-Report des ersten Durchgangs; Addendum + Faktenkorrekturen (Generator-Pfad, Window-Parameter, Dateiliste) auf den Endzustand |

---

## 3. Parameter vorher/nachher

### 3.1 Emitter-JSON (`limbo_godray.json`)

| Parameter | Vorher (HEAD) | Nachher |
|---|---|---|
| `rate` (Ticks/Spawn) | 10 | 30 (steady-state ≈ 3–4 live ≙ Cap, kein Dauer-Cap-Churn) |
| `max_particles` | 10 | **4** |
| `base_particle_size` | 6.0 | **3.5** |
| `particle_size_variation` | 4.0 | **1.0** |
| `face_velocity` | true | **false** (Billboard bleibt aufrecht, kein Roll) |
| `velocity_stretch_factor` | 3.4 | **0.0** (Länge kommt aus der Textur) |
| Sprite | `purple_wisp.png` 8×8, Zentrum RGBA(231,190,255,189) | `limbo_godray_shaft.png` 64×256, vorverdunkelt |
| Farb-Gradient | #C9A0FF → #A45CF2 → #8A3CE8 | **#7A55B8 → #5F3D9E → #46297A** |
| Alpha-Peak (0.2–0.7 Lebenszeit) | 0.1 | **0.06** |
| unverändert | Zylinder 0.9×9.5, speed 0.022, Lebenszeit 100 ± 20, Wind-Modul, Fade-in/out-Ankerpunkte | — |

### 3.2 Window (`LimboAmbience.GODRAYS`)

| Parameter | Vorher | Nachher |
|---|---|---|
| max. gleichzeitige Emitter | 3 | **2** |
| Spawn-Distanz (Blöcke) | 10–24 | **14–28** |
| Respawn-Intervall | 90–130 Ticks | unverändert |
| Höhenband über Wasser | 8 ± 7 | unverändert |
| Roll-Sway | ±0.9 | unverändert |
| Worst-Case additiver Stack | 30 Quads | **8 Quads** |

---

## 4. Audit: andere `purple_wisp`-Emitter mit `additive: true` und Größe ≥ 3.0

Scan über alle 102 Emitter-JSONs (Sprite, `additive`, `base_particle_size`,
`max_particles`, Alpha-Peak, Spawn-Kontext aus dem Java-Aufrufer):

| Emitter | additive | Größe | max_particles | Alpha-Peak | Spawn-Nähe | Wand-Risiko | Einschätzung |
|---|---|---|---|---|---|---|---|
| `limbo_godray.json` | ja | 6.0 ± 4.0 | 10 (Loop) | 0.1 | 10–24 Bl. | **ja — GEFIXT** | dieser Report |
| `storm_godfinger.json` | ja | 4.5 ± 2.5 | 8 (Loop) | 0.1 | am Sturm-Auge, ≤ 2 Emitter (`StormInteriorFx`, Engage ≤ 48 Bl. vom Zentrum) | **ja (moderat)** | Strukturell dasselbe Rezept (8×8-Sprite, additiv, face_velocity + Stretch 2.2, Dauerloop). Mildernd: max 2 Emitter, ans Sturm-Auge gebunden statt an die Kamera — aber ein Spieler unter dem Auge sieht potenziell dieselbe Stufen-Wand in Grün. **Empfehlung (nicht umgesetzt, Scope):** gleiche Kur — dedizierte Schacht-Textur (Generator ist wiederverwendbar, ggf. Grün-Variante), `max_particles` → 4, Alpha-Peak → ~0.05. |
| `impact_light.json` | ja | 3.6 ± 0.8 (Size-Modul wächst 1.2→4.6×) | one-shot: `loop: false`, `count: 3`, Lebenszeit 7 ± 2 Ticks | 0.95 | am Treffer/Crit/Blitz-Einschlag (`CombatFeedbackFx`, `WandPhaseService`, `IntroLightningPhase`), BURST-budgetiert | **nein** | Absichtlicher ~0,35-s-Mikro-Flash aus 3 Quads; kein Loop, keine zeitliche Stapelung, kein Stretch. Hell, aber genau das ist der Zweck. Keine Änderung empfohlen. |

Randfälle außerhalb der Kriterien (der Vollständigkeit halber): `limbo_fog` (8.0 ± 7.0)
und `limbo_fogbank` (26.0 ± 6.0) sind groß, aber **nicht additiv** (alpha-blended,
Alpha-Peak 0.13/0.1) — genau deshalb bilden sie keine additive Aufhellungs-Wand;
kein Handlungsbedarf. Alle übrigen additiven purple_wisp-Nutzer liegen bei Größe ≤ 0.85.

---

## 5. Gate-Belege

Alle Kommandos aus `/workspace/ProjectEclipse`.

### 5.1 JSON-Syntax

```
python3 -m json.tool src/main/resources/assets/eclipse/quasar/emitters/limbo_godray.json   → Exit 0
```

### 5.2 processResources

```
./gradlew processResources --console=plain   → BUILD SUCCESSFUL, Exit 0
```

### 5.3 compileJava (Java geändert: LimboAmbience.java)

```
./gradlew compileJava --console=plain   → BUILD SUCCESSFUL, Exit 0
```

### 5.4 Textur-Verifikation (PIL, Exit 0)

`Image.open(...)`: **size (64, 256), mode RGBA**. Pixel-Belege (x, y → RGBA):

| Messpunkt | Wert | Beleg |
|---|---|---|
| Kern Mitte (32, 128) | (140, 105, 200, 171) | Kern = #8C69C8, dunkles Violett, α 0.67 |
| Kern Viertelhöhe (32, 64) | (140, 105, 200, 199) | Langwellen-Variation, Maximum α = 202 |
| seitlich +8 px (40, 128) | (117, 84, 177, 91) | weicher Gauß-Abfall Richtung Rand |
| linke/rechte Randspalte (0/63, 128) | (…, 0) | α exakt 0 |
| oberste/unterste Zeile (32, 0/255) | (…, 0) | α exakt 0 |
| Fade-Band oben (32, 28) | (140, 105, 200, 100) | weiches vertikales Auslaufen |
| max. α auf irgendeinem Randtexel | **0** | Quad-Kante kann nie zeichnen |

Determinismus: Generator vom neuen Ort `tools/art/` erneut ausgeführt → PNG md5
unverändert `e00ff6c37a4a611f6dc964d1ec8c7d23`.

---

## 6. Erwartetes Sichtergebnis

Statt der blassen, gestuften, fast opaken Wand, die alle ~5 s am Bildrand hereinschob:
**wenige (≤ 2 Emitter × ≤ 4 Partikel), schmale, aufrechte, dunkel-violette Lichtschächte
in Mitteldistanz (14–28 Blöcke)**, die im 8 ± 7-Block-Band über dem Wasser hängen, sanft
mit dem Schiffs-Roll schwanken, über ~5 s ein-/ausblenden und selbst bei
Überlappung höchstens einen dezenten violetten Schimmer addieren. Die dominanten
God-Rays der Szene kommen weiterhin vom Limbo-Post-Shader (Screen-Space, von der
Eclipse-Scheibe aus) — der Quasar-Anteil ist nur noch ein leiser volumetrischer Akzent.
Auf llvmpipe wie auf echter GPU identisch begrenzt, weil die Dunkelheit in der Textur
selbst steckt und nicht am Vertex-Tint hängt.
