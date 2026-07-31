class_name EventProps
extends RefCounted
## Requisiten-Fabrik für den EventRunner (W7/CI-Split wegen gdlint
## max-file-lines; FB-6/CI: Header + fehlende Fabriken wiederhergestellt —
## der Split-Commit a7340a36 hatte nur table_top() übernommen, wodurch
## event_runner.gd nicht mehr kompilierte). PURE Statics, kein Zustand:
## der Runner positioniert die Props und verwaltet ihre Lebensdauer.


static func flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


## Tischplatte (Fluchttisch im Ereignis „Robo-Jagd“).
static func table_top() -> MeshInstance3D:
	var table := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(0.9, 0.08, 0.9)
	table.mesh = top
	table.material_override = flat_mat(Color(0.52, 0.36, 0.22))
	return table


## Stuhl („Kleber-Stuhl“): Sitzfläche + Lehne, relativ zur Gooby-Position.
static func chair_parts(base: Vector3) -> Array[MeshInstance3D]:
	var seat := MeshInstance3D.new()
	var seat_box := BoxMesh.new()
	seat_box.size = Vector3(0.55, 0.1, 0.55)
	seat.mesh = seat_box
	seat.material_override = flat_mat(Color(0.62, 0.45, 0.3))
	seat.position = base + Vector3(0.0, 0.22, 0.0)
	var back := MeshInstance3D.new()
	var back_box := BoxMesh.new()
	back_box.size = Vector3(0.55, 0.6, 0.08)
	back.mesh = back_box
	back.material_override = flat_mat(Color(0.62, 0.45, 0.3))
	back.position = base + Vector3(0.0, 0.55, 0.3)
	return [seat, back]


## Brüllender Fernseher („Fernbedienung“): Korpus + leuchtender Screen
## (Child-Name "Screen" — der Runner dimmt ihn beim Auflösen).
static func tv_set() -> Node3D:
	var tv := Node3D.new()
	var body := MeshInstance3D.new()
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.9, 0.6, 0.12)
	body.mesh = body_box
	body.material_override = flat_mat(Color(0.2, 0.2, 0.24))
	tv.add_child(body)
	var screen := MeshInstance3D.new()
	var screen_box := BoxMesh.new()
	screen_box.size = Vector3(0.78, 0.48, 0.02)
	screen.mesh = screen_box
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.9, 0.95, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.7, 0.85, 1.0)
	glow.emission_energy_multiplier = 2.0
	screen.material_override = glow
	screen.position.z = 0.07
	screen.name = "Screen"
	tv.add_child(screen)
	return tv


## Dunkel-Overlay mit Taschenlampen-Loch („Gewitter-Angst“). Der Runner
## verbindet gui_input und schiebt `hole_px` dem Zeiger hinterher.
static func flashlight_overlay(radius_px: float) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 hole_px = vec2(-4000.0, -4000.0);
uniform float radius_px = 150.0;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.1, 0.88);
void fragment() {
	float d = distance(FRAGCOORD.xy, hole_px);
	float a = tint.a * smoothstep(radius_px * 0.55, radius_px, d);
	COLOR = vec4(tint.rgb, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("radius_px", radius_px)
	overlay.material = mat
	return overlay


## Generische Choice-Karte (Nutella/Wurm/Karton): Buttons unten mittig,
## `options` = [{key, variation, …}]; on_pick bekommt die gewählte Option.
static func show_choice(layer: CanvasLayer, options: Array, on_pick: Callable) -> void:
	# W14 (FB3-Audit): die Options-Knöpfe (Herbert/Nutella/Karton) hatten
	# 14–33 pt Tippfläche und ragten hochkant aus der Safe-Area — physischer
	# 44-pt-Touch-Floor (Muster whats_next_hint) + Bottom-Inset-Abstand.
	var touch_floor := float(AcTokens.TOUCH_FLOOR)
	var bottom_inset := 0.0
	var vp := layer.get_viewport()
	if vp != null:
		touch_floor = maxf(touch_floor, UiScale.touch_px_per_pt(vp) * 46.0)
		bottom_inset = float(UiScale.safe_insets_canvas(vp)["bottom"])
	var choice := PanelContainer.new()
	choice.name = "EventChoice"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	choice.theme = ThemeService.theme()
	choice.theme_type_variation = &"AcCard"
	choice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	choice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice.position.y -= 40.0 + bottom_inset
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	choice.add_child(box)
	for option: Dictionary in options:
		var btn := SquishButton.new()
		btn.theme_type_variation = option.get("variation", &"BtnTeal")
		btn.text = I18nService.t(str(option.get("key", "")))
		btn.custom_minimum_size = Vector2(touch_floor, touch_floor)
		btn.pressed.connect(
			func() -> void:
				choice.queue_free()
				on_pick.call(option)
		)
		box.add_child(btn)
	layer.add_child(choice)


## Antippbare Requisite: Farbklotz + Area3D-Tap. `on_free` räumt die
## Runner-Buchführung (z. B. _props.erase) auf, wenn free_on_tap greift.
static func make_prop(
	color: Color, box_size: Vector3, on_tap: Callable, free_on_tap := true, on_free := Callable()
) -> Node3D:
	var prop := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		# Sonst rendert der „unsichtbare“ Tap-Helfer als opaker Klotz.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	prop.add_child(mesh)
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = box_size * 2.0
	shape.shape = col_box
	area.add_child(shape)
	area.input_event.connect(
		func(
			_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int
		) -> void:
			var pressed: bool = (
				(event is InputEventMouseButton and event.pressed)
				or (event is InputEventScreenTouch and event.pressed)
			)
			if pressed:
				if free_on_tap:
					prop.queue_free()
					if on_free.is_valid():
						on_free.call(prop)
				on_tap.call()
	)
	prop.add_child(area)
	return prop


## Einmaliger Partikel-Puff (Mehl, Gieß-Tröpfchen) am Host-Node.
static func puff_at(host: Node, pos: Vector3, color: Color) -> void:
	var puff := CPUParticles3D.new()
	puff.amount = 16
	puff.lifetime = 0.6
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.direction = Vector3(0, 1, 0)
	puff.spread = 60.0
	puff.initial_velocity_min = 0.8
	puff.initial_velocity_max = 1.6
	puff.gravity = Vector3(0, -2.0, 0)
	puff.scale_amount_min = 0.06
	puff.scale_amount_max = 0.14
	puff.color = color
	puff.position = pos
	host.add_child(puff)
	puff.emitting = true
	host.get_tree().create_timer(1.2).timeout.connect(puff.queue_free)
