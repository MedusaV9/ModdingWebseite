extends SceneTree
## BUGHUNT-Durchlauf-Treiber (KEIN Test, gehört zum Fehlerjagd-Werkzeugkasten):
## fährt das Spiel headless durch alle Routen, Screens, Panels und Minigames,
## spielt jedes Spiel kurz per Zufalls-Bot und provoziert danach bekannte
## Kanten (Doppel-goto, Quit im Countdown, Pause/Resume, erschöpfter Gooby).
## Die Fundgrube ist die Godot-Fehlerausgabe des Laufs:
##   godot --headless --path GOOBY-GODOT \
##     --script res://tests/tools/bughunt_walkthrough.gd 2>&1 | tee lauf.log
## Fortschrittszeilen tragen das Präfix [BUGHUNT], alles andere (ERROR /
## SCRIPT ERROR / WARNING) stammt aus dem Spiel selbst.

## Sekunden Zufalls-Bot pro Minigame (Countdown kommt obendrauf).
const PLAY_SEC := 6.0
## Routen, die Parameter brauchen und deshalb eigene Phasen haben.
const PARAM_ROUTES: Array[StringName] = [&"mg_pregame", &"mg_host"]
## HUD-Aktionen, die Screens/Panels öffnen (Reihenfolge = HUD-Leiste).
const HUD_ACTIONS: Array[StringName] = [
	&"bau", &"reise", &"arcade", &"album", &"profil", &"igohbie", &"wardrobe", &"ikea"
]

var _router: Node
var _gs: Node
var _entry: Node
var _rng := RandomNumberGenerator.new()
var _travel_count := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_rng.seed = 20260726
	_log("Durchlauf startet")
	await _boot_fresh()
	await _complete_onboarding()
	await _walk_all_routes()
	await _open_hud_screens()
	await _open_settings_twice()
	await _play_all_minigames()
	await _edge_cases()
	_log("Durchlauf fertig")
	quit(0)


func _log(msg: String) -> void:
	print("[BUGHUNT] %s" % msg)


## Frischer Spielstand + Home-Einstieg (wie main.tscn, nur mit eigenem Save).
func _boot_fresh() -> void:
	_gs = root.get_node("/root/GameState")
	_router = root.get_node("/root/SceneRouter")
	_router.min_shown_ms = 80
	_router.travel_finished.connect(func(_t: StringName) -> void: _travel_count += 1)
	var save_path := "user://bughunt_%d.json" % Time.get_ticks_usec()
	_gs.initialize(save_path)
	_entry = (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(_entry)
	await _wait_frames(10)


## Onboarding wie ein Spieler: Name eintippen, alle Weiter-Knöpfe drücken.
func _complete_onboarding() -> void:
	var flow: Node = null
	var deadline := Time.get_ticks_msec() + 10_000
	while flow == null and Time.get_ticks_msec() < deadline:
		flow = _find_by_class(root, "OnboardingFlow")
		await process_frame
	if flow == null:
		_log("FEHLER: Onboarding-Flow nicht gefunden")
		return
	_log("Onboarding: Flow offen")
	(flow.get_node("%NameEdit") as LineEdit).text = "Bughunt"
	await _press(flow.get_node("%WelcomeNext"))
	(flow.get_node("%NicknameEdit") as LineEdit).text = "Testgooby"
	await _press(flow.get_node("%NicknameNext"))
	await _press(flow.get_node("%EditorNext"))
	await _press(flow.get_node("%DoneButton"))
	await _wait_idle(20_000)
	_log("Onboarding fertig — aktuelle Route: %s" % _router.get_current_target())


## Jede registrierte Route einmal anreisen (Stadt, alle Orte, alle Screens).
func _walk_all_routes() -> void:
	var routes: Dictionary = _router.get("_routes")
	var targets: Array[String] = []
	for key: StringName in routes.keys():
		targets.append(String(key))
	targets.sort()
	_log("Routen-Durchlauf: %d Ziele" % targets.size())
	for target in targets:
		if PARAM_ROUTES.has(StringName(target)):
			continue
		await _goto(StringName(target))
		await _settle(0.6)
		var scene: Node = _router.get_current_scene()
		var scene_name: String = scene.name if scene != null else "<null>"
		_log("Route '%s' besucht (Szene: %s)" % [target, scene_name])
	await _goto(&"home")


## HUD-Aktionen wie Spieler-Taps: öffnet Screens/Panels, schließt via Back.
func _open_hud_screens() -> void:
	for action in HUD_ACTIONS:
		await _goto(&"home")
		await _settle(0.4)
		_log("HUD-Aktion '%s'" % action)
		_entry._on_hud_action(action)
		await _settle(1.2)
		await _close_everything()


func _open_settings_twice() -> void:
	_log("Settings öffnen/schließen (2×, schnell)")
	_entry._open_settings()
	_entry._open_settings()
	await _settle(1.0)
	_entry._close_settings()
	_entry._close_settings()
	await _settle(0.5)


## Alle spielbaren Minigames: Pregame → PLAY → Countdown → Zufalls-Bot →
## Pause/Resume → Ende melden → Results → zurück zur Arcade.
func _play_all_minigames() -> void:
	var games := MinigameRegistry.playable()
	_log("Minigame-Durchlauf: %d Spiele" % games.size())
	for game in games:
		var id := str(game["id"])
		_gs.set_value("gooby.stats.energy", 100.0)
		await _goto(&"mg_pregame", {"game_id": id})
		await _settle(0.4)
		var pregame: Node = _router.get_current_scene()
		if pregame == null or not pregame.has_method("_on_play_pressed"):
			_log("FEHLER: Pregame für '%s' fehlt (Szene: %s)" % [id, pregame])
			continue
		var before := _travel_count
		pregame._on_play_pressed()
		await _wait_travel(before, 25_000)
		var host: Node = _router.get_current_scene()
		if host == null or not host is MinigameHost:
			_log("FEHLER: Host für '%s' nicht erreicht" % id)
			continue
		_log("Spiel '%s' gestartet (Countdown läuft)" % id)
		await _settle(3.2)
		await _bot_play(host, PLAY_SEC)
		# Der Bot kann per Zufalls-Tap selbst Quit/Zurück getroffen haben —
		# dann ist der Host schon weg und die Reise läuft bereits.
		if is_instance_valid(host):
			_finish_round(host, id)
			await _settle(0.8)
			await _leave_results(host)
		else:
			await _wait_idle(25_000)
			await _goto(&"arcade")
		_log("Spiel '%s' fertig — Route: %s" % [id, _router.get_current_target()])


func _bot_play(host: Node, seconds: float) -> void:
	var stop_at := Time.get_ticks_msec() + int(seconds * 1000.0)
	var paused := false
	while Time.get_ticks_msec() < stop_at and is_instance_valid(host):
		_send_random_input()
		if not paused and Time.get_ticks_msec() > stop_at - int(seconds * 500.0):
			paused = true
			host._on_pause_pressed()
			await _settle(0.3)
			if not is_instance_valid(host):
				return
			host._on_resume_pressed()
		await _settle(0.08)


## Rundenende über den Spiele-Vertrag (ctx.report_end) — bucht den Award.
func _finish_round(host: Node, id: String) -> void:
	if bool(host.get("_round_over")):
		return
	var game: Node = host.get("_game")
	if game == null or not is_instance_valid(game) or game.get("ctx") == null:
		_log("FEHLER: Spiel '%s' hat kein ctx" % id)
		return
	game.ctx.report_end({"score": _rng.randi_range(0, 400)})


func _leave_results(host: Node) -> void:
	var before := _travel_count
	if not is_instance_valid(host):
		await _wait_idle(25_000)
		return
	var results := _find_by_class(host, "MinigameResults")
	if results != null and results.visible:
		results.back_pressed.emit()
	else:
		host._on_quit_pressed()
	await _wait_travel(before, 20_000)


## Kanten: Doppel-goto, Back-Spam, Quit im Countdown, Reise mitten im Spiel,
## erschöpfter Gooby, unbekannte Spiele, App-Pause/Resume, Back-Geste.
func _edge_cases() -> void:
	_log("Kanten: Doppel-goto (busy-Replace)")
	_router.goto(&"city")
	_router.goto(&"album")
	await _wait_idle(25_000)
	await _settle(0.5)

	_log("Kanten: Back-Spam (5×)")
	for _i in 5:
		_router.handle_back_request()
		await process_frame
	await _wait_idle(25_000)

	_log("Kanten: Quit während Countdown")
	_gs.set_value("gooby.stats.energy", 100.0)
	await _goto(&"mg_host", {"game_id": "teaParty"})
	await _settle(0.4)
	var host: Node = _router.get_current_scene()
	if host is MinigameHost:
		var before := _travel_count
		host._on_quit_pressed()
		await _wait_travel(before, 20_000)

	_log("Kanten: Szenenwechsel mitten im Spiel")
	_gs.set_value("gooby.stats.energy", 100.0)
	await _goto(&"mg_host", {"game_id": "carrotCatch"})
	await _settle(4.0)
	await _goto(&"city")
	await _settle(0.5)

	_log("Kanten: erschöpfter Gooby → Host verweigert")
	_gs.set_value("gooby.stats.energy", 10.0)
	await _goto(&"mg_host", {"game_id": "teaParty"})
	await _wait_idle(25_000)
	_gs.set_value("gooby.stats.energy", 100.0)

	_log("Kanten: unbekanntes Spiel in Pregame/Host")
	await _goto(&"mg_pregame", {"game_id": "gibtsNicht"})
	await _wait_idle(25_000)
	await _goto(&"mg_host", {"game_id": "gibtsNicht"})
	await _wait_idle(25_000)

	_log("Kanten: App-Pause/Resume-Notifications")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await _settle(0.3)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _settle(0.5)

	_log("Kanten: System-Back-Geste während Reise")
	_router.goto(&"home")
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait_idle(25_000)


# ── Helfer ────────────────────────────────────────────────────────────────────


func _goto(target: StringName, params: Dictionary = {}) -> void:
	var before := _travel_count
	_router.goto(target, params)
	await _wait_travel(before, 25_000)


func _wait_travel(before: int, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _travel_count > before and not _router.is_busy():
			return
		await process_frame
	_log("WARNUNG: Reise-Timeout (Route: %s)" % _router.get_current_target())


func _wait_idle(timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if not _router.is_busy():
			return
		await process_frame
	_log("WARNUNG: Router bleibt busy")


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_frames(count: int) -> void:
	for _i in count:
		await process_frame


func _press(button: Node) -> void:
	if button is BaseButton:
		(button as BaseButton).pressed.emit()
	await _wait_frames(8)


## Panels/Overlays schließen und sicher heim: erst Back-Anfragen, dann home.
func _close_everything() -> void:
	for _i in 4:
		_router.handle_back_request()
		await _settle(0.3)
	await _wait_idle(25_000)
	await _goto(&"home")
	await _settle(0.3)


func _find_by_class(node: Node, cls: String) -> Node:
	if node.get_script() != null:
		var script: Script = node.get_script()
		if script.get_global_name() == StringName(cls):
			return node
	for child in node.get_children():
		var found := _find_by_class(child, cls)
		if found != null:
			return found
	return null


## Zufalls-Eingaben: Taps, Drags und Richtungs-/Aktionstasten.
func _send_random_input() -> void:
	var win_size := Vector2(root.size)
	var pos := Vector2(_rng.randf() * win_size.x, _rng.randf() * win_size.y)
	match _rng.randi_range(0, 2):
		0:
			var down := InputEventScreenTouch.new()
			down.index = 0
			down.position = pos
			down.pressed = true
			Input.parse_input_event(down)
			var up := InputEventScreenTouch.new()
			up.index = 0
			up.position = pos + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
			up.pressed = false
			Input.parse_input_event(up)
		1:
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = pos
			drag.relative = Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
			Input.parse_input_event(drag)
		2:
			var keys: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE, KEY_ENTER]
			var key := InputEventKey.new()
			key.keycode = keys[_rng.randi_range(0, keys.size() - 1)]
			key.physical_keycode = key.keycode
			key.pressed = true
			Input.parse_input_event(key)
			var release := InputEventKey.new()
			release.keycode = key.keycode
			release.physical_keycode = key.keycode
			release.pressed = false
			Input.parse_input_event(release)
