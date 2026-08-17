extends TestCase
## FERTIG-1 (EVAL Rang 12) — sichtbare Modifier-Schiene: Pregame-Banner
## (Anzeige VOR dem Start), Arcade-Badge auf der Ziel-Kachel und der Host-
## Vollpfad (Consume beim echten Rundenstart, Federleicht = keine Energie,
## Früh-Abbruch = Refund). Läuft gegen den /root/GameState-Autoload wie die
## anderen Host-Tests (test_ef3_quick_retry-Muster).

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PREGAME_SCENE := "res://scripts/minigames/pregame.tscn"
const ARCADE_SCENE := "res://scripts/minigames/arcade_screen.tscn"


func test_pregame_zeigt_banner_nur_fuer_das_event_spiel() -> void:
	var gs := _gs()
	if gs == null:
		fail_test("GameState-Autoload fehlt")
		return
	_force(gs, "teaParty", "doppelGold")
	var mit := await _mount_pregame("teaParty")
	assert_true(
		mit.find_child("ModifierBanner", true, false) != null,
		"Event-Spiel zeigt das Bonus-Banner vor dem Start"
	)
	await _unmount(mit)
	var ohne := await _mount_pregame("carrotCatch")
	assert_true(
		ohne.find_child("ModifierBanner", true, false) == null, "anderes Spiel bleibt ohne Banner"
	)
	await _unmount(ohne)
	_clear(gs)


func test_arcade_badge_sitzt_auf_der_ziel_kachel() -> void:
	var gs := _gs()
	if gs == null:
		fail_test("GameState-Autoload fehlt")
		return
	_force(gs, "teaParty", "muenzregen")
	var arcade: ArcadeScreen = (load(ARCADE_SCENE) as PackedScene).instantiate()
	arcade.auto_navigate = false
	tree.root.add_child(arcade)
	await wait_frames(2)
	var tile := arcade.find_child("Tile_teaParty", true, false)
	var andere := arcade.find_child("Tile_carrotCatch", true, false)
	assert_true(
		tile != null and tile.find_child("ModifierBadge", true, false) != null,
		"Ziel-Kachel trägt das Bonus-Badge"
	)
	assert_true(
		andere != null and andere.find_child("ModifierBadge", true, false) == null,
		"andere Kacheln bleiben ohne Badge"
	)
	arcade.queue_free()
	await wait_frames(2)
	_clear(gs)


func test_host_konsumiert_federleicht_gratis_und_erstattet_abbruch() -> void:
	var gs := _gs()
	if gs == null:
		fail_test("GameState-Autoload fehlt")
		return
	_set_energy(gs, 100.0)
	_force(gs, "carrotCatch", "federleicht")
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "carrotCatch", "difficulty": "normal", "seed": 42})
	tree.root.add_child(host)
	var aktiv := await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)
	assert_true(aktiv, "Runde startet")
	assert_eq(_plays_left(gs), 2, "echter Rundenstart konsumiert eine Modifier-Runde")
	# Seit dem verkabelten Live-Tick faellt Energie waehrend der Wartezeit ganz
	# normal ein Stueck ab. Geprueft wird deshalb, dass die ENERGIEKOSTEN des
	# Rundenstarts (8) NICHT abgebucht wurden — nicht ein exakter Standwert.
	assert_true(
		float(gs.get_value("gooby.stats.energy", 0.0)) > 100.0 - 4.0,
		"Federleicht: keine Energiekosten abgebucht"
	)
	host._on_quit_pressed()
	await wait_frames(2)
	assert_eq(_plays_left(gs), 3, "Früh-Abbruch erstattet die Runde (einmalig)")
	host.queue_free()
	await wait_frames(2)
	_clear(gs)


func test_host_normalfall_zahlt_energie_ohne_event() -> void:
	var gs := _gs()
	if gs == null:
		fail_test("GameState-Autoload fehlt")
		return
	_clear(gs)
	_set_energy(gs, 100.0)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "carrotCatch", "difficulty": "normal", "seed": 43})
	tree.root.add_child(host)
	var aktiv := await wait_until(
		func() -> bool:
			var game: MinigameBase = host.get("_game")
			return game != null and is_instance_valid(game) and game.is_active(),
		8000
	)
	assert_true(aktiv, "Runde startet")
	assert_true(
		float(gs.get_value("gooby.stats.energy", 0.0)) < 99.5,
		"§C6 bleibt: ohne Event kostet die Runde Energie"
	)
	host.queue_free()
	await wait_frames(2)


## ── Helfer ───────────────────────────────────────────────────────────────


func _gs() -> Node:
	return tree.root.get_node_or_null("/root/GameState")


func _force(gs: Node, game_id: String, type_id: String) -> void:
	var now := int(gs.clock.now_ms())
	gs.update(
		func(state: Dictionary) -> void:
			ModifierEngine.force_event(state, {"gameId": game_id, "type": type_id}, now)
	)


func _clear(gs: Node) -> void:
	gs.update(func(state: Dictionary) -> void: ModifierEngine.clear_event(state))


func _set_energy(gs: Node, value: float) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = value
	)


func _plays_left(gs: Node) -> int:
	var cur: Variant = gs.get_value("modifiers.current")
	if cur is Dictionary:
		return int((cur as Dictionary).get("playsLeft", 0))
	return 0


func _mount_pregame(game_id: String) -> Control:
	var pregame: MinigamePregame = (load(PREGAME_SCENE) as PackedScene).instantiate()
	pregame.auto_navigate = false
	pregame.receive_params({"game_id": game_id})
	tree.root.add_child(pregame)
	await wait_frames(2)
	return pregame


func _unmount(node: Control) -> void:
	node.queue_free()
	await wait_frames(2)
