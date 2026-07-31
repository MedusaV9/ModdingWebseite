extends Node
## Boot-Szene (W1a; W14/LOADING). Die Autoloads sind hier bereits geladen —
## main zeigt SOFORT das Boot-Cover (Querformat-Artwork + Möhren-Ladebalken,
## User-Wunsch: „ganz am Anfang beim Rein laden … Coverartwork mit Ladebalken
## unten“) und fährt dahinter die ECHTEN Boot-Phasen (BootPhasen):
##
## 1. "packs"  — PackLoader hat die Content-Packs gemountet (Autoload, VOR dem
##               ersten Frame; hier wird nur das Ergebnis geprüft + gemeldet).
## 2. "save"   — GameState hat den Spielstand geladen (ebenfalls Autoload).
## 3. "welt"   — threaded Load des Zuhause-Einstiegs (ECHTER
##               ResourceLoader-Sub-Fortschritt, kein Fake).
## 4. "einrichten" — HomeEntry instanzieren (Routen, HUD, Onboarding-Check).
## 5. "zuhause" — die erste Router-Reise ins Wohnzimmer (Sub-Fortschritt aus
##               den Router-State-Meilensteinen); frische Saves brechen hier
##               bewusst früh ab, sobald das Onboarding auf Eingabe wartet.
##
## Danach öffnet sich das Cover charmant (Zoom + Kreis-Wipe auf Gooby +
## Konfetti; Reduced Motion: Fade). Force-Reveal nach ZUHAUSE_TIMEOUT_MS —
## das Cover sperrt NIE dauerhaft (Web-Veil-HARD_TIMEOUT-Muster).

const ENTRY_SCENE_PATH := "res://scenes/home/home_entry.tscn"
## Force-Reveal-Deckel der letzten Phase (Web-Veil: HARD_TIMEOUT_MS 8 s +
## Puffer für langsame Erst-Importe auf Altgeräten).
const ZUHAUSE_TIMEOUT_MS := 15_000

var _cover: BootCoverScreen
var _zuhause_aktiv := false

@onready var world: Node3D = $World


func _ready() -> void:
	_cover = BootCoverScreen.new()
	add_child(_cover)
	_boot()


func _boot() -> void:
	# Ein Frame warten, damit das Cover garantiert VOR der Boot-Arbeit malt.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_melde_autoload_phasen()
	var packed := await _lade_welt()
	if not is_inside_tree():
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
	await get_tree().process_frame
	if not is_inside_tree():
		return
	add_child(packed.instantiate())
	_cover.set_progress(BootPhasen.prozent("einrichten", 1.0))
	await _warte_auf_zuhause()
	if not is_inside_tree():
		return
	await _cover_oeffnen()


## Phase 1+2 liefen als Autoloads vor dem ersten Frame: nur die Ergebnisse
## prüfen und EHRLICH als abgeschlossen melden (nichts wird nachgestellt).
func _melde_autoload_phasen() -> void:
	var packs := get_node_or_null("/root/PackLoader")
	_cover.set_progress(BootPhasen.prozent("packs", 1.0 if packs != null else 0.0))
	var gs := get_node_or_null("/root/GameState")
	_cover.set_progress(BootPhasen.prozent("save", 1.0 if gs != null else 0.0))


## Zuhause-Einstieg threaded laden; der ECHTE Lade-Fortschritt des
## ResourceLoaders speist die "welt"-Phase des Balkens.
func _lade_welt() -> PackedScene:
	if ResourceLoader.load_threaded_request(ENTRY_SCENE_PATH) != OK:
		var direkt := load(ENTRY_SCENE_PATH)
		return direkt if direkt is PackedScene else null
	while true:
		if not is_inside_tree():
			return null
		var fortschritt: Array = []
		var status := ResourceLoader.load_threaded_get_status(ENTRY_SCENE_PATH, fortschritt)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not fortschritt.is_empty():
				_cover.set_progress(BootPhasen.prozent("welt", float(fortschritt[0])))
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_cover.set_progress(BootPhasen.prozent("welt", 1.0))
			var res := ResourceLoader.load_threaded_get(ENTRY_SCENE_PATH)
			return res if res is PackedScene else null
		break
	return null


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
		if not is_inside_tree():
			return
		if _wartet_auf_eingabe(router):
			break
		await get_tree().process_frame
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
