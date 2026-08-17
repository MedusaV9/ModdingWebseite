# B — Update-System & Modularität (Design, Ideen-Improver B)

Bereich: USER-WISHES §B (SEHR wichtig). Ziel: Fast alles ohne neue .ipa updatebar, per
„Suche nach Updates“-Knopf in den Settings, offline-first, modulare Team-Releases, Doku in
`docs/UPDATES.md`. Nur DESIGN — keine Implementierung in diesem Dokument.

---

## 0) Ehrliche technische Grundlage (iOS-Tauglichkeit)

**PCK-Loading auf iOS funktioniert und bricht kein Codesigning.** Fakten, ohne Schönfärberei:

- `ProjectSettings.load_resource_pack(path)` ist auf iOS voll unterstützt. Ein `.pck` ist ein
  reines Datenarchiv (Godots virtuelles `res://`-Dateisystem). Die App lädt es aus
  `user://` (= App-Sandbox `Documents/`), das von der Codesignatur **nicht** erfasst wird.
  Die signierte Binary + eingebettete Frameworks bleiben unverändert → kein Signatur-Bruch.
- **Was NICHT geht:** natives Nachladen (GDExtension `.dylib`/`.framework`) zur Laufzeit —
  iOS erlaubt nur beim Build eingebettete, mitsignierte Libraries. Unser Design braucht das
  nie (Data-only, s. §4).
- **GDScript in Packs wäre technisch möglich** (interpretiert/tokenisiert, kein JIT, kein
  Codesign-Problem). Wir verbieten es trotzdem per Policy (§4) — das ist eine bewusste
  Robustheits-Entscheidung, keine technische Notwendigkeit.
- **Apple-Guideline-Realität:** Die App wird als unsigned .ipa gebaut und per
  Sideload (AltStore/SideStore, eigenes Zertifikat des Users) installiert. Es gibt **kein
  App-Review** → App-Store-Guidelines (2.5.2 „kein Code-Download“) greifen schlicht nicht.
  Für Sideload ist das gesamte System unkritisch. Ehrlicher Ausblick: Sollte das Spiel je in
  den App Store, wären Daten-Packs weiterhin völlig okay (Content-Downloads sind Standard,
  vgl. jedes Gacha-Spiel); nur Script-Downloads wären dann heikel — noch ein Grund für
  Data-only.
- **Godot-Caveat (wichtig, oft übersehen):** bereits geladene/gecachte Ressourcen werden
  durch ein nachträgliches `load_resource_pack` **nicht** automatisch ersetzt. Deshalb gilt:
  Packs werden beim **Boot** geladen; nach einem Download werden sie erst beim nächsten
  Start (oder per Soft-Restart, §2.4) wirksam. Das macht das System deterministisch statt
  „meistens funktioniert’s“.

---

## 1) Pack-Struktur, Namenskonventionen, Versionierung

### 1.1 Die Packs (7 Stück, je EINE Zuständigkeit)

| Pack-Id | Inhalt | Typ | Priorität | Ändert sich |
|---|---|---|---|---|
| `core` | Basis-Content-Daten: Möbel-/Food-/Crop-Kataloge, Quests, Strings, Minigame-Level-Daten | PCK | 100 | selten (Core-Team) |
| `balance` | Zahlenwerte/Chancen: Drop-Chancen (Goobyman-Zahnbürste!), Preise, Energie-Kosten, Timer | PCK | 200 | oft |
| `events` | Zeitfenster-Events (Saison-Deko, Nutella-Nacht-Varianten, Bonus-Wochenenden): `{id, start, end, payload}` | PCK | 300 | oft |
| `cosmetics` | Skins/Outfits/Deko-Cosmetics: Katalog-JSON + PNG/`.tres`-Assets | PCK | 400 | oft (eigenes Team!) |
| `stickers` | Sticker-Katalog + 512×512-PNGs (deutsch beschriftet) | PCK | 500 | oft |
| `codes` | Einlöse-Codes: `{id, secret_sha256, effect, once}` | PCK | 600 | oft |
| `config` | Remote-Settings: **Server-IP/Port**, Feature-Flags, News-Panel-Text | **plain JSON** | — | jederzeit |

- `config` ist bewusst **kein** PCK: winzig, muss sofort (ohne Neustart) wirken und auch
  dann lesbar sein, wenn das Pack-System selbst klemmt. Die Netzwerkschicht liest
  `user://packs/config.json` bei jedem Connect frisch.
- **Codes-Detail (wasserdicht):** Da der Content öffentlich liegt (§3), stehen Code-Wörter
  NICHT im Klartext im Pack, sondern als `secret_sha256` der normalisierten Form
  (lowercase, Whitespace raus — wie `codes.js` im Web-GOOBY). Client hasht die Eingabe und
  vergleicht.
- Höhere Priorität = später geladen = gewinnt bei Kollisionen (Registry-Merge §4.2).

### 1.2 Layout im Repo und im Pack (namespaced → keine Pfad-Kollisionen)

```
content/cosmetics/                 # Quell-Ordner im (privaten) Haupt-Repo
  pack.json                        # {"id":"cosmetics","version":"1.4.0","domains":["cosmetics"]}
  data/cosmetics.json              # Katalog (ids, price, nameKey, asset-Pfade)
  assets/hats/party_hut.png        # Assets (werden von Godot importiert)
```

Exportiert landet alles unter `res://content/cosmetics/…`. Jedes Pack liefert
ausschließlich Dateien unter `res://content/<pack_id>/` → zwei Packs können sich nie
gegenseitig Dateien überschreiben; Merge passiert kontrolliert in der ContentRegistry.

### 1.3 Namenskonventionen

- Pack-Datei: `<id>-v<semver>.pck` → `cosmetics-v1.4.0.pck`
- Release-Tag (Namespace pro Team!): `<id>-v<semver>` → `cosmetics-v1.4.0`, `codes-v2.0.1`
- Native App: Tag `ipa-v5.1.0`; Version steht in `application/config/version`
  (project.godot) und wird beim iOS-Export zu `CFBundleShortVersionString`.
- Fixer Manifest-Release-Tag: `updates` (Assets: `manifest.json`, `config.json`).

### 1.4 `manifest.json` (Schema, im Release `updates`)

```json
{
  "schema": 1,
  "latest_native": "5.1.0",
  "notes": "Kurztext fürs Update-Panel (deutsch)",
  "published_at": "2026-07-24T20:00:00Z",
  "packs": [
    {
      "id": "cosmetics",
      "version": "1.4.0",
      "type": "pck",
      "url": "https://github.com/MedusaV9/gooby-updates/releases/download/cosmetics-v1.4.0/cosmetics-v1.4.0.pck",
      "sha256": "e3b0c442…",
      "size": 1848320,
      "min_native": "5.0.0",
      "notes": "12 neue Hüte"
    },
    {
      "id": "config",
      "version": "1.0.3",
      "type": "json",
      "url": "https://github.com/MedusaV9/gooby-updates/releases/download/updates/config.json",
      "sha256": "9f86d081…",
      "size": 412,
      "min_native": "5.0.0"
    }
  ]
}
```

Versionierung strikt **semver**: MAJOR = Format-Bruch (braucht i. d. R. `min_native`-Bump),
MINOR = neuer Content, PATCH = Fix. Semver-Vergleich ist eine ~30-LOC-Util im Client.

---

## 2) Update-Flow im Client

### 2.1 „Suche nach Updates“ (Settings-Knopf)

1. `HTTPRequest` GET auf die **eine feste URL**
   `https://github.com/MedusaV9/gooby-updates/releases/download/updates/manifest.json`
   (10 s Timeout). Offline/Fehler → freundliche Meldung „Gerade nicht erreichbar — du
   kannst ganz normal weiterspielen“ (offline-first, niemals blockieren).
2. `latest_native` > eigene Version → Banner **„Neue App-Version verfügbar — dafür ist eine
   neue IPA nötig“** (+ Link auf Release-Seite). Kein Auto-Download der IPA.
3. Pro Pack: effektive installierte Version = `max(eingebacken, user://-installiert)`.
   Manifest-Version größer? → Kandidat. **Native-Gate:** Ist `min_native` > eigene Version,
   wird das Pack NICHT geladen, sondern in der Liste als „⚠ braucht neue IPA“ angezeigt.
4. Bestätigungs-Dialog: Liste + Größen + `notes`. Ein Tap lädt alles.
5. Download nach `user://packs/tmp/<file>.part` → `FileAccess.get_sha256()` gegen Manifest
   → bei Match Move nach `user://packs/`, Eintrag in `installed.json` (alte Datei bleibt als
   `previous` liegen, §2.5). Mismatch → verwerfen + Retry-Angebot.
6. Abschluss: „Update installiert — aktiv nach Neustart“ + Button **[Jetzt neu laden]**
   (Soft-Restart §2.4). `config.json` wirkt sofort, ganz ohne Neustart.

### 2.2 `user://packs/installed.json`

```json
{
  "schema": 1,
  "packs": {
    "cosmetics": {
      "version": "1.4.0",
      "file": "cosmetics-v1.4.0.pck",
      "sha256": "e3b0c442…",
      "previous": "cosmetics-v1.3.2.pck",
      "enabled": true,
      "installed_at": "2026-07-24T20:05:00Z",
      "survived_boot": false
    }
  },
  "boot": { "attempts": 0, "last_ok": "2026-07-24T19:00:00Z" }
}
```

### 2.3 Lade-Reihenfolge beim Boot (Autoload #1 = `PackLoader`)

1. Basis-`game.pck` (in der IPA) ist automatisch geladen — inkl. der beim IPA-Build
   eingebackenen Stände aller Packs.
2. `PackLoader` liest **zuerst** die eingebackenen `res://content/*/pack.json`-Versionen
   (bevor irgendetwas überschrieben wird).
3. Boot-Guard: `boot.attempts += 1`, sofort persistieren (§2.5).
4. `installed.json` lesen; pro Pack: `enabled == true` UND user-Version **>**
   eingebackene Version UND `min_native` ok → `ProjectSettings.load_resource_pack(path,
   true)` in aufsteigender Priorität. Rückgabe `false` → Pack sofort `enabled=false`.
   **Stale-Cleanup:** Ist die user-Version ≤ eingebacken (weil eine neue IPA den Content
   schon enthält), wird die user-Datei gelöscht — verhindert, dass alte Downloads eine
   neuere IPA „downgraden“. Das ist der klassische Fehler solcher Systeme; hier explizit.
5. `ContentRegistry` (Autoload #2) mergt die Kataloge (§4.2). Erst danach lädt das
   Hauptmenü.
6. Hauptmenü erreicht → `boot.attempts = 0`, `survived_boot = true`, `previous`-Dateien
   der überlebenden Packs löschen (Speicher sparen, iOS-Sandbox).

### 2.4 Soft-Restart vs. echter Neustart

„Jetzt neu laden“ = zurück zur Boot-Szene, neue Packs laden, Registry neu aufbauen,
Hauptmenü neu instanziieren. Für **additiven** Content (neue Sticker/Cosmetics/Codes)
zuverlässig, weil deren Ressourcen noch nie im Cache waren. Für ersetzte Assets gilt
ehrlich: nur ein echter App-Neustart ist 100 % garantiert (Ressourcen-Cache, §0). Das
Panel sagt das dem User genau so. Kein `get_tree().quit()`-Zwang.

### 2.5 Rollback / Boot-Guard (2-Crash-Regel)

`attempts` wird VOR dem Pack-Load hochgezählt und erst beim erreichten Hauptmenü genullt —
ein Crash irgendwo dazwischen hinterlässt also einen Zähler ≥ 1:

- `attempts == 1` beim Start: normaler Retry (kann ein Zufalls-Crash gewesen sein).
- `attempts == 2`: das **zuletzt installierte** Pack (jüngstes `installed_at` mit
  `survived_boot == false`) wird deaktiviert; existiert `previous`, wird darauf
  zurückgerollt. Meldung im Hauptmenü: „Ein Update hat Probleme gemacht und wurde
  deaktiviert.“
- `attempts >= 3`: **Safe Mode** — ALLE user-Packs deaktiviert, Spiel läuft mit
  eingebackenem Stand (das Spiel bleibt IMMER spielbar). Banner mit „Erneut versuchen“.

Kein Godot-Crash-Handler nötig — der persistierte Zähler + „sauber genullt“ ist die
robuste, primitive Lösung.

---

## 3) Privates Repo: Download-Quelle (Abwägung + Empfehlung)

`MedusaV9/CustomServerPrivate` ist privat → `releases/download/…` liefert dort ohne Token
404. (Historisch — seit dem W16-Umzug heißt das Repo `MedusaV9/MinecraftBubbleShieldMod`;
die Abwägung gilt unverändert.) Optionen ehrlich abgewogen:

| Option | Bewertung |
|---|---|
| **(A) Separates öffentliches Content-Repo** `MedusaV9/gooby-updates` (nur Release-Artefakte, kein Quellcode) | ✅ **EMPFEHLUNG.** Tokenlos, offline-first-kompatibel, kein Server nötig, direkte CDN-URLs (Redirect auf GitHub-S3, kein API-Rate-Limit). Der private Code bleibt privat; die CI pusht nur gebaute `.pck`s + Manifest rüber (Token liegt NUR als Actions-Secret im privaten Repo). Preisgabe: nur Assets, die sowieso in jeder verteilten IPA stecken — kein realer Verlust. |
| (B) Haupt-Repo public machen, „releases-only“ | ❌ Gibt es bei GitHub nicht — public Repo = public Code. Der User will das Repo privat; fällt aus. |
| (C) Proxy über den Node.js-Server (AMP) | ❌ als Primärweg: Server läuft nicht immer, Spiel ist offline-first; Update-Verfügbarkeit darf nicht an Server-Uptime hängen. Bandbreite/Traffic zusätzlich. ✅ optional später als **Mirror #2** im Manifest (`mirrors:[…]`). |
| (D) Eingebettetes Read-Only-Token (fine-grained PAT) in der App | ❌ Jeder mit der IPA kann das Token extrahieren → Lesezugriff aufs **komplette private Repo inkl. Code**. GitHub-Secret-Scanning revoked geleakte PATs auch gern automatisch → Updates fallen plötzlich für alle aus. Unsauber UND fragil. Nur als allerletzter Notnagel, und selbst dann lieber (C). |

**Entscheidung: (A).** Struktur von `gooby-updates`: leerer `main`-Branch mit README,
alles Relevante sind Releases: pro Pack ein Tag (`cosmetics-v1.4.0`, unveränderlich) plus
der rollende Fix-Tag `updates`, dessen Assets (`manifest.json`, `config.json`) die CI bei
jedem Pack-Release ersetzt. Eine einzige stabile Client-URL, kein `api.github.com`
(unauthentifiziertes API-Limit 60 req/h wird so komplett umgangen).

---

## 4) Team-Modularität

### 4.1 Workflow „Cosmetics-Team shippt unabhängig“

1. Team ändert NUR `content/cosmetics/**` im privaten Repo (Branch + PR; CODEOWNERS
   mappt `content/cosmetics/` aufs Team).
2. Merge auf `main` mit Pfad-Änderung unter `content/cosmetics/` (oder manueller
   `workflow_dispatch` mit Version) → CI baut `cosmetics-v1.5.0.pck` (§5), erstellt
   Release `cosmetics-v1.5.0` im **public** Repo, regeneriert `manifest.json`.
3. Spieler drücken „Suche nach Updates“ → nur das Cosmetics-Pack wird geladen. Kein
   anderes Team, kein IPA-Build involviert.
4. Der nächste IPA-Build bettet automatisch den neuesten Stand ALLER Packs ein (§5.2) —
   Wunsch „GitHub Actions baut trotzdem immer die neueste IPA mit allem Content“ erfüllt.

### 4.2 ContentRegistry (Autoload, mergt Packs)

- Iteriert bekannte Pack-Ids (konstante Liste der eingebackenen + Ids aus
  `installed.json` — so kann ein per Update NEU eingeführtes Pack ohne IPA ankommen),
  lädt je `res://content/<id>/pack.json` + `data/*.json`.
- Merge-Regeln pro Domain: **append-by-id** (cosmetics, stickers, codes, events),
  **deep-merge-override** (balance über Core-Defaults), **last-writer-wins nach
  Priorität** (config-Flags). Gleiche Content-Id aus zwei Packs → höhere Priorität
  gewinnt + Warnung im Log.
- Spiel-Systeme (Shop, Stickerbuch, Code-Einlösung, Goobyman-Chancen) lesen NUR aus der
  Registry, nie direkt aus Dateien → ein Pack mehr oder weniger ist für die Spiellogik
  unsichtbar.

### 4.3 Code in Packs? — Konservative Empfehlung: **NEIN (Data-only)**

- Packs enthalten **JSON/`.tres`/Assets, niemals `.gd`** und keine `.tscn`, die neue
  Scripts einführen. CI erzwingt das (Build bricht ab, wenn im Pack-Ordner `.gd`/`.tscn`
  mit Script-Referenz außerhalb der Whitelist liegt).
- Begründung: (1) Ein Script-Parse-Fehler crasht potenziell VOR dem Boot-Guard-Reset und
  ist schwerer einzudämmen als kaputte Daten; (2) wer die public-Repo-Releases
  kontrolliert, würde sonst beliebigen Code auf allen Geräten ausführen — sha256 schützt
  nur den Transport, nicht die Quelle; (3) das Cosmetics-Team KANN so gar keine Spiellogik
  kaputt machen — genau die gewünschte Modularität; (4) App-Store-Tür bleibt offen (§0).
- Neues **Verhalten** (nicht nur Daten) braucht damit bewusst eine neue IPA — dafür gibt es
  das Native-Gate und `latest_native`. Ausnahme-Ventil für später (NICHT jetzt bauen):
  ein `core`-Pack dürfte per Zwei-Personen-Review Scripts enthalten; Empfehlung bleibt,
  dieses Ventil geschlossen zu lassen, bis es wirklich weh tut.

---

## 5) GitHub Actions (im privaten Repo)

### 5.1 `.github/workflows/pack-build.yml`

- Trigger: `push` auf `main` mit `paths: content/<id>/**` (Matrix über Pack-Ids, nur
  geänderte bauen) + `workflow_dispatch(pack_id, version)`.
- Steps (ubuntu-latest): Godot 4.4 headless + Export-Templates cachen →
  `godot --headless --import` (Asset-Import! PNGs → `.ctex`) →
  `godot --headless --export-pack "pack-<id>" build/<id>-v<ver>.pck` — pro Pack ein
  Export-Preset in `export_presets.cfg` mit Include-Filter `content/<id>/**` (+ `*.json`
  in den Export-Filtern, sonst fehlen die JSONs im Pack — klassische Falle).
- Version kommt aus `content/<id>/pack.json`; CI verweigert Release, wenn der Tag schon
  existiert (kein stilles Überschreiben unveränderlicher Versionen).
- sha256 berechnen → Release `<id>-v<ver>` im public Repo (`GH_CONTENT_TOKEN`-Secret,
  fine-grained, nur `gooby-updates`, nur `contents:write`) → `tools/build_manifest.mjs`
  regeneriert `manifest.json` aus den vorhandenen Releases → Asset am `updates`-Release
  ersetzen. `concurrency: manifest-update` verhindert Races zweier paralleler Pack-Builds.

### 5.2 `.github/workflows/ipa-build.yml`

- Trigger: Tag `ipa-v*` (+ `workflow_dispatch`).
- Steps (macos-latest): alle Pack-Quellordner sind Teil des Projekts → der normale
  iOS-Export bettet den aktuellsten Content automatisch ein (kein separater Schritt nötig;
  eingebackene Versionen stehen in den `pack.json`s). Godot headless exportiert das
  Xcode-Projekt → `xcodebuild archive` mit `CODE_SIGNING_ALLOWED=NO` →
  `Payload/GOOBY.app` zippen → `GOOBY-v5.x.y-unsigned.ipa` als Release-Asset →
  Manifest-Job bumpt `latest_native`.

---

## 6) `docs/UPDATES.md` — Gliederung (User will die Doku explizit)

1. **Überblick** — Diagramm: privates Repo → CI → `gooby-updates` (public) → Client.
2. **Pack-Typen & Zuständigkeiten** — Tabelle aus §1.1 inkl. Team-Ownership.
3. **manifest.json-Referenz** — Schema §1.4, Feld für Feld.
4. **How-To: Content ändern & shippen** — Schritt-für-Schritt fürs Cosmetics-Team
   (Ordner, `pack.json`-Bump, PR, was die CI dann tut). Der wichtigste Abschnitt.
5. **Client-Verhalten** — Boot-Reihenfolge, `installed.json`, Boot-Guard/Safe-Mode,
   Soft-Restart-Grenzen.
6. **Native-Gate & IPA-Releases** — `min_native`/`latest_native`, wann eine IPA nötig ist,
   `ipa-v*`-Workflow, Sideload-Hinweise.
7. **Fehlerbilder & Debugging** — user://packs inspizieren, Logs, „Pack deaktiviert“-Fälle.
8. **Sicherheit & Policies** — warum Data-only, warum kein Token in der App, Token-Hygiene.
9. **FAQ** — „Warum sehe ich neue Cosmetics erst nach Neustart?“ etc.

---

## 7) Risiken (ehrlich)

- **Manifest-Quelle = Vertrauensanker.** Wer `gooby-updates` schreiben kann, steuert den
  Content aller Geräte. sha256 sichert nur den Transport. Härtung (V2, optional): Manifest
  mit RSA-Key signieren (Godot `Crypto`-Klasse), Public Key in der App. Für ein privates
  Fan-Projekt bewusst nicht Phase 1.
- **Ressourcen-Cache** macht Soft-Apply für ersetzte Assets unzuverlässig → Policy
  „wirksam ab Neustart“ ist die Absicherung, UI kommuniziert das (§2.4).
- **Stale user-Packs vs. neuere IPA** → explizite Cleanup-Regel (§2.3 Schritt 4).
- **JSON-Export-Filter vergessen** → Pack ohne Daten. CI-Smoketest: gebautes Pck headless
  laden und `pack.json` lesen, sonst Build rot.
- **GitHub-Limits:** Release-Assets ≤ 2 GiB, Download tokenlos & CDN-gestützt — kein
  API-Rate-Limit, da nie `api.github.com` aufgerufen wird. Unkritisch.
- **iOS-Speicher:** `user://packs` wächst → nur aktuelle + eine `previous`-Version je Pack
  behalten (§2.5).
- **Godot-Import-Determinismus in CI:** `--import` vor `--export-pack` ist Pflicht, sonst
  fehlen `.ctex`; Template-Version muss exakt zur Editor-Version passen (Cache pinnen).

## 8) Implementierungs-Reihenfolge & Scope (Dateien/LOC, keine Kalenderzeit)

| Schritt | Artefakte | ~LOC |
|---|---|---|
| 1. Semver-Util + `PackLoader` (Boot-Load, Boot-Guard, installed.json, Stale-Cleanup) | `autoload/semver.gd`, `autoload/pack_loader.gd` | 80 + 220 |
| 2. `ContentRegistry` + `pack.json`-Kontrakt + Domain-Merges | `autoload/content_registry.gd`, 7× `content/<id>/pack.json` | 250 |
| 3. `UpdateManager` (Manifest-Fetch, Vergleich, Download, sha256, Native-Gate, config.json-Sofortpfad) | `autoload/update_manager.gd` | 350 |
| 4. Settings-UI (Knopf, Fortschritt, IPA-Banner, Safe-Mode-Banner) | `ui/settings/update_panel.tscn/.gd` | 220 |
| 5. CI Pack-Build + Manifest-Publish + public Repo anlegen | `pack-build.yml`, `tools/build_manifest.mjs`, `export_presets.cfg`-Einträge | 150 + 120 |
| 6. CI IPA-Build (unsigned, bettet Packs ein) | `ipa-build.yml` | 140 |
| 7. Doku + Tests (Semver, Merge-Regeln, Boot-Guard-Simulation) | `docs/UPDATES.md`, `test/updates/*.gd` | 200 + 180 |

Gesamt: ~16 Dateien, ~1900 LOC. Schritte 1–4 sind rein lokal testbar (Pck von Hand nach
`user://packs` kopieren), bevor irgendein CI-Teil existiert.

---

## Top-Entscheidungen (Kurzfassung)

**1. Download-Quelle:** Separates öffentliches Artefakt-Repo `MedusaV9/gooby-updates`
(nur gebaute `.pck`s + `manifest.json` am fixen Release-Tag `updates`). Tokenlos,
CDN-gestützt, kein Server nötig — offline-first bleibt intakt. Eingebettete Tokens
abgelehnt (extrahierbar → privater Code lesbar, Auto-Revocation-Risiko); Node.js-Proxy
nur als optionaler Mirror.

**2. Data-only-Packs:** 6 PCKs (`core`, `balance`, `events`, `cosmetics`, `stickers`,
`codes`) + `config` als plain JSON (Server-IP/Port sofort wirksam, ohne Neustart). Kein
GDScript in Packs — Policy, CI-erzwungen; neues Verhalten braucht bewusst eine IPA.
Code-Secrets nur als sha256 (Repo ist public).

**3. Deterministischer Boot statt Hot-Reload:** Packs laden beim Boot in fester
Prioritätsreihenfolge, namespaced unter `res://content/<id>/`; ContentRegistry mergt.
Downloads wirken ab Neustart/Soft-Restart — umgeht Godots Ressourcen-Cache ehrlich statt
„meistens“.

**4. Selbstheilung:** Boot-Guard mit persistiertem Versuchszähler: 2. Crash →
jüngstes Pack deaktivieren/rollback (previous-Datei), 3. Crash → Safe Mode (nur
eingebackener Content). Das Spiel ist nie soft-locked. Stale-Cleanup verhindert
Downgrades durch alte Downloads nach IPA-Update.

**5. Team-Modularität via Tag-Namespaces:** `cosmetics-v*` etc., CI baut pro geändertem
Content-Ordner per `godot --headless --export-pack`; IPA-Build bettet immer alle
aktuellen Packs ein. `min_native`-Gate meldet „Neue IPA nötig“ statt zu laden.

**6. iOS bestätigt:** PCK = reine Daten in `user://`, kein Codesign-Bruch; Sideload ohne
Review → Guidelines unkritisch. (238 Wörter)
