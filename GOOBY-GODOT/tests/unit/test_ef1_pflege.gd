extends TestCase
## EF-1 (EVAL-1 D6) — Pflege zählt und feuert Sticker: mark_washed
## inkrementiert den vorher NIRGENDS gezählten washes-Counter und stößt die
## achievements-Auswertung an — squeakyClean wird ohne offenes Album frei.
## Zähneputzen zählt weiter teeth_brushed (bestehender Pfad, abgesichert).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://ef1_tests/pflege_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_mark_washed_zaehlt_und_unlockt_sofort() -> void:
	var gs := _fresh_gs()
	var catalog := [
		{"id": "squeakyClean", "cond": {"type": "counter", "key": "washes", "count": 1}},
		{"id": "cleanMachine", "cond": {"type": "counter", "key": "washes", "count": 3}},
	]
	var service := StickerUnlocks.new()
	var unlocked: Array = []
	service.sticker_unlocked.connect(
		func(def: Dictionary) -> void: unlocked.append(str(def.get("id", "")))
	)
	service.attach(gs, catalog)
	assert_eq(int(gs.get_value("achievements.counters.washes", 0)), 0, "frisch = 0")
	BadState.mark_washed(gs)
	assert_eq(int(gs.get_value("achievements.counters.washes", 0)), 1, "Dusche zählt washes")
	assert_eq(unlocked, ["squeakyClean"], "Sticker feuert SOFORT nach der Pflegehandlung")
	BadState.mark_washed(gs)
	BadState.mark_washed(gs)
	assert_eq(int(gs.get_value("achievements.counters.washes", 0)), 3)
	assert_eq(unlocked, ["squeakyClean", "cleanMachine"], "Stufen-Sticker folgt")
	service.free()
	gs.free()


func test_mark_brushed_zaehlt_weiter() -> void:
	var gs := _fresh_gs()
	BadState.mark_brushed(gs, false)
	assert_eq(int(gs.get_value("achievements.counters.teeth_brushed", 0)), 1, "Zähneputzen zählt")
	assert_false(bool(gs.get_value("bad.needsBrushing", true)), "Pflicht erledigt")
	BadState.mark_brushed(gs, true)
	assert_eq(int(gs.get_value("bad.brushBrokenCount", 0)), 1, "Bürsten-Bruch gezählt")
	gs.free()
