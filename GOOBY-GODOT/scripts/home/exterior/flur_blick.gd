class_name FlurBlick
extends Node3D
## Angedeuteter Nachbarraum HINTER einer Tür (HAUS-SICHT, User: „bei Räumen
## den Rest des Hauses sehen"). Eine kleine Nische außerhalb der Wand —
## Boden, Rückwand, Seitenwände — in den Farben des ZIELRAUMS (rooms.json),
## damit beim Türöffnen glaubhaft „die Küche" oder „das Wohnzimmer"
## dahinterliegt. Konsistenz kommt gratis: Farben sind dieselben, die der
## Zielraum wirklich benutzt.
##
## Bewusst billig: 4 Boxen + Bild, kein Licht, kein eigenes _process.

const TIEFE := 1.35
const HOEHE := 2.25
const WAND_DICKE := 0.09
## Zielraum-Farben werden leicht abgedunkelt — der Flur liegt im Schatten.
const SCHATTEN := 0.16


## Nischen für ALLE Türen eines Innenraums bauen (RoomBase ruft das).
static func attach_to(room: Node) -> FlurBlick:
	var room_def: Dictionary = room.room_def()
	if bool(room_def.get("outdoor", false)):
		return null
	var vorhanden := room.get_node_or_null("FlurBlick")
	if vorhanden is FlurBlick:
		return vorhanden
	var blick := FlurBlick.new()
	blick.name = "FlurBlick"
	for door_def: Dictionary in room_def.get("doors", []):
		blick.add_child(blick.nische(room_def, door_def))
	room.add_child(blick)
	return blick


## Eine Nische hinter einer Tür — lokal zeigt +z in den Raum (wie bei
## DoorTransition), die Nische liegt bei -z hinter der Wand.
func nische(room_def: Dictionary, door_def: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Nische_%s" % str(door_def.get("id", ""))
	wurzel.position = RoomDefs.door_world_pos(room_def, door_def)
	var inward := RoomDefs.wall_inward(str(door_def.get("wall", "N")))
	wurzel.rotation.y = atan2(inward.x, inward.z)
	var ziel := RoomDefs.room(str(door_def.get("to", "")))
	var boden_farbe: Color = ziel.get("floor_color", Color("#C9A36B"))
	var wand_farbe: Color = ziel.get("wall_color", Color("#FFF6EC"))
	var breite := RoomDefs.DOOR_WIDTH * GridData.CELL_SIZE + 0.7
	var boden := _box(Vector3(breite, 0.08, TIEFE), boden_farbe.darkened(SCHATTEN * 0.6), "Boden")
	boden.position = Vector3(0.0, -0.04, -RoomBase.WALL_THICKNESS - TIEFE * 0.5)
	wurzel.add_child(boden)
	var rueck := _box(
		Vector3(breite, HOEHE, WAND_DICKE), wand_farbe.darkened(SCHATTEN), "Rueckwand"
	)
	rueck.position = Vector3(0.0, HOEHE * 0.5, -RoomBase.WALL_THICKNESS - TIEFE + WAND_DICKE * 0.5)
	wurzel.add_child(rueck)
	for seite: float in [-1.0, 1.0]:
		var wand := _box(Vector3(WAND_DICKE, HOEHE, TIEFE), wand_farbe.darkened(SCHATTEN), "Seite")
		wand.position = Vector3(
			seite * (breite - WAND_DICKE) * 0.5, HOEHE * 0.5, -RoomBase.WALL_THICKNESS - TIEFE * 0.5
		)
		wurzel.add_child(wand)
	var bild := _box(Vector3(0.5, 0.38, 0.03), boden_farbe.lightened(0.25), "Bild")
	bild.position = Vector3(0.0, 1.45, -RoomBase.WALL_THICKNESS - TIEFE + WAND_DICKE + 0.02)
	wurzel.add_child(bild)
	return wurzel


func _box(size: Vector3, farbe: Color, box_name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 1.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
