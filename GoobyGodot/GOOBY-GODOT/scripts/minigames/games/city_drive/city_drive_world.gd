extends Node3D
## Kompakte 3D-Stadt-Kulisse für die City-Drive-ARCADE-Runde (W13B/DRIVE):
## das 7×7-Ring+Kreuz-Raster der Logik als Kenney-Stadt — DIESELBEN Assets
## und Bau-Muster wie die deliveryRush-Stadt (Agent 3D-B), nur kleiner und
## als EIGENE Datei (kein Griff in fremde Spiel- oder city_scene-Dateien).
##
## Statisch in MultiMeshes gegossen (Straßen, Häuser, Bäume, Skyline) — nur
## Verkehr, Münzen und der Checkpoint-Ring bekommen pro Frame neue Posen.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Logic := preload("res://scripts/minigames/games/city_drive/city_drive_logic.gd")

const CITY := "res://assets/city/gebaeude/"
const HOUSES: Array[String] = [
	CITY + "building-a.glb",
	CITY + "building-c.glb",
	CITY + "building-e.glb",
	CITY + "building-g.glb",
	CITY + "building-f.glb",
]
const TREE := "res://assets/city/natur/tree_default.glb"
const TRAFFIC_CAR := "res://assets/city/autos/taxi.glb"
const AWNING := CITY + "detail-awning.glb"
const STREETLIGHT := "res://assets/city/deko/streetlight.gltf"

## Flächenfarben — dasselbe Abendband wie die deliveryRush-Stadt.
const GRASS := Color(0.5, 0.66, 0.42)
const ASPHALT := Color(0.42, 0.43, 0.48)
const WALK := Color(0.79, 0.71, 0.58)
const DASH := Color(0.95, 0.92, 0.7)
const COIN_GOLD := Color(1.0, 0.82, 0.3)

## W18/B4: Pastell-Tint der Baum-Surfaces per glTF-Materialname — dieselbe
## Palette wie die anderen Kulissen (Props3D.NATURE, Agent 3D-A).
const TREE_TINT := {
	"woodBark": Color(0.64, 0.46, 0.33),
	"leafsGreen": Color(0.45, 0.72, 0.42),
}

## Fahrbahn-/Gehwegbreite innerhalb einer 20-m-Kachel.
const ROAD_W := 13.0
const WALK_W := 17.0

var traffic_prop: Node3D
var coin_prop: Node3D

var _props: Array[Node3D] = []


func build(colliders: Array, rng: GoobyRng, coin_cap: int) -> void:
	_build_ground()
	_build_roads()
	_build_houses(colliders, rng)
	_build_trees(rng)
	_build_skyline(rng)
	traffic_prop = _prop(Models.parts(TRAFFIC_CAR, 2.4), 14, true)
	coin_prop = _prop([_coin_part()], coin_cap + 4)


func _build_ground() -> void:
	var span := Logic.TILE_M * float(Logic.GRID) + 100.0
	add_child(Fx.ground(Vector2(span, span), GRASS, -0.08))


## Straßen: Gehwegplatte + Asphalt in Fahrtrichtung + Mittelstriche —
## dasselbe Lücken-freie Streck-Muster wie die deliveryRush-Stadt.
func _build_roads() -> void:
	var walk_prop := _prop([_slab(WALK_W, WALK, 0.02)], 40)
	var block_prop := _prop([_slab(Logic.TILE_M, WALK.darkened(0.06), 0.015)], 20)
	var road_prop := _prop([_slab(ROAD_W, ASPHALT, -0.025)], 80)
	var dash_prop := _prop([_dash_part()], 140)
	for prop in [walk_prop, block_prop, road_prop, dash_prop]:
		prop.call("begin")
	for r in Logic.GRID:
		for c in Logic.GRID:
			var w := Logic.tile_to_world(r, c)
			var at := Vector3(w.x, 0.0, w.y)
			if not Logic.is_road(r, c):
				if _inside_block(r, c):
					block_prop.call("push", Transform3D(Basis.IDENTITY, at))
				continue
			walk_prop.call("push", Transform3D(Basis.IDENTITY, at))
			_push_asphalt(road_prop, r, c, at)
			_push_dashes(dash_prop, r, c, at)
	for prop in [walk_prop, block_prop, road_prop, dash_prop]:
		prop.call("flush")


func _push_asphalt(prop: Node3D, r: int, c: int, at: Vector3) -> void:
	var stretch := Logic.TILE_M / ROAD_W
	var horizontal := Logic.is_road(r, c + 1) or Logic.is_road(r, c - 1)
	var vertical := Logic.is_road(r - 1, c) or Logic.is_road(r + 1, c)
	if not horizontal and not vertical:
		prop.call("push", Transform3D(Basis.IDENTITY, at))
		return
	if horizontal:
		prop.call("push", Transform3D(Basis.IDENTITY.scaled(Vector3(stretch, 1.0, 1.0)), at))
	if vertical:
		prop.call("push", Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, stretch)), at))


func _push_dashes(prop: Node3D, r: int, c: int, at: Vector3) -> void:
	var east := Logic.is_road(r, c + 1)
	var west := Logic.is_road(r, c - 1)
	var north := Logic.is_road(r - 1, c)
	var south := Logic.is_road(r + 1, c)
	var crossing := (east or west) and (north or south)
	var half := Logic.TILE_M * 0.5
	for i in 4:
		if crossing and (i == 1 or i == 2):
			continue
		var f := (float(i) + 0.5) / 4.0 * 2.0 - 1.0
		if east or west:
			prop.call("push", Transform3D(Basis.IDENTITY, at + Vector3(f * half, 0.0, 0.0)))
		if north or south:
			var turn := Basis(Vector3.UP, PI * 0.5)
			prop.call("push", Transform3D(turn, at + Vector3(0.0, 0.0, f * half)))


func _build_houses(colliders: Array, rng: GoobyRng) -> void:
	var buckets: Array = []
	var props: Array[Node3D] = []
	for path in HOUSES:
		buckets.append([])
		props.append(_prop(Models.parts(path, 13.0), 12))
	for box: Dictionary in colliders:
		var idx := int(rng.next() * float(HOUSES.size())) % HOUSES.size()
		var cx := (float(box["minX"]) + float(box["maxX"])) * 0.5
		var cz := (float(box["minZ"]) + float(box["maxZ"])) * 0.5
		var yaw := float(int(rng.next() * 4.0)) * PI * 0.5
		(buckets[idx] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0.0, cz)))
	for i in props.size():
		props[i].call("begin")
		for xf: Transform3D in buckets[i]:
			props[i].call("push", xf)
		props[i].call("flush")


## Bäume auf der Wiese am Stadtrand (zwei gestreute je Randkachel) — die
## Innenblocks sind bebaut, dort sähe man sie ohnehin nicht.
##
## W18/B4 (report_arcade): die Bäume standen TIEFSCHWARZ in der Stadt.
## Wurzel: das Kenney-Nature-GLB authort `metallicFactor: 1` (Gebäude/
## Autos: 0), und die _3db-Bühne rendert bewusst OHNE Spiegelquelle
## (stage3d, Lambert-Look) — Voll-Metall hat dann keinerlei Diffus-Anteil
## und bleibt schwarz, egal wie hell Sonne/Ambient sind. Fix wie in den
## anderen Kulissen (Props3D.pastel-Muster): Metall raus + Palette-Tint.
func _build_trees(rng: GoobyRng) -> void:
	var tree_prop := _prop(_pastel_parts(Models.parts_by_height(TREE, 7.0), TREE_TINT), 60)
	tree_prop.call("begin")
	for r in Logic.GRID:
		for c in Logic.GRID:
			if Logic.is_road(r, c) or _inside_block(r, c):
				continue
			var w := Logic.tile_to_world(r, c)
			for _i in 2:
				var rx := (rng.next() - 0.5) * Logic.TILE_M * 0.8
				var rz := (rng.next() - 0.5) * Logic.TILE_M * 0.8
				var at := Vector3(w.x + rx, -0.08, w.y + rz)
				tree_prop.call("push", Transform3D(Basis(Vector3.UP, rng.next() * TAU), at))
	tree_prop.call("flush")


## Ferne Silhouetten hinter dem Stadtrand (Nebel macht Kulisse daraus).
func _build_skyline(rng: GoobyRng) -> void:
	var haze := Fx.flat(Color(0.83, 0.68, 0.62), 1.0)
	var prop := _prop_tinted(Models.parts(CITY + "building-skyscraper-a.glb", 16.0), 36, haze)
	prop.call("set_shadows", false)
	prop.call("begin")
	for side in 4:
		for i in 9:
			var along := (float(i) - 4.0) * 22.0 + (rng.next() - 0.5) * 8.0
			var out := 92.0 + rng.next() * 24.0
			var at := Vector3(along, 0.0, -out)
			if side == 1:
				at = Vector3(along, 0.0, out)
			elif side == 2:
				at = Vector3(-out, 0.0, along)
			elif side == 3:
				at = Vector3(out, 0.0, along)
			var tall := Basis.IDENTITY.scaled(Vector3(1.0, 0.7 + rng.next() * 0.9, 1.0))
			prop.call("push", Transform3D(tall.rotated(Vector3.UP, rng.next() * TAU), at))
	prop.call("flush")


func _inside_block(r: int, c: int) -> bool:
	return (
		r >= Logic.RING_MIN and r <= Logic.RING_MAX and c >= Logic.RING_MIN and c <= Logic.RING_MAX
	)


func _slab(size: float, color: Color, y: float) -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3(Logic.TILE_M, 0.05, Logic.TILE_M)
	box.material = Fx.flat(color)
	var scale_v := Vector3(size / Logic.TILE_M, 1.0, size / Logic.TILE_M)
	return {
		"mesh": box,
		"xform": Transform3D(Basis.IDENTITY.scaled(scale_v), Vector3(0.0, y, 0.0)),
	}


func _dash_part() -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 0.04, 0.34)
	box.material = Fx.flat(DASH)
	return {"mesh": box, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.005, 0.0))}


## Mini-Laden fürs Checkpoint-Ziel (W16/G2): die „Einkaufsfahrt" bekommt am
## Ring einen ORT — Kiosk-Theke + Kenney-Markise + leuchtendes rosa Schild +
## zwei Laternen. Lokales +z zeigt zur Straße; city_drive.gd stellt/dreht den
## Knoten bei jedem Checkpoint-Wechsel (reine Deko, keine Kollision).
func build_checkpoint_venue() -> Node3D:
	var venue := Node3D.new()
	venue.name = "CheckpointVenue"
	var counter := MeshInstance3D.new()
	var counter_mesh := BoxMesh.new()
	counter_mesh.size = Vector3(3.2, 1.1, 1.5)
	counter_mesh.material = Fx.flat(Color(0.95, 0.88, 0.72))
	counter.mesh = counter_mesh
	counter.position = Vector3(0.0, 0.55, 0.0)
	venue.add_child(counter)
	var awning := Models.node(AWNING, 3.8)
	awning.position = Vector3(0.0, 1.7, 0.35)
	venue.add_child(awning)
	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(2.6, 0.6, 0.16)
	# Dasselbe Rosa wie der Checkpoint-Ring — der Laden LIEST sich als Ziel.
	sign_mesh.material = Fx.glow(Color(0.95, 0.36, 0.62), 1.1)
	sign.mesh = sign_mesh
	sign.position = Vector3(0.0, 2.75, 0.1)
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	venue.add_child(sign)
	for side in [-1.0, 1.0]:
		var lantern := _one_off(Models.parts_by_height(STREETLIGHT, 4.6))
		lantern.position = Vector3(4.4 * side, 0.0, 1.1)
		lantern.rotation.y = PI
		venue.add_child(lantern)
	return venue


## Funkengarbe für Rempler/Crashes an der Stoßstange (Farben wie das
## Near-Miss-Funken-Modul der Stadt) — city_drive.gd feuert sie per Fx.burst.
func build_sparks() -> GPUParticles3D:
	return (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.82, 0.4, 1.0),
				"amount": 26,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(2.5, 6.0),
				"spread": 85.0,
				"gravity": Vector3(0.0, -9.8, 0.0),
				"size": Vector2(0.05, 0.14),
				"radius": 0.3,
			}
		)
	)


## Asphalt-Staubfahne hinter dem Auto (deliveryRush-Muster, Dauer-Emitter —
## city_drive.gd schaltet sie ab ~60 % Vmax an).
func build_drive_dust() -> GPUParticles3D:
	return (
		Fx
		. particles(
			{
				"color": Color(0.78, 0.72, 0.62, 0.5),
				"amount": 26,
				"lifetime": 0.9,
				"speed": Vector2(0.5, 1.4),
				"spread": 30.0,
				"gravity": Vector3(0.0, 0.9, 0.0),
				"size": Vector2(0.25, 0.6),
				"radius": 0.4,
			}
		)
	)


## Gras-Staub fürs Offroad-Rumpeln (grünlich, steigt leicht auf).
func build_grass_puff() -> GPUParticles3D:
	return (
		Fx
		. particles(
			{
				"color": Color(0.6, 0.68, 0.4, 0.7),
				"amount": 22,
				"lifetime": 0.7,
				"speed": Vector2(0.8, 2.0),
				"spread": 45.0,
				"gravity": Vector3(0.0, 1.4, 0.0),
				"size": Vector2(0.18, 0.45),
				"radius": 0.5,
			}
		)
	)


## Einzelstück aus {mesh, xform}-Teilen (parts_by_height liefert die Liste —
## Models.node passt nur nach BREITE ein, Laternen brauchen die Höhe).
func _one_off(parts: Array) -> Node3D:
	var holder := Node3D.new()
	for entry: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = entry["mesh"]
		mi.transform = entry["xform"]
		holder.add_child(mi)
	return holder


## Goldmünze: liegender, leuchtender Zylinder — von der Verfolgerkamera aus
## als goldener Punkt auf dem Asphalt lesbar (Web: gelbe Sprite-Münzen).
func _coin_part() -> Dictionary:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.16
	disc.radial_segments = 10
	disc.rings = 1
	disc.material = Fx.glow(COIN_GOLD, 1.2)
	return {"mesh": disc, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.7, 0.0))}


## Teile-Liste mit entmetallisierten Pastell-Meshes (W18/B4): MultiMesh
## zieht die Material-SLOTS des Meshes — ein material_override plättete
## Stamm UND Krone auf EINE Farbe, also Mesh duplizieren und pro Surface
## den glTF-Materialnamen auf die Palette mappen. Das Duplikat schützt
## den statischen ModelBank-Cache (deliveryRush teilt sich das GLB).
func _pastel_parts(parts: Array, tint: Dictionary) -> Array:
	var out: Array = []
	for entry: Dictionary in parts:
		var mesh := (entry["mesh"] as Mesh).duplicate() as ArrayMesh
		if mesh == null:
			out.append(entry)
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var color := Color(0.85, 0.85, 0.85)
			if src is BaseMaterial3D:
				color = (src as BaseMaterial3D).albedo_color
			var mat_name := "" if src == null else src.resource_name
			mesh.surface_set_material(i, Fx.flat(tint.get(mat_name, color), 0.88))
		out.append({"mesh": mesh, "xform": entry["xform"]})
	return out


func _prop(parts: Array, cap: int, colored := false) -> Node3D:
	return _prop_tinted(parts, cap, null, colored)


func _prop_tinted(parts: Array, cap: int, material: Material, colored := false) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, colored, material)
	_props.append(node)
	return node
