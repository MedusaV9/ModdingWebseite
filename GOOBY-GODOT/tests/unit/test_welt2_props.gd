extends TestCase
## WELT2 (User: „Warum ist so vieles keine richtigen Assets sondern nur
## Primitives?"): die selbstgebauten Blender-GLBs in assets/props/ laden,
## haben plausible Maße (Ursprung am Boden, Größe passt in den Raum) und
## die Godot-Seite (HomeProps, RoomDeko) hängt sie korrekt ein — inkl.
## weicher Degradation, wenn ein Asset fehlt.

## Alle 23 Eigenbau-Props aus tools/blender/props/build_props.sh.
const EIGENE_PROPS: Array[String] = [
	"tuer_zarge",
	"tuer_blatt",
	"fenster_rahmen_1",
	"fenster_rahmen_2",
	"fenster_rahmen_3",
	"duschvorhang",
	"duschkopf",
	"heizkoerper",
	"lichtschalter",
	"steckdose",
	"bilderrahmen",
	"shed_l1",
	"shed_l2",
	"shed_l3",
	"werkstatt",
	"gewaechshaus",
	"sprinkler",
	"werkbank",
	"sammel_stock",
	"sammel_blatt",
	"pflanze_tomate",
	"pflanze_chili",
	"pflanze_ananas",
]

## Kenney-Crops (CC0), die WELT2 zusätzlich ins Repo geholt hat.
const KENNEY_CROPS: Array[String] = [
	"res://assets/furniture/garten/crop_carrot.glb",
	"res://assets/furniture/garten/crop_melon.glb",
	"res://assets/furniture/garten/crops_leafsStageA.glb",
	"res://assets/furniture/garten/crops_leafsStageB.glb",
	"res://assets/furniture/garten/mushroom_red.glb",
]


func test_alle_eigenbau_glbs_laden() -> void:
	for prop_name in EIGENE_PROPS:
		var node := HomeProps.prop_glb(prop_name)
		assert_true(node != null, "%s.glb lädt" % prop_name)
		if node == null:
			continue
		var aabb := HomeProps.merged_aabb(node, Transform3D.IDENTITY)
		assert_true(aabb.size.length() > 0.01, "%s hat sichtbare Meshes" % prop_name)
		node.free()


func test_prop_glb_fehlt_gibt_null() -> void:
	assert_eq(HomeProps.prop_glb("gibt_es_nicht"), null, "fehlendes Asset degradiert weich")


func test_tuer_glbs_passen_in_die_zarge() -> void:
	# Türöffnung im Spiel: 1,0 m breit, 2,0 m hoch (door_transition.gd).
	var zarge := HomeProps.prop_glb("tuer_zarge")
	var zarge_box := HomeProps.merged_aabb(zarge, Transform3D.IDENTITY)
	assert_true(zarge_box.size.x >= 1.0 and zarge_box.size.x <= 1.5, "Zarge umschließt 1 m")
	assert_true(zarge_box.size.y >= 1.9 and zarge_box.size.y <= 2.4, "Zarge ~2 m hoch")
	assert_true(zarge_box.position.y >= -0.05, "Zarge steht auf dem Boden")
	zarge.free()
	var blatt := HomeProps.prop_glb("tuer_blatt")
	var blatt_box := HomeProps.merged_aabb(blatt, Transform3D.IDENTITY)
	assert_true(blatt_box.size.x <= zarge_box.size.x, "Blatt schmaler als Zarge")
	assert_true(blatt_box.size.y >= 1.7 and blatt_box.size.y <= 2.1, "Blatt ~1,9 m hoch")
	blatt.free()


func test_fensterrahmen_breiten_stimmen() -> void:
	# Fensteröffnung = Zellen × 0,5 m; der Rahmen liegt knapp darüber.
	for zellen: int in [1, 2, 3]:
		var rahmen := HomeProps.prop_glb("fenster_rahmen_%d" % zellen)
		var aabb := HomeProps.merged_aabb(rahmen, Transform3D.IDENTITY)
		var oeffnung := zellen * 0.5
		assert_true(
			aabb.size.x >= oeffnung and aabb.size.x <= oeffnung + 0.4,
			"Rahmen %d: Breite %.2f passt zu %.1f m Öffnung" % [zellen, aabb.size.x, oeffnung]
		)
		rahmen.free()


func test_fenster_modul_nutzt_glb_rahmen() -> void:
	var fenster := HomeProps.fenster(2, true)
	var rahmen_da := false
	var glas_da := false
	for child in fenster.get_children():
		if str(child.name).contains("Prop_fenster_rahmen_2"):
			rahmen_da = true
		if str(child.name) == "Glas":
			glas_da = true
	assert_true(rahmen_da, "Fenster nutzt den Blender-Rahmen")
	assert_true(glas_da, "Glasscheibe bleibt prozedural (Alpha variiert)")
	fenster.free()


func test_garten_props_nutzen_glbs() -> void:
	var kandidaten := {
		"shed": HomeProps.shed(2),
		"werkstatt": HomeProps.werkstatt(),
		"gewaechshaus": HomeProps.gewaechshaus(Vector3.ZERO),
		"sprinkler": HomeProps.sprinkler(),
		"werkbank": HomeProps.werkbank(),
		"sammel_stock": HomeProps.sammel_spot("stock"),
		"sammel_blatt": HomeProps.sammel_spot("blatt"),
	}
	for id: String in kandidaten:
		var node: Node3D = kandidaten[id]
		assert_true(_hat_prop_glb(node), "%s kommt als Blender-GLB" % id)
		node.free()


func test_kenney_crops_vorhanden() -> void:
	for pfad in KENNEY_CROPS:
		assert_true(ResourceLoader.exists(pfad), "%s ist importiert" % pfad)


func test_pflanze_fuer_jede_sorte() -> void:
	# Alle 7 Sorten aus garden_crops.json haben ein echtes Modell.
	for crop_id: String in ["carrot", "melone", "pilz", "salat", "tomate", "chili", "ananas"]:
		for anteil: float in [0.3, 1.0]:
			var pflanze := HomeProps.pflanze(crop_id, anteil)
			assert_true(pflanze != null, "%s (%.1f) hat ein Modell" % [crop_id, anteil])
			if pflanze == null:
				continue
			var aabb := HomeProps.merged_aabb(pflanze, Transform3D.IDENTITY)
			assert_true(
				aabb.size.y > 0.02 and aabb.size.y < 0.9,
				"%s (%.1f): Höhe %.2f passt ins Beet" % [crop_id, anteil, aabb.size.y]
			)
			assert_true(
				aabb.position.y >= -0.05,
				"%s: Ursprung am Boden (y=%.2f)" % [crop_id, aabb.position.y]
			)
			pflanze.free()


func test_modell_glb_skaliert_auf_zielhoehe() -> void:
	var node := HomeProps.modell_glb("res://assets/furniture/garten/crop_carrot.glb", 0.3)
	assert_true(node != null)
	var aabb := HomeProps.merged_aabb(node, Transform3D.IDENTITY)
	assert_almost(aabb.size.y, 0.3, 0.02, "Bounding-Box auf Zielhöhe skaliert")
	assert_almost(aabb.position.y, 0.0, 0.02, "Unterkante auf y=0")
	assert_almost(aabb.get_center().x, 0.0, 0.02, "x-zentriert")
	node.free()


func test_room_deko_platziert_wanddeko() -> void:
	var mount := Node3D.new()
	tree.root.add_child(mount)
	var room_def := {
		"id": "living",
		"grid": Vector2i(8, 6),
		"doors": [{"wall": "S", "offset": 3}],
		"windows": [{"wall": "N", "offset": 5, "size": 2}],
	}
	var belegte := {"S": [[3, 3 + RoomDefs.DOOR_WIDTH]]}
	RoomDeko.anbringen(mount, room_def, belegte)
	var deko: Node3D = mount.get_node("RaumDeko")
	assert_true(deko != null, "RaumDeko-Node hängt am Mount")
	assert_true(_zaehle(deko, "Prop_lichtschalter") >= 1, "Schalter neben der Tür")
	assert_true(_zaehle(deko, "Prop_steckdose") >= 1, "mindestens eine Steckdose")
	assert_eq(_zaehle(deko, "Prop_heizkoerper"), 1, "Heizkörper unterm Fenster")
	assert_eq(_zaehle(deko, "Prop_bilderrahmen"), 1, "Bilderrahmen im Wohnzimmer")
	# Der Heizkörper sitzt mittig unter dem Fenster (Zellen 5..7 → 3,0 m).
	for child: Node3D in deko.get_children():
		if str(child.name).contains("Prop_heizkoerper"):
			assert_almost(child.position.x, 3.0, 0.01, "Heizkörper fenstermittig")
	mount.free()


func test_room_deko_meidet_moebel_und_fremde_raeume() -> void:
	var mount := Node3D.new()
	tree.root.add_child(mount)
	var grid := RoomDefs.make_grid("kitchen")
	var room_def := {
		"id": "kitchen",
		"grid": grid.size,
		"doors": [],
		"windows": [{"wall": "N", "offset": 4, "size": 2}],
	}
	# Möbel direkt vor die Fensterwand stellen → kein Heizkörper (Clipping).
	var chair := FurnitureCatalog.def("chair")
	assert_true(grid.place(chair, Vector2i(4, 0), 0, "welt2-test")["ok"], "Stuhl vor dem Fenster")
	RoomDeko.anbringen(mount, room_def, {}, grid)
	var deko: Node3D = mount.get_node("RaumDeko")
	assert_eq(_zaehle(deko, "Prop_heizkoerper"), 0, "kein Heizkörper im Möbel")
	assert_eq(_zaehle(deko, "Prop_bilderrahmen"), 0, "kein Bilderrahmen in der Küche")
	mount.free()


func test_room_deko_ohne_glbs_kein_crash() -> void:
	# Simuliert fehlende Assets nicht direkt (Loader-Cache), aber prüft den
	# leeren Grenzfall: Raum ohne Türen/Fenster bekommt nur Steckdosen/Bild.
	var mount := Node3D.new()
	tree.root.add_child(mount)
	RoomDeko.anbringen(mount, {"id": "bathroom", "grid": Vector2i(6, 6)}, {})
	var deko: Node3D = mount.get_node("RaumDeko")
	assert_eq(_zaehle(deko, "Prop_lichtschalter"), 0, "keine Tür → kein Schalter")
	assert_eq(_zaehle(deko, "Prop_heizkoerper"), 0, "kein Fenster → kein Heizkörper")
	mount.free()


func _hat_prop_glb(node: Node) -> bool:
	if str(node.name).begins_with("Prop_"):
		return true
	for child in node.get_children():
		if _hat_prop_glb(child):
			return true
	return false


func _zaehle(deko: Node3D, praefix: String) -> int:
	var n := 0
	for child in deko.get_children():
		if str(child.name).contains(praefix):
			n += 1
	return n
