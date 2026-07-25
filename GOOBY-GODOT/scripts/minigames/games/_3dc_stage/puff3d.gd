extends RefCounted
## Partikel-Baukasten der 3D-Bühnen (Agent 3D-C): GPUParticles3D mit
## Billboard-Quads und weichen Kenney-Sprites (star_03 / circle_05).
##
## Zwei Sorten:
##   stream(...) — dauerhaft (Triebwerk, Mehlstaub, Sternenstaub)
##   burst(...)  — Einmal-Wolke, per fire(node, pos) neu gezündet
##
## Alle Werte sind bewusst klein gehalten: ein Emitter = 1 Draw-Call, das
## Perf-Budget (≤ 250) bleibt damit locker eingehalten.

const STAR_TEX := "vfx/star_03.png"
const DOT_TEX := "vfx/circle_05.png"


## Dauer-Emitter. `cfg`: amount, lifetime, size, dir (Vector3), spread, speed
## (Vector2 min/max), gravity (Vector3), color, color_end, add (bool),
## scale_curve (Vector2 min/max), damping, local (bool).
static func stream(tex_path: String, cfg: Dictionary) -> GPUParticles3D:
	var node := _make(tex_path, cfg)
	node.one_shot = false
	node.emitting = bool(cfg.get("emitting", true))
	return node


## Einmal-Wolke (fire() zündet sie an einer Stelle neu).
static func burst(tex_path: String, cfg: Dictionary) -> GPUParticles3D:
	var node := _make(tex_path, cfg)
	node.one_shot = true
	node.explosiveness = float(cfg.get("explosiveness", 0.92))
	node.emitting = false
	return node


## Wolke an `pos` (lokal zum Elternknoten) neu zünden.
static func fire(node: GPUParticles3D, pos: Vector3, color := Color(0, 0, 0, 0)) -> void:
	if node == null:
		return
	node.position = pos
	if color.a > 0.0:
		var mat := node.process_material as ParticleProcessMaterial
		if mat != null:
			mat.color = color
	node.restart()
	node.emitting = true


static func _make(tex_path: String, cfg: Dictionary) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.amount = int(cfg.get("amount", 24))
	node.lifetime = float(cfg.get("lifetime", 0.9))
	node.local_coords = bool(cfg.get("local", true))
	node.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	node.process_material = _process_material(cfg)
	node.draw_pass_1 = _quad(cfg)
	node.material_override = _sprite_material(tex_path, cfg)
	# Emitter sitzen oft am Bildrand — ohne Marge cullt Godot sie wegen der
	# (kleinen) Ausgangs-AABB weg, obwohl die Partikel weit fliegen.
	node.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	return node


static func _process_material(cfg: Dictionary) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_align_y = false
	mat.direction = cfg.get("dir", Vector3.UP)
	mat.spread = float(cfg.get("spread", 25.0))
	var speed: Vector2 = cfg.get("speed", Vector2(0.6, 1.4))
	mat.initial_velocity_min = speed.x
	mat.initial_velocity_max = speed.y
	mat.gravity = cfg.get("gravity", Vector3(0.0, -1.2, 0.0))
	mat.damping_min = float(cfg.get("damping", 0.4))
	mat.damping_max = float(cfg.get("damping", 0.4)) * 1.6
	var scale_range: Vector2 = cfg.get("scale_range", Vector2(0.7, 1.2))
	mat.scale_min = scale_range.x
	mat.scale_max = scale_range.y
	mat.color = cfg.get("color", Color(1, 1, 1, 1))
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	var fade := Gradient.new()
	fade.set_color(0, cfg.get("color", Color(1, 1, 1, 1)))
	fade.set_color(1, cfg.get("color_end", Color(1, 1, 1, 0)))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	mat.color_ramp = ramp
	var box: Vector3 = cfg.get("box", Vector3.ZERO)
	if box != Vector3.ZERO:
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = box
	return mat


static func _quad(cfg: Dictionary) -> QuadMesh:
	var quad := QuadMesh.new()
	var size := float(cfg.get("size", 0.16))
	quad.size = Vector2(size, size)
	return quad


static func _sprite_material(tex_path: String, cfg: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.no_depth_test = bool(cfg.get("on_top", false))
	if bool(cfg.get("add", true)):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	return mat
