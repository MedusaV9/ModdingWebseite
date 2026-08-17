extends Node3D
## ECHTER 3D-VORGARTEN für GvZ (FB-4): das Tower-Defense spielt auf einem
## Rasen-Schachbrett vor Gartenzaun, Bäumen und dem Haus mit Holzveranda.
## SÄMTLICHE Spielfiguren — Zombies, Türme, Panik-Mäher, Projektile und
## Nutella-Drops — laufen als MultiMesh-Instanzen über die Figuren-Menge
## (gvz_stage3d_crowd.gd, Eval C Befund 2: Draw-Call-Budget); nur der
## Boss-Müllwagen bleibt ein Einzelknoten (gvz_stage3d_props.gd). Gooby
## (echtes Rig) verteidigt auf der Veranda. ALLE Anker kommen als CANVAS-
## PIXEL aus der View und werden per ground_point-Raycast auf den Boden
## gelegt — Zellen und Tap-Ziele bleiben EXAKT unter dem Finger, die
## MECHANIK (GvzLogic) bleibt zahlengleich.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Props := preload("res://scripts/minigames/games/gvz/gvz_stage3d_props.gd")
const Crowd := preload("res://scripts/minigames/games/gvz/gvz_stage3d_crowd.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const LANES := 5
const COLS := 9

const LAWN_A := Color("#84B75B")
const LAWN_B := Color("#73A84D")
const LAWN_A_NIGHT := Color("#6E8F64")
const LAWN_B_NIGHT := Color("#5F8056")

## Häuser-Kulisse: das verteidigte Haus + 2 Nachbarn als EIN Schwarm
## (4 MultiMeshes statt 12 Einzel-Meshes; Fassade/Dach je Instanzfarbe).
## Einträge: [lerp-x, z-Abstand in unit, Skalierung, Fassade, Dach].
const HOUSE_SPECS := [
	[0.3, 1.35, 1.0, Color("#F2E3C8"), Color("#C96F5A")],
	[0.52, 1.5, 0.82, Color("#E3D7EA"), Color("#8B9BC9")],
	[0.84, 1.42, 0.9, Color("#D9E8DA"), Color("#C9A05A")],
]
const HOUSE_DOOR := Color("#7C5433")

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
## Haus-Teil-Id ("walls"|"roof"|"door"|"window") → MultiMesh (3 Instanzen).
var _houses: Dictionary = {}
var _backdrop: Node3D
var _fog_wall: Node3D
var _fog_box: MeshInstance3D
var _fog_puffs: Array[MeshInstance3D] = []
var _ghost: MeshInstance3D
var _mat_ghost_ok: StandardMaterial3D
var _mat_ghost_bad: StandardMaterial3D

var _crowd: Node3D
## Zombie-Id → letzter HP-Stand / Trefferblitz-Restzeit (Sekunden).
var _zombie_hp: Dictionary = {}
var _zombie_flash: Dictionary = {}
var _boss: Node3D
var _boss_puffs: Array = []

var _place_burst: GPUParticles3D
var _die_burst: GPUParticles3D
var _pop_burst: GPUParticles3D
var _blast_burst: GPUParticles3D
var _hit_burst: GPUParticles3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Vorgarten-Nachmittag, NICHT überbelichtet (Ziel-Luma ~210).
				"sky_top": Color(0.5, 0.74, 0.93),
				"sky_horizon": Color(0.87, 0.92, 0.86),
				"ground_horizon": Color(0.58, 0.75, 0.46),
				"ground_bottom": Color(0.4, 0.56, 0.33),
				"sun_dir": Vector3(-0.35, -0.8, -0.4),
				"sun_energy": 0.7,
				"ambient": 0.33,
				"fill_energy": 0.18,
				"glow": 0.26,
				"glow_threshold": 0.87,
				"shadow_distance": 34.0,
				"fog": true,
				"fog_color": Color(0.82, 0.9, 0.85),
				"fog_from": 22.0,
				"fog_to": 60.0,
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
	add_child(_make_house_swarm())
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
	_crowd = Crowd.new()
	add_child(_crowd)
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


## W14 Intro-Beat: Kamera schwebt aus leicht erhöhter Totale (k=0) sanft in die
## Spielpose (k=1). Zellen bleiben welt-verankert, Touch-Mapping unberührt.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = Vector3(0.0, 11.5 + 2.4 * e, 8.0 + 1.8 * e)
	stage.camera.rotation_degrees = Vector3(-52.0 - 4.5 * e, 0.0, 0.0)


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
## Alle Figuren laufen zwischen begin() und commit() in die MultiMesh-Menge.
func sync(data: Dictionary, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	if _cell_pos.is_empty():
		return
	var tick := int(data.get("tick", 0))
	gooby.rotation.z = sin(float(tick) * 0.06) * 0.03
	_crowd.call("begin")
	_sync_towers(data.get("towers", []), tick)
	_sync_zombies(data.get("zombies", []), tick, delta)
	_sync_boss(data.get("boss", {}), tick)
	_sync_projectiles(data.get("projectiles", []))
	_sync_drops(data.get("drops", []), tick)
	_sync_mowers(data.get("mowers", []), tick)
	_crowd.call("commit")
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


## Reduced-Motion-Gate (MG-Audit Q2): Partikel-Bursts sind reine Deko und
## bleiben bei reduzierter Bewegung aus — IMMER an der Call-Site gaten,
## nie im geteilten Fx-Kit. Spiel-Feedback (Emotes, Farben) bleibt.
func _rm() -> bool:
	return ThemeService.is_reduced_motion(self)


func place_fx(px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_place_burst, stage.ground_point(px) + Vector3(0.0, 0.3, 0.0))


func die_fx(px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_die_burst, stage.ground_point(px) + Vector3(0.0, 0.5, 0.0))


func pop_fx(px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_pop_burst, stage.ground_point(px) + Vector3(0.0, 1.0, 0.0))


func blast_fx(px: Vector2) -> void:
	if not _rm():
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


## Häuser-Schwarm (Eval C Befund 2): Wände, Dach, Tür, Fenster je EIN
## MultiMesh mit 3 Instanzen (verteidigtes Haus + 2 Nachbarn) — Fassaden-
## und Dachfarben kommen als Instanzfarben, statt 12 Meshes mit je eigenem
## Material. Kulisse wirft keine Schatten (reine Silhouetten).
func _make_house_swarm() -> Node3D:
	var root := Node3D.new()
	_houses.clear()
	var walls := BoxMesh.new()
	walls.size = Vector3(2.2, 1.7, 2.0)
	var roof := PrismMesh.new()
	roof.size = Vector3(2.6, 1.1, 2.4)
	var door := BoxMesh.new()
	door.size = Vector3(0.5, 0.95, 0.06)
	var window := BoxMesh.new()
	window.size = Vector3(0.55, 0.5, 0.06)
	for spec: Array in [["walls", walls], ["roof", roof], ["door", door], ["window", window]]:
		var mesh := spec[1] as PrimitiveMesh
		var mat := (
			Fx.glow(Color(1.0, 0.93, 0.7), 0.5)
			if str(spec[0]) == "window"
			else Fx.flat(Color.WHITE)
		)
		mat.vertex_color_use_as_albedo = true
		mesh.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = HOUSE_SPECS.size()
		mm.visible_instance_count = 0
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 16.0
		root.add_child(node)
		_houses[spec[0]] = mm
	return root


## Alle 3 Häuser an der Kulissen-Linie ausrichten (Instanz-Transforms).
func _layout_houses(lo_x: float, hi_x: float, back_z: float, unit: float) -> void:
	var house_scale := clampf(unit * 0.4, 0.35, 0.72)
	var offsets := {
		"walls": Vector3(0.0, 0.85, 0.0),
		"roof": Vector3(0.0, 2.25, 0.0),
		"door": Vector3(0.3, 0.48, 1.01),
		"window": Vector3(-0.55, 1.05, 1.01),
	}
	for i in HOUSE_SPECS.size():
		var spec: Array = HOUSE_SPECS[i]
		var base := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * house_scale * float(spec[2])),
			Vector3(lerpf(lo_x, hi_x, float(spec[0])), 0.0, back_z - unit * float(spec[1]))
		)
		for id: String in offsets:
			var mm := _houses[id] as MultiMesh
			mm.set_instance_transform(i, base * Transform3D(Basis.IDENTITY, offsets[id]))
			var tint := Color.WHITE
			match id:
				"walls":
					tint = spec[3]
				"roof":
					tint = spec[4]
				"door":
					tint = HOUSE_DOOR
			mm.set_instance_color(i, tint)
	for id: String in _houses:
		(_houses[id] as MultiMesh).visible_instance_count = HOUSE_SPECS.size()


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


## Kulisse hinter der letzten Reihe: Zaun, Gehweg, das VERTEIDIGTE Haus
## (links, mit Nachbarhäusern), Bäume, Hecke und Blumen. Das Horizont-Band
## der View (_field_rect senkt die Feld-Oberkante um ~10 % Bildhöhe) gibt
## der Nachbarschaft echten Platz — vorher wurde alles Hohe hinter dem Zaun
## vom Bildrand abgeschnitten.
func _layout_backdrop() -> void:
	for child in _backdrop.get_children():
		child.queue_free()
	var back_z: float = (cell_world(0, 0) as Vector3).z - _row_d[0] * 0.7
	var lo_x: float = (cell_world(0, 0) as Vector3).x - _row_w[0] * 0.6
	var hi_x: float = (cell_world(0, COLS - 1) as Vector3).x + _row_w[0] * 0.6
	var unit := _row_s[0]
	# Gehweg-Band zwischen Zaun und Häusern (die Straße der Nachbarschaft).
	var walk := MeshInstance3D.new()
	var walk_mesh := BoxMesh.new()
	walk_mesh.size = Vector3(hi_x - lo_x + unit * 4.0, 0.05, unit * 1.1)
	walk_mesh.material = Fx.flat(Color("#CFC7B6"))
	walk.mesh = walk_mesh
	walk.position = Vector3((lo_x + hi_x) * 0.5, 0.02, back_z - unit * 0.95)
	_backdrop.add_child(walk)
	# DAS Haus (die verteidigte Basis) links hinter dem Gehweg + zwei Nachbarn
	# als MultiMesh-Schwarm (HOUSE_SPECS). Maß-Regel: das Horizont-Band ist
	# ~10 % Bildhöhe — Häuser müssen KLEIN und DICHT hinter dem Gehweg stehen,
	# sonst ragt nur die Wand ins Bild und das Dach verschwindet über dem
	# Bildrand (erster Wurf). lerp 0.3: weit genug rechts, dass die Karten-
	# Leiste (oben links) das verteidigte Haus in Landscape nicht verdeckt.
	_layout_houses(lo_x, hi_x, back_z, unit)
	# Hecke als Horizont-Abschluss: schließt die Rasenfläche hinter den
	# Häusern ab, damit am oberen Bildrand keine leere Wiese ausfranst.
	var hedge := MeshInstance3D.new()
	var hedge_mesh := BoxMesh.new()
	hedge_mesh.size = Vector3(hi_x - lo_x + unit * 10.0, unit * 0.9, unit * 0.8)
	hedge_mesh.material = Fx.flat(Color("#5B8A49"))
	hedge.mesh = hedge_mesh
	hedge.position = Vector3((lo_x + hi_x) * 0.5, unit * 0.45, back_z - unit * 2.6)
	_backdrop.add_child(hedge)
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
	for i in 4:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.4),
				Vector3(
					lerpf(lo_x, hi_x, 0.02 + 0.31 * float(i)),
					0.0,
					back_z - unit * (1.9 + 0.35 * float(i % 2))
				)
			)
		)
	var tree_scale := clampf(unit * 0.8, 0.7, 1.5)
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
	var flower_scale := clampf(unit * 0.24, 0.2, 0.45)
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", flower_scale), reds))
	_backdrop.add_child(
		Models.swarm(Models.parts(DIR + "flower_yellowA.glb", flower_scale), yellows)
	)
	_no_backdrop_shadow(_backdrop)


## Kulissen-Schatten sparen: die ganze Nachbarschaft sind reine Silhouetten —
## Schattenwurf hätte pro Mesh einen zweiten Draw-Call gekostet.
func _no_backdrop_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_backdrop_shadow(child)


func _apply_night(night: bool) -> void:
	stage.sun.light_energy = 0.38 if night else 0.7
	stage.fill.light_energy = 0.28 if night else 0.18
	stage.fill.light_color = Color(0.62, 0.7, 0.95) if night else Color(0.76, 0.85, 1.0)
	stage.environment.ambient_light_energy = 0.28 if night else 0.33
	_mat_lawn_a.albedo_color = LAWN_A_NIGHT if night else LAWN_A
	_mat_lawn_b.albedo_color = LAWN_B_NIGHT if night else LAWN_B


## ── Sync-Bausteine ───────────────────────────────────────────────────────


## Türme als MultiMesh-Instanzen (Eval C Befund 2): kein Knoten-Lifecycle
## mehr — pro Frame nur Transform + Instanzfarbe in die Figuren-Menge.
func _sync_towers(list: Array, tick: int) -> void:
	for entry: Dictionary in list:
		var lane := int(entry["lane"])
		var yaw := PI * 0.5 - 0.4 + sin(float(tick) * 0.08 + float(lane)) * 0.05
		var base := Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * row_scale(lane)),
			cell_world(lane, int(entry["col"]))
		)
		_crowd.call("add_tower", str(entry["type"]), base)


## Die ganze Horde läuft über die MultiMesh-Menge (gvz_stage3d_crowd.gd):
## pro Zombie NUR Transform + Instanzfarbe. HP-Abfälle lösen den weißen
## Trefferblitz + Aufplatz-Funken aus — die Rückmeldung, dass Türme wirken.
func _sync_zombies(list: Array, tick: int, delta: float) -> void:
	var seen := {}
	for entry: Dictionary in list:
		var id := int(entry["id"])
		seen[id] = true
		var hp := int(entry.get("hp", 0))
		var flash := maxf(0.0, float(_zombie_flash.get(id, 0.0)) - delta)
		if _zombie_hp.has(id) and hp < int(_zombie_hp[id]) and not bool(entry.get("dig", false)):
			# Weißer Trefferblitz (Instanzfarbe) bleibt auch bei Reduced
			# Motion — nur die Funken-Partikel sind gegated (Q2).
			if flash <= 0.05 and not _rm():
				Fx.burst(
					_hit_burst,
					(
						stage.ground_point(Vector2(entry["px"]))
						+ Vector3(0.0, row_scale(int(entry["lane"])) * 0.55, 0.0)
					)
				)
			flash = 0.24
		_zombie_hp[id] = hp
		_zombie_flash[id] = flash
		if bool(entry.get("hidden", false)):
			continue
		var lane := int(entry["lane"])
		var s := row_scale(lane) * (1.5 if str(entry["type"]) == "brocken" else 1.0)
		var phase := float(id % 7)
		var base := Transform3D(
			Basis(Vector3.UP, -PI * 0.5 + 0.4).scaled(Vector3.ONE * s),
			stage.ground_point(Vector2(entry["px"]))
		)
		var fig_y := 0.0
		if str(entry["type"]) == "huepfer":
			fig_y = absf(sin(float(tick) * 0.25 + phase)) * 0.24
		if bool(entry.get("flying", false)):
			fig_y = 0.62 + sin(float(tick) * 0.1 + phase) * 0.06
		var lean := -0.1 if str(entry["type"]) != "sprinter" else -0.3
		if bool(entry.get("raged", false)):
			lean = -0.34
		(
			_crowd
			. call(
				"add_zombie",
				str(entry["type"]),
				base,
				{
					"dig": entry.get("dig", false),
					"flying": entry.get("flying", false),
					"armor": entry.get("armor", false),
					"slow": entry.get("slow", false),
					"raged": entry.get("raged", false),
					"fig_y": fig_y,
					"wobble": sin(float(tick) * 0.22 + phase) * 0.06,
					"lean": lean + flash * 0.6,
					"flash": flash / 0.24,
				}
			)
		)
	for id: Variant in _zombie_hp.keys():
		if not seen.has(id):
			_zombie_hp.erase(id)
			_zombie_flash.erase(id)


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
	for entry: Dictionary in list:
		var s := row_scale(int(entry["lane"]))
		var base := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * s),
			stage.ground_point(Vector2(entry["px"])) + Vector3(0.0, s * 0.55, 0.0)
		)
		_crowd.call("add_projectile", str(entry["kind"]), base)


func _sync_drops(list: Array, tick: int) -> void:
	for entry: Dictionary in list:
		var s := row_scale(int(entry["lane"]))
		var bob := sin(float(tick) * 0.2 + float(int(entry["id"]))) * 0.05
		var base := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * s),
			stage.ground_point(Vector2(entry["px"])) + Vector3(0.0, s * (0.3 + bob), 0.0)
		)
		_crowd.call("add_drop", base)


func _sync_mowers(list: Array, tick: int) -> void:
	for entry: Dictionary in list:
		if bool(entry.get("used", false)) and not bool(entry.get("active", false)):
			continue
		var s := row_scale(int(entry["lane"])) * 0.8
		# Wie vorher: rotation.y = 90°, aktives Rollbrett wackelt um z (YXZ).
		var basis := Basis(Vector3.UP, PI * 0.5)
		if bool(entry.get("active", false)):
			basis = basis * Basis(Vector3.BACK, sin(float(tick) * 0.9) * 0.08)
		var base := Transform3D(
			basis.scaled(Vector3.ONE * s), stage.ground_point(Vector2(entry["px"]))
		)
		_crowd.call("add_mower", base)


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
	puff_mesh.radial_segments = 16
	puff_mesh.rings = 8
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
	_hit_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.97, 0.85, 0.95),
				"amount": 7,
				"lifetime": 0.28,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.4),
				"spread": 80.0,
				"size": Vector2(0.04, 0.09),
				"additive": true,
			}
		)
	)
	add_child(_hit_burst)
