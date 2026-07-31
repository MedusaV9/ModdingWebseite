# GOOBY Update-System (Packs) — Handbuch

Owner: W2b UPDATES · Design-Grundlage: `docs/godot-rewrite/B-updates.md` (bindend) ·
Code: `GOOBY-GODOT/scripts/updates/` · Stand: M1 (Godot 4.4.1).

Das Update-System liefert **fast alles ohne neue .ipa** aus: Inhalte kommen als
Daten-Packs (`.pck`) per „Suche nach Updates“-Knopf in den Einstellungen aufs Gerät.
Offline-first: ohne Netz läuft das Spiel immer normal weiter.

---

## 1. Überblick & Architektur

**Host der Updates ist DIESES private Repo** (`MedusaV9/MinecraftBubbleShieldMod`;
User-Entscheidung W15, seit dem W16-Umzug aus `MedusaV9/CustomServerPrivate` —
das früher geplante separate public Content-Repo `gooby-updates` entfällt
endgültig). Weil das Repo privat ist, liefern
tokenlose browser-download-URLs (`releases/download/…`) 404 — der Client lädt
deshalb über die **GitHub-Release-API** mit einem Zugangsschlüssel
(fine-grained PAT, → §6a).

```
┌─────────────────────────┐     baut .pck + manifest.json
│ DIESES private Repo     │────────────────────────────────┐
│ (content/<pack>/**)     │  GitHub Actions                │
└─────────────────────────┘  (.github/workflows/           ▼
     Tag packs-v* oder        gooby-packs.yml)   ┌──────────────────────┐
     Dispatch publish=true                       │ GitHub-Release       │
                                                 │ Tag `updates`:       │
                                                 │  manifest.json       │
                                                 │  config.json         │
                                                 │  <id>-v<x.y.z>.pck   │
                                                 └──────────┬───────────┘
                                                            │ GitHub-Release-API
                                                            │ (Token; Assets via
                                                            │  Accept: octet-stream)
                                                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ CLIENT (iPhone, Sideload-IPA)                                            │
│                                                                          │
│ Settings-Knopf ──▶ UpdateManager (scripts/updates/update_service.gd)     │
│                      Release am Tag holen → manifest.json-Asset laden    │
│                      → vergleichen → Assets laden → sha256               │
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
- **Abwärtskompatibel:** Direkte Manifest-URLs (eigener Server, öffentliches
  Repo, `file://`-DEV-Tests) funktionieren unverändert — der API-Weg greift
  nur bei `api.github.com`-URLs oder gesetztem Token (→ §5.1).

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

Eine feste URL liefert den kompletten Update-Stand (Release-Asset am Tag
`updates`). Default im eingebauten `config`-Pack ist die **Release-API-URL**
dieses Repos:

```
https://api.github.com/repos/MedusaV9/MinecraftBubbleShieldMod/releases/tags/updates
```

Der Client holt darüber die Assets-Liste des Releases, lädt daraus das
`manifest.json`-Asset (mit `Accept: application/octet-stream`) und schreibt
die browser-URLs der Pack-Einträge auf ihre Asset-API-URLs um. Das Manifest
selbst behält die browser-URLs (`releases/download/…`) — so bleibt es für
öffentliche Repos/eigene Server unverändert benutzbar:

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
4. **Release fahren:** EIN Tag-Push genügt (→ „Release fahren (Packs)“ in §6):

   ```bash
   git tag packs-v1.0.0 && git push origin packs-v1.0.0
   ```

   Der Tag triggert **gooby-packs** mit implizit `packs=all` + `publish=true`.
   Alternativ ohne Tag: GitHub → Actions → **gooby-packs** → „Run workflow“
   (Input `packs`: `cosmetics` oder `all`; `publish=true` veröffentlicht,
   `publish=false` ist der Probe-Lauf mit reinem Build-Artefakt). Die CI baut
   das Pack (`--export-pack`), lädt es probeweise (Smoketest!), berechnet
   sha256, regeneriert `manifest.json` und hängt alles an den Release-Tag
   `updates`.
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

1. Manifest von der konfigurierten URL holen (10 s Timeout). URL-Quelle:
   Override → Remote-Config (`user://packs/config.json`) → eingebauter
   `config`-Pack (`manifest_url`). Zeigt die URL auf `api.github.com` ODER
   ist ein Token gesetzt (Kette: Override → user://-Settings aus der
   Updates-Sektion → config-Pack-Feld `github_token`), läuft der Abruf über
   die **Release-API** (§1/§3); `Authorization: Bearer <token>` geht dabei
   NUR an API-Hosts, nie an fremde Server. Privates Repo ohne Token →
   Ergebnis `ERROR` mit klarem Panel-Hinweis „Updates brauchen einen
   Zugangsschlüssel — Einstellungen → Updates“ (details.token_required →
   Toast-Key `updates.token_fehlt`). Sonstige Offline-/Fehlerfälle →
   Ergebnis `ERROR`, Toast „Gerade nicht erreichbar — du kannst ganz normal
   weiterspielen“. Niemals blockierend.
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

**„Jetzt neu laden“ (W13C, B §2.4):** Nach einem installierten `.pck`-Update
bietet die Updates-Sektion der Einstellungen zusätzlich den Knopf
**„Jetzt neu laden“** an (`scripts/updates/settings_update_glue.gd`; nur bei
echten PCK-Updates — ein reines `config`-Update wirkt sofort und braucht ihn
nicht). Bestätigungs-Dialog („Dauert nur einen Hoppler!“), dann fährt
`scripts/updates/soft_restart.gd` die feste Reihenfolge:

1. **Gate:** Besuch, Brettspiel-Partie, Minigame oder laufende Router-Reise
   aktiv → verweigert (Toast), nichts wird angefasst.
2. Save flushen (`GameState.save_now`), Netz sauber trennen
   (`Net.disconnect_now`), Musik ausblenden (`Music.stop_music` + Fade
   abwarten).
3. `PackLoader.remount_for_soft_restart()` — mountet die `user://`-Packs neu
   und zählt BEWUSST als Boot-Versuch: die 2-Crash-Regel (§5.3) bleibt auch
   für Soft-Restarts scharf, der Erfolgs-Watch (erste Router-Reise /
   Fallback-Timer) nullt den Zähler wieder.
4. `ContentRegistry.reload()` → `SceneRouter.clear_history()` →
   `get_tree().reload_current_scene()` — die Boot-Szene (`main.tscn`)
   instanziert `HomeEntry` frisch, Routen/Mount-Point/HUD entstehen neu.
   Ein nacktes `reload_current_scene()` OHNE die Schritte 3–4 davor reicht
   ausdrücklich NICHT (die Pack-Mounts würden nicht neu greifen).

**Entschieden gegen einen echten Prozess-Neustart als Fallback:**
`OS.set_restart_on_exit()` ist Desktop-only (auf iOS nicht implementiert),
und ein programmatisches `quit()` gilt auf iOS als Crash (Apple-HIG).
Dazu die Boot-Guard-Falle: ein `quit()` NACH dem Remount (attempts wurde
gerade auf ≥ 1 gezählt, §5.3) ließe den nächsten echten Start als „Versuch 2“
erscheinen — der Guard würde das frisch installierte Pack fälschlich
deaktivieren. Ersetzte Assets bleiben daher ehrlich „wirksam ab echtem
Neustart“ (User beendet die App selbst), genau wie oben beschrieben.

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

`latest_native` im Manifest wird beim IPA-Release gebumpt → alle Clients
sehen „Neue App-Version nötig“. **Stand W15:** der Bump ist SCHARF — der
`release`-Job in `.github/workflows/gooby-godot.yml` lädt nach dem
IPA-Release das `manifest.json`-Asset vom rollenden `updates`-Release dieses
Repos, patcht es mit `tools/ci/bump_latest_native.mjs` (fail-closed:
striktes Semver, Schema-Check, Downgrade-Verweigerung, idempotente Re-Runs;
NUR `latest_native`/`published_at` ändern sich) und lädt es mit `--clobber`
wieder hoch. Existiert der `updates`-Release noch nicht (erster Pack-Release
steht aus) oder fehlt das Manifest-Asset, überspringt sich der Step sauber
mit einer Notice statt rot zu werden. Die App-Version kommt aus
`application/config/version` (project.godot, aktuell 5.0.0) und wird beim
iOS-Export zu `CFBundleShortVersionString`.

### Release fahren (Packs)

Ein Pack-Release ist EIN Tag-Push — der Tag triggert `gooby-packs.yml` mit
implizit `packs=all` + `publish=true`:

```bash
# Tag-Name dokumentiert nur den Anlass; die Pack-Versionen kommen aus
# content/<id>/pack.json (vorher bumpen, §4 Schritt 2!):
git tag packs-v1.0.0 && git push origin packs-v1.0.0
```

Alternativ ohne Tag: GitHub → Actions → **gooby-packs** → „Run workflow“
(Inputs `packs`/`publish`; `publish=false` = Probe-Lauf, nur Artefakt).
Der Lauf baut, verifiziert (Smoketest), regeneriert `manifest.json` und
aktualisiert den rollenden Release `updates`.

### Release fahren (IPA)

Ein IPA-Release ist EIN Tag-Push — der `release`-Job im bestehenden
`gooby-godot.yml` übernimmt den Rest (strikt gated: er läuft NUR bei
`ipa-v*`-Tags oder explizitem Dispatch-Input, nie bei normalen Branch-Pushes,
und nur nach GRÜNEN `linux-checks` + `ios-ipa`):

```bash
# Version im Tag = Release-Version (striktes MAJOR.MINOR.PATCH):
git tag ipa-v5.1.0 && git push origin ipa-v5.1.0
```

Alternativ ohne Tag: GitHub → Actions → **GOOBY Godot** → „Run workflow“ →
Input `release_version` = `5.1.0` (leer lassen = normaler Build ohne Release).

Der Job dann:

1. baut wie bei jedem Push die verifizierte unsignierte .ipa (`ios-ipa`),
2. benennt sie versioniert um (`GOOBY-godot-unsigned-v5.1.0.ipa`),
3. erstellt/aktualisiert das GitHub-Release `ipa-v5.1.0` mit deutschem
   Release-Notes-Gerüst („Was ist neu?“ nach dem Lauf ausfüllen!),
4. bumpt `latest_native` im `updates`-Manifest via
   `tools/ci/bump_latest_native.mjs` — das Script ist fail-closed (striktes
   Semver, Schema-Check, Downgrade-Verweigerung, idempotente Re-Runs) und
   patcht NUR `latest_native`/`published_at`, die Pack-Einträge bleiben
   unangetastet. Kein `updates`-Release/Manifest-Asset vorhanden → Step
   überspringt sich mit Notice (nie rot).

Nicht vergessen: `application/config/version` in `project.godot` sollte zur
Release-Version passen (Owner: Orchestrator/Core — Request stellen), sonst
meldet die frisch installierte App sich selbst als „zu alt“.

### CI-Werkzeuge (dieses Repo)

- `.github/workflows/gooby-packs.yml` — Tag-Push `packs-v*` (implizit
  `packs=all` + `publish=true`) oder `workflow_dispatch` (Inputs: `packs`,
  `publish`): baut, verifiziert, erzeugt Manifest, hängt Assets an den
  rollenden Release-Tag `updates` (softprops/action-gh-release).
  `concurrency: manifest-update` verhindert Manifest-Races.
- `tools/packs/build_packs.sh` — lokal identisch zur CI (Import → Export →
  Smoketest → Manifest). `RELEASE_BASE_URL` leer = `file://`-URLs für Tests.
- `tools/packs/build_manifest.mjs` — Manifest-Generator (`--tag-mode single`
  heute; `per-pack` für unveränderliche `<id>-v<ver>`-Tags, Zielbild Doc B §1.3).
- `tools/ci/bump_latest_native.mjs` — patcht `latest_native`/`published_at`
  im Release-Manifest (läuft automatisch im `release`-Job, s. oben).
- Export-Presets: `GOOBY-GODOT/export_presets.cfg` (`pack-<id>` + `ios`). Der
  `ios-ipa`-Job in `.github/workflows/gooby-godot.yml` ist seit W6 scharf und
  baut bei jedem Push eine verifizierte unsignierte .ipa (Artefakt
  `GOOBY-godot-unsigned-ipa`; Runbook: `docs/godot-rewrite/IOS-BUILD.md`).

## 6a. Token für Spieler (privates Repo)

Dieses Repo ist privat — jeder Spieler-Client braucht deshalb einen
**Zugangsschlüssel** (GitHub-PAT) für die Update-Suche. So verteilt ihn der
Server-Betreiber:

1. **PAT erzeugen:** GitHub → Settings → Developer settings →
   Personal access tokens → **Fine-grained tokens** → „Generate new token“.
   - *Repository access:* **Only select repositories** →
     `MedusaV9/MinecraftBubbleShieldMod` (NUR dieses Repo!).
   - *Permissions:* **Contents: Read-only** — sonst NICHTS. (Der Token kann
     damit Releases/Code dieses Repos lesen, mehr nicht.)
   - Ablaufdatum nach Geschmack (GitHub erzwingt eines; rechtzeitig neu
     erzeugen und nachverteilen).
2. **An die Freunde geben:** Token (Form `github_pat_…`) per DM o. Ä.
   verschicken. Jeder Spieler trägt ihn einmal in der App ein:
   **Einstellungen → Updates → „GitHub-Token (für App-Updates)“** (maskiertes
   Feld; gespeichert in `user://updates_user_override.json`, gilt ab der
   nächsten Update-Suche).
3. **Alternative für gemeinsame Geräte:** das optionale config-Pack-Feld
   `github_token` (s. `content/config/config.example.json`) — die
   User-Settings gewinnen immer. ACHTUNG: Ein Token im config-Pack landet im
   Release-Asset; im privaten Repo okay, aber bewusst entscheiden.
4. **Kompromittiert/Spieler entfernen?** Token auf GitHub widerrufen
   (revoke), neuen erzeugen, neu verteilen. Clients ohne gültigen Token
   sehen im Panel „Updates brauchen einen Zugangsschlüssel — Einstellungen →
   Updates“; das Spiel läuft normal weiter (offline-first).

> **Repo-Umzug (W16): Neuer Zugangsschlüssel nötig!**
>
> GOOBY ist in ein neues Repo umgezogen (`MedusaV9/MinecraftBubbleShieldMod`).
> Der alte Zugangsschlüssel war NUR für das alte Repo freigeschaltet — für Updates
> aus dem neuen Repo funktioniert er nicht. Das musst du als Betreiber einmal tun:
>
> 1. **Neuen Schlüssel erzeugen:** GitHub → Settings → Developer settings →
>    Personal access tokens → Fine-grained tokens → „Generate new token“.
>    Bei *Repository access* **Only select repositories** →
>    `MedusaV9/MinecraftBubbleShieldMod` auswählen (NUR dieses Repo!), bei
>    *Permissions* **Contents: Read-only** — sonst nichts.
> 2. **An alle Freunde verschicken** (per DM o. Ä., Form `github_pat_…`). Jeder
>    trägt den neuen Schlüssel in der App unter **Einstellungen → Updates →
>    „GitHub-Token (für App-Updates)“** ein — einfach den alten überschreiben.
> 3. **Alten Schlüssel widerrufen:** GitHub → Fine-grained tokens → alten Token
>    „Revoke“. (Erst NACHDEM alle den neuen eingetragen haben.)
>
> Solange jemand noch den alten Schlüssel drin hat, sieht er beim Suchen nur den
> Hinweis „Zugangsschlüssel abgelehnt“ — das Spiel läuft ganz normal weiter, es
> kommen nur keine Updates an, bis der neue Schlüssel eingetragen ist.

**Betreiber-Hinweis für Bestandsclients (wichtig, weil der Umzug KEIN
GitHub-Rename war — alte URLs leiten NICHT um):** Bereits verteilte IPAs haben
die ALTE `manifest_url` eingebaut (und ggf. als `user://packs/config.json`
installiert). Zwei Wege:

- **Weg A (einfach, empfohlen bei wenigen Freunden):** neue IPA bauen/verteilen
  (enthält das neue `config.json`) + neuen Token eintragen lassen. Fertig.
- **Weg B (ohne neue IPA, „Brücken-Release“):** solange das alte Repo noch
  existiert, dort EINMAL ein letztes config-Pack-Update veröffentlichen, dessen
  `config.json` die NEUE `manifest_url` trägt (config-Pack-Version bumpen!).
  Reihenfolge pro Spieler: erst mit dem ALTEN Token „Nach Updates suchen“ (holt
  die Brücken-Config, wirkt sofort), DANN den NEUEN Token eintragen. Achtung:
  das optionale `github_token`-Feld im config-Pack hilft hier NICHT automatisch,
  weil User-Settings in der Token-Kette immer gewinnen (`update_service.gd`,
  Token-Kette §5.1).
- Wird das alte Repo einfach gelöscht/archiviert, sehen Alt-Clients nur den
  harmlosen Fehler-Toast („Gerade nicht erreichbar“) — Spiel bleibt voll
  spielbar; Migration dann nur noch über Weg A.

Betreiber-Schritte für den Umzug in Kurzform:

1. Neuen fine-grained PAT fürs neue Repo erzeugen und an alle verteilen (s. o.).
2. Im neuen Repo den ersten Pack-Release fahren (`packs-v*`-Tag pushen oder
   Actions → gooby-packs → Run workflow mit `publish=true`), damit der rollende
   `updates`-Release samt Manifest dort existiert — vorher meldet jede
   Update-Suche „Gerade nicht erreichbar“ (offline-first, nicht blockierend).
3. Bestandsclients per Weg A (neue IPA) oder Weg B (Brücken-Release im alten
   Repo, solange es existiert) migrieren.
4. Alten PAT erst NACH der Migration widerrufen.

Ohne Token funktioniert weiterhin alles außer der Update-Suche — die App
bleibt voll spielbar (eingebauter Content-Stand).

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
| „Updates brauchen einen Zugangsschlüssel…“ | privates Repo ohne (gültigen) Token angefragt | Token vom Betreiber holen (§6a) und unter Einstellungen → Updates eintragen. |
| „Zugangsschlüssel abgelehnt (http=…)“ | Token abgelaufen/widerrufen/falsches Repo im PAT-Scope | Neuen fine-grained PAT erzeugen (nur dieses Repo, contents:read) und neu eintragen. |
| „Asset '…' fehlt im Release“ | Manifest und Release-Assets nicht synchron (Upload halb durch) | Pack-Release neu fahren (`packs-v*`-Tag) — der Workflow regeneriert Manifest + Assets zusammen. |
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
- **Kein fest eingebautes Token in der IPA:** eingebettete PATs wären
  extrahierbar und werden von GitHub-Secret-Scanning gern auto-revoked
  (→ Updates fallen plötzlich aus). Stattdessen trägt jeder Spieler seinen
  vom Betreiber verteilten fine-grained PAT selbst ein (§6a) — Scope NUR
  dieses Repo, NUR `contents: read`; Blast-Radius bei Leak = Lesezugriff auf
  dieses eine Repo, Widerruf jederzeit per GitHub-Revoke.
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
