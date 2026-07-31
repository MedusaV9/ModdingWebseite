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
| `veil.*` (Datei `strings/<locale>/veil.json` — LoadingVeil: `laedt` + `tips`-Array) | W4-P4 TEXT | W4 |
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
