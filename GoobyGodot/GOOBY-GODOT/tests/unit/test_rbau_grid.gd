extends TestCase
## RW-4 — RanchGridData: Außen-Grid mit Zell-Layern (BODEN/OBJEKT),
## KANTEN-Zäunen (N/W-Normalform), Zonen-Sperre, Kollisionen, Rotation
## und Save-Roundtrip (Leftovers statt Datenverlust).

const START_ZONE := Rect2i(0, 6, 10, 10)


func _defs() -> Dictionary:
	return {
		"stall":
		{
			"id": "stall",
			"kategorie": "anlage",
			"layer": RanchGridData.Layer.OBJEKT,
			"footprint": Vector2i(2, 3),
			"kante": false,
			"kosten": 100,
		},
		"weg":
		{
			"id": "weg",
			"kategorie": "boden",
			"layer": RanchGridData.Layer.BODEN,
			"footprint": Vector2i.ONE,
			"kante": false,
			"kosten": 10,
		},
		"zaun":
		{
			"id": "zaun",
			"kategorie": "zaun",
			"layer": RanchGridData.Layer.OBJEKT,
			"footprint": Vector2i.ONE,
			"kante": true,
			"kosten": 20,
		},
	}


func _grid() -> RanchGridData:
	return RanchGridData.new(Vector2i(16, 16), [START_ZONE])


func test_platzieren_und_kollision() -> void:
	var grid := _grid()
	var stall: Dictionary = _defs()["stall"]
	assert_true(bool(grid.place(stall, Vector2i(1, 7), 0, "a")["ok"]), "frei -> ok")
	var again := grid.can_place(stall, Vector2i(2, 8), 0)
	assert_false(bool(again["ok"]), "Überlappung blockiert")
	assert_eq(str(again["reason"]), RanchGridData.REASON_OCCUPIED)
	assert_eq(grid.item_at(Vector2i(2, 9), RanchGridData.Layer.OBJEKT), "a")
	assert_eq(grid.item_at(Vector2i(4, 9), RanchGridData.Layer.OBJEKT), "", "daneben frei")


func test_rotation_dreht_den_footprint() -> void:
	assert_eq(RanchGridData.rotated_footprint(Vector2i(2, 3), 0), Vector2i(2, 3))
	assert_eq(RanchGridData.rotated_footprint(Vector2i(2, 3), 1), Vector2i(3, 2))
	assert_eq(RanchGridData.rotated_footprint(Vector2i(2, 3), 2), Vector2i(2, 3))
	assert_eq(RanchGridData.rotated_footprint(Vector2i(2, 3), 7), Vector2i(3, 2))
	var grid := _grid()
	var stall: Dictionary = _defs()["stall"]
	# 2x3 bei rot=1 wird 3x2: (8,14) + 3 Breite = x 8..10 innerhalb 10er-Zone? x=10 raus.
	assert_false(bool(grid.can_place(stall, Vector2i(8, 14), 1)["ok"]), "gedreht zu breit")
	assert_true(bool(grid.can_place(stall, Vector2i(7, 14), 1)["ok"]), "passt gedreht")


func test_zonen_sperre_und_bounds() -> void:
	var grid := _grid()
	var weg: Dictionary = _defs()["weg"]
	var oben := grid.can_place(weg, Vector2i(3, 3), 0)
	assert_false(bool(oben["ok"]), "Nord-Zone noch gesperrt")
	assert_eq(str(oben["reason"]), RanchGridData.REASON_GESPERRT)
	var raus := grid.can_place(weg, Vector2i(-1, 8), 0)
	assert_eq(str(raus["reason"]), RanchGridData.REASON_OOB)
	# Zone dazuschalten -> gleiche Zelle wird frei.
	var offen := RanchGridData.new(Vector2i(16, 16), [START_ZONE, Rect2i(0, 0, 10, 6)])
	assert_true(bool(offen.can_place(weg, Vector2i(3, 3), 0)["ok"]))


func test_boden_und_objekt_layer_getrennt() -> void:
	var grid := _grid()
	assert_true(bool(grid.place(_defs()["weg"], Vector2i(2, 8), 0, "w")["ok"]))
	assert_true(
		bool(grid.place(_defs()["stall"], Vector2i(2, 8), 0, "s")["ok"]),
		"Objekt darf AUF dem Boden stehen"
	)
	var weg2 := grid.can_place(_defs()["weg"], Vector2i(2, 8), 0)
	assert_false(bool(weg2["ok"]), "Boden auf Boden kollidiert")


func test_kanten_normalform() -> void:
	assert_eq(
		RanchGridData.normalize_kante(Vector2i(3, 4), "S"), {"cell": Vector2i(3, 5), "seite": "N"}
	)
	assert_eq(
		RanchGridData.normalize_kante(Vector2i(3, 4), "E"), {"cell": Vector2i(4, 4), "seite": "W"}
	)
	assert_eq(
		RanchGridData.normalize_kante(Vector2i(3, 4), "N"), {"cell": Vector2i(3, 4), "seite": "N"}
	)


func test_zaun_als_kante_selbe_kante_kollidiert() -> void:
	var grid := _grid()
	var zaun: Dictionary = _defs()["zaun"]
	assert_true(bool(grid.place_kante(zaun, Vector2i(3, 8), "S", "z1")["ok"]))
	# S(3,8) == N(3,9): dieselbe physische Kante ist belegt.
	var doppelt := grid.can_place_kante(zaun, Vector2i(3, 9), "N")
	assert_false(bool(doppelt["ok"]), "S(3,8) und N(3,9) sind EINE Kante")
	assert_eq(str(doppelt["reason"]), RanchGridData.REASON_OCCUPIED)
	assert_eq(grid.kante_item_at(Vector2i(3, 8), "S"), "z1")
	assert_eq(grid.kante_item_at(Vector2i(3, 9), "N"), "z1")
	assert_true(bool(grid.can_place_kante(zaun, Vector2i(3, 8), "N")["ok"]), "andere Kante frei")


func test_zaun_nur_an_freigeschalteten_zellen() -> void:
	var grid := _grid()
	var zaun: Dictionary = _defs()["zaun"]
	assert_false(bool(grid.can_place_kante(zaun, Vector2i(3, 2), "N")["ok"]), "gesperrte Zone")
	# Rand-Kante der Start-Zone (Nachbar oben gesperrt, Zelle selbst frei) geht.
	assert_true(bool(grid.can_place_kante(zaun, Vector2i(3, 6), "N")["ok"]))
	# Zell-Item blockiert eine Kante NICHT (Zaun am Stall erlaubt).
	assert_true(bool(grid.place(_defs()["stall"], Vector2i(1, 7), 0, "s")["ok"]))
	assert_true(bool(grid.can_place_kante(zaun, Vector2i(1, 7), "W")["ok"]))


func test_weide_ring_steckt_rechteck_ab() -> void:
	var ring := RanchGridData.weide_ring(Rect2i(2, 8, 3, 2))
	assert_eq(ring.size(), 10, "2*(3+2) Kanten")
	var grid := _grid()
	var zaun: Dictionary = _defs()["zaun"]
	var i := 0
	for kante: Dictionary in ring:
		var res := grid.place_kante(zaun, kante["cell"], kante["seite"], "r%d" % i)
		assert_true(bool(res["ok"]), "Ring-Kante %d frei" % i)
		i += 1
	# Mit Tor-Lücke fehlt genau eine Kante.
	assert_eq(RanchGridData.weide_ring(Rect2i(2, 8, 3, 2), 0).size(), 9)


func test_save_roundtrip_und_leftovers() -> void:
	var grid := _grid()
	assert_true(bool(grid.place(_defs()["stall"], Vector2i(1, 7), 1, "a")["ok"]))
	assert_true(bool(grid.place_kante(_defs()["zaun"], Vector2i(3, 8), "E", "b")["ok"]))
	var items := grid.to_items_array()
	assert_eq(items.size(), 2)
	var wieder := RanchGridData.from_save(items, _defs(), Vector2i(16, 16), [START_ZONE])
	assert_eq((wieder["leftovers"] as Array).size(), 0, "alles kommt wieder")
	var g2: RanchGridData = wieder["grid"]
	assert_eq(g2.get_item("a")["rot"], 1, "Rotation überlebt")
	assert_eq(g2.kante_item_at(Vector2i(3, 8), "E"), "b", "Kante überlebt (normalisiert)")
	# Unbekanntes Item + Konflikt landen als Leftover, nichts geht verloren.
	items.append({"uid": "x", "item": "ufo", "at": [5, 9], "rot": 0})
	items.append({"uid": "y", "item": "stall", "at": [1, 7], "rot": 0})
	var kaputt := RanchGridData.from_save(items, _defs(), Vector2i(16, 16), [START_ZONE])
	assert_eq((kaputt["leftovers"] as Array).size(), 2, "ufo + Kollision als Leftover")


func test_move_item_prueft_kollision() -> void:
	var grid := _grid()
	assert_true(bool(grid.place(_defs()["stall"], Vector2i(1, 7), 0, "a")["ok"]))
	assert_true(bool(grid.place(_defs()["weg"], Vector2i(6, 8), 0, "w")["ok"]))
	assert_true(bool(grid.move_item("a", Vector2i(4, 10), 1)["ok"]), "freies Ziel")
	assert_eq(grid.item_at(Vector2i(1, 7), RanchGridData.Layer.OBJEKT), "", "alte Zellen frei")
	assert_true(
		bool(grid.move_item("a", Vector2i(4, 10), 0)["ok"]), "Drehen an Ort und Stelle (ignore_uid)"
	)
	var raus := grid.move_item("a", Vector2i(9, 14), 0)
	assert_false(bool(raus["ok"]), "2x3 ragt aus der Zone")


func test_welt_koordinaten() -> void:
	assert_eq(RanchGridData.world_center(Vector2i(0, 0), Vector2i(2, 2), 0), Vector3(3, 0, 3))
	assert_eq(RanchGridData.cell_of(Vector3(3.1, 0, 8.9)), Vector2i(1, 2))
	var kante := RanchGridData.kante_world(Vector2i(2, 2), "S")
	assert_eq(kante["pos"], Vector3(7.5, 0.0, 9.0), "S(2,2)=N(2,3) läuft entlang X")
	var nah := RanchGridData.nearest_kante(Vector3(7.4, 0.0, 8.9))
	assert_eq(nah, {"cell": Vector2i(2, 3), "seite": "N"}, "Snapping auf die nächste Kante")
