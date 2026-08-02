# G8-PT2 — Playtest „Stadt & Läden" (Welle H)

- **Agent:** PT-2 · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Bereich:** Stadt (Orte, Wege, NPC-Leben), Läden (REHWEI, IKEA, Wochenmarkt,
  GOOBERANDO, Flughafen/Reise), DLC-Läden („Goo und Bye"-Tag-Loop, „McGooby"-
  Probeschicht), DLC-Hub inkl. Kauf-Flow.
- **Methode:** 6 Flows unter `tests/tools/playtest_flows/flow_pt2_*.gd` spielen das
  ECHTE Spiel (main.tscn) mit synthetischen Eingaben — jeder Lauf frisches
  `user://`, Start immer durchs komplette Onboarding. Leitformat quer 2868x1320.
  Ausführung strikt unter
  `flock /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh flow_pt2_<x>`.
  Geld-/Warenchecks rechnen JEDEN Kauf exakt nach (merke/prüfe-Delta-Muster).

## Lauf-Übersicht (finale Läufe)

| Flow | Finaler Lauf (unter `/tmp/gooby-godot/artifacts/PLAYTEST/`) | Ergebnis |
| --- | --- | --- |
| `flow_pt2_stadtrundgang` | `flow_pt2_stadtrundgang_105121_42445` | Exit 0 — 3 geplante Soft-Fails = Befund **B4** (kein Orts-Leben in Goobytheke/Flughafen/Post) |
| `flow_pt2_rehwei_ikea` | `flow_pt2_rehwei_ikea_105830_43020` | **0 fail** — REHWEI- & IKEA-Kauf exakt (Geld+Lager) |
| `flow_pt2_wochenmarkt` | `pt2_c5` | **0 fail** — Ankauf 130→150 ᴳ, Stand 2 Slots, Slider-Faktor 0,50, Abrechnung 26 ᴳ exakt |
| `flow_pt2_goobye_tag` | `pt2_d5` | **0 fail** — Schlüssel −2500 ᴳ exakt, Regal 19/19, Alwin bedient (Streak 1), Feierabend bucht exakt +41 ᴳ, Großmarkt-Rundtrip −8 ᴳ |
| `flow_pt2_mcgooby` | `pt2_e1` | **0 fail** — Echt-Timing-Wende „Perfekt!", Pause stoppt Braten, 2 Schichten à 50 P → je +16 ᴳ exakt (12 Basis + 4 Trinkgeld, Combo ×1,2) |
| `flow_pt2_gooberando_guber` | `pt2_f2` | **0 fail** — Bestellung −19 ᴳ exakt (7+9+3 Gebühr), Essen 1:1 im Inventar, Trinkgeld −5, Guber rufen −30 / Storno +28 (netto −2) / Fahrt −30 exakt |

Diagnose-Zwischenläufe (Belege für die Befunde unten): `pt2_a1`, `pt2_b1`,
`pt2_c1…c4`, `pt2_d1…d4`, `pt2_f1`.

## Befunde nach Schweregrad

### B1 — HOCH: DLC-Hub aus den Einstellungen ist unerreichbar (Settings-Overlay bleibt über dem Hub liegen)

- **Repro:** Wohnzimmer → Zahnrad (Settings) → Sektion „DLC" → „Alle DLCs
  ansehen". Reise-Veil läuft, danach zeigt der Schirm WIEDER „Einstellungen" —
  der DLC-Hub ist da, liegt aber UNSICHTBAR DARUNTER und bekommt keinen
  einzigen Tap. Erst ein (gefühlt sinnloser) Tipp auf „‹ Zurück" legt ihn frei.
- **Beleg:** `pt2_d1/016…020_*.png` (Veil → wieder Settings, Route laut Harness
  trotzdem `dlc`). Baum-Obduktion per Wegwerf-Probe-Flow:
  `SettingsScreen` lebt unter `/root/Main/HomeEntry/UiLayer/SettingsScreen`
  (CanvasLayer, rendert über allem), der frisch gemountete `DlcScreen` unter
  `/root/Main/HomeEntry/World/DlcScreen`. Router: `route=dlc, busy=false`.
- **Fix-Verdacht:** `scripts/ui/settings/dlc_sektion.gd:_oeffne_bibliothek`
  ruft `router.goto("dlc")`, schließt aber das Settings-Overlay nie —
  `home_entry.gd:_open_settings` hängt es in den persistenten `UiLayer` des
  HomeEntry-Rahmens, der die Reise überlebt. Vor dem `goto` das Overlay
  schließen (z. B. `back_pressed`-Pfad bzw. `_close_settings`), oder
  `home_entry` räumt `_settings` bei `travel_started` weg.
- **Flow-Umgehung (bis zum Fix):** Schritt `settings_overlay_schliessen` in
  `flow_pt2_goobye_tag`/`flow_pt2_mcgooby` (Zurück-Tipp NACH dem Veil — ein
  Tipp WÄHREND des Veils verpufft im Vorhang, Beleg `pt2_d2/017…019`).

### B2 — HOCH: „Goo und Bye": „Backen (9)"-Pill überdeckt die Regal-Slots 0–2 (Querformat)

- **Repro:** Goobye-Laden im Leitformat quer. Die per Kamera-Unproject
  platzierten Pills von Ofen („Backen (9)") und Regal-Slots landen fast
  deckungsgleich; Backen wird SPÄTER in die UI gehängt und liegt oben. Taps auf
  die Slots 0–2 treffen BACKEN: 3 Taps = **27 ᴳ weg und 9 Brote gebacken statt
  eingeräumt** — und mit leerem Regal verweigert „Laden öffnen!" den Markttag
  (korrekt), d. h. der Tag-Loop ist per Touch quer kaum spielbar. Slots 3–4
  bleiben tippbar.
- **Beleg:** `pt2_d4/037_laden_umsehen.png` (nur 2 „+"-Pills sichtbar, direkt
  neben „Backen (9)"), `pt2_d4/040_slot_2_fuellen.png` (Toast „3× frisches
  Brot…", Lager 32→41), lauf.log `Regal-Bestand: 0 (soll 19)`, Kasse 550→523.
- **Fix-Verdacht:** `scripts/dlc/goobye/laden_scene.gd:_layout_slots` hebt die
  Slot-Pills um `0,8·Knopfhöhe` an, `_layout_backofen` NICHT — bei flacher
  Quer-Kamera projizieren Ofen (`BACKOFEN_POS`+1,15 m) und Regalbrett
  (`REGAL_HOEHE`+0,05 m) auf fast dieselbe Bildzeile. Backen-Pill ebenfalls
  anheben/versetzen oder Kollisionsausweichen im Layout; alternativ Backen vor
  den Slots einhängen (z-Reihenfolge).
- **Flow-Umgehung:** `_slot_fuellen` ruft `slot_tippen(i)` direkt (dieselbe
  Methode, die der Knopf ruft) — dokumentiert im Flow-Kommentar.

### B3 — MITTEL: Flughafen & Post: Parkplatz-Anker steckt im Gebäude-Collider

- **Repro:** `CityScene._spawn_bei("flughafen")` (nutzt das Spiel selbst beim
  Verlassen eines Orts) setzt das Auto auf `parkplatz_welt` — der Punkt liegt
  ~0,5 m IM Kollisionsquader des Gebäudes. `_kollidiere` schiebt das Auto
  sofort raus (immer nach Westen), je nach Winkel über den 7-m-Prompt-Radius
  hinaus: „Betreten"-Prompt flackert weg, Auto macht einen unsichtbaren Satz.
- **Beleg:** `pt2_a1/…flughafen/post`-Schritte (Timeout auf Prompt trotz
  Vorfahrt); reproduzierbar rein aus den Kartendaten (`city_map.json`:
  Parkplatz-Tile grenzt bündig an die Gebäude-Tiles).
- **Fix-Verdacht:** Parkplatz-Anker der beiden Orte in `city_map.json` eine
  halbe Kachel zur Straße rücken oder `_spawn_bei` den Anker aus dem Collider
  herausprojizieren lassen.

### B4 — MITTEL (User-Kritik „leere Läden"): Kein Orts-Leben in Goobytheke, Flughafen, Post (+ Marktplatz-Rand)

- **Befund:** `OrtScene._leben_konfig()` liefert nur für REHWEI und Baumarkt
  eine Besucher-Konfiguration; GOOBYTHEKE, Flughafen und Post haben KEIN
  `OrtLeben` — kein Besucher, kein Idle-Geräusch, niemand außer dem Händler.
  Genau die Orte, die der User als „leer" kritisiert hat.
- **Beleg:** finaler Stadtrundgang `flow_pt2_stadtrundgang_105121_42445/`
  `030_leben_goobytheke_FAIL.png`, `039_leben_flughafen_FAIL.png`,
  `048_leben_post_FAIL.png` (bewusst als Soft-Prüfschritte eingebaut).
- **Vorschlag:** siehe „Spielgefühl"-Abschnitt unten.

### B5 — KLEIN: Reise zum DLC-Hub zeigt die „Trautes Heim"-Ladekarte

- **Befund:** Beim `goto("dlc")` erscheint der Veil mit Home-Karte („Trautes
  Heim / Die Blumen werden gegossen…") — der Spieler denkt, er reist nach
  Hause. Ursache: `loading_veil.gd:_apply_variant` kennt nur Minigame-,
  DLC-Karten- und Home-Modus; die Hub-Route `dlc` fällt auf „home" zurück.
- **Beleg:** `pt2_d1/016_alle_dlcs_ansehen.png`.
- **Fix-Verdacht:** eigenen `veil.dlc_hub`-Eintrag (oder neutrale
  „Auf geht's!"-Trip-Karte) für Ziel `dlc` wählen.

### B6 — KLEIN: IKEA-Detail: Kaufknopf liegt quer unterm Falz

- **Befund:** Im Möbel-Detail (`DetailScroll`) liegt der „Kaufen"-Knopf im
  Leitformat quer unterhalb des sichtbaren Bereichs; ohne Scrollen ist er
  unsichtbar (Erst-Eindruck „kein Kaufknopf").
- **Beleg:** `pt2_b1/047_lager_plus_eins_FAIL.png` (Kauf ging ins Leere, weil
  der Tap unterm Falz landete); nach Scroll-Schritten kauft der finale Lauf
  sauber (`flow_pt2_rehwei_ikea_105830_43020`, 0 fail).
- **Fix-Verdacht:** Detail-Layout quer: Kaufzeile als Sticky-Footer außerhalb
  des Scrollers (Muster HaendlerSheet) statt am Listenende.

### B7 — KLEIN: Engine-ERROR beim Öffnen von Guber/GOOBERANDO aus dem App-Grid

- **Befund:** Beim Tipp auf die Kachel loggt Godot
  `ERROR: Can't use get_node() with absolute paths from outside the active
  scene tree` — irgendein Knoten fragt `/root/...` ab, bevor er im Baum hängt
  (Kandidaten: `fahrdienst_app.gd`/`gooberando_app.gd` `_ready`-Pfad bzw.
  `_warte_s()`-Settings-Lookup während des App-Wechsels). Funktional folgenlos,
  aber ein echter Schmutz-Error in jedem Lauf.
- **Beleg:** `pt2_f1`/`pt2_f2` lauf.log, direkt nach `knopf_in 'KachelGuber'`
  bzw. beim GOOBERANDO-Öffnen.

### B8 — KLEIN: Telefon-Statusleiste zeigt veraltete Münzen

- **Befund:** Nach der GOOBERANDO-Bestellung (−19 ᴳ) zeigt die Status-Zeile des
  Telefons weiter „300", während das HUD links längst 281 zeigt; erst ein
  App-/Grid-Wechsel aktualisiert sie.
- **Beleg:** `pt2_f2/038_fahrer_karte_ansehen.png` (Phone „● 300" vs.
  HUD-Pill „281").

### B9 — KLEIN: „Was nun?"-Hinweiskarte hängt ÜBER dem Telefon-Sheet

- **Befund:** Die Quest-Hinweiskarte („Eine Quest-Belohnung wartet auf dich…")
  bleibt über dem geöffneten Telefon liegen und verdeckt Uhr/Statuszeile,
  solange man sie nicht manuell wegtippt. Gleiche Familie wie PT-4-Befund B6
  (Karte hängt in den Baumodus rein).
- **Beleg:** `pt2_f2/038…040_*.png`, `pt2_f1/048_guber_oeffnen.png`.

### B10 — KLEIN: Wochenmarkt-Öffnungsregel (Sa 8–14) wird nirgends durchgesetzt

- **Befund:** Kartendaten/Kommentar sagen „samstags 8–14 Uhr"
  (`wochenmarkt.gd`-Kopf), aber der Ort ist an JEDEM Tag betretbar und
  `MarktPreise.verkaufen` verkauft an jedem Wochentag (kompletter Lauf `pt2_c5`
  fand an einem Sonntag statt, Ankauf 130→150 ᴳ). Falls das kinderfreundliche
  Absicht ist: Kommentar/Daten anpassen; falls nicht: Gretas Ankauf außerhalb
  der Zeiten freundlich vertrösten. (Der Eigenstand ist korrekt Samstag-fixiert
  — Markttag-Replay bindet an den nächsten Samstag.)

### B11 — TECH/Testbarkeit: `FahrdienstApp.aktualisiere()` nummeriert Knopf-Namen um

- **Befund:** `aktualisiere()` macht `queue_free()` auf alle Kinder (deferred)
  und baut im SELBEN Frame neue Kinder mit denselben Namen — Godot benennt die
  neuen Knoten dann um (`@RufenButton@…`). Wer danach per Name sucht
  (`get_node("RufenButton")`, Tests, künftige Tutorials/Coachmarks!), findet
  die STERBENDE Instanz oder nichts. Spielerisch heute folgenlos, aber eine
  Stolperfalle. Muster-Fix: Kinder erst `remove_child` + `queue_free` (wie in
  `panel_sheet.gd:add_content` dokumentiert).
- **Beleg:** `pt2_f1` Schritt 051 (Node „RufenButton" 30 s lang unauffindbar,
  obwohl der Knopf sichtbar auf dem Schirm steht,
  `pt2_f1/051_wagen_rufen_1_FAIL.png`).

### B12 — HINWEIS: Goobye-Kunden laufen am rechten Bildrand ein, Tür halb außerhalb

- **Befund:** Im Leitformat quer liegt die Ladentür (`TUER_POS` x=5,4) am
  äußersten rechten Bildrand; Kunden erscheinen halb abgeschnitten und laufen
  eine lange leere Diagonale. Kamera etwas weiter fassen oder Tür in den Frame
  rücken.
- **Beleg:** `pt2_d5/049_kunden_schauen_2.png` (Kunde rechts angeschnitten).

### B13 — HINWEIS: Passiver Münz-Zuwachs im Leerlauf (Quelle offen)

- **Befund:** Während der langen Fail-Timeouts in `pt2_f1` stiegen die Münzen
  ohne jede Aktion 276→279→281 (~+5 in 4 min, Telefon offen im Wohnzimmer).
  Quelle nicht ermittelt (Verdacht: Heim-/Quest-Tick). Für exakte
  Geld-Regressionen relevant — Checks sollten in kurzen Fenstern messen (die
  PT-2-Flows tun das).

## Spielgefühl Läden — ehrliche Einschätzung (trotz G7-P55)

- **REHWEI / Baumarkt:** in Ordnung — mit `OrtLeben` (Besucher trudeln ein)
  wirken die Läden bewohnt; Kauf-Sheets sind flott und klar.
- **GOOBYTHEKE / Flughafen / Post:** fühlen sich weiterhin LEER an (B4): ein
  Händler, stille Kulisse, nichts bewegt sich. Der Flughafen hat immerhin die
  Reise-Fantasie, die Post gar nichts Lebendiges.
- **Wochenmarkt:** bester Stadt-Ort — Stände, Häschen, Greta-Dialog, eigener
  Stand mit Slider und Replay („So lief dein Markttag…" mit +ᴳ-Ticker) macht
  echte Laune. Der PLATZ drumherum ist aber kahl (eine Laterne, leere Wiese) —
  zwei, drei Bummel-Besucher zwischen den Ständen würden viel holen.
- **Goo und Bye:** der Tag-Loop trägt (Einräumen → öffnen → Kunden-Choreo mit
  Namen wie „Familie Hoppel stöbert…" → Kassensturz mit hochzählendem Erlös —
  toll!). Der RAUM ist aber karg: leere weiße Wände, keine Deko, keine
  Schaufenster, Tür halb aus dem Bild (B12). Alwin existiert nur als
  Statistik-Zeile — der Story-Kern („Onkel Alwin kommt um 9 und kauft EINE
  Möhre") verdient eine sichtbare Mini-Szene/Sprechblase.
- **McGooby:** spielmechanisch rund (Timing-Fenster, Combo, Trinkgeld), aber
  optisch das „leerste" Erlebnis: eine Patty-Scheibe auf Pastellgrund, kein
  Grill, keine Theke, keine Kundschaft, keine Küche — es fühlt sich nach
  Test-Widget an, nicht nach Fast-Food-Schicht.
- **GOOBERANDO / Guber:** charmantestes Mikro-Erlebnis („Der orange Punkt
  bringt dein Essen. Winken bringt nichts, hilft aber.", Fahrer-Häschen mit
  Verbeugung) — DIESES Niveau an Witz/Leben ist die Messlatte für die anderen
  Läden.

**Konkrete Vorschläge (kleinste wirksame Schritte zuerst):**

1. `_leben_konfig()` für Goobytheke/Flughafen/Post/Marktplatz füllen (B4) —
   dieselben Besucher-Rigs wie REHWEI, je 1–2 Idle-Pfade + leises
   Grundgeräusch (Stempel-Klack in der Post, Board-Pings am Flughafen).
2. Goo und Bye: 3–4 Requisiten (Poster, Pflanze, Einkaufswagen, Preistafel),
   Kunden-Emote am Regal (kurzes „stöbern"-Hüpfen), Alwin um 9 mit Blase
   „Eine Möhre, bitte!" — der Loop hat die Bühne dafür schon.
3. McGooby: flacher Küchen-Hintergrund (Grill + Theke als 2D-Layer genügt),
   Bestell-Avatare der Gäste neben der Bestellkarte, Brutzel-Sound ans
   Patty-Fenster koppeln.
4. Wochenmarkt-Platz: 2 Bummel-Besucher + Vogel/Falter-Partikel über der Wiese.
5. B1/B2 fixen — beide machen echte Inhalte (DLC-Hub, Goobye-Einräumen quer)
   für Spieler praktisch unzugänglich.

## Dateiliste (PT-2, nur eigene Dateihoheit)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_helfer.gd` (+ `.uid`) —
  UI-Sucher (Text/Node, Clip-Schutz über ALLE Scroll-Ahnen), Doppel-Roll-
  Baustein `rolle_schritte`, Wisch-Anker, Termin-Helfer, Dialog-Taps.
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_basis.gd` (+ `.uid`) —
  Onboarding-Schritte, Geld-/Energie-/Inventar-Zettel (merke/prüfe exakt),
  Stadt-Helfer (`fahre_zu` mit Bremse + Anker VOR dem Parkplatz-Trigger).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_stadtrundgang.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_rehwei_ikea.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_wochenmarkt.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_goobye_tag.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_mcgooby.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt2_gooberando_guber.gd` (+ `.uid`)
- `docs/playtest/G8-PT2-stadt-laeden.md` (dieser Report)

Alle Flows `gdformat`- und `gdlint`-sauber; Wegwerf-Diagnose-Flow
(`flow_pt2_probe.gd`, Baum-Obduktion für B1) nach Gebrauch gelöscht.

## Screenshot-/Lauf-Pfade (Belege)

Basis: `/tmp/gooby-godot/artifacts/PLAYTEST/`

- Finale grüne Läufe: `flow_pt2_stadtrundgang_105121_42445/`,
  `flow_pt2_rehwei_ikea_105830_43020/`, `pt2_c5/`, `pt2_d5/`, `pt2_e1/`,
  `pt2_f2/` (je `report.md`, `lauf.log`, `NNN_schritt.png`).
- Befund-Belege: B1 → `pt2_d1/016…020`, `pt2_d2/017…019`; B2 → `pt2_d4/037…041`;
  B3 → `pt2_a1/`; B4 → `flow_pt2_stadtrundgang_105121_42445/030|039|048_*_FAIL.png`;
  B5 → `pt2_d1/016`; B6 → `pt2_b1/047|048`; B7/B11/B13 → `pt2_f1/`;
  B8/B9 → `pt2_f2/038…040`; B12 → `pt2_d5/049`.
