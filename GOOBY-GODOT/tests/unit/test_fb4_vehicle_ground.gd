extends TestCase
## FB-4 Bugfix-Beweis „Manche Autos schweben": Bodenkontakt aller platzierten
## Fahrzeuge in den Minispielen. Drei Schichten:
##   1. Modell-Invariante — jedes Fahrzeug-GLB steht nach ModelBank-Einpassung
##      mit der Unterkante exakt auf y = 0 des Pose-Ursprungs.
##   2. Flächen-Vertrag — die Fahrbahn-OBERKANTE liegt exakt auf der Höhe, auf
##      der die Spiele ihre Fahrzeuge posieren (runner/deliveryRush: y = 0).
##   3. Szenen-Messung — in der echten toyRacer-/deliveryRush-Szene wird die
##      Welt-Unterkante der Fahrzeug-Meshes gegen die Fahrbahn gemessen.
## MultiMesh-Instanzen sind headless NICHT rücklesbar (Dummy-Renderer) — für
## Massenware gilt deshalb Schicht 1 + 2 zusammen als Kontaktbeweis.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const RacerLogic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")

## Alle Fahrzeug-GLBs, die die Minispiele platzieren (+ Einpass-Breite).
const VEHICLES := {
	"res://assets/city/autos/sedan.glb": 2.4,
	"res://assets/city/autos/taxi.glb": 2.4,
	"res://assets/city/autos/suv.glb": 2.4,
	"res://assets/city/autos/van.glb": 1.15,
	"res://assets/city/autos/delivery.glb": 2.6,
	"res://assets/minigames/toy_racer/car-kit/race.glb": 0.94,
	"res://assets/minigames/toy_racer/car-kit/taxi.glb": 0.94,
	"res://assets/minigames/toy_racer/car-kit/police.glb": 0.94,
	"res://assets/minigames/toy_racer/car-kit/hatchback-sports.glb": 0.94,
}
## Toleranz: 2,5 cm (Anti-Z-Fighting-Versätze sind ok, sichtbares Schweben nicht).
const EPS := 0.025


## Unterkante der eingepassten Teile relativ zum Pose-Ursprung.
static func _parts_bottom(parts: Array) -> float:
	var bottom := INF
	for entry: Dictionary in parts:
		var aabb: AABB = (entry["xform"] as Transform3D) * (entry["mesh"] as Mesh).get_aabb()
		bottom = minf(bottom, aabb.position.y)
	return bottom


## Tiefster SICHTBARER Mesh-Punkt eines Szenenknotens (Weltkoordinaten).
static func _world_bottom(node: Node3D) -> float:
	var bottom := INF
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).visible:
			var mi := current as MeshInstance3D
			var aabb := mi.get_aabb()
			for i in 8:
				bottom = minf(bottom, (mi.global_transform * aabb.get_endpoint(i)).y)
		for child in current.get_children():
			stack.append(child)
	return bottom


func _mount(game_id: String) -> Node:
	var meta := MinigameRegistry.get_game(game_id)
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = str(meta.get("orientation", "portrait"))
	ctx.run_seed = 4242
	tree.root.add_child(game)
	game.call("setup", ctx)
	await wait_frames(1)
	game.call("start")
	await wait_frames(4)
	return game


## Schicht 1: jedes Fahrzeug-GLB endet nach Einpassung exakt auf y = 0.
func test_vehicle_models_grounded() -> void:
	for path: String in VEHICLES:
		var parts := Models.parts(path, float(VEHICLES[path]))
		assert_true(parts.size() > 0, "%s lädt nicht" % path)
		assert_almost(_parts_bottom(parts), 0.0, 1e-3, path.get_file())


## Schicht 2 (runner): Fahrbahn-OBERKANTE == 0 == Fahrzeug-Pose-Höhe, und die
## Band-Gruppen tragen die dafür nötige Absenkung um die Kacheldicke.
func test_runner_road_surface_at_zero() -> void:
	var game := await _mount("runner")
	var world: Node3D = game.get("_world")
	assert_true(world != null, "runner hat kein _world")
	var road_h: float = (
		(Models.fitted_size("res://assets/city/strassen/road-straight.glb", 4.6) as Vector3).y
	)
	assert_true(road_h > 0.05, "Fahrbahnkachel unerwartet dünn (%f)" % road_h)
	var band: RefCounted = world.get("band")
	var groups: Array = band.get("_groups")
	assert_true(groups.size() > 0, "ScrollBand leer")
	# Gruppe 0 ist die Fahrbahn (zuerst angemeldet): Kachel-Oberkante == 0.
	var road_items: Array = (groups[0] as Dictionary)["items"]
	for item: Dictionary in road_items:
		assert_almost(float(item.get("y", 0.0)) + road_h, 0.0, EPS, "Fahrbahn-Oberkante")
	game.queue_free()
	await wait_frames(1)


## Schicht 3 (toyRacer): jedes Kart berührt die Fahrbahn am Spline (0 … 3 cm).
func test_toy_racer_karts_touch_track() -> void:
	var game := await _mount("toyRacer")
	var karts: Array = game.get("_karts")
	var race: Dictionary = game.get("race")
	var world: Node3D = game.get("_world")
	assert_eq(karts.size(), 4, "vier Karts erwartet")
	for i in karts.size():
		var kart_state: Dictionary = (race["karts"] as Array)[i]
		var smp: Dictionary = RacerLogic.point_at(race["track"], float(kart_state["s"]))
		var surface: Vector3 = world.call("world_at", smp, float(kart_state["lateral"]))
		var gap := _world_bottom(karts[i]) - surface.y
		assert_true(
			gap >= -EPS and gap <= 0.03 + EPS,
			"Kart %d schwebt/versinkt: %.3f m über dem Spline" % [i, gap]
		)
	game.queue_free()
	await wait_frames(1)


## Schicht 3 (deliveryRush): Asphalt-Oberkante == 0 und der Van steht darauf.
## Verkehrsautos posieren im Code ebenfalls auf y = 0 (Schicht 1 + 2).
func test_delivery_van_and_road() -> void:
	var game := await _mount("deliveryRush")
	var world: Node3D = game.get("_world")
	var props: Array = world.get("_props")
	# Asphalt-Platte (erkannt an ihrer Materialfarbe): Offset + halbe Dicke
	# ergibt die Oberkante — sie MUSS auf y = 0 liegen, denn Van, Verkehr,
	# Routenpfeile und Abgabering posieren alle auf y = 0.
	var asphalt: Color = (world.get_script() as GDScript).get_script_constant_map()["ASPHALT"]
	var road_top := -INF
	for prop: Node3D in props:
		var offsets: Array = prop.get("_offsets")
		var layers: Array = prop.get("_layers")
		for i in layers.size():
			var mm: MultiMesh = (layers[i] as MultiMeshInstance3D).multimesh
			if not (mm.mesh is BoxMesh):
				continue
			var box := mm.mesh as BoxMesh
			var mat := box.material as StandardMaterial3D
			if mat == null or not mat.albedo_color.is_equal_approx(asphalt):
				continue
			road_top = maxf(road_top, (offsets[i] as Transform3D).origin.y + box.size.y * 0.5)
	assert_almost(road_top, 0.0, 1e-3, "Asphalt-Oberkante muss auf y = 0 liegen")
	var van: Node3D = game.get("_van")
	assert_almost(_world_bottom(van), 0.0, EPS, "Van-Unterkante")
	game.queue_free()
	await wait_frames(1)
