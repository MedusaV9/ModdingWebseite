extends TestCase
## GOB-NOM-Elemente (PURE, Doc G §5.2): Blase (fangen/tragen/platzen),
## Luftkissen (Strahl/Ladungen/Cooldown), Ventilator (Wind/Toggle),
## Schiebe-Anker (Schiene/Klemmen), Auto-Seil-Schießer (einmalig, schneidbar)
## und Zuckerwatte-Wolke (Fall-Bremse). Kern-Sim/Coop testet
## test_gobnom_logic.gd — hier NUR das Element-Verhalten.


func _balance() -> Dictionary:
	return GobnomData.load_balance(null)


## Minimal-Level: Bonbon senkrecht am Seil, Mund direkt darunter.
func _mini_level(extra := {}) -> Dictionary:
	var level := {
		"id": 1,
		"candy": {"x": 480, "y": 200},
		"mouth": {"x": 480, "y": 470},
		"ropes": [{"x": 480, "y": 120, "rest": 80}],
		"jars": [{"x": 480, "y": 300}, {"x": 480, "y": 360}, {"x": 480, "y": 420}],
	}
	level.merge(extra, true)
	return level


func _run_ticks(state: Dictionary, ticks: int) -> Array:
	var events: Array = []
	for _i in ticks:
		events.append_array(GobnomLogic.step(state))
	return events


func _cushion_row(x: float, extra := {}) -> Dictionary:
	var row := {"x": x, "y": 400.0, "dx": 0, "dy": -1, "power": 500, "range": 300, "half_w": 60}
	row.merge(extra, true)
	return row


func test_bubble_catches_lifts_and_pops() -> void:
	var level := _mini_level({"bubbles": [{"x": 480, "y": 330, "r": 26}]})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	GobnomLogic.cut_rope(state, 0)
	var caught := false
	for _i in 90:
		for event: Dictionary in GobnomLogic.step(state):
			caught = caught or str(event["kind"]) == "catch"
		if caught:
			break
	assert_true(caught, "Blase fängt das fallende Bonbon")
	# Der Fang übernimmt den Restschwung: erst Dip nach unten, dann Aufstieg.
	var rising := false
	for _i in 300:
		GobnomLogic.step(state)
		if GobnomLogic.candy_velocity(state).y < -50.0:
			rising = true
			break
	assert_true(rising, "Blase trägt nach OBEN")
	assert_true(bool(GobnomLogic.pop_bubble(state, 0)["ok"]), "Antippen platzt")
	assert_false(bool(state["in_bubble"]), "Bonbon wieder frei")
	assert_eq(str(GobnomLogic.pop_bubble(state, 0)["reason"]), "unknown", "weg ist weg")


func test_cushion_beam_charges_and_cooldown() -> void:
	var level := _mini_level({"cushions": [_cushion_row(480.0, {"charges": 2})]})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	var puff := GobnomLogic.puff_cushion(state, 0)
	assert_true(bool(puff["ok"]) and bool(puff["hit"]), "Bonbon im Strahl → Treffer")
	assert_true(GobnomLogic.candy_velocity(state).y < -300.0, "Luftstoß wirkt nach oben")
	assert_eq(str(GobnomLogic.puff_cushion(state, 0)["reason"]), "cooldown", "Cooldown greift")
	state["tick"] = int(state["tick"]) + 100
	assert_true(bool(GobnomLogic.puff_cushion(state, 0)["ok"]), "nach dem Cooldown wieder frei")
	state["tick"] = int(state["tick"]) + 100
	assert_eq(str(GobnomLogic.puff_cushion(state, 0)["reason"]), "empty", "Ladungen sind endlich")


func test_cushion_misses_outside_beam() -> void:
	var level := _mini_level({"cushions": [_cushion_row(60.0, {"half_w": 40, "charges": -1})]})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	var puff := GobnomLogic.puff_cushion(state, 0)
	assert_true(bool(puff["ok"]), "Puff verbraucht sich auch daneben")
	assert_false(bool(puff["hit"]), "Bonbon außerhalb des Strahls → kein Impuls")


func test_fan_pushes_and_toggles() -> void:
	var level := _mini_level(
		{"fans": [{"x": 60, "y": 200, "dx": 1, "dy": 0, "force": 300, "toggleable": true}]}
	)
	var state := GobnomLogic.new_run(level, _balance(), 1)
	_run_ticks(state, 30)
	assert_true(GobnomLogic.candy_pos(state).x > 481.0, "Wind schiebt das Bonbon")
	assert_true(bool(GobnomLogic.toggle_fan(state, 0)["ok"]), "schaltbar")
	assert_false(bool((state["fans"] as Array)[0]["on"]), "Ventilator ist aus")
	var fixed := _mini_level({"fans": [{"x": 60, "y": 200, "dx": 1, "dy": 0, "force": 100}]})
	var state2 := GobnomLogic.new_run(fixed, _balance(), 1)
	assert_eq(str(GobnomLogic.toggle_fan(state2, 0)["reason"]), "fixed", "fixe Fans sind tabu")


func test_slider_rail_clamps_and_moves_anchor() -> void:
	var rail := {"x1": 200, "y1": 90, "x2": 600, "y2": 90, "t": 0.0}
	var level := _mini_level(
		{
			"ropes": [{"x": 200, "y": 90, "rest": 90, "rail": rail}],
			"candy": {"x": 200, "y": 180},
		}
	)
	var state := GobnomLogic.new_run(level, _balance(), 1)
	assert_true(bool(GobnomLogic.move_anchor(state, 0, 2.0)["ok"]), "slide klappt")
	var rope: Dictionary = (state["ropes"] as Array)[0]
	assert_eq(Vector2(rope["anchor"]), Vector2(600, 90), "t wird auf 0..1 geklemmt")
	assert_eq(str(GobnomLogic.move_anchor(state, 7, 0.5)["reason"]), "no_rail", "ohne Schiene nix")


func test_shooter_fires_once_and_rope_is_cuttable() -> void:
	var level := _mini_level({"shooters": [{"x": 560, "y": 330, "r": 110}]})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	GobnomLogic.cut_rope(state, 0)
	var shot := false
	for _i in 120:
		for event: Dictionary in GobnomLogic.step(state):
			shot = shot or str(event["kind"]) == "shoot"
		if shot:
			break
	assert_true(shot, "Schießer feuert, sobald das Bonbon im Radius ist")
	assert_eq((state["ropes"] as Array).size(), 2, "neues Seil hängt")
	assert_true(bool(GobnomLogic.cut_rope(state, 100)["ok"]), "Schießer-Seil ist schneidbar")
	assert_true(bool((state["shooters"] as Array)[0]["fired"]), "feuert nur EINMAL")


func test_cloud_damps_the_fall() -> void:
	var free_level := _mini_level({"mouth": {"x": 100, "y": 470}, "jars": []})
	var cloud_level := _mini_level(
		{
			"mouth": {"x": 100, "y": 470},
			"jars": [],
			"clouds": [{"x": 380, "y": 250, "w": 200, "h": 200}],
		}
	)
	var free_state := GobnomLogic.new_run(free_level, _balance(), 1)
	var cloud_state := GobnomLogic.new_run(cloud_level, _balance(), 1)
	GobnomLogic.cut_rope(free_state, 0)
	GobnomLogic.cut_rope(cloud_state, 0)
	_run_ticks(free_state, 40)
	_run_ticks(cloud_state, 40)
	assert_true(
		GobnomLogic.candy_pos(cloud_state).y < GobnomLogic.candy_pos(free_state).y - 20.0,
		"Zuckerwatte bremst den Fall deutlich"
	)
