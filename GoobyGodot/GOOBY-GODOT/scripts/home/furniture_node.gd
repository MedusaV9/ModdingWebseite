class_name FurnitureNode
extends Node3D
## Sichtbares Möbel-Exemplar (W2a HOUSE): lädt das Katalog-GLB und fittet es
## PROZEDURAL aufs Grid (Kenney/KayKit/itch-Assets haben verschiedene Maße
## und Pivots — Auto-Fit statt Asset-Anfassen): uniform skaliert in den
## Footprint (× fill), XZ-zentriert, Unterkante auf y=0.
##
## Metadaten: `uid` + `item_id` (Baumodus-Picking läuft über GridData-Zellen,
## nicht über Physik).

## Obergrenze fürs Auto-Fit (E9 P1-2): Möbel dürfen nie höher als der Raum
## werden. 2.25 = 0.9 × die 2,5-m-Wand (RoomBase.WALL_HEIGHT — hier als
## Literal, um keine zyklische class_name-Referenz einzuführen).
const MAX_FIT_HEIGHT := 2.25

var uid := ""
var item_def: Dictionary = {}

var _model: Node3D
var _top_y := 0.0
var _light: OmniLight3D


## Zellen-Layer-Item (RUG/FLOOR/SURFACE/CEILING). `base_y` hebt SURFACE-Items
## auf die Trägerfläche; CEILING-Items hängen mit der Oberkante an der Decke
## (W13B). Liefert null bei fehlendem/kaputtem GLB (weich degradieren).
static func create(def: Dictionary, at: Vector2i, rot: int, item_uid: String) -> FurnitureNode:
	var node := _build(def, item_uid)
	if node == null:
		return null
	var center := GridData.world_center(at, def["footprint"], rot)
	node.position = center
	node.rotation.y = -rot * PI / 2.0
	if int(def["layer"]) == GridData.Layer.CEILING:
		node.position.y = GridData.DECKEN_HOEHE - node.top_y()
	return node


## Wand-Layer-Item: sitzt AUF der Wand (Doc D §1.2, kein CSG), Blick in den
## Raum, Höhe ~Möbelhöhe.
static func create_wall(
	def: Dictionary, wall: String, offset: int, room_grid: Vector2i, item_uid: String
) -> FurnitureNode:
	var node := _build(def, item_uid)
	if node == null:
		return null
	var span := int(def["wall_size"]) * GridData.CELL_SIZE
	var along := offset * GridData.CELL_SIZE + span * 0.5
	var lift := Vector3(0.0, 1.35, 0.0)
	var inset := 0.06
	match wall:
		"N":
			node.position = Vector3(along, 0, inset) + lift
		"S":
			node.position = Vector3(along, 0, room_grid.y * GridData.CELL_SIZE - inset) + lift
			node.rotation.y = PI
		"W":
			node.position = Vector3(inset, 0, along) + lift
			node.rotation.y = -PI / 2.0
		"E":
			node.position = Vector3(room_grid.x * GridData.CELL_SIZE - inset, 0, along) + lift
			node.rotation.y = PI / 2.0
	return node


## Oberkante (Welt-y-Offset) — SURFACE-Items werden hier draufgestellt.
func top_y() -> float:
	return _top_y


## Ghost-Optik für den Baumodus: halbtransparent + Gültigkeits-Tönung.
func set_ghost(valid: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.95, 0.5, 0.6) if valid else Color(0.98, 0.35, 0.3, 0.6)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = mat


func set_light_enabled(enabled: bool) -> void:
	if _light != null:
		_light.visible = enabled


static func _build(def: Dictionary, item_uid: String) -> FurnitureNode:
	var model := _make_model(def)
	if model == null:
		return null
	var node := FurnitureNode.new()
	node.uid = item_uid
	node.item_def = def
	node.name = "Furniture_%s" % item_uid
	node._model = model
	node.add_child(node._model)
	node._fit_model(def)
	if bool(def.get("can_toggle_light", false)):
		node._attach_light()
	return node


## Modell-Quelle einer Def: prozedurales Prop (`proc`, z. B. Fenster) oder
## Katalog-GLB. null = nichts Zeichenbares (weich degradieren).
static func _make_model(def: Dictionary) -> Node3D:
	var proc := str(def.get("proc", ""))
	if proc == "fenster":
		return HomeProps.fenster(int(def.get("wall_size", 2)), bool(def.get("exterior", false)))
	if proc == "postkartenwand":
		# REST-4 (EVAL Rang 15): Archiv-Karten am Korkbrett.
		return PostkartenProps.postkartenwand()
	if proc == "souvenirregal":
		# REST-4 (EVAL Rang 15): ein Mini je besuchtem Reiseziel.
		return PostkartenProps.souvenirregal()
	if proc == "girlande":
		# W13B: Drawer-/Shop-Vorschau — die echte Spann-Deko baut GirlandenBau.
		return Girlande.vorschau(str(def.get("id", "")))
	if proc != "":
		push_warning("Unbekanntes Prop: %s (%s)" % [proc, def.get("id", "?")])
		return null
	var path := FurnitureCatalog.glb_path(def)
	if not ResourceLoader.exists(path):
		push_warning("Möbel-GLB fehlt: %s (%s)" % [path, def.get("id", "?")])
		return null
	var scene: PackedScene = load(path)
	return scene.instantiate() if scene != null else null


func _fit_model(def: Dictionary) -> void:
	var aabb := _merged_aabb(_model, Transform3D.IDENTITY)
	if aabb.size.x <= 0.0001 or aabb.size.z <= 0.0001:
		return
	var fp: Vector2i = def["footprint"]
	var fill: float = def["fill"]
	var target_w := fp.x * GridData.CELL_SIZE * fill
	var target_d := fp.y * GridData.CELL_SIZE * fill
	var s := minf(target_w / aabb.size.x, target_d / aabb.size.z)
	# Höhenclamp (E9 P1-2): der Footprint-Fit allein macht schmale, hohe
	# Assets riesig (1×1-Stehlampe → 3,37 m bei 2,5 m Wandhöhe). Uniform
	# bleibt der Scale trotzdem — die Decke ist die Obergrenze.
	if aabb.size.y > 0.0001:
		s = minf(s, MAX_FIT_HEIGHT / aabb.size.y)
	_model.scale = Vector3.ONE * s
	var center := aabb.get_center()
	_model.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
	if int(def["layer"]) == GridData.Layer.RUG:
		_model.position.y += 0.005
	_top_y = aabb.size.y * s


func _attach_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.6)
	_light.light_energy = 1.4
	_light.omni_range = 2.4
	_light.position = Vector3(0.0, maxf(_top_y - 0.1, 0.3), 0.0)
	_light.shadow_enabled = false
	add_child(_light)


static func _merged_aabb(node: Node, xform: Transform3D) -> AABB:
	var merged := AABB()
	var found := false
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		merged = local * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var sub := _merged_aabb(child, local)
		if sub.size != Vector3.ZERO or sub.position != Vector3.ZERO:
			merged = merged.merge(sub) if found else sub
			found = true
	return merged
