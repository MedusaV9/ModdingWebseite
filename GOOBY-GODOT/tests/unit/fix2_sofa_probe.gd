extends SceneTree
## FIX2-Sofa-Probe (KEIN Test): Pfad + Track im Möbel-Umgehungs-Szenario dumpen.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := "user://fix2_probe/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	var scene: PackedScene = load(str(RoomDefs.room("living")["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	await process_frame
	var gooby: GoobyHome = room.gooby()
	gooby.set_wander_enabled(false)
	# Wie der Test: Rebake abwarten + 2 Physics-Frames.
	var t0 := Time.get_ticks_msec()
	while room._rebake_pending and Time.get_ticks_msec() - t0 < 4000:
		await physics_frame
	await physics_frame
	await physics_frame
	# Grid-Blocker dumpen.
	var blocked_str := ""
	for c: Vector2i in gooby.grid.blocked:
		blocked_str += "(%d,%d) " % [c.x, c.y]
	print("GRID %dx%d blocked: %s" % [gooby.grid.size.x, gooby.grid.size.y, blocked_str])
	# Navmesh-Polygone dumpen: Inseln über Kanten-Zusammenhang finden.
	var nm: NavigationMesh = room._nav_region.navigation_mesh
	var verts := nm.get_vertices()
	print("NAVMESH verts=%d polys=%d" % [verts.size(), nm.get_polygon_count()])
	var poly_center: Array[Vector3] = []
	var parent_of: Array[int] = []
	for pi in nm.get_polygon_count():
		parent_of.append(pi)
		var poly := nm.get_polygon(pi)
		var c := Vector3.ZERO
		for vi in poly:
			c += verts[vi]
		poly_center.append(c / poly.size())
	# Union-Find über geteilte Vertices.
	var owner_poly: Dictionary = {}
	for pi in nm.get_polygon_count():
		for vi in nm.get_polygon(pi):
			if owner_poly.has(vi):
				var a := pi
				while parent_of[a] != a:
					a = parent_of[a]
				var b: int = owner_poly[vi]
				while parent_of[b] != b:
					b = parent_of[b]
				parent_of[a] = b
			else:
				owner_poly[vi] = pi
	var islands: Dictionary = {}
	for pi in nm.get_polygon_count():
		var r := pi
		while parent_of[r] != r:
			r = parent_of[r]
		if not islands.has(r):
			islands[r] = []
		(islands[r] as Array).append(pi)
	for r: int in islands.keys():
		var mins := Vector3(99, 99, 99)
		var maxs := Vector3(-99, -99, -99)
		for pi: int in islands[r]:
			mins = mins.min(poly_center[pi])
			maxs = maxs.max(poly_center[pi])
		print(
			(
				"INSEL %d: polys=%d  x %.2f..%.2f  z %.2f..%.2f"
				% [r, (islands[r] as Array).size(), mins.x, maxs.x, mins.z, maxs.z]
			)
		)
	gooby.global_position = Vector3(5.25, 0.0, 4.5)
	await physics_frame
	gooby.walk_to(Vector3(0.75, 0.0, 0.75), 20.0)
	await physics_frame
	print("PFAD size=%d" % gooby._path.size())
	for i in gooby._path.size():
		print(
			(
				"  wp[%d] = (%.3f, %.3f, %.3f)"
				% [i, gooby._path[i].x, gooby._path[i].y, gooby._path[i].z]
			)
		)
	var frame := 0
	while gooby._walking and frame < 900:
		await physics_frame
		frame += 1
		if frame % 20 == 0:
			var p := gooby.global_position
			print(
				(
					"f=%03d pos=(%.3f, %.3f) idx=%d/%d"
					% [frame, p.x, p.z, gooby._path_index, gooby._path.size()]
				)
			)
	print("ENDE f=%d pos=%v" % [frame, gooby.global_position])
	quit(0)
