# GOOBY Update-System (Packs) — Handbuch

Owner: W2b UPDATES · Design-Grundlage: `docs/godot-rewrite/B-updates.md` (bindend) ·
Code: `GOOBY-GODOT/scripts/updates/` · Stand: M1 (Godot 4.4.1).

Das Update-System liefert **fast alles ohne neue .ipa** aus: Inhalte kommen als
Daten-Packs (`.pck`) per „Suche nach Updates“-Knopf in den Einstellungen aufs Gerät.
Offline-first: ohne Netz läuft das Spiel immer normal weiter.

---

## 1. Überblick & Architektur

```
┌─────────────────────────┐     baut .pck + manifest.json
│ privates Haupt-Repo     │────────────────────────────────┐
│ (content/<pack>/**)     │  GitHub Actions                │
└─────────────────────────┘  (.github/workflows/           ▼
                              gooby-packs.yml)   ┌──────────────────────┐
                                                 │ GitHub-Release       │
                                                 │ Tag `updates`:       │
                                                 │  manifest.json       │
                                                 │  config.json         │
                                                 │  <id>-v<x.y.z>.pck   │
                                                 └──────────┬───────────┘
                                                            │ HTTPS (eine feste URL)
                                                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ CLIENT (iPhone, Sideload-IPA)                                            │
│                                                                          │
│ Settings-Knopf ──▶ UpdateManager (scripts/updates/update_service.gd)     │
│                      manifest holen → vergleichen → laden → sha256       │
│                      → user://packs/<id>-v<ver>.pck + installed.json     │
│                                                                          │
│ Boot:  PackLoader (pack_loader.gd)  ── Boot-Guard (boot_guard.gd)        │
│          lädt user://-Packs nach Priorität in res://content/<id>/        │
│        ContentRegistry (content_registry.gd)                             │
│          mergt eingebaute + Pack-Daten → EINE Sicht für alle Systeme     │
└──────────────────────────────────────────────────────────────────────────┘
```

Grundprinzipien (Doc B, Kurzfassung):

- **Deterministischer Boot statt Hot-Reload:** `.pck`-Downloads wirken ab dem
  nächsten Start (bzw. Soft-Restart). Nur der `config`-Pack (plain JSON) wirkt sofort.
- **Data-only:** Packs enthalten JSON/Assets, **niemals GDScript**. Neues *Verhalten*
  braucht bewusst eine neue IPA (→ §6).
- **Selbstheilung:** Boot-Guard mit Crash-Zähler; das Spiel ist nie soft-locked (→ §5.3).

## 2. Pack-Typen & Zuständigkeiten

| Pack-Id | Inhalt | Typ | Priorität | Team / ändert sich |
|---|---|---|---|---|
| `core` | Basis-Content-Daten (Kataloge, Quests, Level-Daten) | PCK | 100 | Core-Team, selten |
| `balance` | Zahlenwerte/Chancen (z. B. `zahnbuersten_bruch_chance`), Preise, Timer | PCK | 200 | oft |
| `events` | Zeitfenster-Events `{id, start, end, payload}` | PCK | 300 | oft |
| `cosmetics` | Skins/Outfits/Deko: Katalog-JSON + Assets | PCK | 400 | Cosmetics-Team, oft |
| `stickers` | Sticker-Katalog + PNGs (deutsch beschriftet) | PCK | 500 | oft |
| `codes` | Einlöse-Codes `{id, secret_sha256, effect, once}` | PCK | 600 | oft |
| `config` | Remote-Settings: **Server-IP/Port**, Feature-Flags, News-Text | **plain JSON** | 700 | jederzeit, wirkt sofort |

- Höhere Priorität = später gemergt = **gewinnt** bei Kollisionen (Registry, §5.4).
- Quell-Ordner im Repo: `GOOBY-GODOT/content/<id>/` mit `pack.json` + `data/*.json`
  (+ optional `assets/`). Exportiert landet alles unter `res://content/<id>/…` —
  namespaced, zwei Packs können sich nie gegenseitig Dateien überschreiben.
- `pack.json`-Schema:

```json
{
	"schema": 1,
	"id": "cosmetics",
	"version": "1.4.0",
	"priority": 400,
	"min_native": "5.0.0",
	"domains": ["cosmetics"],
	"name_de": "Cosmetics",
	"notes_de": "12 neue Hüte"
}
```

- **Codes-Detail:** Der Content liegt (später) öffentlich → Code-Wörter stehen NIE im
  Klartext im Pack, sondern als `secret_sha256` der normalisierten Eingabe
  (lowercase, Whitespace raus). Der Client hasht die Eingabe und vergleicht.
- Domain-Dateiformate (`data/<domain>.json`): Listen-Domains
  (`cosmetics`/`stickers`/`codes`/`events`) = `{"schema":1,"items":[{"id":…},…]}`;
  `balance` = `{"schema":1,"values":{…}}`; `config` = flaches Objekt
  (`content/config/config.example.json` ist die kommentierte Referenz).

## 3. manifest.json-Referenz

Eine feste URL liefert den kompletten Update-Stand (Release-Asset am Tag `updates`):

```json
{
	"schema": 1,
	"latest_native": "5.1.0",
	"notes_de": "Kurztext fürs Update-Panel",
	"published_at": "2026-07-24T20:00:00Z",
	"packs": [
		{
			"id": "cosmetics",
			"version": "1.4.0",
			"type": "pck",
			"url": "https://github.com/…/releases/download/updates/cosmetics-v1.4.0.pck",
			"sha256": "e3b0c442…(64 hex)",
			"size": 1848320,
			"min_native": "5.0.0",
			"priority": 400,
			"notes_de": "12 neue Hüte"
		}
	]
}
```

Feld für Feld:

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `schema` | ✔ | Manifest-Formatversion, aktuell `1`. Unbekannt → Client ignoriert das Manifest (Fehlertoast). |
| `latest_native` | ✔ | Neueste App-(IPA-)Version. Größer als installierte App → „Neue App-Version nötig“-Hinweis. |
| `notes_de` | – | Deutscher Kurztext fürs Panel. |
| `packs[].id` | ✔ | Pack-Id (§2). Doppelte Ids → Manifest ungültig. |
| `packs[].version` | ✔ | Strikt semver `MAJOR.MINOR.PATCH`. MAJOR = Format-Bruch (i. d. R. mit `min_native`-Bump), MINOR = neuer Content, PATCH = Fix. |
| `packs[].url` | ✔ | Download-URL. DEV/Tests: auch `file:///…`, `user://…`, `res://…` erlaubt. |
| `packs[].sha256` | ✔ | Hex-sha256 der Datei; Mismatch → Download wird verworfen. |
| `packs[].min_native` | ✔ | Mindest-App-Version. Größer als installierte App → Pack wird **nie** geladen, Panel zeigt „braucht neue IPA“. |
| `packs[].priority` | – | Merge-Reihenfolge; fehlt → Default-Tabelle (§2), unbekannte Ids → 900. |
| `packs[].type` | – | `pck` (Default) oder `json` (nur `config`). |
| `packs[].size`/`notes_de` | – | Anzeige im Bestätigungs-Dialog. |

Parser/Validator: `scripts/updates/manifest.gd` (`UpdatesManifest.parse/validate`).
Erzeugt wird das Manifest von `tools/packs/build_manifest.mjs` (nie von Hand!).

## 4. So shippt das Cosmetics-Team ein Update — in 5 Schritten

1. **Ändern:** Nur im eigenen Ordner arbeiten: `GOOBY-GODOT/content/cosmetics/`
   (Katalog `data/cosmetics.json`, Assets unter `assets/`). Kein `.gd`, keine
   fremden Ordner — CI/Review lehnt das ab (Data-only-Policy §8).
2. **Version bumpen:** In `content/cosmetics/pack.json` die `version` erhöhen
   (neuer Content = MINOR, Fix = PATCH). `notes_de` kurz pflegen — das sehen
   die Spieler im Update-Panel.
3. **PR + Merge:** Branch → PR → Merge auf `main`. (CODEOWNERS kann
   `content/cosmetics/` fest dem Team zuordnen.)
4. **Workflow starten:** GitHub → Actions → **gooby-packs** → „Run workflow“
   (Input `packs`: `cosmetics` oder `all`, `publish`: `true`). Die CI baut das
   Pack (`--export-pack`), lädt es probeweise (Smoketest!), berechnet sha256,
   regeneriert `manifest.json` und hängt alles an den Release-Tag `updates`.
5. **Fertig.** Spieler drücken in den Einstellungen „Nach Updates suchen“ →
   nur das Cosmetics-Pack wird geladen; aktiv nach Neustart. Kein anderes Team,
   kein IPA-Build involviert. Der nächste IPA-Build bettet den neuen Stand
   automatisch ein (alle `content/`-Ordner sind Teil des Projekts).

Lokal testen (ohne CI): `tools/packs/build_packs.sh cosmetics` baut nach
`GOOBY-GODOT/build/packs/` und erzeugt ein `manifest.json` mit `file://`-URLs —
das kann man dem UpdateService direkt als `manifest_url_override` füttern
(so arbeitet auch `tests/unit/test_updates_flow.gd`).

## 5. Client-Verhalten

### 5.1 „Suche nach Updates“ (Settings-Knopf)

Kette: W1c-`settings_screen.gd` feuert `update_check_requested` und ruft
`/root/UpdateManager.check_for_updates()` (Duck-Typing). Ablauf im Service:

1. Manifest von der konfigurierten URL holen (10 s Timeout). Quelle: Override →
   Remote-Config (`user://packs/config.json`) → eingebauter `config`-Pack
   (`manifest_url`). Offline/Fehler → Ergebnis `ERROR`, Toast „Gerade nicht
   erreichbar — du kannst ganz normal weiterspielen“. Niemals blockierend.
2. `latest_native` > App-Version → `NEEDS_NATIVE` („Neue App-Version nötig —
   bitte neue IPA installieren“). Keine Auto-IPA-Downloads.
3. Pro Pack: effektive Version = `max(eingebaut, user://-installiert)`. Manifest
   größer? → Kandidat. `min_native` > App-Version → Kandidat wird **nicht**
   geladen, sondern als „braucht neue IPA“ gemeldet (Gate).
4. Download nach `user://packs/tmp/<datei>.part` → sha256-Verify (streaming,
   `HashingContext`) → Move nach `user://packs/<id>-v<version>.pck` → Eintrag in
   `installed.json` (alte Datei bleibt als `previous` liegen). Mismatch →
   verwerfen + Fehler melden.
5. Ergebnis-Enum: `UP_TO_DATE` / `UPDATED` / `NEEDS_NATIVE` / `ERROR` +
   Signale `check_started`, `pack_downloaded(id, version)`,
   `check_completed(result, details)`. Toasts (deutsch) verdrahtet
   `scripts/updates/settings_update_glue.gd`.
6. `config.json` wirkt **sofort** (Registry-Overlay, §7) — `.pck`-Inhalte ab Neustart.

### 5.2 `user://packs/installed.json`

```json
{
	"schema": 1,
	"packs": {
		"cosmetics": {
			"version": "1.4.0",
			"file": "cosmetics-v1.4.0.pck",
			"sha256": "e3b0c442…",
			"min_native": "5.0.0",
			"priority": 400,
			"type": "pck",
			"enabled": true,
			"installed_at": "2026-07-24T20:05:00Z",
			"installed_seq": 3,
			"survived_boot": false,
			"previous": "cosmetics-v1.3.2.pck",
			"previous_version": "1.3.2"
		}
	}
}
```

Der Boot-Zähler liegt separat in `user://boot_guard.json`
(`{"schema":1,"attempts":0,"last_ok_unix":…}`) — bewusst getrennt, damit ein
kaputtes `installed.json` den Guard nicht mitreißt.

### 5.3 Boot-Reihenfolge & Boot-Guard (2-Crash-Regel)

`PackLoader` ist Autoload #1, `ContentRegistry` #2 (vor allem anderen):

1. Eingebaute Versionen aus `res://content/*/pack.json` lesen (VOR Overrides —
   sie werden für Stale-Checks gecacht: `PackLoader.builtin_versions`).
2. Boot-Guard: `attempts += 1`, **sofort** persistieren.
3. `installed.json` lesen, Guard-Entscheidung anwenden:
   - **Versuch 1:** normaler Retry (kann ein Zufalls-Crash gewesen sein).
   - **Versuch 2:** das **zuletzt installierte** Pack (höchste `installed_seq`
     mit `survived_boot == false`) wird deaktiviert; existiert `previous`,
     wird darauf zurückgerollt. Toast: „Ein Update hat Probleme gemacht und
     wurde deaktiviert.“
   - **Versuch ≥ 3:** **Safe Mode** — alle user-Packs aus, Spiel läuft mit
     eingebautem Stand (immer spielbar). Banner „Erneut versuchen“ ruft
     `PackLoader.reenable_all_packs()`.
4. Pro aktiviertem Pack (Priorität aufsteigend):
   - **Stale-Cleanup:** user-Version ≤ eingebaute Version (neue IPA enthält den
     Content schon) → Datei löschen, Eintrag raus. Verhindert, dass alte
     Downloads eine neuere IPA „downgraden“ — der klassische Fehler solcher
     Systeme, hier explizit.
   - **Native-Gate:** `min_native` > App-Version → nie laden, liegen lassen.
   - `ProjectSettings.load_resource_pack(pfad, true)`; `false` → Pack sofort
     `enabled=false`.
5. Registry baut die Merge-Sicht (§5.4). Erst danach lädt das Hauptmenü.
6. Erfolgs-Boot (erste abgeschlossene SceneRouter-Reise ODER 15-s-Fallback-Timer)
   → `attempts = 0`, `survived_boot = true`, `previous`-Dateien löschen
   (Speicher, iOS-Sandbox).

Kein Crash-Handler nötig — persistierter Zähler + „sauber genullt“ ist die
robuste, primitive Lösung.

### 5.4 ContentRegistry (die EINE Lese-API)

Spiel-Systeme (Shop, Stickerbuch, Code-Einlösung, Goobyman-Chancen, NetClient)
lesen **nur** aus der Registry, nie direkt aus Dateien:

```gdscript
ContentRegistry.get_cosmetics()          # Array (append-by-id-gemergt)
ContentRegistry.get_stickers()
ContentRegistry.get_codes()
ContentRegistry.get_items("events")      # generisch
ContentRegistry.get_balance("zahnbuersten_bruch_chance", 0.01)
ContentRegistry.get_config("flags.xyz", false)   # Punkt-Pfade
ContentRegistry.get_net_config()         # {host, port, tls} — W2d-Kontrakt
ContentRegistry.version_of("cosmetics")  # "1.4.0"
ContentRegistry.reload()                 # Soft-Restart / nach Update-Download
```

Merge-Regeln pro Domain: **append-by-id** (cosmetics/stickers/codes/events —
gleiche Id: höhere Pack-Priorität gewinnt + Log-Warnung), **deep-merge-override**
(balance über Core-Defaults), **last-writer-wins** (config; `user://packs/config.json`
gewinnt immer). Bekannte Packs = eingebaute Ordner ∪ Ids aus `installed.json` —
so kann ein per Update NEU eingeführtes Pack ohne IPA ankommen.

### 5.5 Soft-Restart vs. echter Neustart

Für **additiven** Content (neue Sticker/Cosmetics/Codes) reicht: zurück zur
Boot-Szene → Packs laden → `ContentRegistry.reload()` → Menü neu. Für **ersetzte**
Assets gilt ehrlich: Godots Ressourcen-Cache tauscht bereits geladene Ressourcen
nicht aus — nur ein echter App-Neustart ist 100 % garantiert. Das Panel sagt
deshalb „Update geladen — Neustart lädt Inhalte“. Kein `get_tree().quit()`-Zwang.

## 6. Native-Gate, IPA-Releases & CI

### IPA vs. Pack — Entscheidungsbaum

```
Was willst du ändern?
├─ Nur Daten (Katalog, Preise, Chancen, Events, Sticker, Codes, Texte)?
│    └─▶ PACK. version bumpen, shippen (§4). Keine IPA.
├─ Server-IP/Port, Feature-Flag, News-Text?
│    └─▶ config-PACK (wirkt sofort, ohne Neustart, §7).
├─ Neue Assets zu BESTEHENDEM Verhalten (neuer Hut, neues Sticker-PNG)?
│    └─▶ PACK (append-by-id; Client kennt das Schema schon).
├─ Neues VERHALTEN (GDScript, neue Szenen-Logik, neues Datenformat)?
│    └─▶ IPA. Zusätzlich min_native der betroffenen Packs anheben,
│        damit alte Apps die neuen Packs nicht laden.
└─ Engine-/Plugin-Änderung (GDExtension, Godot-Update)?
     └─▶ IPA. IMMER. (iOS erlaubt kein natives Nachladen.)
```

`latest_native` im Manifest soll beim IPA-Release gebumpt werden → alle Clients
sehen „Neue App-Version nötig“. **Dieser Automatismus ist geplant (Backlog
GODOT-PLAN §6 → B §5.2), existiert aber noch nicht:** der `ios-ipa`-Job lädt die
.ipa bislang nur als CI-Artefakt hoch; ein Release-Asset-Step und der
Manifest-Bump fehlen. Bis dahin wird `latest_native` bei Bedarf manuell über
einen `gooby-packs`-Lauf gepflegt. Die App-Version kommt aus
`application/config/version` (project.godot, aktuell 5.0.0) und wird beim
iOS-Export zu `CFBundleShortVersionString`.

### CI-Werkzeuge (dieses Repo)

- `.github/workflows/gooby-packs.yml` — `workflow_dispatch` (Inputs: `packs`,
  `publish`): baut, verifiziert, erzeugt Manifest, hängt Assets an den
  rollenden Release-Tag `updates` (softprops/action-gh-release).
  `concurrency: manifest-update` verhindert Manifest-Races.
- `tools/packs/build_packs.sh` — lokal identisch zur CI (Import → Export →
  Smoketest → Manifest). `RELEASE_BASE_URL` leer = `file://`-URLs für Tests.
- `tools/packs/build_manifest.mjs` — Manifest-Generator (`--tag-mode single`
  heute; `per-pack` für unveränderliche `<id>-v<ver>`-Tags, Zielbild Doc B §1.3).
- Export-Presets: `GOOBY-GODOT/export_presets.cfg` (`pack-<id>` + `ios`). Der
  `ios-ipa`-Job in `.github/workflows/gooby-godot.yml` ist seit W6 scharf und
  baut bei jedem Push eine verifizierte unsignierte .ipa (Artefakt
  `GOOBY-godot-unsigned-ipa`; Runbook: `docs/godot-rewrite/IOS-BUILD.md`).

### EHRLICH: öffentliches Content-Repo fehlt noch

Doc B §3 empfiehlt Option (A): separates **öffentliches** Artefakt-Repo
`MedusaV9/gooby-updates` (nur Releases, kein Quellcode) — tokenlos, CDN-gestützt,
kein API-Rate-Limit. Das Repo **existiert noch nicht** (User-Action, Backlog
GODOT-PLAN §6/B). Bis dahin released `gooby-packs.yml` ins **Haupt-Repo**:
Downloads funktionieren dann tokenlos nur, wenn das Haupt-Repo öffentlich ist —
ist es privat, ist der Update-Weg bis zum Umzug faktisch DEV-only
(`file://`-Manifeste, lokale Builds). Umzug später in 3 Schritten:

1. GitHub-Repo `gooby-updates` anlegen (leerer `main` + README genügt).
2. Fine-grained PAT (nur dieses Repo, nur `contents: write`) als Actions-Secret
   `GH_CONTENT_TOKEN` im Haupt-Repo hinterlegen.
3. In `gooby-packs.yml` beim Release-Step `repository:` + `token:` einkommentieren
   und `RELEASE_BASE_URL` auf das neue Repo stellen; danach
   `content/config/data/config.json` → `manifest_url` auf die neue URL bumpen
   (das ist selbst ein config-Pack-Update — ohne IPA!). Die eingebaute
   Fallback-URL wandert mit dem nächsten IPA-Build mit.

## 7. Server-IP/Port ändern — ohne neue IPA

Der `config`-Pack ist der „Sofort-Kanal“ (kein PCK, kein Neustart):

1. `GOOBY-GODOT/content/config/data/config.json` editieren:
   `"net": {"host": "neue.ip.oder.domain", "port": 8765, "tls": false}` +
   `version` in `content/config/pack.json` bumpen.
2. Workflow laufen lassen (§4, Schritt 4) — die CI legt `config.json` als
   Release-Asset ab und trägt es ins Manifest ein (Typ `json`, sha256-geprüft).
3. Spieler: „Nach Updates suchen“ → Datei landet als `user://packs/config.json`.
4. Der W2d-NetClient liest bei **jedem** Connect frisch
   `ContentRegistry.get_net_config()` → nächster Verbindungsaufbau nutzt die
   neue Adresse. Kontrakt: `/tmp/gooby-godot/handoffs/W2b-config-api.md`.

## 8. Fehlerbilder, Debugging & Troubleshooting

| Symptom | Ursache | Fix |
|---|---|---|
| „Gerade nicht erreichbar“ beim Suchen | Offline / Manifest-URL falsch / Release fehlt | `manifest_url` in der Config prüfen; Release-Tag `updates` existiert? Client spielt normal weiter. |
| „sha256-Mismatch … verworfen“ | Unterbrochener/manipulierter Download, oder Manifest wurde nicht regeneriert | Workflow neu laufen lassen (Manifest IMMER via build_manifest.mjs); Retry im Panel. |
| Pack geladen, Inhalt fehlt nach Neustart | `min_native`-Gate greift (App zu alt) oder Pack `enabled=false` | `user://packs/installed.json` ansehen; „braucht neue IPA“-Hinweis beachten. |
| „Ein Update hat Probleme gemacht…“ | Boot-Guard hat nach 2 Crashes das jüngste Pack deaktiviert/zurückgerollt | Pack-Daten fixen, PATCH-Version shippen. Eintrag steht auf `enabled=false`. |
| Safe-Mode-Banner | ≥ 3 Boot-Crashes | „Erneut versuchen“ (reaktiviert alles) oder kaputtes Pack per Update fixen. Spiel läuft derweil mit eingebautem Stand. |
| Pack ohne Daten (leer) | JSON-Export-Filter kaputt | CI-Smoketest schlägt an (`verify_pack_cli.gd` lädt jedes Pack und liest `pack.json`). Presets nicht von Hand umbauen. |
| Alte Inhalte nach IPA-Update | dürfte nie passieren: Stale-Cleanup löscht user-Packs ≤ eingebauter Version | `user://packs/` inspizieren, Log-Zeile „cleaned“ suchen. |
| `--export-pack` loggt `ERROR: Can't open file from path ''` | bekannter, harmloser Godot-4.4-Schönheitsfehler beim Preset-Export | ignorieren; `build_packs.sh` bewertet Datei + Smoketest, nicht Log-Zeilen. |

Debug-Orte: `user://packs/` (Dateien + `installed.json`), `user://boot_guard.json`,
Godot-Log (Registry warnt bei Id-Kollisionen und kaputten Dateien). user://-Pfad
auf dem Desktop: `~/.local/share/godot/app_userdata/GOOBY/`; auf iOS: App-Sandbox
`Documents/`.

Technischer Hinweis zu `--export-pack`: Godot legt in jeden Export zwangsweise
`project.binary`, `.godot/global_script_class_cache.cfg`, `.godot/uid_cache.bin`
und das Icon. Skripte werfen unsere Presets per `exclude_filter` raus
(Data-only!); die verbleibenden Zwangsdateien werden nur beim App-Start VOR dem
Pack-Load gelesen und sind zur Laufzeit inert (verifiziert im Flow-Test).

## 9. Sicherheit & Policies

- **Data-only, per Policy und CI:** kein `.gd`, keine Szenen mit neuen Skripten
  in Packs. Gründe: (1) Script-Parse-Fehler crashen potenziell VOR dem
  Boot-Guard-Reset; (2) wer die Release-Quelle kontrolliert, dürfte sonst
  beliebigen Code auf allen Geräten ausführen — sha256 schützt nur den
  Transport, nicht die Quelle; (3) Teams können so keine Spiellogik kaputt
  machen; (4) App-Store-Tür bleibt offen.
- **Kein Token in der App:** eingebettete PATs sind extrahierbar (→ Lesezugriff
  aufs private Repo) und werden von GitHub-Secret-Scanning gern auto-revoked
  (→ Updates fallen plötzlich aus). Deshalb öffentliches Artefakt-Repo (§6).
- **Manifest-Quelle = Vertrauensanker:** Wer den `updates`-Release schreiben
  kann, steuert den Content aller Geräte. Token-Hygiene: fine-grained,
  minimaler Scope, nur als Actions-Secret. Härtung V2 (Backlog): Manifest-
  RSA-Signatur (Godot `Crypto`), Public Key in der App.
- **iOS-Fakten:** `.pck` = reines Datenarchiv in `user://` (App-Sandbox), von der
  Codesignatur nicht erfasst → kein Signatur-Bruch. Natives Nachladen
  (GDExtension) geht auf iOS nicht — brauchen wir nie. Sideload ohne Review →
  Guidelines unkritisch; Daten-Packs wären selbst im App Store Standard.
- **Speicher:** nur aktuelle + eine `previous`-Version je Pack bleiben liegen;
  Erfolgs-Boot räumt auf. Release-Assets ≤ 2 GiB (GitHub-Limit, unkritisch).

## 10. FAQ

**Warum sehe ich neue Cosmetics erst nach Neustart?**
Godot cached geladene Ressourcen; nachträglich geladene Packs ersetzen sie nicht
zuverlässig. Deshalb gilt ehrlich „wirksam ab Neustart“ (§5.5) — nur der
config-Pack wirkt sofort.

**Warum steht das Code-Geheimwort nicht im Pack?**
Weil die Releases öffentlich liegen. Es steht nur der sha256 der normalisierten
Eingabe drin; der Client vergleicht Hashes (§2).

**Kann ein Update das Spiel dauerhaft kaputt machen?**
Nein. Boot-Guard: 2 Crashes → jüngstes Pack deaktiviert (ggf. Rollback auf
`previous`), 3 Crashes → Safe-Mode mit eingebautem Content. Erfolgs-Boot nullt
den Zähler (§5.3).

**Was passiert, wenn ein Spieler ein Update lädt, aber die App zu alt ist?**
`min_native`-Gate: Das Pack wird als „braucht neue IPA“ angezeigt und **nie**
geladen. Nach dem IPA-Update lädt es der nächste Check normal.

**Wie kommt ein KOMPLETT neues Pack (neue Id) ohne IPA aufs Gerät?**
Manifest-Eintrag mit neuer Id reicht: UpdateService lädt es, `installed.json`
kennt die Id, PackLoader mountet es, die Registry nimmt Ids aus `installed.json`
zusätzlich zu den eingebauten auf (§5.4). Voraussetzung: die App kann mit der
Domain etwas anfangen (sonst braucht es ohnehin eine IPA).

**Woher weiß ich, welche Version gerade aktiv ist?**
`ContentRegistry.version_of("<pack>")` — bzw. `user://packs/installed.json` fürs
Dateisystem und `res://content/<pack>/pack.json` für die gemountete Sicht.
