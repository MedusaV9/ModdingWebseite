extends SceneTree
## FB4-Sonde (KEIN Test): misst in den ECHTEN Spielszenen die Unterkante jedes
## platzierten Fahrzeugs gegen die Fahrbahnhöhe — Grundlage für den Bugfix
## „Manche Autos schweben" und den Bodenkontakt-Test.
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/fb4_ground_probe.gd

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	root.theme = ThemeService.theme()
	_model_report()
	await _toy_racer()
	await _runner()
	await _delivery()
	quit(0)


## Roh-AABBs: Fahrzeuge + Fahrbahnen (Modellursprung vs. Unterkante).
func _model_report() -> void:
	print("== Modell-AABBs (roh) ==")
	var paths := [
		"res://assets/city/autos/sedan.glb",
		"res://assets/city/autos/taxi.glb",
		"res://assets/city/autos/suv.glb",
		"res://assets/city/autos/van.glb",
		"res://assets/city/autos/delivery.glb",
		"res://assets/minigames/toy_racer/car-kit/race.glb",
		"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-straight.glb",
		"res://assets/city/strassen/road-straight.glb",
	]
	for path: String in paths:
		var aabb := Models.aabb(path)
		print(
			(
				"  %s: min_y=%.4f max_y=%.4f size=%.2fx%.2fx%.2f"
				% [
					path.get_file(),
					aabb.position.y,
					aabb.end.y,
					aabb.size.x,
					aabb.size.y,
					aabb.size.z
				]
			)
		)


func _mount(game_id: String) -> Node:
	var meta := MinigameRegistry.get_game(game_id)
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = str(meta.get("orientation", "portrait"))
	ctx.run_seed = 4242
	root.add_child(game)
	game.call("setup", ctx)
	await process_frame
	game.call("start")
	for _i in 30:
		await process_frame
	return game


## Tiefster Punkt aller Mesh-Kinder eines Knotens, in Weltkoordinaten.
static func _world_bottom(node: Node3D) -> float:
	var bottom := INF
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			var aabb := mi.get_aabb()
			for i in 8:
				var corner := mi.global_transform * aabb.get_endpoint(i)
				bottom = minf(bottom, corner.y)
		for child in current.get_children():
			stack.append(child)
	return bottom


func _toy_racer() -> void:
	print("== toyRacer: Kart-Unterkante vs. Spline-Höhe ==")
	var game := await _mount("toyRacer")
	var karts: Array = game.get("_karts")
	var race: Dictionary = game.get("race")
	var world: Node3D = game.get("_world")
	var logic: GDScript = load("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
	for i in karts.size():
		var kart_state: Dictionary = (race["karts"] as Array)[i]
		var smp: Dictionary = logic.point_at(race["track"], float(kart_state["s"]))
		var spline_y: float = (
			(world.call("world_at", smp, float(kart_state["lateral"])) as Vector3).y
		)
		var bottom := _world_bottom(karts[i])
		print(
			(
				"  Kart %d: Unterkante=%.4f Spline=%.4f Differenz=%.4f"
				% [i, bottom, spline_y, bottom - spline_y]
			)
		)
	game.queue_free()
	await process_frame


func _runner() -> void:
	print("== runner: Auto-Instanzen vs. Fahrbahnoberkante ==")
	var game := await _mount("runner")
	var world: Node3D = game.get("_world")
	if world == null:
		print("  (kein _world-Feld)")
		game.queue_free()
		return
	var car_props: Array = world.get("car_props")
	for prop_i in car_props.size():
		var prop: Node3D = car_props[prop_i]
		var lows := _multi_bottoms(prop)
		print("  Auto-Gruppe %d: %d Instanzen, Unterkanten %s" % [prop_i, lows.size(), lows])
	# Fahrbahn: höchster Punkt des road-Modells nach Einpassung.
	var road_parts := Models.parts_yawed(
		"res://assets/city/strassen/road-straight.glb",
		PI * 0.5,
		float(world.get("ROAD_W")) if world.get("ROAD_W") != null else 8.0
	)
	var top := -INF
	for part: Dictionary in road_parts:
		var mesh: Mesh = part["mesh"]
		var aabb: AABB = (part["xform"] as Transform3D) * mesh.get_aabb()
		top = maxf(top, aabb.end.y)
	print("  Fahrbahn-Oberkante (eingepasst): %.4f" % top)
	game.queue_free()
	await process_frame


## Unterkanten der sichtbaren MultiMesh-Instanzen eines MultiProp (Weltkoordinaten).
static func _multi_bottoms(prop: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [prop]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MultiMeshInstance3D:
			var mmi := current as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm != null:
				var count := mm.visible_instance_count
				if count < 0:
					count = mm.instance_count
				var aabb := mm.mesh.get_aabb()
				for i in mini(count, 4):
					var xform := mmi.global_transform * mm.get_instance_transform(i)
					var low := INF
					for c in 8:
						low = minf(low, (xform * aabb.get_endpoint(c)).y)
					out.append(snappedf(low, 0.001))
		for child in current.get_children():
			stack.append(child)
	return out


func _delivery() -> void:
	print("== deliveryRush: Van/Verkehr vs. Asphalt-Oberkante ==")
	var game := await _mount("deliveryRush")
	var van: Node3D = game.get("_van")
	print(
		"  Van-Unterkante: %.4f (Asphalt-Deckel laut _slab: 0.03+0.025=0.055)" % _world_bottom(van)
	)
	var world: Node3D = game.get("_world")
	if world != null:
		var traffic: Node3D = world.get("traffic_prop")
		if traffic != null:
			print("  Verkehr-Unterkanten: %s" % [_multi_bottoms(traffic)])
	game.queue_free()
	await process_frame
