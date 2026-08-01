# Strings — Struktur & Domain-Ownership

DE ist führend; EN muss für jede Domain paritätisch sein (Test:
`tests/unit/test_ui_strings.gd`). Loader: `scripts/ui/i18n.gd` (`I18nService`).

## Struktur

- `strings/de.json` + `strings/en.json` — verschachtelte Objekte, der Loader
  flacht zu `domain.key`-Pfaden ab. Arrays bleiben Arrays (`I18nService.items()`).
- Spätere Wellen können ALTERNATIV eigene Domain-Dateien unter
  `strings/de/<domain>.json` (+ `strings/en/<domain>.json`) anlegen — der Loader
  mergt sie automatisch. Key-Kollisionen sind ein Fehler (push_error) und
  werden vom Paritäts-Test als Fehlschlag gewertet.

## Domain-Ownership (Prefix → Owner)

| Prefix | Owner | Welle |
|---|---|---|
| `ui.*` (generische Buttons/Labels) | W1c UIKIT | W1 |
| `hud.*` | W1c UIKIT | W1 |
| `dialog.*` | W1c UIKIT | W1 |
| `onboarding.*` | W1c UIKIT | W1 |
| `settings.*` | W1c UIKIT | W1 |
| `news.*` | W1c UIKIT | W1 |
| `migration.*` | W1d STATE | W1 |
| `home.*`, `build.*` (Datei `strings/<locale>/home.json`) | W2a HOUSE | W2 |
| `updates.*` | W2b UPDATES | W2 |
| `mg.*`, `net.*` (Dateien `strings/<locale>/mg.json` + `net.json`) | W2d NETMG | W2 |
| `city.*`, `travel.*` (Datei `strings/<locale>/city.json`) | W3a CITY | W3 |
| `gvz.*` | W3b GVZ | W3 |
| `visit.*` | W3c VISIT | W3 |
| `social.*`, `board.*` (Datei `strings/<locale>/social.json`) | W3c VISIT | W3 |
| `events.*`, `stickers.*`, `interactions.*` | W3d CONTENT | W3 |
| `album.*`, `bad.*` (Dateien `strings/<locale>/events.json` + `album.json` + `bad.json`) | W3d CONTENT | W3 |
| `sys.*` (Datei `strings/<locale>/system.json` — Save-Recovery, Netz-Fehler) | W4-P4 TEXT | W4 |
| `veil.*` (Datei `strings/<locale>/veil.json` — LoadingVeil: `laedt` + `tips`-Array; W14/LOADING hat die 6 `tips`-WERTE im ACNH-Ton neu getextet — Keys/Anzahl unverändert, Ownership bleibt bei TEXT, Umformulieren jederzeit erlaubt) | W4-P4 TEXT | W4 |
| `craft.*`, `goobay.*`, `garten.*`, `shed.*`, `lieferung.*` (Datei `strings/<locale>/craft.json`) | M2 HAUS | M2 |
| `phone.*` (Datei `strings/<locale>/phone.json` — IGohbie-Shell, Apps, Fotomodus) | M2 ORTE | M2 |
| `audio.*` (Datei `strings/<locale>/audio.json` — Radiosender-Namen) | FIX-4 AUDIO | FIX |
| `cutscene.*` (Datei `strings/<locale>/cutscene.json` — Cutscene-Titel + Captions) | FIX-4 AUDIO | FIX |
| `recap.*` (Datei `strings/<locale>/recap.json` — Rückblick: Stationen, Statzeilen) | FIX-4 AUDIO | FIX |
| `rpferd.*` (Datei `strings/<locale>/rpferd.json` — Ranch-DLC Pferde: Rassen, Reiten, Zähmen, Zucht, Bindung) | RW-2 PFERDE | RW |
| `dev.*` + NEUE `settings.*`-Keys (Datei `strings/<locale>/settings.json` — Grafik/Anzeige/Steuerung/Barrierefreiheit/Benachrichtigungen/Spiel/Credits + Dev-Menü; die W1-`settings.*`-Keys bleiben in de.json/en.json) | RW-7 SETTINGS | RW |
| `rewards.*` (Datei `strings/<locale>/rewards.json` — Kühlschrank/Füttern, Mini-Fund, Level-Up-Feier, Speise-Namen) | EF-1 DOPAMIN | EF |
| `park.*` (Datei `strings/<locale>/park.json` — Funkelpark: Tor, Fahrgeschäfte, Naschgasse, Park-Speisen) | REST-4 | REST |
| `radio.*` (Datei `strings/<locale>/radio.json` — Radio-Oberfläche: Sender, Titel, Likes) | REST-4 | REST |
| `codes.*` (Datei `strings/<locale>/codes.json` — Aktionscodes-Screen: Eingabe, Fehler, Verlauf) | REST-4 | REST |
| `galerie.*` (Datei `strings/<locale>/galerie.json` — Fotogalerie: Raster, Vollansicht, Favoriten) | REST-4 | REST |
| `postkarten.*` (Datei `strings/<locale>/postkarten.json` — Postkarten-Archiv, Souvenirregal, Set-Bonus, Kartentexte) | REST-4 | REST |
| `revents.*` (Datei `strings/<locale>/ranch_events.json` — Ranch-Random-Events: Bubbles, Krähen-/Danke-Zeilen) | W13 RANCH | W13 |
| `nougat.*` (Datei `strings/<locale>/nougat.json` — Nougatschleuse: Install, Refusals, Klecks-Zeilen) + NEUE `rewards.food.*`-Keys der W13-Speisen (additiv in `rewards.json`) | W13 FOOD | W13 |
| `coop.*` (Datei `strings/<locale>/coop.json` — Coop-Fahrt: Einladung, Beifahrer-Radio, Kaufhinweis) + NEUE `social.nap.*`-Keys der Besucher-Couch-Regel (additiv in `social.json`) | W13B COUCH-COOP | W13 |
| NEUE `build.ebene.*`- + `build.girlande.*`-Keys (additiv in `home.json` — Ebenen-Umschalter Boden/Wand/Decke, Girlanden-Spann-Flow) + `shop.kategorie.girlanden` (EIN additiver Key in `shop.json` — Shop-Kategorie der Girlanden-Items) | W13B CEILING | W13 |
| `mail.*` (Datei `strings/<locale>/mail.json` — Post/Mail-Multiplayer: Briefe-Schalter, Briefkasten, Brief-schreiben-Flow, Fehler-Toasts) | W13B MAIL | W13-B |
| `shake.*` (Datei `strings/<locale>/shake.json` — Schüttel-Secret: Stufen-Bubbles, Schrei, Beschwerde) + NEUE `sleep.story.*`-Keys (additiv in `sleep.json` — Bücherregal, Abnutzung, Seiten, REHWEI-Hinweis) | W13B GESCHICHTEN | W13-B |
| `mg.cityDrive.*` + `mg.host.strike_*` + `mg.pregame.car` (Datei `strings/<locale>/citydrive.json` — City-Drive-Arcade-Runde, 3-Strikes-Teleport-Cutscene des Hosts, Pregame-Auto-Zeile) | W13B DRIVE | W13-B |
| `reisepass.*` (Datei `strings/<locale>/reisepass.json` — Reisepass 2.0: Pass-Vorder-/Stempelseite, MRZ-Gag, Galerie-Picker, Abflugtafel `reisepass.tafel.*`, Boarding-Pass `reisepass.pass.*`) | W13B REISEPASS | W13-B |
| `phone.gooberando.*` + `phone.guber.surge` (additiv in `strings/<locale>/phone.json` — Restaurant-Wahl/Warenkorb/Live-Karte der GOOBERANDO-App, Guber-Surge-Spruch) | W13B GOBERANDO | W13-B |
| `city_leben.*` (Datei `strings/<locale>/city_leben.json` — Ziel-Chevron-GPS-Toasts im Fahr-HUD) | W13B GOBERANDO | W13-B |
| `raumstation.*` + `gfree.*` + `rewards.food.weltraumMoehre` (Datei `strings/<locale>/raumstation.json` — Raumstation GOOB-1: Astro-Snack-Automat, Sternenfoto-Spot, Weltengooby-Toast; GOOBY-FREE-Shop am Flughafen inkl. Shuttle-Knopf; Anzeigename der Weltraum-Möhre) | W13B RAUMSTATION | W13-B |
| NEUE `city.laden.buecher_titel` + `city.laden.im_regal`-Keys (additiv in `city.json` — Bücher-Abschnitt im REHWEI-Laden, „Im Regal“-Ausgrauung) | W13B INTEGRATE | W13-B |
| NEUE `rewards.food.candy-bar` + `rewards.food.lollypop`-Keys (additiv in `rewards.json` — Anzeigenamen der letzten zwei treats-Set-Speisen) | W13B INTEGRATE | W13-B |
| `umzug.*` (Datei `strings/<locale>/umzug.json` — Account-Umzug per Panel-Code: Settings-Zeile, Umzugs-Sheet, Erfolgs-/Fehlertexte inkl. „Spielstand bleibt lokal“-Klartext) | W13C PANEL | W13-C |
| `instant.*` (Datei `strings/<locale>/instant.json` — InstantGooby-Feed: Feed-Karten, Möhren-Like, Posten-Flow, Fehler-Toasts) + `phone.app.instant`/`phone.app.instant_text` (additiv in `phone.json`) | W13C INSTANT | W13-C |
| `gobty.*` (Datei `strings/<locale>/gobty.json` — GOB.TY-Fernsehsender: Sender-UI, 5 Clip-Titel, 10 News-Schlagzeilen, Koch-/Sport-/Wetter-/Gute-Nacht-Banner inkl. `{symbole}`/`{datum}`-Platzhalter) | W13C GOBTY | W13-C |
| `goobyman.*` (Datei `strings/<locale>/goobyman.json` — GOOBYMAN-Drogerie: Laden-Sheet, Zahnputz-Blocker, Erste-Male-Bruch-Info, Umhang-Gag) + `city.ort.goobyman` (additiv in `city.json`) | W13C GOOBYMAN | W13-C |
| `garage.*` (Datei `strings/<locale>/garage.json` — Garage am Haus: Bau-Knopf, Rolltor, Kein-Auto-Hinweis) + NEUE `build.preset.*`-Keys (additiv in `home.json` — Layout-Presets „Raum speichern“) | W13C GARAGE | W13-C |
| `foto.*` + `settings.parallax` + `board.emote.selfie` (Datei `strings/<locale>/foto.json` — Fotomodus: Werkzeuge/Posen/Emotionen/Rahmen/Selfie; `settings.parallax` liegt BEWUSST in foto.json, weil settings.json fremd ist — Loader merged flach) + `social.selfie.*`-Block (additiv in `social.json`) | W13C FOTOWERK | W13-C |
| `fuettern.*` (Datei `strings/<locale>/fuettern.json` — Kühlschrank 2.0: Regal-Grid, Kategorien-Chips, Vorrats-Badge, Zucker-Warnung, Leerzustand, Mampf-Sprüche; die `rewards.kuehlschrank.*`/`rewards.fuettern.satt`-Keys bleiben beim EF-1-Owner; `fuettern.kommentar.*` gehört VOICE, s. u.) | W14 FRIDGE | W14 |
| `dlc.*` (Datei `strings/<locale>/dlc.json` — DLC-Hub: Settings-Sektion „DLC“, Bibliothek-Screen mit Ribbons NEU/BALD/INSTALLIERT, Detail-Sheet, Kommt-bald-Hammer-Gag) | W14 DLCHUB | W14 |
| `netset.*` (Datei `strings/<locale>/netset.json` — Mehrspieler-Settings `netset.mp.*` inkl. Fehlertext-Mapping `netset.mp.fehler.*` + Dev-Werkzeugkasten `netset.dev.*`) | W14 NETSET | W14 |
| `soul.linie.*` + `gespraech.*` + `fuettern.kommentar.*` (Datei `strings/<locale>/soul_lines.json` — 124 Gooby-Lines: Tageszeit/Wetter/W13-Features/Minispiel/Idle/Feiern/Wiedersehen + 4 `soul.linie.markt.stand.*`-Lines additiv von W15 INTEGRATE (MARKT-Request) + Mini-Dialog-Chips `gespraech.*` (Daten: `content/soul/data/gespraeche.json`) + Fütter-Kommentar-Schnittstelle für FRIDGE — kollisionsfrei zu deren `fuettern.*`-UI-Keys) | W14 VOICE | W14 |
| `loading.*` (Datei `strings/<locale>/loading.json` — Lade-Schirme, W7; NEUE `loading.boot.sprueche`-Keys additiv von W14 LOADING: 10 Boot-Cover-Sprüche) | W7 RANCH2 (Boot-Sprüche: W14 LOADING) | W7/W14 |
| NEUE `garten.samen_kurz`/`garten.samen_fehlt`/`garten.spruch.*`-Keys (additiv in `craft.json` — Saatgut-Anzeige + 4 Ernte-Sprüche der neuen Crops; `garten.*` bleibt M2-HAUS-Domain), `city.laden.saatgut_titel` (additiv in `city.json` — Saatgut-Abschnitt im REHWEI-Laden) + `rewards.food.radish`/`rewards.food.eggplant` (additiv in `rewards.json` — Anzeigenamen der neuen Ernte-Foods) | W15 CROPS | W15 |
| `markt.*` (Datei `strings/<locale>/markt.json` — Eigenstand des Wochenmarkts: Sheet-Tabs, Bestücken/Preis-Slider, Markttag-Replay, Abrechnungs-Karte, Tages-Kommentare, Schürze-Gag, Kräuterkasten-Hinweis; die `city.markt.*`-Ankauf-Keys bleiben bei W3a CITY) + NEUE `craft.rezept.r_vogelhaus`/`r_kraeuterkasten`/`r_windrad_deko`-Keys (additiv in `craft.json` — die drei W15-Rezepte) | W15 MARKT | W15 |
| `urlaub.*` (Datei `strings/<locale>/urlaub.json` — „Gooby im Urlaub besuchen“: Besuchen-Knopf/Szenen-Titel/Aktions-Toasts, 9 Souvenir-Namen `urlaub.souvenir.<destId>`, 3×8 AcBubble-Lines je Archetyp `urlaub.bubble.strand/berge/stadt`, Café-Bestell-Gag `urlaub.bestellung`, Soul-Erinnerungen `urlaub.soul.*`) | W15 URLAUB | W15 |

Regeln:
1. Nur der Owner editiert Keys seines Prefixes (in de.json/en.json NUR im
   eigenen Block — oder besser: eigene Domain-Datei anlegen).
2. Keine UI-Texte hartkodiert in `.gd` (Grep-Test auf Umlaut-Literale in
   `scripts/ui/**`).
3. Neue Domains hier eintragen (Append-only-Tabelle).

## Begriffs-Glossar (DE — verbindlich, E6-Audit)

- **Währung:** im Fließtext immer „Münzen“; das Symbol `ᴳ` nur in
  Preis-Chips/Buttons (z. B. `{preis} ᴳ`, „Stornieren (2 ᴳ)“).
- **Gemüse:** Leitbegriff ist **„Möhre“** (wie im REHWEI-Sortiment und
  `mg.carrotCatch.title` „Möhrenfang“) — „Karotte“ nur, wenn der Rhythmus
  es wirklich braucht.
- **GOOUHBUS:** heißt im Text **„Doktor“**, nie „Tierarzt“ (er behandelt
  Gooby als Patient, nicht als Tier).
- **Arcade:** feminin — **„die Arcade“** („Zur Arcade“, „Die Arcade ist
  zurück“).
- **Morph-Regler:** überall „Augenabstand / Augengröße / Ohrenlänge /
  Pausbäckchen“ (Onboarding `onboarding.slider_*` und Spiegel
  `bad.spiegel.*` identisch).
- **Anrede:** Du-Imperativ statt Infinitiv („Tipp für mehr“, nicht „Tippen
  für mehr“); Sticker-Hints für Punkteziele nutzen **„Hol …“**. Kinder
  siezen NPCs, NPCs duzen zurück — das bleibt so.
- **Typografie:** Ellipse `…` (nie `...`), Apostroph `’` (nie `'`),
  Anführungszeichen `„…“` paarig.

*(Doku-Pass W15/INTEGRATE: alle zuvor per >> angehängten Domains — zuletzt
`urlaub.*` — sind in die Tabelle oben gehoben; neue Nachträge bitte wieder
ans Dateiende per >> anhängen, der nächste Doku-Pass hebt sie.)*

>> `mg.carrotGuard.intro` (Datei `strings/<locale>/mg_carrot.json` — Intro-Banner der
W16/G3-Politur P10 MG-CARROT; alle übrigen `mg.carrotGuard.*`-Keys bleiben beim
MG-1-Owner in `mg_batch1.json`) | G3 P10 MG-CARROT | W16

>> NEUE `mail.compose.verwerfen_frage`/`mail.compose.weiterschreiben`-Keys (Datei `strings/<locale>/g3_post.json` — Nachfrage-Karte des MailSheet-Compose-Guards; `mail.*` bleibt W13B-MAIL-Domain, Loader merged flach) | G3 P07 UI-POST | W16

>> NEUE `mg.teaParty.intro`/`streak_banner`/`ende_zeit`/`ende_spills`-Keys (Datei
`strings/<locale>/mg_tea.json` — Intro-/Serien-/Spill-/Ergebnis-Banner der W17/G4-Generalkur
G4-TEA; die W2d-`mg.teaParty.*`-Bestandskeys bleiben in `mg.json`, Loader merged flach) | G4 G4-TEA | W17

>> `mg.carrotCatch.intro` (Datei `strings/<locale>/mg_catch.json` — Intro-Banner der
W17/G4-Politur G4-CATCH; alle übrigen `mg.carrotCatch.*`-Keys bleiben in `mg.json`
beim Rahmen-Owner, Loader merged flach) | G4 CATCH | W17

>> `g4travel.*` (Datei `strings/<locale>/g4_travel.json` — Reise-Strecke der G4-Politur:
9/9-Fortschritts-Kapsel der Reise-App + Weltengooby-Feier-Karte; `travel.*`/`reisepass.*`/
`raumstation.*` bleiben bei ihren Ownern, werden nur konsumiert) | G4 P16 UI-TRAVELAPP | W16

>> NEUE `mg.danceParty.intro`/`perfect`/`good`-Keys (Datei `strings/<locale>/mg_dance.json`
— Ziel-Banner + Hit-Quality-Popups der W17/G4-Politur G4-DANCE; die übrigen
`mg.danceParty.*`-Bestandskeys bleiben beim MG-2-Owner in `mg_batch2.json`, Loader
merged flach) | G4 DANCE | W17

>> `mg.fishingPond.intro` (Datei `strings/<locale>/mg_pond.json` — Intro-Banner der
W17/G4-Politur G4-POND; alle übrigen `mg.fishingPond.*`-Keys bleiben in `mg_batch2.json`
beim MG-2-Owner, Loader merged flach) | G4 POND | W17

>> NEUE `mg.bubblePop.intro`/`mg.bunnyHop.intro`-Keys (Datei `strings/<locale>/mg_himmel.json`
— Intro-Banner der W17/G4-Politur G4-HIMMEL; alle übrigen `mg.bubblePop.*`/`mg.bunnyHop.*`-Keys
bleiben beim MG-1-Owner in `mg_batch1.json`, Loader merged flach) | G4 HIMMEL | W17

>> NEUE `mg.goalieGooby.intro`/`intro_lob`/`intro_roller`-Keys (Datei
`strings/<locale>/mg_goalie.json` — Intro-Banner + Telegraph-Farb-Legende der W17/G4-Politur
G4-GOALIE; alle übrigen `mg.goalieGooby.*`-Keys bleiben beim MG-2-Owner in `mg_batch2.json`,
Loader merged flach) | G4 G4-GOALIE | W17

>> `mg.rocketRescue.intro` (Datei `strings/<locale>/mg_rocket.json` — Intro-Banner der
W17/G4-Politur G4-ROCKET; alle übrigen `mg.rocketRescue.*`-Keys bleiben beim MG-2-Owner
in `mg_batch2.json`, Loader merged flach) | G4 G4-ROCKET | W17
