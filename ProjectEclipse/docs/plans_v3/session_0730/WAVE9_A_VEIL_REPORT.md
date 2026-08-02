# WAVE9-A — Veil-Domäne: Umsetzung EVAL2-A (C1, H1, H2, H3, P1+P5)

**Basis:** `docs/plans_v3/eval2/EVAL2-A_veil_domain.md` (vollständig gelesen; alle Bausteine dort
mit Datei-/Zeilen-Evidenz begründet). **Referenzmuster:** `EMITTER_AUDIT_F107_CLASS.md` §3/§10.
**Compile:** `./gradlew compileJava` → BUILD SUCCESSFUL (nur die zwei vorbestehenden
Deprecation-Warnungen in `FxPayloads.java`, nicht Teil dieser Welle).

**Geänderte/neue Dateien:**

| Datei | Baustein | Art |
|---|---|---|
| `assets/eclipse/pinwheel/shaders/program/resonance_shimmer.json` | C1 | NEU |
| `assets/eclipse/quasar/emitters/arm_wisps.json` | H1 | geändert |
| `assets/eclipse/quasar/emitters/containment_bounce.json` | H2 | NEU |
| `src/main/java/dev/projecteclipse/eclipse/stormfx/StormFxClient.java` | H3 | geändert |
| `assets/eclipse/quasar/emitters/storm_godfinger.json` | P1 | geändert |
| `assets/eclipse/quasar/emitters/totality_diamond_glint.json` | P5 | geändert |

Alle fünf JSONs mit `python3 -c "import json;json.load(open(...))"` validiert (OK).

---

## C1 — `resonance_shimmer`-Programmdefinition angelegt

**Root-Cause-Rekap:** Veils `ShaderManager.prepare` lädt Programme ausschließlich über den
Definition-Lister (`.json`); die nackte `resonance_shimmer.fsh` wurde nie zu einem Programm,
`BlitPostStage.apply` bekam `null` und zeichnete nichts — die registrierte, gefütterte
WOAH-04-§4.6-Pipeline war tot.

**Fix:** `pinwheel/shaders/program/resonance_shimmer.json` neu, exakt das `echo_grade`-Muster:

```json
{ "vertex": "veil:blit_screen", "fragment": "eclipse:resonance_shimmer" }
```

**Referenzketten-Verifikation (alle Glieder in dieser Session gelesen):**

1. `ResonanceFieldFx` (static init, Z. 121–123) registriert die `PipelineSpec`
   `eclipse:resonance_shimmer` (FEATURE-Band); Prädikat `wantShimmer` (`shimmer > 0.004 &&
   !reducedFx`), Feeder `feedShimmer` setzt `ShimmerAmount` + `Time` (Z. 170–172).
2. `pinwheel/post/resonance_shimmer.json`: eine `veil:blit`-Stage, `shader:
   "eclipse:resonance_shimmer"`, `in: minecraft:main`, `out: veil:post` — löst jetzt auf die
   neue Programmdefinition auf.
3. Vertex `veil:blit_screen`: in `veil-neoforge-1.21.1-4.3.0.jar` vorhanden
   (`assets/veil/pinwheel/shaders/program/blit_screen.vsh/.json`, per `unzip -l` geprüft).
4. Fragment `eclipse:resonance_shimmer` → `shaders/program/resonance_shimmer.fsh` (53 Zeilen,
   fertig): Uniforms `DiffuseSampler0`/`ShimmerAmount`/`Time` decken sich exakt mit dem Feeder;
   `#include eclipse:eclipse_common` → `shaders/include/eclipse_common.glsl` existiert und
   definiert das benutzte `efxHash` (grep-verifiziert) — dieselbe Include-Zeile nutzt die
   nachweislich funktionierende `echo_grade.fsh`.

**Restrisiko:** Der Look selbst (≤2-px-Radialsplit, 6.5-Hz-Tremble) war nie live gesichtet;
auf llvmpipe kann der Beat subtil ausfallen. Kein Budget-Risiko — der Controller besitzt
Iris-Gate, `veilPostFx`-Toggle und das ≤3-Pass-Cap.

---

## H1 — `arm_wisps`-Vortex-Kur

**Root-Cause-Rekap:** Ungedämpfter `veil:vortex` (strength 0.9, range 2, KEIN drag) auf einem
Dauer-Loop an jedem sichtbaren Artefakt-Träger (`ArmParticles`, dazu `TheOtherEntity`-
Dawn-Burst): Partikel verließen den 2-Block-Range nach ~2 Ticks mit 1.8–2.7 B/t und flogen die
restlichen ~25 t ungebremst ballistisch — 40–60 Blöcke „Leuchtspurgeschosse" mit 10-Punkt-Trail.
Der einzige Kraft-Modul-Emitter des Bestands ohne `veil:drag` (F-108 scannte nur `veil:wind`).

**Fix (JSON-only):** `strength` 0.9 → **0.1**, neues Modul `veil:drag` **0.45** (direkt nach dem
Vortex, vor `veil:color`).

**Herleitung (Bytecode-gestützt, in dieser Session per `javap -p -c` gegen
`veil-neoforge-1.21.1-4.3.0.jar` nachvollzogen):**

- `VortexForceModule.applyForce`: solange |Δ|² < range² wird pro Tick ein Tangentialvektor der
  Länge `strength` auf die Velocity addiert (kein dt, kein Falloff).
- `DragForceData` → `ScaleForceModule.applyForce`: `velocity *= strength` pro Tick — Drag-
  `strength` IST der Retention-Faktor (deckt sich mit der §3.1-Formelprobe: godfinger
  0.0004·0.96/0.04 ≈ 0.19 B/s).
- Rekurrenz (Modulordnung Vortex→Drag): `v ← (v + s)·d`; Fixpunkt **v\* = s·d/(1−d)**.
- **Warum nicht das wörtliche „drag ~0.9" des Audits:** s=0.1, d=0.9 ⇒ v\* = 0.1·0.9/0.1 =
  0.9 B/t = **18 B/s** — verfehlt das im selben Audit gesetzte Ziel „Terminal ≲2 B/s" um 9×.
  Die ~0.9-Empfehlung trägt das F-108-WIND-Muster mit, dort sind die Per-Tick-Kräfte aber
  0.0004–0.02 (5–250× kleiner als ein Vortex mit s=0.1).
- **Gewählt:** s=0.1, d=0.45 ⇒ v\* = 0.1·0.45/0.55 ≈ 0.0818 B/t ≈ **1.64 B/s** ✓ (≲2 B/s mit
  Marge). Ballistischer Rest nach Range-Austritt: ≤ v\*·d/(1−d) ≈ **0.07 Blöcke** (vorher
  40–60). Gesamt-Bogen über die max. 30-t-Lebenszeit ≤ ~2.5 Blöcke — in den Orbit gekrümmt:
  die enge Wisp-Spirale am Arm.
- Einordnung in den Bestand: die 33 gutmütigen Kraft-Emitter tragen Drag 0.01–0.3 (Retention);
  0.45 liegt knapp darüber, damit am Arm sichtbare Orbit-Bewegung bleibt (Brackets:
  `limbo_moths` 0.05+0.01 ⇒ ~0.01 B/s quasi-statisch; `vortex_wisp` 0.6+0.05 ⇒ 0.63 B/s).

**Restrisiko:** Der Look ist eine Neu-Justierung (Streaks → Orbit); der 10-Punkt-Trail zeichnet
jetzt ein kurzes, dichtes Band an der Spirale — falls das am Arm zu dicht liest, wäre
`trailLength` runter der nächste Regler. Braucht eine Live-Sichtung am Artefakt-Träger.

---

## H2 — `containment_bounce.json` angelegt

**Root-Cause-Rekap:** `ContainmentService.CONTAINMENT_BOUNCE_EMITTER` (Javadoc: „P2 registers
this Quasar emitter") wird bei jedem Weltrand-Bounce als `S2CQuasarPayload` gesendet, das
Emitter-JSON wurde aber nie geliefert — `QuasarSpawner.spawnOrFallback` lief in den einmaligen
unknown-id-Warn und den generischen 8-Partikel-END_ROD/PORTAL-Vanilla-Burst (Code in dieser
Session gegengelesen, Z. 139–169).

**Fix:** `quasar/emitters/containment_bounce.json` neu, `unlock_burst`-Anatomie wie im Audit
empfohlen: One-Shot (loop false, max_lifetime 3, rate 2, count 8 ⇒ zwei Spawn-Events, ~16
Partikel), Hemisphäre `from_surface` [0.5, 0.4, 0.5] (das Feld schiebt von UNTEN), additiv,
`velocity_stretch 0.4`, Haus-Wisp `purple_wisp.png` (16×16, Rand-α 0), Größe 0.12±0.05,
Lebenszeit 14±4 t. Farbrampe Weiß-Blitz → `#E4CFFF` → **`#B98CFF`** (= `ContainmentService.
HINT_COLOR`, auch die Farbe der Bounce-Actionbar-Message) → `#7B4FD0`; α 1.0 → 0.85 → 0.4 → 0.
Statt `unlock_burst`s Gravity+Drag nur `veil:drag` 0.75 — der Puls soll als „Abprallen nach
oben" lesen, nicht als fallender Funkenregen.

**Herleitung / Anti-Stapel-Prüfung der Sender-Seite (`ContainmentService` komplett gelesen):**

- `applyBounce` feuert aus `onPlayerTick`, sobald `y < bounceY`; der Flip setzt vy = +2.8 B/t.
  Schlimmstfall liegt der Spieler nach einem Terminal-Fall (~3.9 B/t) einen Tick später noch
  unter der Schwelle ⇒ **maximal 2 Payloads auf Folge-Ticks**; danach trägt der Bogen (+2.8-
  Launch ≈ 40 Blöcke hoch) den Spieler für ≥6 s aus der Zone — Dauer-Anrennen ergibt also einen
  Burst pro ~6-s-Zyklus, nie einen Stapel. Payload geht nur an den gebounc­ten Spieler
  (`sendToPlayer`).
- Burst-Ausdehnung: Reichweite = v₀·d/(1−d) = 0.5·0.75/0.25 = **1.5 Blöcke** — kompakt, und
  selbst der Doppel-Feuer-Schlimmstfall sind ≤32 kleine Quads (≤0.17) für ≤0.9 s.
- Budget: `spawnOrFallback` ohne Kanal ⇒ `FxBudget.Channel.BURST` (One-Shot-Gesetz) ✓.

**Restrisiko:** Erster komponierter Look für diesen Beat — Feinabstimmung (Count/Tint-Balance
gegen die parallel weiterlaufenden Server-REVERSE_PORTAL-Partikel) braucht eine Live-Sichtung.

---

## H3 — Kamera-Clearance in `StormFxClient.tickWisps`

**Root-Cause-Rekap:** Die ≤3 `vortex_wisp`-Loop-Emitter orbitieren den Vortex-Sturm auf
Shell+1 und werden per `setPosition` geführt; Releases gab es für DISSIPATE/Sichtbarkeit/Tier,
aber keinen Kamera-Abstands-Release — der Sturm-Eintritt ist eine Wandquerung durch den
Orbit-Ring, und die bis 4.2-Block-Quads (plus die quasi-ortsfesten Partikel, die der ziehende
Emitter auf dem Ring zurücklässt) erzeugten Near-Plane-Schnittkanten — exakt die Lücke, die
E5-Nachfix 2 (§10.2) beim Godfinger schloss.

**Fix (~20 Zeilen Java):** Das §10.2-Hysterese-Paar übernommen, Kommentar-/Javadoc-Stil und
Referenz auf den Godfinger-Fix inklusive:

- `WISP_CAMERA_CLEARANCE = 7.0` — Slot released, sobald seine Ring-Sollposition horizontal
  näher kommt (Emitter-Removal tötet die Live-Quads sofort, `ParticleEmitter.onRemoved` —
  inklusive des auf dem Ring zurückgelassenen Trails).
- `WISP_CAMERA_REENGAGE = 10.0` — Re-Spawn erst jenseits davon; `wispAngle` läuft während des
  Release weiter (Godfinger-Regel: das Muster setzt exakt dort fort, wo es wäre — kein Ruckeln).
- Struktur wie `tickGodFingers`: Ringposition VOR dem Live/Tot-Zweig berechnen, Live-Pfad
  released-oder-setPosition, Spawn-Pfad nur jenseits REENGAGE (Budget-Refusal retryt weiter
  jeden Tick). Der jetzt redundante `wispPos`-Helper wurde inlined/entfernt;
  `tickWisps` bekommt den `camera`-Parameter vom bereits vorhandenen `tickStorm`-Wert.

**Herleitung der Schwellen (aus vortex_wisp-Größe + Spawn-Shape, nicht blind 6/9 kopiert):**

- Worst-Case-Quad-Reichweite ab Ring-Anker: Spawn-Sphäre r **1.6** + max. Quad-Halbkante
  (1.5 + 0.6)/2 = **2.1** ⇒ **3.7 Blöcke** (Godfinger: 1.4 + 2.1 = 3.5). Lebenszeit-Drift
  vernachlässigbar: Vortex 0.6 + Drag 0.05 ⇒ Terminal 0.6·0.05/0.95 ≈ 0.032 B/t.
- Schließgeschwindigkeits-Budget: anders als der quasi-statische Godfinger (~0.03 B/t Drift)
  zieht der Wisp-Emitter selbst mit `SWIRL_RAD_PER_TICK`·(r+1) ≈ 0.40 B/t (Default r=22) bis
  ~0.66 B/t (Siege-skaliertes r≈36) über den Ring; plus Kamera (Elytra ~2 B/t) ⇒ ~2.6 B/t
  kombinierter Ein-Tick-Vorstoß.
- **Release 7.0:** Marge = 7.0 − 3.7 = 3.3 ≥ Godfinger-Marge 2.5 + 0.66 Emitter-Eigenbewegung.
  **Re-Engage 10.0:** Hysterese-Breite 3 (wie 6→9 beim Godfinger) und > 2.6-B/t-Vorstoß —
  kein Kantenflackern beim Entlangwaten.

**Restrisiko:** Der Release tötet den gesamten Ring-Trail des Slots (bis ~30 Blöcke Bogen) —
beim Eintritt ein Fog-/Motion-maskierter Pop, derselbe bewusste Trade wie beim Godfinger-Schaft
(§10.2-Präzedenz). Zweitens verliert `wispHeights[k]` während eines Release seinen Vortrieb
(Höhe friert ein) — identisch zum Verhalten bei Budget-Refusals, kein neues Artefakt.

---

## P1 — `storm_godfinger`-Alpha-Plateau 0.1 → 0.15

**Root-Cause-Rekap:** §10.6-Live-Learning: der verdunkelnde `storm_interior`-Grade crusht die
additiven Schächte bei Dämmerung/Nacht unter die llvmpipe-Sichtbarkeit (~0.12) — der Godfinger
ist aber der einzige Orientierungs-Marker Richtung Sturm-Auge.

**Fix:** Beide Plateau-Punkte (percent 0.25/0.75) 0.1 → **0.15** (Audit-Fenster 0.14–0.16).
Kein Kanten-Risiko: 3.2er-Quads auf der 64×256-Soft-Schaft-Textur; Kriterium 3 bleibt
unterschritten, weil der Textur-Peak 0.55 die Effektiv-α auf ~0.08 dämpft. Wind/Drag
(0.0004/0.96, Terminal 0.19 B/s) unangetastet.

**Restrisiko:** Tages-Gegenprobe laut Audit einplanen (Überstrahlen bei Noon unwahrscheinlich,
aber ungeprüft).

## P5 — `totality_diamond_glint` auf `flash_soft.png`

**Root-Cause-Rekap:** Stärkster E2-Grenzfall: Quad bis 1.6 (1.1 + 0.5), additiv, α-Peak 1.0
auf dem 16×16-`wisp_white` — Nearest-Texel-Rechtecke zentral im Blick beim Totality-Peak
(`TotalityPeakFx` feuert den Glint als Diamond-Ring-Beat Richtung Sonne).

**Fix:** Sprite auf die vorhandene **128×128-`flash_soft.png`** umgestellt (das fertige
§6/E2-Gegenmittel; PNG-Header in dieser Session verifiziert). Sonst nichts geändert.

**Restrisiko:** `flash_soft` hat einen weicheren Luminanz-Falloff — der Glint kann größer/
weicher lesen; beim nächsten Totality-Peak gegensichten.

---

## Live-Abnahme-Plan (Client, je Baustein)

Alle Befehle sind gegen den Quellcode verifiziert (`FxDevCommands`, `DevResonanceCommands`).

1. **C1:** Welt betreten → `/eclipsefx post list` (Row `eclipse:resonance_shimmer` vorhanden)
   → `/dev woah resonance spawn here`, einen Feld-Kristall schlagen. **Erwartung:** ~0.6 s
   radialer RGB-Split-Puls („die Luft klingt"), KEINE `ShaderManager`-Warnung im Log;
   `/dev woah resonance solve` für den Finale-Peak (0.6, 40 t). Schnell-Smoke ohne Gameplay:
   `/eclipsefx post eclipse:resonance_shimmer on` — Log bleibt warnfrei = Programm linkt
   (Feeder füttert dann `shimmer`≈0, der Split selbst braucht den Kristall-Schlag).
2. **H1:** `/give @s eclipse:arm_artifact`, F5-Ansicht. **Erwartung:** enge violette
   Wisp-Spirale (~1.64 B/s Terminal) am Arm, Partikel+Trail bleiben ≤ ~2 Blöcke am Körper,
   keine 40-Block-Leuchtspuren. Positions-Blick: `/eclipsefx emitter eclipse:arm_wisps`.
3. **H2:** `/eclipsefx emitter eclipse:containment_bounce`. **Erwartung:** kompakter
   weiß→violetter Aufwärts-Puff, ≤1.5 Blöcke, ~0.9 s, Tint passend zur `#B98CFF`-Actionbar.
   Gameplay-Probe: Containment-Tag/`bounceY` in der Protection-Config aktiv, unter `bounceY`
   fallen — Burst statt des bisherigen Vanilla-END_ROD/PORTAL-Fallbacks; beim wiederholten
   Anrennen ein Puls pro Bounce-Zyklus (~6 s), kein Stapeln.
4. **H3:** `/eclipsefx storm add 22 48 vortex`, zu Fuß/Elytra durch die Wand auf Wisp-Höhe
   (Shell+1). **Erwartung:** der querungsnahe Orbit-Slot verschwindet, sobald seine
   Ringposition <7 Blöcke an der Kamera ist (keine 4-Block-Quad-Schnittkanten), kehrt >10
   Blöcke zurück; die zwei anderen Slots orbitieren unbeirrt weiter; an der Kante entlangwaten
   flackert nicht. Danach `/eclipsefx storm remove`.
5. **P1:** `/eclipsefx storm add 40 80 sphere`, `/time set midnight`, ins Innere Richtung
   Zentrum. **Erwartung:** die Godfinger-Schächte im Auge sind jetzt als blasse grüne Säulen
   lesbar (vorher de facto unsichtbar); Gegenprobe `/time set noon`: kein Überstrahlen.
6. **P5:** `/eclipsefx emitter eclipse:totality_diamond_glint`. **Erwartung:** weicher
   additiver Glint-Pop ohne Rechteck-Texelkanten; echter Beat beim nächsten Totality-Peak
   (Diamond-Ring Richtung Sonne) gegensichten.
