# GOOBY-EVAL 2026-08 — Lens C: Technik, Tests, Performance, CI

**Stand der Messung:** 8. August 2026 · Godot
`4.4.1.stable.official.49a5bc7b6` · Linux/Xvfb/llvmpipe · Branch
`cursor/gooby-godot-loop-2-d1d8`

**Lens-Grenze:** Dieser Bericht bewertet ausschließlich Technik, Tests,
Performance, Save-Integrität, CI und Code-Gesundheit. Gameplay und visuelle
Qualität werden nur erwähnt, wenn sie einen technischen Messwert erklären.

## Kurzurteil

**Technischer Reifegrad: 6/10 — sehr breite, in Teilen hervorragende
Testsubstanz, aber noch kein ehrliches Release-Gate.**

Das Positive zuerst: 3.816 Haupttests und 27.352 UI-Checks decken erstaunlich
viel Logik ab. Die Zufallsstichprobe der Kernsysteme war 5/5 echte
Verhaltensprüfung, nicht bloß „Szene lässt sich instanzieren“. Save/Migration
ist die stärkste technische Domäne: echte Alt-Saves, tiefe Feldvergleiche,
Fuzz-Eingaben, drei Backup-Generationen und Recovery aus `.tmp` sind vorhanden
und grün. Die drei gemessenen Welten bleiben unter dem für diese Bewertung
gesetzten 400-Draw-Call-Budget.

Das Negative ist nicht kosmetisch: Die lokale Vollsuite ist reproduzierbar
rot, während CI grün meldet. Zwei echte Server-Integrationstests zeigen in CI
„PASS“, nachdem sie sich wegen eines hart kodierten, dort nicht existierenden
Pfads selbst übersprungen haben. Lokal existiert dieser absolute Pfad, aber dem
Server fehlen Dependencies; beide Tests laufen deshalb jeweils 20 Sekunden in
einen Timeout. Das ist kein Flake, sondern ein falsches grünes Signal. GvZ
reißt im belasteten L8-Snapshot mit 371 Draw Calls das Minigame-Budget um 48 %
und mit 619.527 Rendering-Primitiven den 250k-Richtwert deutlich. Jeder
Haupttestlauf endet zusätzlich mit RID-/Resource-Leaks, der nackte Boot mit
einem konstanten `ObjectDB`-Leak. Der iOS-Job ist grün und forensisch
verifiziert, packt durch `all_resources` aber sogar Tests in eine 194,9-MB-IPA.

**Release-Urteil:** Offline-Kern und Save-Pfad sind belastbar. Netzwerk-Gate,
GvZ-Budget, Test-Teardown und IPA-Selektion sind vor einem technisch sauberen
Release zu beheben. Ein P0-Datenverlust wurde nicht gefunden; mehrere P1-
Qualitäts- und Gate-Probleme bleiben.

## Kernzahlen

| Bereich | Ergebnis | Urteil |
|---|---:|---|
| Hauptsuite lokal, aktueller Snapshot | 484 Dateien · **3.816 Tests · 2 rot** · 866,354 s | Rot; beide Server-Integrationen |
| Hauptsuite lokal, erster Lauf | 482 Dateien · 3.796 Tests · 2 rot · 878,753 s | Derselbe Fehler, also reproduzierbar |
| Hauptsuite letzte CI | 3.796 Tests · 0 rot · Test-Step 17:19 min | Formal grün, aber 2 Serverfälle optional geskippt |
| W1c lokal | **27.352 Checks · 0 rot · 8,152 s** | Funktional grün; Polygonfehler bleibt |
| Nackter Boot, ohne Lock-Wartezeit | Exit 0 · 3,145 s / 3,137 s | Bootet, aber `ObjectDB`-Leak |
| Boot Prozessstart → `home/living` | **11.962 ms** | 2.434 ms bis Treiber, 9.493 ms Main→interaktiv |
| Welten | Stadt **258–307**, Ranch **159**, Park **111** Draw Calls | Alle unter Eval-Budget 400 |
| Minispiele | GvZ L8 **371**, Battleship **244** Draw Calls | GvZ rot; Battleship nur 6 Calls Reserve |
| Letzte veröffentlichte CI | [Run 31247137637](https://github.com/MedusaV9/CustomServerPrivate/actions/runs/31247137637) · alle regulären Jobs grün | 23:45 min End-to-End |
| iOS | **194,9 MB · 6.527 PCK-Dateien** | Verifiziert, aber unnötig aufgebläht |

Die erste gemessene nackte Boot-Walltime von 70,278 s enthielt rund 67 s
Wartezeit am gemeinsam verwendeten `flock` und ist **keine** Cold-Boot-Zeit.
Sie wird deshalb nicht als Produktwert verkauft.

## 1. Tests

### 1.1 Vollsuite: lokal reproduzierbar rot

Ausgeführt wurde, seriell über den VM-weiten Godot-Lock:

```text
bash tools/ci/run_godot_isolated.sh \
  godot --headless --path GOOBY-GODOT --script res://tests/run_tests.gd
```

Der aktuelle Lauf:

```text
== GOOBY-Tests: 484 Testdateien ==
FAIL test_net_integration.gd::test_hello_und_freunde_flow_gegen_echten_server
  — Server wurde nicht binnen 20 s erreichbar
FAIL test_social_integration.gd::test_social_stack_gegen_echten_server
  — Server wurde nicht binnen 20 s erreichbar
== Ergebnis: tests=3816, failed=2 ==
```

Beide gestarteten Node-Prozesse sterben vorher eindeutig:

```text
Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'express'
imported from /workspace/GOOBY-SERVER/server.js
```

Der erste Vollauf vor dem parallel gelandeten Widget-Paket hatte 3.796 Tests,
ebenfalls exakt diese zwei Fehler. Laufzeiten: 878,753 s und 866,354 s. Das ist
kein zufälliger Test-Flake; die Umwelt-/Pfadabhängigkeit ist deterministisch
kaputt.

Die Ursache hat zwei Ebenen:

1. Beide Tests kodieren `SERVER_JS := "/workspace/GOOBY-SERVER/server.js"`
   absolut ein. Das ist weder der angegebene Worktree
   `/workspace/worktrees/gooby` noch der GitHub-Workspace.
2. Die CI installiert in `GOOBY-SERVER/` keine npm-Dependencies. Im aktuellen
   CI fällt bereits die absolute Pfadprüfung durch; die Tests drucken
   `SKIP (optional)` und kehren ohne Assert zurück. Der Runner zählt sie danach
   als `PASS`.

Letzte CI:

```text
SKIP (optional): GOOBY-SERVER/server.js fehlt noch
PASS test_net_integration.gd::test_hello_und_freunde_flow_gegen_echten_server
SKIP (optional): GOOBY-SERVER/server.js fehlt noch
PASS test_social_integration.gd::test_social_stack_gegen_echten_server
== Ergebnis: tests=3796, failed=0 ==
```

**Bewertung:** Die Unit-/Fake-Link-Abdeckung der Netzwerklogik ist wertvoll,
aber die Bezeichnung „Integrationstest gegen echten Server“ ist im grünen CI-
Lauf faktisch falsch. Ein Skip darf nicht als Pass ohne Skip-Zähler erscheinen.

### 1.2 W1c-Runner

```text
checks: 27352
failed: 0
```

Der gültige lokale Lauf dauerte 8,152 s. Positiv: Breiten, Safe-Areas,
Onboarding, Toast-Lanes, Theme, Strings und Veil-Zustände werden mit vielen
inhaltlichen Asserts geprüft.

Der Lauf ist trotzdem nicht logsauber:

```text
ERROR: Fehlender String-Key: gibt.es.nicht (de)
ERROR: Invalid polygon data, triangulation failed.
```

Der fehlende Key gehört zu einem Negativtest. Der Polygonfehler tritt dagegen
im `test_ui_veil.gd::test_wipe_endzustaende_und_reduced_motion` auf und
wiederholt sich lokal wie in CI. Nach dem Runner meldet CI außerdem
`ObjectDB instances leaked` und `4 resources still in use at exit`.

### 1.3 Zufallsstichprobe Kernsysteme

Die fünf Kandidaten wurden reproduzierbar aus Save, Economy, Quests und
Minigame-Logik gewählt (Seed = HEAD-SHA). Alle fünf liefen im Volltest und
prüfen echte Zustandsübergänge:

| Test | Was tatsächlich geprüft wird | Qualität |
|---|---|---|
| `test_state_save_manager.gd::test_corruption_recovers_from_backup` | Hauptdatei wird physisch zerstört; Recovery muss `bak1`, Coins 111 und `.corrupt` liefern | Verhalten, stark |
| `test_migration_fuzz.gd::test_fuzz_save_manager_bootet_immer` | 7 Text-/Binärmüll-Klassen werden auf Platte geschrieben; jede muss als v5-Dictionary recovern und Rohdatei sichern | Verhalten, stark |
| `test_state_logic.gd::test_economy_golden_step_sequence` | Award/Spend-Sequenz gegen Golden mit Coins, Earned, Spent, Tages- und Endless-Ledger nach jedem Schritt | Verhalten, stark |
| `test_rest2_quest_engine.gd::test_punkte_quest_zaehlt_erst_nach_heutiger_runde` | Alter Bestwert zählt nicht; erst eine neue Runde schaltet gedeckelten Fortschritt und Complete frei | Verhalten, stark |
| `test_w13_gvz_wiring.gd::test_run_stats_zaehlen_deterministisch_in_der_sim` | Vollständige deterministische GvZ-Sim, Tower-/Schuss-/Drop-/Kill-Zähler und hash-neutrale Stats | Verhalten, stark |

**Stichprobenurteil: 5/5 echte Verhaltensprüfung.** Das Problem des Testsystems
ist nicht fehlende Assert-Substanz, sondern Gate-/Skip-Ehrlichkeit und
Teardown-Hygiene.

### 1.4 Log- und Teardown-Hygiene der Hauptsuite

Der aktuelle Lauf enthält 33 `ERROR:`, 44 `WARNING:` und 2 `SCRIPT ERROR:`.
Ein Teil davon sind bewusst provozierte Negativpfade. Echte technische
Störsignale gehen darin unter:

```text
SCRIPT ERROR: Left operand of 'is' is a previously freed instance.   (2×)
ERROR: Parameter "material" is null.                                 (14×)
ERROR: 16 RID allocations ... DummyTexture ... leaked at exit.
ERROR: 20 RID allocations ... DummyMesh ... leaked at exit.
ERROR: 18 RID allocations ... DummyMaterial ... leaked at exit.
ERROR: 3 RID allocations ... DummyShader ... leaked at exit.
ERROR: 11 RID allocations ... RendererSceneCull::Instance ... leaked.
WARNING: ObjectDB instances leaked at exit.
ERROR: 44 resources still in use at exit.
```

Ein Runner, der trotz `SCRIPT ERROR` einzelne Tests als grün wertet, liefert
kein hinreichend starkes Runtime-Gate. Erwartete Negativtest-Logs brauchen
gezielte Erfassung; alles andere muss den Lauf fehlschlagen lassen.

## 2. Boot-Hygiene

Zwei unkontendierte Läufe von
`godot --headless --path GOOBY-GODOT --quit` endeten mit Exit 0 in 3,145 s und
3,137 s. Beide enthielten genau:

```text
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
```

Der Verbose-Lauf klassifiziert:

| Klasse | Befund |
|---|---|
| Objekt-Leaks | 6× `RefCounted`, 1× `GDScriptFunctionState` |
| StringName-Leaks | `process_frame`, `_lade_welt`; 2 unclaimed |
| Netzwerk beim Boot | `Socket error: 111`, `Connection to remote host failed` |
| RID-Leaks | **0 im nackten Boot** |
| Navigation-Sync-Warnungen | **0** |
| Shader-Compile-/Shader-Fehler | **0** |
| Ressourcen „still in use“ | **0 im nackten Boot** |

Der suspendierte Function-State passt zum bereits in `E4-perf.md`
dokumentierten Exit-Pfad `LoadingVeil.cover()` → Audio/await, wird durch diesen
Trace aber nicht neu bis zur konkreten Coroutine bewiesen. Wichtig ist: Der
Leak ist konstant und bootblockiert nicht, verschmutzt jedoch jeden CI-Lauf und
maskiert neue Leaks. Der Netzwerk-Connect beim nackten Boot ist ein unnötiger
Seiteneffekt für Smoke-Tests/offline Start.

Der gerenderte Boot bis zur tatsächlich aufgedeckten Home-Route wurde separat
gemessen:

```text
BOOT_TIMING process_to_driver_ms=2434
            main_to_interactive_ms=9493
            total_ms=11962
            frames=75 target=home/living
```

Das ist auf llvmpipe kein iPhone-Benchmark, aber 9,5 s Main→interaktiv ist auch
als VM-Proxy auffällig. Ein nackter `--quit`-Smoke von 3,1 s beweist diese
User-Zeit nicht.

## 3. Performance

### 3.1 Methode und Budget

Der temporäre Treiber lag ausschließlich unter `/tmp`, nutzte
`PerfOverlay.snapshot()`/`RenderingServer.get_rendering_info`, wartete 60 Frames
und nahm danach die Maxima über 80 Frames. Er wurde nicht committet. Aufruf:
Xvfb 1280×720, OpenGL Compatibility, llvmpipe, Dummy-Audio.

`A-engine.md` §7 dokumentiert Raum ≤150 Draw Calls/≤150k Tris und Minigame
≤250/≤250k. Ein eigenes dokumentiertes Open-World-Limit von 400 war dort nicht
auffindbar; die **400er Weltgrenze stammt aus diesem Eval-Auftrag** und wird
hier entsprechend verwendet. `TOTAL_PRIMITIVES_IN_FRAME` ist der vom
Projekt-Overlay gelieferte Primitive-Zähler; er ist ein guter Trendindikator,
aber nicht auf jedem Canvas-/3D-Pfad exakt mit „Dreiecke“ gleichzusetzen.

CPU-`frame_ms` unter llvmpipe wird dokumentiert, aber **nicht** als
iPhone-FPS-Urteil benutzt.

### 3.2 Gemessene Szenen

| Szene | Draw Calls | Primitive | Szenen-Nodes | Gesamt-Nodes | VRAM | llvmpipe process ms | Budget |
|---|---:|---:|---:|---:|---:|---:|---|
| Stadt, freie Fahrt, Tag | **258–307** | 338.386 | 465 | 558 | 66,2 MB | 163,07–180,55 | Welt ≤400: **PASS** |
| Ranch, voll aufgebaut/Hof | **159** | 429.971 | 1.235 | 1.328 | 64,6 MB | 184,17 | Welt ≤400: **PASS** |
| Funkelpark, Tag | **111** | 103.064 | 208 | 293 | 70,8 MB | 24,77–37,62 | Welt ≤400: **PASS** |
| GvZ L8, 4 Tower + 7 sichtbare Zombies | **371** | 619.527 | 236 | 315 | 73,8 MB | 79,58 | MG ≤250: **FAIL** |
| Battleship, Setup | **244** | 23.108 | 284 | 372 | 70,3 MB | 19,66–22,11 | MG ≤250: **PASS knapp** |

GvZ wurde erst gewertet, nachdem der Messstatus explizit
`max_zombies=7` ausgab. Ein voriger, unbelasteter Lauf mit
`max_zombies=0` wurde verworfen. Gegenüber E4 (866 Draw Calls in der damaligen
2D-Immediate-Version) ist 371 eine klare Verbesserung von rund 57 %, aber noch
121 Calls beziehungsweise 48 % über Budget. Gleichzeitig ist durch die neue
3D-Bühne der Primitive-Zähler auf 619.527 gestiegen.

Battleship ist formal grün, hat aber nur 2,4 % Draw-Call-Puffer. Ein weiteres
HUD-/Effektpaket kann es ohne Wächter über die Grenze schieben.

Die Stadt schwankte bei identischem Setup zwischen 258 und 307 Draw Calls
(19 % bezogen auf den kleineren Wert), während Ranch, Park und Battleship
stabil waren. Wahrscheinliche dynamische Beiträge müssen erst isoliert werden;
ohne festen Snapshot ist der Messwert als Regression-Baseline zu breit.

### 3.3 Lade- und Wechselzeiten

| Ziel | Direkt `ready_for_reveal` | Router-Wechsel komplett |
|---|---:|---:|
| Stadt | 167–195 ms | **2.349–2.357 ms** |
| Funkelpark | 38–42 ms | **1.003–1.083 ms** |
| Ranch | 1.921–2.304 ms | **2.935–2.946 ms** |
| GvZ L8 Setup | 2.016–2.231 ms | nicht über Router gemessen |
| Battleship Setup | 288–290 ms | nicht über Router gemessen |

Der erzwungene Ranch-Restaufbau nach Reveal (`baue_rest_sofort`) dauerte
zusätzlich 7.471–7.983 ms. Das ist nicht identisch mit Spieler-Wartezeit — die
Szene revealt vorher — zeigt aber, wie viel Arbeit nach dem ersten sichtbaren
Hof noch abgearbeitet wird.

### 3.4 Performance-Urteil

- **Welten:** Draw-Call-seitig im geforderten Open-World-Budget; Ranch erreicht
  das mit vielen Nodes und offenbar wirksamer Batching-/Streaming-Struktur.
- **GvZ:** weiterhin klar rot; sowohl Draw Calls als auch Primitive brauchen
  einen gezielten Pass.
- **Battleship:** gerade noch grün, ohne Sicherheitsmarge.
- **Start/Wechsel:** Park okay, Stadt/Ranch/GvZ und kompletter Boot auffällig.
- **Regression:** Es existiert ein Overlay, aber kein CI-Budgettest für diese
  fünf repräsentativen Lastzustände. Der wichtigste Nutzen des Overlay-Ansatzes
  bleibt damit manuell.

## 4. Save-Integrität

### 4.1 Vorhandene Absicherung

`SaveManager` bietet:

- Schreiben über `.tmp` + `flush()` + Rename,
- drei Backup-Generationen,
- Recovery-Reihenfolge `.tmp` → `bak1` → `bak2` → `bak3`,
- Sicherung der kaputten Rohdatei als `.corrupt`,
- Migration vor Normalisierung,
- injizierte Zeit für Load/Migration/Autosave.

Vorhandene echte Alt-Fixtures:

```text
v4_fresh.json
v4_midgame.json
v4_maxed.json
v4_urlaub.json
v2_legacy.json
v2_legacy.expected_v4.json
```

Im aktuellen Vollauf bestanden unter anderem:

```text
PASS test_fresh_fixture_migrates
PASS test_midgame_fixture_migrates_losslessly
PASS test_maxed_fixture_migrates
PASS test_v2_legacy_chain_matches_web_chain
PASS test_all_corrupt_falls_back_to_fresh
PASS test_wrong_typed_slice_is_corrupt_not_crash
PASS test_missing_file_prefers_complete_tmp_over_bak
PASS test_missing_file_skips_broken_bak1_uses_bak2
```

Die v2-Kette wird deep-equal mit der vom Web-Code vorgemigrierten v4-Fixture
verglichen. Midgame prüft unter anderem Coins, laufende Reise-Erstattung,
Stats, Gewicht, Sticker und Verlustbericht. Das ist deutlich stärker als ein
reiner „Migration gibt Dictionary zurück“-Test.

### 4.2 Restlücken

Die Fuzz-Tests sind eine kuratierte Menge harter Payloads und strukturierter
Mutationen, kein Property-Fuzzer mit Tausenden generierten Sequenzen. Außerdem
werden Crashfenster logisch durch vorbereitete Dateien simuliert; es gibt
keinen Subprozess-Test, der einen Schreiber zwischen Backup-Rotation und Rename
wirklich beendet. `_rotate_backups()` ignoriert Rückgabefehler der Rename-/
Remove-Aufrufe. Volle Platte, Berechtigungsfehler und fehlschlagende
Backup-Rotation sind nicht abgedeckt.

**Save-Urteil: 8,5/10.** Kein Datenverlustfund in der Stichprobe; die
verbleibenden Punkte sind Härtung, nicht ein aktuell reproduzierter Verlust.

## 5. CI und iOS

### 5.1 Letzter veröffentlichter Lauf

[Run 31247137637](https://github.com/MedusaV9/CustomServerPrivate/actions/runs/31247137637)
auf Commit `4e72c8e0`:

| Job | Dauer | Zustand |
|---|---:|---|
| `lint` | 3:10 min | grün (`gdlint` 1:32, `gdformat --check` 1:19) |
| `linux-checks` | 19:39 min | formal grün |
| `ios-ipa` | 4:00 min | grün, startet nach Linux |
| `release` | — | korrekt geskippt, kein Release-Trigger |
| Gesamtlauf | 23:45 min | grün |

Der kritische Pfad wird fast vollständig von der ungeshardeten Hauptsuite
bestimmt: 17:19 min im `Test-Runner`. W1c braucht 9 s, Boot 4 s.

In den letzten 20 sichtbaren Workflow-Läufen waren 18 grün und 2 rot:

- Run `30331638663`: `gdformat --check`, genau eine vergessene Datei.
- Run `30753776121`: echter Server-Integrationstest
  `test_wj6_gaestebuch...` lief nach 20 s in einen Server-Timeout
  (`3645 Tests, 1 rot`).

Das ist kein Bild einer zufällig instabilen Godot-Engine. Es zeigt zwei
Prozessrisiken: Formatierung vor Push und uneinheitliche echte Servertests.
Der aktuelle absolute-Pfad-Skip versteckt letztere inzwischen, statt sie zu
lösen.

### 5.2 IPA

Der aktuelle veröffentlichte iOS-Job meldet:

```text
IPA PASS: .ipa gebaut: 194.9 MB, 6527 Dateien im PCK
(1422 Assets + 40 JSON verifiziert,
 Orientierungen: LandscapeLeft, LandscapeRight)
```

Positiv: Export, unsigned `xcodebuild`, Packen und forensische Prüfung sind
grün. Die Prüfung leitet Bundle-/Orientierungs-Erwartungen aus dem Preset ab.

Negativ:

- `export_filter="all_resources"` packt auch Testcode; der Exportlog nennt
  konkret `res://tests/unit/test_shop_screen.gdc`.
- Der Quellordner `GOOBY-GODOT/tests/` allein belegt rund **10 MB**; dazu
  kommen Tools und Dev-Helfer.
- Die IPA ist gegenüber der alten E4-Schätzung von 20–25 MB auf 194,9 MB
  gewachsen. Ein Teil ist legitimer Content-Zuwachs, aber Testcode gehört
  unabhängig davon nicht in das Produkt-PCK.
- Exportwarnung:
  `Unicode parsing error ... NUL character`.
- Beide iPhone-Icon-Slots verwenden die 1024er Quelle und werden bei jedem
  Export automatisch auf 120 bzw. 180 px skaliert.

Der Build ist also **technisch erfolgreich**, aber nicht distributionssauber.

## 6. Code-Gesundheit

### 6.1 Größte GDScript-Dateien

| Datei | Zeilen | Bytes | Funktionen |
|---|---:|---:|---:|
| `scripts/home/customize/customize_screen.gd` | **1.000** | 36.734 | 59 |
| `scripts/minigames/games/delivery_rush/delivery_rush.gd` | **1.000** | 35.736 | 44 |
| `scripts/minigames/games/ranch_herde/herde_game.gd` | **1.000** | 33.890 | 42 |

Alle drei landen exakt am konfigurierten `max-file-lines: 1000`. Das sieht
nicht nach gesundem Modulzuschnitt aus, sondern nach Wachstum bis an die
Lintkante. `customize_screen` mischt Zustandsmutation, Kauf, Layout, UI-Bau,
Preview und Eventhandler. `delivery_rush` mischt Routing/Autopilot, Sim,
Verkehr, 3D-Bühnenbau, HUD und Kamera. `herde_game` enthält Levelauswahl, Sim,
Welt-/Tierbau, Kamera, Effekte und HUD.

`gdlint` und `gdformat --check` sind im letzten CI-Lauf grün. Das ist
Stilkonformität, kein Beweis für geringe Komplexität.

### 6.2 Autoload- und Root-Kopplung

Der aktuelle Commit hat **20 Autoloads**. Viele Screens lösen Abhängigkeiten
per Root-String statt Konstruktor-/Context-Injektion auf. Beispiele:

- `dev_menu.gd`: 13 direkte `/root/...`-Lookups,
- `settings_screen.gd`: 11,
- `arcade_screen.gd`: 7,
- `boot/main.gd`: 7,
- `social_screen.gd`, `minigame_host.gd`, `pregame.gd`: je 6.

Die Lookups sind meist `get_node_or_null` und damit crashweich, aber nicht
kopplungsarm. Das erschwert isolierte Tests und macht Autoload-Reihenfolge zur
unsichtbaren API. Der neue `WidgetBridge` vergrößert die globale Oberfläche
weiter.

### 6.3 Tote und duplizierte Pfade

- `FriendsScreen.register_routes()` wird im Produkt nicht aufgerufen; Treffer
  sind Test-/Screenshot-/Auditcode. Produktion registriert `SocialScreen`.
  `friends_screen.tscn` ist damit trotz gegenteiliger Kommentare kein
  nachweisbar erreichbarer Vollbildpfad.
- Der ältere E15-Befund zum Settings-Screen ist **nicht mehr aktuell**:
  `HomeEntry` verbindet `settings_pressed` mit `_open_settings()` und
  instanziiert `settings_screen.tscn`.
- `scripts/state/os_bridge.gd` hat keinen Produktionsaufrufer und dupliziert
  die inzwischen echte `scripts/state/import/legacy_capacitor.gd`-Lösung.
- `CityNotificationService` besitzt weiterhin eine eigene statische
  Reise-Queue neben dem Autoload `NotificationService`/`NotifyStub`.

Klassische Kommentar-Marker `TODO/FIXME/HACK/XXX`: **0** in produktivem
GDScript (`"HACK"` kommt einmal nur als abgelehnter Testdatenwert vor).
Allerdings existieren **18 `BACKLOG`-Markierungen** in produktiven Skripten.
Einige beschreiben inzwischen implementierte Funktionalität und sind selbst
Dokumentationsschuld.

## 7. Top-10-Findings

1. **CI ist bei zwei echten Server-Integrationen falsch grün:** absoluter
   `/workspace`-Pfad + optionaler Return werden als PASS gezählt.
2. **Die lokale Hauptsuite ist reproduzierbar rot:** 3.816 Tests, dieselben
   zwei Server-Timeouts in zwei Volläufen.
3. **GvZ bleibt über Budget:** 371/250 Draw Calls und 619.527 Primitive im
   belasteten L8-Snapshot.
4. **Test-Teardown leakt massiv:** 16 Texturen, 20 Meshes, 18 Materialien,
   3 Shader, 11 Instanzen und 44 Ressourcen.
5. **Boot ist nicht logsauber:** konstanter `ObjectDB`-Leak plus unnötiger
   Netzwerk-Connect beim nackten Smoke.
6. **Boot bis Home dauert im VM-Proxy 11,96 s;** Ranch-Wechsel liegt bei
   2,95 s, vollständiger Restaufbau weitere 7,47 s.
7. **Die IPA ist mit 194,9 MB/6.527 Dateien aufgebläht und enthält Tests.**
8. **Der Veil erzeugt reproduzierbar ungültige Polygon-Daten,** obwohl W1c
   formal 0 Fehler zählt.
9. **Drei produktive Skripte stehen exakt bei 1.000 Zeilen** mit 42–59
   Funktionen und mehreren Verantwortlichkeiten.
10. **20 Autoloads, breite Root-String-Kopplung und tote/duplizierte Dienste**
    erhöhen Boot-, Test- und Änderungsrisiko.

## 8. Priorisierte Technik-Queue

Sortierung: Risiko × Auswirkung, nicht nach Bequemlichkeit.

| # | Problem und Beleg | Konkreter Fix | Betroffene Dateien | Aufwand |
|---:|---|---|---|:---:|
| 1 | **Server-Integration ist falsch grün.** CI: `SKIP (optional)` → `PASS`; lokal 2× 20-s-Timeout. | Pfad aus `ProjectSettings.globalize_path("res://../GOOBY-SERVER/server.js")` ableiten; `npm ci` als CI-/Preflight-Step; in CI fehlenden Server/Node als Fehler behandeln; Runner muss Skips separat zählen. | `tests/unit/test_net_integration.gd`, `test_social_integration.gd`, `tests/run_tests.gd`, `tools/ci/preflight.sh`, `.github/workflows/gooby-godot.yml`, `GOOBY-SERVER/package-lock.json` | M |
| 2 | **GvZ 371 Draw Calls / 619.527 Primitive.** 48 % über Draw-Budget. | RenderDoc/iPhone-Profiling; Bühne/HUD getrennt messen; Materialien/Meshes cachen; wiederholte Crowd-/Prop-Geometrie über MultiMesh/Atlas; belasteten L8-Wächter einchecken. | `scripts/minigames/games/gvz/gvz_stage3d.gd`, `gvz_props3d.gd`, `gvz_hud.gd`, `gvz_game.gd`, neuer Perf-Test | L |
| 3 | **Runner akzeptiert echte Engine-/Scriptfehler.** 2× freed-instance, 14× null material bei nur 2 Testfails. | Godot-Log in strukturierte erwartete/unerwartete Meldungen trennen; Negativtests kapseln; unerwartetes `SCRIPT ERROR`/`ERROR` lässt Runner rot werden. | `tests/run_tests.gd`, betroffene Szenentests, `tools/ci/preflight.sh` | M |
| 4 | **Massive RID-/Resource-Leaks am Suite-Ende.** | Testdateien per Leak-Bisect gruppieren; Instanzen/Viewport/Ressourcen explizit freigeben; nach jeder Datei Node-/RID-Drift prüfen; Abschlussgate auf 0. | `tests/run_tests.gd`, Tests um GvZ/3D/Materialbuilder, gemeinsame Test-Fixtures | L |
| 5 | **Boot-`ObjectDB`-Leak in jedem Lauf.** 6 RefCounted + 1 FunctionState. | Suspendierte Boot-/Veil-Coroutine bei Quit abbrechen; Audio fire-and-forget entkoppeln; Verbose-Boot als 0-Leak-Gate aufnehmen. | `scripts/core/loading_veil.gd`, `scripts/audio/audio_director.gd`, Boot-Smoke | M |
| 6 | **Ungültiges Veil-Polygon reproduzierbar lokal und CI.** | Degenerierte/zu kurze Punktlisten vor `draw_polygon` abweisen; konkrete Seed/Viewport-Kombination als Regressionstest pinnen; W1c darf Engine-Error nicht überstimmen. | `scripts/core/loading_veil.gd` bzw. Petal/Wipe-Helfer, `tests/unit/test_ui_veil.gd` | S |
| 7 | **Kein automatisches Perf-Budgetgate.** GvZ-Regression blieb trotz Overlay sichtbar. | Deterministischen Render-Runner für Stadt/Ranch/Park/GvZ/Battleship einchecken; feste Zustände, Warmup und zulässige Bandbreite; Draw/Node/Primitive-Trends als CI-Artefakt. | `scripts/dev/perf_overlay.gd`, neue `tests/perf/*`, CI/Preflight optionaler Perf-Job | M |
| 8 | **Boot/Wechsel auffällig:** 11,96 s bis Home; Stadt 2,35 s, Ranch 2,95 s. | Phasen-Telemetrie in Main/Router (Import, Save, Home-Bau, Veil-Mindestzeit, Ready); unnötige Boot-Netzverbindung verschieben; Stadt/Ranch-Builder weiter time-slicen/cachen; Budgets definieren. | `scripts/boot/main.gd`, `scripts/core/scene_router.gd`, `scripts/city/*`, `scripts/ranch/welt/*`, `scripts/net/net_client.gd` | L |
| 9 | **IPA enthält Tests und ist 194,9 MB groß.** Log zeigt `test_shop_screen.gdc`; `tests/` ≈10 MB Quelle. | Produktpreset auf explizite Ressourcen oder mindestens Excludes für `tests/**`, `tools/**`, Dev-/Screenshot-Treiber; Verify-Skript verbietet Testpfade im PCK. | `GOOBY-GODOT/export_presets.cfg`, `tools/ci/verify_ipa.py` | M |
| 10 | **iOS-Exportwarnungen:** NUL/Unicode und Auto-Resize zweier Icons. | Verursacherdatei des NUL-Bytes im Exportlog identifizieren und säubern; echte 120/180-Icon-Assets generieren/referenzieren; Warnungen fail-closed klassifizieren. | betroffene Ressource, `icon_gooby_*`, `export_presets.cfg`, Export-Gate | S |
| 11 | **Drei 1.000-Zeilen-God-Objects.** 59/44/42 Funktionen. | Zustand/Actions, Builder, Rendering/Stage, HUD und Input in testbare Komponenten teilen; bestehende Public-API per Contracttests halten. | `customize_screen.gd`, `delivery_rush.gd`, `ranch_herde/herde_game.gd` + neue Teilmodule | L |
| 12 | **20 Autoloads und breite `/root/...`-Kopplung.** | `AppContext/Services` in Entry/Host injizieren; Dev-/Screen-spezifische Dienste nicht autoloaden; Root-Lookups hinter kleinen Adaptern zentralisieren. | `project.godot`, `boot/main.gd`, `home_entry.gd`, `minigame_host.gd`, `settings_screen.gd`, `arcade_screen.gd` | L |
| 13 | **Tote/duplizierte Pfade:** FriendsScreen nicht produktiv registriert; `os_bridge.gd` ohne Nutzer; zwei Notification-Queues. | FriendsScreen bewusst löschen oder Route/Wiring herstellen; OS-Bridge auf `legacy_capacitor` reduzieren; Reise-Notifications auf `Notify.schedule/cancel` migrieren. | `scripts/ui/friends/*`, `scripts/ui/social/*`, `scripts/state/os_bridge.gd`, `scripts/city/notification_service.gd`, `reise_app.gd`, `platform/notification_service.gd` | M |
| 14 | **Save-Rotation ignoriert Datei-I/O-Fehler; Crash nur simuliert.** | Rename/Remove-Ergebnisse prüfen und Save fehlschlagen lassen; Subprozess beim definierten Faultpoint töten; volle Platte/Permission/Rename-Failure testen. | `scripts/state/save_manager.gd`, `tests/unit/test_state_save_manager.gd`, neuer Fault-Injection-Treiber | M |
| 15 | **CI-Kritischer Pfad 23:45 min, davon Hauptsuite 17:19.** | Testdateien deterministisch in 2–4 isolierte Shards teilen; Reports zusammenführen; Server-Integration eigener Job; keine parallelen Godot-Prozesse lokal, aber CI-Runner je Shard getrennt. | `tests/run_tests.gd`, neue Shard-Argumente, `.github/workflows/gooby-godot.yml`, Preflight bleibt seriell | M |
| 16 | **Stadt-Draws schwanken 258→307 bei gleichem Label.** | Zeit, RNG, Verkehr, Wetter und Kamera vollständig injizieren; festen Perf-Snapshot definieren; Median + Max über Wiederholungen reporten und Jittergrenze setzen. | `scripts/city/city_scene.gd`, Stadt-Ambience/Traffic, neuer Perf-Fixture | M |

## Schluss

GOOBY hat kein Testmengenproblem. Es hat ein **Testvertrauensproblem an den
Systemgrenzen**: grün trotz Skip, grün trotz Engine-Error, grün trotz Leaks.
Die richtige Priorität ist deshalb nicht „noch 500 Unit-Tests“, sondern die
vorhandenen 3.816 Tests zu einem ehrlichen Gate zu machen, GvZ und Startpfad
mit denselben reproduzierbaren Budgets zu überwachen und nur
Produktressourcen in die IPA zu packen.

Der stärkste Gegenbeweis gegen ein pauschales „alles instabil“-Urteil ist die
Save-Domäne: echte Fixtures, deep-equal Migration, Fuzz und Recovery sind
substanziell und grün. Dieses Niveau muss jetzt für Netzwerk, Runtime-Logs und
Performance-Gates gelten.
