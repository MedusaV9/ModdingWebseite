extends TestCase
## W1d — Umzugskoffer (moving_box_import.gd): roher Alt-App-JSON (happy),
## GOOBY5-Roundtrip (Godot↔Godot) und Junk-Eingaben.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MovingBox := preload("res://scripts/state/moving_box_import.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")

const NOW_MS := 1768478400000


func test_raw_v4_json_import_happy_path() -> void:
	# Exakt das, was der Dev-Panel-Export der Alt-App in die Zwischenablage
	# legt: der komplette v4-Save als roher JSON-String.
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/v4_midgame.json")
	var res := MovingBox.import_text(raw, NOW_MS)
	assert_true(res["ok"], res["error"])
	assert_eq(res["state"]["v"], 5)
	assert_eq(res["state"]["progression"]["level"], 12)
	assert_eq(res["state"]["economy"]["coins"], 4210 + 250 + 180)
	assert_eq(res["report"]["importedFrom"], "web-v4")
	assert_eq(res["report"]["stickers"], 20)


func test_raw_json_with_surrounding_whitespace() -> void:
	var raw := "\n  " + FileAccess.get_file_as_string("res://tests/fixtures/v4_fresh.json") + "  \n"
	assert_true(MovingBox.import_text(raw, NOW_MS)["ok"], "Zwischenablage-Whitespace toleriert")


func test_gooby5_code_roundtrip() -> void:
	var state := SaveSchema.default_state(NOW_MS)
	state["economy"]["coins"] = 1234
	state["meta"]["playerName"] = "Testi"
	var code := MovingBox.export_code(state)
	assert_true(code.begins_with("GOOBY5."), "Format-Prefix")
	assert_eq(code.split(".").size(), 3, "PREFIX.payload.crc32")
	var res := MovingBox.import_text(code, NOW_MS)
	assert_true(res["ok"], res["error"])
	# Numerisch tolerant: der Code transportiert JSON (int → float).
	var diff := Util.first_diff(res["state"], state)
	assert_true(diff.is_empty(), "Godot→Godot-Transfer verlustfrei: " + diff)
	assert_eq(res["report"]["importedFrom"], "godot-v5")


func test_gooby5_crc_mismatch_rejected() -> void:
	var code := MovingBox.export_code(SaveSchema.default_state(NOW_MS))
	var parts := code.split(".")
	var tampered := "%s.%s.%s" % [parts[0], parts[1], "00000000"]
	var res := MovingBox.import_text(tampered, NOW_MS)
	assert_false(res["ok"])
	assert_true(res["error"].contains("CRC"), res["error"])


func test_gooby5_tampered_payload_rejected() -> void:
	var code := MovingBox.export_code(SaveSchema.default_state(NOW_MS))
	var parts := code.split(".")
	var payload := parts[1]
	# Ein Zeichen in der Mitte kippen → CRC muss es fangen.
	var mid := int(payload.length() / 2.0)
	var flipped := "B" if payload[mid] != "B" else "C"
	var tampered_payload := payload.substr(0, mid) + flipped + payload.substr(mid + 1)
	var res := MovingBox.import_text("%s.%s.%s" % [parts[0], tampered_payload, parts[2]], NOW_MS)
	assert_false(res["ok"], "getauschtes Byte erkannt")


func test_junk_inputs() -> void:
	assert_false(MovingBox.import_text("", NOW_MS)["ok"], "leer")
	assert_false(MovingBox.import_text("   \n ", NOW_MS)["ok"], "nur Whitespace")
	assert_false(MovingBox.import_text("hallo welt", NOW_MS)["ok"], "kein JSON")
	assert_false(MovingBox.import_text("[1,2,3]", NOW_MS)["ok"], "JSON, aber kein Objekt")
	assert_false(MovingBox.import_text("GOOBY5.abc", NOW_MS)["ok"], "zu wenige Teile")
	assert_false(MovingBox.import_text("GOOBY5.!!!!.deadbeef", NOW_MS)["ok"], "kaputtes base64")
	assert_false(MovingBox.import_text('{"v": 7}', NOW_MS)["ok"], "Forward-Version")
	assert_false(MovingBox.import_text('{"v": 3, "coins": {}}', NOW_MS)["ok"], "korrupte Typen")


func test_crc32_known_vector() -> void:
	# IEEE-CRC32("123456789") == 0xCBF43926 (der Standard-Testvektor).
	assert_eq(MovingBox.crc32("123456789".to_utf8_buffer()), 0xCBF43926)
