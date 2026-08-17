extends TestCase
## GOB-NOM-Kernlogik (PURE, Doc G §5): Verlet-Determinismus (Seed → identischer
## State-Hash), Constraint-Stabilität (Seile explodieren nicht), Schnitt-Logik
## (per Id + Swipe-Segment + Budget), Elemente (Blase/Kissen/Ventilator/
## Schiene/Schießer/Wolke/Stacheln), Gläser/Sieg/Niederlage und die
## Coop-Ownership-Gates. Alles headless über die GobnomLogic-API.


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


func _coop_level(extra := {}) -> Dictionary:
	var level := _mini_level(
		{
			"kind": "coop",
			"split": {"axis": "x", "at": 480},
			"ropes":
			[
				{"x": 200, "y": 120, "rest": 80, "owner": "a"},
				{"x": 700, "y": 120, "rest": 80, "owner": "b"},
			],
		}
	)
	level.merge(extra, true)
	return level


func _run_ticks(state: Dictionary, ticks: int) -> Array:
	var events: Array = []
	for _i in ticks:
		events.append_array(GobnomLogic.step(state))
	return events


## ── Determinismus ────────────────────────────────────────────────────────


func test_same_seed_same_inputs_same_hash() -> void:
	var level := _mini_level(
		{"fans": [{"x": 60, "y": 300, "dx": 1, "dy": 0, "force": 120, "turbulence": 0.4}]}
	)
	var hashes: Array = []
	for _round in 2:
		var state := GobnomLogic.new_run(level, _balance(), 42)
		_run_ticks(state, 45)
		GobnomLogic.cut_rope(state, 0)
		_run_ticks(state, 30)
		hashes.append(GobnomLogic.state_hash(state))
	assert_eq(hashes[0], hashes[1], "gleicher Seed + gleiche Inputs → identischer Hash")


func test_different_seed_diverges_with_turbulence() -> void:
	var level := _mini_level(
		{"fans": [{"x": 60, "y": 300, "dx": 1, "dy": 0, "force": 200, "turbulence": 0.5}]}
	)
	var state_a := GobnomLogic.new_run(level, _balance(), 1)
	var state_b := GobnomLogic.new_run(level, _balance(), 2)
	_run_ticks(state_a, 120)
	_run_ticks(state_b, 120)
	assert_ne(
		GobnomLogic.state_hash(state_a),
		GobnomLogic.state_hash(state_b),
		"Turbulenz zieht deterministisch am GoobyRng-Seed"
	)


## ── Constraint-Stabilität ────────────────────────────────────────────────


func test_rope_constraint_stays_stable() -> void:
	var state := GobnomLogic.new_run(_mini_level(), _balance(), 1)
	var anchor := Vector2(480, 120)
	for _i in 600:
		GobnomLogic.step(state)
		var pos := GobnomLogic.candy_pos(state)
		assert_true(is_finite(pos.x) and is_finite(pos.y), "Position bleibt endlich")
		assert_true(anchor.distance_to(pos) <= 80.0 + 1.5, "Seil dehnt sich nie über rest")
	var vel := GobnomLogic.candy_velocity(state)
	assert_true(vel.length() < 100.0, "ausgependelt statt explodiert (v=%s)" % vel)


func test_one_sided_rope_never_pushes() -> void:
	# Bonbon START über dem Anker: das Seil ist locker und darf NICHT drücken.
	var level := _mini_level({"candy": {"x": 480, "y": 80}})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	_run_ticks(state, 5)
	assert_true(GobnomLogic.candy_pos(state).y > 80.0, "lockeres Seil lässt das Bonbon frei fallen")


## ── Schnitt-Logik ────────────────────────────────────────────────────────


func test_cut_rope_and_double_cut() -> void:
	var state := GobnomLogic.new_run(_mini_level(), _balance(), 1)
	assert_false(bool(GobnomLogic.cut_rope(state, 9)["ok"]), "unbekannte Id")
	var first := GobnomLogic.cut_rope(state, 0)
	assert_true(bool(first["ok"]), "Schnitt klappt")
	assert_eq(str(GobnomLogic.cut_rope(state, 0)["reason"]), "already_cut", "kein Doppelschnitt")
	_run_ticks(state, 240)
	assert_eq(str(state["outcome"]), "won", "senkrechter Fall in den Mund = NOM")
	assert_eq(int(state["jars_taken"]), 3, "alle Gläser auf der Fall-Linie")


func test_cut_segment_swipe_hits_crossing_ropes_only() -> void:
	var level := _mini_level(
		{
			"ropes":
			[
				{"x": 480, "y": 120, "rest": 80},
				{"x": 200, "y": 120, "rest": 200},
			]
		}
	)
	var state := GobnomLogic.new_run(level, _balance(), 1)
	var miss := GobnomLogic.cut_segment(state, Vector2(700, 300), Vector2(760, 300))
	assert_eq(miss.size(), 0, "Swipe daneben schneidet nichts")
	# Waagerechter Swipe zwischen Anker (480,120) und Bonbon (~480,200):
	# kreuzt Seil 0 UND das schräge Seil 1 (Anker 200,120) in einem Zug.
	var cut := GobnomLogic.cut_segment(state, Vector2(300, 160), Vector2(560, 160))
	assert_eq(cut.size(), 2, "ein Swipe kappt beide gekreuzten Seile")


func test_cut_budget_is_enforced() -> void:
	var level := _mini_level(
		{
			"max_cuts": 1,
			"ropes":
			[
				{"x": 480, "y": 120, "rest": 80},
				{"x": 200, "y": 120, "rest": 200},
			]
		}
	)
	var state := GobnomLogic.new_run(level, _balance(), 1)
	assert_eq(GobnomLogic.cuts_left(state), 1, "Budget startet bei max_cuts")
	assert_true(bool(GobnomLogic.cut_rope(state, 0)["ok"]), "erster Schnitt frei")
	var second := GobnomLogic.cut_rope(state, 1)
	assert_eq(str(second["reason"]), "cut_limit", "Budget erschöpft")
	assert_eq(GobnomLogic.cuts_left(state), 0, "cuts_left zählt runter")


## ── Gefahren + Sieg ──────────────────────────────────────────────────────


func test_spikes_lose_the_run() -> void:
	var level := _mini_level(
		{"mouth": {"x": 100, "y": 470}, "spikes": [{"x": 430, "y": 320, "w": 100, "h": 30}]}
	)
	var state := GobnomLogic.new_run(level, _balance(), 1)
	GobnomLogic.cut_rope(state, 0)
	var events := _run_ticks(state, 120)
	var kinds: Array = []
	for event: Dictionary in events:
		kinds.append(str(event["kind"]))
	assert_true(kinds.has("spike"), "Stachel-Ereignis gemeldet")
	assert_eq(str(state["outcome"]), "lost", "Stacheln = verloren")


func test_falling_out_of_world_loses() -> void:
	var level := _mini_level({"mouth": {"x": 100, "y": 100}, "jars": []})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	GobnomLogic.cut_rope(state, 0)
	_run_ticks(state, 300)
	assert_eq(str(state["outcome"]), "lost", "aus dem Bild gefallen = verloren")


func test_actions_blocked_after_outcome() -> void:
	var state := GobnomLogic.new_run(_mini_level(), _balance(), 1)
	state["outcome"] = "won"
	assert_eq(str(GobnomLogic.cut_rope(state, 0)["reason"]), "outcome", "kein Nachschneiden")
	assert_eq(GobnomLogic.cut_segment(state, Vector2.ZERO, Vector2(960, 540)).size(), 0)


func test_stars_follow_jars() -> void:
	assert_eq(GobnomLogic.stars_for(0), 0)
	assert_eq(GobnomLogic.stars_for(2), 2)
	assert_eq(GobnomLogic.stars_for(9), 3, "geklemmt auf 3")


## ── Coop-Ownership (Doc G §5.4) ──────────────────────────────────────────


func test_coop_cut_gates_by_owner() -> void:
	var state := GobnomLogic.new_run(_coop_level(), _balance(), 1)
	var wrong := GobnomLogic.cut_rope(state, 1, "a")
	assert_eq(str(wrong["reason"]), "wrong_side", "A darf Bs Anker NICHT schneiden")
	assert_false(bool((state["ropes"] as Array)[1]["cut"]), "Seil blieb dran")
	assert_true(bool(GobnomLogic.cut_rope(state, 1, "b")["ok"]), "B schon")
	assert_true(bool(GobnomLogic.cut_rope(state, 0, "a")["ok"]), "A auf der eigenen Seite")


func test_coop_position_gates_without_owner_tag() -> void:
	# Ohne owner-Tag entscheidet die Bildschirmhälfte des Elements.
	var cushion := {"x": 200, "y": 400, "dx": 0, "dy": -1, "power": 400, "range": 300, "half_w": 60}
	var level := _coop_level({"cushions": [cushion]})
	var state := GobnomLogic.new_run(level, _balance(), 1)
	assert_eq(
		str(GobnomLogic.puff_cushion(state, 0, "b")["reason"]),
		"wrong_side",
		"Kissen steht links → B verweigert"
	)
	assert_true(bool(GobnomLogic.puff_cushion(state, 0, "a")["ok"]), "A darf")


func test_coop_swipe_cut_respects_sides() -> void:
	var state := GobnomLogic.new_run(_coop_level(), _balance(), 1)
	# Ein Swipe von B quer über BEIDE Seile darf nur Bs Seil (Anker rechts)
	# kappen — As Anker bleibt verweigert (denied-Event).
	var cut := GobnomLogic.cut_segment(state, Vector2(100, 160), Vector2(860, 160), "b")
	assert_eq(cut, [1], "nur Bs Seil fällt")
	var denied := 0
	for event: Dictionary in state["events"]:
		if str(event["kind"]) == "denied":
			denied += 1
	assert_true(denied >= 1, "fremder Anker meldet denied")


func test_coop_solo_player_bypasses_gates() -> void:
	var state := GobnomLogic.new_run(_coop_level(), _balance(), 1)
	assert_true(bool(GobnomLogic.cut_rope(state, 1, "solo")["ok"]), "solo testet frei")


func test_side_of_both_axes() -> void:
	var x_state := GobnomLogic.new_run(_coop_level(), _balance(), 1)
	assert_eq(GobnomLogic.side_of(x_state, Vector2(100, 100)), "a")
	assert_eq(GobnomLogic.side_of(x_state, Vector2(800, 100)), "b")
	var y_level := _coop_level({"split": {"axis": "y", "at": 270}})
	var y_state := GobnomLogic.new_run(y_level, _balance(), 1)
	assert_eq(GobnomLogic.side_of(y_state, Vector2(480, 100)), "a")
	assert_eq(GobnomLogic.side_of(y_state, Vector2(480, 400)), "b")
