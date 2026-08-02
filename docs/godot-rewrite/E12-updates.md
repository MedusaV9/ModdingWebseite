# E12 — Update-System-Robustheit (rein funktional)

## Verdict

**Kernmechanik PASS, Produktintegration FAIL.** Der unabhängige Headless-Test
(nicht der Unit-Test-Runner) besteht **30/30** funktionale Prüfungen. Ein
gutartiges, ausschließlich aus `pack.json` und `data/cosmetics.json` bestehendes
PCK wird per `file://`-Manifest gefunden, kopiert, SHA-256-verifiziert,
installiert und beim nächsten Boot gemountet; `ContentRegistry` liefert danach
den neuen Inhalt. Ein separater zweiter Godot-Prozess bestätigt den echten
Autoload-Boot. Config, Boot-Guard, defekte Eingaben, Downgrade und Stale-Cleanup
funktionieren auf API-/Dateiebene.

Der dokumentierte Endnutzerweg ist dagegen nicht fertig verdrahtet: Im
laufenden Produkt ist der Settings-Screen nicht vom HUD aus erreichbar,
Update-Ergebnisse werden nicht angezeigt und der Safe-Mode hat keinen Banner/
Retry-Aufruf. Damit ist das robuste Backend vorhanden, aber der beschriebene
Produktflow nicht benutzbar.

Getestet auf Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`), Godot
`4.4.1.stable.official.49a5bc7b6`. Das Repository blieb unverändert
(`git status --short` leer); alle Testartefakte liegen unter `/tmp` bzw. einem
isolierten `user://`.

## Befunde nach Priorität

### P0

Keine.

### P1-01 — Update- und Recovery-UI ist im Produkt nicht verdrahtet

**Auswirkung:** Ein Spieler kann den dokumentierten „Suche nach Updates“-Flow
nicht regulär auslösen/auswerten und Safe-Mode nicht per „Erneut versuchen“
verlassen.

Belege aus dem echten Code:

- `HomeEntry._build_hud()` verbindet nur `Hud.action_pressed`, nicht
  `Hud.settings_pressed`; letzteres wird vom Zahnrad zwar emittiert, hat aber
  keinen Consumer.
- `settings_screen.tscn` wird außerhalb von Tests/Screenshot-Code nirgends
  instanziiert.
- `SettingsUpdateGlue` wird nirgends instanziiert oder per `attach()` verbunden.
  Ein manuell instanziierter Settings-Screen startet zwar
  `UpdateManager.check_for_updates()`, ignoriert aber
  `check_completed`; `UPDATED`, `ERROR`, `UP_TO_DATE` und
  `NEEDS_NATIVE` bleiben ohne Toast.
- `PackLoader.pack_disabled`, `safe_mode_entered`, `is_safe_mode()` und
  `reenable_all_packs()` haben außerhalb von Tests keinen Consumer. Der in
  `docs/UPDATES.md` versprochene Banner/Retry existiert nicht.

Die Unit-Tests übersehen dies, weil sie Glue-Schlüssel statisch prüfen und
Services direkt instanziieren, nicht den Produktions-Einstieg.

**Repro:** App starten, HUD-Zahnrad drücken: `settings_pressed` wird emittiert,
aber nichts öffnet sich. Alternativ:

```bash
rg 'settings_pressed\.connect|SettingsUpdateGlue|safe_mode_entered|reenable_all_packs' \
  GOOBY-GODOT --glob '*.{gd,tscn}'
```

Es erscheinen nur Definitionen/Tests, keine Produktionsverdrahtung.

### P2-01 — Gemischter Teilerfolg meldet `UPDATED` trotz Downloadfehler

`UpdateService._final_result()` priorisiert `UPDATED` vor `ERROR`. Im
Laufzeittest installierte ein valides Config-Update, während ein zweites,
abgeschnittenes PCK korrekt am SHA-Mismatch scheiterte. Ergebnis:
`result == UPDATED`, zugleich `details.errors` nicht leer. Selbst nach Anschluss
des vorhandenen Glue würde nur „Update geladen“ erscheinen; der Fehler bleibt
unsichtbar.

**Empfehlung:** Einen eigenen `PARTIAL`-Status einführen oder bei
`details.errors` mindestens zusätzlich den Fehlerhinweis anzeigen.

### P2-02 — Boot-Guard-Dokumentation zählt Crashes falsch

Code und Laufzeit entscheiden beim **Beginn** eines Boots nach dem bereits
inkrementierten Zähler:

- Versuch 1: `NORMAL`
- Versuch 2 (also nach **einem** nicht bestätigten Vorboot):
  `DISABLE_NEWEST`/Rollback
- Versuch 3 (also nach **zwei** nicht bestätigten Vorboots): `SAFE_MODE`

`docs/UPDATES.md` nennt dagegen mehrfach „nach 2 Crashes“ bzw. „≥ 3
Boot-Crashes“. Die Versuchstabelle ist korrekt, die Crash-Formulierungen in
§5.3, Troubleshooting und FAQ sind driftend.

### P2-03 — Dokumentierter Soft-Restart ist nicht implementiert

`PackLoader.load_packs_at_boot()` läuft automatisch nur in der einmaligen
Autoload-`_ready()`. Es gibt außerhalb der Tests keinen weiteren Aufrufer.
„Zurück zur Boot-Szene → Packs laden“ aus §5.5 mountet daher nichts neu.
Verlässlich funktioniert der echte Prozessneustart; dieser wurde separat
bestätigt.

### P3 / Härtungs-Empfehlung — Daten und ersetzbare Ressourcen trennen

Der Loader verwendet aktuell
`ProjectSettings.load_resource_pack(path, true)`. Als Best Practice sollten
downloadbare Inhalte in einem strikt versionierten Daten-Namespace liegen und
mit `replace_files=false` gemountet werden; zusätzlich Data-only-Allowlist in
Build/CI beibehalten. **Nicht einfach nur den Boolean umstellen:** Die aktuelle
Struktur aktualisiert bestehende Packs durch Überschreiben identischer
`res://content/<id>/...`-Pfade und müsste vorher auf explizites Lesen der
versionierten Pack-Pfade umgebaut werden.

## Funktionale Evidenz

### Gutartiges PCK: kompletter Flow außerhalb der Unit-Tests

Testskript: `/tmp/gooby-godot/eval/e12_updates_eval.gd`

Inhalt des mit `PCKPacker` gebauten Packs:

- `res://content/e12_cosmetics/pack.json`
- `res://content/e12_cosmetics/data/cosmetics.json`
- einziges neues Item: `e12_benign_hat` / „E12 Testhut“
- kein Script, keine Szene, kein Code, kein Überschreiben bestehender Pack-IDs

Ausführung:

```bash
XDG_DATA_HOME=/tmp/gooby-godot/eval/e12-xdg-v2 \
  godot --headless --path /workspace/GOOBY-GODOT \
  --script /tmp/gooby-godot/eval/e12_updates_eval.gd
```

Ergebnis: `E12_RESULT passes=30 failures=0`.

Nachgewiesene Kette:

1. PCKPacker baut das reine Daten-Pack.
2. `file://manifest.json` wird geparst.
3. PCK und plain `config.json` werden heruntergeladen/kopiert.
4. SHA-256 stimmt; `installed.json` enthält Hash und Version.
5. Vor dem Boot-Mount ist der neue PCK-Inhalt erwartungsgemäß unsichtbar.
6. `PackLoader` mountet die neue Pack-ID.
7. `ContentRegistry.version_of("e12_cosmetics") == "1.2.3"`.
8. `ContentRegistry.get_cosmetics()` enthält `e12_benign_hat`.
9. Erfolgs-Boot setzt `attempts=0` und `survived_boot=true`.
10. Ein zweiter Check ist `UP_TO_DATE`.

Echter neuer Prozess:

```bash
XDG_DATA_HOME=/tmp/gooby-godot/eval/e12-xdg-v2 \
  godot --headless --path /workspace/GOOBY-GODOT \
  --script /tmp/gooby-godot/eval/e12_autoload_probe.gd
```

Ergebnis:

```text
E12_AUTOLOADS=["PackLoader", "ContentRegistry", ..., "UpdateManager", "Net", ...]
E12_PACK_IDS=[..., "e12_cosmetics", ...]
E12_HAS_CONTENT=true
```

Damit ist der reale Autoload-Boot über Prozessgrenze bestätigt.

### Boot-Guard über legitime API/State-Dateien

Bestanden:

- Versuch 1: normal, keine Deaktivierung.
- Versuch 2: höchste `installed_seq` mit `survived_boot=false` deaktiviert.
- Versuch 2 mit existierender `previous`: aktuelle Datei gelöscht, Metadaten auf
  Vorgängerversion zurückgestellt, Pack bleibt aktiviert/bewährt.
- Versuch 3: Safe-Mode, alle aktivierten user-Packs deaktiviert.
- `reenable_all_packs()`: alle wieder aktiv, Guard auf 0.
- `mark_boot_successful()`: Erfolgs-Reset dauerhaft auf 0.

### Defekte, nicht bösartige Eingaben

Bestanden:

- abgeschnittenes syntaktisch kaputtes Manifest → `ERROR`;
- syntaktisch valides, aber halbes Manifest → Validator-`ERROR`;
- halbierte PCK-Datei bei Hash des vollständigen Packs → SHA-Mismatch,
  `.part` gelöscht, kein Ziel, kein installierter Eintrag;
- Manifest-Version unter installierter Version → `UP_TO_DATE`, kein Downgrade;
- `min_native=99.0.0` → `NEEDS_NATIVE`, `gated=["e12_gate"]`, kein Download,
  Glue-Schlüssel `updates.braucht_ipa`;
- gemischtes valides + abgeschnittenes Update → Teilfehler korrekt in
  `details.errors`, aber Gesamtstatus fälschlich `UPDATED` (P2-01).

### Config-Serverweg ohne IPA

Ein valides plain `config.json` mit
`{"net":{"host":"e12.local","port":4545,"tls":false}}` wurde über dasselbe
Manifest installiert. `ContentRegistry.reload()` lieferte Host/Port sofort;
ein realer `NetClient.connect_now()` über einen Capture-Link versuchte exakt:

```text
ws://e12.local:4545/ws
```

### Stale-Cleanup

Bei eingebautem `e12_stale` v2.0.0 und installiertem v1.5.0 plus
`previous` v1.0.0 wurden beide alten Dateien gelöscht, der
`installed.json`-Eintrag entfernt und `report.cleaned=["e12_stale"]` geliefert.

## Doku-Abgleich `docs/UPDATES.md`

| Aussage | Ist |
|---|---|
| file-Manifest → SHA → Install → Boot-Mount → Registry | korrekt |
| Config wirkt sofort; NetClient liest bei jedem Connect | korrekt |
| Downgrades werden vermieden | korrekt |
| Stale user-Pack ≤ Built-in wird entfernt | korrekt |
| Native-Gate lädt Pack nie | korrekt |
| previous-Rollback / Safe-Mode / Erfolgs-Reset | Kern-API korrekt |
| Settings-Toasts sind verdrahtet | falsch; Glue ist verwaist |
| Safe-Mode-Banner + „Erneut versuchen“ | falsch; keine UI-Integration |
| „2/3 Crashes“ | ungenau/falsch; tatsächlich Versuch 2/3 |
| Zur Boot-Szene zurück = Soft-Restart lädt Packs | falsch; kein Aufrufer |

## Weitere Verifikation

```text
Godot-Hauptsuite: 438 Tests, 0 fehlgeschlagen
gdlint Updates-Scope: no problems found
gdformat --check Updates-Scope: 11 files unchanged
Headless-App-Smoke: Exit 0
Repository: git status --short leer
```
