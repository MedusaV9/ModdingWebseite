class_name LampenSchalter
extends Node3D
## Lampen-Interactable (W3d CONTENT, Doc F §3.2): Tap auf eine Lampe öffnet
## ein Schalter-Sheet (W1c PanelSheet) mit fettem Kippschalter + simpler
## 2D-Gooby-Arm-Illustration. Beim Umlegen watschelt Gooby zur Lampe
## (`wave`-Clip als IK-Ersatz M1) und das Licht toggelt über die W2a-API
## `FurnitureNode.set_light_enabled` — Zustand persistiert pro Möbel-uid im
## `bad`-Slice (BadState.light_on).

var _host: InteractablesHost
var _furniture: Node3D
var _sheet: PanelSheet
var _illustration: ArmSwitchIllustration
var _busy := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_furniture = furniture
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))
	_apply_saved_state()


## Aktueller (persistierter) Licht-Zustand.
func is_on() -> bool:
	var gs := _host.game_state()
	if gs == null:
		return true
	return BadState.light_on(gs, str(_furniture.get("uid")))


func _apply_saved_state() -> void:
	if _furniture.has_method("set_light_enabled"):
		_furniture.set_light_enabled(is_on())


func _on_tapped() -> void:
	if _busy or _room_busy():
		return
	_open_sheet()


func _open_sheet() -> void:
	if _sheet == null:
		_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
		# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
		_sheet.theme = ThemeService.theme()
		_ui_layer().add_child(_sheet)
	_sheet.set_title(I18nService.t("bad.lampe.titel"))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_illustration = ArmSwitchIllustration.new()
	_illustration.switch_up = is_on()
	_illustration.custom_minimum_size = Vector2(0, 190)
	body.add_child(_illustration)
	var toggle := SquishButton.new()
	toggle.theme_type_variation = &"BtnTeal"
	toggle.text = I18nService.t("bad.lampe.umlegen")
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(_on_toggle_pressed)
	body.add_child(toggle)
	_sheet.add_content(body)
	_sheet.open()


func _on_toggle_pressed() -> void:
	if _busy:
		return
	_busy = true
	var target := not is_on()
	if _illustration != null:
		_illustration.switch_up = target
		_illustration.queue_redraw()
	_sheet.close()
	await _walk_and_flip(target)
	_busy = false


func _walk_and_flip(target: bool) -> void:
	var room := _host.room()
	var gooby: Node = room.gooby() if room != null and room.has_method("gooby") else null
	if gooby != null:
		if gooby.global_position.distance_to(global_position) > 3.0 and room.has_method("say"):
			room.say(I18nService.t("bad.lampe.komme"))
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.55, 0.0, 0.55), 4.0)
		gooby.play_clip("wave")
	if _furniture != null and is_instance_valid(_furniture):
		if _furniture.has_method("set_light_enabled"):
			_furniture.set_light_enabled(target)
	var gs := _host.game_state()
	if gs != null:
		BadState.set_light_on(gs, str(_furniture.get("uid")), target)
	if room != null and room.has_method("say"):
		room.say(I18nService.t("bad.lampe.klick"))
	if gooby != null:
		gooby.set_wander_enabled(true)


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer


class ArmSwitchIllustration:
	extends Control
	## Simple 2D-Illustration: Schalterplatte + Gooby-Arm, der den Kipphebel
	## umlegt (Doc F: „Skeuomorph, Daumen-groß“). Reines _draw() — kein Asset.

	var switch_up := true

	func _draw() -> void:
		var center := size / 2.0
		# Schalterplatte
		var plate := Rect2(center + Vector2(-46.0, -75.0), Vector2(92.0, 150.0))
		draw_rect(plate, Color("#F6EAD8"), true)
		draw_rect(plate, Color(0.29, 0.23, 0.21, 0.25), false, 4.0)
		# Kipphebel (oben = an)
		var pivot := center
		var tip := pivot + (Vector2(0.0, -46.0) if switch_up else Vector2(0.0, 46.0))
		draw_line(pivot, tip, Color("#4A3B36"), 16.0)
		draw_circle(tip, 14.0, Color("#FFD166"))
		draw_circle(pivot, 9.0, Color("#4A3B36"))
		# Gooby-Arm von rechts (Creme-Kapsel + Pfote mit Ballen)
		var shoulder := Vector2(size.x - 8.0, center.y + 46.0)
		var paw := tip + Vector2(30.0, 12.0)
		draw_line(shoulder, paw, Color("#FFF3E0"), 30.0)
		draw_circle(paw, 22.0, Color("#FFF3E0"))
		draw_circle(paw + Vector2(-5.0, -4.0), 6.0, Color("#F7C8CF"))
		for i in 3:
			var toe := paw + Vector2(-14.0 + i * 11.0, -14.0)
			draw_circle(toe, 3.6, Color("#F7C8CF"))
