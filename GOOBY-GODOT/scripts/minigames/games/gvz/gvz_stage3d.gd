extends Node3D
## ECHTER 3D-VORGARTEN für GvZ (FB-4): das Tower-Defense spielt auf einem
## Rasen-Schachbrett vor Gartenzaun, Bäumen und dem Haus mit Holzveranda —
## Türme, Zombies, Boss-Müllwagen, Projektile, Nutella-Kleckse, Panik-Mäher
## und die Nebelwand sind echte Meshes (Fabrik: gvz_stage3d_props.gd), Gooby
## (echtes Rig) verteidigt auf der Veranda. ALLE Anker kommen als CANVAS-PIXEL
## aus der View und werden per ground_point-Raycast auf den Boden gelegt —
## Zellen und Tap-Ziele bleiben EXAKT unter dem Finger, die MECHANIK
## (GvzLogic) bleibt zahlengleich.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Props := preload("res://scripts/minigames/games/gvz/gvz_stage3d_props.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const LANES := 5
const COLS := 9

const LAWN_A := Color("#8FC168")
const LAWN_B := Color("#7EB258")
const LAWN_A_NIGHT := Color("#6E8F64")
const LAWN_B_NIGHT := Color("#5F8056")

var stage: Node3D
var gooby: Node3D

## Raycast-Ergebnis des Layouts: [lane][col] → Bodenpunkt, plus Zellmaße.
var _cell_pos: Array = []
var _row_w: Array[float] = []
var _row_d: Array[float] = []
var _row_s: Array[float] = []

var _lawn_a: MultiMeshInstance3D
var _lawn_b: MultiMeshInstance3D
var _mat_lawn_a: StandardMaterial3D
var _mat_lawn_b: StandardMaterial3D
var _deck: MeshInstance3D
var _house: Node3D
var _backdrop: Node3D
var _fog_wall: Node3D
var _fog_box: MeshInstance3D
var _fog_puffs: Array[MeshInstance3D] = []
var _ghost: MeshInstance3D
var _mat_ghost_ok: StandardMaterial3D
var _mat_ghost_bad: StandardMaterial3D

var _towers: Dictionary = {}
var _zombies: Dictionary = {}
var _boss: Node3D
var _boss_puffs: Array = []
var _proj_pool: Array[Node3D] = []
var _drop_pool: Array[Node3D] = []
var _mowers: Dictionary = {}

var _place_burst: GPUParticles3D
var _die_burst: GPUParticles3D
var _pop_burst: GPUParticles3D
var _blast_burst: GPUParticles3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Vorgarten-Nachmittag, NICHT überbelichtet.
				"sky_top": Color(0.5, 0.74, 0.93),
				"sky_horizon": Color(0.89, 0.93, 0.88),
				"ground_horizon": Color(0.62, 0.78, 0.5),
				"ground_bottom": Color(0.44, 0.6, 0.36),
				"sun_dir": Vector3(-0.35, -0.8, -0.4),
				"sun_energy": 0.78,
				"ambient": 0.42,
				"fill_energy": 0.22,
				"glow": 0.26,
				"glow_threshold": 0.87,
				"shadow_distance": 34.0,
				"fog": true,
				"fog_color": Color(0.85, 0.92, 0.88),
				"fog_from": 30.0,
				"fog_to": 80.0,
				"far": 120.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(110.0, 80.0), Color(0.45, 0.64, 0.34)))
	_mat_lawn_a = Fx.flat(LAWN_A)
	_mat_lawn_b = Fx.flat(LAWN_B)
	_lawn_a = _make_lawn_multimesh(_mat_lawn_a, 23)
	_lawn_b = _make_lawn_multimesh(_mat_lawn_b, 22)
	add_child(_lawn_a)
	add_child(_lawn_b)
	_deck = MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3.ONE
	deck_mesh.material = Fx.flat(Color("#D9BC8C"))
	_deck.mesh = deck_mesh
	add_child(_deck)
	_house = Props.house()
	add_child(_house)
	_backdrop = Node3D.new()
	add_child(_backdrop)
	_fog_wall = _make_fog_wall()
	add_child(_fog_wall)
	_mat_ghost_ok = Fx.glass(Color(0.45, 0.9, 0.5, 0.4), true)
	_mat_ghost_bad = Fx.glass(Color(0.92, 0.4, 0.38, 0.4), true)
	_ghost = MeshInstance3D.new()
	var ghost_mesh := PlaneMesh.new()
	ghost_mesh.size = Vector2.ONE
	_ghost.mesh = ghost_mesh
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.0)
	gooby.base_emotion = "happy"
	_build_fx()


## Kamera: schräg von oben über die Veranda auf den Rasen — steil genug, dass
## das fast bildschirmfüllende 2D-Feld komplett auf dem Boden landet.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 11.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
	stage.set_half_height(4.8, 10.0)


## Alle 45 Zellen per Raycast EXAKT unter das 2D-Feld legen; Rasen, Veranda,
## Haus, Kulisse und Nebelwand richten sich daran aus. Nach jedem apply_view
## und jedem Levelstart neu aufrufen. `fog_px` < 0 = kein Nebel.
func layout(field: Rect2, night: bool, fog_px: float) -> void:
	_cell_pos.clear()
	_row_w.clear()
	_row_d.clear()
	_row_s.clear()
	var cw := field.size.x / float(COLS)
	var ch := field.size.y / float(LANES)
	for lane in LANES:
		var row: Array = []
		for col in COLS:
			var px := field.position + Vector2((float(col) + 0.5) * cw, (float(lane) + 0.5) * ch)
			row.append(stage.ground_point(px))
		_cell_pos.append(row)
		var mid_x := field.position.x + field.size.x * 0.5
		var top: Vector3 = stage.ground_point(Vector2(mid_x, field.position.y + float(lane) * ch))
		var bot: Vector3 = stage.ground_point(
			Vector2(mid_x, field.position.y + (float(lane) + 1.0) * ch)
		)
		var w := absf((row[1] as Vector3).x - (row[0] as Vector3).x)
		var d := absf(top.z - bot.z)
		_row_w.append(w)
		_row_d.append(d)
		_row_s.append(clampf(d * 0.62, w * 0.5, w * 1.3))
	_apply_night(night)
	_layout_lawn()
	_layout_deck(field)
	_layout_fog(field, fog_px)
	_layout_backdrop()


## Jeden Frame: kompletter Sim-Zustand als Anker-Listen aus der View.
## `data`: tick, towers, zombies, boss, projectiles, drops, mowers, ghost.
func sync(data: Dictionary, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	if _cell_pos.is_empty():
		return
	var tick := int(data.get("tick", 0))
	gooby.rotation.z = sin(float(tick) * 0.06) * 0.03
	_sync_towers(data.get("towers", []), tick)
	_sync_zombies(data.get("zombies", []), tick)
	_sync_boss(data.get("boss", {}), tick)
	_sync_projectiles(data.get("projectiles", []))
	_sync_drops(data.get("drops", []), tick)
	_sync_mowers(data.get("mowers", []), tick)
	_sync_ghost(data.get("ghost", {}))


func cell_world(lane: int, col: int) -> Vector3:
	if lane < 0 or lane >= _cell_pos.size():
		return Vector3.ZERO
	var row: Array = _cell_pos[lane]
	return row[clampi(col, 0, row.size() - 1)]


func row_scale(lane: int) -> float:
	if _row_s.is_empty():
		return 1.0
	return _row_s[clampi(lane, 0, _row_s.size() - 1)]


## ── FX (Anker in Canvas-Pixeln) ──────────────────────────────────────────


func place_fx(px: Vector2) -> void:
	Fx.burst(_place_burst, stage.ground_point(px) + Vector3(0.0, 0.3, 0.0))


func die_fx(px: Vector2) -> void:
	Fx.burst(_die_burst, stage.ground_point(px) + Vector3(0.0, 0.5, 0.0))


func pop_fx(px: Vector2) -> void:
	Fx.burst(_pop_burst, stage.ground_point(px) + Vector3(0.0, 1.0, 0.0))


func blast_fx(px: Vector2) -> void:
	Fx.burst(_blast_burst, stage.ground_point(px) + Vector3(0.0, 0.4, 0.0))
	stage.pulse_glow(0.5)


func mower_fx() -> void:
	gooby.emote("scared", 1.0)


func win_fx() -> void:
	gooby.emote("ecstatic", 1.6)
	gooby.play_for("celebrate", 1.2)
	stage.pulse_glow(0.9)


func lose_fx() -> void:
	gooby.emote("sad", 2.0)


## ── Layout-Bausteine ─────────────────────────────────────────────────────


func _make_lawn_multimesh(mat: StandardMaterial3D, count: int) -> MultiMeshInstance3D:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _layout_lawn() -> void:
	var idx_a := 0
	var idx_b := 0
	for lane in LANES:
		var basis := Basis.IDENTITY.scaled(Vector3(_row_w[lane], 1.0, _row_d[lane] * 1.03))
		for col in COLS:
			var pos: Vector3 = cell_world(lane, col) + Vector3(0.0, 0.012, 0.0)
			if (lane + col) % 2 == 0:
				_lawn_a.multimesh.set_instance_transform(idx_a, Transform3D(basis, pos))
				idx_a += 1
			else:
				_lawn_b.multimesh.set_instance_transform(idx_b, Transform3D(basis, pos))
				idx_b += 1


func _layout_deck(field: Rect2) -> void:
	var back_out: Vector3 = stage.ground_point(Vector2(0.0, field.position.y))
	var back_in: Vector3 = stage.ground_point(field.position)
	var front_in: Vector3 = stage.ground_point(Vector2(field.position.x, field.end.y))
	var width := maxf(0.6, absf(back_in.x - back_out.x)) * 1.15
	var depth := absf(back_in.z - front_in.z) + _row_d[0] * 0.4
	_deck.scale = Vector3(width, 0.14, depth)
	_deck.position = Vector3(back_in.x - width * 0.5, 0.07, (back_in.z + front_in.z) * 0.5)
	# Haus als Kulisse in der hinteren linken Ecke (der 44-px-Steg links ist
	# zu schmal, um das Haus IM Bild neben dem Feld zu zeigen).
	_house.position = Vector3(back_in.x + _row_w[0] * 0.55, 0.0, back_in.z - _row_d[0] * 1.1)
	_house.scale = Vector3.ONE * clampf(_row_s[0] * 0.7, 0.6, 1.6)
	# Gooby wacht SICHTBAR auf dem Steg im vorderen Drittel, Blick zum Feld.
	gooby.position = Vector3(back_in.x - width * 0.5, 0.15, front_in.z - depth * 0.32)
	gooby.scale = Vector3.ONE * clampf(_row_s[3] * 0.85, 0.5, 1.7)
	gooby.rotation.y = PI * 0.5 - 0.55


func _layout_fog(field: Rect2, fog_px: float) -> void:
	_fog_wall.visible = fog_px >= 0.0
	if not _fog_wall.visible:
		return
	var back: Vector3 = stage.ground_point(Vector2(fog_px, field.position.y))
	var front: Vector3 = stage.ground_point(Vector2(fog_px, field.end.y))
	var right_back: Vector3 = stage.ground_point(Vector2(field.end.x, field.position.y))
	var width := maxf(0.5, right_back.x - back.x) + _row_w[0] * 0.4
	var depth := absf(back.z - front.z) + _row_d[0] * 0.6
	var height := _row_s[2] * 1.7
	_fog_box.scale = Vector3(width, height, depth)
	_fog_box.position = Vector3(back.x + width * 0.5, height * 0.5, (back.z + front.z) * 0.5)
	for i in _fog_puffs.size():
		var t := float(i) / float(_fog_puffs.size() - 1)
		var puff := _fog_puffs[i]
		puff.scale = Vector3.ONE * (height * (0.42 + 0.14 * float(i % 2)))
		puff.position = Vector3(
			lerpf(back.x, front.x, 0.2 * float(i % 3)) - _row_w[0] * 0.1,
			height * (0.55 + 0.2 * float(i % 2)),
			lerpf(back.z, front.z, t)
		)


## Kulisse hinter der letzten Reihe. Wichtig: über der Feld-Oberkante bleibt
## nur der schmale Karten-Streifen — Zaun/Bäume müssen KLEIN bleiben, sonst
## ragen sie abgeschnitten ins HUD (erster Wurf: riesige Baum-Silhouetten).
func _layout_backdrop() -> void:
	for child in _backdrop.get_children():
		child.queue_free()
	var back_z: float = (cell_world(0, 0) as Vector3).z - _row_d[0] * 0.7
	var lo_x: float = (cell_world(0, 0) as Vector3).x - _row_w[0] * 0.6
	var hi_x: float = (cell_world(0, COLS - 1) as Vector3).x + _row_w[0] * 0.6
	var unit := _row_s[0]
	var fence_scale := clampf(unit * 0.5, 0.4, 1.3)
	var fence_parts := Models.parts(DIR + "fence_simple.glb", fence_scale)
	var fence_poses: Array = []
	var step := fence_scale * 1.02
	var count := int((hi_x - lo_x) / step) + 1
	for i in count:
		fence_poses.append(
			Transform3D(Basis.IDENTITY, Vector3(lo_x + float(i) * step, 0.0, back_z))
		)
	_backdrop.add_child(Models.swarm(fence_parts, fence_poses))
	var tree_poses: Array = []
	for i in 3:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.4),
				Vector3(
					lerpf(lo_x, hi_x, 0.3 + 0.28 * float(i)),
					0.0,
					back_z - unit * (2.6 + 1.2 * float(i % 2))
				)
			)
		)
	var tree_scale := clampf(unit * 1.3, 1.0, 2.6)
	_backdrop.add_child(
		Models.swarm(Models.parts(DIR + "tree_default.glb", tree_scale), tree_poses)
	)
	var reds: Array = []
	var yellows: Array = []
	for i in 8:
		var pose := Transform3D(
			Basis.IDENTITY,
			Vector3(
				lerpf(lo_x, hi_x, 0.04 + 0.13 * float(i)),
				0.0,
				back_z - unit * (0.3 + 0.3 * float(i % 3))
			)
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	var flower_scale := clampf(unit * 0.35, 0.25, 0.8)
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", flower_scale), reds))
	_backdrop.add_child(
		Models.swarm(Models.parts(DIR + "flower_yellowA.glb", flower_scale), yellows)
	)


func _apply_night(night: bool) -> void:
	stage.sun.light_energy = 0.4 if night else 0.78
	stage.fill.light_energy = 0.3 if night else 0.22
	stage.fill.light_color = Color(0.62, 0.7, 0.95) if night else Color(0.76, 0.85, 1.0)
	stage.environment.ambient_light_energy = 0.34 if night else 0.42
	_mat_lawn_a.albedo_color = LAWN_A_NIGHT if night else LAWN_A
	_mat_lawn_b.albedo_color = LAWN_B_NIGHT if night else LAWN_B


## ── Sync-Bausteine ───────────────────────────────────────────────────────


func _sync_towers(list: Array, tick: int) -> void:
	var seen := {}
	for entry: Dictionary in list:
		var key := str(entry["key"])
		seen[key] = true
		var record: Dictionary = _towers.get(key, {})
		if record.is_empty() or str(record["type"]) != str(entry["type"]):
			if not record.is_empty():
				(record["node"] as Node3D).queue_free()
			var node: Node3D = Props.tower(str(entry["type"]))
			add_child(node)
			record = {"type": str(entry["type"]), "node": node}
			_towers[key] = record
		var lane := int(entry["lane"])
		var root := record["node"] as Node3D
		root.position = cell_world(lane, int(entry["col"]))
		root.scale = Vector3.ONE * row_scale(lane)
		root.rotation.y = PI * 0.5 - 0.4 + sin(float(tick) * 0.08 + float(lane)) * 0.05
	for key: Variant in _towers.keys():
		if not seen.has(key):
			((_towers[key] as Dictionary)["node"] as Node3D).queue_free()
			_towers.erase(key)


func _sync_zombies(list: Array, tick: int) -> void:
	var seen := {}
	for entry: Dictionary in list:
		var id := int(entry["id"])
		seen[id] = true
		var record: Dictionary = _zombies.get(id, {})
		if record.is_empty():
			record = Props.zombie(str(entry["type"]))
			add_child(record["node"] as Node3D)
			_zombies[id] = record
		_pose_zombie(record, entry, tick)
	for id: Variant in _zombies.keys():
		if not seen.has(id):
			((_zombies[id] as Dictionary)["node"] as Node3D).queue_free()
			_zombies.erase(id)


func _pose_zombie(record: Dictionary, entry: Dictionary, tick: int) -> void:
	var root := record["node"] as Node3D
	root.visible = not bool(entry.get("hidden", false))
	if not root.visible:
		return
	var lane := int(entry["lane"])
	var s := row_scale(lane)
	var phase := float(int(entry["id"]) % 7)
	root.position = stage.ground_point(Vector2(entry["px"]))
	root.scale = Vector3.ONE * s * (1.5 if str(entry["type"]) == "brocken" else 1.0)
	root.rotation.y = -PI * 0.5 + 0.4
	var figure := record["figure"] as Node3D
	var mound := record.get("mound") as Node3D
	var dig := bool(entry.get("dig", false))
	figure.visible = not dig
	if mound != null:
		mound.visible = dig
	if dig:
		return
	# Schlurf-Wackeln; Hüpfer hüpfen, Sprinter lehnen sich in den Lauf.
	figure.rotation.z = sin(float(tick) * 0.22 + phase) * 0.06
	figure.position.y = 0.0
	if str(entry["type"]) == "huepfer":
		figure.position.y = absf(sin(float(tick) * 0.25 + phase)) * 0.24
	var lean := -0.1 if str(entry["type"]) != "sprinter" else -0.3
	figure.rotation.x = lean if not bool(entry.get("raged", false)) else -0.34
	var armor := record.get("armor") as Node3D
	if armor != null:
		armor.visible = bool(entry.get("armor", false))
	var balloon := record.get("balloon") as Node3D
	if balloon != null:
		var flying := bool(entry.get("flying", false))
		balloon.visible = flying
		figure.position.y = 0.62 + sin(float(tick) * 0.1 + phase) * 0.06 if flying else 0.0
	var slow := record.get("slow") as Node3D
	if slow != null:
		slow.visible = bool(entry.get("slow", false))


func _sync_boss(boss: Dictionary, tick: int) -> void:
	if _boss != null and boss.is_empty():
		_boss.visible = false
		return
	if boss.is_empty():
		return
	if _boss == null:
		var made: Dictionary = Props.boss()
		_boss = made["node"] as Node3D
		_boss_puffs = made["puffs"]
		add_child(_boss)
	_boss.visible = true
	var lane := int(boss.get("lane", 2))
	_boss.position = stage.ground_point(Vector2(boss["px"]))
	_boss.scale = Vector3.ONE * row_scale(lane) * 1.5
	_boss.rotation.y = -PI * 0.5 + 0.35
	_boss.rotation.z = sin(float(tick) * 0.15) * 0.02
	var phase := int(boss.get("phase", 1))
	for i in _boss_puffs.size():
		(_boss_puffs[i] as MeshInstance3D).visible = i < phase - 1


func _sync_projectiles(list: Array) -> void:
	while _proj_pool.size() < list.size():
		var node: Node3D = Props.projectile()
		add_child(node)
		_proj_pool.append(node)
	for i in _proj_pool.size():
		var node := _proj_pool[i]
		if i >= list.size():
			node.visible = false
			continue
		var entry: Dictionary = list[i]
		var lane := int(entry["lane"])
		var s := row_scale(lane)
		node.visible = true
		node.position = stage.ground_point(Vector2(entry["px"])) + Vector3(0.0, s * 0.55, 0.0)
		node.scale = Vector3.ONE * s
		var kinds: Dictionary = node.get_meta("kinds")
		for kind: Variant in kinds:
			(kinds[kind] as Node3D).visible = str(kind) == str(entry["kind"])


func _sync_drops(list: Array, tick: int) -> void:
	while _drop_pool.size() < list.size():
		var node: Node3D = Props.drop()
		add_child(node)
		_drop_pool.append(node)
	for i in _drop_pool.size():
		var node := _drop_pool[i]
		if i >= list.size():
			node.visible = false
			continue
		var entry: Dictionary = list[i]
		var lane := int(entry["lane"])
		var s := row_scale(lane)
		var bob := sin(float(tick) * 0.2 + float(int(entry["id"]))) * 0.05
		node.visible = true
		node.position = (
			stage.ground_point(Vector2(entry["px"])) + Vector3(0.0, s * (0.3 + bob), 0.0)
		)
		node.scale = Vector3.ONE * s


func _sync_mowers(list: Array, tick: int) -> void:
	for entry: Dictionary in list:
		var lane := int(entry["lane"])
		if not _mowers.has(lane):
			var node: Node3D = Props.mower()
			add_child(node)
			_mowers[lane] = node
		var root := _mowers[lane] as Node3D
		var used := bool(entry.get("used", false)) and not bool(entry.get("active", false))
		root.visible = not used
		if used:
			continue
		var s := row_scale(lane)
		root.position = stage.ground_point(Vector2(entry["px"]))
		root.scale = Vector3.ONE * s * 0.8
		root.rotation.y = PI * 0.5
		if bool(entry.get("active", false)):
			root.rotation.z = sin(float(tick) * 0.9) * 0.08


func _sync_ghost(ghost: Dictionary) -> void:
	_ghost.visible = not ghost.is_empty()
	if ghost.is_empty():
		return
	var lane := int(ghost["lane"])
	var col := int(ghost["col"])
	_ghost.position = cell_world(lane, col) + Vector3(0.0, 0.03, 0.0)
	_ghost.scale = Vector3(_row_w[lane], 1.0, _row_d[lane])
	(_ghost.mesh as PlaneMesh).material = (
		_mat_ghost_ok if bool(ghost.get("ok", false)) else _mat_ghost_bad
	)


## ── Nebelwand + Partikel ─────────────────────────────────────────────────


func _make_fog_wall() -> Node3D:
	var root := Node3D.new()
	_fog_box = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = Fx.glass(Color(0.88, 0.91, 0.96, 0.86), true)
	_fog_box.mesh = box
	_fog_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_fog_box)
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.material = Fx.glass(Color(0.92, 0.94, 0.98, 0.8), true)
	for _i in 5:
		var puff := MeshInstance3D.new()
		puff.mesh = puff_mesh
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(puff)
		_fog_puffs.append(puff)
	root.visible = false
	return root


func _build_fx() -> void:
	_place_burst = (
		Fx
		. particles(
			{
				"color": Color(0.62, 0.48, 0.32, 0.9),
				"amount": 12,
				"lifetime": 0.45,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.2),
				"spread": 70.0,
				"size": Vector2(0.05, 0.13),
			}
		)
	)
	add_child(_place_burst)
	_die_burst = (
		Fx
		. particles(
			{
				"color": Color(0.78, 0.89, 0.76, 0.95),
				"amount": 14,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.6),
				"spread": 80.0,
				"size": Vector2(0.06, 0.14),
			}
		)
	)
	add_child(_die_burst)
	_pop_burst = (
		Fx
		. particles(
			{
				"color": Color(0.95, 0.58, 0.53, 0.95),
				"amount": 12,
				"lifetime": 0.45,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.4, 2.8),
				"spread": 90.0,
				"size": Vector2(0.05, 0.12),
				"additive": true,
			}
		)
	)
	add_child(_pop_burst)
	_blast_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.72, 0.35, 0.95),
				"amount": 22,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(2.0, 4.2),
				"spread": 90.0,
				"size": Vector2(0.08, 0.2),
				"additive": true,
			}
		)
	)
	add_child(_blast_burst)
