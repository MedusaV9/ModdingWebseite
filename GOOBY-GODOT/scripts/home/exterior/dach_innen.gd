class_name DachInnen
extends Node3D
## Dach-Andeutung IM Raum (HAUS-SICHT, User: „das Dach über sich spüren").
## Erdgeschoss-Räume (HouseLayout.etage 0) bekommen Deckenbalken über der
## Wandkrone, Dachgeschoss-Räume (etage 1) eine Dachschräge über der
## Außenwand (Nord) mit Sparren darunter — außer der Spieler hat im
## Gestalten-Modus ein Flachdach gewählt: dann gibt es überall Balken.
##
## Bewusst dünn/hoch genug, dass weder die Schräg- noch die Draufsicht-
## Kamera den Raum verliert; im Baumodus versteckt RoomBase das Ganze.

const BALKEN_DICKE := 0.13
const BALKEN_ABSTAND := 1.15
## Dachschräge: so tief ragt sie von der Nordwand in den Raum …
const SCHRAEGE_TIEFE := 1.15
## … und so hoch steigt sie dabei an.
const SCHRAEGE_HUB := 0.85
const SPARREN_ABSTAND := 1.4

var _schraege := false


## Ans RoomBase hängen (nur Innenräume; idempotent).
static func attach_to(room: Node) -> DachInnen:
	var room_def: Dictionary = room.room_def()
	if bool(room_def.get("outdoor", false)):
		return null
	var vorhanden := room.get_node_or_null("DachInnen")
	if vorhanden is DachInnen:
		return vorhanden
	var dach := DachInnen.new()
	dach.name = "DachInnen"
	var room_id := str(room.get("room_id"))
	var groesse: Vector2i = room_def.get("grid", Vector2i(8, 8))
	var welt := Vector2(groesse.x * GridData.CELL_SIZE, groesse.y * GridData.CELL_SIZE)
	dach.baue(room_id, welt, HouseStyleState.style(room.game_state()))
	room.add_child(dach)
	return dach


func baue(room_id: String, welt: Vector2, style: Dictionary) -> void:
	var haus: Dictionary = style.get("haus", CustomizeCatalog.default_haus())
	var dach_form := str(haus.get("dachForm", "sattel"))
	_schraege = HouseLayout.etage(room_id) == 1 and dach_form != "flach"
	if _schraege:
		_baue_schraege(welt)
	_baue_balken(welt)


## Hat dieser Raum eine sichtbare Dachschräge? (Tests)
func hat_schraege() -> bool:
	return _schraege


## Deckenbalken quer über den Raum (EIN MultiMesh). Im Dachgeschoss werden
## es Kehlbalken auf Schrägen-Höhe, im Erdgeschoss liegen sie auf der
## Wandkrone.
func _baue_balken(welt: Vector2) -> void:
	var hoehe := RoomBase.WALL_HEIGHT + BALKEN_DICKE * 0.5 + 0.02
	if _schraege:
		hoehe += SCHRAEGE_HUB * 0.55
	var transforms: Array[Transform3D] = []
	var z := BALKEN_ABSTAND
	while z < welt.y - 0.2:
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(welt.x * 0.5, hoehe, z)))
		z += BALKEN_ABSTAND
	var mesh := BoxMesh.new()
	mesh.size = Vector3(welt.x + 0.16, BALKEN_DICKE, BALKEN_DICKE)
	mesh.material = CustomizeMaterials.flat("nussbaum")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instanz := MultiMeshInstance3D.new()
	instanz.name = "Deckenbalken"
	instanz.multimesh = multi
	instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instanz)


## Dachschräge über der Nordwand (Außenwand): Holzuntersicht, die von der
## Wandkrone in den Raum hinein ansteigt, mit Sparren darunter.
func _baue_schraege(welt: Vector2) -> void:
	var winkel := atan2(SCHRAEGE_HUB, SCHRAEGE_TIEFE)
	var laenge := sqrt(SCHRAEGE_TIEFE * SCHRAEGE_TIEFE + SCHRAEGE_HUB * SCHRAEGE_HUB)
	var platte := MeshInstance3D.new()
	platte.name = "Dachschraege"
	var box := BoxMesh.new()
	box.size = Vector3(welt.x + 0.16, 0.07, laenge)
	platte.mesh = box
	platte.material_override = CustomizeMaterials.flat("eiche_hell")
	platte.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Um X kippen: Nordkante (z=0) liegt auf der Wandkrone, die Innenkante
	# steigt Richtung Raummitte an.
	platte.rotation.x = -winkel
	platte.position = Vector3(
		welt.x * 0.5, RoomBase.WALL_HEIGHT + SCHRAEGE_HUB * 0.5, SCHRAEGE_TIEFE * 0.5
	)
	add_child(platte)
	var transforms: Array[Transform3D] = []
	var x := SPARREN_ABSTAND * 0.5
	while x < welt.x - 0.1:
		var basis := Basis(Vector3.RIGHT, -winkel)
		transforms.append(
			Transform3D(
				basis,
				Vector3(x, RoomBase.WALL_HEIGHT + SCHRAEGE_HUB * 0.5 - 0.09, SCHRAEGE_TIEFE * 0.5)
			)
		)
		x += SPARREN_ABSTAND
	var sparren_mesh := BoxMesh.new()
	sparren_mesh.size = Vector3(0.11, 0.11, laenge)
	sparren_mesh.material = CustomizeMaterials.flat("nussbaum")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = sparren_mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var sparren := MultiMeshInstance3D.new()
	sparren.name = "Sparren"
	sparren.multimesh = multi
	sparren.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparren)
