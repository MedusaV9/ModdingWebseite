# IDEEN-IMPROVER E — Stadt & Orte, Reise-Cutscene, Taxi/Guber/GOOBERANDO

Godot 4.4 · Referenz: `/workspace/GOOBY` · USER-WISHES §E (Zeilen 54–61) + §C37 (Taxi-Live-Activity)
Asset-Basis GEPRÜFT (Verzeichnis-Listing, nicht geraten):
`kenney/car-kit` (taxi.glb, **delivery.glb**, van, suv, sedan, sedan-sports, hatchback-sports,
police, race, truck, wheel-*, cone, box), `city-kit-roads` (straight/bend/intersection/crossroad/
crossing **+ bislang UNGENUTZT: roundabout, curve, end, end-round, square, straight-half,
sign-highway, light-curved**), `city-kit-commercial` (building a–h, skyscraper a/b, low-detail a–f,
detail-awning[-wide]), `city-kit-suburban` (**nur** Zäune/Wege/planter/Bäume — KEINE Wohnhäuser!),
`nature-kit` (37), `food-kit` (**70 GLBs** — Obst/Gemüse/Fertiggerichte), `minigolf-kit`
(windmill, castle), `kaykit-city` (streetlight, bench, hydrant, dumpster, trash, box, building A–F),
`kaykit-restaurant` (fridge_A, oven, kitchencounter_*, crates, menu, table, jars),
`itch/tinytreats-*` (bakery-interior, pretty-park …). Blender 4.0.2 auf der VM.

Web-Referenz-Code: `src/city/cityBuilder.js` (9×9-Grid, TILE_M=20, pures Layout-Modul),
`carController.js` + `carFeel.js` (τ=120 ms Steer-Lowpass, 90°/s Yaw-Cap, Lane-Assist-Feder,
Chase-Cam k=4.0/s, FOV 55→60, Wedge-Watchdog), `traffic.js` (Loop-Follower, 70%-Hitbox),
`systems/vacation.js`+`postcards.js` (Phasen NONE/AWAY/RETURN_READY/OVERDUE, Postkarten-Archiv
Cap 36, souvenirCoins, `visited`-Sammelpass), `data/vacations.js` (9 Ziele).

Querverweise: **A** (SceneRouter/LoadingVeil, Raum=Szene, Tür-System §F), **C** (`gooby_notify`
lokale Notifications M1, ActivityKit M2 — Taxi-Zeiten sind vorab bekannt), **D** (Grid-Bau,
LKW-Lieferung, IKEA-3D-Ausstellung — ich designe hier nur GEBÄUDE + BETRETEN des IKEA).

---

## 1. Stadt 2.0 — Karte, Distrikte, freie Fahrt

### 1.1 Grundentscheidungen

- **Grid bleibt das Datenmodell** (bewährt, pur, testbar): 20-m-Tiles, aber **15×12 statt 9×9**
  → 300×240 m, ~2,7× Fläche. Layout wird **fest geauthort** (kein Seed mehr für Straßen/Orte —
  Spieler sollen die Stadt AUSWENDIG lernen wie ein Dorf in Animal Crossing); Seed variiert nur
  noch Deko (Bäume, Props, Zebrastreifen).
- **Straßen-Lattice statt Ring+Kreuz:** Vertikal-Straßen in Spalten 1/6/10/13, Horizontal in
  Reihen 1/4/7/10 → 9 Super-Blöcke à 2–4 Tiles = Distrikte. Zwei **Kreisverkehre**
  (`road-roundabout.glb`, bisher ungenutzt!) an den Hauptknoten (1,6) und (7,10) als Landmarken
  und weil Kreisel fahren Spaß macht.
- **Distrikte:** Wohnen (SW+SE), Zentrum (Mitte), Gewerbe (Nord), Park (S-Mitte),
  Flughafen-Zubringer (N-Rand, eigene Vorfahrt außerhalb des Lattice).

### 1.2 Stadtplan (ASCII, 15 Spalten × 12 Reihen)

```
Legende:  . Gras/Bäume   # Straße   ◎ Kreisverkehr   = Flughafen-Zubringer
          F Flughafen-Terminal   f Tower/Vorfeld   I IKEA-Großladen   B Baumarkt
          C Autohaus   R REHWEI   A GOOBYTHEKE   D Dr.…GOOUHBUS-Praxis   P POW!
          O Post   W Wochenmarkt-Platz   * Brunnen-Plaza   K Funkelpark-Tor
          H Spieler-Haus (+Garten §D)   h Nachbar-Goobys   G GOOBERANDO-Küche

        c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14
  r0     .  .  f  F  F  f  .  .  .  .  .   .   .   .   .     ← Flughafen (Sackgasse)
  r1     .  #  #  #  =  #  ◎  #  #  #  #   #   #   #   .     ← Nord-Avenue + Zubringer (c4↑)
  r2     .  #  I  I  .  .  #  B  B  .  #   C   C   #   .     ← GEWERBE
  r3     .  #  I  I  .  .  #  B  .  .  #   .   C   #   .
  r4     .  #  #  #  #  #  #  #  #  #  #   #   #   #   .     ← Mittel-Avenue
  r5     .  #  R  R  .  G  #  *  .  P  #   O   .   #   .     ← ZENTRUM
  r6     .  #  A  A  .  .  #  W  W  .  #   D   D   #   .
  r7     .  #  #  #  #  #  ◎  #  #  #  #   #   #   #   .     ← Süd-Avenue
  r8     .  #  h  .  h  .  #  .  K  K  #   h   .   #   .     ← WOHNEN + PARK
  r9     .  #  H  .  h  .  #  K  K  K  #   h   h   #   .
  r10    .  #  #  #  #  #  #  #  #  #  #   #   #   #   .     ← Süd-Ring
  r11    .  .  .  .  .  .  .  .  .  .  .   .   .   .   .
```

Wege (Gefühl): Haus (r9,c2) → REHWEI = 1 Block hoch, sofort links — der „Brötchen-holen-Weg".
Flughafen = einmal quer durch die ganze Stadt (Reise fühlt sich nach Aufbruch an). Park-Tor
liegt gegenüber vom Wohnviertel (Feierabend-Runde). GOOBERANDO-Küche (G) sichtbar im Zentrum —
man kann dem eigenen Liefer-Fahrer real entgegenfahren (die Simulation läuft auf demselben
Straßengraphen, §5.2).

### 1.3 Freie Fahrt (ersetzt die festen Routen)

- Kein `ROUTE_TILES` mehr. Stattdessen `road_graph.gd`: Knoten = Straßen-Tiles, Kanten =
  Nachbarschaft; **A\*** liefert Pfade für (a) optionalen GPS-Pfeil, (b) Traffic-Ziele,
  (c) GOOBERANDO-Fahrer-Simulation. Pure RefCounted-Klasse, GUT-testbar ohne Szene.
- **Energie-Regel (User-Wunsch):** Fahren kostet NICHTS. Erst beim Einparken in einen
  Parkplatz-Trigger (Area3D am Ort) kommt der Bestätigungs-Prompt:
  „REHWEI betreten? (−5 ⚡)" → Ja = Abzug + Szenenwechsel; Nein = weiterfahren, kein Abzug.
  Kostentabelle (flach, im Ort-Katalog): Zentrum-Orte 4 ⚡, Gewerbe 5 ⚡, Park 6 ⚡,
  Flughafen 6 ⚡, **nach Hause 0 ⚡**. Bei zu wenig Energie: Prompt bietet direkt
  „🚕 Taxi rufen" an (§4).
- **„Nach Hause"-Knopf:** Haus-Icon dauerhaft im Fahr-HUD (oben rechts, neben Pause).
  Tap → 0,5 s Fade → Auto steht in der Einfahrt (r9,c2), Gooby steigt aus. Kostenlos,
  keine Bestätigung (es ist ein Fluchtknopf — er muss reibungslos sein).
- **Ziel-Wahl:** Stadtkarte (2D-Minimap, §5.2) über HUD-Knopf; Pin antippen → GPS-Pfeil
  (3D-Pfeil überm Auto + Breadcrumb-Punkte auf der Straße, abschaltbar in Settings).
- **Haupt-UI-Umbenennung (Wunsch Z. 58):** Der alte „Laden"-Knopf heißt jetzt **„Reise"**
  und öffnet: [Losfahren 🚗] [Stadtkarte 🗺] [IGohbie 📱].

### 1.4 Fahr- & Kamera-Design in Godot

Das Web-Fahrgefühl ist gut abgestimmt und wird **zahlengleich portiert** — `carFeel.js` ist
pure Mathematik, wird 1:1 `car_feel.gd` (statische Funktionen + `FEEL`-Konstanten-Dictionary,
GUT-Tests portieren die node:test-Fälle):

- Auto = `CharacterBody3D` mit eigener Integration (KEIN VehicleBody3D — wir wollen arcade,
  deterministisch, kein Physik-Tuning-Fass): Heading + Speed wie im Web
  (Auto-Throttle 9→13 m/s Ramp, Steer-Lowpass τ=120 ms, Yaw-Cap 90°/s, Lane-Assist-Feder
  max 8°/s mit Fade bei 25° Intent / 40 % Deflection). `move_and_slide()` übernimmt die
  Kollision (ersetzt die Hand-AABBs; Gebäude = StaticBody3D-Boxen aus dem Layout).
- **Wedge-Watchdog** (F4 P1-1) mitnehmen: 2,6 s Stillstand bei Throttle → Rettung; in der
  freien Fahrt NEU: statt Event einfach **Rückwärtsgang** — Godot-Version bekommt einen
  Rückwärts-Knopf (Brake gedrückt halten bei Stillstand = langsam rückwärts). Löst 90 % der
  Verkeil-Fälle spielerisch.
- Chase-Cam: eigenes `chase_cam.gd` (damped follow k=4,0/s, 6 m Look-Ahead, FOV 55→60,
  kein Roll) + `SpringArm3D` NUR als Clip-Schutz gegen Gebäude (Wunsch §A „Kamera-Clipping
  vermeiden"). Bei Rückwärtsfahrt: Kamera bleibt vorn (kein Umschwenken — Übersicht).
- **Spieler-Auto = Autohaus-Auto:** `CarDef`-Resource `{id, glb, preis, max_speed, accel,
  steer_rate, farben[]}` — Startwagen `sedan` (9→13 m/s), Kaufbare: `hatchback-sports`
  (10→15), `sedan-sports` (10→16, teuer), `suv` (8→12, gemütlich+breit), `race` (Endgame).
  Farbwahl = Material-Tint auf dem Karosserie-Mesh. **Dieselben CarDefs speisen die
  Fahr-Minispiele (§G-Wunsch)** — Contract mit dem Games-Improver: `GameState.aktives_auto`.
- Steuerung: Touch-Zonen links/rechts + Brems-/Rückwärts-Knopf unten Mitte (wie Web,
  §G3.1-Vorzeichen-Kontrakt übernehmen: rechts halten = Bildschirm-rechts lenken);
  Hoch- UND Querformat (Zonen sind relative Hälften, funktioniert in beiden).
- **Hupe!** Kleiner Knopf neben Bremse: „HONK" — Fußgänger-Goobys hüpfen erschrocken,
  Traffic-Goobys hupen zurück. Reiner Charme, 20 Zeilen.

### 1.5 Verkehr & Ambiente

- Traffic 2.0: 10–14 car-kit-Autos, aber statt geauthorter Loops: **Wander-Agenten** auf dem
  Straßengraphen — an jeder Kreuzung zufällige erlaubte Abbiegung (Rechtsverkehr,
  Spur-Offset 2,5 m wie Web). Skaliert automatisch mit der größeren Karte, null
  Loop-Authoring. Forgiving 70 %-Hitbox + Near-Miss-Funken (aus `traffic.js` portieren).
  Crash = §C4.5-Bump (30 % Speed, Recovery) — KEIN Energie-/Münzverlust in der freien Fahrt.
- **Fußgänger:** 4–6 Mini-Goobys auf Gehweg-Splines (Sidewalk-Offset 6,5 m), winken wenn
  man langsam vorbeifährt, hüpfen bei Hupe. Ein `MultiMeshInstance3D` + einfacher
  Waddle-Bone reicht.
- Tag/Nacht (Sync mit `dayNight`-System): DirectionalLight-Kurve; nachts Streetlight-Emissive
  an + warme Fenster-Emissive-Textur auf Gebäuden; Godot-Postprocessing: leichtes Bloom
  (Wunsch §A/§G) + dezenter DoF auf Distanz.
- Ambient-Audio: Distrikt-Crossfade (Zentrum: Gemurmel+Möwen?, Wohnen: Vögel, Gewerbe:
  Baustellen-Pling, Flughafen: Turbinen-Wusch alle ~90 s).
- Performance-Regel: ALLE Wiederhol-Assets (Bäume, Laternen, Props) über MultiMesh; Gebäude
  einzeln (brauchen Collider), aber geteilte Materialien (Kenney-Atlas) → Ziel < 120 Draw
  Calls für die ganze Stadt.

---

## 2. Orte als betretbare Szenen — das „Ort"-Framework

### 2.1 OrtScene-Basisklasse

```
res://orte/_base/
  ort_scene.gd          # class_name OrtScene extends Node3D
  ort_scene.tscn        # Basis: Camera-Rig, ExitDoor(Area3D), NpcSlots, LichtSetup
  ort_katalog.gd        # Ort-Registry: id → {szene, name, energie_kosten, parktile, oeffnungszeiten?}
  haendler_ui.tscn/.gd  # generisches Shop-Panel (Warenliste = Array[WareDef], Kauf-Signal)
  dialog/
    dialog_runner.gd    # Dialogbaum-Interpreter (JSON, §2.2)
    text_bubble.tscn    # Sprechblase: RichTextLabel, Typewriter, Tail zum Sprecher
    gebrabbel.gd        # AC-Gebrabbel: Vokal-Samples, pitch = f(zeichen) + sprecher_basis
```

- Lebenszyklus: `betreten(ctx)` (vom SceneRouter/A nach LoadingVeil gerufen; ctx = woher,
  Tageszeit, aktive Quest-Flags) / `verlassen()` (Tür-Area ODER X-Knopf → Router zurück zur
  Stadt, Auto steht noch am Parkplatz).
- Interieur-Bauweise: kleiner Raum (6×8 m), fixe ¾-Kamera mit ±10° Touch-Orbit, Boden/Wände
  aus einem gemeinsamen `ort_interior_kit` (Blender, §6), Möblierung aus kaykit/kenney.
  Gooby läuft per Tap-to-Move (NavigationRegion3D klein, kein Rebake nötig — statisch).
- Händler-UI: einheitlich für REHWEI/GOOBYTHEKE/POW!/Baumarkt/Wochenmarkt — Warengrid
  (Icon, Name, Preis), Detail-Popup, Kaufen-Knopf; Waren-Icons: 3D-Preview via SubViewport
  ODER beim Build vorgerenderte PNGs (Entscheid: **vorgerendert** — ein `scripts/render_icons.gd`
  CI-Schritt, spart Laufzeit-Viewports auf dem Handy).
- **Erste-Betreten-Bonus:** Jeder Ort gibt beim ersten Besuch einen Sticker (Sticker-Seite
  „Stadt", Wunsch §H) — motiviert die Erkundungs-Tour durch alle Distrikte.

### 2.2 Dialog-System

JSON-Dialogbäume (Content-Pack-fähig → §B-Updater kann neue Dialoge shippen!):

```json
{ "id": "doktor_besuch", "start": "hallo",
  "nodes": {
    "hallo": { "sprecher": "goouhbus", "text": "…", 
               "optionen": [ {"text": "…", "next": "diagnose", "cond": "gooby_krank",
                              "effekt": "give_item:rezept"} ] } } }
```

`dialog_runner.gd` ist pur (RefCounted, GUT-Test: jeder Knoten erreichbar, keine toten Enden).
Text-Bubbles: Typewriter 28 Zeichen/s, pro Zeichen ein Gebrabbel-Blip (kurze Vokal-Samples,
Pitch aus Zeichen-Hash + Sprecher-Basispitch: GOOUHBUS = 0,7× tief+langsam, REHWEI-Kassiererin
= 1,3× flott, Liefer-Gooby = 1,15× + leicht atemlos). Skip: Tap = Text sofort voll, 2. Tap = weiter.

### 2.3 Die Orte im Einzelnen

| Ort | Kern-Loop | NPC | Meilenstein |
|---|---|---|---|
| **REHWEI** | Lebensmittel kaufen (alle food-kit-Items als Waren!) | Kassiererin „Frau Rehwald" | M1 |
| **GOOBYTHEKE** | Medizin; „Gooby-Tropfen" NUR mit Rezept | Apothekerin „Hilde" | M1 |
| **Dr.Dr.Professor.Dr.Dr.GOOUHBUS** | Rezept-Flow, Check-up-Gags | der Doktor | M1 |
| **Flughafen** | Urlaub buchen, GOOBY-FREE-Shop, Cutscene-Start | Schalter-Gooby | M1 |
| **POW!** | Kamera kaufen (schaltet Fotomodus frei) + 3 Tagesangebote | Verkäufer „Bäm" | M2 |
| **Autohaus** | CarDefs kaufen, Farbwahl, Drehpodest, Probefahrt | „Gooberto Benzino" | M2 |
| **Post** | Briefe/Pakete (Multiplayer-Hook §C), Postkarten-Archiv | Postbotin | M2 |
| **Wochenmarkt** | NUR Samstag: Ernte verkaufen (§D-Garten), 4 Stände, Feilsch-Bonus | Markt-Goobys | M2 |
| **Baumarkt** | Materialien/Baupläne (§D-Werkstatt), Gabelstapler-Deko | „Bodo Balken" | M3 |
| **IKEA-Großladen** | Gebäude 2×2 Tiles + Parkplatz + Eingang/Kassen-Zone; die 3D-Ausstellung drinnen designt **Improver D** — Schnittstelle: `OrtScene` „ikea" lädt Ds Ausstellungs-Szene als Kind | — | M3 (Gebäude M1-Deko) |

- **Rezept-Flow (M1, der erste „Quest-Loop" des Spiels):** Gooby krank (health-System) →
  GOOBYTHEKE verkauft Hustensaft (leicht) frei, aber „Gooby-Tropfen" (heilt richtig krank)
  brauchen Rezept → Praxis → Dialogbaum → Item `rezept_tropfen` → zurück zur GOOBYTHEKE →
  Hilde-Dialog + Kauf. Zwei Orte, ein Loop, viel Charakter.
- **POW!-Tagesangebote:** 3 Slots, seeded aus Kalendertag (mulberry32(dateseed) — Rezept aus
  `postcards.js` übernehmen), −20/−30/−50 % auf Deko/Spielzeug-Pool; Countdown „Neu in 7 h!".
- **Wochenmarkt:** Platz W ist Mo–Fr leer (Schild: „Markt: Samstag! – Bitte nicht am Schild
  knabbern"). Samstags 4 Stände (Blender-Stand ×4 Farbvarianten), Verkaufs-UI mit
  +15 % Markt-Bonus auf Garten-Ernte, Händler-Gooby-Animationen (wiegen, einpacken, winken).

### 2.4 Dialog-Beispiele (DEUTSCH, Auszug aus den JSON-Bäumen)

**Dr.Dr.Professor.Dr.Dr.GOOUHBUS** (alter Doktor, drei Brillen, keine davon im Einsatz):

```
[hallo]  GOOUHBUS: „Herein, wenn's kein Vertreter ist! … Oh, ein Gooby. Setz dich aufs
         Bänkchen, ich suche nur kurz meine Brille."
         (Er trägt eine auf der Stirn, eine um den Hals und eine im Mund.)
   ├─ „Gooby ist krank."            → [diagnose]
   ├─ „Sind Sie wirklich 4× Doktor?" → [titel]
   └─ „Nur zum Check-up."           → [checkup]

[titel]  GOOUHBUS: „Dr. Dr. Professor Dr. Dr.! Zwei Titel in Medizin, einer in Käsekunde,
         und einen … habe ich im Aufzug gefunden. Der zählt moralisch."
         → zurück zu [hallo]

[diagnose] GOOUHBUS: „Krank? KRANK?! Das haben wir gleich. Zunge raus! … Das ist ein Ohr.
           Auch gut. Sag mal AAAAH."
           GOOBY: „Bleeeh~"
           GOOUHBUS: „Interessant. SEHR interessant. Ich habe keine Ahnung, was das bedeutet."
   ├─ „Er hat ein ganzes Glas Nutella gegessen."
   │    GOOUHBUS: „EIN Glas? Respekt. Ich habe als Student zwei geschafft. Trotzdem: REZEPT!"
   └─ „Er niest ununterbrochen."
        GOOUHBUS: „Niesen ist nur Applaus von innen. Aber sicher ist sicher: REZEPT!"

[rezept] (Er stempelt dreimal daneben, einmal auf die eigene Hand, dann aufs Rezept.)
         GOOUHBUS: „Damit gehst du zu Hilde in die GOOBYTHEKE. Und richte ihr aus,
         sie schuldet mir noch ein Käsebrot. Von 1987."
         → Item „Rezept: Gooby-Tropfen" · Dialog-Ende

[checkup] GOOUHBUS: „Kerngesund! Das Herz pumpt, die Ohren wackeln, der Rest ist Zubehör.
          Macht null Münzen. Berufsehre."
```

**GOOBYTHEKE (Hilde):**

```
HILDE: „Willkommen in der GOOBYTHEKE. Rezept oder Ratschlag?"
  ├─ [hat rezept_tropfen] „Rezept, bitte!" 
  │    HILDE: „Vom GOOUHBUS? Kann man das überhaupt lesen? … Ah. ‚Käsebrot'. 
  │    Der alte Gauner. Hier, die Gooby-Tropfen. Dreimal täglich, nicht auf die Möbel."
  └─ „Was hilft gegen Bauchweh?"
       HILDE: „Weniger Nutella. — Ich weiß. Ich sage es trotzdem jedes Mal."
```

**REHWEI (Frau Rehwald, Kassiererin):**

```
REHWALD: „Willkommen bei REHWEI! Heute im Angebot: alles, was rund ist."
Beim Bezahlen: „Sammelst du Treuepunkte? Nein? Ich auch nicht, ich erfinde sie nur gern."
Bei >10 Items: „Das wird ein Festmahl. Oder ein Dienstag. Bei Goobys weiß man nie."
```

**Autohaus (Gooberto Benzino, M2):**

```
BENZINO: „Dieses Schmuckstück? Null auf hundert in … irgendwann! Aber HÖR dir diese Hupe an."
Bei Probefahrt: „Zerkratz sie nicht! Haha! … Nein wirklich. Bitte nicht."
```

---

## 3. Reise-Cutscene NEU + der NUTZEN von Urlaub

### 3.1 Bestätigung + Warnung (vor der Cutscene)

Flughafen-Schalter → Ziel gewählt (9 Ziele aus `data/vacations.js` portieren: Preis,
Dauer 3–4 Realtage, souvenirCoins, Unlock-Level) → Modal:

> **„Gooby fliegt für 3 Tage ans Glitzermeer"** — Preis: 120 Münzen.
> ⚠️ Gooby ist solange NICHT zu Hause. Seine Werte sind eingefroren (das Resort kümmert
> sich um alles). Abholen nicht vergessen — sonst nimmt er das Taxi und DU zahlst.
> [Buchen ✈] [Doch nicht]

### 3.2 Shot-Liste (eigene Szene `cutscenes/reise_abflug.tscn`, ~30 s, Skip ab Sek. 2)

```
Shot 1 (4 s)  Flur, Hintertür: Tür-Animation aus §F/A wiederverwendet; Gooby zieht den
              neuen Rollkoffer (Blender-Prop), Koffer kippelt einmal um → er stellt ihn
              betont würdevoll wieder auf.
Shot 2 (6 s)  Garten/Einfahrt: Kamera-Dolly seitlich (Path3D), Gooby winkt ins Bild.
Shot 3 (8 s)  Bordstein: car-kit/taxi fährt mit Ease-in vor (Path3D), hält, Kofferraum-
              Node rotiert auf, Koffer hüpft rein (kleiner Bogen-Tween), Gooby steigt ein.
Shot 4 (6 s)  Stadt-Montage: 2 s Taxi auf der Mittel-Avenue (ECHTE Stadtszene, Kran-Kamera
              über dem Kreisverkehr — die Stadt spielt sich selbst vor), Wipe.
Shot 5 (6 s)  Flughafen-Vorfahrt → Gooby läuft als Silhouette ins Terminal; low-poly
              Flugzeug (Blender) hebt dahinter ab, Kamera neigt hoch, Bloom-Sonne.
              → Fade → Urlaubs-Status-UI.
```

Rückkehr-Variante (Abholung): gekürzt rückwärts (~12 s): Flugzeug landet → Gooby kommt mit
Koffer + **Mitbringsel-Tüte** raus → Umarmung-Konfetti (Reunion aus `vacation.js` Pickup).
Umsetzung: ein Master-`AnimationPlayer` steuert Kamera-Tracks + Path3D-Follower; keine
Physik, deterministisch, skippbar; Assets = Stadt-Assets (keine Duplikate).

### 3.3 Der NUTZEN von Urlaub (Alt-System übernehmen + verstärken)

Alt-Spiel hat bereits (aus `vacation.js`/`postcards.js`/`stickers.js` verifiziert):
Postkarten-Archiv (1/Tag, Cap 36, 5 Text-Varianten), souvenirCoins bei Abholung (30–70),
Reiseziele-Sammelpass (`visited`), Travel-Sticker-Seite. **Alles portieren**, plus:

1. **Physische Souvenirs:** Jedes Ziel schenkt bei Abholung 1 Deko-Item (Möbel-katalogfähig,
   §D-Grid: „Schneekugel Glitzermeer", „Mini-Rakete", „Hafenlaterne" …). Souvenir-Regal
   (Baumarkt-Bauplan) zeigt sie; **Set-Bonus**: alle 9 ausgestellt → goldener
   „Weltengooby"-Sticker + Deckengirlande.
2. **Erholungs-Boost:** 48 Realstunden nach Abholung Buff „Erholt ☀": Energie-Drain ×0,75,
   Aufwachen gibt +5 Laune. (Zahlen im Owning-Module frieren, `vacation.gd`.)
3. **GOOBY FREE (Mitbringsel-Shop im Terminal):** 24 h nach Rückkehr exklusive Ziel-Deko
   kaufbar („nur aus dem Urlaub mitbringbar") — sanfter Münz-Sink + Grund, den Flughafen-Ort
   wirklich zu betreten.
4. **Postkarten aufhängbar:** Archiv-Karten als WALL-Items (§D-Grid, Bilderrahmen-Slot).

---

## 4. Taxi-Warte-Loop (+ Guber) — Statemaschine

`systems/taxi_service.gd` — pures RefCounted, Zeit als **Timestamps im Save** (nie Countdown-
Reste), damit App-Kill/Neustart selbstheilend ist (Muster: `vacation.js` sliceOf).

```
IDLE ──rufen()──▶ GERUFEN     t_ruf = now; warte = rand(300..600 s) [Guber: 30..90 s]
                              Notifications planen (§C gooby_notify):
                                T−15 s  „🚕 Dein Taxi ist gleich da!"
                                T+0     „🚕 Dein Taxi steht vor der Tür!" (1-Min-Fenster läuft)
                                T+60 s  „Das Taxi ist wieder weggefahren 😾" (wird gecancelt
                                         bei Einstieg)
GERUFEN ──(App offen/zu egal; now ≥ t_ruf+warte)──▶ WARTET
                              Taxi-Modell spawnt am Bordstein (car-kit/taxi), Warnblinker-
                              Emissive, alle 20 s kurzes Hup-Hüpfen. In-App-Banner statt
                              Notification, wenn App im Vordergrund (Foreground-Handler §C).
WARTET ─┬─ Spieler tippt Taxi/„Einsteigen" ──▶ FAHRT   kurze Einsteige-Animation, Fade,
        │                                              Ankunft am Ziel-Ort → IDLE
        └─ now > t_ankunft+60 s ──▶ VERPASST   Taxi fährt sichtbar weg (falls Szene aktiv);
                                               50 % Anfahrtsgebühr verfallen; Bubble:
                                               „Der Fahrer lässt grüßen. Wörtlich: ‚grüße'."
                                               → IDLE
Storno in GERUFEN: 2 Münzen Gebühr, Notifications canceln → IDLE.
App-Start-Recovery: now > t_ankunft+60 ∧ state==GERUFEN|WARTET → VERPASST still abwickeln.
```

- **Wann rufbar:** immer via IGohbie; bei **0 Energie** wird die App gehighlightet
  (User-Wunsch: Taxi ist der 0-Energie-Rettungsweg). Kosten: Taxi 10 Münzen, **Guber**
  30 Münzen (schwarzer `sedan-sports`, ledriger Innenraum-Skin, Fahrer-Dialog vornehm:
  „Stilles Wasser oder … stilles Wasser?"). Gelegentlicher Surge-Gag: „Preise gerade 1,3× —
  es regnet nicht mal. Wir verstehen es auch nicht."
- Live Activity (iOS, M2): ActivityKit-Countdown per §C-Plugin — Zeiten sind beim Rufen
  bekannt, kein Server nötig. M1 = nur lokale Notifications (§C M1).

## 5. GOOBERANDO — „Erstmal Goobyn."

### 5.1 Bestell-UI (IGohbie-App; App-Shell-Contract: Apps registrieren sich per Manifest)

3 virtuelle Restaurants (rein lokal): **Bella Goobia** (Pizza/Pasta), **Gooby Wok** (Asia),
**Burger Bap** (Burger/Fries) — Menü-Items mappen auf food-kit-GLBs (Icons vorgerendert,
§2.1) und geben die normalen Sättigungs-/Laune-Werte des Essens-Systems. UI-Flow:
Restaurant-Liste (Karte, Bewertung als Gag: „4,8 ★ — ein Stern abgezogen, Fahrer hat
gewunken, Kunde war schüchtern") → Menü-Grid → Warenkorb → Kasse (Münzen; Liefergebühr 3).

### 5.2 Fahrer-Live-Simulation (rein lokal!) + Statemaschine

`systems/delivery_service.gd` (pur, GUT-testbar):

```
IDLE ─bestellen()─▶ BESTELLT    t_bestellt = now; prep = rand(120..300 s);
                                Route = A*(GOOBERANDO-Küche (r5,c5) → Haus (r9,c2)) auf dem
                                road_graph; fahrzeit = routenlänge / 8 m/s;
                                t_los = t_bestellt + max(30 s, prep − fahrzeit)
        │                       Notification T_tuer: „🍜 Dein Essen ist da! DING DONG"
BESTELLT ─(now ≥ t_los)─▶ UNTERWEGS
        Fahrer-Position = polyline_point(route, (now−t_los)/fahrzeit)  ← DETERMINISTISCH aus
        Timestamps; Stadtkarte (2D-Minimap) zeichnet den orangen Pin jede Sekunde neu; App
        zu/auf/Neustart egal — Position ist reine Funktion der Uhrzeit. Fährt der Spieler
        selbst durch die Stadt, spawnt zusätzlich ein echter car-kit/delivery-Van an
        derselben Graph-Position (Sichtung des eigenen Essens = Highlight!).
UNTERWEGS ─(now ≥ t_los+fahrzeit)─▶ VOR_DER_TÜR
        Klingel: „DING DONG"-Sound + Türklingel-Bubble im Haus + Notification (falls App zu).
        Geduld 5 min: Liefer-Gooby wartet, tippelt, schaut auf sein Handy.
VOR_DER_TÜR ─┬─ Tür öffnen ─▶ ÜBERGABE   oranger Liefer-Gooby (Gooby-Mesh, Fell-Tint
             │                #FF7A00, GOOBERANDO-Käppi), Verbeugung, Tüten-Übergabe-Tween
             │                (Bogen Hand→Hand), Essen ins Inventar
             │                → TRINKGELD-Prompt: [5 Münzen geben 💛] [Nur winken]
             └─ 5 min vorbei ─▶ ABGESTELLT  Tüte steht vor der Tür (voller Effekt — wir
                                            sind freundlich), aber kein Trinkgeld-Moment,
                                            Zettel: „Hab geklingelt! – G."
TRINKGELD gegeben: 30 % Chance auf Buff „Extra-Grinsen 😁" (2 h Energie-Drain ×0,75);
Fahrer macht Freuden-Sprung. Zähler lieferungen/trinkgelder im Save:
lieferungen ≥ 4 ∧ trinkgelder == 0 → Fahrer schaut traurig, Bubble: „…kein Trinkgeld?
Schon okay. Mama sagt, Anerkennung ist auch eine Währung." + einmaliger Hinweis-Toast.
→ FERTIG → IDLE
```

### 5.3 Logo-Specs (für die Bildgenerierung)

- **Marke:** GOOBERANDO · Slogan „Erstmal Goobyn."
- **Farben:** Orange `#FF7A00`, Cremeweiß `#FFF4E6`, Outline-Braun `#4A3B36`
  (= exakt die Text-/Schatten-Farbe des Spiel-UIs, rgba(74,59,54) im Web-CSS — bindet das
  Logo an den Look).
- **Wordmark:** fette, runde Sans (Baloo-artig), minimal rotiert (−3°), das zweite „O" ist
  eine Essensschüssel von oben mit Dampf-Swirl.
- **Maskottchen:** Gooby-Kopf mit oranger Schirmmütze (Logo-Monogramm „G" auf der Mütze),
  zwinkert, hält Papiertüte.
- **Stil:** Flat Vector, dicke Outlines (#4A3B36, ~8 px bei 1024), KEINE Verläufe (außer
  dezentem Dampf), transparenter Hintergrund.
- **Deliverables:** App-Icon 1024² (Kopf im abgerundeten Quadrat) · Wordmark horizontal ·
  Tüten-Aufdruck einfarbig WEISS (für die Blender-Tüten-Textur) · Fahrer-Map-Pin 128²
  (Kopf im Kreis + kleiner Richtungskeil unten).

---

## 6. Asset-Bedarfsliste — vorhanden vs. Blender-Neubau

### 6.1 Vorhanden (Kits nutzen, teils erstmals)

| Bedarf | Quelle (verifiziert) |
|---|---|
| Straßen inkl. **Kreisel, Kurven, Sackgassen-Enden, Highway-Schild** | city-kit-roads (roundabout/curve/end/end-round/sign-highway bisher ungenutzt) |
| Taxi, Liefer-Van, Verkehr, Spieler-Autos | car-kit (`taxi.glb`, `delivery.glb`, sedan[-sports], hatchback-sports, suv, race, van, police, truck) |
| Generische Stadt-Füllgebäude | city-kit-commercial a–h + skyscraper + kaykit-city building A–F |
| Markisen für Ladenfronten | `detail-awning`, `detail-awning-wide` |
| Gehweg-Deko (Laternen, Bänke, Hydranten, Müll) | kaykit-city |
| REHWEI-Interieur: Kühlregal, Theke, Kisten, Regal-Ware | kaykit-restaurant (fridge_A, kitchencounter_*, crates) + **food-kit (70 Lebensmittel!)** |
| Park-Tor, Windmühlen-Café (Landmarken behalten) | minigolf-kit castle/windmill |
| Wohnviertel-Deko: Zäune, Wege, Planter, Bäume | city-kit-suburban + nature-kit |
| Wochenmarkt-Ware, Körbe | food-kit + kaykit-restaurant jars/crates + nature-kit crops |
| POW!-Interieur-Basis | itch/tinytreats (Regal-Teile) + kaykit |

### 6.2 Blender-Neubauten (Kenney-Stil, alle mit Palette-Methode §6.3)

| Asset | Umfang | Bemerkung |
|---|---|---|
| **Ladenfronten** REHWEI, GOOBYTHEKE, GOOUHBUS-Praxis, POW!, Baumarkt, Autohaus (Glas-Showroom), Post | 7 Korpusse | Basis: Kenney-Proportionen (1×1 Footprint, ×10 in Engine); Korpus + Markise + **Schild-Quad** (Logo-Texturen werden GENERIERT, nicht modelliert) |
| **IKEA-Großladen** | 1 (2×2 Tiles) | blaue Box + gelbe Letter-Plates; Eingang mit Schiebetür-Node für D |
| **Flughafen**: Terminal (2×1), Tower, low-poly Flugzeug | 3 | Flugzeug nur für Cutscene (Start/Landung), <1500 Tris |
| **Wohnhäuser** haus_a/b/c | 3 | city-kit-suburban hat KEINE Häuser im Repo — Alternativ-Option: Voll-Kit von kenney.nl nachladen (CC0, Internet erlaubt); Blender-Variante gibt uns Gooby-Proportionen (runder, dickere Türen) |
| **Marktstand** (1 Modell, 4 Farbvarianten via Palette-UV) | 1 | Dach + Theke + Pfosten |
| Kleinteile: **Rollkoffer, GOOBERANDO-Papiertüte** (Logo-Textur), GOOBERANDO-Käppi (Gooby-Attachment), Souvenir-Regal, 9 Souvenirs | ~13 | je < 300 Tris |
| `ort_interior_kit`: Wand-/Boden-Module, Ladentheke, Regal 3 Größen | ~8 | teilt EIN Material mit allen Neubauten |

### 6.3 Blender-Python-Methode (Palette-Texture-Atlas, konkret)

Kenney-Stil = flat-shaded Low-Poly, **eine winzige Palette-Textur, UVs pro Face auf eine
Farbzelle kollabiert** → alle Neubauten teilen 1 Material = 1 Draw-Call-Gruppe.

1. `gooby_city_palette.png`: 256², 8×8 Zellen à 32 px (Fassaden-Creme, REHWEI-Rot,
   Apotheken-Grün, POW!-Gelb/Blau, Baumarkt-Orange, Post-Gelb, IKEA-Blau, GOOBERANDO-Orange
   #FF7A00, Glas-Cyan, Dach-Grau …). Zellzentren ansteuern → kein Bleeding.
2. Headless-Pipeline: `blender -b -P tools/build_city_assets.py` (idempotent, im Repo,
   CI-fähig):

```python
import bpy, bmesh
def paint(obj, face_cells):            # face_index → (col,row) der Palette
    bm = bmesh.new(); bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        c, r = face_cells.get(f.index, (0, 0))
        for l in f.loops:              # ganze Face auf das Zellzentrum
            l[uv].uv = ((c + .5) / 8, (r + .5) / 8)
    bm.to_mesh(obj.data); bm.free()
# Korpus: Cube → Scale/Extrude (Schaufenster-Nische), Bevel-Modifier 0.02, shade_flat;
# Schild: separates Quad-Mesh, EIGENES Material (generierte Logo-PNG);
# Export: bpy.ops.export_scene.gltf(filepath=…, export_format='GLB', export_apply=True)
```

3. Stil-Regeln (Checkliste je Asset): nur Quads/Tris aus Extrudes, Bevel ≤ 0,02, KEINE
   Normal-Maps, Silhouette lesbar bei 60 px Höhe, Ursprung an Boden-Mitte, +Z = Front,
   authored ≈ 1 Einheit (Engine skaliert ×10 wie `BUILDING_SCALE`).

---

## 7. Prioritäten

| Stufe | Inhalt |
|---|---|
| **M1** | `city_layout.gd` + `road_graph.gd` + Stadtszene (15×12), Auto-Port (`car_feel.gd`, player_car, chase_cam, Rückwärtsgang), Traffic-Wander-Agenten light (6 Autos), Energie-bei-Ankunft + „Nach Hause"-Knopf, Ort-Framework (OrtScene, Händler-UI, Dialog-Runner, Gebrabbel), **3 Kern-Orte:** REHWEI, GOOBYTHEKE + GOOUHBUS (Rezept-Flow), Flughafen (Buchung + GOOBY FREE-Stub), **Reise-Cutscene neu** (Abflug + Rückkehr), Vacation-Port (Phasen/Postkarten/souvenirCoins), Blender-Welle 1 (7 Ladenfronten, Terminal, Koffer, Flugzeug), „Reise"-Knopf-Rename |
| **M2** | Taxi/Guber-Service + lokale Notifications (§C-Plugin), GOOBERANDO komplett (App, Fahrer-Sim, Übergabe, Trinkgeld, Logo-Generierung), Stadtkarte/Minimap, POW! (Kamera + Tagesangebote), Autohaus (CarDefs + Probefahrt), Post (Archiv, MP-Stub), Wochenmarkt (Samstag-Logik), Fußgänger + Tag/Nacht, Souvenir-Regal + Erholungs-Boost |
| **M3** | Baumarkt (mit §D-Werkstatt), IKEA-Integration (Ds Ausstellung einhängen), Live Activity (ActivityKit), Guber-Premium-Polish, Ambient-Audio-Distrikte, Set-Bonus „Weltengooby", Hupe-Reaktionen/Near-Miss-Funken, Wohnhaus-Varianten |

## 8. Risiken

1. **Handy-Performance große Stadt:** 180 Tiles + Interieurs. Gegenmittel: MultiMesh für alle
   Wiederholer, geteilte Palette-Materialien, Interieurs als getrennte Szenen (Stadt wird
   entladen), Ziel-Budget < 120 Draw Calls / < 250 k Tris. Früh auf echtem iPhone profilen.
2. **Freie Fahrt = Verkeilen/Softlocks:** Wedge-Watchdog + Rückwärtsgang von Anfang an;
   „Nach Hause"-Knopf ist das ultimative Rettungsnetz.
3. **Notification-Permission verweigert:** Taxi/GOOBERANDO laufen komplett über In-Game-Timer
   weiter (Notifications sind reiner Komfort — §C-Regel übernehmen).
4. **Blender-Stilbruch:** Palette-Methode + Stil-Checkliste + 1 Testrender neben Kenney-Kit
   VOR der Serienproduktion; Schilder als generierte Texturen entkoppeln Logo-Qualität vom
   3D-Skill.
5. **Katalog-Drift:** CarDefs (Autohaus ↔ Minispiele) und Ort-Katalog (Stadt ↔ IGohbie-Apps)
   je EIN Owning-Module + GUT-Sync-Test (Muster: CatalogSyncTests des Servers / Kataloge im
   Web-Spiel).
6. **Uhr-Manipulation:** Alle Warte-Loops aus Timestamps — Rückwärts-Sprung generiert nichts
   doppelt (Muster `postcards.js` monotone Bookkeeping); Vorwärts-Cheat toleriert
   (Offline-Spiel, kein Schaden).
7. **Dialog-Längen DEUTSCH:** Bubbles auf 2×38 Zeichen auslegen, Runner bricht automatisch
   in Folge-Bubbles um (deutsche Komposita-Falle: „Bewässerungsanlagenbauplan").

## 9. Scope-Schätzung (neue Dateien / LOC, GDScript + Szenen)

| Modul | Dateien | LOC |
|---|---|---|
| `city/` (layout, road_graph, city.tscn/.gd, parking_trigger) | 6 | ~1.100 |
| `city/car/` (car_feel, player_car, chase_cam, hud) | 5 | ~800 |
| `city/traffic/` (agenten, fußgänger) | 3 | ~450 |
| `city/minimap/` (karten-render, pins) | 2 | ~300 |
| `orte/_base/` (OrtScene, Katalog, Händler-UI, Dialog-Runner, Bubble, Gebrabbel) | 8 | ~1.200 |
| `orte/*` (10 Orte à Szene+Skript+Dialog-JSON) | ~30 | ~2.200 |
| `cutscenes/` (Abflug + Rückkehr) | 3 | ~500 |
| `systems/` (taxi_service, delivery_service, vacation-Port, souvenirs) | 4 | ~1.000 |
| `handy/apps/` (taxi, guber, gooberando UI) | 5 | ~900 |
| GUT-Tests (feel, graph, dialoge, statemaschinen, kataloge) | ~10 | ~1.400 |
| Blender-Pipeline (`tools/build_city_assets.py` + Paletten-PNG) | 2 | ~600 |
| **Summe** | **~78** | **~10.400** |
