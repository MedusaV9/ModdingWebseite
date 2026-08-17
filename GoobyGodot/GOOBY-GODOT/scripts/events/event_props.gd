class_name EventProps
extends RefCounted
## Requisiten-Fabrik für den EventRunner (W7/CI-Split wegen gdlint
## max-file-lines; FB-6/CI: Header + fehlende Fabriken wiederhergestellt —
## der Split-Commit a7340a36 hatte nur table_top() übernommen, wodurch
## event_runner.gd nicht mehr kompilierte). PURE Statics, kein Zustand:
## der Runner positioniert die Props und verwaltet ihre Lebensdauer.

## Luft zwischen Choice-Karte und Lane-Oberkante bzw. Blocker-Rects (px).
const CHOICE_GAP := 10.0
## Rand-Luft der Choice-Karte zur Safe-Area-Oberkante (px).
const CHOICE_TOP_PAD := 8.0


## Choice-Karte mit Lane-Anker (W18/E3a): PRESET_CENTER_BOTTOM + fester
## Offset lagen HOCHKANT unterm HUD-Dock (nur ein rosa Streifen sichtbar).
## Die Karte legt sich stattdessen in die freie Bubble-Lane ÜBER der
## HUD-Bodenmöblierung (Hud.bubble_lane(): hochkant Dock-Oberkante, quer
## Auge/Chip-Zeile — beide Leitformate), weicht belegten BOTTOM-Rects
## (Gooby-Bubble) per UiAnchors.dodge nach OBEN aus, reserviert die Zone
## selbst (Nachzügler weichen ihr aus) und folgt Resize/Format-Wechseln.
## W21 (Event-Kaperung): `am_rand` ankert stattdessen RECHTS in der Lane —
## der Vertagen-Chip parkt an der Kante statt in der Welt-Tap-Mitte.
class ChoiceCard:
	extends PanelContainer

	var am_rand := false

	func _ready() -> void:
		get_viewport().size_changed.connect(relayout)
		UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, self)
		relayout()
		_relayout_settled()

	func _exit_tree() -> void:
		UiAnchors.release(UiAnchors.ZONE_BOTTOM, self)

	## In die Bubble-Lane legen; ohne (sichtbares) HUD — Stadt/Tests —
	## bleibt die Safe-Area-Unterkante die Lane-Referenz.
	func relayout() -> void:
		if not is_inside_tree():
			return
		var vp := get_viewport()
		var canvas := Vector2(vp.get_visible_rect().size)
		var insets := UiScale.safe_insets_canvas(vp)
		var lane := {
			"top": canvas.y - float(insets["bottom"]) - 12.0,
			"width": canvas.x - float(insets["left"]) - float(insets["right"]) - 24.0,
		}
		var hud := _hud()
		if hud != null:
			lane = hud.bubble_lane()
		var safe_top := float(insets["top"]) + EventProps.CHOICE_TOP_PAD
		var min_size := get_combined_minimum_size()
		var blockers := UiAnchors.occupied_rects(UiAnchors.ZONE_BOTTOM, self)
		var rect := Rect2()
		if am_rand:
			rect = EventProps.chip_rect(canvas, safe_top, lane, min_size, blockers)
		else:
			rect = EventProps.choice_rect(canvas, safe_top, lane, min_size, blockers)
		position = rect.position
		size = rect.size

	## Container-Minimum steht erst nach einem Layout-Frame (Theme/Fonts) —
	## danach einmal nachziehen (Muster whats_next_hint._relayout_settled).
	func _relayout_settled() -> void:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
		if is_instance_valid(self):
			relayout()

	func _hud() -> Hud:
		for node: Node in get_tree().get_nodes_in_group(&"hud"):
			if node is Hud and (node as Hud).is_visible_in_tree():
				return node
		return null


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


## PURE (Wächter-testbar): Ziel-Rect der Choice-Karte in Canvas-Pixeln.
## Mittig, Unterkante mit Luft an `lane.top` (Oberkante der HUD-Boden-
## möblierung), Breite ≤ lane.width; belegte BOTTOM-Rects (Gooby-Bubble)
## werden ÜBERstiegen, die Oberkante bleibt unterhalb von `safe_top`.
static func choice_rect(
	canvas: Vector2, safe_top: float, lane: Dictionary, card_size: Vector2, blockers: Array
) -> Rect2:
	var size := Vector2(minf(card_size.x, float(lane["width"])), card_size.y)
	var pos := Vector2((canvas.x - size.x) / 2.0, float(lane["top"]) - CHOICE_GAP - size.y)
	var rect := UiAnchors.dodge(Rect2(pos, size), blockers, UiAnchors.ZONE_BOTTOM, CHOICE_GAP)
	rect.position.y = maxf(rect.position.y, safe_top)
	return rect


## PURE (Wächter-testbar): Rand-Anker des Vertagen-Chips (W21 Event-
## Kaperung) — RECHTS bündig mit der Lane-Kante statt mittig in der
## Welt-Tap-Zone, Unterkante mit Luft an `lane.top` wie die Karte;
## belegte BOTTOM-Rects werden überstiegen, Oberkante bleibt safe.
static func chip_rect(
	canvas: Vector2, safe_top: float, lane: Dictionary, chip_size: Vector2, blockers: Array
) -> Rect2:
	var size := Vector2(minf(chip_size.x, float(lane["width"])), chip_size.y)
	var lane_rechts := canvas.x / 2.0 + float(lane["width"]) / 2.0
	var pos := Vector2(lane_rechts - size.x, float(lane["top"]) - CHOICE_GAP - size.y)
	var rect := UiAnchors.dodge(Rect2(pos, size), blockers, UiAnchors.ZONE_BOTTOM, CHOICE_GAP)
	rect.position.y = maxf(rect.position.y, safe_top)
	return rect


## Vertagen-Chip (W21 Event-Kaperung): kleine AcChip-Pille am Lane-Rand
## („{gooby} wartet…“) — blockt NUR sich selbst, die Welt bleibt spielbar.
## Tap räumt den Chip ab und ruft `on_tap` (holt die Wahlkarte zurück).
static func show_chip(layer: CanvasLayer, text: String, on_tap: Callable) -> Control:
	var touch_floor := float(AcTokens.TOUCH_FLOOR)
	var vp := layer.get_viewport()
	if vp != null:
		touch_floor = maxf(touch_floor, UiScale.touch_px_per_pt(vp) * 44.0)
	var chip := ChoiceCard.new()
	chip.am_rand = true
	chip.name = "EventChoiceChip"
	chip.theme = ThemeService.theme()
	# Die AC-Optik trägt die Pille selbst — das Panel ist reine Geometrie.
	chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var knopf := SquishButton.new()
	knopf.theme_type_variation = &"AcChip"
	knopf.text = text
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.custom_minimum_size = Vector2(0.0, touch_floor)
	knopf.pressed.connect(
		func() -> void:
			chip.queue_free()
			on_tap.call()
	)
	chip.add_child(knopf)
	layer.add_child(chip)
	return chip


## Generische Choice-Karte (Nutella/Wurm/Karton): `options` = [{key,
## variation, …}]; on_pick bekommt die gewählte Option. Gibt die Karte
## zurück, damit der Runner sie bei einem Abbruch (Raumwechsel) abräumt.
## Position: ChoiceCard ankert sich selbst in der Bubble-Lane (W18/E3a).
static func show_choice(layer: CanvasLayer, options: Array, on_pick: Callable) -> Control:
	# W14 (FB3-Audit): die Options-Knöpfe (Herbert/Nutella/Karton) hatten
	# 14–33 pt Tippfläche und ragten hochkant aus der Safe-Area — physischer
	# 44-pt-Touch-Floor (Muster whats_next_hint).
	var touch_floor := float(AcTokens.TOUCH_FLOOR)
	var vp := layer.get_viewport()
	if vp != null:
		touch_floor = maxf(touch_floor, UiScale.touch_px_per_pt(vp) * 46.0)
	var choice := ChoiceCard.new()
	choice.name = "EventChoice"
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	choice.theme = ThemeService.theme()
	choice.theme_type_variation = &"AcCard"
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
	return choice


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
