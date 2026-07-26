extends SceneTree
## BUGHUNT-Zustands-Fuzzer (KEIN Test): lädt Spielstände mit Extremwerten und
## kaputten Slices (0 Münzen, Level 40, volles Lager, alle Sticker, mitten im
## Urlaub, schlafend mit überfälligem Wecker, Zeitsprünge, Teil-Korruption)
## und fährt danach die Kern-Screens ab. Jede Godot-Fehlerausgabe des Laufs
## ist ein Fund:
##   godot --headless --path GOOBY-GODOT \
##     --script res://tests/tools/bughunt_fuzz.gd 2>&1 | tee fuzz.log

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SCREEN_ROUTES: Array[StringName] = [
	&"home", &"arcade", &"album", &"city", &"social", &"wardrobe", &"ikea"
]

var _router: Node
var _gs: Node
var _entry: Node
var _travel_count := 0
var _case_name := ""


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("[FUZZ] Start")
	await _boot()
	for case_data in _build_cases():
		_case_name = str(case_data["name"])
		print("[FUZZ] === Fall '%s' ===" % _case_name)
		_load_case(case_data)
		await _visit_screens()
		print("[FUZZ] Fall '%s' fertig" % _case_name)
	await _raw_file_cases()
	print("[FUZZ] Fertig")
	quit(0)


func _boot() -> void:
	_gs = root.get_node("/root/GameState")
	_router = root.get_node("/root/SceneRouter")
	_router.min_shown_ms = 50
	_router.travel_finished.connect(func(_t: StringName) -> void: _travel_count += 1)
	# Onboarding überspringen: der erste Save ist schon "fertig".
	var boot_save := _base_state()
	_write_save("user://fuzz_boot.json", boot_save)
	_gs.initialize("user://fuzz_boot.json")
	_entry = (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(_entry)
	await _settle(2.0)
	await _wait_idle()


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _base_state() -> Dictionary:
	_gs = root.get_node("/root/GameState")
	_gs.register_default_slices()
	var s := SaveSchema.default_state(_now_ms())
	s["onboarding"]["done"] = true
	return s


func _build_cases() -> Array[Dictionary]:
	var now := _now_ms()
	var cases: Array[Dictionary] = []

	var zero := _base_state()
	zero["economy"]["coins"] = 0
	for k in ["hunger", "energy", "hygiene", "fun"]:
		zero["gooby"]["stats"][k] = 0.0
	zero["inventory"]["food"] = {}
	zero["home"]["storage"] = []
	cases.append({"name": "alles_null", "state": zero})

	var maxed := _base_state()
	maxed["economy"]["coins"] = 999_999_999
	maxed["progression"]["level"] = 40
	maxed["progression"]["xp"] = 999_999.0
	for i in 300:
		var item := "bedSingle" if i % 3 == 0 else ("loungeSofa" if i % 3 == 1 else "chair")
		maxed["home"]["storage"].append({"item": item, "uid": "fz%d" % i})
	for i in 500:
		maxed["stickers"]["unlocked"]["sticker_%d" % i] = 1
		maxed["stickers"]["seen"]["sticker_%d" % i] = true
	cases.append({"name": "alles_voll", "state": maxed})

	var negativ := _base_state()
	negativ["economy"]["coins"] = -5000
	negativ["progression"]["level"] = -3
	negativ["progression"]["xp"] = -100.0
	for k in ["hunger", "energy", "hygiene", "fun"]:
		negativ["gooby"]["stats"][k] = -50.0
	negativ["gooby"]["weight"] = 900.0
	cases.append({"name": "negativ", "state": negativ})

	var vac := _base_state()
	vac["vacation"] = {
		"phase": "away",
		"destId": "strand",
		"startedAt": now - 3600_000,
		"returnAt": now + 86_400_000,
		"postcards": 1,
	}
	cases.append({"name": "mitten_im_urlaub", "state": vac})

	var schlaf := _base_state()
	schlaf["gooby"]["sleep"] = {
		"sleeping": true, "startedAt": now - 7_200_000, "wakeAt": now - 3_600_000
	}
	schlaf["gooby"]["lastTickAt"] = now - 7_200_000
	cases.append({"name": "wecker_ueberfaellig", "state": schlaf})

	var zurueck := _base_state()
	zurueck["gooby"]["lastTickAt"] = now - 30 * 86_400_000
	zurueck["garden"]["lastTickAt"] = now - 30 * 86_400_000
	cases.append({"name": "30_tage_weg", "state": zurueck})

	var vor := _base_state()
	vor["gooby"]["lastTickAt"] = now + 10 * 86_400_000
	vor["meta"]["createdAt"] = now + 10 * 86_400_000
	cases.append({"name": "uhr_zurueckgestellt", "state": vor})

	var kaputt := _base_state()
	kaputt["home"]["storage"] = [
		{"item": "gibtsNicht", "uid": "x1"},
		{"kein_item": true},
		"nur_ein_string",
		{"item": "bedSingle", "uid": "x2"},
	]
	kaputt["stickers"]["unlocked"] = {"": 1, "🦄": "ja"}
	kaputt["minigames"]["legacy"]["best"] = {"teaParty": "hundert"}
	kaputt["minigames"]["difficulty"] = {"teaParty": 42}
	cases.append({"name": "kaputte_teilwerte", "state": kaputt})

	return cases


func _load_case(case_data: Dictionary) -> void:
	var path := "user://fuzz_%s.json" % case_data["name"]
	_write_save(path, case_data["state"])
	_gs.initialize(path)


## Rohdatei-Fälle: Teil-Korruption + Recovery über Backups.
func _raw_file_cases() -> void:
	print("[FUZZ] === Fall 'save_abgeschnitten' ===")
	_write_raw("user://fuzz_trunc.json", '{"v":5,"meta":{"createdAt":123')
	_gs.initialize("user://fuzz_trunc.json")
	await _visit_screens()

	print("[FUZZ] === Fall 'save_zukunftsversion' ===")
	_write_raw("user://fuzz_v99.json", '{"v":99}')
	_gs.initialize("user://fuzz_v99.json")
	await _visit_screens()

	print("[FUZZ] === Fall 'recovery_aus_backup' ===")
	var good := _base_state()
	good["economy"]["coins"] = 777
	_write_save("user://fuzz_rec.json.bak1", good)
	_write_raw("user://fuzz_rec.json", "kein json {")
	_gs.initialize("user://fuzz_rec.json")
	var coins := int(_gs.get_value("economy.coins", -1))
	print("[FUZZ] Recovery-Coins: %d (777 = aus Backup)" % coins)
	await _visit_screens()


func _visit_screens() -> void:
	WardrobeScreen.register_routes()
	IkeaScreen.register_routes()
	for route in SCREEN_ROUTES:
		await _goto(route)
		await _settle(0.4)
	_entry._open_settings()
	await _settle(0.5)
	_entry._close_settings()
	await _goto(&"home")


func _write_save(path: String, state: Dictionary) -> void:
	_write_raw(path, JSON.stringify(state))


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.flush()


func _goto(target: StringName, params: Dictionary = {}) -> void:
	var before := _travel_count
	_router.goto(target, params)
	var deadline := Time.get_ticks_msec() + 25_000
	while Time.get_ticks_msec() < deadline:
		if _travel_count > before and not _router.is_busy():
			return
		await process_frame
	print("[FUZZ] WARNUNG: Reise-Timeout bei '%s' (Fall %s)" % [target, _case_name])


func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 25_000
	while Time.get_ticks_msec() < deadline:
		if not _router.is_busy():
			return
		await process_frame


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout
