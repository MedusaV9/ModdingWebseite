extends Node3D
## ECHTER 3D-PICKNICKTISCH für Memory (FB-4): Karten liegen als 3D-Plättchen
## auf einer Picknickdecke im Grünen, die Motive sind ECHTE Food-Modelle
## (Kenney-Food-Kit) und ploppen beim Umdrehen auf. Gooby (echtes Rig) sitzt
## hinter der Decke und schaut zu. Die Karten werden per ground_point-Raycast
## EXAKT unter die 2D-Tap-Rechtecke gelegt — Eingabe bleibt zahlengleich, die
## MECHANIK komplett in memory_match.gd/MemoryMatchLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CARD_RATIO := 1.0 / 0.82
const FLIP_SPEED := 9.0

## Kartenmotiv-Key → GLB im Food-Ordner (Reihenfolge = FACE_KEYS der Logic).
const FACE_MODELS := {
	"carrot": "carrot.glb",
	"apple": "apple.glb",
	"banana": "banana.glb",
	"cheese": "cheese.glb",
	"watermelon": "watermelon.glb",
	"donut-sprinkles": "donut-sprinkles.glb",
	"cupcake": "cupcake.glb",
	"burger": "burger.glb",
	"ice-cream": "ice-cream.glb",
	"pizza": "pizza.glb",
	"cake": "cake.glb",
	"strawberry": "strawberry.glb",
}

var stage: Node3D
var gooby: Node3D

var _cards: Array[Node3D] = []
var _card_pos: Array[Vector3] = []
var _card_w: Array[float] = []
var _flip: Array[float] = []
var _faces: Array[int] = []
var _blanket: Node3D
var _basket: Node3D
var _snacks: Node3D
var _star_burst: GPUParticles3D
var _poof_burst: GPUParticles3D

var _mat_face: StandardMaterial3D
var _mat_matched: StandardMaterial3D
var _mat_back: StandardMaterial3D
var _mat_emblem: StandardMaterial3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Sanfter Picknick-Nachmittag, NICHT überbelichtet: Ambient
				# kommt aus dem Himmel, also sky_energy UND ambient drosseln.
				"sky_top": Color(0.48, 0.7, 0.88),
				"sky_horizon": Color(0.8, 0.86, 0.8),
				"ground_horizon": Color(0.56, 0.7, 0.46),
				"ground_bottom": Color(0.4, 0.54, 0.34),
				"sky_energy": 0.78,
				"sun_dir": Vector3(-0.3, -0.85, -0.35),
				"sun_energy": 0.52,
				"ambient": 0.36,
				"fill_energy": 0.16,
				"glow": 0.24,
				"glow_threshold": 0.86,
				"shadow_distance": 30.0,
				"fog": true,
				"fog_color": Color(0.82, 0.88, 0.82),
				"fog_from": 26.0,
				"fog_to": 70.0,
				"far": 110.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(80.0, 60.0), Color(0.46, 0.64, 0.35)))
	_mat_face = Fx.flat(Color(0.98, 0.94, 0.84))
	_mat_matched = Fx.flat(Color(0.62, 0.84, 0.56))
	_mat_back = Fx.flat(Color(0.92, 0.46, 0.6))
	_mat_emblem = Fx.flat(Color(0.68, 0.26, 0.4))
	_build_backdrop()
	_build_gooby()
	_build_fx()


func _build_backdrop() -> void:
	# Karierte Picknickdecke: heller Grund + MultiMesh-Karostreifen.
	_blanket = Node3D.new()
	add_child(_blanket)
	var cloth := MeshInstance3D.new()
	var cloth_mesh := BoxMesh.new()
	cloth_mesh.size = Vector3(1.0, 0.05, 1.0)
	cloth_mesh.material = Fx.flat(Color(0.95, 0.86, 0.72))
	cloth.mesh = cloth_mesh
	cloth.position.y = 0.025
	_blanket.add_child(cloth)
	# Dezente Karolinien statt Riesen-Schachbrett (Streifen skalieren mit).
	var stripes := MultiMeshInstance3D.new()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.0, 0.052, 0.024)
	stripe.material = Fx.flat(Color(0.88, 0.56, 0.56))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stripe
	mm.instance_count = 16
	for i in 8:
		var offset := -0.42 + float(i) * 0.12
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.026, offset)))
		mm.set_instance_transform(
			i + 8, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(offset, 0.027, 0.0))
		)
	stripes.multimesh = mm
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blanket.add_child(stripes)
	# Kulisse: Baumreihe, Zaun und Blumen hinterm Tisch.
	var fence_poses: Array = []
	for i in 14:
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-11.7 + float(i) * 1.8, 0.0, -17.0)))
	add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.8), fence_poses))
	var tree_poses: Array = []
	for i in 5:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.1),
				Vector3(-12.0 + float(i) * 6.0, 0.0, -20.0 - 2.0 * float(i % 2))
			)
		)
	# Zwei nähere Bäume rahmen das Feld — Mittelgrund statt leerer Wiese.
	tree_poses.append(Transform3D(Basis(Vector3.UP, 0.7), Vector3(-9.6, 0.0, -13.0)))
	tree_poses.append(Transform3D(Basis(Vector3.UP, 2.3), Vector3(9.8, 0.0, -14.2)))
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 4.2), tree_poses))
	var reds: Array = []
	var yellows: Array = []
	for i in 10:
		var pose := Transform3D(
			Basis.IDENTITY, Vector3(-8.0 + float(i) * 1.8, 0.0, -13.6 if i % 2 == 0 else -14.9)
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.5), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.5), yellows))
	_basket = Models.node(DIR + "picnic_basket_round.gltf", 1.5)
	add_child(_basket)
	# Snack-Ecke als Vordergrund-Requisite (Position setzt layout()).
	_snacks = Node3D.new()
	add_child(_snacks)
	for entry: Array in [
		["apple.glb", 0.55, Vector3(0.0, 0.0, 0.0)],
		["strawberry.glb", 0.5, Vector3(0.75, 0.0, 0.45)],
		["cupcake.glb", 0.55, Vector3(-0.5, 0.0, 0.7)],
	]:
		var snack := Models.node(DIR + str(entry[0]), float(entry[1]))
		snack.position = entry[2]
		_snacks.add_child(snack)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.15)
	gooby.base_emotion = "happy"
	gooby.add_child(Fx.blob_shadow(0.55))


func _build_fx() -> void:
	_star_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.5, 0.95),
				"amount": 16,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.4, 3.0),
				"spread": 80.0,
				"size": Vector2(0.06, 0.15),
				"additive": true,
			}
		)
	)
	add_child(_star_burst)
	_poof_burst = (
		Fx
		. particles(
			{
				"color": Color(0.85, 0.82, 0.78, 0.85),
				"amount": 10,
				"lifetime": 0.45,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 1.8),
				"spread": 70.0,
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_poof_burst)


## Kamera: schräg von oben auf die Decke — flach genug für Kulisse am Horizont.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 10.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
	stage.set_half_height(4.9, 10.0)


## Karten per Raycast EXAKT unter die 2D-Rechtecke legen; Decke, Korb und
## Gooby richten sich am Kartenfeld aus. Nach jedem apply_view neu aufrufen.
func layout(rects: Array[Rect2], faces: Array[int]) -> void:
	while _cards.size() < rects.size():
		var card := _spawn_card()
		add_child(card)
		_cards.append(card)
		_flip.append(0.0)
		_faces.append(-1)
	_card_pos.clear()
	_card_w.clear()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for i in _cards.size():
		if i >= rects.size():
			_cards[i].visible = false
			continue
		var rect := rects[i]
		var center: Vector3 = stage.ground_point(rect.get_center())
		var edge: Vector3 = stage.ground_point(rect.get_center() + Vector2(rect.size.x * 0.5, 0.0))
		var w := clampf(center.distance_to(edge) * 1.7, 0.3, 4.0)
		_card_pos.append(center)
		_card_w.append(w)
		_cards[i].visible = true
		_cards[i].position = center
		_cards[i].scale = Vector3.ONE * w
		_set_face(i, faces[i])
		lo.x = minf(lo.x, center.x - w * 0.5)
		lo.z = minf(lo.z, center.z - w * 0.7)
		hi.x = maxf(hi.x, center.x + w * 0.5)
		hi.z = maxf(hi.z, center.z + w * 0.7)
	var pad := 0.8
	_blanket.position = Vector3((lo.x + hi.x) * 0.5, -0.01, (lo.z + hi.z) * 0.5)
	_blanket.scale = Vector3(hi.x - lo.x + pad * 2.0, 1.0, hi.z - lo.z + pad * 2.0)
	# Gooby sitzt NAH hinterm Feld (statt winzig am Horizont) und schaut drauf.
	gooby.position = Vector3((lo.x + hi.x) * 0.5 + (hi.x - lo.x) * 0.24, 0.0, lo.z - 1.35)
	gooby.scale = Vector3.ONE * 1.7
	gooby.rotation.y = -0.3
	# Korb + Snack-Ecke ÜBER BILDSCHIRM-ANKER in den sichtbaren unteren
	# Wiesenstreifen raycasten (Welt-Offsets rieten daneben — der Streifen
	# unterhalb der Decke ist nur wenige Zehntel Einheiten tief).
	var cam := stage.get("camera") as Camera3D
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	_basket.position = stage.ground_point(Vector2(vp.x * 0.13, vp.y * 0.94))
	_snacks.position = stage.ground_point(Vector2(vp.x * 0.82, vp.y * 0.93))


## Jeden Frame: Flip-Winkel weiterziehen, Zustand (Rücken/Motiv/gelöst) zeigen.
## `shows` = Sichtbarkeit je Karte (View entscheidet — Reveal/Peek/Zustand).
func sync(cards: Array[Dictionary], shows: Array[bool], pulse: float, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.4) * 0.03
	for i in _cards.size():
		if i >= cards.size():
			_cards[i].visible = false
			continue
		var card: Dictionary = cards[i]
		_set_face(i, int(card["face"]))
		var state := str(card["state"])
		var target := PI if (shows[i] or state == "matched") else 0.0
		_flip[i] = move_toward(_flip[i], target, FLIP_SPEED * delta)
		var node := _cards[i]
		var flipper := node.get_node("Flipper") as Node3D
		flipper.rotation.x = _flip[i]
		# Beim Drehen hebt die Karte leicht ab (kein Wühlen in der Decke).
		var mid := sin(clampf(_flip[i] / PI, 0.0, 1.0) * PI)
		flipper.position.y = 0.05 + mid * 0.45
		var face_up := _flip[i] > PI * 0.5
		(node.get_node("Flipper/Motiv") as Node3D).visible = face_up
		var body := node.get_node("Flipper/Blatt") as MeshInstance3D
		body.set_surface_override_material(0, _mat_matched if state == "matched" else _mat_face)
		node.get_node("Flipper/Ruecken").visible = not face_up


func match_fx(index: int) -> void:
	if index < 0 or index >= _card_pos.size():
		return
	Fx.burst(_star_burst, _card_pos[index] + Vector3(0.0, _card_w[index] * 0.7, 0.0))
	gooby.emote("ecstatic", 0.9)
	gooby.hop(0.3, 0.2)


func miss_fx(index: int) -> void:
	if index < 0 or index >= _card_pos.size():
		return
	Fx.burst(_poof_burst, _card_pos[index] + Vector3(0.0, _card_w[index] * 0.5, 0.0))
	gooby.emote("dizzy", 0.9)


func peek_fx() -> void:
	gooby.emote("happy", 1.2)
	stage.pulse_glow(0.7)


func cleared_fx() -> void:
	gooby.emote("ecstatic", 1.6)
	gooby.play_for("celebrate", 1.2)
	stage.pulse_glow(1.0)


## Motiv-Modell einer Karte setzen (nur bei Änderung — Endlos teilt Boards neu).
func _set_face(index: int, face: int) -> void:
	if _faces[index] == face:
		return
	_faces[index] = face
	var holder := _cards[index].get_node("Flipper/Motiv") as Node3D
	for child in holder.get_children():
		child.queue_free()
	var keys: Array[String] = MemoryMatchLogic.FACE_KEYS
	var key: String = keys[face % keys.size()]
	var model := Models.node(DIR + str(FACE_MODELS.get(key, "apple.glb")), 0.62)
	# Motiv hängt am Flipper und liegt bei 180° oben auf der Karte.
	model.rotation.x = PI
	model.position.y = -0.05
	holder.add_child(model)


func _spawn_card() -> Node3D:
	var root := Node3D.new()
	var flipper := Node3D.new()
	flipper.name = "Flipper"
	flipper.position.y = 0.05
	root.add_child(flipper)
	var body := MeshInstance3D.new()
	body.name = "Blatt"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.94, 0.07, 0.94 * CARD_RATIO)
	body_mesh.material = _mat_face
	body.mesh = body_mesh
	flipper.add_child(body)
	# Rückseite: rosa Deckplatte + rundes Wappen (liegt bei 0° oben).
	var back := Node3D.new()
	back.name = "Ruecken"
	flipper.add_child(back)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.86, 0.02, 0.86 * CARD_RATIO)
	plate_mesh.material = _mat_back
	plate.mesh = plate_mesh
	plate.position.y = 0.042
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.add_child(plate)
	var emblem := MeshInstance3D.new()
	var emblem_mesh := CylinderMesh.new()
	emblem_mesh.top_radius = 0.2
	emblem_mesh.bottom_radius = 0.2
	emblem_mesh.height = 0.03
	emblem_mesh.radial_segments = 18
	emblem_mesh.material = _mat_emblem
	emblem.mesh = emblem_mesh
	emblem.position.y = 0.058
	emblem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.add_child(emblem)
	# „?" auf dem Rücken: in 3 Sekunden klar, dass hier verdeckte Karten liegen.
	var quest := Label3D.new()
	quest.text = "?"
	quest.font_size = 180
	quest.pixel_size = 0.0024
	quest.modulate = Color(1.0, 0.97, 0.9, 0.95)
	quest.outline_size = 20
	quest.outline_modulate = Color(0.55, 0.18, 0.3, 0.9)
	quest.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	quest.position.y = 0.078
	back.add_child(quest)
	var holder := Node3D.new()
	holder.name = "Motiv"
	holder.visible = false
	flipper.add_child(holder)
	return root
