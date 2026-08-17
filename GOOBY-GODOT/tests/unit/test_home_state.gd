extends TestCase
## W2a — HomeState: Slice-Registry (W1d), Erstbezug/Umzugstag-Layout,
## Grid-Laden/-Speichern mit Leftover-Heilung, Lager-API, Flags, uids.
## Jeder Test räumt die Registry wieder ab (SaveSchema ist prozessweit).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w2a_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_slice_registrierung_und_defaults() -> void:
	HomeState.register_slice()
	HomeState.register_slice()
	assert_true(SaveSchema.registered_slice_ids().has("home"), "idempotent registriert")
	var s := SaveSchema.default_state(NOW_MS)
	assert_eq(s["home"]["storageCapacity"], 100, "W1d-Platzhalter-Kontrakt bleibt")
	assert_eq(s["home"]["nextUid"], 1)
	assert_eq(s["home"]["flags"], {})
	assert_eq(s["home"]["rooms"], {})
	var normalized := SaveSchema.normalize(s, NOW_MS)
	assert_true(normalized["ok"], "Roundtrip mit registriertem Slice")
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_normalize_heilt_kaputte_typen() -> void:
	var healed := HomeState.normalize_slice(
		{"rooms": [], "storage": "kaputt", "nextUid": -3, "flags": 7, "storageCapacity": -1}
	)
	assert_eq(healed["rooms"], {})
	assert_eq(healed["storage"], [])
	assert_eq(healed["nextUid"], 1)
	assert_eq(healed["flags"], {})
	assert_eq(healed["storageCapacity"], 0)
	var kept := (
		HomeState
		. normalize_slice(
			{
				"rooms": {"living": {"items": []}},
				"storage": [{"item": "chair", "count": 2}, "müll", {"kein_item": 1}],
				"nextUid": 7.0,
				"movingDay": true,
			}
		)
	)
	assert_eq(kept["rooms"], {"living": {"items": []}}, "gültige Daten bleiben verbatim")
	assert_eq(kept["storage"], [{"item": "chair", "count": 2}], "kaputte Einträge fliegen")
	assert_eq(kept["nextUid"], 7, "JSON-float → int")
	assert_true(kept["movingDay"])


func test_erstbezug_fuellt_default_layout() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	var rooms: Dictionary = gs.get_value("home.rooms")
	assert_eq(rooms.keys().size(), 5, "alle 5 Räume bestückt")
	assert_eq(
		rooms["living"]["items"].size(), RoomDefs.default_layout("living").size(), "Wohnzimmer"
	)
	var storage: Array = gs.get_value("home.storage")
	assert_true(StorageLogic.count_of(storage, "bedSingle") >= 1, "Bett im Lager (Bauquest)")
	assert_true(HomeState.is_room_unlocked(gs, "garden"), "Garten freigeschaltet")
	assert_false(HomeState.is_room_unlocked(gs, "hall"), "hall hat (noch) keine Szene")
	var before: int = gs.get_value("home.rooms.living.items").size()
	HomeState.ensure_initialized(gs)
	assert_eq(gs.get_value("home.rooms.living.items").size(), before, "idempotent")
	_teardown(gs)


func test_grid_laden_speichern_roundtrip() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	var grid := HomeState.load_room_grid(gs, "living")
	var items_vorher: Array = gs.get_value("home.rooms.living.items")
	assert_eq(grid.to_items_array().size(), items_vorher.size(), "alles rekonstruiert")
	var def := FurnitureCatalog.def("chair")
	var uid := HomeState.next_uid(gs)
	assert_true(grid.place(def, Vector2i(0, 0), 0, uid)["ok"])
	HomeState.save_room_grid(gs, "living", grid)
	var reloaded := HomeState.load_room_grid(gs, "living")
	assert_eq(reloaded.get_item(uid)["at"], Vector2i(0, 0), "Save→Load erhält Platzierung")
	_teardown(gs)


func test_leftovers_wandern_ins_lager() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	(
		gs
		. set_value(
			"home.rooms.garden.items",
			[
				{"uid": "i-9001", "item": "gibtEsNicht", "at": [0, 0], "rot": 0},
				{"uid": "i-9002", "item": "chair", "at": [4, 4], "rot": 0},
				{"uid": "i-9003", "item": "chair", "at": [4, 4], "rot": 0},
			]
		)
	)
	var grid := HomeState.load_room_grid(gs, "garden")
	assert_eq(grid.to_items_array().size(), 1, "Kollision + Unbekanntes raus")
	var storage: Array = gs.get_value("home.storage")
	assert_eq(StorageLogic.count_of(storage, "chair"), 1, "bekanntes Item ins Lager")
	var unknown_found := false
	for entry: Dictionary in storage:
		if entry.get("item") == StorageLogic.UNKNOWN_ITEM and entry.get("origId") == "gibtEsNicht":
			unknown_found = true
	assert_true(unknown_found, "unbekannte id als __unknown__ + origId erhalten")
	var saved: Array = gs.get_value("home.rooms.garden.items")
	assert_eq(saved.size(), 1, "geheilter Raum sofort persistiert")
	_teardown(gs)


func test_lager_api_und_flags() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	var punkte := HomeState.storage_points_used(gs)
	assert_true(HomeState.store_item(gs, "chair"))
	assert_eq(HomeState.storage_points_used(gs), punkte + 1, "Stuhl wiegt 1 Lagerpunkt")
	assert_true(HomeState.take_from_storage(gs, "chair"))
	assert_false(HomeState.take_from_storage(gs, "chair"), "nur was drin ist, kommt raus")
	gs.set_value("home.storageCapacity", HomeState.storage_points_used(gs))
	assert_false(HomeState.store_item(gs, "bathtub"), "Kapazität voll → abgelehnt")
	assert_false(HomeState.flag(gs, HomeState.FLAG_BED_PLACED))
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	assert_true(HomeState.flag(gs, HomeState.FLAG_BED_PLACED))
	var uid_a := HomeState.next_uid(gs)
	var uid_b := HomeState.next_uid(gs)
	assert_ne(uid_a, uid_b, "uids laufen fort")
	_teardown(gs)
