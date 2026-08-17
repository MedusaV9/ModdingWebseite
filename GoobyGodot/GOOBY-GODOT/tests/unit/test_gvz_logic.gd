extends TestCase
## GvZ-Kernlogik (W3b, PURE): Platzierungsregeln, Ökonomie-Invarianten,
## Determinismus (Seed → identischer State-Hash), Sieg/Niederlage samt
## Panik-Gooby, Spezial-Türme (Pust/Knolle/Trampolin/Magnet/Boom), Rüstungen
## und Boss Knurps. Alle Läufe headless über GvzLogic/GvzZombies/GvzCombat.

const ALL_TOWERS := [
	"moehrenschuetze",
	"nutella_sammler",
	"dicker_bert",
	"schnarch_knolle",
	"boom_beere",
	"eis_gooby",
	"doppelmoehre",
	"magnet_gooby",
	"trampolin_gooby",
	"pust_gooby",
	"sternchen_gooby",
	"melonen_meier",
]


## Fake-GameState für GvzProgress (Duck-Typing wie /root/GameState).
class GameStateDouble:
	extends RefCounted
	var state := {}
	var notified: Array = []

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(slice_id: String) -> void:
		notified.append(slice_id)


func _balance() -> Dictionary:
	return GvzData.load_balance(null)


func _mini_level(spawns := [], extra := {}) -> Dictionary:
	var level := {
		"id": 1,
		"lanes": [0, 1, 2, 3, 4],
		"start_nutella": 500,
		"unlock_towers": ALL_TOWERS.duplicate(),
		"spawns": spawns,
		"waves": [],
	}
	level.merge(extra, true)
	return level


func test_placement_rules() -> void:
	var state := GvzLogic.new_run(_mini_level(), _balance())
	assert_eq(int(state["nutella"]), 500, "Start-Nutella aus dem Level")
	var placed := GvzLogic.place_tower(state, "moehrenschuetze", 0, 1)
	assert_true(bool(placed["ok"]), "Platzieren klappt")
	assert_eq(int(state["nutella"]), 400, "Kosten abgezogen")
	assert_eq(str(GvzLogic.place_tower(state, "dicker_bert", 0, 1)["reason"]), "cell_occupied")
	assert_eq(str(GvzLogic.place_tower(state, "moehrenschuetze", 1, 1)["reason"]), "cooldown")
	assert_eq(str(GvzLogic.place_tower(state, "quatschturm", 0, 2)["reason"]), "unknown_tower")
	assert_eq(str(GvzLogic.place_tower(state, "dicker_bert", 7, 0)["reason"]), "lane")
	assert_eq(str(GvzLogic.place_tower(state, "dicker_bert", 0, 9)["reason"]), "col")
	state["nutella"] = 10
	assert_eq(str(GvzLogic.place_tower(state, "dicker_bert", 1, 0)["reason"]), "nutella")
	var locked := GvzLogic.new_run(
		_mini_level([], {"unlock_towers": ["nutella_sammler"]}), _balance()
	)
	assert_eq(str(GvzLogic.place_tower(locked, "moehrenschuetze", 0, 1)["reason"]), "locked")


func test_goldi_needs_code_gate() -> void:
	var state := GvzLogic.new_run(_mini_level(), _balance())
	assert_eq(str(GvzLogic.place_tower(state, "goldi", 0, 0)["reason"]), "code_gate")
	var gilded := GvzLogic.new_run(_mini_level(), _balance(), "normal", 1, {"goldi": true})
	assert_true(bool(GvzLogic.place_tower(gilded, "goldi", 0, 0)["ok"]), "mit Code frei")
	assert_true(GvzLogic.available_towers(gilded).has("goldi"))


func test_economy_never_negative_full_bot_run() -> void:
	var balance := _balance()
	var level := GvzData.level_by_id(GvzData.load_levels(), 1)
	var state := GvzLogic.new_run(level, balance, "normal", 1)
	var max_n := int(balance["economy"]["max_nutella"])
	var min_seen := 999999
	while not GvzLogic.is_over(state) and int(state["tick"]) < GvzBot.MAX_TICKS:
		GvzLogic.tick(state)
		GvzBot.act(state)
		min_seen = mini(min_seen, int(state["nutella"]))
		assert_true(int(state["nutella"]) >= 0, "Nutella nie negativ (t=%d)" % int(state["tick"]))
		if int(state["nutella"]) > max_n:
			fail_test("Nutella über dem Deckel")
			break
	assert_eq(str(state["outcome"]), "won", "L1 gewinnt (Bot-Referenzlauf)")
	assert_true(min_seen >= 0, "Minimum >= 0")


func test_collect_drop_caps_at_max() -> void:
	var state := GvzLogic.new_run(_mini_level(), _balance())
	var max_n := int(state["balance"]["economy"]["max_nutella"])
	state["nutella"] = max_n - 10
	GvzLogic._spawn_drop(state, 0, 0, 25, "sky")
	var drop_id := int((state["drops"] as Array)[0]["id"])
	assert_eq(GvzLogic.collect_drop(state, drop_id), 25, "Betrag gemeldet")
	assert_eq(int(state["nutella"]), max_n, "am Deckel gekappt")
	assert_eq(GvzLogic.collect_drop(state, drop_id), -1, "Doppel-Sammeln unmöglich")


func test_determinism_same_seed_same_hash() -> void:
	# Verglichen wird State-Hash UND Ereignis-Strom: der Endzustand zweier
	# Seeds kann konvergieren (Bot sammelt jeden Klecks sofort), der Weg
	# dahin (Drop-Positionen aus GoobyRng) nicht.
	var balance := _balance()
	var level := GvzData.level_by_id(GvzData.load_levels(), 3)
	var one := GvzLogic.new_run(level, balance, "normal", 7)
	var two := GvzLogic.new_run(level, balance, "normal", 7)
	var other := GvzLogic.new_run(level, balance, "normal", 8)
	var trail_one := PackedStringArray()
	var trail_two := PackedStringArray()
	var trail_other := PackedStringArray()
	for _i in 900:
		trail_one.append(var_to_str(GvzLogic.tick(one)))
		GvzBot.act(one)
		trail_two.append(var_to_str(GvzLogic.tick(two)))
		GvzBot.act(two)
		trail_other.append(var_to_str(GvzLogic.tick(other)))
		GvzBot.act(other)
	assert_eq(GvzLogic.state_hash(one), GvzLogic.state_hash(two), "Seed 7 == Seed 7 (Hash)")
	assert_eq(trail_one, trail_two, "Seed 7 == Seed 7 (Events)")
	assert_ne(trail_one, trail_other, "Seed 7 != Seed 8 (Events)")
	assert_true(int(one["tick"]) == 900 and int(other["tick"]) == 900)


func test_mower_saves_once_then_house_falls() -> void:
	var state := GvzLogic.new_run(
		_mini_level([{"t": 999.0, "lane": 4, "type": "schlurfi"}]), _balance()
	)
	GvzZombies.spawn(state, "schlurfi", 0, 100)
	var mowed := false
	for _i in 40:
		for event: Dictionary in GvzLogic.tick(state):
			if str(event["kind"]) == "mower":
				mowed = true
	assert_true(mowed, "Panik-Gooby löst aus")
	assert_true(bool(state["mowers"][0]["used"]), "verbraucht")
	assert_true((state["zombies"] as Array).is_empty(), "Walze räumt die Reihe")
	assert_eq(str(state["outcome"]), "", "noch kein Verlust")
	for _i in 80:
		GvzLogic.tick(state)
	GvzZombies.spawn(state, "schlurfi", 0, 100)
	for _i in 120:
		GvzLogic.tick(state)
		if GvzLogic.is_over(state):
			break
	assert_eq(str(state["outcome"]), "lost", "zweiter Durchbruch = Niederlage")


func test_win_when_lawn_cleared() -> void:
	# Der Schlurfi läuft die volle Bahn (9200 → Haus, ~950 Ticks) und wird
	# vom Panik-Gooby erledigt — danach ist der Rasen sauber = Sieg.
	var state := GvzLogic.new_run(
		_mini_level([{"t": 0.1, "lane": 2, "type": "schlurfi"}]), _balance()
	)
	for _i in 1400:
		GvzLogic.tick(state)
		if GvzLogic.is_over(state):
			break
	assert_eq(str(state["outcome"]), "won", "alle Spawns tot + kein Boss = Sieg")
	assert_eq(int(state["kills"]), 1)
	assert_eq(int(state["score"]), int(state["balance"]["score"]["kill"]), "Kill-Score")


func test_balloon_flies_over_mower_and_pust_pops() -> void:
	var state := GvzLogic.new_run(
		_mini_level([{"t": 999.0, "lane": 4, "type": "schlurfi"}]), _balance()
	)
	GvzZombies.spawn(state, "ballon", 0, 300)
	for _i in 100:
		GvzLogic.tick(state)
		if GvzLogic.is_over(state):
			break
	assert_eq(str(state["outcome"]), "lost", "Ballon umfliegt den Panik-Gooby")
	assert_false(bool(state["mowers"][0]["used"]), "Walze bleibt liegen")
	var popper := GvzLogic.new_run(_mini_level(), _balance())
	assert_true(bool(GvzLogic.place_tower(popper, "pust_gooby", 1, 0)["ok"]))
	var balloon := GvzZombies.spawn(popper, "ballon", 1, 6000)
	var popped := false
	for _i in 70:
		for event: Dictionary in GvzLogic.tick(popper):
			if str(event["kind"]) == "pop":
				popped = true
	assert_true(popped, "Windstoß poppt den Ballon")
	assert_false(bool(balloon["flying"]), "danach Bodenzombie")


func test_shield_blocks_straight_shots_only() -> void:
	var state := GvzLogic.new_run(_mini_level(), _balance())
	var bouncer := GvzZombies.spawn(state, "tuersteher", 0, 5000)
	var hp := int(bouncer["hp"])
	GvzZombies.damage(state, bouncer, 50, "carrot")
	assert_eq(int(bouncer["hp"]), hp, "Schild blockt Möhren komplett")
	GvzZombies.damage(state, bouncer, 50, "star")
	assert_eq(int(bouncer["hp"]), hp - 50, "Bogenschuss geht vorbei")
	GvzZombies.damage(state, bouncer, 50, "blast")
	assert_eq(int(bouncer["hp"]), hp - 100, "Explosion geht vorbei")
	var magnet_state := GvzLogic.new_run(_mini_level(), _balance())
	assert_true(bool(GvzLogic.place_tower(magnet_state, "magnet_gooby", 0, 2)["ok"]))
	var eimer := GvzZombies.spawn(magnet_state, "eimer", 0, 5000)
	var magnet: Dictionary = magnet_state["towers"][GvzLogic.cell_key(0, 2)]
	assert_true(GvzZombies.magnet_steal(magnet_state, magnet, 4), "Magnet klaut den Eimer")
	assert_eq(int(eimer["armor_hp"]), 0, "Rüstung weg")
	assert_eq(str(eimer["armor"]), "", "dauerhaft")


func test_knolle_trampolin_and_boom() -> void:
	var state := GvzLogic.new_run(_mini_level(), _balance())
	assert_true(bool(GvzLogic.place_tower(state, "schnarch_knolle", 0, 4)["ok"]))
	var knolle: Dictionary = state["towers"][GvzLogic.cell_key(0, 4)]
	knolle["armed_at"] = 0
	var biter := GvzZombies.spawn(state, "schlurfi", 0, 4700)
	GvzZombies.step(state)
	assert_true(bool(biter["dead"]), "scharfe Knolle erledigt den Anbeißer")
	assert_false((state["towers"] as Dictionary).has(GvzLogic.cell_key(0, 4)), "Knolle weg")
	assert_true(bool(GvzLogic.place_tower(state, "trampolin_gooby", 1, 4)["ok"]))
	var jumper := GvzZombies.spawn(state, "schlurfi", 1, 4700)
	GvzZombies.step(state)
	assert_eq(int(jumper["x"]), 8600, "Trampolin katapultiert zurück")
	var boom_state := GvzLogic.new_run(_mini_level(), _balance())
	assert_true(bool(GvzLogic.place_tower(boom_state, "boom_beere", 2, 4)["ok"]))
	var near := GvzZombies.spawn(boom_state, "eimer", 2, 4400)
	var fuse := int(boom_state["balance"]["towers"]["boom_beere"]["fuse_ticks"])
	for _i in fuse + 2:
		GvzLogic.tick(boom_state)
	assert_false(
		(boom_state["towers"] as Dictionary).has(GvzLogic.cell_key(2, 4)), "Beere explodiert"
	)
	assert_true(bool(near["dead"]), "Blast tötet den Eimer trotz Rüstung")


func test_boss_knurps_enter_phases_summon_win() -> void:
	var level := _mini_level(
		[{"t": 999.0, "lane": 4, "type": "schlurfi"}],
		{"boss": {"type": "boss_knurps", "enter_at": 0}}
	)
	var state := GvzLogic.new_run(level, _balance(), "normal", 3)
	GvzLogic.tick(state)
	var boss: Dictionary = state["boss"]
	assert_false(boss.is_empty(), "Boss fährt vor")
	assert_eq(int(boss["phase"]), 1)
	var third := int(boss["max_hp"]) / 3
	GvzZombies.damage_boss(state, int(boss["hp"]) - third)
	var summoned := false
	var phase3 := false
	for _i in 400:
		for event: Dictionary in GvzLogic.tick(state):
			match str(event["kind"]):
				"boss_summon":
					summoned = true
				"boss_phase":
					phase3 = int(event["phase"]) == 3
		if summoned and phase3:
			break
	assert_true(phase3, "letztes Drittel = Phase 3")
	assert_true(summoned, "Boss ruft Verstärkung")
	assert_true((state["zombies"] as Array).size() > 0, "Beschwörungen stehen")
	GvzZombies.damage_boss(state, 999999)
	GvzLogic.tick(state)
	assert_eq(str(state["outcome"]), "won", "Boss tot = Sieg (Reste egal)")


func test_conveyor_items_are_free() -> void:
	var level := _mini_level(
		[{"t": 999.0, "lane": 4, "type": "schlurfi"}],
		{
			"mods": {"conveyor": true, "conveyor_hybrid": true},
			"conveyor":
			{"start_delay_ticks": 2, "interval_ticks": 10, "max_queue": 3, "pool": ["eis_gooby"]},
		}
	)
	var state := GvzLogic.new_run(level, _balance())
	state["nutella"] = 0
	for _i in 5:
		GvzLogic.tick(state)
	assert_true((state["conveyor"]["queue"] as Array).has("eis_gooby"), "Band liefert")
	var placed := GvzLogic.place_tower(state, "eis_gooby", 0, 3)
	assert_true(bool(placed["ok"]), "Band-Item trotz 0 Nutella setzbar")
	assert_eq(int(state["nutella"]), 0, "gratis")
	assert_eq(GvzLogic.cooldown_left(state, "eis_gooby"), 0, "cooldown-frei")
	assert_true((state["conveyor"]["queue"] as Array).is_empty(), "aus der Queue entnommen")


func test_progress_stars_score_and_slice() -> void:
	assert_eq(GvzProgress.stars_for(0), 3)
	assert_eq(GvzProgress.stars_for(1), 2)
	assert_eq(GvzProgress.stars_for(4), 1)
	var balance := _balance()
	var total := GvzProgress.final_score(20, 5, 3, true, balance)
	var score: Dictionary = balance["score"]
	var want := 20 + 3 * int(score["star_bonus"]) + 5 * int(score["level_bonus"])
	want += int(score["first_clear_bonus"])
	assert_eq(total, want, "Coin-Row-würdiger Gesamt-Score")
	var gs := GameStateDouble.new()
	var first := GvzProgress.record_win(gs, 3, 2, 120)
	assert_true(bool(first["first_clear"]), "Erst-Abschluss erkannt")
	assert_eq(GvzProgress.level_stars(gs, 3), 2)
	assert_true(GvzProgress.is_cleared(gs, 3))
	assert_eq(GvzProgress.max_unlocked(gs), 1, "L1 zuerst nicht übersprungen")
	var again := GvzProgress.record_win(gs, 3, 1, 90)
	assert_false(bool(again["first_clear"]))
	assert_false(bool(again["new_best"]))
	assert_eq(GvzProgress.level_stars(gs, 3), 2, "Sterne fallen nie")
	assert_eq(int(gs.get_value("gvz.best.3", 0)), 120, "Best bleibt")
	assert_true(gs.notified.has("gvz"), "Slice-Change gemeldet")
