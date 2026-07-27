extends TestCase
## Regressionstests für die REST5-Bugfixes (EVAL-2 P1/P2):
## - B2  Timer-Lambdas mit Node-Captures → Methoden-/gebundene Callables
## - B3  Navigation-Map-Sync-Fehler → eigene NavigationServer-Map je Raum
## - B5  Navmesh-GPU-Readback → CPU-Quellgeometrie (Boden + Blocker-AABBs)
## - B10 agent_radius/agent_max_climb voxel-exakt (keine Präzisionswarnung)
## - SubViewport-Größenkonflikt (stretch + manuelle size) in der Möbel-Vitrine
## - SpatialMaterial-3.x-Property `specular` in fx3d.gd

const FX3D := "res://scripts/minigames/games/_3db_stage/fx3d.gd"

## Timer-Lambda-Allowlist: Datei → maximal erlaubte Lambda-Verbindungen auf
## timeout-Signale. NUR für verifiziert sichere Muster: reine self-Lambdas
## (nur Member-Zugriffe — räumt Godot beim Free von self ab) oder Lambdas
## auf Timer-NODES, die mit ihrer Szene sterben. funkelpark: 1× self-Lambda
## auf SceneTreeTimer (Musik-Blende), 1× Lambda auf Timer-Node (_caption) —
## belegter Bereich (scripts/park), s. /tmp/gooby-godot/handoffs/
## REST5-findings.md.
const TIMER_LAMBDA_ALLOW: Dictionary = {"res://scripts/park/funkelpark.gd": 2}

# ── B10: Navmesh-Werte voxel-exakt ───────────────────────────────────────────


func test_navmesh_werte_voxel_exakt() -> void:
	var mesh := RoomNavmesh.make_mesh()
	assert_almost(mesh.cell_size, RoomNavmesh.CELL, 1e-6, "cell_size")
	assert_almost(mesh.cell_height, RoomNavmesh.CELL, 1e-6, "cell_height")
	# Radius/Steighöhe MÜSSEN auf dem Voxelraster liegen, sonst warnt der
	# Generator mit "loses precision" (ceil/floor auf Zellgröße).
	assert_almost(fmod(mesh.agent_radius, mesh.cell_size), 0.0, 1e-6, "agent_radius nicht Voxel")
	assert_almost(
		fmod(mesh.agent_max_climb, mesh.cell_height), 0.0, 1e-6, "agent_max_climb nicht Voxel"
	)


# ── B3: eigene Navigation-Map je Raum ────────────────────────────────────────


func test_private_map_lebenszyklus() -> void:
	var region := NavigationRegion3D.new()
	region.navigation_mesh = RoomNavmesh.make_mesh()
	tree.root.add_child(region)
	var map := RoomNavmesh.attach_private_map(region)
	assert_true(map.is_valid(), "attach_private_map muss eine gültige RID liefern")
	# NavigationServer-Kommandos werden erst beim Physik-Sync ausgeführt.
	await tree.physics_frame
	await tree.physics_frame
	assert_eq(NavigationServer3D.region_get_map(region.get_rid()), map, "Region nicht umgehängt")
	var default_map := region.get_world_3d().navigation_map
	assert_ne(map, default_map, "private Map darf nicht die geteilte World-Map sein")
	assert_almost(NavigationServer3D.map_get_cell_size(map), RoomNavmesh.CELL, 1e-6)
	# Aufräumen wie in RoomBase._exit_tree: erst Region raus, dann Map frei.
	region.queue_free()
	await wait_frames(2)
	var leer := RoomNavmesh.free_private_map(map)
	assert_false(leer.is_valid(), "free_private_map muss RID() zurückgeben")
	# Idempotent: zweiter Aufruf mit RID() darf nichts tun (kein Fehler).
	RoomNavmesh.free_private_map(leer)


func test_zwei_raeume_bekommen_verschiedene_maps() -> void:
	# Kern von B3: überlappen zwei Räume kurz (Szenenwechsel), dürfen ihre
	# identischen Polygone nie auf derselben Map landen.
	var region_a := NavigationRegion3D.new()
	var region_b := NavigationRegion3D.new()
	tree.root.add_child(region_a)
	tree.root.add_child(region_b)
	var map_a := RoomNavmesh.attach_private_map(region_a)
	var map_b := RoomNavmesh.attach_private_map(region_b)
	assert_ne(map_a, map_b, "jeder Raum braucht seine eigene Map")
	region_a.queue_free()
	region_b.queue_free()
	await wait_frames(2)
	RoomNavmesh.free_private_map(map_a)
	RoomNavmesh.free_private_map(map_b)


# ── B5: CPU-Bake statt GPU-Readback ──────────────────────────────────────────


func test_cpu_bake_erzeugt_polygone() -> void:
	var region := NavigationRegion3D.new()
	region.navigation_mesh = RoomNavmesh.make_mesh()
	tree.root.add_child(region)
	var map := RoomNavmesh.attach_private_map(region)
	RoomNavmesh.bake(region, Vector2(4.0, 4.0), [])
	assert_true(region.navigation_mesh.get_polygon_count() > 0, "Boden-Bake liefert Polygone")
	region.queue_free()
	await wait_frames(2)
	RoomNavmesh.free_private_map(map)


func test_cpu_bake_blocker_verkleinert_flaeche() -> void:
	var region := NavigationRegion3D.new()
	region.navigation_mesh = RoomNavmesh.make_mesh()
	tree.root.add_child(region)
	var map := RoomNavmesh.attach_private_map(region)
	RoomNavmesh.bake(region, Vector2(4.0, 4.0), [])
	var frei := _navmesh_flaeche(region.navigation_mesh)
	# Blocker: 1×1×0,5-m-Kiste mitten im Raum (Visual-AABB, kein Readback).
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 1.0)
	blocker.mesh = box
	blocker.position = Vector3(2.0, 0.25, 2.0)
	tree.root.add_child(blocker)
	await wait_frames(1)
	RoomNavmesh.bake(region, Vector2(4.0, 4.0), [blocker])
	var verstellt := _navmesh_flaeche(region.navigation_mesh)
	assert_true(verstellt > 0.0, "auch mit Blocker bleibt begehbare Fläche")
	assert_true(
		verstellt < frei - 0.1,
		"Blocker muss die begehbare Fläche verkleinern (%f !< %f)" % [verstellt, frei]
	)
	# Flache Deko (unter MIN_BLOCKER_HOEHE) darf NICHT blockieren.
	var deko := MeshInstance3D.new()
	var teppich := BoxMesh.new()
	teppich.size = Vector3(1.0, 0.02, 1.0)
	deko.mesh = teppich
	deko.position = Vector3(1.0, 0.01, 1.0)
	tree.root.add_child(deko)
	await wait_frames(1)
	RoomNavmesh.bake(region, Vector2(4.0, 4.0), [deko])
	assert_almost(_navmesh_flaeche(region.navigation_mesh), frei, 0.05, "Deko blockt nicht")
	blocker.queue_free()
	deko.queue_free()
	region.queue_free()
	await wait_frames(2)
	RoomNavmesh.free_private_map(map)


## Begehbare Fläche des NavigationMesh in m² (Fächer-Triangulierung je Polygon).
func _navmesh_flaeche(mesh: NavigationMesh) -> float:
	var vertices := mesh.get_vertices()
	var summe := 0.0
	for i in mesh.get_polygon_count():
		var poly := mesh.get_polygon(i)
		for j in range(1, poly.size() - 1):
			var a := vertices[poly[0]]
			var b := vertices[poly[j]]
			var c := vertices[poly[j + 1]]
			summe += (b - a).cross(c - a).length() * 0.5
	return summe


# ── SubViewport: stretch-Container bestimmt die Größe ────────────────────────


func test_showcase_ueberlaesst_groesse_dem_stretch_container() -> void:
	var showcase := FurnitureShowcase.new()
	showcase.size = Vector2(300.0, 200.0)
	tree.root.add_child(showcase)
	await wait_frames(2)
	# Das alte manuelle Resize-Handling (Warnspam-Quelle) muss weg bleiben.
	assert_false(showcase.has_method("_on_resized"), "manuelles Viewport-Resize ist zurück")
	var container: SubViewportContainer = null
	for child in showcase.get_children():
		if child is SubViewportContainer:
			container = child
	assert_true(container != null, "Showcase braucht einen SubViewportContainer")
	if container != null:
		assert_true(container.stretch, "Container muss stretch behalten")
		var viewport: SubViewport = null
		for child in container.get_children():
			if child is SubViewport:
				viewport = child
		assert_true(viewport != null, "Container braucht den SubViewport")
		if viewport != null:
			showcase.size = Vector2(320.0, 240.0)
			await wait_frames(2)
			assert_eq(viewport.size, Vector2i(320, 240), "stretch muss die Größe nachziehen")
	showcase.queue_free()
	await wait_frames(1)


# ── fx3d.gd: Godot-4-Property statt SpatialMaterial-Remap ────────────────────


func test_fx3d_flat_nutzt_metallic_specular() -> void:
	var fx: GDScript = load(FX3D)
	var mat: StandardMaterial3D = fx.flat(Color.RED)
	assert_almost(mat.metallic_specular, 0.0, 1e-6, "flat() setzt keinen Glanzanteil")
	var quelle := FileAccess.get_file_as_string(FX3D)
	assert_false(
		quelle.contains("mat.specular"),
		"fx3d.gd nutzt wieder das Godot-3-Property `specular` (Warnspam)"
	)


# ── B4: Vorlagen-Nodes außerhalb des Baums müssen beim Exit sterben ──────────


func test_star_hopper_gold_vorlage_wird_freigegeben() -> void:
	# `_gold` (carrot.glb) ist reine duplicate()-Vorlage und hängt nie im
	# Baum — vor dem Fix leakte der Teilbaum samt Meshes/Materialien beim
	# Beenden (RID-/ObjectDB-/Resource-Meldungen im Walkthrough).
	var stage_script: GDScript = load(
		"res://scripts/minigames/games/star_hopper/star_hopper_stage.gd"
	)
	var stage: Node3D = stage_script.new()
	tree.root.add_child(stage)
	# Die Bühne baut sich erst in setup_stage (Aufrufer ist star_hopper.gd).
	stage.setup_stage([-1.15, 0.0, 1.15])
	await wait_frames(3)
	var vorlage: Node3D = stage.get("_gold")
	if vorlage == null:
		fail_test("Stage baut die Karotten-Vorlage nicht")
		stage.queue_free()
		await wait_frames(1)
		return
	assert_false(vorlage.is_inside_tree(), "Vorlage gehört nicht in den Baum")
	var beobachter: WeakRef = weakref(vorlage)
	stage.queue_free()
	await wait_frames(3)
	assert_true(beobachter.get_ref() == null, "Karotten-Vorlage leakt nach Stage-Free")


# ── B2: keine Timer-Lambdas mit Node-Captures im Quellcode ───────────────────


func test_keine_timer_lambdas_im_quellcode() -> void:
	# Tripwire: `<timer>.timeout.connect(func …)` loggt "Lambda capture …
	# was freed", sobald ein gecapturter Node vor dem Timeout stirbt —
	# Methoden-Callables räumt Godot dagegen automatisch ab.
	var funde: Dictionary = {}
	_scan_timer_lambdas("res://scripts", funde)
	for pfad: String in funde:
		var erlaubt := int(TIMER_LAMBDA_ALLOW.get(pfad, 0))
		assert_true(
			int(funde[pfad]) <= erlaubt,
			(
				(
					"%s: %d Timer-Lambda(s) gefunden (erlaubt: %d) — bitte Methoden-"
					% [pfad, funde[pfad], erlaubt]
				)
				+ "Callable oder .bind() verwenden (REST5, EVAL-2 B2)"
			)
		)


func _scan_timer_lambdas(dir_path: String, funde: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var pfad := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			_scan_timer_lambdas(pfad, funde)
		elif name.ends_with(".gd"):
			var anzahl := _zaehle_timer_lambdas(pfad)
			if anzahl > 0:
				funde[pfad] = anzahl
		name = dir.get_next()
	dir.list_dir_end()


func _zaehle_timer_lambdas(pfad: String) -> int:
	var zeilen := FileAccess.get_file_as_string(pfad).split("\n")
	var anzahl := 0
	for i in zeilen.size():
		var zeile := zeilen[i]
		if not zeile.contains("timeout.connect("):
			continue
		var rest := zeile.get_slice("timeout.connect(", 1).strip_edges()
		if rest.begins_with("func"):
			anzahl += 1
		elif rest.is_empty() and i + 1 < zeilen.size():
			# Mehrzeilige Form: `timeout.connect(` + nächste Zeile `func …`.
			if zeilen[i + 1].strip_edges().begins_with("func"):
				anzahl += 1
	return anzahl
