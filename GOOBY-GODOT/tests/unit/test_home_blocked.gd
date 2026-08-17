extends TestCase
## W2a — Blockade-Erkennung (Doc F §6/§7): Grid blockiert Türzone →
## Spidergooby-Gag-Trigger. Pure über GridData-BFS + RoomDefs-Türzonen.


func _sofa() -> Dictionary:
	return {
		"id": "sofa",
		"footprint": Vector2i(4, 2),
		"layer": GridData.Layer.FLOOR,
		"blocks_movement": true,
		"surface": false,
		"wall_size": 4,
		"fill": 1.0,
		"lagerwert": 3,
		"pflicht": "",
	}


func test_tuerzonen_geometrie_alle_waende() -> void:
	var room := {"grid": Vector2i(8, 6), "doors": []}
	var n := RoomDefs.door_zone(room, {"wall": "N", "offset": 2})
	assert_eq(n, [Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 0), Vector2i(3, 1)])
	var s := RoomDefs.door_zone(room, {"wall": "S", "offset": 2})
	assert_eq(s, [Vector2i(2, 5), Vector2i(2, 4), Vector2i(3, 5), Vector2i(3, 4)])
	var w := RoomDefs.door_zone(room, {"wall": "W", "offset": 1})
	assert_eq(w, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)])
	var e := RoomDefs.door_zone(room, {"wall": "E", "offset": 1})
	assert_eq(e, [Vector2i(7, 1), Vector2i(6, 1), Vector2i(7, 2), Vector2i(6, 2)])


func test_wall_door_spans() -> void:
	var room := RoomDefs.room("living")
	var spans := RoomDefs.wall_door_spans(room)
	assert_eq(spans["N"], [[2, 4]], "Küchen-Tür N offset 2")
	assert_eq(spans["W"], [[4, 6]])
	assert_eq(spans["E"], [[5, 7]])


func test_zugebaute_tuer_wird_erkannt() -> void:
	var room := RoomDefs.room("kitchen")
	var grid := RoomDefs.make_grid("kitchen")
	var door := RoomDefs.door("kitchen", "kueche_living")
	var zone := RoomDefs.door_zone(room, door)
	var gooby_cell := Vector2i(7, 6)
	assert_true(grid.is_zone_reachable(gooby_cell, zone), "leerer Raum: Tür erreichbar")
	# Sofa-Riegel quer vor die Türzone (x=2, y=0..7 via zwei rotierte Sofas).
	assert_true(grid.place(_sofa(), Vector2i(2, 0), 1, "r1")["ok"])
	assert_true(grid.place(_sofa(), Vector2i(2, 4), 1, "r2")["ok"])
	assert_false(grid.is_zone_reachable(gooby_cell, zone), "Riegel blockt → Gag-Trigger")
	grid.remove_item("r2")
	assert_true(grid.is_zone_reachable(gooby_cell, zone), "Lücke → wieder erreichbar")


func test_gooby_in_der_falle_bleibt_erkennbar() -> void:
	var grid := GridData.new(Vector2i(6, 6), [Vector2i(0, 0)])
	assert_true(grid.place(_sofa(), Vector2i(0, 1), 1, "w1")["ok"], "Wand unter Zone")
	assert_true(grid.place(_sofa(), Vector2i(2, 0), 0, "w2")["ok"], "Wand rechts der Zone")
	assert_false(grid.is_zone_reachable(Vector2i(4, 4), [Vector2i(0, 0)]), "Ecke abgeriegelt")
	assert_true(grid.is_zone_reachable(Vector2i(0, 0), [Vector2i(0, 0)]), "in der Zone selbst")


func test_unbegehbares_ziel_und_start() -> void:
	var grid := GridData.new(Vector2i(4, 4))
	grid.place(_sofa(), Vector2i(0, 0), 0, "s")
	assert_false(grid.is_reachable(Vector2i(0, 0), Vector2i(3, 3)), "Start im Möbel")
	assert_false(grid.is_reachable(Vector2i(3, 3), Vector2i(1, 1)), "Ziel im Möbel")
	assert_true(grid.is_reachable(Vector2i(3, 3), Vector2i(3, 3)), "Ziel = Start")
