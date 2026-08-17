extends TestCase
## PURE-Tests für VisitLogic (W3c VISIT): 5-Hz-POS-Takt, POS-Payload-
## Roundtrip, Raum-Sichtbarkeit und BUILD_DELTA-Anwendung beim Gast
## (place/remove, Konfliktregel „Gast steht auf der Zelle → Teleport").


func test_pos_takt_5hz() -> void:
	assert_true(VisitLogic.should_send_pos(-1, 0), "erster Send immer sofort")
	assert_false(VisitLogic.should_send_pos(1000, 1100), "100 ms < 200 ms → warten")
	assert_true(VisitLogic.should_send_pos(1000, 1200), "exakt 200 ms → senden")
	assert_true(VisitLogic.should_send_pos(1000, 1500))
	assert_eq(VisitLogic.POS_INTERVAL_MS, 200, "5 Hz = Server-Bucket-Refill (rooms.js)")


func test_pos_payload_roundtrip() -> void:
	var body := VisitLogic.pos_payload(Vector3(1.2345, 9.0, -3.5), "walk", "living")
	assert_eq(body["roomId"], "living")
	assert_eq(body["anim"], "walk")
	var parsed := VisitLogic.parse_pos(body)
	assert_true(parsed["ok"])
	assert_almost((parsed["pos"] as Vector3).x, 1.234, 0.0011, "auf mm gerundet")
	assert_almost((parsed["pos"] as Vector3).z, -3.5, 1e-6)
	assert_almost((parsed["pos"] as Vector3).y, 0.0, 1e-9, "y reist nie mit")
	assert_eq(parsed["anim"], "walk")
	assert_eq(parsed["room_id"], "living")


func test_parse_pos_robust() -> void:
	assert_false(VisitLogic.parse_pos(null)["ok"])
	assert_false(VisitLogic.parse_pos("quatsch")["ok"])
	assert_false(VisitLogic.parse_pos({})["ok"])
	assert_false(VisitLogic.parse_pos({"pos": [1.0]})["ok"], "pos braucht 2 Werte")
	var minimal := VisitLogic.parse_pos({"pos": [1, 2]})
	assert_true(minimal["ok"])
	assert_eq(minimal["anim"], "idle", "fehlende Felder → Defaults")
	assert_eq(minimal["room_id"], "")


func test_peer_sichtbarkeit_nur_gleicher_raum() -> void:
	assert_true(VisitLogic.peer_visible("living", "living"))
	assert_false(VisitLogic.peer_visible("living", "kitchen"))
	assert_false(VisitLogic.peer_visible("", ""), "ohne Raum nie sichtbar")
	assert_false(VisitLogic.peer_visible("", "living"))


func test_build_delta_place() -> void:
	var grid := GridData.new(Vector2i(8, 8))
	var delta := {"op": "place", "item": "chair", "cell": [3, 3], "rot": 0}
	var res := VisitLogic.apply_build_delta(grid, delta, Vector2i(0, 0), "uid-x")
	assert_true(res["ok"], str(res))
	assert_false(res["teleport"], "Gast steht woanders → kein Teleport")
	assert_eq(res["uid"], "uid-x")
	assert_eq(grid.item_at(Vector2i(3, 3), GridData.Layer.FLOOR), "uid-x")
	var again := VisitLogic.apply_build_delta(grid, delta, Vector2i.ZERO, "uid-y")
	assert_false(again["ok"], "Zelle belegt → Best-Effort-Fehler")


func test_build_delta_place_auf_gast_zelle_teleportiert() -> void:
	var grid := GridData.new(Vector2i(8, 8))
	# table = 3x2 ab [2,2] → Zellen (2..4, 2..3); Gast steht auf (3,3).
	var delta := {"op": "place", "item": "table", "cell": [2, 2], "rot": 0}
	var res := VisitLogic.apply_build_delta(grid, delta, Vector2i(3, 3))
	assert_true(res["ok"], str(res))
	assert_true(res["teleport"], "Möbel unterm Gast → Szene teleportiert zur Tür")


func test_build_delta_remove() -> void:
	var grid := GridData.new(Vector2i(8, 8))
	grid.place(FurnitureCatalog.def("chair"), Vector2i(2, 2), 0, "weg-1")
	var res := VisitLogic.apply_build_delta(grid, {"op": "remove", "cell": [2, 2]}, Vector2i.ZERO)
	assert_true(res["ok"])
	assert_eq(res["uid"], "weg-1")
	assert_eq(grid.item_at(Vector2i(2, 2), GridData.Layer.FLOOR), "")
	var missing := VisitLogic.apply_build_delta(
		grid, {"op": "remove", "cell": [7, 7]}, Vector2i.ZERO
	)
	assert_eq(missing["reason"], VisitLogic.REASON_NOT_FOUND)


func test_build_delta_fehlerfaelle() -> void:
	var grid := GridData.new(Vector2i(8, 8))
	assert_eq(
		VisitLogic.apply_build_delta(null, {"op": "place"}, Vector2i.ZERO)["reason"],
		VisitLogic.REASON_BAD_DELTA
	)
	assert_eq(
		VisitLogic.apply_build_delta(grid, "quatsch", Vector2i.ZERO)["reason"],
		VisitLogic.REASON_BAD_DELTA
	)
	assert_eq(
		VisitLogic.apply_build_delta(grid, {"op": "explodieren"}, Vector2i.ZERO)["reason"],
		VisitLogic.REASON_BAD_DELTA
	)
	var unknown := {"op": "place", "item": "warpkern", "cell": [1, 1]}
	assert_eq(
		VisitLogic.apply_build_delta(grid, unknown, Vector2i.ZERO)["reason"],
		VisitLogic.REASON_UNKNOWN_ITEM
	)


func test_anim_mapping() -> void:
	assert_eq(VisitLogic.anim_for(true), "walk")
	assert_eq(VisitLogic.anim_for(false), "idle")
