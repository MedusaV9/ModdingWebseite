extends TestCase
## HAUS-CUSTOM — Anwendung ändert Material MESSBAR: apply_to_room stellt
## Boden/Wände eines RoomBase-förmigen Baums um (stabile Node-Namen), das
## Außenmodell (HouseExterior) wird gebaut und über apply_to_exterior
## umgefärbt (inkl. Hausnummern-Text). Kein fremder Code nötig.

const GameStateScript := preload("res://scripts/state/game_state.gd")

## Minimaler Stellvertreter für RoomBase (gehört einem anderen Agenten):
## nur die stabile Struktur, auf die sich apply_to_room verlässt.
const RAUM_ATTRAPPE := """
extends Node3D
var room_id := \"living\"
"""


func _raum_attrappe(room_id: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = RAUM_ATTRAPPE
	script.reload()
	var raum: Node3D = script.new()
	raum.set("room_id", room_id)
	var walls := Node3D.new()
	walls.name = "Walls"
	raum.add_child(walls)
	for wand_name: String in ["Wall_N_0_12_0", "Wall_W_0_10_0", "Wall_E_0_10_0"]:
		var wand := MeshInstance3D.new()
		wand.name = wand_name
		walls.add_child(wand)
	var deko := MeshInstance3D.new()
	deko.name = "Fensterbank"
	walls.add_child(deko)
	var nav := Node3D.new()
	nav.name = "NavRegion"
	raum.add_child(nav)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	nav.add_child(floor_mesh)
	var fugen := Node3D.new()
	fugen.name = "BodenFugen"
	raum.add_child(fugen)
	return raum


func test_apply_to_room_stellt_flaechen_um() -> void:
	var raum := _raum_attrappe("living")
	var style := HouseStyleState.normalize(
		{
			"raeume":
			{
				"living":
				{"wand": "uni", "wandFarbe": "mint", "boden": "teppich", "bodenFarbe": "rose"}
			}
		}
	)
	var geaendert := HouseStyle.apply_to_room(raum, style)
	assert_eq(geaendert, 4, "Boden + 3 Wände umgestellt, Deko nicht")
	var floor_mesh: MeshInstance3D = raum.find_child("Floor", true, false)
	var boden_mat := floor_mesh.material_override as ShaderMaterial
	assert_true(boden_mat != null, "Boden bekommt Umfärbe-ShaderMaterial")
	assert_eq(
		boden_mat.get_shader_parameter("tint"), CustomizeMaterials.farbe("rose"), "Teppich rosa"
	)
	var wand: MeshInstance3D = raum.find_child("Wall_N_0_12_0", true, false)
	var wand_mat := wand.material_override as ShaderMaterial
	assert_eq(wand_mat.get_shader_parameter("tint"), CustomizeMaterials.farbe("mint"), "Wand mint")
	var deko: MeshInstance3D = raum.find_child("Fensterbank", true, false)
	assert_true(deko.material_override == null, "fremde Deko bleibt unangetastet")
	assert_false(
		(raum.find_child("BodenFugen", true, false) as Node3D).visible,
		"alte Fugen-Deko versteckt (Muster bringen eigene Fugen mit)"
	)
	# Messbare ÄNDERUNG: anderer Stil ⇒ anderes Material.
	var style2 := HouseStyleState.normalize(
		{"raeume": {"living": {"boden": "stein", "bodenFarbe": "grau"}}}
	)
	HouseStyle.apply_to_room(raum, style2)
	assert_ne(floor_mesh.material_override, boden_mat, "Bodenwechsel ändert das Material")
	raum.free()


func test_apply_to_room_outdoor_nutzt_grundstueck() -> void:
	var garten := _raum_attrappe("garden")
	var style := HouseStyleState.normalize(
		{"grundstueck": {"boden": "sand", "bodenFarbe": "butter", "zaunFarbe": "teal"}}
	)
	var geaendert := HouseStyle.apply_to_room(garten, style)
	assert_true(geaendert >= 4, "Garten: Boden + Zaunwände umgestellt")
	var floor_mesh: MeshInstance3D = garten.find_child("Floor", true, false)
	var mat := floor_mesh.material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("tint"), CustomizeMaterials.farbe("butter"), "Sandfarbe")
	garten.free()


func test_exterior_build_und_umfaerben() -> void:
	var style := (
		HouseStyleState
		. normalize(
			{
				"haus": {"fassade": "himmel", "dachForm": "sattel", "hausnummerZahl": 7},
				"grundstueck": {"weg": "platten", "zaun": "latten"},
			}
		)
	)
	var haus := HouseExterior.build(style)
	assert_true(haus.find_child("Fassade", true, false) != null, "Fassade gebaut")
	assert_true(haus.find_child("Dach", true, false).get_child_count() > 0, "Dach gebaut")
	assert_true(haus.find_child("Weg", true, false) != null, "Weg gebaut")
	assert_true(haus.find_child("Zaun", true, false) != null, "Zaun gebaut")
	var fassade: MeshInstance3D = haus.find_child("Fassade", true, false)
	var vorher := fassade.material_override as ShaderMaterial
	assert_eq(
		vorher.get_shader_parameter("tint"), CustomizeMaterials.farbe("himmel"), "Fassade blau"
	)
	var zahl: Label3D = haus.find_child("Zahl", true, false)
	assert_eq(zahl.text, "7", "Hausnummer im Schild")
	# Umfärben ohne Neubau (apply_to_exterior) — messbar anderes Material.
	style["haus"]["fassade"] = "terracotta"
	style["haus"]["hausnummerZahl"] = 42
	var geaendert := HouseStyle.apply_to_exterior(haus, style)
	assert_true(geaendert >= 8, "viele Teile umgefärbt (%d)" % geaendert)
	var nachher := fassade.material_override as ShaderMaterial
	assert_ne(nachher, vorher, "Fassadenwechsel ändert das Material")
	assert_eq(
		nachher.get_shader_parameter("tint"),
		CustomizeMaterials.farbe("terracotta"),
		"neue Fassadenfarbe sitzt"
	)
	assert_eq(zahl.text, "42", "Hausnummern-Text nachgezogen")
	haus.free()


func test_exterior_dachformen_und_varianten() -> void:
	for form: String in ["sattel", "walm", "flach"]:
		var style := HouseStyleState.normalize({"haus": {"dachForm": form}})
		var haus := HouseExterior.build(style)
		var dach: Node3D = haus.find_child("Dach", true, false)
		assert_true(dach.get_child_count() > 0, "Dachform %s baut Geometrie" % form)
		haus.free()
	var ohne := HouseExterior.build(
		HouseStyleState.normalize({"grundstueck": {"weg": "keins", "zaun": "keins"}})
	)
	assert_true(ohne.find_child("Weg", true, false) == null, "kein Weg gebaut")
	assert_true(ohne.find_child("Zaun", true, false) == null, "kein Zaun gebaut")
	ohne.free()
	var markise := HouseExterior.build(
		HouseStyleState.normalize({"haus": {"vordach": "markise", "vordachFarbe": "teal"}})
	)
	assert_true(markise.find_child("Vordach", true, false) != null, "Markise gebaut")
	markise.free()


func test_flaechen_material_teilt_instanzen() -> void:
	var raum_a := {"wand": "uni", "wandFarbe": "mint", "boden": "teppich", "bodenFarbe": "rose"}
	var raum_b := raum_a.duplicate()
	var mat_a := HouseStyle.flaechen_material("wand", raum_a)
	var mat_b := HouseStyle.flaechen_material("wand", raum_b)
	assert_eq(mat_a, mat_b, "gleiches Muster+Farbe = EIN geteiltes Material (Mobile-Budget)")
	assert_ne(
		HouseStyle.flaechen_material("boden", raum_a), mat_a, "andere Fläche = anderes Material"
	)
