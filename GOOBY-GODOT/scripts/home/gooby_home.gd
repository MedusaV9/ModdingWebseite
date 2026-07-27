class_name GoobyHome
extends Node3D
## Gooby im Raum (W2a HOUSE, Doc F §7): W1b-GoobyRig + Navmesh-Pfadverfolgung,
## Idle-Streifzüge über freie Standplätze (12 Zufalls-Samples), skriptbares
## walk_to() für Tür-Reisen und der Spidergooby-Decken-Gag (Doc F §6).
##
## FIX2-Movement (P0, zweiteilige Ursache):
## (1) Der frühere NavigationAgent3D verglich Distanzen in 3D — die gebackenen
##     Navmesh-Wegpunkte liegen aber ~0.58 m ÜBER Goobys Origin (Voxel-Höhe
##     cell_height 0.25), womit path_desired_distance (0.2) nie erreichbar
##     war: der Pfad-Index blieb bei 0 stehen und Gooby pendelte im
##     2-Frame-Ping-Pong um den ersten Wegpunkt.
## (2) Das gebackene Navmesh selbst ist degeneriert: Visual-Mesh-Parsing +
##     agent_radius 0.28 bei cell_size 0.25 erodieren das 6×5-m-Wohnzimmer
##     auf 8 Polygone, die nur die Raummitte abdecken (plus abgetrennte
##     Mini-Inseln) — Navmesh-Pfade enden mitten im Raum.
## Deshalb läuft Gooby jetzt über das GRID (die autoritative Möbel-Belegung,
## GridData.walkable): BFS über begehbare Zellen + String-Pulling für weiche
## Diagonalen, Wegpunkt-Fortschritt rein in XZ.

signal arrived

const SPEED := 1.15
const WANDER_WAIT_MIN := 4.0
const WANDER_WAIT_MAX := 9.0
const IDLE_SPOT_SAMPLES := 12
const CEILING_Y := 2.3
## XZ-Abstand, ab dem ein Wegpunkt als erreicht gilt (Pfad-Index rückt vor).
const WAYPOINT_DIST := 0.08
## XZ-Abstand, ab dem das Ziel als erreicht gilt.
const ARRIVE_DIST := 0.15
## Ohne Grid (Raum noch im Aufbau) regelmäßig neu anfragen statt dauerhaft
## blind geradeaus zu laufen.
const PATH_RETRY_S := 0.5
## Goobys Körperradius fürs String-Pulling: Diagonalen brauchen seitlich so
## viel freie Zelle, damit die Silhouette nicht in Möbeln hängt.
const KOERPER_RADIUS := 0.2
## Abtastschritt der Sichtlinien-Prüfung (deutlich unter CELL_SIZE 0.5).
const LOS_SCHRITT := 0.1

var rig: GoobyRig
var grid: GridData
## REST-3 (Pflege): Tempo-Faktor 0..1 — müde/kranke Goobys watscheln
## sichtbar langsamer (PflegeRunner setzt das; 1.0 = normal).
var speed_mult := 1.0

var _wander_enabled := true
var _wander_timer := 0.0
var _walking := false
var _scripted := false
var _last_cell := Vector2i(-99, -99)
var _rng := RandomNumberGenerator.new()
var _target := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_retry := 0.0


func _ready() -> void:
	rig = GoobyRig.new()
	add_child(rig)
	# FIX-F-Handoff: gespeicherte Char-Editor-Morphs auf den Spieler-Gooby anwenden.
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		rig.apply_saved_morphs(gs)
	add_child(_make_blob_shadow())
	_wander_timer = _rng.randf_range(1.0, 3.0)


## Blob-Shadow (W4-P3 POLISH-6, Doc A §7): weicher Schattenfleck statt
## teurer Echtzeit-Schatten — die Raum-Sonne rendert ohne Shadow-Map.
func _make_blob_shadow() -> MeshInstance3D:
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	quad.orientation = PlaneMesh.FACE_Y
	blob.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _blob_textur()
	mat.no_depth_test = false
	blob.material_override = mat
	blob.position = Vector3(0.0, 0.02, 0.0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return blob


## Radialer Schwarz-nach-transparent-Verlauf (kein Asset nötig).
static func _blob_textur() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.24, 0.18, 0.14, 0.4))
	gradient.set_color(1, Color(0.24, 0.18, 0.14, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


func set_wander_enabled(enabled: bool) -> void:
	_wander_enabled = enabled
	if not enabled:
		_stop_walking()


## Clip-Proxy auf den W1b-Rig (DoorTransition ruft Clips per Duck-Typing).
func play_clip(clip: String) -> void:
	rig.play_clip(clip)


## Skriptbarer Lauf (Tür-Reise): läuft zur Position, feuert `arrived`.
## Awaitbar; bricht nach `timeout_s` ab (Navmesh-Lücken nie deadlocken).
func walk_to(world_pos: Vector3, timeout_s := 6.0) -> void:
	_scripted = true
	_start_walking(world_pos)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while _walking and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_stop_walking()
	_scripted = false
	arrived.emit()


## Laufenden Skript-Lauf sofort abbrechen (W4-P3: responsiver Tür-Skip —
## das awaitende walk_to kehrt im nächsten Frame zurück).
func cancel_walk() -> void:
	_stop_walking()


## Aktuelle Grid-Zelle (für Blockade-Checks der Türen).
func current_cell() -> Vector2i:
	return GridData.cell_of(global_position)


## BODEN-IST-LAVA-Gag (Doc F §6): Panik, Sprung an die Decke, Hold,
## Plumps zurück. Awaitbar; Bubble-Texte macht RoomBase.
## Reduced Motion (W4-P3 POLISH-16): Instant-Pfad ohne Bounce-Tweens.
func spidergooby_gag(hold_s := 2.2) -> void:
	set_wander_enabled(false)
	var floor_pos := global_position
	rig.set_emotion("scared")
	rig.play_clip("hop")
	if _reduced_motion():
		global_position.y = CEILING_Y
		rig.rotation.z = PI
		rig.set_emotion("ecstatic")
		await get_tree().create_timer(minf(hold_s, 0.8)).timeout
		global_position.y = floor_pos.y
		rig.rotation.z = 0.0
	else:
		var up := create_tween()
		up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		up.tween_property(self, "global_position:y", CEILING_Y, 0.45)
		up.parallel().tween_property(rig, "rotation:z", PI, 0.45)
		await up.finished
		rig.set_emotion("ecstatic")
		await get_tree().create_timer(hold_s).timeout
		var down := create_tween()
		down.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		down.tween_property(self, "global_position:y", floor_pos.y, 0.5)
		down.parallel().tween_property(rig, "rotation:z", 0.0, 0.4)
		await down.finished
	rig.set_emotion("happy")
	rig.play_clip("idle")
	set_wander_enabled(true)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


func _physics_process(delta: float) -> void:
	if _walking:
		_step_walk(delta)
		return
	if not _wander_enabled or _scripted or grid == null:
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(WANDER_WAIT_MIN, WANDER_WAIT_MAX)
		var spot := _pick_idle_spot()
		if spot != Vector3.INF:
			_start_walking(spot)


## Freie-Standplatz-Suche (Doc F §7): 12 Samples aus freien Grid-Zellen,
## erreichbar (BFS) und nicht der letzte Spot.
func _pick_idle_spot() -> Vector3:
	var free := grid.free_cells()
	if free.is_empty():
		return Vector3.INF
	var from := current_cell()
	for _i in IDLE_SPOT_SAMPLES:
		var cell: Vector2i = free[_rng.randi_range(0, free.size() - 1)]
		if cell == _last_cell or grid.blocked.has(cell):
			continue
		if not grid.is_reachable(from, cell):
			continue
		_last_cell = cell
		return GridData.world_center(cell, Vector2i.ONE, 0)
	return Vector3.INF


func _start_walking(world_pos: Vector3) -> void:
	_target = world_pos
	_compute_path()
	_walking = true
	rig.set_locomotion(1.0)


func _stop_walking() -> void:
	_walking = false
	rig.set_locomotion(0.0)


## Pfad übers Grid planen (statt Navmesh — s. Kopf): BFS von der eigenen
## Zelle zur Zielzelle, dann String-Pulling. Kommt die BFS nicht bis zum
## Ziel (Zelle belegt/abgeschnitten), endet der Pfad an der nächsten
## erreichbaren Zelle — _step_walk stoppt dort, statt Möbel zu pflügen.
## Leerer Pfad = noch kein Grid; _step_walk fragt dann per PATH_RETRY_S-Takt
## nach und läuft solange gerade aufs Ziel zu.
func _compute_path() -> void:
	_path_index = 0
	_path_retry = PATH_RETRY_S
	_path = PackedVector3Array()
	if grid == null:
		return
	var start_cell := _nearest_walkable(GridData.cell_of(global_position))
	var ziel_cell := GridData.cell_of(_target)
	var cells := _grid_path(start_cell, ziel_cell)
	if cells.is_empty():
		return
	var pts := PackedVector3Array()
	pts.append(_xz(global_position))
	for cell: Vector2i in cells:
		pts.append(GridData.world_center(cell, Vector2i.ONE, 0))
	# Zielzelle erreicht → das exakte Ziel innerhalb der Zelle anfahren.
	if cells[cells.size() - 1] == ziel_cell:
		pts.append(_xz(_target))
	_path = _string_pulling(pts)


## Nächste begehbare Zelle (Ring-Suche) — falls Gooby z. B. per Baumodus
## knapp in eine Möbel-Zelle geschoben wurde.
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if grid.walkable(cell):
		return cell
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var kandidat := cell + Vector2i(dx, dy)
				if grid.walkable(kandidat):
					return kandidat
	return cell


## BFS über begehbare Zellen (4er-Nachbarschaft, wie GridData.is_reachable).
## Liefert die Zellfolge von `from_cell` bis `to_cell` — oder, wenn das Ziel
## nicht erreichbar ist, bis zur erreichbaren Zelle mit dem kleinsten
## Restabstand. Leer nur, wenn schon die Startzelle unbegehbar ist.
func _grid_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	if not grid.walkable(from_cell):
		return []
	var parent := {from_cell: from_cell}
	var frontier: Array[Vector2i] = [from_cell]
	var lese := 0
	var best := from_cell
	var best_d := (to_cell - from_cell).length_squared()
	var found := from_cell == to_cell
	while lese < frontier.size() and not found:
		var cell: Vector2i = frontier[lese]
		lese += 1
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			if parent.has(next) or not grid.walkable(next):
				continue
			parent[next] = cell
			var d := (to_cell - next).length_squared()
			if d < best_d:
				best_d = d
				best = next
			if next == to_cell:
				found = true
				break
			frontier.append(next)
	var ende := to_cell if found else best
	var out: Array[Vector2i] = []
	var cur := ende
	while cur != from_cell:
		out.push_front(cur)
		cur = parent[cur]
	out.push_front(from_cell)
	return out


## String-Pulling: Zwischenpunkte überspringen, solange die Direktlinie
## (inkl. seitlichem KOERPER_RADIUS) durch begehbare Zellen führt — macht
## aus BFS-Treppen weiche Diagonalen. Der direkte Folgepunkt wird immer
## akzeptiert (garantierter Fortschritt).
func _string_pulling(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _segment_frei(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func _segment_frei(a: Vector3, b: Vector3) -> bool:
	var d := _xz(b - a)
	var laenge := d.length()
	if laenge < 0.001:
		return true
	var dir := d / laenge
	var seite := Vector3(-dir.z, 0.0, dir.x) * KOERPER_RADIUS
	var steps := int(ceilf(laenge / LOS_SCHRITT))
	for s in steps + 1:
		var p: Vector3 = a + dir * (laenge * float(s) / float(steps))
		if not grid.walkable(GridData.cell_of(p)):
			return false
		if not grid.walkable(GridData.cell_of(p + seite)):
			return false
		if not grid.walkable(GridData.cell_of(p - seite)):
			return false
	return true


static func _xz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _step_walk(delta: float) -> void:
	var to_target := _xz(_target - global_position)
	if to_target.length() <= ARRIVE_DIST:
		_stop_walking()
		return
	if _path.size() < 2:
		_path_retry -= delta
		if _path_retry <= 0.0:
			_compute_path()
	# Erreichte Wegpunkte rein in XZ abhaken (nie in 3D vergleichen — genau
	# der 3D-Vergleich hat den alten Agent stallen lassen, s. Kopf).
	while (
		_path_index < _path.size()
		and _xz(_path[_path_index] - global_position).length() <= WAYPOINT_DIST
	):
		_path_index += 1
	var to_next := to_target
	if _path_index < _path.size():
		to_next = _xz(_path[_path_index] - global_position)
	elif _path.size() >= 2:
		# Pfadende erreicht, Ziel aber weiter weg (Zielzelle belegt oder
		# abgeschnitten): hier stehen bleiben statt Möbel zu pflügen.
		_stop_walking()
		return
	var step := to_next.normalized() * SPEED * clampf(speed_mult, 0.25, 1.0) * delta
	if step.length() > to_next.length():
		step = to_next
	global_position += step
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to_next.x, to_next.z), 10.0 * delta)
	rig.set_locomotion(1.0)
