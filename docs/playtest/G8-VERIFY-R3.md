# G8-VERIFY-R3 — Nachmessung der R2-Fixes + Kombinations-Playtests (W18/R3)

- **Agent:** VERIFY-PT · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Auftrag:** Die 7 R2-Fixes + 5 R2-Features (Commits `afa30159`…`36980df3`,
  s. `git log --oneline -12`) wie ein skeptischer QA-Lead NACHMESSEN: die 6
  wichtigsten End-to-End-Flows frisch fahren, dazu 2 NEUE Kombinations-Flows
  (`flow_verify_r3a/b`), die die R2-Features im Zusammenspiel statt einzeln
  testen. Keine Spiel-Code-Fixes — nur Flows + dieser Bericht. (Nachtrag:
  ein dritter eigener Flow `flow_verify_r3c` wurde nötig, um die
  FIX-1-Crash-Strecke trotz der Befunde V1/V5 wirklich zu erreichen.)
- **Methode:** Echte Spiel-Läufe (main.tscn, frisches `user://`, komplettes
  Onboarding, quer 2868x1320) unter
  `flock -w 7200 /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh <flow>`.
  Läufe liegen unter `/tmp/gooby-godot/artifacts/PLAYTEST/r3_*`. Wichtig für
  Nachahmer: Läufe in der Abendschicht (OS-Lokalzeit 18:00–05:00) können das
  Nachtevent `gewitter_angst` ziehen (Befund V1) — Verifikationsläufe deshalb
  mit `TZ=Etc/GMT+12` (lokal Vormittag) pinnen, wenn 3D-/Welt-Taps gebraucht
  werden.

## Lauf-Übersicht (R3-Läufe, `/tmp/gooby-godot/artifacts/PLAYTEST/…`)

| Lauf | Flow | Ergebnis | Kurzbefund |
| --- | --- | --- | --- |
| `r3_pt4_geschichten` | `flow_pt4_geschichten` | 27 OK / 9 FAIL | KEIN Crash (FIX-1-Sonde nicht erreicht) — Nachtevent `gewitter_angst` frisst ab Home-Entry alle Welt-Taps (V1), Bett nie platziert |
| `r3_pt4_geschichten_tag` | `flow_pt4_geschichten` (TZ-Tag) | 32 OK / 4 FAIL | A/B-Gegenprobe: OHNE Nachtevent ist die komplette Bett-Platzierung GRÜN (V1 damit belegt). Neuer Rest-Fail: der EINMALIGE `bett_antippen`-Tap verpufft direkt nach dem Baumodus (Kamera-Rückflug/Gooby am Bett, V5) → Story-Kapitel ab 024 Folge-Fails, B1-Sonde wieder nicht erreicht |
| `r3_pt4_quests` | `flow_pt4_quests` | **32/32 OK** | B2-Wache: „Panel lebendig=true Kinder=6 im offenen Blatt=true“ |
| `r3_pt4_sheets` | `flow_pt4_sheets` | 37 OK / 1 FAIL | B2-Wache grün; einziger Fail = erster Bett-Spot ungültig, weil Gooby nach GELÖSTEM Gewitter-Event schlafend liegen bleibt (V2) — Ausweich-Spot griff |
| `r3_fix3_dlc_hub` | `flow_fix3_dlc_hub` | **33/33 OK** | Settings-Overlay schließt von allein, Hub-Ladekarte statt „Trautes Heim“, Codes-Ausgang ebenso |
| `r3_pt1_haus_rundgang` | `flow_pt1_haus_rundgang` | 78 OK / 26 FAIL | Garten-B1-Wachen + TV-B4-Sonde GRÜN; 26 Fails sind EINE Kaskade: Guide-X-Tap verpufft im Pop-in-Moment, Karte bleibt offen und deckt die Innentüren (V3) |
| `r3_pt3_rahmen` | `flow_pt3_rahmen` | 23 OK / 20 FAIL (Watchdog) | KEIN Spiel-Befund: Boot in halbfertigen Parallel-Worker-Stand (`BeuteFlug`/`WochenVorhaben*` unbekannt → Compile-Kaskade, s. „Testinfrastruktur“) |
| `r3_pt3_rahmen_v2` | `flow_pt3_rahmen` (Rerun) | **57/57 OK** | Nach frischem Import komplett grün → Erstlauf-Hänger war reines Umgebungs-Artefakt. FIX-7 voll belegt: Wisch 0→312→692, Lücken-Wisch →925, Mausrad →1309, echter Touch-Drag AUF einer Kachel →1609; Resume-Countdown feldzentriert (Δ 2.8 px); Router-History sauber |
| `r3_pt2_stadtrundgang` | `flow_pt2_stadtrundgang` | 103 OK / 5 FAIL | OrtLeben-PFLICHT-Sonde 9/9 „ja“; die 5 Fails sind der Rehwei-Block (Vorfahrt-Flake: Auto rollte zur Goobytheke weiter, Prompt kam nie) |
| `r3_verify_a` | `flow_verify_r3a` (NEU) | **66 OK / 3 FAIL** (alle Sonden grün) | Klammer VOR Bonus (`gruss=true bonus=false`), Herz-Blatt 4/4 Elemente, B2-Wache „Kinder=7 im offenen Blatt“, „Was nun?“-Karte weicht (0 sichtbar), Bett-Quest erfüllt, Wisch-Scroll 0→312, Rekord: Pill-Stufe 2 + `rekord_gefeuert=true` + „Neuer Rekord!“ auf der Ergebnis-Karte. Die 3 Fails sind NUR der Flow-Ausstieg: Star-Hopper-Runde endete vor dem Pause-Tap, Results-Karte stand davor (Census: `MinigameHost/Results` STOP + Dim 0,55) — kein Spielbefund |
| `r3_verify_b` | `flow_verify_r3b` (NEU) | **116 OK / 4 FAIL** (alle Sonden grün) | OrtLeben Post „ja“ + Tierarzt „ja“; `settings_zu_von_allein` OK; Schlüssel-Kauf 3000→550 EXAKT; Regal 19 → Backen −9 exakt → Slot-3-Tap → Regal 22; Feierabend bucht +21 EXAKT; McGooby-Endkarte „Angebot=true Nochmal=true Feierabend=true“, Kasse 12+4=16 konsistent + exakt gutgeschrieben, Schichten gespielt=1. Die 4 Fails sind der Goobytheke-Block = Vorfahrt-Flake (V4), Ort danach ausgelassen |
| `r3_verify_c` | `flow_verify_r3c` (NEU) | **41/41 OK** | Gezielter B1-Nachfass: nach 4 s Kamera-Ruhe öffnet schon der ERSTE frisch projizierte Bett-Tap die Bettzeit-Karte (V5-Mechanik bestätigt); „Gute-Nacht-Geschichte“ → Startbuch-Tap (Original-Crash-Strecke) → Möhrenmond-Seite steht → 3 Wort-Chips gefüllt → „schöne Geschichte“, Blatt schließt von selbst — **kein Signal 11, Prozess lebt** |

## Verifikations-Tabelle: R2-Fix → Status → Beleg

| R2-Fix/Feature (Commit) | Status | Beleg |
| --- | --- | --- |
| **FIX-1** Geschichten-Buch-Crash Signal 11 (`afa30159`) | **VERIFIZIERT** | `r3_verify_c` 41/41: Startbuch-Tap über echte Eingabe-Events (Schritt 031, exakt die alte Segfault-Strecke) → Möhrenmond-Buchseite steht, 3 Wort-Chips + Seiten-/Blattwechsel (beide free()-Pfade), Blatt schließt von selbst, „kein Signal 11, Prozess lebt“ (lauf.log). Die Original-Flow-Läufe erreichten die Sonde nur wegen V1 (Nacht) bzw. V5 (Einmal-Tap) nicht — kein einziger Signal-11-/freed-Treffer in allen drei `lauf.log`. |
| **FIX-2** Tagesquest-Blatt beim 2. Öffnen leer (`e50ab550`) | **VERIFIZIERT** | `r3_pt4_quests` 32/32 + `r3_pt4_sheets` B2-Wache: „Panel lebendig=true Kinder=6 im offenen Blatt=true“ (lauf.log:71 bzw. :50); Kombi-Gegenprobe `r3_verify_a` (Kinder=7, nach Morgen-Ritual + Herz-Blatt davor) |
| **FIX-3** DLC-Hub aus Einstellungen unerreichbar + Hub-Ladekarte (`04c4634b`) | **VERIFIZIERT** | `r3_fix3_dlc_hub` 33/33: `settings_zu_von_allein` OK, `hub_karte_statt_heim` OK, Codes-Ausgang OK; Kombinations-Gegenprobe `r3_verify_b` Schritt 044 `settings_zu_von_allein` OK (Overlay bereits weg, danach Kachel-Taps + Kauf ohne Zurück-Umweg) |
| **FIX-4** Goobye Backen-Pill → Bottom-Leiste, Tür/Kunden sichtbar (`619f3dd5`) | **VERIFIZIERT** | `r3_verify_b` (lauf.log 176–211): echte Slot-Taps ×6/×8/×5 → Regal 19; Backen aus der Leiste bucht GENAU −9; Slot-3-Tap NACH dem Backen landet auf dem Slot (Regal 22); Kundenstrom lief, Feierabend bucht EXAKT +21 |
| **FIX-5** Garten-Defaults verschwinden (blockers-Ownership) (`c1ea2d89`) | **VERIFIZIERT** | `r3_pt1_haus_rundgang` Schritte 099–103 GRÜN: `garten_save_check`, `garten_asset_rot_check`, `garten_rebuild_anstossen`, `garten_blocker_wache` — Defaults überleben `rebuild()` |
| **FIX-6** Doppel-Feuer/Release-Tap/Blase/TV-Knopf (`c1ea2d89`) | **VERIFIZIERT** (B4-Sonde) | `r3_pt1_haus_rundgang` 017–020 GRÜN: `fernseher_tippen`, `fernseher_aus_ueberdeckung` (TV-Aus-Knopf frei), `fernseher_aus_tippen`; keine Doppel-Feuer-Symptome im Rundgang |
| **FIX-7** Touch-Drag scrollt über Kacheln (DragScroll) (`1ac7981d`) | **VERIFIZIERT** | `r3_pt3_rahmen_v2` 57/57: Wisch 0→312→692, Wisch in der Kachel-Lücke →925, Mausrad →1309, echter Touch-Drag AUF `Tile_memoryMatch` →1609 („Touch-Drag-Wache: scroll_vertical 1609 (Referenz vorher 1309)“); Kombi-Gegenprobe `r3_verify_a`: Wisch 0→312 + Kachel-Tap nach Scroll öffnet Pregame |
| **ORT-LEBEN** 9 Orte + PT2-B4 (`a00fc124`) | **VERIFIZIERT** | `r3_pt2_stadtrundgang`: OrtLeben-Sonde „ja“ in Goobytheke, Flughafen, Post, Baumarkt, Autohaus, Goobyman, Pow, Tierarzt, Gouhbus (lauf.log 1291–1472); `r3_verify_b`: Post „ja“, Tierarzt „ja“. Nicht gemessen blieben nur je Lauf die Vorfahrt-Flake-Orte (Rehwei bzw. Goobytheke — in je einem der beiden Läufe grün) |
| **SEELE 1+2** Stimmungs-Herz + Morgen-Ritual-Serialisierung (`5cb97df2`) | **VERIFIZIERT** | `r3_verify_a` (lauf.log 43/58): Aufwach-Klammer steht, Tagesbonus WARTET (`gruss=true bonus=false` — Kette statt Stapel); Herz-Blatt `titel=true laune=true grund=true tipp=true` |
| **A2** Rekord-Puls (`1ac7981d`) | **VERIFIZIERT** | `r3_verify_a` (lauf.log 153): Saat-Bestwert 1 überholt → `rekord_banner_zuendet` OK, „Rekord-Puls: Pill-Stufe 2, rekord_gefeuert=true“, Ergebnis-Karte zeigt „Neuer Rekord!“ (`065_pause_oeffnen_FAIL.png`) |

## Neue Befunde

### V1 — MITTEL-HOCH: Nachtevent „Gewitter-Angst“ frisst alle Welt-/3D-Taps und legt Bau-Flows lahm (18:00–05:00 lokal, 25 % je Home-Entry)

- **Was passiert:** `roll_on_start` würfelt bei JEDEM Home-Entry über die
  OS-Lokalzeit (`home_entry.gd:80-89`, `Time.get_datetime_dict_from_system`).
  `gewitter_angst` (Def `content/events/data/events.json`: Fenster
  18:00–05:00, `wahrscheinlichkeit` 0.25, Cooldown 3 Tage) kann damit auch
  DIREKT nach dem Onboarding zünden — mitten im ersten Bau-/Tutorial-Moment.
  Die Szene (`event_runner.gd:_setup_gewitter_angst`) macht Gooby UNSICHTBAR
  (+ Wandern aus) und legt ein Vollbild-`ColorRect` mit
  `MOUSE_FILTER_STOP` und Tint-Alpha 0,88 auf CanvasLayer 6
  (`event_props.gd:flashlight_overlay`). Folge: HUD-Knöpfe auf HÖHEREN Layern
  funktionieren weiter (Baumodus lässt sich öffnen!), aber ALLES darunter —
  sämtliche 3D-Taps (Bau-Spots, Möbel, Türen, Gooby) — wird vom Overlay
  geschluckt. Wer die Augen im Lichtkegel nicht findet, sitzt bis zu
  `timeout_min` 10 Minuten im Dunkeln.
- **Repro:** OS-Lokalzeit in 18:00–05:00 (z. B. `TZ` unverändert am Abend),
  frisches Save, Home-Entry wiederholen bis der 25-%-Roll zündet; dann
  Baumodus öffnen und einen Bett-Spot tippen → Tap verpufft, Spot wird nie
  gewählt, „Platzieren“ bleibt grau.
- **Beleg (Lauf `r3_pt4_geschichten`):** `011_coachmark_wegtippen.png`
  (alles gedimmt AUSSER Toast; HUD-Chip „Wo ist mein Gooby?“ = Gooby
  unsichtbar), `014_platzieren_bereit_erster_spot_FAIL.png` +
  `022_baumodus_fertig_FAIL.png` (heller Taschenlampen-Kegel WANDERT mit den
  Harness-Taps = `hole_px` folgt dem Zeiger; Bau-Leiste sichtbar, aber
  gedimmt/tot). Erklärt auch das R3-Rätsel „alles dunkel außer Toasts“:
  Toasts wohnen auf dem RewardLayer (90) ÜBER dem Overlay (6).
- **Fix-Verdacht:** (a) `_roll_random_event` unterdrücken, solange
  Onboarding/Guide läuft oder ein Bau-/Blatt-Kontext aktiv ist (Gate wie die
  P50-HUD-Weiche); (b) EventRunner beim Betreten des Baumodus pausieren
  (Overlay ausblenden, Timer stunden); (c) fürs Playtest-Harness: Nachtläufe
  mit 3D-Taps per `TZ` auf Tag pinnen (in der Methode oben dokumentiert).

### V2 — KLEIN: Nach gelöstem Gewitter-Event bleibt Gooby dauerhaft wander-deaktiviert liegen und blockiert Bau-Spots

- **Was passiert:** `_on_gewitter_petted` legt Gooby schlafen; `_resolve()`
  überspringt für `gewitter_angst` (in `keep_pose`,
  `event_runner.gd:890-892`) das `set_wander_enabled(true)`. Gooby bleibt
  liegen, wo er gefunden wurde — liegt er auf einer Bau-Zelle, ist der Spot
  ungültig und „Wegschicken“-Helfer greifen nicht (Wandern aus).
- **Repro:** Gewitter-Event lösen (Augen antippen, dann streicheln), direkt
  danach Baumodus öffnen und ein Möbel auf Goobys Zelle platzieren wollen.
- **Beleg (Lauf `r3_pt4_sheets`):** `029_platzieren_bereit_erster_spot_FAIL.png`
  — heller Raum, Gooby schläft unten links, Bubble „Danke… bei dir ist der
  Donner nur halb so laut… zzz…“, „Platzieren“ grau; der Ausweich-Spot des
  Flows griff danach (Lauf 37/38).
- **Fix-Verdacht:** Beim Baumodus-Start schlafende Event-Goobys aufwecken
  oder `keep_pose` nur bis zum nächsten Raum-/Modus-Wechsel halten.

### V3 — KLEIN (Testbarkeit) / UX-Risiko: Guide-X-Tap kann im Pop-in-Moment verpuffen — Karte bleibt offen und deckt Innentüren

- **Was passiert:** Im `r3_pt1_haus_rundgang` traf der `tipp_falls_da`-Tap
  auf `GuideBeenden` (Schritt 011, 1,5 s nach dem Bonus-Claim) die Karte
  „Goobster zieht ein! (Schritt 1/9)“ nicht — sie blieb bis Lauf-Ende offen.
  Die Karte STOPpt Eingaben unter ihrer Fläche (Layer 70): alle
  Innentür-Taps (Küche/Schlafzimmer/Bad, Schritte 024–086) verpufften, nur
  TV und Gartentür lagen außerhalb und liefen grün. Mechanik-Verdacht: der
  Harness liest das Button-Rect EINMAL und tippt dann — während
  `UiMotion.pop_in` (TRANS_BACK-Überschwinger) wandert der X-Knopf zwischen
  Rect-Lesen und Press/Release; SquishButton feuert nur bei Release IM
  Knopf. Für echte Spieler harmlos (nochmal tippen), für Flows eine Falle,
  weil `tipp_falls_da` KEINE Nachbedingung hat.
- **Beleg:** `r3_pt1_haus_rundgang/011_guide_tour_beenden.png` (Karte + X
  sichtbar, Tap ohne Wirkung), `024_kueche_tuer_tippen_FAIL.png` (Karte
  „Schritt 1/9“ steht noch, Tür-Tap-Zone verdeckt); Gegenprobe: Schritte
  092–096 Gartentür (außerhalb der Karte) GRÜN.
- **Fix-Verdacht:** Flows: nach `guide_tour_beenden` eine
  `warte_bis`-Wache „keine GuideKarte sichtbar“ (Retry statt Weiterlaufen);
  Harness: Rect unmittelbar vor Press UND Release neu lesen. Spielseitig
  optional: Guide-X erst nach Pop-in-Ende Eingaben annehmen.

### V4 — KLEIN (Testinfrastruktur): Vorfahrt-Flake — teleportiertes Auto löst den „betreten?“-Prompt manchmal nicht aus

- **Was passiert:** Der Flow-Helfer `fahre_zu` (flow_pt2_basis) teleportiert
  das Auto an den Parkplatz-Anker und zieht die Bremse. In ~1 von 10
  Ort-Anfahrten kommt der Prompt trotzdem nicht: im Stadtrundgang traf es
  den Rehwei (Beleg: Auto steht auf dem Screenshot an der GOOBYTHEKE —
  weitergerollt/abgetrieben), in `r3_verify_b` die Goobytheke (Log: „Auto
  steht (Bremse an) vor goobytheke ((-112.0, 0.0, 10.0))“, Prompt-Timeout
  20 s). Ortsunabhängig, je Lauf ein anderer Kandidat — echte Spieler
  FAHREN in den Trigger-Radius, darum kein Spieler-Befund.
- **Repro:** `flow_pt2_stadtrundgang` mehrfach fahren; im Schnitt ~1 Ort je
  Lauf verliert seinen Prompt (Kaskade von 4–5 Folge-Fails am selben Ort).
- **Beleg:** `r3_pt2_stadtrundgang/017_prompt_rehwei_FAIL.png`,
  `r3_verify_b/019_prompt_goobytheke_FAIL.png`.
- **Fix-Verdacht:** `fahre_zu` nach dem Teleport 1–2 Physik-Frames warten
  und die Distanz zum Trigger nachmessen (ggf. nachteleportieren), oder der
  Ort-Trigger sollte zusätzlich zustands- statt nur flankengesteuert prüfen
  (Auto STEHT im Radius ⇒ Prompt).

### V5 — KLEIN (Testbarkeit) / UX-Randfall: Einmal-Tap aufs frisch platzierte Bett verpufft direkt nach dem Baumodus (Kamera-Rückflug + Gooby am Bett)

- **Was passiert:** `flow_pt4_geschichten` wartet nach „Fertig“ nur 1,5 s
  und tippt das Bett dann GENAU EINMAL an (`tipp_3d` projiziert die
  Weltposition einmalig und tippt; die `erwarte`-Schleife fasst NICHT nach
  — `playtest_harness.gd:_aktion_tipp_3d` + `_warte_auf_bedingung`). Im
  Tag-Lauf stand in diesem Moment (a) die Kamera noch im Rückflug aus dem
  Baumodus (Projektion veraltet, llvmpipe: wenige FPS) und (b) Gooby
  DIREKT am/auf dem frisch platzierten Bett — der eine Tap traf ihn statt
  der Tap-Area des Betts. Die Bettzeit-Karte kam nie, alle Story-Schritte
  danach fielen als Kaskade (024→025→027→034). Für Spieler ein Randfall
  (nochmal tippen genügt), für Flows dieselbe Falle wie V3:
  Einmal-Taps ohne Nachfassen auf bewegte Ziele.
- **Repro:** Baumodus → Bett platzieren → „Fertig“ → innerhalb ~1,5 s das
  Bett antippen, während Gooby dort steht bzw. die Kamera noch fliegt.
- **Beleg (Lauf `r3_pt4_geschichten_tag`):** `023_bett_steht.png` (Gooby
  steht unmittelbar am Bett, Kamera noch in Baumodus-Nähe) vs.
  `024_bett_antippen_FAIL.png` (Kamera zurückgeflogen, Gooby inzwischen
  weg vom Bett, Karte trotzdem nie geöffnet — der Tap fiel in den einen
  frühen Moment). Platzierung selbst 012–023 komplett GRÜN.
- **Fix-Verdacht:** Harness: `tipp_3d` in der `erwarte`-Schleife
  nachfassen lassen (Position pro Versuch FRISCH projizieren) — exakt so
  umgeht es der neue `flow_verify_r3c` (Tipp-Serie + Titelzeilen-Schutz,
  s. u.); spielseitig optional: nach Bau-Commit Gooby vom neuen Möbel
  wegschicken.
- **Gegenprobe (bestätigt):** `r3_verify_c` — nach 4 s Kamera-Ruhe traf
  bereits der ERSTE frisch projizierte Tap (`025_bett_tipp_1.png` →
  `028_bettzeit_karte_da.png`), die beiden Nachfass-Taps landeten
  by design harmlos auf der Titelzeile der offenen Karte.

### Beobachtung (kein Befund): Guide-Karte und „Deine Knöpfe“-Coachmark stehen gleichzeitig

`r3_pt1_haus_rundgang/011_guide_tour_beenden.png` zeigt beide Karten
nebeneinander plus Sticker-Toast — die R2-Serialisierung (Bonus → Guide)
greift, aber der HUD-Coachmark läuft parallel zur Tour. Eng, aber bedienbar;
nur als Politur-Kandidat notiert.

## Testinfrastruktur-Notiz (kein Spiel-Befund)

`r3_pt3_rahmen` (Erstlauf) bootete in einen halbfertigen Baum-Stand der
~7 Parallel-Worker: `SCRIPT ERROR: Identifier "BeuteFlug" not declared`
(`daily_bonus_popup.gd:262`) bzw. `WochenVorhaben*` (`quest_service.gd`)
→ Compile-Kaskade über `reward_hub`/`home_state`/`dev_service`, Boot blieb
im Veil hängen, Watchdog nach 900 s. Die Klassen existieren inzwischen im
Baum (WIP anderer Worker); das `flock` serialisiert nur Godot-LÄUFE, nicht
die Datei-Edits. Konsequenz für künftige Runden: vor Playtest-Ketten einen
Import unter `flock` laufen lassen und bei Parse-Fehlern im `lauf.log` den
Lauf als Umgebungs-Artefakt werten und wiederholen. Gegenprobe bestanden:
Nach frischem Import lief `r3_pt3_rahmen_v2` mit 57/57 durch.

## Neue Kombinations-Flows (Dateihoheit dieser Runde)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_verify_r3a.gd` (+ `.uid`):
  Onboarding-Kette → Morgen-Sequenz mit gepinnter Uhr (Klammer VOR Bonus,
  IDEA-SEELE 1) → Stimmungs-Herz-Tap + Blatt-Inhalt (IDEA-SEELE 2) →
  Tagesquest-Blatt ZWEIMAL (FIX-2 + P50-Weiche) → Baumodus (HUD-Weiche +
  „Was nun?“-Karte weicht + Bett-Quest) → Arcade-Wisch-Scroll (FIX-7) +
  Kachel-Tap nach Scroll → Runde mit Rekord-Versuch (A2: Saat-Bestwert 1 →
  Banner + goldene Pill). Diagnose: `_veil_census`-Sonden loggen jeden
  großflächigen Schleier/STOP-Fänger samt CanvasLayer (Werkzeug zur
  V1-Diagnose).
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_verify_r3b.gd` (+ `.uid`):
  Stadt mit 3 Ort-Leben-Sonden (Goobytheke/Post/Tierarzt, ORT-LEBEN) →
  DLC-Hub aus Einstellungen, Overlay muss VON ALLEIN zu (FIX-3-Kern) →
  Goobye-Schlüssel 2500 ᴳ exakt → Goobye-Tag mit echten Slot-Taps + Backen +
  Slot-3-nach-Backen (FIX-4/B2) + Kundenstrom + „Feierabend bucht EXAKT den
  Tagesumsatz“ → History-Back in den Hub → McGooby-Probeschicht mit
  deterministischen Patty-Wendungen → ENDKARTE (Kassensturz konsistent,
  Angebot-Block sichtbar, Nochmal/Feierabend) → Hub → nach Hause.
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_verify_r3c.gd` (+ `.uid`):
  Gezielter B1-Nachfass (erbt von `flow_pt4_geschichten`): Bett-Bauquest,
  dann statt des Einmal-Taps eine NACHFASSENDE Bett-Tipp-Serie (pro
  Versuch frische Kamera-Projektion; steht die Bettzeit-Karte schon,
  tippen Folgeversuche harmlos auf ihre Titelzeile statt auf den
  schließenden Backdrop — V5-Umgehung), danach der Original-Story-Pfad
  über echte Taps: „Gute-Nacht-Geschichte“ → Startbuch (B1-Crash-Strecke)
  → 3 Wort-Chips → Blatt schließt von selbst.

## Screenshot-Pfade (Kern-Belege)

- V1: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt4_geschichten/011_coachmark_wegtippen.png`,
  `…/014_platzieren_bereit_erster_spot_FAIL.png`, `…/022_baumodus_fertig_FAIL.png`
- V2: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt4_sheets/029_platzieren_bereit_erster_spot_FAIL.png`
- V3: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt1_haus_rundgang/011_guide_tour_beenden.png`,
  `…/024_kueche_tuer_tippen_FAIL.png`, Gegenprobe `…/092_garten_tuer_tippen.png`
- V5: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt4_geschichten_tag/023_bett_steht.png`
  (Gooby am Bett) vs. `…/024_bett_antippen_FAIL.png`; Platzierung grün:
  `…/013_bett_spot_waehlen.png`–`022_baumodus_fertig.png`
- FIX-1-Kernbelege: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_verify_c/028_bettzeit_karte_da.png`
  (Bettzeit-Karte), `…/031_startbuch_oeffnen.png` (Möhrenmond-Seite NACH dem
  Ex-Crash-Tap), `…/038_wort_3_gooby_schlaeft.png` (3 Lücken gefüllt),
  `…/040_gute_nacht_ansehen.png` (Blatt zu, Gooby schläft: „Mmmh… schöne
  Geschichte… gute Nacht…“)
- FIX-5-Wachen grün: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt1_haus_rundgang/099_garten_save_check.png`–`103_garten_blocker_wache.png`
- Rehwei-Flake: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt2_stadtrundgang/017_prompt_rehwei_FAIL.png`
  (Auto steht an der GOOBYTHEKE statt am Rehwei)
- Compile-Kaskade: `/tmp/gooby-godot/artifacts/PLAYTEST/r3_pt3_rahmen/lauf.log` (Zeilen 6–18)
