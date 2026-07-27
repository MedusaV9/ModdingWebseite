# CREDITS V3 — F-072 Status ("Verbessere die Credits-Szene noch weiter … und die ganze Cutscene noch viel mehr")

Dritter Polish-Pass über die Credits-Sequenz (nach V1 und V2/F-068). V3 fügt NEUE
Dimensionen hinzu — nichts aus V2 wurde wiederholt. Alle Änderungen sind
deterministisch (stateless-push law), budget-neutral bei den Displays (kein einziges
Display mehr als V2) und im Shader durch `Detail`/Early-Outs abgesichert.

## Was verbessert wurde (vorher → nachher)

### 1. Schwarzes Loch physikalischer + dramatischer (`black_hole.fsh`)
- **Photonen-Ring-Substruktur** — Vorher: ein weicher Ring-Glow. Nachher: zusätzlich
  ein rasiermesserdünner ECHTER Einstein-Ring bei `1.32·coreR` mit umlaufenden
  Noise-"Beads" (Knoten gelinsten Lichts, Doppler-beamed), der auf Schluck-Pulse hart
  aufflammt.
- **Gelinstes Hintergrund-Sternfeld** — Vorher: keins. Nachher: prozedurale Sterne
  werden am QUELL-Radius einer Punktlinse gesampelt (`r_src = r − 1.35·coreR²/r`) —
  mit wachsender Strength wandern sie sichtbar auf Bögen nach außen, nahe am Ring
  werden sie tangential zu Einstein-BÖGEN verschmiert, eine 1/r-Differentialrotation
  lässt das nahe Feld auf seinen Orbits kriechen. Detail-gated + fenster-begrenzt.
- **Akkretions-Hotspots** — Vorher: zwei statisch schimmernde Bänder. Nachher: zwei
  helle Knoten reiten die Bänder auf inkommensurablen Orbits, flackern auf langsamen
  kubierten Sinus-Uhren auf und verschmieren in eine breite NACHLAUFENDE Keule
  (Leading-Edge scharf, Wake lang).
- **Polare Jets** — Vorher: keine. Nachher: zwei gegenläufige Leuchtsäulen entlang der
  kleinen Disc-Achse, erst ab der 0.7-Intensitätsstufe eingeblendet (`smoothstep` auf
  Strength), mit auswärts wandernden Puls-Knoten, langsamem Schwanken und
  Doppler-hellem oberen Jet. Geschert statt rotiert — 1 mad()/Pixel.
- **Ereignishorizont-"Atmen"** — Vorher: statischer Kernradius + Noise-Wobble.
  Nachher: neue `Pulse`-Uniform (0..1 Gulp-Envelope) schwillt den Kernradius +5 % an
  und flammt Haupt-Ring, Sub-Ring, Disc-Glow und Jets auf — das Loch HEBT sich
  sichtbar, wenn es schluckt.

### 2. Server→Shader-Puls-Leitung (neu)
- `CreditsPayloads.S2CCreditsPulsePayload` (float strength; Payload-Versionsgruppe auf
  `credits2` gebumpt, da auch das Title-Payload seine Form änderte) →
  `CreditsSkyFx.handlePulse/holePulse` (3t Attack / 15t Decay, smoothstep; stärkerer
  laufender Puls wird nie von einem schwachen abgeschnitten) →
  `CreditsBlackHolePostFx` füttert die `Pulse`-Uniform pro Frame.
- `CreditsSequence.devourPulse` (die deterministischen Schluck-Momente) sendet den
  Puls jetzt MIT — Shader-Atmen und Shockwave/Blink/Thump landen auf demselben Tick.

### 3. Infall-Dramaturgie (`CreditsBlackHoleAct`)
- **Hitze-Glühen vor dem Schlucken** — ab 78 % des Falls IGNITED jedes Fragment:
  Block-State-Swap auf Magma (25 % Shroomlight-Akzente, gehasht) + Full-Bright
  (15/15); beim Recycle-Wrap zurück zum echten Terrain-Block mit sofortigem
  Doppler-Relight. Nur Kanten-Trigger — kein NBT-Verkehr pro Push.
- **Gezeiten-Filamente** — das per-Member-Arc-Trailing weitet sich über das
  Spaghettisierungs-Fenster (+0.34 rad/Member): ein Tear-off-Cluster zieht sich
  sichtbar zu einem glühenden Spiralfaden auseinander, statt als Klumpen zu fallen.
- **"Letzte Blitze"** — `horizonFlash`: zweite, dichtere deterministische Flash-Uhr
  (Periode 47t, gejittert, Stärke 0.10–0.26) zwischen den großen Gulps; die Sequenz
  leitet sie als REINE Client-Pulse weiter (Ring-Flackern ohne Shockwave/Thump).

### 4. Kamera & Timing (`CreditsSequence`)
- **FOV-Beat-Map** — Vorher: zwei Atem-Wegpunkte. Nachher: vier (0.275 → 0.255 →
  0.235 → 0.215, je 360t geeased) — Pull-back, Settle, zweiter Atem, dann langsamer
  DOLLY-PUSH ins Loch, während der Devour peakt; der DARK-Beat (0.4) ist der
  antwortende finale Pull-Back.
- **Ambient-Tremor** — durchgehendes, kaum spürbares Beben (0.06→0.12 mit dem
  Devour-Fortschritt, alle 80t lückenlos nachgelegt): die Realität selbst steht nicht
  mehr still. (Bewusst KEIN Dauer-Handheld-Drift über das Shake-System — dessen 9-Hz-
  Grundfrequenz liest sich bei Dauerbetrieb als Zittern, nicht als Drift.)

### 5. Weltall-Atmosphäre
- **`credits3_nebula`** (neu, `tools/photon/credits3_fx.py`) — riesige, fast statische
  Nebel-Schwaden mit Flüster-Alpha auf einer 55–80-Block-Schale um den Maw-Anker
  (rahmen die Disc, matschen sie nie zu) + VIER dezente Sternschnuppen pro
  Re-Fire-Fenster (gestreckte Streaks, tangential skimmend). Reitet die
  Maw-Kadenz (300t, Dedup) — nahtlos.
- **Ergrauen als stetige Kurve** — Vorher: 4 Intensitätsstufen + lineares Grau im
  Shader. Nachher: SECHS Stufen (0.45/0.56/0.68/0.8/0.91/1.0) mit 260t-Client-Ramps
  (die sich überlappen) + geeaste Grau-Kurve im Shader — ein durchgehender Slope,
  keine sichtbare Stufe mehr.

### 6. Typografie-Finale (`TitleCardLayer` + `CreditsPayloads`)
- Titel-Payload trägt jetzt `style` (DECODE / GENTLE / FINALE) statt `boolean gentle`.
- **FINALE-Stil** (nur der "Minecraft Eclipse"-Closer, `beatFinaleTitle` →
  `sendFinaleTitle`): jeder Buchstabe MATERIALISIERT auf eigener gestaffelter Rampe
  (4t Stagger, 34t Ramp, ~4 px Aufstieg), während 3 goldene Staub-Motes pro Buchstabe
  hineinspiralen und verglühen; das Tracking startet 2.8 px weit und ATMET EIN
  (danach ±0.3 px Rest-Atem); ein chromatischer Saum (rote/blaue Ghost-Passes,
  1.6 px) BERUHIGT sich über 130t auf null; die Gold-Hairlines erscheinen erst, wenn
  die Zeile ruht; das Fade-out sinkt zurück ins gehaltene Schwarz. `reducedFx` lässt
  Motes + Saum weg, behält Stagger + Kerning-Ease. Sub-Pixel via Float-Translate im
  skalierten Pose-Stack.
- Die mittleren End-Cards (RETURNS/NEXT/Maker) behalten bewusst den GENTLE-Stil.

### 7. Shatter-Feinschliff (`CreditsSequence` + `credits3_precrack`)
- **Vorriss-Phase** — neuer Beat t=70 (50t VOR dem Bruch, exakt gegen die authorte
  Build-up-Gradiente): `credits3_precrack` (Riss-Glühen flach über der Insel, feiner
  Staub RIESELT von der Unterseite, zwei Seam-Pops) + niedriger Dauer-Tremor (0.14)
  + leise tiefe Steinknacke (Deepslate + fernes Grollen). Erst Dread, DANN der Bruch.
- **See-Schockwelle** — 26t nach dem Bruch erreicht der Impuls das Wasser: ein
  breiter Shockwave-Ring (0.7, 34) auf Meereshöhe unter der Insel + tiefer
  Wasser-Schlag. Signatur bleibt unter der (1.0, 50)-Giant-Naht.
- **Versammlungs-Sog** (`CreditsFormationAct.gather`) — jedes Formations-Element wird
  1.45× JENSEITS seines Slots geboren (± 0.35 rad Swirl um die Blickachse) und über
  seine ersten 90t auf einer Smootherstep-Kurve auf den Slot GESOGEN (sanfter Start,
  entschlossener Rush, weicher Catch). Steady-State ist bit-identisch zur reinen
  Formations-Pose — Re-Pushes bleiben konsistent.

### Replay-Parität (`/eclipsefx sequence credits <PHASE>`)
- `SHATTER`: Vorriss-Veil + Tremor sofort, Collapse-Paket 50t später (Live-Dramaturgie).
- `BLACKHOLE`: Nebula-Cue + ein Sample-Gulp-Puls (0.7) nach 160t zusätzlich.

## Geänderte / neue Dateien
- `src/main/resources/assets/eclipse/pinwheel/shaders/program/black_hole.fsh` (V3-Layer)
- `src/main/java/.../network/credits/CreditsPayloads.java` (Pulse-Payload, Title-Style, Version `credits2`)
- `src/main/java/.../client/credits/CreditsSkyFx.java` (Gulp-Envelope)
- `src/main/java/.../client/credits/CreditsBlackHolePostFx.java` (Pulse-Uniform-Feed)
- `src/main/java/.../client/credits/TitleCardLayer.java` (FINALE-Materialize-Stil)
- `src/main/java/.../ritual/CreditsBlackHoleAct.java` (Heat-Swap, Filamente, horizonFlash)
- `src/main/java/.../ritual/CreditsFormationAct.java` (Versammlungs-Sog)
- `src/main/java/.../ritual/CreditsSequence.java` (Vorriss-Beat, See-Schockwelle, 6-Stufen-Leiter, FOV-Beat-Map, Tremor, Pulse-Sends, Finale-Titel, Replay-Parität)
- `src/main/java/.../veilfx/CreditsFinale3FxRows.java` (NEU — Client-Row-Registrar, self-subscribing; `FxCues`/`EclipseMod` unangetastet)
- `tools/photon/credits3_fx.py` (NEU — Generator) + generierte Assets
  `assets/eclipse/fx/credits3_precrack.{fx,fxproj}`, `credits3_nebula.{fx,fxproj}` (validiert)

**Nicht angefasst** (Shared-Files-Regel): `EclipseMod.java`, `FxCues.java` (Cue-Ids via
`FxCues.cue(...)` lokal abgeleitet), `EclipsePayloads.java`, lang-Dateien,
`sounds.json`. **Kein Langdrop nötig** (kein neuer Text — der Finale-Titel nutzt den
bestehenden `eclipse.credits.end.title`), **kein credits3_sounds.json nötig** (nur
Vanilla-Sounds: `DEEPSLATE_BREAK`, `GENERIC_EXPLODE`, bestehende Thunder/Portal-Cues).

## Offene Punkte
- Der Netzwerk-Versions-Bump (`credits1` → `credits2`) trennt alte Clients sauber ab —
  gewollt, aber erwähnenswert für Modpack-Updates (Client und Server müssen zusammen
  aktualisiert werden).
- Handheld-Kamera-Drift bleibt bewusst außen vor (das Shake-System exponiert keine
  Frequenz über das Payload; ein eigener Drift-Kanal wäre ein Shared-File-Edit).
- Beat-genaue Synchronisation auf die `victory_theme`-WELLENFORM ist serverseitig
  nicht möglich (nur die eingefrorene Dauer, 3600t, ist im Code verfügbar); die
  FOV-/Gulp-Uhren sind stattdessen auf die Akt-Struktur gelegt.
- Die Hotspot-/Jet-Parameter sind auf die 0.55-Disc-Squash der Displays abgestimmt;
  falls die Disc-Geometrie im Act geändert wird, `discP`-Skalierung (1.72) mitziehen.

## Testanleitung (`/dev`, permission 2)
1. `/dev credits start` — volle Sequenz. Prüfen:
   - **t≈70** (direkt nach dem ersten Reveal): Riss-Glühen + rieselnder Staub +
     leises Knacken VOR dem Bruch; **t≈146**: Schockwellen-Ring über dem Wasser.
   - **Formation-Aufbau** (nach dem Beach-Reveal): Elemente werden sichtbar
     ANGESAUGT statt einfach einzublenden.
   - **Black-Hole-Finale** (t≈3720+): Einstein-Sub-Ring mit Beads; Sterne wandern
     auf Bögen um das Loch; zwei Hotspots flackern/schmieren auf den Disc-Bändern;
     ab ca. der Mitte zünden die polaren Jets; bei jedem Schluck-Moment schwillt der
     Horizont an und die Ringe flammen (zwischen den Gulps: kleine Ring-Flacker);
     Fragmente GLÜHEN magma-orange kurz vor dem Verschwinden und ziehen sich zu
     Spiralfäden; Nebel-Schwaden + seltene Sternschnuppen im Hintergrund; das
     Ergrauen läuft als eine durchgehende Kurve; dezenter Dauer-Tremor; FOV atmet
     und drückt am Ende langsam hinein.
   - **Titel** (t≈5200): "Minecraft Eclipse" materialisiert Buchstabe für Buchstabe
     aus Gold-Staub, Kerning atmet ein, Farbsaum beruhigt sich.
2. `/dev credits skip` — springt zum Outro; Finale + Hold laufen normal weiter.
3. `/dev end_event` — löst die Haltephase (auch mitten im Finale: Cleanup-Check).
4. FX-only-Proben ohne Weltzustand: `/eclipsefx sequence credits SHATTER` (Vorriss →
   Collapse-Abfolge) und `/eclipsefx sequence credits BLACKHOLE` (Nebula + ein
   Sample-Gulp nach 8 s).
5. `reducedFx`-Gegenprobe: Shader fällt auf den billigen Kern zurück (kein Sub-Ring,
   keine Jets/Hotspots/Sternfeld), Titel ohne Motes/Saum — beides darf nicht leer
   aussehen (Ring + Stagger bleiben).

## Risiken
- **Shader-Kosten**: alle neuen Layer sind `Detail`-gated und/oder fenster-begrenzt
  (`starWin`/`jetGate`/Band-Guards mit Early-Out-ifs); der teuerste neue Pfad
  (Sternfeld) ist ein einzelner Zell-Hash ohne Loop. Auf `reducedFx` ist V3 im
  Shader ein No-op gegenüber V2.
- **Display-Budget unverändert**: Heat-Swap/Filamente sind reine State-/Pose-Mathematik
  auf den BESTEHENDEN 840 recycelten Displays; der Sog auf den bestehenden 1800
  Formations-Displays. Neue NBT-Writes nur an Kanten (2 pro Fragment-Zyklus).
- **Photon-Budget**: `credits3_nebula` ≤48 zusätzliche Partikel (40 Swaths + 8
  Streaks) auf dem AMBIENT-Kanal; `credits3_precrack` ≤164, einmalig, 70t.
- **Determinismus**: alle neuen Uhren (Heat, Filament, Flash, Sog) sind reine
  Funktionen von (index, actTick) mit `CreditsSequence.hash01` — Re-Pushes und
  Late-Joins bleiben konsistent; der Pulse ist fire-and-forget (verlorenes Paket =
  ein ausgelassenes Flackern, nie Drift).
