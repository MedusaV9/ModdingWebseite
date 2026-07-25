extends RefCounted
## Kleine 3D-Bauteile der Minispiele (Agent 3D-B): Materialien, Boden, Ringe
## und GPUParticles3D-Emitter (Staub, Gischt, Funken, Glitzer).
##
## Reine Fabrik — kein Zustand, alles statisch. Die Spiele hängen die
## zurückgegebenen Knoten selbst in ihre Bühne.

## Einzige Ausnahme von „kein Zustand": die Partikelmaske wird einmal gebaut
## und von allen Emittern geteilt (sie ist unveränderlich).
static var _puff_cache: GradientTexture2D = null


## Standard-Look der Spielwelt: matte Pastellflächen ohne Spiegelung.
static func flat(color: Color, rough := 0.92) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	# 0, nicht 0,15: die Vorlage ist durchweg Lambert (kein Glanzanteil). Schon
	# ein Rest-Specular zieht bei streifendem Blick einen hellen Saum über
	# Böden und Fahrbahnen.
	mat.specular = 0.0
	return mat


## Leuchtendes Material (Münzen, Ringe, Powerups) — trägt den Glow-Puls.
static func glow(color: Color, energy := 1.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.28
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## Durchscheinende Fläche (Pfützen, Wasser-Overlay, Schilde).
static func glass(color: Color, unshaded := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.2
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Waagerechte Bodenplatte (Wiese, Wasser, Teppich).
static func ground(size: Vector2, color: Color, y := 0.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	plane.material = flat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Ring (Netzring, Abwurfring) — liegt in der xz-Ebene, wenn man ihn um 90°
## um x kippt; standardmäßig steht er senkrecht (Blick entlang z).
static func ring(radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.01, radius - thickness)
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 10
	torus.material = glow(color, 1.1)
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Weicher Kontaktschatten unter einer Figur (der Sonnenschatten allein
## verschwindet auf großen Distanzen — dieser Fleck hält die Figur am Boden).
static func blob_shadow(radius: float, strength := 0.3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	# Weicher Radialverlauf statt harter Fläche. MUL-Blending sah im
	# GL-Compatibility-Renderer wie ein schwarzes Rechteck aus — deshalb ein
	# normales Alpha-Quad mit Verlaufstextur.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_color = Color(0.24, 0.2, 0.22, strength)
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0
	mi.position.y = 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Partikel-Emitter. `cfg`: color, amount, lifetime, speed (Vector2 min/max),
## gravity (Vector3), spread (Grad), size (Vector2 min/max), one_shot (bool).
static func particles(cfg: Dictionary) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = float(cfg.get("radius", 0.18))
	proc.direction = cfg.get("direction", Vector3(0.0, 1.0, 0.0))
	proc.spread = float(cfg.get("spread", 40.0))
	var speed: Vector2 = cfg.get("speed", Vector2(0.8, 2.2))
	proc.initial_velocity_min = speed.x
	proc.initial_velocity_max = speed.y
	proc.gravity = cfg.get("gravity", Vector3(0.0, -4.5, 0.0))
	proc.damping_min = 0.4
	proc.damping_max = 1.2
	var size: Vector2 = cfg.get("size", Vector2(0.05, 0.13))
	proc.scale_min = size.x
	proc.scale_max = size.y
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 0.75))
	fade.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = fade
	proc.scale_curve = curve_tex
	proc.color = cfg.get("color", Color(1.0, 0.95, 0.85, 0.9))

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Runder Weichzeichner statt harter Kante: als reines Quad lag hinter dem
	# Lieferwagen eine Spur kleiner grauer WÜRFEL auf dem Asphalt statt einer
	# Staubfahne (und Gischt/Funken hatten dasselbe Problem).
	mat.albedo_texture = _puff_texture()
	mat.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD
		if bool(cfg.get("additive", false))
		else BaseMaterial3D.BLEND_MODE_MIX
	)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mesh.material = mat

	var node := GPUParticles3D.new()
	node.draw_pass_1 = mesh
	node.process_material = proc
	node.amount = int(cfg.get("amount", 16))
	node.lifetime = float(cfg.get("lifetime", 0.7))
	node.one_shot = bool(cfg.get("one_shot", false))
	node.explosiveness = float(cfg.get("explosiveness", 0.0))
	node.emitting = false
	node.local_coords = bool(cfg.get("local", false))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	return node


## Weiche runde Partikelmaske (einmal gebaut, von allen Emittern geteilt).
static func _puff_texture() -> GradientTexture2D:
	if _puff_cache != null:
		return _puff_cache
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.5, Color(1.0, 1.0, 1.0, 0.72))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	_puff_cache = tex
	return tex


## Einmaligen Ausbruch an einer Position auslösen (Landung, Treffer, Münze).
static func burst(node: GPUParticles3D, at: Vector3) -> void:
	if node == null:
		return
	node.global_position = at
	node.restart()
	node.emitting = true
