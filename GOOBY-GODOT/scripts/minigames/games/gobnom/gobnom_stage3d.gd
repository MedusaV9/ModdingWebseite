extends Node3D
## ECHTE 3D-KÜCHEN-BÜHNE für GOB NOM (FB-4, Kulisse MP-G): das Physik-Puzzle
## spielt auf einer senkrechten Ebene (z = 0) vor Goobys Küchenwand — Fliesen-
## Spiegel, Regalbretter voller Gläser, Fenster mit Blick ins Grüne — Bonbon,
## Seile (mit Faser-Drall), Blasen, Kissen, Ventilatoren, Stachelbretter,
## NUTELLA-Gläser (verlockend baumelnd) und Schießer sind echte Meshes, Gooby
## (echtes Rig) wartet mit offenem Mund als Fänger und fiebert mit, wenn das
## Bonbon nah kommt. ALLE Anker kommen als CANVAS-PIXEL aus der View
## (_to_screen-Ausgabe) und werden per wall_point-Raycast auf die Ebene
## gelegt — Schnitt-Linien und Tap-Zonen bleiben EXAKT unter dem Finger, die
## MECHANIK (GobnomLogic) bleibt zahlengleich.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Backdrop := preload("res://scripts/minigames/games/gobnom/gobnom_backdrop.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const ROPE_SEG_N := 12
const MAX_ROPE_SEGS := 96
const MAX_SWIPE_DOTS := 64
const MAX_ARC_DOTS := 22
const OUTLINE := Color("#4A3B36")
const CANDY_PINK := Color("#F2A0B5")
const CANDY_WRAP := Color("#FFE9F0")
const ROPE_BROWN := Color("#A9744B")
const ROPE_DARK := Color("#8A5A38")
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const RAIL_GRAY := Color("#C9BCA9")
const CUSHION_TEAL := Color("#9FD8CF")
const FAN_METAL := Color("#9DA6AD")
const SPIKE_GRAY := Color("#8C8C94")
const NUTELLA := Color("#5C3A21")
const NUTELLA_LID := Color("#E8E2D8")
const STAR_GOLD := Color("#FFD34D")
const KITCHEN_WALL := Color("#EBD8B4")
const COUNTER_WOOD := Color("#D2AC7C")

## Spielpose der Kamera (frame()); auch End-Pose der Intro-Fahrt.
const CAM_POS := Vector3(0.0, 0.0, 11.5)
## Intro-Beat (G5 P36, mg-audit-b §2 P2): Start-Versatz der Fahrt — bei k=0
## steht die Kamera links vorm Vorrats-Regal der Küchenwand (Establish),
## bei k=1 EXAKT wieder auf CAM_POS (kein Ruck beim Übergang ins Spiel).
const INTRO_POS_OFF := Vector3(-2.6, 1.2, -6.0)
const INTRO_PITCH_DEG := 2.0
const INTRO_YAW_DEG := 16.0

var stage: Node3D
var gooby: Node3D
## Welt(960×540) → Canvas-Pixel; die View hängt hier ihr _to_screen ein.
var to_px: Callable

## 3D-Einheiten pro Welt-Pixel (aus dem Layout gemessen).
var _upx := 0.01
var _ground_y := 0.0
var _candy: Node3D
var _mouth_ring: MeshInstance3D
var _mouth_ring_scale := 1.0
var _mouth_pos := Vector3.ZERO
var _hungry := false
var _rope_segs: MultiMeshInstance3D
var _swipe_dots: MultiMeshInstance3D
## Schwung-Bogen: die letzten Bonbon-Positionen als verblassende Spur.
var _arc_dots: MultiMeshInstance3D
var _arc_trail: Array[Vector3] = []
var _level_root: Node3D
var _anchors: Array[Node3D] = []
var _bubbles: Array[Node3D] = []
var _fans: Array[Node3D] = []
var _jars: Array[Node3D] = []
var _shooters: Array[Node3D] = []
var _cushions: Array[Node3D] = []
var _ground: MeshInstance3D
var _backdrop: Node3D
var _mood := "open"
## Fahrt-Fortschritt der Intro-Kamera (1.0 = keine Fahrt, Spielpose).
var _intro_k := 1.0
var _mat_cushion_ready: StandardMaterial3D
var _mat_cushion_wait: StandardMaterial3D
var _mat_shooter: StandardMaterial3D
var _mat_shooter_fired: StandardMaterial3D
var _cut_burst: GPUParticles3D
var _gold_burst: GPUParticles3D
var _pop_burst: GPUParticles3D
var _confetti_burst: GPUParticles3D
var _puff_burst: GPUParticles3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Warmes Küchen-Nachmittagslicht, NICHT überbelichtet (die
				# Creme-Wand kippt sonst unter Filmic ins Weiße). WICHTIG:
				# KEIN Tiefen-Nebel — die Wand steht ~19 m vor der Kamera,
				# jeder Nebel ab <20 m wäscht die ganze Küche milchig aus.
				"sky_top": Color(0.55, 0.74, 0.92),
				"sky_horizon": Color(0.93, 0.85, 0.84),
				"ground_horizon": Color(0.62, 0.78, 0.5),
				"ground_bottom": Color(0.44, 0.6, 0.36),
				"sun_dir": Vector3(-0.3, -0.75, -0.5),
				"sun_energy": 0.55,
				"ambient": 0.26,
				"fill_energy": 0.14,
				"glow": 0.3,
				"glow_threshold": 0.85,
				"shadow_distance": 30.0,
				"fog": false,
				"far": 100.0,
			}
		)
	)
	_mat_cushion_ready = Fx.flat(CUSHION_TEAL)
	_mat_cushion_wait = Fx.flat(RAIL_GRAY)
	_mat_shooter = Fx.flat(WOOD)
	_mat_shooter_fired = Fx.flat(WOOD_DARK)
	# Küchen-Arbeitsplatte statt Wiese: das Puzzle spielt IN Goobys Küche.
	_ground = Fx.ground(Vector2(70.0, 50.0), COUNTER_WOOD)
	add_child(_ground)
	_backdrop = Node3D.new()
	add_child(_backdrop)
	Backdrop.build(_backdrop)
	_level_root = Node3D.new()
	add_child(_level_root)
	_candy = _spawn_candy()
	add_child(_candy)
	_mouth_ring = Fx.ring(0.5, 0.07, Color(1.0, 0.72, 0.62))
	_mouth_ring.rotation.x = PI * 0.5
	add_child(_mouth_ring)
	_rope_segs = _make_rope_multimesh()
	add_child(_rope_segs)
	_swipe_dots = _make_swipe_multimesh()
	add_child(_swipe_dots)
	_arc_dots = _make_arc_multimesh()
	add_child(_arc_dots)
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.4)
	gooby.base_emotion = "happy"
	_build_fx()


## Kamera frontal auf die Spielebene; die wall_point-Anker halten alle
## Welt-Punkte deckungsgleich mit der 2D-Letterbox-Eingabe.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = CAM_POS
	stage.camera.rotation_degrees = Vector3.ZERO
	stage.set_half_height(4.4, 11.5)


## Intro-Fahrt Regal→Seil (G5 P36): k=0 rahmt das Vorrats-Regal, k=1 steht
## EXAKT auf der frame()-Pose — gleiche Ease-Kurve wie gvz/carrot_catch.
## Reduced Motion ruft direkt establish(1.0) (Fahrt übersprungen).
func establish(k: float) -> void:
	_intro_k = clampf(k, 0.0, 1.0)
	_apply_intro_pose()


func _apply_intro_pose() -> void:
	var e := 1.0 - ease(_intro_k, 0.4)
	stage.camera.position = CAM_POS + INTRO_POS_OFF * e
	stage.camera.rotation_degrees = Vector3(INTRO_PITCH_DEG * e, INTRO_YAW_DEG * e, 0.0)


## Statische Level-Elemente aufbauen. state/balance kommen 1:1 aus der View;
## alle Positionen laufen über to_px → wall_point (Ebene z = 0).
func layout_level(state: Dictionary, balance: Dictionary) -> void:
	for child in _level_root.get_children():
		child.queue_free()
	_anchors = []
	_bubbles = []
	_fans = []
	_jars = []
	_shooters = []
	_cushions = []
	_arc_trail = []
	_hungry = false
	var a := _wall(Vector2(0.0, 540.0))
	var b := _wall(Vector2(960.0, 540.0))
	_upx = maxf(0.001, a.distance_to(b) / 960.0)
	_ground_y = a.y
	_ground.position.y = _ground_y - 0.02
	_backdrop.position = Vector3(0.0, _ground_y, 0.0)
	for rope: Dictionary in state["ropes"]:
		if rope.get("rail") is Dictionary:
			var rail: Dictionary = rope["rail"]
			_level_root.add_child(_spawn_rail(_wall(rail["from"]), _wall(rail["to"])))
		var anchor := _spawn_anchor()
		_level_root.add_child(anchor)
		_anchors.append(anchor)
	for _bubble: Dictionary in state["bubbles"]:
		var bubble := _spawn_bubble()
		_level_root.add_child(bubble)
		_bubbles.append(bubble)
	for cushion: Dictionary in state["cushions"]:
		var node := _spawn_cushion(Vector2(cushion["dir"]))
		node.position = _wall(cushion["pos"])
		_level_root.add_child(node)
		_cushions.append(node)
	for fan: Dictionary in state["fans"]:
		var node := _spawn_fan(Vector2(fan["dir"]))
		node.position = _wall(fan["pos"])
		_level_root.add_child(node)
		_fans.append(node)
	for spike: Dictionary in state["spikes"]:
		_level_root.add_child(_spawn_spikes(spike))
	for cloud: Dictionary in state["clouds"]:
		_level_root.add_child(_spawn_cloud(cloud))
	for jar: Dictionary in state["jars"]:
		var node := _spawn_jar()
		node.position = _wall(jar["pos"])
		_level_root.add_child(node)
		_jars.append(node)
	for shooter: Dictionary in state["shooters"]:
		var node := _spawn_shooter(float(shooter["r"]) * _upx)
		node.position = _wall(shooter["pos"])
		_level_root.add_child(node)
		_shooters.append(node)
	if bool(state["coop"]):
		_level_root.add_child(_spawn_split(state["split"]))
	_layout_mouth(state)
	var physics: Dictionary = balance.get("physics", {})
	_candy.scale = Vector3.ONE * maxf(0.05, float(physics.get("candy_r", 14.0)) * _upx / 0.14)


## Gooby als Fänger: Gesicht auf Mundhöhe, Fangzone als Glüh-Ring.
func _layout_mouth(state: Dictionary) -> void:
	var mouth := _wall((state["mouth"] as Dictionary)["pos"])
	var h := 170.0 * _upx
	gooby.scale = Vector3.ONE * (h / 1.4)
	# Leicht HINTER der Ebene, damit Bonbon + Fangring vor dem Gesicht liegen.
	gooby.position = Vector3(mouth.x, mouth.y - h * 0.78, -0.25)
	_mouth_pos = mouth
	_mouth_ring.position = mouth + Vector3(0.0, 0.0, 0.18)
	_mouth_ring_scale = maxf(0.3, 40.0 * _upx / 0.5)
	_mouth_ring.scale = Vector3.ONE * _mouth_ring_scale


## Jeden Frame: Bonbon, Seile, Blasen, Rotoren, Gläser und Swipe-Spur stellen.
## candy = Welt-Pixel des Bonbons, swipe_pts = Welt-Pixel aller Swipe-Zeiger.
## Während der Intro-Fahrt raycasten alle _wall-Anker aus der NEUTRALEN
## End-Pose (hide_seek-W16-Muster) — sonst klebten Bonbon/Seile an den
## Screen-Pixeln der bewegten Kamera statt an der Welt; danach kommt die
## Fahrt-Pose fürs Rendern wieder drauf.
func sync_state(state: Dictionary, candy: Vector2, swipe_pts: Array, delta: float) -> void:
	var intro_fahrt := _intro_k < 1.0
	if intro_fahrt:
		stage.camera.position = CAM_POS
		stage.camera.rotation_degrees = Vector3.ZERO
	stage.tick(delta)
	gooby.tick(delta)
	var tick := int(state["tick"])
	var candy_at := _wall(candy)
	_candy.visible = str(state["outcome"]) != "won"
	_candy.position = candy_at
	_candy.rotation.z = -float(tick) * 0.06
	_sync_arc(candy_at, str(state["outcome"]) == "")
	_sync_mouth(candy_at, state)
	_sync_mood(state)
	_sync_ropes(state, candy_at)
	var i := 0
	for bubble: Dictionary in state["bubbles"]:
		var node := _bubbles[i]
		i += 1
		node.visible = not bool(bubble["popped"])
		if not node.visible:
			continue
		var at := candy_at if bool(bubble["holds"]) else _wall(bubble["pos"])
		node.position = at
		var pulse := 1.0 + sin(float(tick) * 0.16) * 0.04
		node.scale = Vector3.ONE * (float(bubble["r"]) * _upx * 2.0 * pulse)
	i = 0
	for fan: Dictionary in state["fans"]:
		var node := _fans[i]
		i += 1
		var on := bool(fan["on"])
		if on:
			(node.get_node("Rotor") as Node3D).rotation.z = -float(tick) * 0.45
		(node.get_node("Wind") as GPUParticles3D).emitting = on
	i = 0
	for jar: Dictionary in state["jars"]:
		var jar_node := _jars[i]
		jar_node.visible = not bool(jar["taken"])
		# Verlockendes Baumeln: jedes Glas pendelt sacht um seinen Deckel.
		jar_node.rotation.z = sin(float(tick) * 0.055 + float(i) * 1.7) * 0.14
		i += 1
	i = 0
	for shooter: Dictionary in state["shooters"]:
		var node := _shooters[i]
		i += 1
		var fired := bool(shooter["fired"])
		(node.get_node("Kiste") as MeshInstance3D).material_override = (
			_mat_shooter_fired if fired else _mat_shooter
		)
		(node.get_node("Ring") as Node3D).visible = not fired
	i = 0
	for cushion: Dictionary in state["cushions"]:
		var ready := int(cushion["charges"]) != 0 and tick >= int(cushion["ready_tick"])
		var pad := _cushions[i].get_node("Polster") as MeshInstance3D
		i += 1
		pad.material_override = _mat_cushion_ready if ready else _mat_cushion_wait
	_sync_swipes(swipe_pts)
	if intro_fahrt:
		_apply_intro_pose()


## Seile als EIN MultiMesh gestreckter Zylinder (gleiche Durchhang-Kurve
## wie GobnomArt.draw_rope — rein visuell). Gespannte Seile werden dünner
## und heller, lose hängen dicker durch; der Segment-Wechsel hell/dunkel
## zeichnet den Faser-Drall.
func _sync_ropes(state: Dictionary, candy_at: Vector3) -> void:
	var mm := _rope_segs.multimesh
	var used := 0
	var idx := 0
	for rope: Dictionary in state["ropes"]:
		var anchor_at := _wall(rope["anchor"])
		if idx < _anchors.size():
			_anchors[idx].position = anchor_at
			_anchors[idx].visible = not bool(rope["cut"])
		idx += 1
		if bool(rope["cut"]):
			continue
		var rest := float(rope["rest"]) * _upx
		var dist := anchor_at.distance_to(candy_at)
		var slack := clampf(1.0 - dist / maxf(rest, 0.01), 0.0, 1.0)
		var taut := 1.0 - slack
		var thickness := lerpf(0.06, 0.042, taut)
		var mid := (anchor_at + candy_at) * 0.5 + Vector3(0.0, -slack * rest * 0.35, 0.0)
		var prev := anchor_at
		for s in ROPE_SEG_N:
			if used >= MAX_ROPE_SEGS:
				break
			var t := float(s + 1) / float(ROPE_SEG_N)
			var p := anchor_at.lerp(mid, t).lerp(mid.lerp(candy_at, t), t)
			mm.set_instance_transform(used, _seg_transform(prev, p, thickness))
			var fiber := ROPE_BROWN if s % 2 == 0 else ROPE_DARK
			mm.set_instance_color(used, fiber.lightened(taut * 0.22))
			prev = p
			used += 1
	mm.visible_instance_count = used


## Swipe-Spuren als Punktkette VOR der Ebene (deckungsgleich mit dem Finger).
func _sync_swipes(swipe_pts: Array) -> void:
	var mm := _swipe_dots.multimesh
	var count := mini(swipe_pts.size(), MAX_SWIPE_DOTS)
	mm.visible_instance_count = count
	for i in count:
		var at := _wall(swipe_pts[i]) + Vector3(0.0, 0.0, 0.3)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))


## Bogen-Spur des Bonbons: neueste Position vorn, ältere verblassen golden.
func _sync_arc(candy_at: Vector3, flying: bool) -> void:
	if flying:
		if _arc_trail.is_empty() or _arc_trail[_arc_trail.size() - 1].distance_to(candy_at) > 0.06:
			_arc_trail.append(candy_at)
			if _arc_trail.size() > MAX_ARC_DOTS:
				_arc_trail.pop_front()
	elif not _arc_trail.is_empty():
		_arc_trail.pop_front()
	var mm := _arc_dots.multimesh
	mm.visible_instance_count = _arc_trail.size()
	for i in _arc_trail.size():
		var age := float(i + 1) / float(_arc_trail.size())
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * (0.5 + age)),
				_arc_trail[i] + Vector3(0.0, 0.0, -0.15)
			)
		)
		mm.set_instance_color(i, Color(1.0, 0.83, 0.42, 0.08 + 0.3 * age))


## Goobys Maul fiebert mit: kommt das Bonbon nah, weitet sich der Fangring
## und Gooby reißt erwartungsvoll die Augen auf.
func _sync_mouth(candy_at: Vector3, state: Dictionary) -> void:
	if str(state["outcome"]) != "":
		return
	var dist := candy_at.distance_to(_mouth_pos)
	var near := clampf(1.0 - dist / 4.0, 0.0, 1.0)
	var tick := int(state["tick"])
	var pulse := 1.0 + near * (0.16 + 0.08 * sin(float(tick) * 0.3))
	_mouth_ring.scale = Vector3.ONE * (_mouth_ring_scale * pulse)
	if near > 0.55 and not _hungry:
		_hungry = true
		gooby.emote("ecstatic", 0.7)
	elif near < 0.35 and _hungry:
		_hungry = false


func _sync_mood(state: Dictionary) -> void:
	var mood := "open"
	if str(state["outcome"]) == "won":
		mood = "nom"
	elif str(state["outcome"]) != "":
		mood = "sad"
	if mood == _mood:
		return
	_mood = mood
	match mood:
		"nom":
			gooby.emote("ecstatic", 2.2)
			gooby.play_for("celebrate", 1.4)
			stage.pulse_glow(0.9)
		"sad":
			gooby.emote("sad", 2.2)
		_:
			gooby.emote("happy", 0.8)


## Reduced-Motion-Gate (MG-Audit Q2): Partikel-Bursts sind reine Deko und
## bleiben bei reduzierter Bewegung aus — IMMER an der Call-Site gaten,
## nie im geteilten Fx-Kit. Gooby-Emotes/Glow bleiben als Feedback.
func _rm() -> bool:
	return ThemeService.is_reduced_motion(self)


func cut_fx(world_px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_cut_burst, _wall(world_px) + Vector3(0.0, 0.0, 0.2))


func jar_fx(world_px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_gold_burst, _wall(world_px) + Vector3(0.0, 0.0, 0.2))


func pop_fx(world_px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_pop_burst, _wall(world_px) + Vector3(0.0, 0.0, 0.2))


func confetti_fx(world_px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_confetti_burst, _wall(world_px) + Vector3(0.0, 0.0, 0.3))


func puff_fx(world_px: Vector2) -> void:
	if _rm():
		return
	Fx.burst(_puff_burst, _wall(world_px) + Vector3(0.0, 0.0, 0.2))


## Canvas-Pixel → Punkt auf der Spielebene (z = 0).
func _wall(world_pos: Variant) -> Vector3:
	var px: Vector2 = to_px.call(Vector2(world_pos))
	var at: Vector3 = stage.wall_point(px, 0.0)
	return at


## ── Aufbau-Helfer ─────────────────────────────────────────────────────────


func _build_fx() -> void:
	_cut_burst = _burst(Color(1.0, 0.85, 0.4, 0.95), 12, 0.4, true)
	_gold_burst = _burst(Color(1.0, 0.83, 0.3, 0.95), 16, 0.55, true)
	_pop_burst = _burst(Color(0.6, 0.8, 0.95, 0.95), 14, 0.45, false)
	_confetti_burst = _burst(Color(0.95, 0.65, 0.75, 0.95), 24, 1.0, true)
	_puff_burst = _burst(Color(0.62, 0.85, 0.8, 0.9), 10, 0.4, false)


func _burst(color: Color, amount: int, life: float, additive: bool) -> GPUParticles3D:
	var node := (
		Fx
		. particles(
			{
				"color": color,
				"amount": amount,
				"lifetime": life,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.6),
				"spread": 85.0,
				"size": Vector2(0.04, 0.1),
				"additive": additive,
			}
		)
	)
	add_child(node)
	return node


func _make_rope_multimesh() -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var seg := CylinderMesh.new()
	seg.top_radius = 1.0
	seg.bottom_radius = 1.0
	seg.height = 1.0
	seg.radial_segments = 6
	# Faser-Drall: Instanzfarben wechseln hell/dunkel pro Segment.
	var mat := Fx.flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	seg.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = seg
	mm.instance_count = MAX_ROPE_SEGS
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Schwung-Bogen: goldene Punktspur der letzten Bonbon-Positionen — macht
## den Pendel-Bogen der Seil-Physik SICHTBAR.
func _make_arc_multimesh() -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 8
	dot.rings = 4
	var mat := Fx.glow(Color.WHITE, 0.7)
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot
	mm.instance_count = MAX_ARC_DOTS
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _make_swipe_multimesh() -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.055
	dot.height = 0.11
	dot.material = Fx.glow(Color(0.98, 0.62, 0.71), 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = MAX_SWIPE_DOTS
	mm.visible_instance_count = 0
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Einheits-Zylinder (Höhe 1, Radius 1) zwischen zwei Punkte spannen.
func _seg_transform(a: Vector3, b: Vector3, thickness: float) -> Transform3D:
	var d := b - a
	var y := d
	if d.length_squared() < 0.000001:
		y = Vector3(0.0, 0.001, 0.0)
	var x := y.normalized().cross(Vector3.BACK)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized() * thickness
	var z := x.normalized().cross(y.normalized()) * thickness
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _spawn_candy() -> Node3D:
	# Basisgröße: Radius 0.14 — layout_level skaliert auf candy_r * _upx.
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.14
	ball_mesh.height = 0.28
	ball_mesh.material = Fx.flat(CANDY_PINK)
	ball.mesh = ball_mesh
	root.add_child(ball)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := TorusMesh.new()
	stripe_mesh.inner_radius = 0.1
	stripe_mesh.outer_radius = 0.145
	stripe_mesh.material = Fx.flat(CANDY_WRAP)
	stripe.mesh = stripe_mesh
	stripe.rotation.x = PI * 0.35
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stripe)
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.07
	tip_mesh.height = 0.12
	tip_mesh.radial_segments = 8
	tip_mesh.material = Fx.flat(CANDY_WRAP)
	for side: float in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		tip.mesh = tip_mesh
		tip.rotation.z = side * PI * 0.5
		tip.position = Vector3(side * 0.2, 0.0, 0.0)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tip)
	return root


func _spawn_anchor() -> Node3D:
	var root := Node3D.new()
	var pin := MeshInstance3D.new()
	var pin_mesh := CylinderMesh.new()
	pin_mesh.top_radius = 0.09
	pin_mesh.bottom_radius = 0.09
	pin_mesh.height = 0.06
	pin_mesh.material = Fx.flat(WOOD)
	pin.mesh = pin_mesh
	pin.rotation.x = PI * 0.5
	root.add_child(pin)
	var eye := MeshInstance3D.new()
	var eye_mesh := TorusMesh.new()
	eye_mesh.inner_radius = 0.025
	eye_mesh.outer_radius = 0.05
	eye_mesh.material = Fx.flat(OUTLINE)
	eye.mesh = eye_mesh
	eye.position.z = 0.03
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(eye)
	root.scale = Vector3.ONE * maxf(0.6, 11.0 * _upx / 0.09)
	return root


func _spawn_rail(from: Vector3, to: Vector3) -> Node3D:
	var root := Node3D.new()
	var bar := MeshInstance3D.new()
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = 1.0
	bar_mesh.bottom_radius = 1.0
	bar_mesh.height = 1.0
	bar_mesh.radial_segments = 8
	bar_mesh.material = Fx.flat(RAIL_GRAY)
	bar.mesh = bar_mesh
	bar.transform = _seg_transform(from, to, 0.035)
	root.add_child(bar)
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.06
	knob_mesh.height = 0.12
	knob_mesh.material = Fx.flat(OUTLINE)
	for at: Vector3 in [from, to]:
		var knob := MeshInstance3D.new()
		knob.mesh = knob_mesh
		knob.position = at
		knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(knob)
	return root


func _spawn_bubble() -> Node3D:
	# Einheits-Blase (Durchmesser 1) — sync skaliert auf r * _upx * 2.
	var root := Node3D.new()
	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.5
	ball_mesh.height = 1.0
	ball_mesh.material = Fx.glass(Color(0.62, 0.82, 0.95, 0.4))
	ball.mesh = ball_mesh
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var shine := MeshInstance3D.new()
	var shine_mesh := SphereMesh.new()
	shine_mesh.radius = 0.09
	shine_mesh.height = 0.18
	shine_mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 0.8)
	shine.mesh = shine_mesh
	shine.position = Vector3(-0.18, 0.2, 0.3)
	shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shine)
	return root


func _spawn_cushion(dir: Vector2) -> Node3D:
	var root := Node3D.new()
	var pad := MeshInstance3D.new()
	var pad_mesh := CapsuleMesh.new()
	pad_mesh.radius = 0.16
	pad_mesh.height = 0.52
	pad.mesh = pad_mesh
	pad.name = "Polster"
	pad.material_override = _mat_cushion_ready
	pad.rotation.z = PI * 0.5
	root.add_child(pad)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.22, 0.22, 0.14)
	base_mesh.material = Fx.flat(WOOD)
	base.mesh = base_mesh
	base.position.x = -0.3
	root.add_child(base)
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.08
	tip_mesh.height = 0.16
	tip_mesh.radial_segments = 8
	tip_mesh.material = Fx.flat(OUTLINE)
	tip.mesh = tip_mesh
	tip.rotation.z = -PI * 0.5
	tip.position.x = 0.42
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tip)
	root.rotation.z = -Vector2(dir).angle()
	root.scale = Vector3.ONE * maxf(0.5, 26.0 * _upx / 0.26)
	return root


func _spawn_fan(dir: Vector2) -> Node3D:
	var root := Node3D.new()
	var housing := MeshInstance3D.new()
	var housing_mesh := CylinderMesh.new()
	housing_mesh.top_radius = 0.2
	housing_mesh.bottom_radius = 0.2
	housing_mesh.height = 0.1
	housing_mesh.material = Fx.flat(FAN_METAL)
	housing.mesh = housing_mesh
	housing.rotation.x = PI * 0.5
	root.add_child(housing)
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position.z = 0.06
	root.add_child(rotor)
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.16, 0.06, 0.02)
	blade_mesh.material = Fx.flat(Color("#F9EDD6"))
	for i in 3:
		var blade := MeshInstance3D.new()
		blade.mesh = blade_mesh
		var a := TAU * float(i) / 3.0
		blade.position = Vector3(cos(a) * 0.11, sin(a) * 0.11, 0.0)
		blade.rotation.z = a
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotor.add_child(blade)
	# Windrichtung folgt der Fan-Drehung (root richtet +x auf `dir` aus).
	var wind := (
		Fx
		. particles(
			{
				"color": Color(0.72, 0.84, 0.92, 0.55),
				"amount": 12,
				"lifetime": 0.7,
				"speed": Vector2(1.4, 2.2),
				"spread": 10.0,
				"size": Vector2(0.03, 0.07),
				"direction": Vector3(1.0, 0.0, 0.0),
				"gravity": Vector3.ZERO,
			}
		)
	)
	wind.name = "Wind"
	wind.position.x = 0.26
	wind.emitting = false
	root.add_child(wind)
	root.rotation.z = -Vector2(dir).angle()
	root.scale = Vector3.ONE * maxf(0.5, 22.0 * _upx / 0.2)
	return root


func _spawn_spikes(spike: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tl := _wall(Vector2(float(spike["x"]), float(spike["y"])))
	var br := _wall(
		Vector2(float(spike["x"]) + float(spike["w"]), float(spike["y"]) + float(spike["h"]))
	)
	var size := Vector3(absf(br.x - tl.x), absf(tl.y - br.y), 0.16)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = size
	board_mesh.material = Fx.flat(WOOD_DARK)
	board.mesh = board_mesh
	board.position = (tl + br) * 0.5
	root.add_child(board)
	var horizontal := size.x >= size.y
	var count := int(maxf(2.0, (size.x if horizontal else size.y) / (20.0 * _upx)))
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 8.0 * _upx
	spike_mesh.height = 14.0 * _upx
	spike_mesh.radial_segments = 8
	spike_mesh.material = Fx.flat(SPIKE_GRAY)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = spike_mesh
	mm.instance_count = count
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var at: Vector3
		var basis := Basis.IDENTITY
		if horizontal:
			at = Vector3(
				lerpf(tl.x, br.x, t), maxf(tl.y, br.y) + spike_mesh.height * 0.5, board.position.z
			)
		else:
			at = Vector3(
				minf(tl.x, br.x) - spike_mesh.height * 0.5, lerpf(tl.y, br.y, t), board.position.z
			)
			basis = Basis(Vector3.BACK, PI * 0.5)
		mm.set_instance_transform(i, Transform3D(basis, at))
	var spikes := MultiMeshInstance3D.new()
	spikes.multimesh = mm
	root.add_child(spikes)
	return root


func _spawn_cloud(cloud: Dictionary) -> Node3D:
	var root := Node3D.new()
	var tl := _wall(Vector2(float(cloud["x"]), float(cloud["y"])))
	var br := _wall(
		Vector2(float(cloud["x"]) + float(cloud["w"]), float(cloud["y"]) + float(cloud["h"]))
	)
	var center := (tl + br) * 0.5 + Vector3(0.0, 0.0, -0.7)
	var w := absf(br.x - tl.x)
	var h := absf(tl.y - br.y)
	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = 1.0
	blob_mesh.height = 2.0
	blob_mesh.material = Fx.flat(Color(0.97, 0.8, 0.88))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blob_mesh
	mm.instance_count = 5
	for i in 5:
		var t := float(i) / 4.0 - 0.5
		var at := center + Vector3(t * w * 0.72, sin(t * 4.0) * h * 0.16, 0.0)
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY.scaled(Vector3(w * 0.24, h * 0.38, h * 0.3)), at)
		)
	var blobs := MultiMeshInstance3D.new()
	blobs.multimesh = mm
	blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blobs)
	return root


func _spawn_jar() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.16
	body_mesh.bottom_radius = 0.14
	body_mesh.height = 0.3
	body_mesh.material = Fx.flat(NUTELLA)
	body.mesh = body_mesh
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.18
	lid_mesh.bottom_radius = 0.18
	lid_mesh.height = 0.08
	lid_mesh.material = Fx.flat(NUTELLA_LID)
	lid.mesh = lid_mesh
	lid.position.y = 0.19
	root.add_child(lid)
	var label := MeshInstance3D.new()
	var label_mesh := BoxMesh.new()
	label_mesh.size = Vector3(0.22, 0.14, 0.02)
	label_mesh.material = Fx.flat(Color(1.0, 1.0, 1.0, 0.95))
	label.mesh = label_mesh
	label.position = Vector3(0.0, -0.02, 0.15)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(label)
	var star := MeshInstance3D.new()
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.06
	star_mesh.height = 0.12
	star_mesh.material = Fx.glow(STAR_GOLD, 1.5)
	star.mesh = star_mesh
	star.position = Vector3(0.19, 0.26, 0.08)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(star)
	var shine := MeshInstance3D.new()
	var shine_mesh := SphereMesh.new()
	shine_mesh.radius = 0.035
	shine_mesh.height = 0.07
	shine_mesh.material = Fx.glow(Color(1.0, 0.98, 0.9), 1.1)
	shine.mesh = shine_mesh
	shine.position = Vector3(-0.09, 0.05, 0.14)
	shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shine)
	root.scale = Vector3.ONE * maxf(0.5, 22.0 * _upx / 0.16)
	return root


func _spawn_shooter(radius_units: float) -> Node3D:
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(32.0 * _upx, 26.0 * _upx, 0.16)
	box.mesh = box_mesh
	box.name = "Kiste"
	box.material_override = _mat_shooter
	root.add_child(box)
	var eye := MeshInstance3D.new()
	var eye_mesh := TorusMesh.new()
	eye_mesh.inner_radius = 3.0 * _upx
	eye_mesh.outer_radius = 6.5 * _upx
	eye_mesh.material = Fx.flat(OUTLINE)
	eye.mesh = eye_mesh
	eye.position.z = 0.09
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(eye)
	var ring := Fx.ring(radius_units, 0.02, Color(0.66, 0.55, 0.42, 0.6))
	ring.name = "Ring"
	ring.rotation.x = PI * 0.5
	root.add_child(ring)
	return root


## Coop-Hälften: getönte Glasscheiben + Grenzbalken + A/B-Beschriftung.
func _spawn_split(split: Dictionary) -> Node3D:
	var root := Node3D.new()
	var at := float(split.get("at", 480.0))
	var vertical := str(split.get("axis", "x")) == "x"
	var tl := _wall(Vector2(0.0, 0.0))
	var br := _wall(Vector2(960.0, 540.0))
	var rects: Array = []
	if vertical:
		rects = [
			[Vector2(0.0, 0.0), Vector2(at, 540.0), Color(0.96, 0.63, 0.6, 0.07), "A"],
			[Vector2(at, 0.0), Vector2(960.0, 540.0), Color(0.55, 0.78, 0.52, 0.07), "B"],
		]
	else:
		rects = [
			[Vector2(0.0, 0.0), Vector2(960.0, at), Color(0.96, 0.63, 0.6, 0.07), "A"],
			[Vector2(0.0, at), Vector2(960.0, 540.0), Color(0.55, 0.78, 0.52, 0.07), "B"],
		]
	for entry: Array in rects:
		var a := _wall(Vector2(entry[0]))
		var b := _wall(Vector2(entry[1]))
		var pane := MeshInstance3D.new()
		var pane_mesh := BoxMesh.new()
		pane_mesh.size = Vector3(absf(b.x - a.x), absf(a.y - b.y), 0.01)
		pane_mesh.material = Fx.glass(entry[2], true)
		pane.mesh = pane_mesh
		pane.position = (a + b) * 0.5 + Vector3(0.0, 0.0, 0.2)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pane)
		var tag := Label3D.new()
		tag.text = str(entry[3])
		tag.font_size = 220
		tag.pixel_size = _upx * 0.4
		tag.modulate = Color(entry[2], 0.4)
		tag.position = (a + b) * 0.5 + Vector3(0.0, 0.0, 0.25)
		root.add_child(tag)
	var border_a := _wall(Vector2(at, 0.0) if vertical else Vector2(0.0, at))
	var border_b := _wall(Vector2(at, 540.0) if vertical else Vector2(960.0, at))
	var steps := 14
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := t0 + 0.5 / float(steps)
		var dash := MeshInstance3D.new()
		var dash_mesh := BoxMesh.new()
		var p0 := border_a.lerp(border_b, t0)
		var p1 := border_a.lerp(border_b, t1)
		dash_mesh.size = Vector3(maxf(0.02, absf(p1.x - p0.x)), maxf(0.02, absf(p1.y - p0.y)), 0.02)
		dash_mesh.material = Fx.flat(Color(0.29, 0.23, 0.21, 0.5))
		dash.mesh = dash_mesh
		dash.position = (p0 + p1) * 0.5 + Vector3(0.0, 0.0, 0.22)
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dash)
	_no_shadow(root)
	return root


func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)
