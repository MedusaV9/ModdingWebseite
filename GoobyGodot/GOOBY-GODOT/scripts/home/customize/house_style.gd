class_name HouseStyle
extends RefCounted
## Anwendungs-Schnittstelle des Gestalten-Modus (HAUS-CUSTOM). Der Raum-/
## Außenbau gehört einem anderen Agenten (`room_base.gd`/`home_props.gd`) —
## deshalb passiert die Anwendung hier über zwei Funktionen, die der
## Raum-Besitzer einhängt (Handoff: HAUSCUSTOM-room-request.md):
##
##   HouseStyle.apply_to_room(room, HouseStyleState.style(gs))
##   HouseStyle.apply_to_exterior(haus_node, HouseStyleState.style(gs))
##
## `apply_to_room` verlässt sich NUR auf die stabilen Node-Namen von
## RoomBase („Walls"/„Wall_*", „NavRegion/Floor", „BodenFugen") und setzt
## material_override — kein Umbau fremder Szenen. Innenräume bekommen
## Wand/Boden des Raums, der Garten (outdoor) Grundstücks-Boden + Zaunfarbe.
## Rückgabewert = Anzahl umgestellter Meshes (Tests messen darüber).

const WALL_PREFIX := "Wall_"


## Bequemer Einstieg: Stil direkt aus dem GameState lesen und anwenden.
static func style_of(gs: Object) -> Dictionary:
	return HouseStyleState.style(gs)


## Wände + Boden eines RoomBase-Raums nach `style` umstellen.
static func apply_to_room(room: Node, style: Dictionary) -> int:
	if room == null:
		return 0
	var room_id := str(room.get("room_id"))
	var outdoor := bool(RoomDefs.room(room_id).get("outdoor", false))
	var geaendert := 0
	var boden_material: Material
	var wand_material: Material
	if outdoor:
		var grund: Dictionary = style.get("grundstueck", CustomizeCatalog.default_grundstueck())
		boden_material = HouseExterior.teil_material("grund", style)
		wand_material = CustomizeMaterials.flat(str(grund.get("zaunFarbe", "eiche")))
	else:
		var raum := _raum_style(style, room_id)
		boden_material = flaechen_material("boden", raum)
		wand_material = flaechen_material("wand", raum)
	var floor_mesh := room.find_child("Floor", true, false)
	if floor_mesh is MeshInstance3D:
		(floor_mesh as MeshInstance3D).material_override = boden_material
		geaendert += 1
	geaendert += _apply_walls(room, wand_material)
	# Die Fugen-Deko von RoomBase gehört zur alten Farbplatte — die Muster
	# bringen ihre eigenen Fugen mit.
	var fugen := room.find_child("BodenFugen", true, false)
	if fugen is Node3D:
		(fugen as Node3D).visible = false
	return geaendert


## Haus-Außenmodell (HouseExterior.build) umfärben, ohne neu zu bauen.
## STRUKTUR-Wechsel (Dachform/Varianten/Weg/Zaun-Stil) brauchen stattdessen
## einen frischen `HouseExterior.build(style)`.
static func apply_to_exterior(node: Node, style: Dictionary) -> int:
	if node == null:
		return 0
	var geaendert := 0
	var haus: Dictionary = style.get("haus", CustomizeCatalog.default_haus())
	for kind: Node in _mit_meta(node):
		var teil := str(kind.get_meta(HouseExterior.META))
		if teil == "hausnummer_text" and kind is Label3D:
			(kind as Label3D).text = str(int(haus.get("hausnummerZahl", 5)))
			geaendert += 1
			continue
		var material := HouseExterior.teil_material(teil, style)
		if material == null:
			continue
		if kind is MeshInstance3D:
			(kind as MeshInstance3D).material_override = material
			geaendert += 1
		elif kind is MultiMeshInstance3D:
			var multi: MultiMesh = (kind as MultiMeshInstance3D).multimesh
			if multi != null and multi.mesh is BoxMesh:
				(multi.mesh as BoxMesh).material = material
				geaendert += 1
	return geaendert


## Geteiltes Material für eine Raumfläche (art ∈ {wand, boden}) aus einem
## Raum-Style ({wand, wandFarbe, boden, bodenFarbe}) — auch für die Vorschau.
static func flaechen_material(art: String, raum: Dictionary) -> Material:
	var id := str(raum.get(art, ""))
	var def := CustomizeCatalog.def(art, id)
	var muster := str(def.get("muster", "uni"))
	return CustomizeMaterials.surface(muster, str(raum.get("%sFarbe" % art, "creme")))


static func _raum_style(style: Dictionary, room_id: String) -> Dictionary:
	var raeume: Dictionary = style.get("raeume", {})
	var raw: Variant = raeume.get(room_id)
	if raw is Dictionary:
		return raw
	return CustomizeCatalog.raum_default(room_id)


static func _apply_walls(room: Node, material: Material) -> int:
	var walls := room.find_child("Walls", true, false)
	if walls == null:
		return 0
	var geaendert := 0
	for kind in walls.get_children():
		if kind is MeshInstance3D and str(kind.name).begins_with(WALL_PREFIX):
			(kind as MeshInstance3D).material_override = material
			geaendert += 1
	return geaendert


static func _mit_meta(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node.has_meta(HouseExterior.META):
		out.append(node)
	for kind in node.get_children():
		out.append_array(_mit_meta(kind))
	return out
