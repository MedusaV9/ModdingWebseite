class_name GoobyHome
extends Node3D
## Gooby im Raum (W2a HOUSE, Doc F §7): W1b-GoobyRig + NavigationAgent3D,
## Idle-Streifzüge über freie Standplätze (12 Zufalls-Samples), skriptbares
## walk_to() für Tür-Reisen und der Spidergooby-Decken-Gag (Doc F §6).

signal arrived

const SPEED := 1.15
const WANDER_WAIT_MIN := 4.0
const WANDER_WAIT_MAX := 9.0
const IDLE_SPOT_SAMPLES := 12
const CEILING_Y := 2.3

var rig: GoobyRig
var agent: NavigationAgent3D
var grid: GridData

var _wander_enabled := true
var _wander_timer := 0.0
var _walking := false
var _scripted := false
var _last_cell := Vector2i(-99, -99)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	rig = GoobyRig.new()
	add_child(rig)
	agent = NavigationAgent3D.new()
	agent.radius = 0.28
	agent.path_desired_distance = 0.2
	agent.target_desired_distance = 0.2
	agent.avoidance_enabled = false
	add_child(agent)
	_wander_timer = _rng.randf_range(1.0, 3.0)


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


## Aktuelle Grid-Zelle (für Blockade-Checks der Türen).
func current_cell() -> Vector2i:
	return GridData.cell_of(global_position)


## BODEN-IST-LAVA-Gag (Doc F §6): Panik, Sprung an die Decke, Hold,
## Plumps zurück. Awaitbar; Bubble-Texte macht RoomBase.
func spidergooby_gag(hold_s := 2.2) -> void:
	set_wander_enabled(false)
	var floor_pos := global_position
	rig.set_emotion("scared")
	rig.play_clip("hop")
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
	agent.target_position = world_pos
	_walking = true
	rig.set_locomotion(1.0)


func _stop_walking() -> void:
	_walking = false
	rig.set_locomotion(0.0)


func _step_walk(delta: float) -> void:
	var to_target := agent.target_position - global_position
	to_target.y = 0.0
	if to_target.length() <= 0.15 or agent.is_navigation_finished():
		_stop_walking()
		return
	var next := agent.get_next_path_position()
	var to_next := next - global_position
	to_next.y = 0.0
	if to_next.length() < 0.02:
		# Kein Navmesh (frisch gebaked/Headless): gerade aufs Ziel zu.
		to_next = to_target
	var step := to_next.normalized() * SPEED * delta
	if step.length() > to_next.length():
		step = to_next
	global_position += step
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to_next.x, to_next.z), 10.0 * delta)
	rig.set_locomotion(1.0)
