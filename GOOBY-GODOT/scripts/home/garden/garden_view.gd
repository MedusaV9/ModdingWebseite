class_name GardenView
extends Node3D
## 3D-Darstellung des Garten-Grids (Doc D §6.1) im Garten-Raum: Beete,
## Pflanzen (Höhe = Wachstumsstufe), Bauten (HomeProps), Sammel-Spots,
## Zaun-Kanten und der Auswahl-Rahmen.
##
## Das Grid liegt mittig im Raum (GardenState.world_origin), damit jede
## Erweiterung sichtbar nach außen wächst. Reine Anzeige — geschrieben wird
## ausschließlich über GardenState/GardenWorld.

## Höhe der Beet-Platte über dem Rasen.
const BEET_HOEHE := 0.06
## Wie hoch eine Pflanze auf der letzten Stufe wird.
const PFLANZE_MAX_H := 0.55
const ZAUN_HOEHE := 0.45

var origin := Vector2.ZERO
var _gs: Object
var _grid: GardenGrid
var _auswahl: MeshInstance3D
var _blocker_mount: Node3D


func setup(gs: Object, raum_meter: Vector2, blocker_mount: Node3D = null) -> void:
	_gs = gs
	_blocker_mount = blocker_mount
	rebuild(raum_meter)


## Alles neu aufbauen (nach jeder Garten-Aktion).
func rebuild(raum_meter: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	if _blocker_mount != null:
		for child in _blocker_mount.get_children():
			child.queue_free()
	_grid = GardenState.grid(_gs)
	origin = GardenState.world_origin(raum_meter, _grid.size)
	_build_rasenkante()
	_build_beete()
	_build_strukturen()
	_build_kanten()
	_build_spots()
	_build_auswahl()


func garden_grid() -> GardenGrid:
	return _grid


## Mittelpunkt einer Garten-Zelle in Raum-Weltkoordinaten.
func cell_to_world(cell: Vector2i) -> Vector3:
	var size := GardenGrid.CELL_SIZE
	return Vector3(origin.x + (cell.x + 0.5) * size, 0.0, origin.y + (cell.y + 0.5) * size)


## Weltposition → Garten-Zelle (außerhalb = (-1, -1)).
func world_to_cell(world: Vector3) -> Vector2i:
	var size := GardenGrid.CELL_SIZE
	var cell := Vector2i(
		int(floor((world.x - origin.x) / size)), int(floor((world.z - origin.y) / size))
	)
	return cell if _grid != null and _grid.in_bounds(cell) else Vector2i(-1, -1)


## Auswahl-Rahmen setzen ((-1,-1) blendet ihn aus).
func highlight(cell: Vector2i) -> void:
	if _auswahl == null:
		return
	_auswahl.visible = _grid != null and _grid.in_bounds(cell)
	if _auswahl.visible:
		_auswahl.position = cell_to_world(cell) + Vector3(0.0, 0.02, 0.0)


func _build_rasenkante() -> void:
	var breite := _grid.size.x * GardenGrid.CELL_SIZE
	var tiefe := _grid.size.y * GardenGrid.CELL_SIZE
	var platte := HomeProps.box(Vector3(breite, 0.02, tiefe), "blatt")
	platte.position = Vector3(origin.x + breite * 0.5, 0.01, origin.y + tiefe * 0.5)
	add_child(platte)


func _build_beete() -> void:
	for cell: Vector2i in _grid.plot_cells():
		var data := _grid.cell(cell)
		var erde := HomeProps.box(
			Vector3(GardenGrid.CELL_SIZE * 0.9, BEET_HOEHE, GardenGrid.CELL_SIZE * 0.9),
			"holz_dunkel"
		)
		erde.position = cell_to_world(cell) + Vector3(0.0, BEET_HOEHE * 0.5, 0.0)
		add_child(erde)
		var crop_id := str(data.get("crop", ""))
		if crop_id != "":
			_build_pflanze(cell, crop_id, int(data.get("stage", 0)))


func _build_pflanze(cell: Vector2i, crop_id: String, stufe: int) -> void:
	var crop := GardenCrops.crop(crop_id)
	if crop.is_empty():
		return
	var anteil := clampf(float(stufe) / float(crop["stufen"]), 0.15, 1.0)
	# WELT2: echtes Pflanzen-Modell (Kenney bzw. eigener Blender-Crop) —
	# der Stiel+Kugel-Lolli bleibt nur als Fallback ohne Assets.
	var modell := HomeProps.pflanze(crop_id, anteil)
	if modell != null:
		modell.position = cell_to_world(cell) + Vector3(0.0, BEET_HOEHE, 0.0)
		add_child(modell)
		return
	var hoehe := PFLANZE_MAX_H * anteil
	var stiel := HomeProps.box(Vector3(0.06, hoehe, 0.06), "blatt")
	stiel.position = cell_to_world(cell) + Vector3(0.0, BEET_HOEHE + hoehe * 0.5, 0.0)
	add_child(stiel)
	var frucht := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.06 + 0.1 * anteil
	kugel.height = kugel.radius * 2.0
	frucht.mesh = kugel
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(crop["farbe"]))
	mat.roughness = 0.9
	frucht.material_override = mat
	frucht.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frucht.position = cell_to_world(cell) + Vector3(0.0, BEET_HOEHE + hoehe, 0.0)
	add_child(frucht)


func _build_strukturen() -> void:
	for entry: Dictionary in _grid.structures:
		var kind := str(entry["kind"])
		var zellen := GardenGrid.structure_cells(kind, entry["at"], int(entry.get("rot", 0)))
		if zellen.is_empty():
			continue
		var mitte := _zellen_mitte(zellen)
		var node := _struktur_node(kind, entry)
		if node == null:
			continue
		node.position = mitte
		node.rotation.y = PI * 0.5 * int(entry.get("rot", 0))
		if _blocker_mount != null and kind != "sprinkler":
			_blocker_mount.add_child(node)
		else:
			add_child(node)


func _struktur_node(kind: String, entry: Dictionary) -> Node3D:
	match kind:
		"shed":
			return HomeProps.shed(maxi(1, HomeState.shed_stufe(_gs)))
		"werkstatt":
			return HomeProps.werkstatt()
		"gewaechshaus":
			var door: Vector2i = entry.get("door", Vector2i(-1, -1))
			var zellen := GardenGrid.structure_cells(kind, entry["at"], int(entry.get("rot", 0)))
			var versatz := Vector3.ZERO
			if _grid.in_bounds(door):
				versatz = cell_to_world(door) - _zellen_mitte(zellen)
			return HomeProps.gewaechshaus(versatz)
		"sprinkler":
			return HomeProps.sprinkler()
		"baum":
			return _baum()
	return null


func _baum() -> Node3D:
	# WELT2: echter Kenney-Baum statt Zylinder+Kugel (gleiche Hüllhöhe;
	# tree_default ist schlank genug, dass die Krone in der 1-Zellen-
	# Stellfläche bleibt und nicht in Nachbar-Bauten ragt).
	var glb := HomeProps.modell_glb("res://assets/furniture/garten/tree_default.glb", 2.1)
	if glb != null:
		glb.name = "Baum"
		return glb
	var wurzel := Node3D.new()
	wurzel.name = "Baum"
	var stamm := HomeProps.zylinder(0.12, 1.1, "holz_dunkel")
	stamm.position.y = 0.55
	wurzel.add_child(stamm)
	var krone := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.7
	kugel.height = 1.2
	krone.mesh = kugel
	krone.material_override = HomeProps.material("blatt")
	krone.position.y = 1.5
	krone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(krone)
	return wurzel


func _build_kanten() -> void:
	for edge: Dictionary in _grid.edges:
		var from: Vector2i = edge["from"]
		var laenge := maxi(1, int(edge.get("len", 1)))
		var waagerecht := str(edge.get("dir", "E")) == "E"
		var start := cell_to_world(from)
		var span := laenge * GardenGrid.CELL_SIZE
		var groesse := (
			Vector3(span, ZAUN_HOEHE, 0.08) if waagerecht else Vector3(0.08, ZAUN_HOEHE, span)
		)
		var zaun := HomeProps.box(groesse, "holz")
		var halbe := GardenGrid.CELL_SIZE * 0.5
		zaun.position = (
			start
			+ Vector3(
				(span * 0.5 - halbe) if waagerecht else -halbe,
				ZAUN_HOEHE * 0.5,
				-halbe if waagerecht else (span * 0.5 - halbe)
			)
		)
		add_child(zaun)


func _build_spots() -> void:
	for spot: Dictionary in GardenWorld.offene_spots(_gs):
		var node := HomeProps.sammel_spot(str(spot["material"]))
		node.position = cell_to_world(spot["at"])
		add_child(node)


func _build_auswahl() -> void:
	_auswahl = MeshInstance3D.new()
	_auswahl.name = "Auswahl"
	var quad := QuadMesh.new()
	quad.size = Vector2(GardenGrid.CELL_SIZE * 0.95, GardenGrid.CELL_SIZE * 0.95)
	_auswahl.mesh = quad
	_auswahl.rotation.x = -PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(AcTokens.GOLD, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_auswahl.material_override = mat
	_auswahl.visible = false
	add_child(_auswahl)


func _zellen_mitte(zellen: Array[Vector2i]) -> Vector3:
	var summe := Vector3.ZERO
	for cell in zellen:
		summe += cell_to_world(cell)
	return summe / float(zellen.size())
