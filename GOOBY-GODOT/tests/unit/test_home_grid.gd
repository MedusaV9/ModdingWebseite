extends TestCase
## W2a — GridData + StorageLogic: Platzierung, Kollision, Rotation, Wände,
## Erreichbarkeit, Lager und (De-)Serialisierung (Doc D §1).


func _def(id: String, w: int, h: int, layer: int, extra := {}) -> Dictionary:
	var def := {
		"id": id,
		"footprint": Vector2i(w, h),
		"layer": layer,
		"lagerwert": 1,
		"pflicht": "",
		"surface": false,
		"blocks_movement": layer == GridData.Layer.FLOOR,
		"wall_size": w,
		"fill": 1.0,
	}
	def.merge(extra, true)
	return def


func test_rotated_footprint_und_zellen() -> void:
	assert_eq(GridData.rotated_footprint(Vector2i(4, 2), 0), Vector2i(4, 2))
	assert_eq(GridData.rotated_footprint(Vector2i(4, 2), 1), Vector2i(2, 4))
	assert_eq(GridData.rotated_footprint(Vector2i(4, 2), 2), Vector2i(4, 2))
	assert_eq(GridData.rotated_footprint(Vector2i(4, 2), 3), Vector2i(2, 4))
	var cells := GridData.cells_for(Vector2i(2, 3), Vector2i(2, 1), 1)
	assert_eq(cells, [Vector2i(2, 3), Vector2i(2, 4)], "rot 1 tauscht B/T")


func test_platzierung_und_kollision() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var sofa := _def("sofa", 4, 2, GridData.Layer.FLOOR)
	assert_true(grid.place(sofa, Vector2i(0, 0), 0, "a")["ok"])
	var second := grid.place(sofa, Vector2i(2, 1), 0, "b")
	assert_false(second["ok"])
	assert_eq(second["reason"], GridData.REASON_OCCUPIED)
	var oob := grid.can_place(sofa, Vector2i(4, 0), 0)
	assert_eq(oob["reason"], GridData.REASON_OOB)
	assert_eq(grid.item_at(Vector2i(3, 1), GridData.Layer.FLOOR), "a")
	assert_eq(grid.item_at(Vector2i(3, 3), GridData.Layer.FLOOR), "")
	var unknown := grid.place({}, Vector2i(0, 0), 0, "x")
	assert_eq(unknown["reason"], GridData.REASON_UNKNOWN_ITEM)


func test_rotation_belegt_getauschte_zellen() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var tisch := _def("tisch", 3, 2, GridData.Layer.FLOOR)
	assert_true(grid.place(tisch, Vector2i(0, 0), 1, "t")["ok"])
	assert_eq(grid.item_at(Vector2i(1, 2), GridData.Layer.FLOOR), "t", "2 breit, 3 tief")
	assert_eq(grid.item_at(Vector2i(2, 0), GridData.Layer.FLOOR), "", "x=2 frei bei rot 1")


func test_tuerzone_blockt_bau_aber_nicht_gooby() -> void:
	var zone := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)]
	var grid := GridData.new(Vector2i(6, 6), zone)
	var regal := _def("regal", 2, 1, GridData.Layer.FLOOR)
	var res := grid.can_place(regal, Vector2i(2, 0), 0)
	assert_eq(res["reason"], GridData.REASON_BLOCKED)
	assert_true(grid.walkable(Vector2i(2, 0)), "Türzone ist begehbar")
	assert_false(grid.free_cells().has(Vector2i(2, 0)), "aber kein Idle-Standplatz")


func test_surface_braucht_traeger() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var toaster := _def("toaster", 1, 1, GridData.Layer.SURFACE)
	assert_eq(grid.can_place(toaster, Vector2i(1, 1), 0)["reason"], GridData.REASON_NEEDS_SURFACE)
	var zeile := _def("zeile", 2, 2, GridData.Layer.FLOOR, {"surface": true})
	assert_true(grid.place(zeile, Vector2i(1, 1), 0, "z")["ok"])
	assert_true(grid.place(toaster, Vector2i(1, 1), 0, "t")["ok"])
	var second := grid.can_place(toaster, Vector2i(1, 1), 0)
	assert_eq(second["reason"], GridData.REASON_OCCUPIED)


func test_teppich_und_moebel_stapeln() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var teppich := _def("teppich", 3, 3, GridData.Layer.RUG, {"blocks_movement": false})
	var stuhl := _def("stuhl", 1, 1, GridData.Layer.FLOOR)
	assert_true(grid.place(teppich, Vector2i(0, 0), 0, "r")["ok"])
	assert_true(grid.place(stuhl, Vector2i(1, 1), 0, "s")["ok"], "FLOOR auf RUG erlaubt")
	var zweiter := grid.can_place(teppich, Vector2i(2, 2), 0)
	assert_eq(zweiter["reason"], GridData.REASON_OCCUPIED, "RUG auf RUG nicht")


func test_wand_items_und_tuer_spannen() -> void:
	var grid := GridData.new(Vector2i(8, 6), [], {"N": [[2, 4]]})
	var lampe := _def("lampe", 1, 1, GridData.Layer.WALL, {"wall_size": 1})
	assert_true(grid.place_wall(lampe, "N", 0, "l1")["ok"])
	assert_eq(grid.can_place_wall(lampe, "N", 0)["reason"], GridData.REASON_OCCUPIED)
	assert_eq(grid.can_place_wall(lampe, "N", 2)["reason"], GridData.REASON_BLOCKED, "Türspanne")
	assert_eq(grid.can_place_wall(lampe, "N", 8)["reason"], GridData.REASON_OOB)
	assert_eq(grid.can_place_wall(lampe, "Q", 0)["reason"], GridData.REASON_OOB)
	assert_true(grid.can_place_wall(lampe, "E", 5)["ok"], "E-Wand: Breite = size.y")
	assert_eq(grid.wall_width("E"), 6)


func test_wall_item_at_findet_wand_items() -> void:
	var grid := GridData.new(Vector2i(8, 6))
	var spiegel := _def("spiegel", 1, 1, GridData.Layer.WALL, {"wall_size": 1})
	var bild := _def("bild", 2, 1, GridData.Layer.WALL, {"wall_size": 2})
	assert_true(grid.place_wall(spiegel, "N", 2, "s")["ok"])
	assert_true(grid.place_wall(bild, "E", 1, "b")["ok"])
	assert_eq(grid.wall_item_at("N", 2), "s")
	assert_eq(grid.wall_item_at("N", 3), "", "Nachbar-Slot frei")
	assert_eq(grid.wall_item_at("E", 1), "b", "mehrzellig: erster Slot")
	assert_eq(grid.wall_item_at("E", 2), "b", "mehrzellig: zweiter Slot")
	assert_eq(grid.wall_item_at("W", 2), "", "andere Wand frei")
	grid.remove_item("s")
	assert_eq(grid.wall_item_at("N", 2), "", "nach remove_item wieder frei")


func test_from_save_platziert_traeger_vor_surface() -> void:
	# E9 P1-1: SURFACE-Item hat eine KLEINERE uid als sein Träger —
	# to_items_array sortiert nach uid, das Aufliegende steht also VOR dem
	# Träger im Array. from_save darf es trotzdem nicht ins Lager verlieren.
	var defs := {
		"tisch": _def("tisch", 1, 1, GridData.Layer.FLOOR, {"surface": true}),
		"lampe": _def("lampe", 1, 1, GridData.Layer.SURFACE),
	}
	var grid := GridData.new(Vector2i(8, 8))
	assert_true(grid.place(defs["tisch"], Vector2i(3, 3), 0, "i-000020")["ok"])
	assert_true(grid.place(defs["lampe"], Vector2i(3, 3), 0, "i-000010")["ok"])
	var arr := grid.to_items_array()
	assert_eq(str(arr[0]["item"]), "lampe", "uid-sortiert: Lampe zuerst")
	var loaded := GridData.from_save(arr, defs, Vector2i(8, 8))
	assert_true(loaded["leftovers"].is_empty(), "Lampe bleibt auf dem Tisch")
	assert_eq(loaded["grid"].to_items_array(), arr, "Roundtrip identisch")
	# Schwebende SURFACE-Items (Träger fehlt wirklich) degradieren weiter weich.
	var ohne_traeger := [{"uid": "i-1", "item": "lampe", "at": [5, 5], "rot": 0}]
	var healed := GridData.from_save(ohne_traeger, defs, Vector2i(8, 8))
	assert_eq(healed["leftovers"].size(), 1, "ohne Träger → Leftover")
	# Kaputte Einträge landen weiterhin im Leftover, nicht im Crash.
	var gemischt := [
		{"uid": "i-2", "item": "lampe", "at": [3, 3], "rot": 0},
		"muell",
		{"uid": "i-3", "item": "unbekannt", "at": [0, 0], "rot": 0},
		{"uid": "i-9", "item": "tisch", "at": [3, 3], "rot": 0},
	]
	var repariert := GridData.from_save(gemischt, defs, Vector2i(8, 8))
	assert_eq(repariert["leftovers"].size(), 2, "Müll + unbekannt")
	assert_eq(repariert["grid"].to_items_array().size(), 2, "Tisch + Lampe stehen")


func test_verschieben_und_entfernen() -> void:
	var grid := GridData.new(Vector2i(6, 6))
	var sofa := _def("sofa", 2, 2, GridData.Layer.FLOOR)
	grid.place(sofa, Vector2i(0, 0), 0, "a")
	var self_move := grid.move_item("a", Vector2i(1, 0), 1)
	assert_true(self_move["ok"], "Verschieben in eigene Zellen (ignore_uid)")
	assert_eq(grid.item_at(Vector2i(1, 1), GridData.Layer.FLOOR), "a")
	assert_eq(grid.item_at(Vector2i(0, 0), GridData.Layer.FLOOR), "")
	var removed := grid.remove_item("a")
	assert_eq(removed["uid"], "a")
	assert_eq(grid.item_at(Vector2i(1, 1), GridData.Layer.FLOOR), "")
	assert_true(grid.remove_item("nope").is_empty())


func test_erreichbarkeit_bfs() -> void:
	var grid := GridData.new(Vector2i(5, 5))
	var wand := _def("wand", 1, 5, GridData.Layer.FLOOR)
	assert_true(grid.place(wand, Vector2i(2, 0), 0, "w")["ok"])
	assert_false(grid.is_reachable(Vector2i(0, 0), Vector2i(4, 4)), "Wand teilt Raum")
	assert_true(grid.is_reachable(Vector2i(0, 0), Vector2i(1, 4)))
	assert_false(grid.walkable(Vector2i(2, 2)))
	assert_true(grid.is_zone_reachable(Vector2i(0, 0), [Vector2i(4, 4), Vector2i(1, 3)]))
	assert_false(grid.is_zone_reachable(Vector2i(0, 0), [Vector2i(4, 4)]))
	var lampe := _def("lampe", 1, 1, GridData.Layer.FLOOR, {"blocks_movement": false})
	grid.remove_item("w")
	grid.place(lampe, Vector2i(2, 2), 0, "l")
	assert_true(grid.walkable(Vector2i(2, 2)), "blocks_movement=false bleibt begehbar")


func test_serialisierung_roundtrip_und_leftovers() -> void:
	var defs := {
		"sofa": _def("sofa", 2, 2, GridData.Layer.FLOOR),
		"lampe": _def("lampe", 1, 1, GridData.Layer.WALL, {"wall_size": 1}),
	}
	var grid := GridData.new(Vector2i(6, 6))
	grid.place(defs["sofa"], Vector2i(1, 1), 3, "i-1")
	grid.place_wall(defs["lampe"], "W", 2, "i-2")
	var items := grid.to_items_array()
	assert_eq(items.size(), 2)
	assert_eq(items[0], {"uid": "i-1", "item": "sofa", "at": [1, 1], "rot": 3})
	assert_eq(items[1], {"uid": "i-2", "item": "lampe", "at": [2, 0], "rot": 0, "wall": "W"})
	var loaded := GridData.from_save(items, defs, Vector2i(6, 6))
	assert_true(loaded["leftovers"].is_empty())
	assert_eq(loaded["grid"].to_items_array(), items, "Roundtrip identisch")
	var kaputt := [
		{"uid": "i-3", "item": "unbekannt", "at": [0, 0], "rot": 0},
		{"uid": "i-4", "item": "sofa", "at": [1, 1], "rot": 0},
		{"uid": "i-5", "item": "sofa", "at": [1, 2], "rot": 0},
	]
	var healed := GridData.from_save(kaputt, defs, Vector2i(6, 6))
	assert_eq(healed["leftovers"].size(), 2, "unbekannt + Kollision wandern raus")
	assert_eq(healed["grid"].to_items_array().size(), 1)


func test_welt_koordinaten() -> void:
	assert_eq(GridData.world_center(Vector2i(0, 0), Vector2i.ONE, 0), Vector3(0.25, 0.0, 0.25))
	assert_eq(GridData.world_center(Vector2i(2, 4), Vector2i(4, 2), 1), Vector3(1.5, 0.0, 3.0))
	assert_eq(GridData.cell_of(Vector3(0.26, 0.0, 0.9)), Vector2i(0, 1))


func test_lager_logik() -> void:
	var defs := {
		"deko": _def("deko", 1, 1, GridData.Layer.SURFACE, {"lagerwert": 1}),
		"wanne": _def("wanne", 4, 2, GridData.Layer.FLOOR, {"lagerwert": 4}),
		"absurd": _def("absurd", 1, 1, GridData.Layer.FLOOR, {"lagerwert": 99}),
	}
	var storage: Array = []
	StorageLogic.add(storage, "deko")
	StorageLogic.add(storage, "deko")
	StorageLogic.add(storage, "wanne")
	assert_eq(storage.size(), 2, "gleiche Items mergen")
	assert_eq(StorageLogic.count_of(storage, "deko"), 2)
	assert_eq(StorageLogic.points_used(storage, defs), 6)
	assert_eq(StorageLogic.item_weight("absurd", defs), 4, "lagerwert clamp 1..4")
	assert_eq(StorageLogic.item_weight("unbekannt", defs), 1)
	assert_true(StorageLogic.can_add(storage, "wanne", defs, 10))
	assert_false(StorageLogic.can_add(storage, "wanne", defs, 9))
	assert_true(StorageLogic.take(storage, "deko"))
	assert_eq(StorageLogic.count_of(storage, "deko"), 1)
	assert_true(StorageLogic.take(storage, "deko"))
	assert_false(StorageLogic.take(storage, "deko"), "leer")
	assert_eq(storage.size(), 1)


func test_lager_kapazitaet_100() -> void:
	var defs := {"sofa": _def("sofa", 4, 2, GridData.Layer.FLOOR, {"lagerwert": 3})}
	var storage: Array = []
	for _i in 33:
		StorageLogic.add(storage, "sofa")
	assert_eq(StorageLogic.points_used(storage, defs), 99)
	assert_false(StorageLogic.can_add(storage, "sofa", defs, 100), "99+3 > 100")
	assert_true(StorageLogic.can_add(storage, "unbekannt", defs, 100), "99+1 <= 100")
