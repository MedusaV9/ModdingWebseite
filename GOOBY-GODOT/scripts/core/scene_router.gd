extends Node
## SceneRouter — DAS eine Transition-System (W1a; löst den Web-Doppel-Veil-Bug:
## es gibt genau EIN Transition-Surface und EINE Statemaschine).
##
## Statemaschine: IDLE → COVER → SWAP → WAIT_READY → REVEAL → IDLE.
## - COVER: LoadingVeil deckt ab; sein Blocker frisst ab hier allen Input.
## - SWAP: alte Szene queue_free() + 1 Frame; neue Szene kommt aus dem
##   threaded Preload (ResourceLoader.load_threaded_request).
## - WAIT_READY: Reveal erst wenn ALLE erfüllt: (a) neue Szene emittiert
##   "ready_for_reveal" (Szenen OHNE dieses Signal gelten sofort als bereit),
##   (b) idle_frames_required (2) Frames NACH ready vergangen (Shader-Warmup),
##   (c) min_shown_ms erreicht. Hard-Timeout hard_timeout_ms (10 s) →
##   Force-Reveal + Warnung — nie Deadlock.
## - REVEAL: Veil öffnet; danach IDLE + travel_finished.
##
## Replace-Queue: goto() während busy ERSETZT die wartende Anfrage (nur die
## letzte gewinnt, travel_replaced feuert) — nie zwei Transitions parallel.
##
## Reise-Typen (API FROZEN nach W1, Handoff W1a-core.md):
## - VEIL_TRAVEL: voller Ladescreen (Haus↔Stadt, Minigames, Orte).
## - DOOR_TRAVEL: Raumwechsel im Haus. W15/DOORTRAVEL (Doc A §1.4): der
##   Zielraum wird ADDITIV neben den Quellraum gemountet und die Kamera
##   fährt auf einer Path3D-Kurve durch den Türrahmen (_door_fahrt →
##   DoorTravelFahrt; Gooby läuft voraus, danach Quelle entladen). Fällt
##   die Fahrt aus (Reduced Motion, Low-End, additive Ladezeit über
##   DoorTravelFahrt.LADE_BUDGET_MS, fremde Szenen/Fixtures), bleibt der
##   kurze Tür-Wisch (EF-3/EVAL-1 F1) der Codepfad: ~330-ms-Wisch statt
##   Karte+Blende, Mindestanzeige door_min_shown_ms (0). W2-HOUSE ruft
##   goto(..., TravelType.DOOR_TRAVEL) NACH seiner Tür-Gag-/Lauf-Sequenz
##   auf; der Zielraum lädt derweil threaded im Hintergrund (preload_target
##   beim Tür-Tap). Signatur unverändert — die Fahrt ist eine INNERE
##   Variante, API/Signale/Timeouts des Routers bleiben frozen.
##
## FIX1 — EIN gemeinsamer Zurück-Pfad (P0 „Zurück-Button geht meist nicht“):
## - Der Router führt eine Reise-HISTORY; `back()` reist zum vorherigen Ziel.
## - `&"home"` ist ein ALIAS: alle Screens rufen `goto(&"home")` — vorher war
##   das Ziel NIE registriert (Räume heißen `home/<raum>`), der Guard
##   `routes.has(&"home")` schlug fehl und der Zurück-Knopf tat still NICHTS.
##   Jetzt wird der Alias automatisch mitregistriert, sobald die erste
##   `home/`-Route ankommt, und löst beim goto auf den zuletzt besuchten Raum
##   auf (sonst auf den Start-Raum).
## - Escape / Android-Back / iOS-Wischgeste (WM_GO_BACK_REQUEST): schließt
##   zuerst das oberste Panel (PanelStack), sonst reist es zurück.

signal state_changed(state: int)
signal travel_started(target: StringName, travel_type: int)
signal travel_finished(target: StringName)
signal travel_replaced(old_target: StringName, new_target: StringName)
signal travel_force_revealed(target: StringName)

enum TravelType { VEIL_TRAVEL, DOOR_TRAVEL }
enum State { IDLE, COVER, SWAP, WAIT_READY, REVEAL }

const READY_FOR_REVEAL_SIGNAL := &"ready_for_reveal"
const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")
## Alias-Ziel, das alle Zurück-Buttons ansteuern (FIX1).
const HOME_ALIAS := &"home"
## Präfix der Raum-Routen (RoomDefs.ROUTE_PREFIX — hier gespiegelt, damit
## der Router kein Home-Modul importieren muss).
const HOME_ROUTE_PREFIX := "home/"
## History-Deckel — reicht für tiefe Ketten, begrenzt Speicher.
const HISTORY_LIMIT := 16

## Mindest-Anzeigedauer des Veils (verhindert Blitz-Flackern bei Mini-Szenen).
var min_shown_ms := 600
## Mindest-Anzeigedauer für DOOR_TRAVEL (EF-3 F1): 0 — der Tür-Wisch ist so
## kurz wie das Laden erlaubt; die Wisch-Animation selbst glättet den Cut.
var door_min_shown_ms := 0
## Force-Reveal-Deckel: nach so vielen ms wird IMMER aufgedeckt (nie Deadlock).
var hard_timeout_ms := 10_000
## Idle-Frames nach ready_for_reveal (Shader-/Pipeline-Warmup).
var idle_frames_required := 2

var _state: int = State.IDLE
var _routes: Dictionary = {}
var _mount_point: Node = null
var _veil: Node = null
var _current_scene: Node = null
var _current_target := StringName()
var _pending: Dictionary = {}
var _busy := false
var _requested_paths: Dictionary = {}
## Reise-History (älteste zuerst): [{"target": StringName, "params": {}}].
var _history: Array[Dictionary] = []


func _ready() -> void:
	if _veil == null:
		var veil := VEIL_SCENE.instantiate()
		add_child(veil)
		_veil = veil
	# Escape/Back auch verarbeiten, wenn kein Control fokussiert ist.
	set_process_unhandled_input(true)


## Escape (Desktop) fungiert wie die System-Zurück-Geste.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if handle_back_request():
			get_viewport().set_input_as_handled()


## Android-Back / iOS-Zurück-Wisch kommt als WM-Notification an.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back_request()


## DER Zurück-Pfad (FIX1): oberstes Panel schließen, sonst zurückreisen.
## true = die Anfrage wurde konsumiert.
func handle_back_request() -> bool:
	if PanelStack.close_top():
		return true
	# Bei laufender Reise NICHT „true“ vortäuschen — sonst schlucken
	# Screens (Arcade) den Zurück-Tap ohne Navigation (H4).
	if _busy:
		return false
	if can_go_back():
		back()
		return true
	return false


## Ziel registrieren (W2/W3-Agents melden hier ihre Räume/Screens an,
## ohne den Router zu editieren). Die erste `home/`-Route registriert
## automatisch den `&"home"`-Alias mit (FIX1 — s. Kopfkommentar).
func register_route(target: StringName, scene_path: String) -> void:
	_routes[target] = scene_path
	if String(target).begins_with(HOME_ROUTE_PREFIX) and not _routes.has(HOME_ALIAS):
		_routes[HOME_ALIAS] = scene_path


func register_routes(routes: Dictionary) -> void:
	for target in routes.keys():
		register_route(target, routes[target])


## Container, in den Szenen gemountet werden (setzt main.gd beim Boot).
func set_mount_point(node: Node) -> void:
	_mount_point = node


## DI-Hook für Tests (Fake-Veil) — VOR dem Betreten des Trees aufrufen.
func install_veil(veil: Node) -> void:
	if _veil != null and _veil.get_parent() == self:
		_veil.queue_free()
	_veil = veil


## Threaded Preload beim "ersten Anfassen" eines Reiseziels (Tür-Tap,
## Reise-Dialog) — macht den SWAP später praktisch blockierungsfrei.
func preload_target(target: StringName) -> void:
	if not _routes.has(target):
		return
	var path := String(_routes[target])
	if _requested_paths.has(path) or ResourceLoader.has_cached(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_requested_paths[path] = true


## Einziger Einstiegspunkt für Szenenwechsel.
func goto(
	target: StringName, params: Dictionary = {}, travel_type: int = TravelType.VEIL_TRAVEL
) -> void:
	target = _resolve_target(target)
	if not _routes.has(target):
		push_error("SceneRouter: unbekanntes Ziel '%s' — erst register_route()." % target)
		return
	if _busy:
		if not _pending.is_empty():
			travel_replaced.emit(_pending["target"], target)
		_pending = {"target": target, "params": params, "type": travel_type}
		return
	_travel(target, params, travel_type)


## Zum vorherigen History-Ziel zurückreisen (DER gemeinsame Zurück-Pfad).
## true = Rückreise gestartet; false = keine History (Aufrufer entscheidet).
func back(travel_type: int = TravelType.VEIL_TRAVEL) -> bool:
	if _busy or not can_go_back():
		return false
	_history.pop_back()
	var previous: Dictionary = _history.back()
	_travel(previous["target"], previous["params"], travel_type, false)
	return true


func can_go_back() -> bool:
	return _history.size() >= 2


## History (älteste zuerst) — Kopie für Tests/Debug.
func get_history() -> Array[StringName]:
	var targets: Array[StringName] = []
	for entry in _history:
		targets.append(entry["target"])
	return targets


## Tests/Szenenwechsel-Reset (z. B. neuer Spielstand).
func clear_history() -> void:
	_history.clear()


func is_busy() -> bool:
	return _busy


func get_state() -> int:
	return _state


func get_current_target() -> StringName:
	return _current_target


func get_current_scene() -> Node:
	return _current_scene


## `&"home"` → zuletzt besuchter Raum (History), sonst erste `home/`-Route.
func _resolve_target(target: StringName) -> StringName:
	if target != HOME_ALIAS:
		return target
	for i in range(_history.size() - 1, -1, -1):
		var visited: StringName = _history[i]["target"]
		if String(visited).begins_with(HOME_ROUTE_PREFIX):
			return visited
	for key: StringName in _routes.keys():
		if String(key).begins_with(HOME_ROUTE_PREFIX):
			return key
	return target


func _record_history(target: StringName, params: Dictionary) -> void:
	if not _history.is_empty() and _history.back()["target"] == target:
		_history.back()["params"] = params
		return
	_history.append({"target": target, "params": params})
	while _history.size() > HISTORY_LIMIT:
		_history.pop_front()


func _travel(target: StringName, params: Dictionary, travel_type: int, record := true) -> void:
	_busy = true
	if record:
		_record_history(target, params)
	_current_target = target
	var cover_started_ms := Time.get_ticks_msec()
	travel_started.emit(target, travel_type)
	preload_target(target)

	# W15/DOORTRAVEL (Doc A §1.4): additive Tür-Fahrt als INNERE Variante
	# von DOOR_TRAVEL — gleiche States/Signale/Timeouts. Jede Nicht-Eignung
	# (fremde Szene/Fixture, Reduced Motion, Low-End, Ladezeit über Budget)
	# fällt auf den bewährten Wisch-Pfad darunter zurück.
	var gefahren := false
	if travel_type == TravelType.DOOR_TRAVEL:
		gefahren = await _door_fahrt(target, params, cover_started_ms)

	if not gefahren:
		_set_state(State.COVER)
		await _veil.cover(_reduced_motion())

		_set_state(State.SWAP)
		if is_instance_valid(_current_scene):
			_current_scene.queue_free()
		_current_scene = null
		await get_tree().process_frame
		var ready_state := {"ready": false}
		var packed := await _finish_threaded_load(String(_routes[target]))
		if packed != null:
			_mount_scene(packed, params, ready_state)
		else:
			push_error("SceneRouter: Szene für '%s' konnte nicht geladen werden." % target)
			ready_state["ready"] = true

		_set_state(State.WAIT_READY)
		var min_shown := (
			door_min_shown_ms if travel_type == TravelType.DOOR_TRAVEL else min_shown_ms
		)
		var clean := await _wait_until_ready(ready_state, cover_started_ms, min_shown)
		if not clean:
			push_warning(
				(
					"SceneRouter: Hard-Timeout (%d ms) für '%s' — Force-Reveal."
					% [hard_timeout_ms, target]
				)
			)
			travel_force_revealed.emit(target)

		_set_state(State.REVEAL)
		await _veil.reveal(_reduced_motion())

	_set_state(State.IDLE)
	_busy = false
	travel_finished.emit(target)
	_drain_pending()


## W15: additive Tür-Fahrt (Kamera fährt DURCH die Tür statt Wisch).
## true = Fahrt komplett gelaufen (Ziel gemountet, Quelle entladen, States
## COVER→SWAP→WAIT_READY→REVEAL bedient); false = Aufrufer nimmt den Wisch.
func _door_fahrt(target: StringName, params: Dictionary, started_ms: int) -> bool:
	if _mount_point == null or not is_instance_valid(_current_scene):
		return false
	var grund := DoorTravelFahrt.fallback_grund(
		_reduced_motion(), DoorTravelFahrt.ist_low_end(get_tree().root), 0
	)
	if grund != "":
		return false
	var plan := DoorTravelFahrt.fahrt_plan(_current_scene, target, params)
	if plan.is_empty():
		return false
	var packed := await _lade_im_budget(String(_routes[target]), started_ms)
	if packed == null:
		return false

	_set_state(State.COVER)
	_set_state(State.SWAP)
	var quelle := _current_scene
	var ready_state := {"ready": false}
	_mount_scene(packed, params, ready_state)
	var fahrt := DoorTravelFahrt.new()
	fahrt.name = "DoorTravelFahrt"
	_mount_point.add_child(fahrt)
	fahrt.vorbereiten(quelle as Node3D, _current_scene as Node3D, plan)

	_set_state(State.WAIT_READY)
	var clean := await _wait_until_ready(ready_state, started_ms, door_min_shown_ms)
	if not clean:
		push_warning(
			"SceneRouter: Hard-Timeout (%d ms) für '%s' — Force-Reveal." % [hard_timeout_ms, target]
		)
		travel_force_revealed.emit(target)

	_set_state(State.REVEAL)
	await fahrt.abfahren(not clean)
	if is_instance_valid(quelle):
		quelle.queue_free()
	fahrt.queue_free()
	return true


## W15: threaded Load mit hartem Zeitbudget (DoorTravelFahrt.LADE_BUDGET_MS,
## gemessen ab Reisebeginn). Nicht rechtzeitig fertig → null; der Wisch-Pfad
## lädt dann wie bisher zu Ende (inklusive Veil-Fortschritt).
func _lade_im_budget(path: String, started_ms: int) -> PackedScene:
	if ResourceLoader.has_cached(path):
		var cached := load(path)
		return cached if cached is PackedScene else null
	if not _requested_paths.has(path):
		return null
	var deadline := started_ms + DoorTravelFahrt.LADE_BUDGET_MS
	while Time.get_ticks_msec() < deadline:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_requested_paths.erase(path)
			var res := ResourceLoader.load_threaded_get(path)
			return res if res is PackedScene else null
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		await get_tree().process_frame
	return null


func _mount_scene(packed: PackedScene, params: Dictionary, ready_state: Dictionary) -> void:
	_current_scene = packed.instantiate()
	if _current_scene.has_signal(READY_FOR_REVEAL_SIGNAL):
		var mark_ready := func() -> void: ready_state["ready"] = true
		_current_scene.connect(READY_FOR_REVEAL_SIGNAL, mark_ready, CONNECT_ONE_SHOT)
	else:
		ready_state["ready"] = true
	if _current_scene.has_method("receive_params"):
		_current_scene.receive_params(params)
	var mount := _mount_point if _mount_point != null else self
	mount.add_child(_current_scene)


func _wait_until_ready(ready_state: Dictionary, started_ms: int, min_shown := -1) -> bool:
	if min_shown < 0:
		min_shown = min_shown_ms
	var idle_frames := 0
	while true:
		var elapsed := Time.get_ticks_msec() - started_ms
		var is_ready: bool = ready_state["ready"]
		if is_ready and idle_frames >= idle_frames_required and elapsed >= min_shown:
			return true
		if elapsed >= hard_timeout_ms:
			return false
		await get_tree().process_frame
		if ready_state["ready"]:
			idle_frames += 1
	return false


func _finish_threaded_load(path: String) -> PackedScene:
	if _requested_paths.has(path):
		while true:
			var progress: Array = []
			var status := ResourceLoader.load_threaded_get_status(path, progress)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if not progress.is_empty() and _veil != null and _veil.has_method("set_progress"):
					_veil.set_progress(float(progress[0]))
				await get_tree().process_frame
				continue
			_requested_paths.erase(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(path)
				if res is PackedScene:
					return res
			break
	var fallback := load(path)
	return fallback if fallback is PackedScene else null


func _drain_pending() -> void:
	if _pending.is_empty():
		return
	var next: Dictionary = _pending
	_pending = {}
	_travel(next["target"], next["params"], next["type"])


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


func _set_state(state: int) -> void:
	_state = state
	state_changed.emit(state)
