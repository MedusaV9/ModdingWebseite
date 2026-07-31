# MD1 — Eclipse Wand (das Hero-Item)

**Auftrag:** Zensus §5 Welle M-D Zeile MD1 (`docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md`).
(a) Pro-Pfad-use-Varianten (`use_glut` Peitschhieb / `use_riss` Riss-Zug / `use_stern`
Stich nach oben); (b) levelup/awaken von 2 auf 8+ Bones (echte Zeremonie); (c) stall
mit sichtbarem „Verschlucken"; (d) Selbstkritik-Pass für das meistgesehene 3D-Modell
(Transforms, Idle-Leben, Pfad-Färbung).

**Datei-Besitz (exklusiv):** `wand/*.java` (ohne FX-Rows — die liegen in
`client/wand/Wand{Photon,Fx2Photon}FxRows` und blieben unangetastet!),
`geo/item/eclipse_wand.geo.json`, `animations/item/eclipse_wand.animation.json`,
`textures/item/wand/*`, `scripts/geckolib_gen/items/eclipse_wand.py`,
`client/wand/WandClientExtensions` + `EclipseWandRenderer`, `docs/uv/eclipse_wand.md`.
**NICHT angefasst:** alle `.fx`/`tools/photon/**` (W13-A1/A2 — Wünsche nur als Spec §7),
`entity/wizard/*` (MB2!), `models/item/eclipse_wand.json` (geprüft, unverändert gut —
§6.3), FROZEN-Basen, Lang-Dateien (keine neuen Keys ⇒ kein langdrop nötig).

---

## 1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

**Wie der Wand-Code den Pfad kennt & Anims triggert** (die Kernfrage aus dem Auftrag):

| Trigger-Seam | Datei/Stelle | Anim heute |
|---|---|---|
| Erfolgreicher Cast | `WandPowers.handleCast` — NACH `WandSpellEffects.cast` + `castFlourish`; **`path` ist dort bereits aufgelöst und non-NONE validiert** (`WandSoulbind.pathOf(stack)`, NONE returnt vorher) | EIN `use` für alle drei Pfade |
| Veil-Ladung leer | `WandPowers.handleCast` (no_charge-Ast, mit AMETHYST_CHIME 0.5-Pitch) | `stall` (0.3 s Wackeln) |
| Wand global disabled | `WandPowers.handleCast` (disabled-Ast) | `stall` |
| Levelup (Node-Kauf) | `WandTreeService.recalcLevel` (celebrate && rose) | `levelup` (1.2 s, **nur root+tip = 2 Bones**) |
| Pfadwahl (First-Bind) | `WandPowers.handleChoosePath` — D11-Zeremonie: weißer Flash + Sting via `WandTickService.schedule(…, 18, …)` = **0.9 s nach Trigger** | `awaken` (1.6 s, nur root+tip) |
| Rebirth | `WandTreeService.handleRebirth` | `awaken` |

Controller-Contract (verifiziert an `EclipseWandItem`/`EclipseGeoAnimations`): `base`
(Blend 4, loopt `idle`) + `action` (Transition 0, nur `triggerableAnim`-One-Shots,
server-seitig via `triggerWandAnim` → GeckoLib-eigener Sync). Kanal-Übersteuerung ist
PRO KANAL: der später registrierte `action` gewinnt für Kanäle, die er animiert; alles
andere hält `base` weiter — darauf baut der ganze Entwurf (§4.1).

**Wo die `p_*`-Bones leben:** `geo/item/eclipse_wand.geo.json`, 36 Bones / 26 Cubes;
je Pfad drei Gruppen-Roots `p_<pfad>_s1..3` als Kinder von `tip`, vom
`EclipseWandRenderer.preRender` per `wand_path`/`wand_level` gehidet
(`stageForLevel`: L1 = s1, L2–3 = s2, L4–5 = s3). Vier Textur-Sets + Glowmasks +
Pfad-Tints (`getRenderColor`) existieren bereits — Aufgabe (d) „Pfad-Färbung via
Glowmask" war zu VERIFIZIEREN, nicht zu bauen.

**Idle-Molang-Bestand:** 8-s-Loop, alle Dauerrotationen sind Vielfache von 45 °/s
(= ganze 360°-Vielfache über die Länge — Naht-Gesetz aus MD3 §1 bestätigt), Mikro-Puls
auf `tip` (±6 % Scale) vorhanden.

**GeckoLib-Vorzeichen/Transform-Semantik:** komplett aus `MD3_ITEMSB_REPORT.md` §6.3
übernommen (Rot X/Y negiert, Pos X negiert, Z→Y→X, Molang == numerisch zur Laufzeit)
— mein Offline-Checker (§5) rechnet exakt damit.

## 2 Plan

1. **(a) Pfad-Dispatch:** `EclipseWandItem.useAnimFor(WandPath)` + drei neue
   Triggerables; in `WandPowers.handleCast` den einen `ANIM_USE`-Trigger durch den
   Pfad-Dispatch ersetzen (die `path`-Variable steht dort schon validiert bereit).
   `use` bleibt als NONE-Fallback registriert (Dev-Edits).
2. **(b) Zeremonie:** Geo +11 Bones/+7 Cubes — ruhend unsichtbare Gruppe `cere_anchor`
   (Kind von `tip`; `idle` pinnt sie auf Scale 0, MD3-„ruht-auf-Scale-0"-Muster) mit
   2 Annulus-Ringen, weißheißem Kern, 4 Orbit-Fragmenten. `levelup` 2→25 animierte
   Bones, `awaken` 2→25 (neu 2.0 s, **Klimax exakt bei 0.9 s = D11-Flash-Tick**).
3. **(c) stall** 0.3→0.7 s: Spitze + Krone werden eingesaugt (tip-Scale-Kollaps vererbt
   auf alle `p_*`-Kinder), Schluck wandert als Bulge `knot`→`handle_wrap` nach unten,
   schwacher Sputter, Ruhelage.
4. **(d)** Display-Transforms rechnerisch prüfen (Sweep-Boxen unter GUI-/1st-Person-
   Scale), Idle-Mikro-Leben ergänzen (knot/wrap-Sway, Scherben-Atmen, Stern-Twinkle).
5. Painter: Materialien für die neuen Bones (Annulus mit transparenter Mitte!),
   Texturen regenerieren, Determinismus 2×-md5.

## 3 Geänderte Dateien

| Datei | Art |
|---|---|
| `geo/item/eclipse_wand.geo.json` | 36 → **47 Bones**, 26 → **33 Cubes** (+ visible_bounds 2.5→3.5/3.0 für die Zeremonie-Ausdehnung) |
| `animations/item/eclipse_wand.animation.json` | 5 → **8 Anims**; idle 19→21 Bones, levelup/awaken 2→**25** Bones, stall 1→**14** Bones |
| `wand/EclipseWandItem.java` | +3 Triggerables (`use_riss/glut/stern`) + `useAnimFor(WandPath)` |
| `wand/WandPowers.java` | 1 Zeile: Cast-Trigger nutzt `useAnimFor(path)` statt `ANIM_USE` |
| `scripts/geckolib_gen/items/eclipse_wand.py` | `ceremony_ring`-Material + 3 `glow_cere_*`-Zuweisungen; **`paint_catalyst()` jetzt opt-in `--catalyst`** (§6.1!) |
| `textures/item/wand/*` (8 PNGs) | Painter-Output (nur regeneriert) |
| `docs/uv/eclipse_wand.md` | **NEU** — fehlte komplett (§6.2) |

`models/item/eclipse_wand.json`, `client/wand/*` (inkl. FX-Rows), `wizard_catalyst.png`
(wiederhergestellt, §6.1) und alle fremden Team-Dateien unverändert.

## 4 Ergebnis pro Auftrag

### 4.1 (a) Pro-Pfad-use-Varianten — jeder Pfad hat jetzt Handling-Charakter

| Anim | Länge | Charakter | Kern-Mechanik |
|---|---|---|---|
| `use_glut` | 0.5 s | **Peitschhieb** | Windup [14°] → Schlag [−42°] catmullrom; die Welle läuft mit 0.02-s-Versatz durch `shaft`→`shaft_mid`→`shaft_top`→`tip` (Segment-Lag verkauft die Peitsche); Finnen fächern ±25°, Kern/Flammen flackern 1.7–1.9× auf; 14 Bones |
| `use_riss` | 0.45 s | **Riss-Zug** | Yank ZUM Spieler (root-Pos +1.6 Z, Rot [16,−24,8] catmullrom mit Überschwinger); Scherbenkrone kontrahiert auf 0.5–0.6 und SCHNAPPT auf 1.4–1.5; Splitter splayen (b/c ±28° Z, d/e ±22° X); Glitch-Jitter auf a/f (0.02-s-1-Frame-Versätze, MB4-Muster); Ring-Spinburst endet bei exakt 360°; 14 Bones |
| `use_stern` | 0.5 s | **Stich nach oben** | Dip (−1.2) → Thrust (+3.0 catmullrom, Halte-Beat bei 0.34); Scheiben-Spin-up über `p_stern_s2` (idle-unberührt ⇒ Pop-frei, endet 360°); die 4 Orbit-Sterne staffeln mit 0.04-s-Versatz nach oben (+2.4…+3.6) und flaren 1.5×; Schaft-Segmente strecken kaskadiert; 13 Bones |

Kanal-Disziplin gegen Übergabe-Pops: auf Bones, die der idle DAUERROTIERT
(`p_riss_s1..3`, `p_glut_s2`, `stern_disc`, …), fassen die One-Shots nur **Scale/Position**
an; Rotations-Akzente liegen auf idle-unberührten Bones (`riss_ring`, `p_stern_s2`,
Splitter-Kinder) und enden auf exakten 360°-Vielfachen (§6.4).

### 4.2 (b) levelup/awaken — von 2 auf 25 Bones

Neue Geo-Gruppe (ruhend UNSICHTBAR — `idle` hält `cere_anchor` statisch auf Scale 0,
Action-Controller übersteuert den Kanal nur während der Zeremonie):

```
tip
└─ cere_anchor                  (Träger, Scale-0-Pin im idle)
   ├─ glow_cere_core            (2×2×2, inflate 0.45 — umhüllt die Spitze)
   ├─ cere_ring_a  [14,0,0]     (statischer Kipp — MD3-§6.1-Gesetz: Kipp ≠ Spin!)
   │  └─ glow_cere_ring_a       (6×6-Annulus, animierter Y-Spin)
   ├─ cere_ring_b  [−10,0,18]
   │  └─ glow_cere_ring_b       (8×8-Annulus, gegenläufig)
   └─ cere_orbit                (Y-Spin-Träger)
      └─ glow_cere_frag_a..d    (4 Fragmente, Radien 3.5–4 px auf 4 Höhen)
```

| Anim | Länge | Ablauf |
|---|---|---|
| `levelup` | 1.2 s | root-360-Spin (Bestand) + wrap-Konterspin −360, knot-Vollturn mit Pop, Schaft-Stretch-Kaskade (0.15/0.25/0.35 s), Ringe steigen +2/+3.2 und rotieren 720/−540°, Kern flammt 1.3×, Fragmente blühen gestaffelt (0.2–0.5 s) auf und ziehen bei 1.1 s ein, aktive Pfad-Krone pulst 1.2× — 25 Bones |
| `awaken` | **2.0 s** | 0–0.5 Zittern + Aufstieg, Spitze ATMET EIN (0.8×); 0.5–0.9 Beschleunigung (Ringe, Orbit, Schaft-Stretch); **0.9 s KLIMAX** — root-Pop 1.12, tip 1.85, Kern 1.5, Fragment-Flare — landet auf D11s weißem Flash + `BEACON_ACTIVATE` (Tick 18 = 0.9 s, `WandPowers.handleChoosePath`); 0.9–2.0 Ringe entschleunigen und ENTSCHWEBEN nach oben (+3/+4), Fragmente lösen sich gestaffelt auf, Absetzen — 25 Bones |

Beide enden mit `cere_anchor`-Scale 0 ⇒ nahtlose Rückgabe an den idle-Pin, kein
End-Blitzer. Die Zeremonie trägt die Pfadfarbe (Painter mischt die aktive Palette
Richtung Weiß) — auch ein Stage-1-Stab hat jetzt eine echte Zeremonie statt „root dreht
sich + tip wird groß".

### 4.3 (c) stall — sichtbares Verschlucken (0.3 → 0.7 s, 1 → 14 Bones)

Ablauf: 0–0.18 s die Spitze KOLLABIERT (Scale [0.55,0.5,0.55], Pos −1.4) und saugt die
gesamte Krone mit ein (alle 9 `p_*`-Gruppen schrumpfen zusätzlich auf 0.25–0.35, mit
0.02-s-Stagger pro Stufe — die Vererbung über `tip` zieht sie sichtbar nach unten in
den Schaft); 0.28 s der **Schluck**: `knot` bulged [1.35,0.9,1.35], 0.38 s wandert der
Bulge in `handle_wrap` (Energie läuft den Stab HINUNTER); Husten-Wackler auf root;
0.5–0.58 s schwacher Sputter (tip versucht 1.04-Re-Flare) — dann Ruhelage. Spam-fest:
beginnt und endet in Rest, Re-Trigger mitten drin startet sauber neu.

### 4.4 (d) Selbstkritik-Pass — Transforms + Idle-Leben

- **Display-Transforms** (`models/item/eclipse_wand.json`): rechnerisch geprüft (§5
  Sweep-Boxen), UNVERÄNDERT gelassen — Ruhe-Fußabdruck im GUI-Slot ist mit
  Zeremonie-Gruppe identisch zum Ship-Stand (Scale-0-Pin), 1st/3rd-Person-Werte sind
  produktionserprobt. Transiente Slot-Überschreitungen bei `use_stern`/`awaken` sind
  bewusst (MD3-Präzedenz „die Scherben fliegen aus dem Slot").
- **Idle-Leben bei genauem Hinsehen** (neu): `knot`-Sway ±2° (45 °/s-Naht),
  `handle_wrap` ±1.5°, Riss-Hauptscherbe atmet ±5 % (135 °/s), Sternkern twinkelt ±8 %
  (225 °/s) — alle Perioden ganze 360°-Vielfache über 8 s, Naht bleibt bei 7e-15 (§5).
- **Pfad-Färbung via Glowmask**: bestätigt vorhanden (4 Textur-Sets + `getRenderColor`-
  Tints); die neuen Zeremonie-Elemente hängen am selben Swap.
- **visible_bounds** 2.5→3.5/3.0 (Offset [0,1,0]): awaken-Sweep erreicht 38.9 px ≈
  2.43 Blöcke — die alten Bounds hätten in Bounds-cullenden Kontexten geclippt.

## 5 Validierung

| Prüfung | Ergebnis (wörtlich) |
|---|---|
| `python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>` | `validate_geo: 2/2 file(s) passed — all good`; GEO `-> PASS (0 error(s), 0 warning(s))`, ANIM `-> PASS (0 error(s), 0 warning(s))` |
| Painter-Determinismus | 2× Lauf, `md5sum`-diff leer → **byte-identisch** (alle 8 Wand-PNGs) |
| `./gradlew compileJava` | `BUILD SUCCESSFUL` |
| Canvas-Konsistenz | Albedo + Glowmask je 64×64, alle 4 Varianten ✓ |
| Idle-Loop-Naht (FK-Checker) | max Matrix-Delta t=0 vs t=8.0 = **7.105e-15** |
| One-Shot-Ruhelagen (FK-Checker) | **kein** Bone endet ≠ Ruhelage (Schwelle 0.2 px); verbleibende Übergabe-Deltas ≤ **0.139 px** = idle-Mikro-Sway-Klasse, identisch zum SHIP-Stand des alten `use` |
| Textur-Eyeball (8×) | Annulus-Ringe lesen als Ringe (Mitte transparent), voll emissiv in der Glowmask, Runen-Nähte unverändert |

FK-Checker = eigener Offline-Nachrechner (`/tmp/md1_check.py`, nicht committet, nach
MD3-Vorbild): baut die Bone-Welt-Matrizen mit GeckoLibs Transform-Semantik (MD3 §6.3)
nach, prüft Ruhelagen/Naht und sampelt Sweep-AABBs. Kein `runClient` gestartet
(llvmpipe-VM, 7 Teams parallel — §8 liefert das Test-Rezept für die Sichtprüfung).

Sweep-Boxen (alle sichtbaren Bones, dt = 0.01, linear; GUI = ×0.7 im 16-px-Slot):

| Anim | Sweep (px) | GUI-Slot | Befund |
|---|---|---|---|
| idle | 9.8 × 22.3 × 9.0 | 6.8 × 15.6 | passt (wie Ship-Stand) |
| use_glut | 16.3 × 25.2 × 33.4 | 11.4 × 17.6 | Z-Peitschweg zeigt in die Tiefe — im Slot nur 1.6 px Überstand |
| use_riss | 13.3 × 24.5 × 13.9 | 9.3 × 17.2 | passt praktisch |
| use_stern | 14.6 × 38.8 × 17.7 | 10.2 × 27.2 | **überschreitet bewusst** (der Stich verlässt den Slot für 0.3 s) |
| levelup | 18.1 × 33.9 × 19.3 | 12.7 × 23.8 | bewusst (Zeremonie) |
| awaken | 23.5 × 38.9 × 24.1 | 16.4 × 27.2 | bewusst; 1st-Person max 23.3 px ≈ 1.46 Blöcke ⇒ nie im Gesicht |
| stall | 7.8 × 22.0 × 7.8 | 5.5 × 15.4 | KLEINER als idle — das Verschlucken zieht zusammen ✓ |

## 6 Funde (Bugs/Gefahren — teils behoben, teils Meldung)

### 6.1 `eclipse_wand.py` hat bei jedem Lauf finale Kunst überschrieben (BEHOBEN)

Der Wand-Painter emittierte historisch auch `textures/item/wizard_catalyst.png`. Die
committete Datei ist aber inzwischen ERSETZTE Final-Kunst: **168 von 256 Pixeln**
weichen vom Generator-Output ab (per PIL gegen `git show HEAD` verglichen). Mein
Pflicht-Painter-Lauf hat sie deshalb zunächst geclobbert — per `git checkout` auf den
Commit-Stand restauriert und `paint_catalyst()` auf **opt-in `--catalyst`** umgestellt
(AGENTS.md-Gesetz: Pixel-Icons sind finale Kunst). **Warnung an alle Teams:** wer den
Wand-Painter vor diesem Fix laufen ließ, prüfe `wizard_catalyst.png` im eigenen Diff.

### 6.2 `docs/uv/eclipse_wand.md` fehlte komplett

Das AUSGEBAUTESTE Item hatte als einziges GeckoLib-Asset mit eigenem Painter keine
UV-Doku (§6.4 Schritt 5). Jetzt angelegt (volle UV-Tabelle, Art-Brief, Emissiv-Regeln,
Kipp/Spin-Trennungs-Hinweis).

### 6.3 Display-Transforms: „prüfen" ergab „nicht anfassen"

Der GUI-Fußabdruck des Ruhezustands ist durch den Scale-0-Pin exakt der Ship-Stand;
jede Transform-Änderung hätte NUR Risiko gebracht. Die rechnerische Prüfung (§5) ist
der Beleg, dass die 0.7er-GUI-Scale + [0,−3.2,0]-Translation den 22.3-px-Stab weiterhin
in den Slot setzt.

### 6.4 Merksatz: One-Shot-Rotationen auf idle-rotierenden Bones poppen ZWEIMAL

Beim Kanal-Design gefunden: Action-Übernahme UND -Rückgabe springen auf den laufenden
idle-Molang-Winkel (Transition 0). Deshalb (a) One-Shot-Rotationen bevorzugt auf
idle-unberührte Bones legen, (b) auf geteilten Bones nur Scale/Position anfassen,
(c) Spin-Akzente auf exakt 360°-Vielfachen enden lassen (nicht bloß 90°-symmetrisch —
das prozedurale Textur-Grain unterscheidet die Faces!). Erst-Entwurf endete
`riss_ring` bei 270° / `p_stern_s2` bei 450° / `knot` bei 180° — alle drei auf 360°
umgestellt (Polish-Pass 1).

## 7 FX-Spec-Wünsche an W13-A1/A2 (NUR Spec — keine `.fx`/Rows angefasst)

Timing-Anker, alle relativ zum server-seitigen `triggerWandAnim`-Tick (GeckoLib-Sync
und FxCue reisen im selben Tick-Fenster):

| Beat | Zeit | Wunsch |
|---|---|---|
| use_glut Schlag-Frame | **0.18 s** | Falls die Muzzle-Cues (`CUE_WANDFX2_MUZZLE`) je einen Anim-Sync-Modus bekommen: Glut-Muzzle um ~3–4 t verzögern, dann sitzt der Flash auf dem Peitschen-Impact statt auf dem Klick |
| use_riss Yank-Frame | **0.14 s** | dito ~3 t; optional Mini-Implosion (einwärts, violett) am `tip`-Bone — die Krone kontrahiert exakt dort |
| use_stern Thrust-Apex | **0.20–0.34 s** | Halte-Beat; ein kurzer Aufwärts-Streak ab `tip` würde die Staffelung der `glow_stern_p1..4` (+2.4…+3.6 px, 0.16–0.28 s) verlängern |
| stall Schluck | **0.28 s** (`knot`-Bulge), 0.38 s (`handle_wrap`) | Wunsch: winziger „Choke"-Puff (2–3 dunkle Partikel, abwärts) auf dem Schluck-Beat — aktuell trägt nur das Amethyst-Chime (0.5-Pitch) den Fail |
| awaken Klimax | **0.9 s** | KEIN neuer Wunsch — bewusst auf den bestehenden D11-`SOULBIND_FLASH`-Tick gelegt; bitte den 18-t-Schedule in `handleChoosePath` nicht verschieben, ohne mir Bescheid zu geben |
| levelup Ring-Fenster | **0.15–1.05 s** | optional: kleine Funken-Lane am Bone `glow_cere_ring_a` (steigt +2 px, 720°-Spin) |

Bone-Anker für Entity-/Model-Lanes: `tip` (Spitze), `cere_anchor` (Zeremonie-Zentrum,
NUR während levelup/awaken sichtbar), `glow_cere_ring_a/b`, `knot` (Schluck-Punkt).

## 8 Test-Rezept (Client-Sichtprüfung)

Vorbereitung: `/give @s eclipse:eclipse_wand`, Rechtsklick → Pfadwahl (spielt direkt
`awaken` — Klimax muss auf dem weißen Flash landen!). `/dev wand set … path <pfad>`
für die anderen Varianten.

1. **Pro-Pfad-Cast:** je Pfad Rechtsklick-Cast — Glut peitscht (Welle läuft durch den
   Schaft), Riss ruckt zum Spieler (Krone kontrahiert/schnappt), Stern sticht nach oben
   (Scheibe spint auf, Sterne staffeln). First- UND Third-Person prüfen.
2. **stall:** Ladung leeren (casten bis `no_charge`-Meldung) und weiterklicken —
   Spitze+Krone werden eingesaugt, Schluck-Bulge wandert knot→Wicklung abwärts,
   schwacher Sputter. Mehrfach spammen: kein Hänger, kein End-Blitzer.
3. **levelup:** Tree-Node kaufen bis Level steigt — Doppel-Ring-Zeremonie mit
   Orbit-Fragmenten; danach darf NICHTS von der Zeremonie stehenbleiben (Scale-0-Pin).
4. **awaken/Rebirth:** `/dev`-Rebirth-Pfad — 2-s-Zeremonie, Ringe entschweben oben.
5. **Idle ≥ 16 s** pro Pfad ansehen (Loop-Naht bei 8 s unsichtbar; knot/wrap-Sway,
   Scherben-Atmen bzw. Stern-Twinkle sichtbar) + GUI-Slot-Check (Ruhezustand wie bisher).
6. **Log-Check:** keine Missing-Asset-Zeilen für `eclipse_wand` (Anim-Ids
   `animation.eclipse_wand.use_riss/use_glut/use_stern` müssen auflösen).
