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

Regeln:
1. Nur der Owner editiert Keys seines Prefixes (in de.json/en.json NUR im
   eigenen Block — oder besser: eigene Domain-Datei anlegen).
2. Keine UI-Texte hartkodiert in `.gd` (Grep-Test auf Umlaut-Literale in
   `scripts/ui/**`).
3. Neue Domains hier eintragen (Append-only-Tabelle).
