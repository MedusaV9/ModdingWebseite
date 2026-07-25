extends TestCase
## W2a — Katalog-/Raumdaten-Integrität: Pflicht-Möbel, GLB-Pfade,
## Default-Layouts kollisionsfrei, Tür-Symmetrie (Doc D §1.3/§2.4).

const VALID_LAYERS := [
	GridData.Layer.RUG, GridData.Layer.FLOOR, GridData.Layer.SURFACE, GridData.Layer.WALL
]


func test_katalog_geladen_und_normalisiert() -> void:
	var defs := FurnitureCatalog.defs()
	assert_true(defs.size() >= 30, "mind. ~30 Start-Möbel (sind: %d)" % defs.size())
	for id: String in defs:
		var def: Dictionary = defs[id]
		assert_eq(def["id"], id)
		assert_true(def["name_de"] != "", "%s: name_de" % id)
		assert_true(def["name_en"] != "", "%s: name_en" % id)
		assert_true(VALID_LAYERS.has(def["layer"]), "%s: Layer" % id)
		var fp: Vector2i = def["footprint"]
		assert_true(fp.x >= 1 and fp.y >= 1, "%s: Footprint" % id)
		assert_true(def["lagerwert"] >= 1 and def["lagerwert"] <= 4, "%s: lagerwert 1-4" % id)
		assert_true(def["preis"] >= 0, "%s: preis" % id)
		assert_true(def["kategorie"] != "", "%s: kategorie" % id)
		if def["layer"] == GridData.Layer.WALL:
			assert_true(def["wall_size"] >= 1, "%s: wall_size" % id)


func test_glb_pfade_existieren() -> void:
	for id: String in FurnitureCatalog.ids():
		var def: Dictionary = FurnitureCatalog.defs()[id]
		# Prozedurale Möbel (Doc D §9, z. B. Fenster) haben bewusst kein GLB —
		# FurnitureNode baut sie aus HomeProps.
		if str(def.get("proc", "")) != "":
			assert_eq(str(def.get("glb", "")), "", "%s: proc-Möbel ohne glb-Pfad" % id)
			continue
		var path := FurnitureCatalog.glb_path(def)
		assert_true(ResourceLoader.exists(path), "GLB fehlt: %s (%s)" % [path, id])


func test_pflicht_moebel_vorhanden() -> void:
	var slots := {"bett": 0, "couch": 0, "kuehlschrank": 0}
	for id: String in FurnitureCatalog.ids():
		var slot: String = FurnitureCatalog.defs()[id]["pflicht"]
		if slot != "":
			assert_true(slots.has(slot), "unbekannter Pflicht-Slot: %s" % slot)
			slots[slot] += 1
	for slot: String in slots:
		assert_true(slots[slot] >= 1, "Pflicht-Slot %s hat kein Möbel" % slot)
	assert_eq(FurnitureCatalog.def("bedSingle")["pflicht"], "bett", "Bett = PFLICHT")
	assert_eq(FurnitureCatalog.def("loungeSofa")["pflicht"], "couch", "Couch = PFLICHT")


func test_lampen_haben_licht_faehigkeit() -> void:
	var lampen := FurnitureCatalog.by_category("lampen")
	assert_true(lampen.size() >= 3, "mehrere Lampen")
	for def: Dictionary in lampen:
		assert_true(def["can_toggle_light"], "%s: an/aus-Fähigkeit" % def["id"])


func test_pflicht_slot_letztes_item_regel() -> void:
	var items := [
		{"uid": "i-1", "item": "bedSingle", "at": [0, 0], "rot": 0},
		{"uid": "i-2", "item": "chair", "at": [4, 0], "rot": 0},
	]
	assert_true(FurnitureCatalog.is_last_of_mandatory_slot(items, "i-1"), "letztes Bett gesperrt")
	assert_false(FurnitureCatalog.is_last_of_mandatory_slot(items, "i-2"), "Stuhl frei")
	items.append({"uid": "i-3", "item": "bedDouble", "at": [4, 4], "rot": 0})
	assert_false(FurnitureCatalog.is_last_of_mandatory_slot(items, "i-1"), "zweites Bett gibt frei")
	assert_eq(FurnitureCatalog.mandatory_counts(items)["bett"], 2)


func test_raum_definitionen() -> void:
	assert_eq(RoomDefs.ids(), ["bathroom", "bedroom", "garden", "kitchen", "living"])
	for room_id: String in RoomDefs.ids():
		var room := RoomDefs.room(room_id)
		var grid_size: Vector2i = room["grid"]
		assert_true(grid_size.x >= 6 and grid_size.y >= 6, "%s: Mindestgröße" % room_id)
		assert_true(
			ResourceLoader.exists(str(room["scene"])),
			"%s: Szene fehlt: %s" % [room_id, room["scene"]]
		)
		for door: Dictionary in room["doors"]:
			var other := RoomDefs.room(str(door["to"]))
			assert_false(other.is_empty(), "%s: Ziel-Raum %s" % [room_id, door["to"]])
			var back := RoomDefs.door(str(door["to"]), str(door["to_door"]))
			assert_false(back.is_empty(), "%s: Gegen-Tür %s" % [room_id, door["to_door"]])
			assert_eq(str(back["to"]), room_id, "Tür-Symmetrie %s" % door["id"])
			for cell: Vector2i in RoomDefs.door_zone(room, door):
				assert_true(
					cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y,
					"%s/%s: Türzone in Bounds" % [room_id, door["id"]]
				)


func test_default_layouts_kollisionsfrei() -> void:
	for room_id: String in RoomDefs.ids():
		var grid := RoomDefs.make_grid(room_id)
		var seq := 0
		for entry: Dictionary in RoomDefs.default_layout(room_id):
			var def := FurnitureCatalog.def(str(entry["item"]))
			assert_false(def.is_empty(), "%s: Item %s im Katalog" % [room_id, entry["item"]])
			if def.is_empty():
				continue
			seq += 1
			var res: Dictionary
			if entry.has("wall"):
				res = grid.place_wall(def, str(entry["wall"]), int(entry["at"][0]), "d-%d" % seq)
			else:
				var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
				res = grid.place(def, at, int(entry.get("rot", 0)), "d-%d" % seq)
			assert_true(
				res["ok"],
				"%s: %s @ %s → %s" % [room_id, entry["item"], str(entry["at"]), res["reason"]]
			)
		assert_true(seq >= 8, "%s: liebevolles Layout (≥8 Items, sind %d)" % [room_id, seq])


func test_default_layout_laesst_tueren_erreichbar() -> void:
	for room_id: String in RoomDefs.ids():
		var room := RoomDefs.room(room_id)
		var grid := RoomDefs.make_grid(room_id)
		var seq := 0
		for entry: Dictionary in RoomDefs.default_layout(room_id):
			var def := FurnitureCatalog.def(str(entry["item"]))
			seq += 1
			if entry.has("wall"):
				grid.place_wall(def, str(entry["wall"]), int(entry["at"][0]), "d-%d" % seq)
			else:
				var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
				grid.place(def, at, int(entry.get("rot", 0)), "d-%d" % seq)
		var free := grid.free_cells()
		assert_true(free.size() >= 10, "%s: genug freie Standplätze" % room_id)
		for door: Dictionary in room["doors"]:
			assert_true(
				grid.is_zone_reachable(free[0], RoomDefs.door_zone(room, door)),
				"%s: Tür %s im Default-Layout erreichbar" % [room_id, door["id"]]
			)


func test_default_storage_hat_bett_fuer_bauquest() -> void:
	var hat_bett := false
	for entry: Dictionary in RoomDefs.default_storage():
		var def := FurnitureCatalog.def(str(entry["item"]))
		assert_false(def.is_empty(), "Lager-Item %s im Katalog" % entry["item"])
		if def.get("pflicht", "") == "bett":
			hat_bett = true
	assert_true(hat_bett, "Bett liegt im Start-Lager (Doc D §3.1 Bauquest)")


func test_schlafzimmer_startet_ohne_bett() -> void:
	for entry: Dictionary in RoomDefs.default_layout("bedroom"):
		var def := FurnitureCatalog.def(str(entry["item"]))
		assert_ne(def.get("pflicht", ""), "bett", "Bett kommt aus dem Lager, nicht vorplatziert")


func test_route_table() -> void:
	var routes := RoomDefs.route_table()
	assert_eq(routes.size(), 5)
	assert_eq(routes[&"home/living"], "res://scenes/home/wohnzimmer.tscn")
	assert_eq(RoomDefs.route_target("garden"), &"home/garden")
