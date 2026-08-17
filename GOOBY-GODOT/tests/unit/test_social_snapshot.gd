extends TestCase
## PURE-Tests für VisitSnapshot (W3c VISIT): Aufbau aus dem W1d-State,
## JSON-Roundtrip, Validierung (Struktur + 256-KB-Limit), Raum-Filter und
## die GridData-Rekonstruktion beim Gast (read-only Möbel aus Save-Format).

const StateUtil := preload("res://tests/fixtures/state_test_util.gd")


## Mini-GameState-Double: get_value() über flache Pfad-Keys (mehr braucht
## VisitSnapshot nicht — Duck-Typing wie /root/GameState).
class FakeState:
	extends RefCounted
	var values: Dictionary = {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		return values.get(path, fallback)


func _state_with_rooms() -> FakeState:
	var gs := FakeState.new()
	gs.values = {
		"meta.goobyNickname": "Blobby",
		"home.rooms":
		{
			"living":
			{
				"items":
				[
					{"uid": "c1", "item": "chair", "at": [5, 5], "rot": 0},
					{"uid": "t1", "item": "table", "at": [1, 6], "rot": 0},
				]
			},
			"kitchen": {"items": []},
			"kaputt": "kein Dictionary",
		},
	}
	return gs


func test_build_from_state() -> void:
	var snapshot := VisitSnapshot.build_from_state(_state_with_rooms())
	assert_eq(snapshot["v"], VisitSnapshot.VERSION)
	assert_eq(snapshot["goobyName"], "Blobby")
	var rooms: Dictionary = snapshot["rooms"]
	assert_eq(rooms.keys().size(), 3, "auch leere/kaputte Räume reisen mit")
	assert_eq((rooms["living"]["items"] as Array).size(), 2)
	assert_eq(rooms["kaputt"]["items"], [], "kaputter Eintrag wird zu leerer Liste")


func test_json_roundtrip_verlustfrei() -> void:
	var snapshot := VisitSnapshot.build_from_state(_state_with_rooms())
	var text := VisitSnapshot.to_json(snapshot)
	var back := VisitSnapshot.parse(text)
	assert_true(back["ok"], "Roundtrip muss parsen: %s" % str(back))
	assert_true(
		StateUtil.deep_equal(snapshot, back["snapshot"]),
		"Diff: %s" % StateUtil.first_diff(snapshot, back["snapshot"])
	)


func test_validate_fehlerfaelle() -> void:
	assert_eq(VisitSnapshot.validate("kein dict")["reason"], VisitSnapshot.REASON_NOT_A_DICT)
	assert_eq(VisitSnapshot.validate({})["reason"], VisitSnapshot.REASON_NO_ROOMS)
	assert_eq(
		VisitSnapshot.validate({"rooms": {}})["reason"],
		VisitSnapshot.REASON_NO_ROOMS,
		"leere rooms sind kein gültiges Haus"
	)
	assert_true(VisitSnapshot.validate({"rooms": {"living": {"items": []}}})["ok"])
	assert_eq(VisitSnapshot.parse("{kaputt")["reason"], VisitSnapshot.REASON_NOT_A_DICT)
	assert_eq(VisitSnapshot.parse("[1,2]")["reason"], VisitSnapshot.REASON_NOT_A_DICT)


func test_validate_256kb_limit() -> void:
	var items: Array = []
	# ~70 Bytes/Item → 6000 Items sprengen die 256 KB sicher.
	for i in 6000:
		items.append({"uid": "uid-%06d" % i, "item": "chair", "at": [i % 12, i % 10], "rot": 0})
	var fat := {"v": 1, "goobyName": "XXL", "rooms": {"living": {"items": items}}}
	assert_true(VisitSnapshot.byte_size(fat) > VisitSnapshot.MAX_BYTES)
	assert_eq(VisitSnapshot.validate(fat)["reason"], VisitSnapshot.REASON_TOO_BIG)


func test_room_ids_filtert_und_sortiert() -> void:
	var snapshot := {
		"rooms":
		{
			"living": {"items": []},
			"bedroom": {"items": []},
			"mondbasis": {"items": []},
		}
	}
	assert_eq(
		VisitSnapshot.room_ids(snapshot),
		["bedroom", "living"] as Array[String],
		"nur W2a-RoomDefs-Räume, sortiert"
	)
	assert_eq(VisitSnapshot.room_ids({}), [] as Array[String])


func test_make_grid_rekonstruktion() -> void:
	var snapshot := VisitSnapshot.build_from_state(_state_with_rooms())
	var built := VisitSnapshot.make_grid(snapshot, "living")
	var grid: GridData = built["grid"]
	assert_true(grid != null)
	assert_eq(grid.item_at(Vector2i(5, 5), GridData.Layer.FLOOR), "c1")
	assert_eq(grid.item_at(Vector2i(2, 7), GridData.Layer.FLOOR), "t1", "table 3x2 ab [1,6]")
	assert_eq(grid.item_at(Vector2i(9, 9), GridData.Layer.FLOOR), "")
	assert_eq((built["leftovers"] as Array).size(), 0)
	assert_eq(VisitSnapshot.make_grid(snapshot, "mondbasis")["grid"], null)


func test_make_grid_unbekanntes_landet_in_leftovers() -> void:
	var snapshot := {
		"rooms":
		{
			"living":
			{
				"items":
				[
					{"uid": "ok1", "item": "chair", "at": [5, 5], "rot": 0},
					{"uid": "gh1", "item": "warpkern", "at": [2, 2], "rot": 0},
				]
			}
		}
	}
	var built := VisitSnapshot.make_grid(snapshot, "living")
	assert_eq((built["leftovers"] as Array).size(), 1, "unbekanntes Möbel wird ignoriert")
	assert_eq((built["grid"] as GridData).item_at(Vector2i(5, 5), GridData.Layer.FLOOR), "ok1")


func test_brettspieltisch_gate_m1_fallback() -> void:
	# Der Orchestrator hat 'brettspieltisch' in den W2a-Katalog aufgenommen:
	# das Gate prüft jetzt echten Besitz (Raum ODER Lager); ohne Besitz zu.
	assert_true(not FurnitureCatalog.def("brettspieltisch").is_empty(), "Item ist im Katalog")
	assert_true(not VisitSnapshot.has_board_table(FakeState.new()), "ohne Besitz: Gate zu")
	var gs := FakeState.new()
	gs.values["home.storage"] = [{"item": "brettspieltisch"}]
	assert_true(VisitSnapshot.has_board_table(gs), "mit Tisch im Lager: Gate offen")
