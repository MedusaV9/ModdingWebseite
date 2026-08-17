extends TestCase
## RW-7 — Dev-Menü-Aktionen (Doc §5.2/§5.3): dev.touched-Markierung ueber den
## additiven Slice, Snapshot VOR jeder Mutation, Clamps, Redaktion des
## Netzwerk-Logs und der Zeit/Wetter-Override per Duck-Typing.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rw7_tests/dev_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _cleanup(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(DevActions.SLICE_ID)


func test_gold_setzen_markiert_und_clampt() -> void:
	var gs := _fresh_gs()
	assert_false(DevActions.is_touched(gs), "frischer Save ist unmarkiert")
	var wert := DevActions.set_gold(gs, 5000, NOW_MS)
	assert_eq(wert, 5000)
	assert_eq(int(gs.get_value("economy.coins")), 5000)
	assert_true(DevActions.is_touched(gs), "dev.touched nach der Aktion")
	assert_eq(int(gs.get_value("dev.touchedAt")), NOW_MS)
	assert_eq(DevActions.set_gold(gs, -50, NOW_MS), 0, "Clamp nach unten")
	assert_eq(DevActions.set_gold(gs, 999_999_999, NOW_MS), DevActions.GOLD_MAX, "Clamp nach oben")
	_cleanup(gs)


func test_level_setzen_clampt_auf_max_level() -> void:
	var gs := _fresh_gs()
	assert_eq(DevActions.set_level(gs, 12, NOW_MS), 12)
	assert_eq(int(gs.get_value("progression.level")), 12)
	assert_eq(int(gs.get_value("progression.xp")), 0)
	assert_eq(DevActions.set_level(gs, 999, NOW_MS), Leveling.MAX_LEVEL)
	assert_eq(DevActions.set_level(gs, 0, NOW_MS), 1)
	_cleanup(gs)


func test_snapshot_vor_mutation_und_pruning() -> void:
	var gs := _fresh_gs()
	var path := DevActions.snapshot(gs, "test", NOW_MS)
	assert_false(path.is_empty(), "Snapshot geschrieben")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(raw is Dictionary)
	if raw is Dictionary:
		assert_true((raw as Dictionary).has("sha256"), "Hash liegt bei")
		assert_true((raw as Dictionary).has("v"), "Schema-Version liegt bei")
		var digest := DevActions.hash_of(JSON.stringify((raw as Dictionary)["state"]))
		assert_eq(str((raw as Dictionary)["sha256"]), digest, "SHA-256 passt zum Inhalt")
	_cleanup(gs)


func test_sticker_freischalten() -> void:
	var gs := _fresh_gs()
	var n := DevActions.unlock_all_stickers(gs, NOW_MS)
	assert_true(n > 0, "Katalog hat Sticker")
	var unlocked: Variant = gs.get_value("stickers.unlocked", {})
	assert_true(unlocked is Dictionary)
	if unlocked is Dictionary:
		assert_eq((unlocked as Dictionary).size(), n, "alle Sticker freigeschaltet")
	assert_true(DevActions.is_touched(gs))
	_cleanup(gs)


func test_pferd_spawnen_mit_allowlist() -> void:
	var gs := _fresh_gs()
	var ok := DevActions.spawn_horse(gs, "Testpferd", "lila", NOW_MS)
	assert_true(ok, "Spawn klappt (unbekannte Farbe faellt auf braun)")
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {})
	assert_true(pferde is Dictionary)
	if pferde is Dictionary:
		assert_eq((pferde as Dictionary).size(), 1)
		var pferd: Dictionary = (pferde as Dictionary).values()[0]
		assert_eq(str(pferd.get("farbe", pferd.get("fellfarbe", "braun"))), "braun")
	assert_true(DevActions.is_touched(gs))
	_cleanup(gs)


func test_quest_warte_verkuerzen() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(s: Dictionary) -> void:
			s["ranch"] = {
				"quests":
				{
					"aktiv":
					{
						"haupt_01": {"status": "wartend", "bereitAt": NOW_MS + 3_600_000},
						"haupt_02": {"status": "aktiv", "zielIndex": 0},
					}
				}
			}
	)
	var n := DevActions.quest_warte_verkuerzen(gs, NOW_MS)
	assert_eq(n, 1, "nur Laeufe mit bereitAt werden verkuerzt")
	assert_eq(
		int(gs.get_value("ranch.quests.aktiv.haupt_01.bereitAt")),
		NOW_MS + 10_000,
		"Timer steht auf 10 s ab jetzt"
	)
	_cleanup(gs)


func test_touched_ueberlebt_speichern_und_laden() -> void:
	_seq += 1
	var dir := "user://rw7_tests/dev_reload_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/save_v5.json"
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(path)
	DevActions.set_gold(gs, 777, NOW_MS)
	var manager: Variant = gs.get("_manager")
	manager.flush_if_dirty(gs.state())
	gs.free()
	# Neu laden — Slice ist (wie im echten Boot mit aktivem Dev-Modus)
	# registriert, die Markierung bleibt erhalten.
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	DevActions.ensure_slice(gs2)
	gs2.initialize(path)
	assert_true(DevActions.is_touched(gs2), "dev.touched ueberlebt den Reload")
	gs2.free()
	SaveSchema.unregister_slice(DevActions.SLICE_ID)


func test_redaktion_entfernt_geheimnisse() -> void:
	var redacted: Variant = (
		DevActions
		. redact(
			{
				"sessionId": "geheim",
				"deviceSecret": "geheim",
				"authToken": "geheim",
				"text": "privater Chat",
				"liste": [{"password": "x", "score": 12}],
				"score": 42,
			}
		)
	)
	assert_true(redacted is Dictionary)
	var dict: Dictionary = redacted
	assert_eq(str(dict["sessionId"]), "[redigiert]")
	assert_eq(str(dict["deviceSecret"]), "[redigiert]")
	assert_eq(str(dict["authToken"]), "[redigiert]")
	assert_eq(str(dict["text"]), "[redigiert]")
	assert_eq(str(dict["liste"][0]["password"]), "[redigiert]")
	assert_eq(int(dict["liste"][0]["score"]), 12, "harmlose Werte bleiben")
	assert_eq(int(dict["score"]), 42)


func test_zeit_wetter_override_per_ducktyping() -> void:
	var szene := Node.new()
	var controller := _fake_wetter_controller()
	szene.add_child(controller)
	var touched := DevActions.apply_time_weather(szene, 21.5, "regen")
	assert_eq(touched, 2, "stunde_override + wetter_override getroffen")
	assert_almost(float(controller.get("stunde_override")), 21.5, 0.001)
	assert_eq(str(controller.get("wetter_override")), "regen")
	DevActions.apply_time_weather(szene, -1.0, "")
	assert_almost(float(controller.get("stunde_override")), -1.0, 0.001, "zurueck zur Simulation")
	szene.free()


func _fake_wetter_controller() -> Node:
	var script := GDScript.new()
	script.source_code = ('extends Node\nvar stunde_override := -1.0\nvar wetter_override := ""\n')
	script.reload()
	var node: Node = script.new()
	return node
