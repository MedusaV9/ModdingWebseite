extends Node3D
## 3D-Partikel der Rückbau-Spiele (Agent 3D-A): ein wiederverwendbarer
## GPUParticles3D-Ausbruch statt der 2D-Konfettikreise der Vorgängerfassung.
##
## Der Knoten hält EINEN Emitter und wird per `burst(position)` an die
## Trefferstelle geworfen — kein Instanziieren pro Treffer, konstant ein
## Draw-Call. Wer mehrere Farben braucht, hängt mehrere Sparks in die Bühne.

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const STAR_TEX := "res://assets/minigames/_3da_stage/vfx/star_03.png"

var particles: GPUParticles3D


## Emitter bauen. `cfg`: color, amount, lifetime, speed (Vector2 min/max),
## gravity (Vector3), spread (Grad), size (Vector2 min/max), radius,
## texture ("star"|"puff"), additive (bool), direction (Vector3).
func build(cfg: Dictionary) -> void:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = float(cfg.get("radius", 0.14))
	proc.direction = cfg.get("direction", Vector3.UP)
	proc.spread = float(cfg.get("spread", 55.0))
	var speed: Vector2 = cfg.get("speed", Vector2(1.2, 3.0))
	proc.initial_velocity_min = speed.x
	proc.initial_velocity_max = speed.y
	proc.gravity = cfg.get("gravity", Vector3(0.0, -4.0, 0.0))
	proc.damping_min = 0.3
	proc.damping_max = 1.1
	proc.angular_velocity_min = -180.0
	proc.angular_velocity_max = 180.0
	var size: Vector2 = cfg.get("size", Vector2(0.06, 0.16))
	proc.scale_min = size.x
	proc.scale_max = size.y
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.2))
	fade.add_point(Vector2(0.25, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = fade
	proc.scale_curve = curve_tex
	proc.color = cfg.get("color", Color(1.0, 0.93, 0.7))

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD
		if bool(cfg.get("additive", true))
		else BaseMaterial3D.BLEND_MODE_MIX
	)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	# Der weiche Fleck kommt aus der gerechneten Alpha-Scheibe: das gelieferte
	# PNG trägt seine Rundung nur in der Helligkeit und würde als Staubwolke
	# (nicht-additiv) ein Rechteck malen.
	if str(cfg.get("texture", "star")) == "puff":
		mat.albedo_texture = Props3D.disc()
	elif ResourceLoader.exists(STAR_TEX):
		mat.albedo_texture = load(STAR_TEX)
	quad.material = mat

	particles = GPUParticles3D.new()
	particles.draw_pass_1 = quad
	particles.process_material = proc
	particles.amount = int(cfg.get("amount", 18))
	particles.lifetime = float(cfg.get("lifetime", 0.8))
	particles.one_shot = true
	particles.explosiveness = float(cfg.get("explosiveness", 0.9))
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-10, -6, -10), Vector3(20, 14, 20))
	add_child(particles)


## Einmaligen Ausbruch an einer Weltposition auslösen.
func burst(at: Vector3) -> void:
	if particles == null:
		return
	particles.global_position = at
	particles.restart()
	particles.emitting = true


## Dauer-Emitter (Wasserkräusel, Nebelschwaden) ein-/ausschalten.
func stream(on: bool) -> void:
	if particles == null:
		return
	particles.one_shot = false
	particles.emitting = on
