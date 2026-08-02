# G8-PT1 — Playtest „Home/Haus, Baumodus, Kühlschrank & Zuwendung" (Welle H)

- **Agent:** PT-1 · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Bereich:** Haus-Rundgang (alle 5 Räume + Möbel-Interaktionen), Baumodus
  komplett (Dock, Platzieren, Drehen, Lager, Decken-Ebene, HUD-P50), Kühlschrank
  2.0 + komplette Fütter-Sequenz, Gooby-Zuwendung (Streicheln/Übermut, Ball,
  Antwort-Chips), Tagesbonus/Overlay-Verhalten beim Start. Zusatzauftrag:
  ASSET-ROT-Verdacht im Garten VERIFIZIEREN.
- **Methode:** 5 Flows unter `tests/tools/playtest_flows/flow_pt1_*.gd` spielen
  das ECHTE Spiel (main.tscn) mit synthetischen Eingaben — jeder Lauf frisches
  `user://`, Start immer durchs komplette Onboarding, Leitformat quer 2868x1320.
  Ausführung strikt unter
  `flock /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh flow_pt1_<x>`.
  Zustands-Checks lesen den echten GameState (merke/prüfe-Delta-Muster);
  Sequenzen (Füttern, Apport) werden per Frame-Beobachter im Poll mitgeschnitten.

## Lauf-Übersicht (finale Läufe)

| Flow | Finaler Lauf (unter `/tmp/gooby-godot/artifacts/PLAYTEST/`) | Ergebnis |
| --- | --- | --- |
| `flow_pt1_haus_rundgang` | `flow_pt1_haus_rundgang_172356_80434` | Exit 0 — 97 OK, 4 geplante Soft-Fails = Befunde **B1/B2/B4** (Garten-Defaults weg, Dusche-Doppelfire ×2, TV-Aus-Knopf verdeckt) |
| `flow_pt1_baumodus` | `flow_pt1_baumodus_171059_79392` | **48/48 OK** — Bett aus Lager, Drehen rot 0→1 (Footprint 2×3→3×2), Platzieren im Save, Fußmatte-Einlagern-Roundtrip, Ebene Decke/Boden, HUD-P50 hin & zurück |
| `flow_pt1_kuehlschrank` | `flow_pt1_kuehlschrank_171322_79527` | **43/43 OK** — Chips filtern echt, Sequenz: Regie + schwebendes Modell + GENAU 3 Bisse, Verliebtheit (Möhre = `favorit`), Hunger +≥2 gebucht, Vorrat 3→2, Badge ×2 |
| `flow_pt1_zuwendung` | `flow_pt1_zuwendung_171751_79688` | **36/36 OK** — petsToday 0→13 (1 echter 3D-Tap + 12er-Burst), Übermut-Gag „zerzaust", Apport balls 0→1 & fun +2,9, Chips: Antwort verbucht (`entschuldigen`), 12-s-Timeout räumt ab |
| `flow_pt1_tagesbonus` | `flow_pt1_tagesbonus_172056_79821` | **35/35 OK** — Popup nach Onboarding, 3× abweisen (Später/Backdrop/ESC) bucht nichts + bietet wieder an, Claim Tag 1 +20 (110→130), Tag 2 +30, Kulanz-Hinweis nach Lücke |

Diagnose-Zwischenläufe (Belege für die Befunde unten): `pt1_rundgang_v1`,
`flow_pt1_haus_rundgang_151742_73319` (v2), `…_154716_75687` (v3),
`…_162724_77979` (v4), `…_164829_78470` (v5), `flow_pt1_baumodus_165312_78680`
(Bau v1). Headless-GLB-Diagnose: `flow_pt1_diag_assets.gd` (kein Playtest-Flow,
Aufruf im Datei-Kopf).

## Befunde nach Schweregrad

### B1 — HOCH: Garten-Defaults (Baum, dicker Baum, Bank, großer Topf) verschwinden — Ownership-Konflikt am `blockers()`-Mount, KEINE GLB-Degradation

- **Repro:** Frisches Spiel → in den Garten reisen. Das Save/Grid führt 12
  Items, sichtbar sind nur 8 (Blumen, Büsche, Grasbüschel). `treeDefault`,
  `treeFat`, `gardenBench`, `potLarge` fehlen als Nodes — ihre Zellen bleiben
  aber im Grid belegt (unsichtbare Blocker beim späteren Bauen!).
- **Beweiskette (finaler Lauf, Schritte 098–100):**
  - `garten_save_check`: Grid-Items vollständig inkl. der 4 Kandidaten.
  - `garten_asset_rot_check`: FEHLENDE Möbel-Nodes exakt
    `treeDefault@[0,4]`, `treeFat@[26,16]`, `gardenBench@[0,22]`,
    `potLarge@[27,4]` — das sind GENAU die Garten-Items mit
    `blocks_movement=true`.
  - `garten_blocker_diagnose`: `Blockers-Kinder: []` (leergeräumt!), GridMount
    hält nur die 8 non-blocking Items; Live-`FurnitureNode.create("treeDefault")`
    im selben Frame liefert einen Node → GLB lädt einwandfrei.
  - Headless-Diagnose `flow_pt1_diag_assets.gd`: alle 6 geprüften GLBs
    existieren, laden, instanziieren; `FurnitureNode.create` ≠ null.
- **Ursache (Code-Obduktion):** `RoomBase._ready()` baut erst die Möbel
  (`rebuild_furniture`, Zeile 82) — `_spawn_furniture` hängt Möbel mit
  `blocks_movement=true` in `_blockers` (`room_base.gd:783-784`). DANACH läuft
  `GardenHost.attach_to` (Zeile 90) → `GardenView.setup(…, _room.blockers())`
  → `rebuild()` — und `rebuild()` räumt pauschal ALLE Kinder des fremden
  Mounts ab (`garden_view.gd:34-36`), inklusive der gerade gespawnten Möbel.
  Der ursprüngliche ASSET-ROT-Verdacht (weiche GLB-Degradation in
  FurnitureNode) ist damit WIDERLEGT.
- **Beleg:** `flow_pt1_haus_rundgang_172356_80434/099_garten_asset_rot_check_FAIL.png`,
  `100_garten_blocker_diagnose.png` + lauf.log; identisch in v4/v5.
- **Fix-Verdacht:** `garden_view.gd:rebuild` darf nur die EIGENEN Bauten
  freigeben (eigene Kinder-Liste führen oder Marker-Gruppe
  `garden_struktur`), alternativ hängt `RoomBase`/`GardenHost` die
  Garten-Bauten in einen eigenen Unter-Mount (`blockers()/GartenBauten`),
  damit Möbel- und Garten-Ownership getrennt sind.

### B2 — HOCH: Ein Klick = Doppel-Tap auf Interactables (Maus + emulierter Touch) — Dusch-Routine endet sofort, Gooby bleibt unsichtbar zurück

- **Repro (Desktop/Dev, `pointing/emulate_touch_from_mouse=true`):** Bad →
  Wanne EINMAL antippen. Erwartet: Gooby läuft zur Wanne, Vorhang zu,
  Silhouette, zweiter Tap später = abspülen + Hygiene. Tatsächlich: Hygiene
  bucht SOFORT (84,7→100 im selben Poll), `is_shower=true` aber
  `routine_aktiv=false` — und nach dem „Abspül"-Tap ist Gooby UNSICHTBAR ohne
  aktive Routine (Flow-Rettungsschritt macht ihn wieder sichtbar).
- **Ursache:** `interactables_host.gd:make_tap_area` (Zeilen 100–110) feuert
  `on_tap` sowohl für `InputEventMouseButton` ALS AUCH für den von
  `emulate_touch_from_mouse` synthetisierten `InputEventScreenTouch` — zwei
  Fires pro physischem Klick. In `klo_dusche.gd` trifft das eine echte Race:
  Fire 1 startet `_run_shower_routine` und hängt im `await gooby.walk_to(…)`;
  Fire 2 sieht `_routine_active=true` und ruft `finish_shower()` (bucht
  Hygiene, Vorhang auf). Die FORTGESETZTE Coroutine setzt danach
  `gooby.visible=false` und `_show_curtain(true)` — Zustand: Vorhang zu,
  Gooby weg, keine Routine. Auf Mobile reproduziert ein schnelles
  Doppeltippen (Kinderhände!) während Goobys Anlauf DIESELBE Race — der Bug
  ist also nicht nur Desktop-Kosmetik.
- **Weitere Treffer desselben Doppelfires:** Lichtschalter-Sheet öffnete sich
  in v3 ungewollt während der Tür-Navigation (`…_154716_75687`). Goobys
  eigener Streichel-Pfad ist NICHT betroffen (Zuwendungs-Lauf: 1 echter Tap
  buchte exakt +1 pet).
- **Beleg:** `flow_pt1_haus_rundgang_172356_80434/065_dusche_soll_zustand_FAIL.png`,
  `068_dusche_aufraeumen_FAIL.png` + lauf.log (`hygiene 84.7 -> 100.0`,
  „BUG-BELEG: Gooby unsichtbar OHNE aktive Routine"); gleiches Bild in v4/v5.
- **Fix-Verdacht:** (1) `make_tap_area` auf EINE Ereignisfamilie festlegen
  (bei gesetztem `emulate_touch_from_mouse` genügt `InputEventScreenTouch`)
  oder pro Frame deduplizieren; (2) unabhängig davon in
  `klo_dusche.gd:_run_shower_routine` nach dem `await walk_to` erneut
  `_routine_active` prüfen, bevor Gooby versteckt und der Vorhang gezogen
  wird — dann ist auch das organische Mobile-Doppeltippen abgesichert.

### B3 — MITTEL: Goobys Sprechblase (Kapsel = `MOUSE_FILTER_STOP`) schluckt Taps auf die Baumodus-Action-Bar

- **Repro:** Baumodus öffnen (Bett-Quest sagt „Platzier dein Bett! Gooby will
  kuscheln!"), Gooby läuft unter die Action-Bar — die kopf-folgende Blase
  schwebt über „Drehen"/„Platzieren". Tap auf den Knopf: die Kapsel
  (`ac_bubble.gd:_bauen`, `MOUSE_FILTER_STOP` + `gui_input`) fängt ihn, die
  Blase schließt sich, der Knopf feuert NIE.
- **Beleg:** Bau v1 `flow_pt1_baumodus_165312_78680/021_bett_rotation_merken.png`
  (Blase direkt über dem Drehen-Knopf) → `022_bett_drehen_FAIL.png` (Blase
  weg, `rot` blieb 0, Schritt-Timeout 16 s). Nach dem Flow-Wächter
  (`_tipp_frei_schritte`: warten bis die Knopfmitte frei ist) läuft derselbe
  Schritt in v2 sauber durch (rot 0→1 in 1,0 s).
- **Fix-Verdacht:** Die Blase reserviert nur die UiAnchors-Bottom-Zone
  (`ac_bubble.gd:_positionieren`); die Action-Bar des Bau-Docks
  (`build_ui_dock.gd:_build_action_bar`) hat keine Reservierung. Entweder die
  Action-Bar-Fläche via `UiAnchors.reserve` schützen und die kopf-folgende
  Kapsel dodgen lassen (Muster GoobyGespraech-Chips), oder die Kapsel im
  Baumodus auf `MOUSE_FILTER_IGNORE` schalten (Skip-Tap ist dort verzichtbar).

### B4 — MITTEL: Fernseher-Aus-Knopf landet UNTER der rechten HUD-Spalte (Quest/Profil gewinnen den Tap)

- **Repro:** Wohnzimmer, TV antippen (läuft: „Zapp! …"). Der Aus-Knopf
  (`GobtyAusKnopf`) ankert BOTTOM_RIGHT „106·f über der HUD-Daumen-Zeile"
  (`fernseher.gd:_layout_aus_knopf`) — im Leitformat quer reicht die rechte
  HUD-KNOPFSPALTE aber tiefer: Quest/Profil liegen ÜBER der Pill, der Tap
  trifft die HUD-Knöpfe.
- **Beleg:** `flow_pt1_haus_rundgang_172356_80434/019_fernseher_aus_ueberdeckung_FAIL.png`
  („Fer…"-Pill hinter Quest/Profil); der Flow weist die Überdeckung per
  STOP-Control-Check nach und schaltet den TV nur über einen nach links
  versetzten Ausweich-Tap aus (`020_fernseher_aus_links_tippen.png`, OK).
- **Fix-Verdacht:** Aus-Knopf-Rect gegen die HUD-Spalte dodgen (UiAnchors
  besitzt die Zonen-Logik bereits) oder Anker um eine Knopfspalten-Breite
  nach links ziehen (`offset_right` zusätzlich um die HUD-Spaltenbreite).

### B5 — NIEDRIG: Antwort-Chips können ohne Goobys Frage-Zeile erscheinen (Gefühls-Sperre verschluckt die Line)

- **Befund:** `SeeleRunner.stoss_gruss` → `_nach_moment` startet die Chips
  IMMER (`gooby_gespraech.gd:starte` → `_zeige_chips`), die zugehörige
  Gruß-Zeile hängt aber am Gefühls-Pfad (`melde_gefuehl` → `_feel_zeile`) und
  entfällt komplett, wenn `_entscheide_gefuehl` sperrt (laufendes Gefühl mit
  ≥ Prio oder `SoulFeelings.erlaubt`-Cooldown). Der Spieler sieht dann Chips
  wie „Tut mir leid, Gooby." ohne jedes „Warum" — im Lauf stand noch die alte
  Ball-Zeile („Ball! Bester Ball der Welt!") in der Blase.
- **Beleg:** `flow_pt1_zuwendung_171751_79688/030_chips_ansehen.png`
  (getriggert über den öffentlichen `stoss_gruss`-Hook kurz nach dem
  Ball-Gefühl; organisch identisch möglich, wenn der Raum-Gruß auf ein noch
  laufendes Gefühl trifft).
- **Fix-Verdacht:** Frage-Zeile an die Chips koppeln statt an das Gefühl —
  `GoobyGespraech.starte` soll die Anlass-Line selbst über `zeige_linie`
  bringen (unabhängig von der Feelings-Sperre), oder Chips nur öffnen, wenn
  die Line wirklich gezeigt wurde.

### B6 — NIEDRIG: Tagesbonus-Popup legt sich beim ALLERERSTEN Start über die laufende Guide-Tour

- **Befund:** Direkt nach dem Onboarding öffnen Guide-Tour („Schritt 1/9")
  UND Tagesbonus gleichzeitig; das Popup deckt die Tour-Karte ab. Technisch
  ist der Stapel sauber (abweisen/claimen funktioniert, Tour läuft danach
  weiter), aber zwei konkurrierende Erklär-Flächen im ersten Spielmoment
  verwässern die Tour.
- **Beleg:** `flow_pt1_tagesbonus_172056_79821/010_popup_ansehen.png` (Popup
  über der Tour-Karte), `020_claim_toast_da.png` (nach dem Claim übernimmt
  wieder die Tour).
- **Vorschlag:** Bonus-Angebot am Tag 1 bis zum Tour-Ende zurückstellen (der
  RewardHub kennt den Tour-Zustand über das Guide-Flag).

### B7 — HINWEIS: Klopapier-Mumie parkt Gooby AUF dem Küchentisch

- **Befund:** Das Random-Event `MumieSzene` friert Goobys Wandern ein
  (`set_wander_enabled(false)`) — erwischt es ihn auf einem Möbel (Beleg:
  mitten auf dem Küchentischchen), sitzt die eingewickelte Mumie unplausibel
  auf der Tischplatte, bis der Spieler sie freigetippt hat. Die Tap-Zone ist
  klein (0,9×1,2 m um Gooby), blockiert also nicht den Raum — es sieht nur
  schief aus und das Event konkurriert im Follow-Kamera-Bild mit Tür-Taps.
- **Beleg:** `flow_pt1_haus_rundgang_154716_75687/028_kueche_moebel_protokoll.png`
  („Ich bin eine MUMIE! …", Gooby aufs Tischchen gewickelt).
- **Vorschlag:** Beim Event-Start Gooby zuerst auf den nächsten
  Navmesh-Bodenpunkt setzen (Muster `walk_to`-Snap), dann wickeln.
- **Test-Konsequenz:** Alle PT-1-Flows legen Random-Events als ersten Schritt
  still (`_events_stilllegen` — GameState-Cooldowns, kein Code-Eingriff),
  sonst sind Tür-Läufe nicht deterministisch.

### B8 — HINWEIS (Testumgebung): llvmpipe-Sampling verpasst Kurzzustände; Qualitäts-Toast im Erst-Start

- Der Ball-Zustand `FLIEGT` war im Poll nie sichtbar (nur `GOOBY_HOLT` →
  `BRINGT_ZURUECK`) — unter llvmpipe (wenige FPS) ist die Flugphase kürzer
  als ein Poll-Intervall. Prüfungen auf solche Kurzzustände sollten am
  Counter (hier `balls`) hängen, nicht am Zustand — die PT-1-Flows tun das.
- Im Tagesbonus-Lauf erschien der Auto-Qualitäts-Toast („Bildrate war eine
  Weile im Keller…", `010_popup_ansehen.png`) — erwartbares Verhalten der
  Qualitäts-Stufung in der Software-Render-Umgebung, kein Spielfehler.

## Garten-Verifikation (Zusatzauftrag ASSET-ROT)

Auftrag war zu verifizieren, ob `treeDefault`, `treeFat`, `gardenBench`,
`potLarge` wegen „weicher GLB-Degradation in FurnitureNode" nicht spawnen.
**Ergebnis: Verdacht bestätigt im SYMPTOM, widerlegt in der URSACHE.**

1. Die 4 Items fehlen wirklich als Nodes im Garten (Grid führt sie, Raum
   zeigt sie nicht) — reproduziert in v4, v5 und im finalen Lauf.
2. GLB-Degradation ist es NICHT: headless laden/instanziieren alle GLBs
   sauber (`flow_pt1_diag_assets.gd`), und ein Live-`FurnitureNode.create`
   IM laufenden Garten liefert einen gültigen Node.
3. Tatsächliche Ursache: `GardenView.rebuild()` leert den geteilten
   `blockers()`-Mount und zerstört damit die von `RoomBase._spawn_furniture`
   dort geparkten `blocks_movement`-Möbel — Details und Fix-Verdacht in
   **B1**. Es trifft exakt die 4 genannten Items, weil nur sie im
   Garten-Default `blocks_movement=true` tragen.

## Spielgefühl Home/Bau/Füttern/Zuwendung — ehrliche Einschätzung

- **Baumodus:** fühlt sich rund an — Dock mit Lager-Karten, Status-Kapsel,
  Ebenen-Chips samt Kamera-Neigung zur Decke, HUD gleitet weg und federt
  zurück (P50 in beide Richtungen sauber verifiziert). Die Bett-Quest-Blase
  über der Action-Bar (B3) ist der einzige Stolperer.
- **Kühlschrank/Füttern:** bestes Home-Erlebnis — Regal-Sheet mit
  Vorrats-Badges, Junk-Warnung am Törtchen, ECHTE 3-Bisse-Inszenierung mit
  schwebender Speise, Verliebtheits-Herz beim Lieblingsessen und „Erster
  Happen"-Erfolg (+10 ᴳ). Kleiner Schönheitsfehler: die Sequenz spielt dort,
  wo Gooby gerade steht — hinter der Küchenzeile sieht man sie nur durch das
  X-Ray-Band.
- **Zuwendung:** Streichel-Kicher, Übermut-Gag („Paus-e-e! Mein Fell ist ganz
  zerzaust!" + Fell-Konfetti) und der Ball-Apport mit Kopfstoß-Rückgabe
  tragen emotional. Die Antwort-Chips sind ein schönes Ritual — ihnen fehlt
  nur manchmal die Frage (B5).
- **Tagesbonus:** Serie-Chips, Kulanz-Zeile („Ein Tag verpasst — kein
  Problem…") und die drei Abweis-Wege verhalten sich vorbildlich; nur das
  Timing gegen die Guide-Tour (B6) gehört sortiert.
- **Haus-Rundgang:** Türen mit Bestätigungskarte + Klemm-Gag funktionieren,
  aber die Follow-Kamera macht 3D-Ziele (Türen!) zu beweglichen Zielen — als
  Spieler schwenkt man oft nach. Die Interactables (TV, Lampe, Klo/Wanne)
  reagieren gut, sobald B2/B4 gefixt sind.

## Dateiliste (PT-1, nur eigene Dateihoheit)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_helfer.gd` (+ `.uid`) —
  geteilte Schicht: merke/prüfe-Zettel, UI-/Text-Sucher, HUD-P50-Prüfer,
  Möbel-Protokoll (fehlende Nodes!), Kamera-Pan-Bausteine, Tür-Reise mit/ohne
  Karte, Blasen-Wächter `_tipp_frei_schritte`/`text_frei`, Event-Stilllegung.
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_haus_rundgang.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_baumodus.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_kuehlschrank.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_zuwendung.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_tagesbonus.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt1_diag_assets.gd` (+ `.uid`)
  — headless GLB-/Katalog-Diagnose zu B1 (kein Playtest-Flow).
- `docs/playtest/G8-PT1-home-bau.md` (dieser Report)

Alle Flows `gdformat`- und `gdlint`-sauber; Import-Lauf unter dem flock
ausgeführt, `.uid`-Dateien liegen bei. Keine Spiel-Code-Änderungen.

## Screenshot-/Lauf-Pfade (Belege)

Basis: `/tmp/gooby-godot/artifacts/PLAYTEST/`

- Finale grüne Läufe: `flow_pt1_haus_rundgang_172356_80434/`,
  `flow_pt1_baumodus_171059_79392/`, `flow_pt1_kuehlschrank_171322_79527/`,
  `flow_pt1_zuwendung_171751_79688/`, `flow_pt1_tagesbonus_172056_79821/`
  (je `report.md`, `lauf.log`, `NNN_schritt.png`).
- Befund-Belege: B1 → `…172356_80434/099|100_*`; B2 →
  `…172356_80434/065|068_*` (plus v4/v5); B3 →
  `flow_pt1_baumodus_165312_78680/021|022_*`; B4 → `…172356_80434/019|020_*`;
  B5 → `flow_pt1_zuwendung_171751_79688/030_chips_ansehen.png`; B6 →
  `flow_pt1_tagesbonus_172056_79821/010|020_*`; B7 →
  `flow_pt1_haus_rundgang_154716_75687/028_kueche_moebel_protokoll.png`.
- Highlights (funktionierend): Baumodus-Drehung
  `flow_pt1_baumodus_171059_79392/023|024_*`, Decken-Ebene `041_*`, HUD-P50
  zurück `047_*`; Fütter-Herz `flow_pt1_kuehlschrank_171322_79527/032_*`,
  Badge ×2 `041_*`; Übermut `flow_pt1_zuwendung_171751_79688/018_*`, Chips
  `030_*`; Tagesbonus Tag 2 `flow_pt1_tagesbonus_172056_79821/026_*`, Kulanz
  `031_*`.
