extends TestCase
## EF-1 (EVAL-1 D4+D5) — Idle-Frequenz + Streichel-Treppe: der Mini-Fund
## kommt etwa alle 90 s und läuft über die VORHANDENE Seelen-Bremse
## (ambient_allowed, 90-s-Mindestabstand); Streicheln klingt in steigender
## Tonhöhe, jeder zehnte Streichler des Tages gibt einen Münz-Bonus.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _seq := 0


class RoomStub:
	extends Node3D
	## Minimaler RoomBase-Ersatz für den GoobyReactions-Runner: GameState,
	## (kein) Gooby, Grid-Feld und ein Sprech-Protokoll.

	var grid: Variant = null
	var gs_ref: Object = null
	var lines: Array = []

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return null

	func say(text: String) -> void:
		lines.append(text)

	func is_build_mode_active() -> bool:
		return false


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://ef1_tests/idle_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


## Runner wie attach_to, aber mit gepinnter Zeit + ohne Visuals VOR setup —
## sonst bucht der Betreten-Moment die Frequenzbremse mit der OS-Uhr.
func _runner(gs: Node) -> Array:
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	return [room, runner]


func test_frequenz_konstanten_bleiben_im_saegezahn() -> void:
	assert_almost(GoobyReactions.FUND_INTERVAL_S, 90.0, 1e-6, "Mini-Fund ~90 s (EVAL-1 D4)")
	assert_true(GoobyReactions.IDLE_TEXT_QUOTE >= 0.7 - 1e-6, "Idle-Texte mindestens 70 %")
	assert_true(GoobyReactions.IDLE_MAX_S <= 90.0, "Idle-Handlung mindestens alle 90 s")
	assert_eq(SoulTriggers.AMBIENT_MIN_GAP_MS, 90_000, "die EINE Seelen-Bremse bleibt bei 90 s")


func test_mini_fund_gibt_muenze_und_respektiert_bremse() -> void:
	var gs := _fresh_gs()
	var pair := _runner(gs)
	var room: RoomStub = pair[0]
	var runner: GoobyReactions = pair[1]
	var coins0 := int(gs.get_value("economy.coins", 0))
	var lines0 := room.lines.size()
	# 90 s nach dem Betreten-Moment (der die Bremse ggf. schon gebucht hat).
	runner.now_ms_override = NOW_MS + 91_000
	runner._run_mini_fund()
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		coins0 + GoobyReactions.MINI_FUND_COINS,
		"Fund gibt die kleine Münze"
	)
	assert_true(room.lines.size() > lines0, "Fund wird kommentiert")
	# 30 s später: die Seelen-Bremse (90-s-Mindestabstand) hält.
	runner.now_ms_override = NOW_MS + 121_000
	runner._run_mini_fund()
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		coins0 + GoobyReactions.MINI_FUND_COINS,
		"innerhalb der Bremse KEIN zweiter Fund"
	)
	# Nach Ablauf des Mindestabstands ist wieder ein Fund erlaubt.
	runner.now_ms_override = NOW_MS + 182_000
	runner._run_mini_fund()
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		coins0 + 2 * GoobyReactions.MINI_FUND_COINS,
		"nach 90 s wieder erlaubt"
	)
	room.queue_free()
	await wait_frames(1)
	gs.free()


func test_streichel_treppe_pur() -> void:
	assert_almost(GoobyReactions.pet_pitch(1), 1.0, 1e-6, "erste Stufe = Grundton")
	assert_true(
		GoobyReactions.pet_pitch(2) > GoobyReactions.pet_pitch(1), "Tonhöhe steigt je Streichler"
	)
	assert_almost(
		GoobyReactions.pet_pitch(10),
		1.0 + GoobyReactions.PET_PITCH_SCHRITT * 9.0,
		1e-6,
		"zehnte Stufe = Spitze"
	)
	assert_almost(GoobyReactions.pet_pitch(11), 1.0, 1e-6, "nach dem Bonus startet die Treppe neu")
	assert_false(GoobyReactions.pet_bonus_due(0))
	assert_false(GoobyReactions.pet_bonus_due(9))
	assert_true(GoobyReactions.pet_bonus_due(10), "jeder zehnte Streichler = Bonus")
	assert_true(GoobyReactions.pet_bonus_due(20))


func test_zehnter_streichler_gibt_bonus() -> void:
	var gs := _fresh_gs()
	var pair := _runner(gs)
	var room: RoomStub = pair[0]
	var runner: GoobyReactions = pair[1]
	var coins0 := int(gs.get_value("economy.coins", 0))
	for _i in 9:
		runner.handle_tap()
	assert_eq(int(gs.get_value("achievements.counters.petsToday", 0)), 9, "neun Streichler")
	assert_eq(int(gs.get_value("economy.coins", 0)), coins0, "noch kein Bonus")
	runner.handle_tap()
	assert_eq(int(gs.get_value("achievements.counters.petsToday", 0)), 10)
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		coins0 + GoobyReactions.PET_BONUS_COINS,
		"der zehnte Streichler gibt den kleinen Bonus"
	)
	room.queue_free()
	await wait_frames(1)
	gs.free()
