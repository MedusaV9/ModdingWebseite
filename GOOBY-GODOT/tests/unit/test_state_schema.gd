extends TestCase
## W1d — Save-v5-Schema: Roundtrip, Slices-Registry, Korruptions-Kontrakt.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")

const NOW_MS := 1768478400000


func test_default_state_shape() -> void:
	var s := SaveSchema.default_state(NOW_MS)
	assert_eq(s["v"], 5)
	assert_eq(s["meta"]["createdAt"], NOW_MS)
	assert_eq(s["meta"]["goobyNickname"], "Gooby")
	assert_eq(s["meta"]["charMorphs"].keys(), ["eyes_apart", "eye_scale", "ear_len", "chubby"])
	assert_eq(s["gooby"]["stats"], {"hunger": 80.0, "energy": 90.0, "hygiene": 85.0, "fun": 70.0})
	assert_eq(s["economy"]["coins"], 100)
	assert_eq(s["progression"], {"level": 1, "xp": 0})
	assert_eq(s["inventory"]["food"], {"carrot": 3, "apple": 1, "cupcake": 1})
	assert_eq(s["garden"]["grid"].size(), 6, "6 Grid-Felder (Doc H: Plots 1-6)")
	assert_eq(s["home"]["storageCapacity"], 100, "Doc D §1.4 Platzhalter")
	assert_false(s["radio"]["owned"], "v5-Neusaves besitzen KEIN Radio (Doc H §6.1)")
	assert_false(s["camera"]["owned"], "POW!-Kamera nur per Grandfathering/Kauf")
	assert_eq(s["vacation"]["phase"], "none")
	assert_eq(s["achievements"]["counters"]["feeds"], 0)
	assert_true(s["achievements"]["counters"].has("galleryPhotos"), "v4-Counter-Superset")


func test_roundtrip_json_is_lossless() -> void:
	var s := SaveSchema.default_state(NOW_MS)
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(s)), OK)
	var normalized := SaveSchema.normalize(json.data, NOW_MS)
	assert_true(normalized["ok"], "roundtrip normalize ok: " + normalized["error"])
	# Numerisch tolerant: JSON kennt nur double (int 3 kommt als 3.0 zurueck).
	var diff := Util.first_diff(normalized["state"], s)
	assert_true(diff.is_empty(), "persist → load → deep-equal (Schema-Roundtrip): " + diff)


func test_normalize_clamps_hostile_leaves() -> void:
	var s := SaveSchema.default_state(NOW_MS)
	s["gooby"]["stats"]["hunger"] = 400.0
	s["gooby"]["stats"]["fun"] = -20.0
	s["gooby"]["weight"] = 900.0
	s["economy"]["coins"] = -50
	s["progression"]["level"] = 99
	s["codes"]["lockUntil"] = 9.0e15
	s["gallery"]["legacyCount"] = 999
	s["radio"]["station"] = "piratensender"
	var normalized := SaveSchema.normalize(s, NOW_MS)
	assert_true(normalized["ok"])
	var n: Dictionary = normalized["state"]
	assert_eq(n["gooby"]["stats"]["hunger"], 100.0)
	assert_eq(n["gooby"]["stats"]["fun"], 0.0)
	assert_eq(n["gooby"]["weight"], 95.0)
	assert_eq(n["economy"]["coins"], 0)
	assert_eq(n["progression"]["level"], 40)
	assert_eq(n["codes"]["lockUntil"], float(NOW_MS + 86400000), "Far-Future-Stamp kollabiert")
	assert_eq(n["gallery"]["legacyCount"], 40)
	assert_eq(n["radio"]["station"], "bordmusik")


func test_normalize_rejects_structural_corruption() -> void:
	assert_false(SaveSchema.normalize("nope", NOW_MS)["ok"], "kein Objekt")
	assert_false(SaveSchema.normalize({"v": 5, "gooby": "kaputt"}, NOW_MS)["ok"], "Slice-Typ")
	assert_false(SaveSchema.normalize({"v": 5, "economy": []}, NOW_MS)["ok"], "Array statt Dict")
	assert_false(SaveSchema.normalize({"v": 6}, NOW_MS)["ok"], "Forward-Version")
	assert_false(SaveSchema.normalize({"v": -1}, NOW_MS)["ok"], "absurde Version")
	assert_false(SaveSchema.normalize({"v": 4}, NOW_MS)["ok"], "v4 braucht Migration")


func test_slice_registry_additive_packs() -> void:
	SaveSchema.register_slice(
		"testPack",
		func() -> Dictionary: return {"foo": 1, "bar": "x"},
		func(raw: Variant) -> Dictionary:
			var d: Dictionary = raw if raw is Dictionary else {}
			d["foo"] = maxi(0, int(d.get("foo", 1)))
			return d
	)
	var s := SaveSchema.default_state(NOW_MS)
	assert_eq(s["testPack"], {"foo": 1, "bar": "x"}, "registrierter Slice in default_state")
	s["testPack"]["foo"] = -5
	var normalized := SaveSchema.normalize(s, NOW_MS)
	assert_true(normalized["ok"])
	assert_eq(normalized["state"]["testPack"]["foo"], 0, "Slice-normalize angewendet")
	SaveSchema.unregister_slice("testPack")
	assert_false(SaveSchema.default_state(NOW_MS).has("testPack"))


func test_unknown_top_level_keys_pass_through() -> void:
	# Additive Slices OHNE Registrierung (Web-Muster vacation/themePark):
	# unbekannte Keys ueberleben normalize verbatim.
	var s := SaveSchema.default_state(NOW_MS)
	s["somePackData"] = {"hello": true}
	var normalized := SaveSchema.normalize(s, NOW_MS)
	assert_true(normalized["ok"])
	assert_eq(normalized["state"]["somePackData"], {"hello": true})
