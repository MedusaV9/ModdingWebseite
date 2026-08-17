extends TestCase
## W4-P5 (INFRA) — State-Lücken aus dem Coverage-Sweep (Plan §2.4-13):
## save_schema.merge_defaults/default_plot/default_counters,
## save_manager.flush_if_dirty, game_state.is_loaded/import_state und
## moving_box_import.decode_code (CRC-/Format-Härtung direkt an der API).

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SaveManager := preload("res://scripts/state/save_manager.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const MovingBox := preload("res://scripts/state/moving_box_import.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_dir() -> String:
	_seq += 1
	var dir := "user://w4p5_tests/gaps_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


func test_merge_defaults_fuellt_und_erkennt_mismatches() -> void:
	var defaults := {"a": 1, "nested": {"x": 1, "y": 2}, "list": [1, 2]}
	# Fehlende Keys kommen aus den Defaults; unbekannte Keys überleben.
	var res := SaveSchema.merge_defaults(defaults, {"a": 7, "extra": "bleibt"})
	assert_true(res["ok"])
	assert_eq(res["value"]["a"], 7)
	assert_eq(res["value"]["nested"]["x"], 1, "fehlendes nested → Default")
	assert_eq(res["value"]["extra"], "bleibt", "additive Keys überleben (Web-Muster)")
	# null clobbert strukturierte Defaults nie.
	var res_null := SaveSchema.merge_defaults(defaults, {"nested": null, "list": null})
	assert_true(res_null["ok"])
	assert_eq(res_null["value"]["nested"], {"x": 1, "y": 2}, "null → Default bleibt")
	assert_eq(res_null["value"]["list"], [1, 2])
	# Struktur-Mismatch = korrupt (F2-Kontrakt): Dict-Default trifft Array.
	var res_bad := SaveSchema.merge_defaults(defaults, {"nested": [1]})
	assert_false(res_bad["ok"], "Array statt Dict → korrupt")
	assert_true(String(res_bad["error"]).contains("nested"), "Fehlerpfad benennt den Key")
	var res_bad2 := SaveSchema.merge_defaults(defaults, {"list": {"k": 1}})
	assert_false(res_bad2["ok"], "Dict statt Array → korrupt")
	var res_bad3 := SaveSchema.merge_defaults(defaults, {"a": {"k": 1}})
	assert_false(res_bad3["ok"], "Dict statt Skalar → korrupt")
	# Arrays werden verbatim übernommen (kein Element-Merge).
	var res_arr := SaveSchema.merge_defaults(defaults, {"list": [9]})
	assert_true(res_arr["ok"])
	assert_eq(res_arr["value"]["list"], [9])


func test_default_plot_und_counters_form() -> void:
	var plot := SaveSchema.default_plot()
	for key in ["crop", "plantedAt", "progressMin", "wateredUntil", "waterings", "fertilized"]:
		assert_true(plot.has(key), "Plot-Key %s" % key)
	assert_eq(plot["crop"], null, "frisch → kein Crop")
	assert_false(plot["fertilized"])
	var counters := SaveSchema.default_counters()
	for key in ["feeds", "washes", "sleeps", "trips", "tickles", "codesRedeemed"]:
		assert_true(counters.has(key), "Counter-Key %s" % key)
		assert_eq(int(counters[key]), 0, "%s startet bei 0" % key)
	assert_eq(counters["petsDay"], "", "petsDay ist ein Day-String")
	# Frische Factories: Mutation eines Rückgabewerts verseucht den nächsten nicht.
	plot["waterings"] = 99
	assert_eq(int(SaveSchema.default_plot()["waterings"]), 0, "Factory liefert frische Dicts")


func test_flush_if_dirty_nur_bei_dirty() -> void:
	var manager: SaveManager = SaveManager.new()
	manager.save_path = _fresh_dir() + "/save_v5.json"
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	assert_false(manager.flush_if_dirty(state), "sauber → kein Flush")
	assert_false(FileAccess.file_exists(manager.save_path), "nichts geschrieben")
	manager.mark_dirty(1000)
	assert_true(manager.is_dirty())
	state["economy"]["coins"] = 777
	assert_true(manager.flush_if_dirty(state), "dirty → Flush")
	assert_true(FileAccess.file_exists(manager.save_path), "Datei existiert")
	assert_false(manager.is_dirty(), "Flush räumt dirty auf")
	assert_false(manager.flush_if_dirty(state), "zweiter Flush ist No-op")
	var reloaded := manager.load_state(NOW_MS)
	assert_eq(int(reloaded["state"]["economy"]["coins"]), 777, "Inhalt kam an")


func test_game_state_is_loaded_und_import_state() -> void:
	var gs: Node = GameStateScript.new()
	assert_false(gs.is_loaded(), "vor initialize → false")
	var dir := _fresh_dir()
	gs.initialize(dir + "/save_v5.json")
	assert_true(gs.is_loaded(), "nach initialize → true")
	# import_state (Umzugskoffer-Pfad): kompletter Austausch + sofortiger Save.
	var imported := SaveSchema.default_state(NOW_MS)
	imported["economy"]["coins"] = 4242
	imported["meta"]["playerName"] = "Importi"
	var coins_signal := [-1]
	gs.coins_changed.connect(func(c: int) -> void: coins_signal[0] = c)
	gs.import_state(imported)
	assert_eq(int(gs.get_value("economy.coins")), 4242, "State ausgetauscht")
	assert_eq(gs.get_value("meta.playerName"), "Importi")
	assert_eq(coins_signal[0], 4242, "coins_changed feuert beim Import")
	assert_true(
		FileAccess.file_exists(dir + "/save_v5.json"), "import_state saved SOFORT (kein Debounce)"
	)
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(dir + "/save_v5.json"))
	assert_eq(int(json.data["economy"]["coins"]), 4242, "Datei trägt den Import")
	gs.free()


func test_decode_code_roundtrip_und_fehlerfaelle() -> void:
	var state := SaveSchema.default_state(NOW_MS)
	state["economy"]["coins"] = 987
	var code := MovingBox.export_code(state)
	assert_true(code.begins_with("GOOBY5."), "Format-Präfix")
	var ok := MovingBox.decode_code(code)
	assert_true(ok["ok"], "Roundtrip decodiert: " + ok["error"])
	var json := JSON.new()
	assert_eq(json.parse(ok["json"]), OK, "Payload ist JSON")
	assert_eq(int(json.data["economy"]["coins"]), 987, "Inhalt identisch")
	# Fehlerfälle: falsches Präfix, fehlende Teile, kaputte Base64, CRC-Flip.
	assert_false(MovingBox.decode_code("GOOBY4.abc.12345678")["ok"], "falsches Präfix")
	assert_false(MovingBox.decode_code("GOOBY5.nur-zwei-teile")["ok"], "zu wenige Segmente")
	assert_false(MovingBox.decode_code("GOOBY5.!!!!.12345678")["ok"], "kaputte base64url")
	var parts := code.split(".")
	var flipped_crc := "00000000" if parts[2] != "00000000" else "ffffffff"
	var tampered := "%s.%s.%s" % [parts[0], parts[1], flipped_crc]
	var res := MovingBox.decode_code(tampered)
	assert_false(res["ok"], "CRC-Mismatch erkannt")
	assert_true(String(res["error"]).contains("CRC"), "Fehlertext benennt CRC")
