class_name RoomNavmesh
extends RefCounted
## Gemeinsamer Raum-Navmesh-Baustein (REST5, EVAL-2 B3/B5/B10) für
## RoomBase und VisitRoomView. Drei Probleme des alten Pfads werden hier
## zentral gelöst:
##
## - B5: `bake_navigation_mesh()` parste Visual-Meshes zur LAUFZEIT über den
##   RenderingServer (GPU→CPU-Readback, Godot warnt vor "significant
##   performance issues"). Jetzt wird die Quellgeometrie CPU-seitig gebaut:
##   ein Boden-Rechteck plus ein projizierter Blocker-Quader je
##   bewegungsblockierendem Möbel/Bauwerk (aus deren CPU-AABBs).
## - B3: Beim Szenenwechsel/Testlauf überlappen alter und neuer Raum kurz
##   auf der geteilten World-Map — identische Polygone lösten
##   "Navigation map synchronization error" aus. Jeder Raum bekommt deshalb
##   seine EIGENE NavigationServer-Map (Gooby läuft ohnehin übers Bau-Grid,
##   gooby_home.gd — niemand fragt die Default-Map ab).
## - B10: agent_radius/agent_max_climb liegen exakt auf dem Voxelraster
##   (Vielfache von CELL 0.25) — 0.28/0.3 wurden vom Generator gerundet und
##   spammten "loses precision"-Warnungen.
##
## WICHTIG: Die eigene Map MUSS beim Verlassen des Baums über
## `free_private_map()` freigegeben werden, sonst leakt die RID (B4).

## MUSS zur NavigationMesh-Zellgröße passen (Godot-Default 0.25).
const CELL := 0.25
## Mindesthöhe eines Blocker-Quaders — flache Deko blockt nicht.
const MIN_BLOCKER_HOEHE := 0.26


## Voxel-exakt konfiguriertes NavigationMesh für einen Raum.
static func make_mesh() -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = CELL
	nav_mesh.agent_height = 1.0
	nav_mesh.agent_max_climb = CELL
	nav_mesh.cell_size = CELL
	nav_mesh.cell_height = CELL
	return nav_mesh


## Eigene, aktive Navigation-Map erzeugen und die Region dorthin umhängen.
## Rückgabe: die Map-RID (vom Aufrufer in _exit_tree freigeben!).
static func attach_private_map(region: NavigationRegion3D) -> RID:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL)
	NavigationServer3D.map_set_active(map, true)
	NavigationServer3D.region_set_map(region.get_rid(), map)
	return map


## Private Map freigeben (idempotent). Rückgabe: RID() zum Zurückschreiben.
static func free_private_map(map: RID) -> RID:
	if map.is_valid():
		NavigationServer3D.free_rid(map)
	return RID()


## Navmesh synchron aus CPU-Geometrie backen: begehbares Boden-Rechteck
## `size` (Meter, ab Ursprung der Region) minus projizierte Blocker-Quader.
## `blocker_roots`: Nodes, deren Visual-AABBs als Hindernis zählen.
static func bake(region: NavigationRegion3D, size: Vector2, blocker_roots: Array) -> void:
	if region == null or region.navigation_mesh == null:
		return
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(_floor_faces(size), Transform3D.IDENTITY)
	for root: Variant in blocker_roots:
		if not (root is Node3D and is_instance_valid(root)):
			continue
		var aabb := blocker_aabb(region, root as Node3D)
		if aabb.size.x <= 0.0 or aabb.size.z <= 0.0:
			continue
		if aabb.size.y < MIN_BLOCKER_HOEHE:
			continue
		source.add_projected_obstruction(
			_footprint(aabb), aabb.position.y, maxf(aabb.size.y, 1.0), false
		)
	# Synchroner CPU-Bake; das NavigationMesh meldet sich der Region über
	# sein changed-Signal selbst.
	NavigationServer3D.bake_from_source_geometry_data(region.navigation_mesh, source)


## Zusammengefasste Visual-AABB eines Teilbaums im Regions-Raum — rein aus
## den CPU-seitig vorliegenden Instanz-AABBs (kein Mesh-Readback).
static func blocker_aabb(region: NavigationRegion3D, node: Node3D) -> AABB:
	var into_region := region.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
		if current is VisualInstance3D and (current as VisualInstance3D).is_inside_tree():
			var vi := current as VisualInstance3D
			var local := (into_region * vi.global_transform) * vi.get_aabb()
			if first:
				merged = local
				first = false
			else:
				merged = merged.merge(local)
	return merged


## Zwei Dreiecke über das Boden-Rechteck. Die Wicklung ist die, die der
## Navmesh-Generator als begehbare Oberseite akzeptiert — andersherum backt
## er ein LEERES Mesh (0 Polygone; empirisch verifiziert, s. Regressionstest
## test_cpu_bake_erzeugt_polygone).
static func _floor_faces(size: Vector2) -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(0.0, 0.0, 0.0),
			Vector3(size.x, 0.0, 0.0),
			Vector3(size.x, 0.0, size.y),
			Vector3(0.0, 0.0, 0.0),
			Vector3(size.x, 0.0, size.y),
			Vector3(0.0, 0.0, size.y),
		]
	)


## XZ-Grundriss einer AABB als Obstruction-Umriss (y wird projiziert).
static func _footprint(aabb: AABB) -> PackedVector3Array:
	var x0 := aabb.position.x
	var z0 := aabb.position.z
	var x1 := aabb.position.x + aabb.size.x
	var z1 := aabb.position.z + aabb.size.z
	return PackedVector3Array(
		[Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1)]
	)
