# B5 — Herzschlag-Dread (Welle 13, Zensus §6 N3)

Team B5. Besitz-Dateien (exklusiv):

- `src/main/resources/assets/eclipse/pinwheel/shaders/program/world_grade.fsh`
  (Uniform-Deklarationen liegen NUR hier — `pinwheel/post/world_grade.json` ist ein
  reiner Blit-Stage-Eintrag, `pinwheel/shaders/program/world_grade.json` nur das
  vertex/fragment-Paar. Beide bleiben unangetastet.)
- `src/main/java/dev/projecteclipse/eclipse/veilfx/VeilPostController.java`

N1 (Umbral-Adern / `eclipse:umbral_veins` + `UmbralVeinsFx`) ist bereits gebaut und wird
NICHT angefasst. Referenz-Muster für diese Arbeit: die A9-Uniforms `BloodDusk` /
`ShadowBands` / `SunSnap` (neue Uniform + Feeder-Methode + Keep-Alive-Klausel +
Idle-0-Regel) und die Slew-Felder `easedPhaseLean` / `easedRimOnly` im Controller.

---

## 1. Uniform-Vertrag

| | |
|---|---|
| Name | `DreadPulse` |
| Typ | `uniform float`, Wertebereich `[0, 1]` |
| Pipeline | `eclipse:world_grade` (GRADE) |
| Feeder | `VeilPostController.feedWorldGrade` → `dreadPulseUniform()` |
| Semantik | **fertige Puls-Stärke**: Schwere × Herzschlag-Hüllkurve. Der Shader macht KEINE Zeitmathematik. |
| Idle | exakt `0.0` ⇒ der Shader-Block wird übersprungen ⇒ **bit-identischer Frame** |
| Time-Basis | Java, pausen-eingefroren (Client-Tick-Zähler + partialTick) — `VeilRenderTime` existiert in pinwheel-Posts nicht |

Der Puls wird komplett in Java berechnet (Leitplanke): der Shader liest einen Skalar und
ist damit trivial + llvmpipe-tauglich, die Kurve ist im Java-Code testbar.

---

## 2. Kurvenformel (Doppelschlag, kein Sinus)

Phase-Akkumulator `dreadPhase ∈ [0,1)`, pro Client-Tick um `1 / periodTicks` erhöht
(Akkumulation statt `time % period`, damit ein Perioden-Wechsel die Phase nie springen
lässt), im Feeder mit `partialTick / periodTicks` interpoliert.

```
periodSeconds = lerp(1.10, 0.70, dread)            // ruhig → panisch
t             = dreadPhase * periodSeconds         // Sekunden im Zyklus
dw(t, c)      = min(|t − c|, periodSeconds − |t − c|)   // Wrap-Distanz
gauss(d, σ)   = exp(−(d/σ)²)

pulse = min(1, gauss(dw(t, 0.00), 0.075)           // LUB  (Amplitude 1.00)
             + 0.70 * gauss(dw(t, 0.22), 0.060))   // DUB  (Amplitude 0.70)

DreadPulse = dread * (0.15 + 0.85 * pulse)
```

**Warum ein fester DUB-Abstand in Sekunden (0.22 s) statt eines Phasen-Bruchteils:**

1. physiologisch korrekt — das S1–S2-Intervall verkürzt sich bei höherem Puls kaum,
   der Zyklus tut es;
2. Photosensitivität: bei festem Phasen-Offset (0.18) läge der Lub-Dub-Abstand im
   Panik-Tempo bei 126 ms (≈ 4 Hz Hell-Dunkel-Wechsel). Mit dem festen 0.22-s-Abstand
   bleiben es **2 Peaks pro Zyklus = 2.9 Flashes/s bei 0.70 s** — unter der 3-Hz-Linie
   und im Geist der Hausregel aus `BackroomsFlickerOverlay` (≥ 450 ms Pulsabstand).

Verifizierte Kurve (Einmal-Skript, nicht committet):

| t (s) | 0.00 (LUB) | 0.05 | 0.08 | 0.12 (Tal) | 0.22 (DUB) | 0.28 | 0.32 | ≥ 0.38 |
|---|---|---|---|---|---|---|---|---|
| `pulse` | 1.000 | 0.641 | 0.324 | 0.139 | 0.700 | 0.258 | 0.044 | ≈ 0 |

Lesbarkeit: Peak → Tal 0.14 → zweiter Peak 0.70 → **Stille** (0.48 s bei 0.70 s Zyklus,
0.80 s bei 1.10 s Zyklus). Das ist der Lub-Dub-Charakter; ein Sinus kommt nicht vor.

Der Boden `0.15` hält zwischen den Schlägen einen minimalen Druck (Release, kein
Blackout-Strobe); bei `dread == 0` ist er wirkungslos, weil er multipliziert wird.

---

## 3. Schwellen (Auslöser)

### (a) HP — absolut in Herzen, `Minecraft.getInstance().player.getHealth() / 2`

Absolut (nicht als Anteil), weil die Max-HP an den Leben hängen
(`HeartsService`: 1 Leben = 4 HP = 2 Herzen, 0–7 Leben) — „3 Herzen" muss bei jedem
Leben-Stand dasselbe bedeuten.

```
window   = smoothstep(3.0 → 2.5 Herzen)                  // weiche Fensterkante
severity = clamp((2.5 − hearts) / (2.5 − 1.0), 0, 1)     // Leiter bis 1 Herz
dreadHp  = window * (0.35 + 0.65 * severity)
```

| Herzen | 3.0 | 2.75 | 2.5 | 2.0 | 1.5 | ≤ 1.0 |
|---|---|---|---|---|---|---|
| `dreadHp` | 0.00 | 0.18 | 0.35 | 0.57 | 0.78 | 1.00 |

⇒ **subtil bei 2.5–3 Herzen** (Abdunklung in der Ecke 3 % bei 2.75, 8 % bei 2.5),
**deutlich unter 1.5 Herzen** (18 % bei 1.5, 23 % bei 1 Herz — jeweils im
Systolen-Peak). Die harte HP-Grenze flackert nie: `window` ist ein
Smoothstep über eine halbe Herz-Breite, und darüber liegt noch der Slew (§5).

Kein Puls für Zuschauer/Kreativ/Tote — dort gibt es keine Gefahr.

### (b) Dread-Zone — Backrooms (Client-State, reine Getter auf bestehende public API)

Was clientseitig ohne neuen Hook verfügbar ist (geprüft: `BackroomsDread` ist rein
server-seitig, `BackroomsPayloads` kennt nur Jumpscare + Flicker-Envelope,
`BackroomsFlickerOverlay` hält seinen Zustand privat):

- `BackroomsDimension.isBackrooms(level.dimension())` — die Dread-Zone IST eine
  Dimension (public static, reiner Getter);
- `BackroomsLayers.layerOf(player.getBlockY()).level()` — Tiefe 1…5 (pure Funktion);
- Nähe eines `GlitchedWandererEntity` — Client-sichtbare Entity, exakt das Muster von
  `client.backrooms.BackroomsBuzz` (Hush-when-stalked, 12 Blöcke).

```
base = 0.20 + 0.055 * (layer − 1)          // Yellow Rooms 0.20 … The Hollow 0.42
prox = 1 − clamp(dist(Wanderer) / 14, 0, 1)   // 0 außerhalb / kein Wanderer
zone = base + (0.85 − base) * prox
```

Die Zone summt also leise (0.20–0.42) und **schwillt auf 0.85 an, wenn der Wanderer
nah ist** — sonst wäre der Puls über eine 20-Minuten-Instanz ein Dauer-Drone.

### Kombination

`dread = max(dreadHp, zone)` (das Mandat sagt ODER). Beides speist dieselbe Uniform;
zwei Herzschläge kann es nicht geben.

---

## 4. Shader-Wirkung (`world_grade.fsh`, Block `[v7]`)

Läuft nach `ShadowBands`, vor `ExposureMul`; nutzt das bereits berechnete `d`
(Bildmitten-Abstand) — kein zusätzlicher Textur-Tap, reine ALU (llvmpipe-tauglich).

```glsl
if (DreadPulse > 0.001) {
    float dreadEdge = smoothstep(mix(0.34, 0.10, DreadPulse), 0.86, d);
    color *= 1.0 - dreadEdge * DreadPulse * 0.26;                       // Vignette
    float dreadLuma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(color, vec3(dreadLuma), DreadPulse * (0.14 + 0.26 * dreadEdge));
}
```

- **Vignette zieht sich enger**: die INNERE Kante des Falloffs wandert mit dem Schlag
  von 0.34 auf 0.10 — der Rahmen schnürt sich zu, statt nur die Ecken abzudunkeln.
  Abdunklung in der Bildecke ~23 % beim Systolen-Peak mit 1 Herz, ~3 % beim
  2.75-Herzen-Flüstern (Faktor 0.26 × Kanten-Smoothstep 0.895 in der Ecke).
- **Desaturierung hebt sich**, randgewichtet (Mitte 14 %, Ecke 37 %): Tunnelblick, die
  Bildmitte bleibt in einem Hardcore-Event lesbar.
- Dazwischen **Release** (Puls fällt auf den 0.15-Boden), Idle = bit-identisch.

`mix(0.34, 0.10, DreadPulse)` ist immer < 0.86, `smoothstep` bekommt also nie
`edge0 ≥ edge1`. Keine Early-Returns, keine `#`-Kommentare im Block
(glsl-processor-NPE-Leitplanke).

---

## 5. Slew / reducedFx / Keep-Alive

- **Slew** (`tickDreadPulse` → `advanceDread`, im bestehenden `onClientTick` neben
  `tickPhaseLeanEase`): Anstieg 0.10/Tick, Abfall 0.05/Tick. Unter 0.002 wird die Zeile
  fallengelassen (Idle-Skip). Gemessen am 60-fps-Trace (§6): Treffer auf 1.25 Herzen ⇒
  erster sichtbarer Frame nach 0.00 s, volle Amplitude nach 0.40 s; geheilt ⇒ **0.83 s
  Ausschleichen** bis exakt 0. `advanceDread` ist bewusst die MC-freie Hälfte des Ticks,
  damit die Rampe ohne laufendes Spiel durchgemessen werden kann.
- **Erster Schlag sofort**: steigt `dread` aus dem Nichts, wird die Phase auf 0
  zurückgesetzt — derselbe Beat wie `BackroomsDread` („der erste Thud landet in dem
  Moment, in dem es dich bemerkt").
- **reducedFx**: KEINE Modulation. Statt des Doppelschlags ein konstanter
  `dread * 0.45` (die `BackroomsFlickerOverlay`-Regel „ein langsames Dimmen statt des
  Strobes"). Das Dread-Signal bleibt, das Flackern verschwindet.
- **Keep-Alive** (`wantWorldGrade`, nach dem `bloodDusk`-Vorbild): `dread > 0.002`
  hält den Pass am Leben. Weil die Dread-Zone eine eigene Dimension ist, gilt die
  Klausel AUCH außerhalb OVERWORLD/NETHER — einzige Ausnahme `eclipse:limbo`, das
  laut Kommentar im Controller seinen eigenen Grade besitzt.
- **Neutralisierung außerhalb der Grade-Dimensionen**: läuft der Pass nur wegen des
  Dread-Herzschlags (also außerhalb OVERWORLD/NETHER), speisen `EclipseAmount`,
  `DesatAmount`, `ArrivalDim`, `EndTintPulse`, `HeatTint`, `HeatShimmer` ihren
  Idle-Wert und `ExposureMul` 1.0. Sonst würde der Eclipse-Grade der Oberwelt in die
  gelben Räume durchschlagen — das wäre eine Regression, die es ohne diese Klausel
  nicht gäbe. (`NightAmount`, `PhaseTint`, `BloodDusk`, `ShadowBands` sind bereits
  intern dimensions-gegated.)

---

## 6. Verifikation

Alle vier Checks sind reproduzierbar ohne laufenden Client — die beiden Harnesse ziehen
Konstanten und Methodenrümpfe per Brace-Matching WÖRTLICH aus `VeilPostController.java`
bzw. rendern den echten `world_grade.fsh`, es gibt keine abgetippte Zweitfassung.

| Check | Werkzeug | Ergebnis |
|---|---|---|
| Java | `./gradlew compileJava` | BUILD SUCCESSFUL |
| GLSL-Syntax + Link | `glslangValidator -l` auf den geflatteten Shader (echte `veil:space_helper`-Include aus dem Veil-Jar, `#veil:buffer veil:camera` zu einem std140-Block expandiert) | 0 Fehler; Negativkontrolle (erfundener Funktionsaufruf im `[v7]`-Block) schlägt fehl ⇒ der Check greift wirklich |
| Veil-Parser | `glsl-processor` 0.2.3 (`GlslParser.preprocessParse` + Round-Trip-Writer) — die NPE-Leitplanke | OK, `DreadPulse` 5× im Round-Trip |
| Kurve + Schwellen | Java-Harness auf dem extrahierten Code | siehe unten |

**Kurve** (Harness, 1 ms Auflösung): genau **2 Peaks pro Zyklus** — LUB bei t = 0.000 s
Amplitude 1.000, DUB bei t = 0.220 s Amplitude 0.700 — bei beiden Tempi.
Flash-Rate 1.82 Hz (ruhig) bzw. **2.86 Hz im Panik-Tempo**, unter der 3-Hz-Linie.

**Doppelschlag lesbar** — der ausgespielte 60-fps-Trace bei 1.25 Herzen (Amplitude 0.892,
Zyklus 0.74 s), ein Zeichen je Frame:

```
...........:-=+#%%%#*+-::::-=+**+=-:...................::-=*#%%%#*=-::::-+***+=::.........
            ^ LUB 0.892        ^ DUB 0.664              ^ LUB          ^ DUB
```

Gemessene Peak-Abstände: **LUB → DUB 0.233 s, DUB → nächster LUB 0.517 s**. Der laute
Erstschlag, der Einbruch, der leisere Zweitschlag, dann eine halbe Sekunde Ruhe — kein
Metronom, kein Sinus.

**Schwellen**: `dreadFromHearts` ist über 10 → 0 Herzen monoton steigend, größter Sprung
0.0053 pro 0.005 Herzen (also stetig, kein Knick), und `dreadFromHearts(3.0) == 0.000000`
— bei 3 Herzen und darüber passiert nachweislich nichts.

**Kein Flackern**: größte Änderung der Uniform zwischen zwei aufeinanderfolgenden Frames
bei 60 fps im Panik-Tempo = 0.159. Im gerenderten Bild sind das 1.55/255 (0.6 %)
Luminanz pro Frame — eine Rampe, kein Blitz.

**reducedFx**: bei `easedDread = 1` liefert die Uniform über den ganzen Zyklus konstant
0.450 (bitweise identisch bei t = 0 und t = 0.5) — keine Modulation.

**Idle-Beweis (der harte)**: der echte Shader wurde offline auf llvmpipe (Mesa 25.2,
GL 4.5 core — Veils eigener Fallback-Renderer) gegen die Fassung aus `git HEAD` gerendert,
mit identischen Eingaben, über eine geraycastete Yellow-Rooms-Szene aus den echten
Vanilla-Blocktexturen. In allen drei Szenarien (Backrooms mit geleerten Sky-Lanes,
Oberwelt-Nacht, volle Totalität mit `BloodDusk`/`ShadowBands`) ist das Ergebnis bei
`DreadPulse = 0` **pixelweise identisch, max |diff| = 0**.

**Severity-Leiter im gerenderten Bild** (Ecken-Luminanz / Sättigung, Systolen-Peak):

| | idle | 2.75 Herzen | 1.5 Herzen | 1 Herz |
|---|---|---|---|---|
| `DreadPulse` | 0.000 | 0.175 | 0.783 | 1.000 |
| Ecke Luminanz | 148.9 | 144.5 (−2.9 %) | 126.3 (−15 %) | 119.0 (−20 %) |
| Mitte Luminanz | 67.9 | 68.0 | 68.4 | 68.5 |
| Sättigung | 52.7 | 50.7 | 41.3 | 37.2 |

Die Mitte bleibt konstant (Tunnelblick statt Blackout), der Rand trägt den Schlag.

**Nicht verifiziert**: keine Sichtprüfung im laufenden Client. Auf der VM liefen bereits
zwei Minecraft-Instanzen anderer Teams (~3 GB frei) — ein dritter Client hätte deren
Sitzungen per OOM abgeschossen. Der Offline-Render führt denselben GLSL-Code mit denselben
Feeder-Werten auf demselben Renderer aus, ersetzt aber keinen In-Game-Blick auf
Kamera-Bewegung + HUD.

## 7. Test-Rezept

Standard sind 5 Leben = 20 HP = 10 Herzen (`HeartsService`: 1 Leben = 4 HP = 2 Herzen).

- **< 3 Herzen, deterministisch**: `/dev lives give <spieler> -4` ⇒ 1 Leben ⇒ Max-HP 4
  ⇒ der Spieler steht dauerhaft auf 2 Herzen ⇒ `DreadPulse`-Amplitude 0.567. Danach
  `/damage @s 2` ⇒ 1 Herz ⇒ volle Amplitude 1.000. Zurück mit
  `/dev lives give <spieler> 4`. (`/dev lives` kennt nur `give` (Delta) und `status`,
  kein `set`.)
- **< 3 Herzen, schnell**: bei vollen 10 Herzen `/damage @s 15` ⇒ 5 HP = 2.5 Herzen
  (Amplitude 0.350), `/damage @s 17` ⇒ 1.5 Herzen (0.783).
- **Dread-Zone**: `/dev backrooms tp hollow` (Level 5, stärkste Basis 0.42) oder
  `/dev backrooms tp yellow` (Level 1, 0.20 — der leise Grundton). Vollständiger Weg:
  `/dev backrooms start` und durchs Portal. Alle `/dev`-Kommandos brauchen Permission 2.
- **Jagd-Anschwellen**: mit einem `GlitchedWandererEntity` innerhalb von 14 Blöcken
  steigt die Zonen-Schwere Richtung 0.85 — am einfachsten in einer echten Instanz
  abzuwarten (`/dev backrooms flicker` triggert nur den Blackout-Beat, nicht die Jagd).
- **Isoliert ansehen**: `/eclipsefx post eclipse:world_grade on` +
  `/eclipsefx uniform eclipse:world_grade DreadPulse 1.0` friert den Peak ein
  (Permission 3). Achtung: der Per-Frame-Feeder überschreibt das Override wieder, sobald
  er läuft — für einen stabilen Blick lieber echten Schaden nehmen.
- **reducedFx gegenprüfen**: Client-Option `reducedFx` an ⇒ der Doppelschlag muss zu
  einem konstanten Druck werden (kein Pulsieren mehr), das Dread-Signal aber bleiben.
