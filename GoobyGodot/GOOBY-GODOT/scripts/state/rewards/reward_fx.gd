class_name RewardFx
extends RefCounted
## Geteilte Mikro-Belohnungs-Effekte (EF-1, EVAL-1 D4/D5/D6): Zahl-Floats,
## Herz-/Glitzer-/Funken-Bursts im 3D-Raum und der 2D-Konfetti-Burst für
## globale Feiern (Sticker/Level-Up). Reine Statics ohne Zustand — jeder
## Effekt räumt sich selbst auf und respektiert Reduced Motion:
## Partikel fallen weg, Zahl-Floats bleiben (statisch, kurz) sichtbar.

const MINT := Color("#59C9B9")
const ROSA := Color("#FF7BA9")
const GOLD := Color("#FFD166")
const INK := Color("#3B3630")

const FLOAT_DAUER_S := 1.2
const FLOAT_HUB_M := 0.55


## Beide Quellen prüfen: UiTheme (Laufzeit-Schalter, ThemeService) UND
## AppSettings (persistierte Einstellung) — Effekte hören auf jede von beiden.
static func reduced_motion(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	if ThemeService.is_reduced_motion(node):
		return true
	var settings := node.get_node_or_null("/root/AppSettings")
	return (
		settings != null
		and settings.has_method("is_reduced_motion")
		and settings.is_reduced_motion()
	)


## „+20“-Zahl über einer Welt-Position: steigt und blendet aus.
## Reduced Motion: steht still und verschwindet nach derselben Zeit.
static func float_text(parent: Node, world_pos: Vector3, text: String, color := MINT) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.name = "RewardFloat"
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 18
	label.outline_modulate = INK
	parent.add_child(label)
	label.global_position = world_pos
	var tree := parent.get_tree()
	if tree == null:
		return
	if reduced_motion(parent):
		# Methoden-Callable statt Lambda: die Verbindung löst sich beim
		# Freigeben des Labels selbst — ein Lambda-Capture würde nach einem
		# Szenenwechsel als "Lambda capture ... was freed" feuern (B2).
		tree.create_timer(FLOAT_DAUER_S).timeout.connect(label.queue_free)
		return
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + FLOAT_HUB_M, FLOAT_DAUER_S)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOAT_DAUER_S).set_delay(0.2)
	tween.tween_callback(label.queue_free)


## Herzchen-Burst (Streicheln/Füttern) — kleine rosa Quads, kurzlebig.
static func herz_burst(parent: Node, world_pos: Vector3, amount := 12) -> void:
	_burst_3d(parent, world_pos, amount, _gradient([ROSA, Color("#F4BFCD")]), 0.09)


## Glitzer-Burst (Pflege-Erfolg) — mint-goldenes Funkeln.
static func glitzer_burst(parent: Node, world_pos: Vector3, amount := 14) -> void:
	_burst_3d(parent, world_pos, amount, _gradient([MINT, Color("#FFF6E8")]), 0.06)


## Funken-Burst (Mini-Fund) — goldene Funken am Gooby.
static func funken_burst(parent: Node, world_pos: Vector3, amount := 10) -> void:
	_burst_3d(parent, world_pos, amount, _gradient([GOLD, Color("#FFB84D")]), 0.055)


## Pflege-Belohnung (EVAL-1 D6): „+{n}“-Float in Mint + Glitzer — der EINE
## geteilte Baustein für Dusche/Bad/Zähneputzen (jede Pflegehandlung soll
## identisch lesbar zurückmelden).
static func pflege_reward(parent: Node, world_pos: Vector3, betrag: int) -> void:
	float_text(parent, world_pos, "+%d" % betrag, MINT)
	glitzer_burst(parent, world_pos + Vector3(0.0, -0.25, 0.0))


## 2D-Konfetti-Regen für globale Feiern (Sticker-Toast, Hub-Layer).
## `parent` ist ein Control/CanvasLayer-Kind; Breite über `breite_px`.
static func konfetti_2d(parent: Node, amount := 40, breite_px := 640.0) -> void:
	if parent == null or not parent.is_inside_tree() or reduced_motion(parent):
		return
	var particles := CPUParticles2D.new()
	particles.name = "RewardKonfetti"
	particles.position = Vector2(breite_px * 0.5, -12.0)
	particles.one_shot = true
	particles.emitting = true
	particles.amount = amount
	particles.lifetime = 1.8
	particles.explosiveness = 0.85
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(breite_px * 0.4, 6.0)
	particles.direction = Vector2.DOWN
	particles.spread = 28.0
	particles.gravity = Vector2(0.0, 380.0)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 190.0
	particles.angular_velocity_min = -240.0
	particles.angular_velocity_max = 240.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	particles.hue_variation_min = -0.5
	particles.hue_variation_max = 0.5
	particles.color = GOLD
	parent.add_child(particles)
	_free_later(parent, particles, 2.2)


static func _burst_3d(
	parent: Node, world_pos: Vector3, amount: int, ramp: Gradient, size_m: float
) -> void:
	if parent == null or not parent.is_inside_tree() or reduced_motion(parent):
		return
	var particles := CPUParticles3D.new()
	particles.name = "RewardBurst"
	particles.amount = maxi(1, amount)
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.1
	particles.gravity = Vector3(0.0, -3.2, 0.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size_m, size_m)
	var mat := StandardMaterial3D.new()
	# Ohne vertex_color_use_as_albedo rendert der Gradient NICHT (grau).
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	particles.mesh = mesh
	particles.color_ramp = ramp
	parent.add_child(particles)
	particles.global_position = world_pos
	particles.emitting = true
	_free_later(parent, particles, 1.4)


static func _gradient(colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, colors[0])
	gradient.set_color(1, Color(colors[colors.size() - 1], 0.0))
	if colors.size() > 1:
		gradient.add_point(0.6, colors[1])
	return gradient


static func _free_later(parent: Node, node: Node, seconds: float) -> void:
	var tree := parent.get_tree()
	if tree == null:
		node.queue_free()
		return
	# Methoden-Callable statt Lambda-Capture (B2): stirbt `node` vor dem
	# Timeout (Szenenwechsel), räumt Godot die Verbindung selbst ab — ein
	# Lambda würde "Lambda capture ... was freed" in den Log spammen.
	tree.create_timer(seconds).timeout.connect(node.queue_free)
