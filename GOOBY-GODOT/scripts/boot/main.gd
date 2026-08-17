extends Node
## Boot-Szene (W1a; W14/LOADING). Die Autoloads sind hier bereits geladen —
## main zeigt SOFORT das Boot-Cover (Querformat-Artwork + Möhren-Ladebalken,
## User-Wunsch: „ganz am Anfang beim Rein laden … Coverartwork mit Ladebalken
## unten“) und fährt dahinter die ECHTEN Boot-Phasen (BootPhasen):
##
## 1. "packs"  — PackLoader hat die Content-Packs gemountet (Autoload, VOR dem
##               ersten Frame; hier wird nur das Ergebnis geprüft + gemeldet).
## 2. "save"   — GameState hat den Spielstand geladen (ebenfalls Autoload).
## 3. "welt"   — threaded Load des Zuhause-Einstiegs PLUS Warmup-Liste
##               (W16/BOOTPERF: Wohnzimmer, HUD, Gooby-Rig, Home-Musik) —
##               ECHTER, gewichteter ResourceLoader-Sub-Fortschritt, kein
##               Fake; die späteren Synchron-Loads werden Cache-Hits.
## 4. "einrichten" — HomeEntry instanzieren (Routen, HUD, Onboarding-Check).
## 5. "zuhause" — die erste Router-Reise ins Wohnzimmer (Sub-Fortschritt aus
##               den Router-State-Meilensteinen); frische Saves brechen hier
##               bewusst früh ab, sobald das Onboarding auf Eingabe wartet.
##
## Danach öffnet sich das Cover charmant (Zoom + Kreis-Wipe auf Gooby +
## Konfetti; Reduced Motion: Fade). Force-Reveal nach ZUHAUSE_TIMEOUT_MS —
## das Cover sperrt NIE dauerhaft (Web-Veil-HARD_TIMEOUT-Muster).

## EVAL-2026-08/C #5: `await get_tree().process_frame` bleibt bei Quit
## suspendiert — die Boot-Coroutine leakt dann als GDScriptFunctionState
## samt Stack (konstanter ObjectDB-Leak in JEDEM Boot-Smoke). Dieses
## Signal feuert pro Frame UND beim Baum-Austritt, damit jede wartende
## Boot-Coroutine aufwacht und über `_beendet` sauber zu Ende läuft.
signal frame_oder_abbruch

const ENTRY_SCENE_PATH := "res://scenes/home/home_entry.tscn"
## Force-Reveal-Deckel der letzten Phase (Web-Veil: HARD_TIMEOUT_MS 8 s +
## Puffer für langsame Erst-Importe auf Altgeräten).
const ZUHAUSE_TIMEOUT_MS := 15_000
## W16/BOOTPERF (E3): Warmup-Ziele der "welt"-Phase neben dem Einstieg —
## genau die Pfade, die später sonst SYNCHRON auf dem Main-Thread laden
## (Befund B6): hud.tscn (home_entry._build_hud), Wohnzimmer-Szene (erste
## Router-Reise; "living" spiegelt HomeEntry.START_ROOM — KEIN direkter
## HomeEntry-Verweis, sonst zöge main.gd dessen Klassengraph in den Compile),
## gooby.glb (gooby_rig.gd) und der Home-Musik-Track (music_director.gd,
## fällt sonst exakt in den Reveal-Moment). Gewichte = grobe Kostenanteile
## für den Balken-Sub-Fortschritt (Summe 1.0; Einstieg dominiert, weil sein
## Skript-Klassengraph die reale Last der Phase ist).
const WARMUP_ENTRY_GEWICHT := 0.55
const WARMUP_START_ROOM := "living"
const WARMUP_EXTRAS: Array[Dictionary] = [
	{"pfad": "res://scripts/ui/hud.tscn", "gewicht": 0.07},
	{"pfad": "res://assets/character/gooby.glb", "gewicht": 0.10},
]
const WARMUP_RAUM_GEWICHT := 0.13
const WARMUP_MUSIK_GEWICHT := 0.15

var _cover: BootCoverScreen
var _zuhause_aktiv := false
## Quit-/Teardown-Flag (EVAL-2026-08/C #5): _exit_tree setzt es VOR dem
## Weck-Signal — resumte Coroutinen brechen ab, ohne freigegebene
## Kinder (_cover) anzufassen.
var _beendet := false
## Noch nicht abgeholte load_threaded_request-Ziele (EVAL-2026-08/C #5):
## bei Quit MITTEN im Warmup lädt der Loader-Thread weiter Skripte, während
## die Engine schon abbaut — deren Static-Initialisierer leaken dann als
## RefCounted-Instanzen im ObjectDB-Report. _exit_tree holt offene Ziele
## deshalb blockierend ab (deterministischer Teardown statt Race).
var _offene_ladeziele: Array[String] = []
## Referenzen auf fertig geladene Warmup-Ressourcen — hält sie im
## ResourceLoader-Cache, bis die echten Verbraucher (HUD/Raum/Rig/Musik)
## eigene Referenzen besitzen; wird nach der Cover-Öffnung geleert.
var _warmup_refs: Dictionary = {}

@onready var world: Node3D = $World


func _ready() -> void:
	_cover = BootCoverScreen.new()
	add_child(_cover)
	_boot()


func _process(_delta: float) -> void:
	frame_oder_abbruch.emit()


func _exit_tree() -> void:
	_beendet = true
	frame_oder_abbruch.emit()
	# Offene Warmup-Loads abholen: jeder nicht abgeholte Load-Token
	# überlebt sonst das Engine-Cleanup und leakt (s. o.).
	for pfad in _offene_ladeziele:
		BootCoverScreen.lade_token_abholen(pfad)
	_offene_ladeziele.clear()


func _boot() -> void:
	# Ein Frame warten, damit das Cover garantiert VOR der Boot-Arbeit malt.
	await frame_oder_abbruch
	if _beendet or not is_inside_tree():
		return
	_melde_autoload_phasen()
	var packed := await _lade_welt()
	if _beendet or not is_inside_tree():
		return
	if packed == null:
		# Fallback (Einstieg fehlt): Mount-Point wie in W1 setzen — und das
		# Cover trotzdem öffnen, der Bildschirm bleibt nie gesperrt.
		var router := get_node_or_null("/root/SceneRouter")
		if router != null and router.has_method("set_mount_point"):
			router.set_mount_point(world)
		await _cover_oeffnen()
		return
	_cover.set_progress(BootPhasen.prozent("einrichten", 0.0))
	await frame_oder_abbruch
	if _beendet or not is_inside_tree():
		return
	# W16/BOOTPERF (E1/B10): Die erste Router-Reise läuft KOMPLETT unsichtbar
	# hinterm Boot-Cover (Layer 120 > Veil 100) — die 600-ms-Anti-Flacker-
	# Mindestanzeige des Veils wäre hier reine Wartezeit auf schnellen
	# Geräten. Nur für die Boot-Reise nullen (das Cover übernimmt die
	# Anti-Flacker-Rolle selbst) und danach zurücksetzen; der Default 600
	# für normale, sichtbare Reisen bleibt unverändert (test_loading_regeln).
	var boot_router := get_node_or_null("/root/SceneRouter")
	var min_shown_normal := -1
	if boot_router != null and "min_shown_ms" in boot_router:
		min_shown_normal = boot_router.min_shown_ms
		boot_router.min_shown_ms = 0
	add_child(packed.instantiate())
	_cover.set_progress(BootPhasen.prozent("einrichten", 1.0))
	await _warte_auf_zuhause()
	if boot_router != null and min_shown_normal >= 0:
		boot_router.min_shown_ms = min_shown_normal
	if _beendet or not is_inside_tree():
		return
	await _cover_oeffnen()
	# Die Verbraucher halten jetzt eigene Referenzen (bzw. beim Onboarding-
	# Abbruch verhält sich der nächste Load wie heute) — Cache-Anker lösen.
	_warmup_refs.clear()


## Phase 1+2 liefen als Autoloads vor dem ersten Frame: nur die Ergebnisse
## prüfen und EHRLICH als abgeschlossen melden (nichts wird nachgestellt).
func _melde_autoload_phasen() -> void:
	var packs := get_node_or_null("/root/PackLoader")
	_cover.set_progress(BootPhasen.prozent("packs", 1.0 if packs != null else 0.0))
	var gs := get_node_or_null("/root/GameState")
	_cover.set_progress(BootPhasen.prozent("save", 1.0 if gs != null else 0.0))


## W16/BOOTPERF (E3): die Warmup-Liste der "welt"-Phase — Einstieg zuerst,
## danach nur Extras, die wirklich existieren (fehlende Dateien fallen still
## aus der Liste = heutiges Verhalten ohne Warmup). Statisch für den Test.
static func warmup_ziele() -> Array[Dictionary]:
	var ziele: Array[Dictionary] = [{"pfad": ENTRY_SCENE_PATH, "gewicht": WARMUP_ENTRY_GEWICHT}]
	var extras: Array[Dictionary] = []
	for extra in WARMUP_EXTRAS:
		extras.append(extra.duplicate())
	var raum := str(RoomDefs.route_table().get(RoomDefs.route_target(WARMUP_START_ROOM), ""))
	extras.append({"pfad": raum, "gewicht": WARMUP_RAUM_GEWICHT})
	var musik := MusicRegistry.path(MusicRegistry.track_for("home"))
	extras.append({"pfad": musik, "gewicht": WARMUP_MUSIK_GEWICHT})
	for extra in extras:
		var pfad := str(extra["pfad"])
		if pfad != "" and ResourceLoader.exists(pfad):
			ziele.append(extra)
	return ziele


## Zuhause-Einstieg + Warmup-Liste threaded laden (W16/BOOTPERF E3); der
## ECHTE, gewichtete Lade-Fortschritt ALLER Ziele speist die "welt"-Phase —
## feine Granularität statt des load_steps=2-Sprungs, und die späteren
## Synchron-Loads der Verbraucher werden Cache-Hits.
func _lade_welt() -> PackedScene:
	if ResourceLoader.load_threaded_request(ENTRY_SCENE_PATH) != OK:
		var direkt := load(ENTRY_SCENE_PATH)
		return direkt if direkt is PackedScene else null
	_offene_ladeziele.append(ENTRY_SCENE_PATH)
	var ziele := warmup_ziele()
	var fertig: Dictionary = {}
	for ziel in ziele:
		var pfad := str(ziel["pfad"])
		if pfad == ENTRY_SCENE_PATH:
			continue
		if ResourceLoader.has_cached(pfad):
			_warmup_refs[pfad] = load(pfad)  # Cache-Hit, sofort fertig.
			fertig[pfad] = true
		elif ResourceLoader.load_threaded_request(pfad) != OK:
			fertig[pfad] = true  # Kein Request möglich → wie heute ohne Warmup.
		else:
			_offene_ladeziele.append(pfad)
	var sub_gemeldet := 0.0
	while true:
		if _beendet or not is_inside_tree():
			return null
		var sub := _warmup_fortschritt(ziele, fertig)
		# Nur vorwärts melden — die gewichtete Summe ist monoton, der Guard
		# hält die Regel auch bei Rundungs-Rauschen ein.
		if sub > sub_gemeldet:
			sub_gemeldet = sub
			_cover.set_progress(BootPhasen.prozent("welt", sub))
		if fertig.has(ENTRY_SCENE_PATH):
			if _warmup_refs.get(ENTRY_SCENE_PATH) == null:
				return null  # Einstieg fehlgeschlagen → Fallback wie bisher.
			if fertig.size() == ziele.size():
				break
		await frame_oder_abbruch
	_cover.set_progress(BootPhasen.prozent("welt", 1.0))
	var res: Variant = _warmup_refs.get(ENTRY_SCENE_PATH)
	return res if res is PackedScene else null


## Gewichteter Gesamt-Fortschritt (0..1) aller Warmup-Ziele. Fertige Ziele
## werden abgeholt (load_threaded_get) und in _warmup_refs verankert, damit
## die späteren load()-Aufrufe der Verbraucher garantierte Cache-Hits sind;
## fehlgeschlagene Ziele zählen als fertig (Fallback = heutiges Verhalten).
func _warmup_fortschritt(ziele: Array[Dictionary], fertig: Dictionary) -> float:
	var summe := 0.0
	var gewicht_summe := 0.0
	for ziel in ziele:
		var pfad := str(ziel["pfad"])
		var gewicht := float(ziel["gewicht"])
		gewicht_summe += gewicht
		if fertig.has(pfad):
			summe += gewicht
			continue
		var fortschritt: Array = []
		var status := ResourceLoader.load_threaded_get_status(pfad, fortschritt)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not fortschritt.is_empty():
				summe += gewicht * clampf(float(fortschritt[0]), 0.0, 1.0)
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_warmup_refs[pfad] = ResourceLoader.load_threaded_get(pfad)
		fertig[pfad] = true
		_offene_ladeziele.erase(pfad)
		summe += gewicht
	return summe / maxf(gewicht_summe, 0.0001)


## Letzte Phase: auf die erste abgeschlossene Router-Reise warten (Sub-
## Fortschritt aus den ECHTEN Router-State-Meilensteinen). Frische Saves
## zeigen stattdessen das Onboarding — sobald der Router dafür still bleibt,
## öffnet das Cover aufs Onboarding. Deckel: ZUHAUSE_TIMEOUT_MS.
func _warte_auf_zuhause() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	var fertig := {"ok": false}
	if router.has_signal("travel_finished"):
		router.travel_finished.connect(
			func(_target: StringName) -> void: fertig["ok"] = true, CONNECT_ONE_SHOT
		)
	_zuhause_aktiv = true
	if router.has_signal("state_changed"):
		router.state_changed.connect(_on_router_state)
	var deadline := Time.get_ticks_msec() + ZUHAUSE_TIMEOUT_MS
	while not fertig["ok"] and Time.get_ticks_msec() < deadline:
		if _beendet or not is_inside_tree():
			return
		if _wartet_auf_eingabe(router):
			break
		await frame_oder_abbruch
	_zuhause_aktiv = false
	if router.has_signal("state_changed") and router.state_changed.is_connected(_on_router_state):
		router.state_changed.disconnect(_on_router_state)


## Onboarding/Übernahme-Angebot wartet auf den Spieler (kein Router-Ziel in
## Arbeit) → das Cover muss öffnen, sonst sähe niemand die Frage.
func _wartet_auf_eingabe(router: Node) -> bool:
	if router.has_method("is_busy") and router.is_busy():
		return false
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_value"):
		return false
	return not bool(gs.get_value("onboarding.done", false))


func _on_router_state(state: int) -> void:
	if not _zuhause_aktiv or _cover == null:
		return
	var sub := BootPhasen.zuhause_sub_fuer_router_state(state)
	# Nur vorwärts melden — REVEAL→IDLE (0.0) darf den Balken nicht zurückziehen.
	var neu := BootPhasen.prozent("zuhause", sub)
	if neu > _cover.get_progress():
		_cover.set_progress(neu)


func _cover_oeffnen() -> void:
	_cover.set_progress(1.0)
	await _cover.oeffne(_reduced_motion())
	_cover.queue_free()


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
