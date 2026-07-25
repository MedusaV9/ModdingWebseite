class_name StreetDiorama
extends Node3D
## Fenster-Diorama (Doc D §1.2, USER §D43): hinter jeder Außenwand mit
## Fenster steht EIN geteiltes Mini-Diorama — Straße, Bordstein, zwei
## Nachbarhäuser und 2–3 Autos, die gemächlich vorbeifahren.
##
## Bewusst billig: keine Portal-Shader, kein Wand-CSG, keine Physik. Das
## Diorama wird NUR aufgebaut, wenn im Raum wirklich ein Fenster hängt
## (`RoomBase` ruft `attach_if_needed`), und liegt außerhalb der Wand, wo es
## nur durch die Fensterscheibe zu sehen ist.

## Vista-Ids (Doc D §1.2) — "strasse" hat Verkehr, "garten" nur Grün.
const VISTA_STRASSE := "strasse"
## So weit hinter der Wand liegt das Diorama.
const TIEFE := 3.2
## Fahrbreite und Tempo der Autos.
const STRASSE_LAENGE := 22.0
const AUTO_TEMPO := 2.1
const AUTO_GLB := "res://assets/city/autos/sedan.glb"

var vista := VISTA_STRASSE

var _autos: Array[Node3D] = []
var _laenge := STRASSE_LAENGE


## Baut das Diorama für `wall` hinter einem Raum der Größe `world_size`,
## wenn dort ein Fenster hängt. Liefert das Diorama oder null.
static func attach_if_needed(
	room: Node3D, grid: GridData, world_size: Vector2, wall: String, vista_id: String
) -> StreetDiorama:
	if not _hat_fenster(grid, wall):
		return null
	var diorama := StreetDiorama.new()
	diorama.name = "Diorama_%s" % wall
	diorama.vista = vista_id
	diorama._laenge = maxf(STRASSE_LAENGE, maxf(world_size.x, world_size.y) * 2.5)
	room.add_child(diorama)
	diorama.position = _diorama_position(wall, world_size)
	diorama.rotation.y = _diorama_yaw(wall)
	return diorama


## Hängt an dieser Wand mindestens ein Fenster (WALL-Item mit `exterior`)?
static func _hat_fenster(grid: GridData, wall: String) -> bool:
	for offset in grid.wall_width(wall):
		var uid := grid.wall_item_at(wall, offset)
		if uid == "":
			continue
		if bool(grid.get_item(uid).get("def", {}).get("exterior", false)):
			return true
	return false


func _ready() -> void:
	_build_kulisse()
	if vista == VISTA_STRASSE:
		_build_autos()


func _process(delta: float) -> void:
	if _autos.is_empty():
		return
	for auto in _autos:
		auto.position.x += AUTO_TEMPO * delta * (1.0 if auto.rotation.y == 0.0 else -1.0)
		if absf(auto.position.x) > _laenge * 0.5:
			auto.position.x = -sign(auto.position.x) * _laenge * 0.5


func _build_kulisse() -> void:
	var himmel := HomeProps.box(Vector3(_laenge, 6.0, 0.1), "glas")
	himmel.position = Vector3(0.0, 2.4, -2.2)
	add_child(himmel)
	var boden_farbe := "metall" if vista == VISTA_STRASSE else "blatt"
	var boden := HomeProps.box(Vector3(_laenge, 0.1, 4.0), boden_farbe)
	boden.position = Vector3(0.0, -0.05, 0.0)
	add_child(boden)
	if vista == VISTA_STRASSE:
		_build_strasse()
		return
	for i in 5:
		var busch := HomeProps.box(Vector3(0.7, 0.7, 0.7), "blatt")
		busch.position = Vector3(-4.0 + i * 2.0, 0.35, -0.6)
		add_child(busch)


func _build_strasse() -> void:
	var bordstein := HomeProps.box(Vector3(_laenge, 0.16, 0.5), "anstrich")
	bordstein.position = Vector3(0.0, 0.08, 1.6)
	add_child(bordstein)
	var strich_zahl := int(_laenge / 2.0)
	for i in strich_zahl:
		var strich := HomeProps.box(Vector3(0.7, 0.02, 0.1), "rahmen")
		strich.position = Vector3(-_laenge * 0.5 + 1.0 + i * 2.0, 0.06, 0.0)
		add_child(strich)
	# Die Häuser bleiben unter RoomBase.WALL_HEIGHT, sonst lugen ihre Dächer
	# von innen über die Außenwand ins Zimmer.
	for i in 3:
		var hoehe := 2.0 + i * 0.2
		var haus := HomeProps.box(Vector3(2.6, hoehe, 1.6), "holz" if i % 2 == 0 else "dach")
		haus.position = Vector3(-5.0 + i * 5.0, hoehe * 0.5, -1.6)
		add_child(haus)
		var dach := HomeProps.box(Vector3(2.9, 0.2, 1.9), "akzent")
		dach.position = Vector3(haus.position.x, hoehe, -1.6)
		add_child(dach)
	var laterne := HomeProps.zylinder(0.06, 2.2, "metall")
	laterne.position = Vector3(2.4, 1.1, 1.5)
	add_child(laterne)
	var lampe := HomeProps.box(Vector3(0.3, 0.2, 0.3), "gold")
	lampe.position = Vector3(2.4, 2.3, 1.5)
	add_child(lampe)


## 2–3 Autos auf der Fahrspur — Sprites wären flackrig, ein einzelnes
## GLB pro Auto ist billiger als ein Spline-System.
func _build_autos() -> void:
	var abstaende := [-6.0, 1.5, 8.0]
	for i in abstaende.size():
		var auto := _auto_modell()
		auto.position = Vector3(abstaende[i], 0.0, 0.45 if i % 2 == 0 else -0.45)
		auto.rotation.y = 0.0 if i % 2 == 0 else PI
		add_child(auto)
		_autos.append(auto)


func _auto_modell() -> Node3D:
	if ResourceLoader.exists(AUTO_GLB):
		var scene: PackedScene = load(AUTO_GLB)
		if scene != null:
			var node := Node3D.new()
			node.add_child(scene.instantiate())
			return node
	var ersatz := Node3D.new()
	var karosse := HomeProps.box(Vector3(1.1, 0.4, 0.6), "akzent")
	karosse.position.y = 0.3
	ersatz.add_child(karosse)
	var dach := HomeProps.box(Vector3(0.6, 0.3, 0.55), "glas")
	dach.position.y = 0.62
	ersatz.add_child(dach)
	return ersatz


static func _diorama_position(wall: String, world_size: Vector2) -> Vector3:
	match wall:
		"N":
			return Vector3(world_size.x * 0.5, 0.0, -TIEFE)
		"S":
			return Vector3(world_size.x * 0.5, 0.0, world_size.y + TIEFE)
		"W":
			return Vector3(-TIEFE, 0.0, world_size.y * 0.5)
	return Vector3(world_size.x + TIEFE, 0.0, world_size.y * 0.5)


static func _diorama_yaw(wall: String) -> float:
	if wall == "W" or wall == "E":
		return PI / 2.0
	return 0.0
