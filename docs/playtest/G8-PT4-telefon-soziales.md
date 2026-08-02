# G8-PT4 — Playtest „Telefon & Soziales" (Welle H)

- **Agent:** PT-4 · **Branch:** `cursor/bubble-shield-loop` · **Datum:** 2.8.
- **Bereich:** IGohbie-Telefon (alle Apps, Freunde-App, Fotomodus), Radio/Kino/GOB.TY/
  Geschichten, Garderobe + Gestalten, Quests/Progression (Tagesquests, Erfolge,
  Level, Tagesbonus), Onboarding (frischer Spielstand).
- **Methode:** 7 Flows unter `tests/tools/playtest_flows/flow_pt4_*.gd` spielen das
  ECHTE Spiel (main.tscn) mit synthetischen Eingaben — jeder Lauf frisches
  `user://`, Start immer durchs komplette Onboarding. Formate: Leitformat quer
  2868x1320; Media-Flow zusätzlich hoch 1320x2868 (der Radio-Like-Altbefund war
  ein Hochformat-Befund). Ausführung strikt unter
  `flock /tmp/gooby_godot_global.lock tools/ci/run_playtest.sh flow_pt4_<x>`.

## Lauf-Übersicht (finale Läufe)

| Flow | Finaler Lauf (unter `/tmp/gooby-godot/artifacts/PLAYTEST/`) | Ergebnis |
| --- | --- | --- |
| `flow_pt4_onboarding` | `flow_pt4_onboarding_094135_32254` | 25 ok / 2 fail — beide Fails = Befund **B5** (Karten-Zentrierung), kein Hänger |
| `flow_pt4_telefon` | `flow_pt4_telefon_100423_36369` | **36 ok / 0 fail** |
| `flow_pt4_sheets` | `flow_pt4_sheets_104531_41689` | 31 ok / 1 fail — der Fail ist die eingebaute Regressions-Sonde für **B2** |
| `flow_pt4_media` (hoch) | `flow_pt4_media_115052_47287` | **57 ok / 0 fail** |
| `flow_pt4_garderobe` | `flow_pt4_garderobe_115237_48009` | **41 ok / 0 fail** |
| `flow_pt4_quests` | `flow_pt4_quests_113120_45422` | 29 ok / 1 fail — der Fail ist dieselbe **B2**-Sonde |
| `flow_pt4_geschichten` | `flow_pt4_geschichten_114152_46020` | **Crash-Repro erfolgreich**: Signal 11 im Schritt `startbuch_oeffnen_CRASH` (= Befund **B1**) |

## Verifikation der 7 Screenshot-Befunde des Users vom 1.8.

Die 7 Screenshots sind in `UserFeedback.md` als 6 Befund-Kategorien erfasst;
Zeile 7 ist der Pionier-Befund „Overlay-Stau nach Onboarding" (P58), dessen
Fix-Stand laut Auftrag mitzuprüfen war.

| # | Befund (1.8.) | Behoben? | Beleg |
| --- | --- | --- | --- |
| 1 | HUD-Kacheln schneiden Wörter ab („IGohbi/Garder/Gestalt") | **TEILWEISE — quer NEIN** | Hochformat-Dock: alle Labels voll (`flow_pt4_media_115052_47287/026_hud_zurueck_nach_radio.png`). **Leitformat quer 2868x1320: weiterhin gekürzt** — „Albu/IGohb/Garde/Gestal/Arcad/Quest" (`flow_pt4_quests_113120_45422/018_wohnzimmer_kurz.png`, stabiler Frame, keine Animation). Details → Befund **B4**. |
| 2 | Sprechblasen brechen mitten im Wort („Ohh, wird das sch") | **JA** | Finaler Blasen-Text bricht an Wortgrenzen, Endgröße wird vorm Typewriter reserviert (Prüfschritt `gobty_blase_ohne_wortabriss` OK, `flow_pt4_media_115052_47287/030…031_*.png`). Achtung beim Sichten: WÄHREND des Typewriter-Reveals endet der sichtbare Text naturgemäß mitten im Wort („Ich wollte dir Pfannkuche…") — das ist die Tipp-Animation, kein Umbruch-Bug. |
| 3 | Tagesquests-Blatt liegt ÜBER den Status-Leisten | **JA** | P50 greift: bei offenem Blatt weicht/dimmt das HUD (Prüfschritte `hud_weicht_dem_blatt` OK in `flow_pt4_sheets_104531_41689/014_*.png`, `hud_weicht_dem_radio` OK in media). Sichtbeleg mit gedimmten Statusleisten hinter dem Quest-Blatt: `flow_pt4_quests_113120_45422/023_erfolg_macher_ploppt.png`. |
| 4 | IGohbie-Telefon hat ein kaputtes Dunkel-Icon | **JA** | App-Grid: alle 7 Kacheln mit sauberen, hellen Icons + Labels (Taxi, Guber, GOOBERANDO, Kamera 🔒, Freunde, GoobyPal, InstantGooby) — kein Dunkel-Blob mehr (`flow_pt4_telefon_100423_36369/013_app_grid_ansehen.png`, Prüfschritt `kamera_kachel_kein_blob` OK). |
| 5 | Gestalten-Liste schneidet „Briefkasten" ab | **JA** | Font-Messung im Lauf: `Kat_briefkasten 'Briefkasten': Text 85 px / Platz 210 px, Trim aus=true -> ok` (lauf.log Garderobe-Lauf 2) + Sichtbeleg volles Label auf grünem Aktiv-Pill: `flow_pt4_garderobe_115237_48009/032_briefkasten_label_vollstaendig.png`. |
| 6 | Baumodus = Knopf-Salat | **JA** | Im Baumodus sind die HUD-Kacheln weggeglitten, nur Bau-Dock (Lager/Presets/Verkaufen/Fertig), Platzieren-Leiste und Sicht-Chips bleiben (`flow_pt4_sheets_104531_41689/025_hud_weicht_im_baumodus.png`; Bett-Bauquest end-zu-end in media/sheets/geschichten gespielt). Rest-Schönheitsfehler: die „Was nun?"-Hinweiskarte hängt AUCH im Baumodus oben rein → Befund **B6**. |
| 7 | Pionier-Befund P58: Overlay-Stau nach Onboarding (unsichtbarer Tagesbonus-Schleier schluckt Taps) | **JA (funktional)** | Frischer Spielstand in ALLEN 7 Läufen: Tagesbonus-Schleier ist jetzt SICHTBAR (gemessen: „Tagesbonus-Veil Alpha effektiv: 0.35", onboarding-lauf.log) und tappbar, Guide-Tour + Coachmark lassen sich wegklicken, kein Tap-Schlucker mehr. Optik-Rest (Stapel-Reihenfolge) → Befund **B7**. |

## Neue Befunde (G8, nach Schweregrad)

### B1 — BLOCKER: Gute-Nacht-Geschichte: Buch öffnen CRASHT das Spiel (Signal 11)

- **Repro (deterministisch, `flow_pt4_geschichten`):** frisches Onboarding →
  Baumodus → Bett platzieren (liegt im Start-Lager, Erste-Male-Bauquest) →
  Fertig → Bett antippen → „Gute-Nacht-Geschichte" → Bücherregal erscheint →
  Startbuch „Goobys Möhrenmond-Fibel" antippen → **Segfault, Spiel weg**.
- **Beleg:** `flow_pt4_geschichten_114152_46020/lauf.log` —
  `ERROR: Object … was freed or unreferenced while a signal is being emitted from it` →
  `handle_crash: Program crashed with signal 11` (Godot 4.4.1, kompletter
  Backtrace im Log). Screenshots bis `026_bibliothek_ansehen.png` (der Crash-Frame
  selbst kann nicht mehr geschrieben werden).
- **Fix-Verdacht:** `scripts/events/story_time.gd` — `_on_book_chosen` (Z. 224)
  läuft IM `pressed`-Signal des Buch-Knopfs (Z. 205) und ruft über
  `_open_page → _setze_inhalt` (Z. 289) ein hartes `_inhalt.free()` (Z. 294) auf
  die Bibliotheks-Ansicht — mitsamt dem Knopf, der gerade noch emittiert.
  `queue_free()` + `remove_child` (wie in `panel_sheet.gd:add_content`
  dokumentiert) oder `call_deferred` heilt das. Dasselbe Muster droht beim
  Seiten-Wechsel über die Wort-Chips (Z. 356/371 → `_setze_inhalt` Z. 279).

### B2 — KRITISCH: Tagesquests-Blatt ist beim ZWEITEN Öffnen leer

- **Repro:** Quest-Kachel → Blatt öffnet mit Inhalt → schließen (Runterwischen
  oder Dim-Tap) → Quest-Kachel erneut → Blatt öffnet **nur mit Titel + Griff,
  ohne Quests**. In beiden Flows als Sonde eingebaut
  (`wieder_oeffnen_regression`).
- **Beleg:** `flow_pt4_quests_113120_45422/028_wieder_oeffnen_regression_FAIL.png`
  (leeres Blatt „Tagesquests"), ebenso
  `flow_pt4_sheets_104531_41689/018_wieder_oeffnen_regression_FAIL.png`.
- **Fix-Verdacht:** `scripts/logic/quests/quest_service.gd:open_panel()` cached
  `_sheet` und `_panel` und reicht beim Wieder-Öffnen DENSELBEN `_panel` erneut
  an `PanelSheet.add_content()` (`scripts/ui/panel_sheet.gd:139`). `add_content`
  hängt erst ALLE `_body`-Kinder ab und `queue_free()`t sie — auch wenn das Kind
  identisch mit dem neu einzuhängenden `node` ist — und fügt den bereits
  todgeweihten Knoten wieder ein → im nächsten Frame verschwindet der Inhalt.
  Fix: in der Schleife `if child == node: continue` (oder im Service das Panel
  pro Öffnen neu bauen). Betrifft potenziell JEDEN Aufrufer, der Inhalt cached.

### B3 — MITTEL: Kamera-Pan löst Interactables/Türen aus (Tap feuert auf PRESS)

- **Repro:** Ein-Finger-Drag (Kamera-Pan) mit Startpunkt AUF einem Interactable
  (Tür, Radio, Lampe …) → das Interactable feuert SOFORT beim Press, obwohl der
  Spieler nur schwenken wollte.
- **Beleg:** `flow_pt4_media_115052_47287/026…027_*.png` — zwischen den beiden
  Frames lag nur der Eck-Wisch (Press bei 25 % / 66 % Bildschirm, auf der offenen
  Schlafzimmertür) → Dialog „Schlafzimmer betreten?" steht offen, ohne dass je
  „getippt" wurde.
- **Fix-Verdacht:** `scripts/home/interactables/interactables_host.gd:100–109`
  (`make_tap_area`) und `scripts/home/door_transition.gd:340–351` behandeln
  bereits das PRESS-Event als Tap — ohne Drag-Schwelle/Release-Prüfung. Tap erst
  bei Release und nur, wenn der Finger keine Pan-Schwelle überschritten hat
  (denselben Gesten-Arbiter nutzen wie der Boden-Pan des `HomeCameraRig`).

### B4 — MITTEL: HUD-Kachel-Labels im Leitformat (quer) weiterhin gekürzt

- **Rest von User-Befund 1:** Im Querformat 2868x1320 zeigen die rechten
  Mini-Kacheln „Albu/IGohb/Garde/Gestal/Arcad/Quest" (stabiler Frame:
  `flow_pt4_quests_113120_45422/018_wohnzimmer_kurz.png`); im Hochformat-Dock
  sind alle Labels voll.
- **Fix-Verdacht:** Die Querformat-Randspalte dampft die Kachelbreite ein
  (`hud.gd:_fit_landscape_column`), übrig bleiben nach 2×14 px
  StyleBox-Innenrand nur ~18 px Textbreite — da passt selbst
  `HudLabelFit.MIN_PX = 8` nicht („Garderobe" braucht ~45 px), also greift der
  Ellipsis-/Clip-Fallback. Das P50-Versprechen „nie mehr abgeschnitten" braucht
  hier eine Kurzform-Tabelle (z. B. „Bau/Mode/Quest"), breitere Kacheln oder
  Label UNTER der Kachel.

### B5 — KLEIN: Onboarding-Karten quer nicht zentriert, Editor-Karte gequetscht

- **Beleg:** `flow_pt4_onboarding_094135_32254/003_welcome_karte_zentriert_FAIL.png`
  und `010_editor_karte_zentriert_FAIL.png`; Messung im Lauf: Karten-Mitte 664 px
  bei 1564 px Canvas-Breite (7,5 % links der Mitte). Auf der Editor-Karte wirken
  Vorschau + Regler in 2868x1320 gedrängt; in `007_spitzname_weiter.png` steht
  über dem „Augenabstand"-Regler ein abgeschnittenes Textfragment („Dr").
- **Fix-Verdacht:** Onboarding-Spalte reserviert rechts Platz (Safe-Area/Panel),
  zentriert aber am Gesamt-Canvas vorbei — Karten am nutzbaren Feld ausrichten.

### B6 — KLEIN: „Was nun?"-Hinweiskarte hängt über Telefon und Bau-UI

- **Beleg:** `flow_pt4_telefon_100423_36369/013_app_grid_ansehen.png` (Karte
  liegt über der Telefon-Oberkante samt Uhr/Status) und
  `flow_pt4_sheets_104531_41689/025_hud_weicht_im_baumodus.png` (Karte über dem
  Baumodus). Beim Quest-Blatt wird der Hinweis bereits korrekt versteckt
  (`refresh_hint`-Gate) — Telefon-Overlay und Baumodus fehlen in dem Gate.

### B7 — KLEIN: Overlay-Stapel direkt nach dem Onboarding (nur Optik)

- **Beleg:** `flow_pt4_onboarding_094135_32254/013_onboarding_fertig.png` und
  `015_tagesbonus_erscheint.png`: direkt nach dem Onboarding stehen DREI Lagen
  gleichzeitig — Tagesbonus-Popup ÜBER der Guide-Tour-Karte („Schritt 1/9")
  ÜBER der „…Knöpfe"-Erklärkarte. Schon WÄHREND des Onboardings ploppt der
  „Erfolg: Stickerzeit — +10 Münzen!"-Toast plus eine „Qualität
  angepasst"-Systemkarte über die Editor-Karte (`007_spitzname_weiter.png`).
  Funktional kein Jam mehr (alles der Reihe nach wegtippbar, s. Verifikation
  #7) — aber der erste Spielmoment wirkt überladen. Wunsch: Overlays
  nacheinander (Bonus → Tour → Hinweis), Erfolgs-Toasts erst im freien Spiel.

### B8 — HINWEIS: Log-Rauschen beim App-Öffnen im Telefon

- **Beleg:** 6× `ERROR: Can't use get_node() with absolute paths from outside
  the active scene tree` in `flow_pt4_telefon_100423_36369/lauf.log` (je einer
  pro App-Start, z. B. `scripts/city/phone/fahrdienst_app.gd`).
- **Fix-Verdacht:** Apps rufen Autoload-Lookups (`get_node_or_null("/root/…")`)
  schon im Konstruktor/vor `add_child` auf. Lookup in `_ready()` verschieben
  oder `Engine.get_main_loop().root` nutzen. Nicht fatal, verdeckt aber echte
  Fehler im Log.

## Positiv verifiziert (Auszug)

- **P53 Sheet-System:** Radio- und Tagesquests-Blatt: Slide-up, Hintergrund-Dim
  (blockiert Taps), Runterwischen am Griff schließt, Dim-Tap schließt, Fokus
  kehrt zum HUD zurück. Radio-Like-Knopf liegt im Hochformat KOMPLETT im Canvas
  (`flow_pt4_media_115052_47287/021_radio_laeuft_ansehen.png`), Like landet im
  Save („Gemerkt als Lieblingssong!", `023_titel_liken.png`).
- **P52 Telefon:** links-Wisch = zurück zum Grid, runter-Wisch = Telefon zu,
  Home-Balken funktioniert, alle Apps öffnen (Taxi, Guber, GOOBERANDO, Freunde,
  GoobyPal, InstantGooby), Kamera/Fotomodus ist auf frischem Spielstand sauber
  level-gesperrt (Sperr-Toast statt App — tieferer Fotomodus-Test braucht
  einen Spielstand mit freigeschaltetem Level).
- **Freunde-App:** korrekter Offline-Zustand in der Sandbox („Offline — Freunde
  brauchen Internet"), Freundes-Code-Zeile + „Freund hinzufügen" vorhanden
  (`flow_pt4_telefon_100423_36369/027_app_freunde_ansehen.png`).
- **Quest-Loop komplett:** Tagesquest „Einkaufsbummel" durch echten
  Garderoben-Kauf erfüllt → „Abholen" → „Quest geschafft! +15 Münzen, +8 XP" →
  Erfolg „Macher — +10 Münzen!" ploppt, Münzen im Save gebucht, Haken
  „Erledigt!" (`flow_pt4_quests_113120_45422/023_erfolg_macher_ploppt.png`).
- **Tagesbonus:** „+20 Münzen — bis morgen!" erscheint nach dem Onboarding und
  ist einsammelbar (alle Läufe, Schritt `tagesbonus_abholen`).
- **P54 Garderobe/Gestalten:** Kategorie-Chips, Kauf mit Feedback (Beanie 100
  Münzen → im Besitz + angelegt, Save-Pfad `cosmetics.outfits.*` geprüft),
  zu-teuer-Fall ohne Abbuchung (Krone 1200) mit Toast „Dafür reichen die Münzen
  nicht." (`flow_pt4_garderobe_115237_48009/036_kugel_kaufen_zu_teuer.png`,
  `039_wand_kategorie.png`), Briefkasten-/Wand-Kategorien inkl. Scroll.
- **GOB.TY:** Fernseher an → Bild + „Fernseher aus"-Knopf, Zappen wechselt Clip
  („Zapp!…"), Ausschalten räumt auf (`flow_pt4_media_115052_47287/030…037_*.png`).
- **Geschichten-Blatt (ohne Buch-Tap):** Bettzeit-Karte → „Gute-Nacht-
  Geschichte" → Bücherregal öffnet, Runterwischen schließt (P53 gilt auch hier).

## Dateien (Dateihoheit PT-4)

- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_basis.gd` (+ `.uid`) —
  gemeinsame Onboarding-/Bett-Bauquest-/Prüf-Helfer
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_onboarding.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_telefon.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_sheets.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_media.gd` (+ `.uid`) — im
  Hochformat starten: `tools/ci/run_playtest.sh flow_pt4_media 1320x2868`
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_garderobe.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_quests.gd` (+ `.uid`)
- `GOOBY-GODOT/tests/tools/playtest_flows/flow_pt4_geschichten.gd` (+ `.uid`) —
  ABSICHTLICHER Crash-Repro für B1; erst nach dem Fix wieder grün erwartbar
- `docs/playtest/G8-PT4-telefon-soziales.md` (dieser Bericht)

Alle Flows `gdformat`/`gdlint`-sauber. Die B2-Sonden (`wieder_oeffnen_regression`)
und die B5-Zentrierungs-Messungen bleiben absichtlich als harte Prüfungen in den
Flows — sie werden grün, sobald die Befunde gefixt sind.

## Screenshot-/Artefakt-Pfade

Alle Läufe unter `/tmp/gooby-godot/artifacts/PLAYTEST/<lauf>/` mit
`report.md`, `lauf.log`, `lauf.json` und einem PNG pro Schritt:

- `flow_pt4_onboarding_094135_32254/` (quer)
- `flow_pt4_telefon_100423_36369/` (quer)
- `flow_pt4_sheets_104531_41689/` (quer)
- `flow_pt4_media_115052_47287/` (hoch 1320x2868)
- `flow_pt4_garderobe_115237_48009/` (quer)
- `flow_pt4_quests_113120_45422/` (quer)
- `flow_pt4_geschichten_114152_46020/` (quer, Crash-Repro inkl. Backtrace im
  `lauf.log`)
