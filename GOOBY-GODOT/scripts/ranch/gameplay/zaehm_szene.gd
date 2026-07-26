class_name RanchZaehmSzene
extends Node3D
## Zaehm-Begegnung (RW-2, IDEAS-1 A5 + IDEAS-3 Kap. 1): Anschleichen an
## ein Wildpferd + Beruhigen im Schnaub-Rhythmus. ALLE Regeln kommen aus
## RanchHorseTaming (PURE); diese Szene ist Verdrahtung: Bewegung,
## Kamera, HUD-Balken, Takt-Puls und Feier. KEIN Abwurf-Frust — ein
## Fehlschlag heisst nur "es trabt davon, kommt wieder" (Cooldown).
##
## Steuerung: WASD/Pfeile bewegen, C = Ducken (Toggle, auch HUD-Button),
## Leertaste/HUD-Button = Beruhigen-Tipp. Einbau (RW-1/RANCH-1):
## szene.seed_wert setzen, `gezaehmt(pferd)` verbinden, mounten.

signal gezaehmt(pferd: Dictionary)

const Taming := preload("res://scripts/ranch/gameplay/horse_taming.gd")

const GEH_TEMPO := 3.0
const DUCK_TEMPO := 1.2
const START_ABSTAND_M := 14.0
const INK := Color("#3B3630")
const CREME := Color("#FFF6E8")
const TEAL := Color("#5FA8A0")
const ROSA := Color("#E98CA0")
const GOLD := Color("#F2B04C")

## Begegnungs-Seed: gleicher Seed = gleiches Wildpferd (deterministisch).
@export var seed_wert := 1234
## Eigene Kamera bauen (false, wenn die Welt schon eine stellt).
@export var use_camera := true

var zustand: Dictionary = {}
var wildpferd: Dictionary = {}
var geduckt := false

var _pferd_node: RanchPferd
var _spieler: Node3D
var _kamera: Camera3D
var _hud: Control
var _balken_aufmerksam: ColorRect
var _balken_ruhe: ColorRect
var _hint: Label
var _feedback: Label
var _feedback_t := 0.0
var _puls: Control
var _puls_t := 0.0
var _beruhigen_btn: Button
var _ducken_btn: Button
var _fertig := false


func _ready() -> void:
	zustand = Taming.neue_begegnung(seed_wert)
	wildpferd = Taming.wildpferd_dict(seed_wert, RanchRassen.load_balance())
	_baue_welt()
	_baue_hud()
	if use_camera:
		_kamera = Camera3D.new()
		_kamera.current = true
		add_child(_kamera)


func _process(delta: float) -> void:
	if _fertig:
		return
	var bewegung := _lese_bewegung()
	_spieler.position += bewegung * (DUCK_TEMPO if geduckt else GEH_TEMPO) * delta
	_spieler.scale.y = 0.72 if geduckt else 1.0
	var abstand := _spieler.position.distance_to(_pferd_node.get_parent_node_3d().position)
	match str(zustand.get("phase")):
		"anschleichen":
			var neu := Taming.step_anschleichen(
				zustand, delta, abstand, bewegung.length() > 0.05, geduckt
			)
			_auf_event(str(neu.get("event", "")))
			zustand = neu
		"beruhigen":
			var neu := Taming.step_beruhigen(zustand, delta)
			_auf_event(str(neu.get("event", "")))
			zustand = neu
		"davongetrabt":
			var neu := Taming.step_cooldown(zustand, delta)
			_auf_event(str(neu.get("event", "")))
			zustand = neu
	_update_hud(delta)
	if _kamera != null:
		_update_kamera(delta)
	if _pferd_node != null:
		_pferd_node.get_parent_node_3d().visible = str(zustand.get("phase")) != "davongetrabt"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_C:
			_toggle_ducken()
		KEY_SPACE:
			_beruhigen_tipp()


## Beruhigen-Tipp (HUD-Button/Leertaste): nur in der Beruhigen-Phase.
func _beruhigen_tipp() -> void:
	if str(zustand.get("phase")) != "beruhigen" or _fertig:
		return
	var neu := Taming.beruhigen_tap(zustand)
	_auf_event(str(neu.get("event", "")))
	zustand = neu


func _toggle_ducken() -> void:
	geduckt = not geduckt
	_ducken_btn.button_pressed = geduckt


func _auf_event(event: String) -> void:
	match event:
		"bereit":
			_hint.text = I18nService.t("rpferd.zaehmen.beruhigen_hint")
			_beruhigen_btn.visible = true
			AudioDirector.try_play(self, "ui_open")
		"schnauben":
			_puls_t = 1.0
			_spiele_schnauben()
		"treffer":
			_zeige_feedback(I18nService.t("rpferd.zaehmen.treffer"), TEAL)
			AudioDirector.try_play(self, "mg_good")
		"daneben":
			_zeige_feedback(I18nService.t("rpferd.zaehmen.daneben"), ROSA)
			AudioDirector.try_play(self, "ui_error", 0.9)
		"gezaehmt":
			_zeige_feedback(I18nService.t("rpferd.zaehmen.gezaehmt"), GOLD)
			AudioDirector.try_play(self, "mg_win")
			_fertig = true
			_beruhigen_btn.visible = false
			gezaehmt.emit(wildpferd.duplicate(true))
		"davongetrabt":
			_zeige_feedback(I18nService.t("rpferd.zaehmen.davongetrabt"), CREME)
			_beruhigen_btn.visible = false
			_pferd_node.set_gait("galopp")
			AudioDirector.try_play(self, "mg_lose", 1.1)
		"wieder_da":
			_zeige_feedback(I18nService.t("rpferd.zaehmen.wieder_da"), CREME)
			_hint.text = I18nService.t("rpferd.zaehmen.anschleichen_hint")
			_pferd_node.set_gait("stand")
			_spieler.position = Vector3(0.0, 0.0, START_ABSTAND_M)


## ---------------------------------------------------------------- Aufbau


func _baue_welt() -> void:
	var licht := DirectionalLight3D.new()
	licht.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	licht.shadow_enabled = true
	add_child(licht)
	var umgebung := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.48, 0.7, 0.92)
	sky_mat.sky_horizon_color = Color(0.9, 0.95, 1.0)
	sky_mat.ground_horizon_color = Color(0.85, 0.92, 0.88)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	add_child(umgebung)
	umgebung.environment = env
	var boden := MeshInstance3D.new()
	var boden_mesh := PlaneMesh.new()
	boden_mesh.size = Vector2(70.0, 70.0)
	boden.mesh = boden_mesh
	boden.material_override = RanchPferd.material(Color(0.58, 0.78, 0.47))
	add_child(boden)
	# Wildpferd auf der Lichtung (leichter Wende-Winkel wirkt lebendig).
	var pferd_wurzel := Node3D.new()
	pferd_wurzel.position = Vector3(0.0, 0.0, 0.0)
	pferd_wurzel.rotation.y = 0.6
	add_child(pferd_wurzel)
	_pferd_node = RanchPferd.new()
	_pferd_node.set_aussehen(wildpferd)
	pferd_wurzel.add_child(_pferd_node)
	# Gooby-Proxy: pastellige Kapsel mit Gesicht reicht fuers Anschleichen.
	_spieler = Node3D.new()
	_spieler.position = Vector3(0.0, 0.0, START_ABSTAND_M)
	add_child(_spieler)
	var koerper := MeshInstance3D.new()
	var kapsel := CapsuleMesh.new()
	kapsel.radius = 0.34
	kapsel.height = 1.25
	koerper.mesh = kapsel
	koerper.position.y = 0.66
	koerper.material_override = RanchPferd.material(Color("#F2B04C"))
	_spieler.add_child(koerper)
	var auge := MeshInstance3D.new()
	var auge_mesh := SphereMesh.new()
	auge_mesh.radius = 0.05
	auge_mesh.height = 0.1
	auge.mesh = auge_mesh
	auge.position = Vector3(0.12, 1.02, -0.3)
	auge.material_override = RanchPferd.material(Color("#3A2E2E"))
	_spieler.add_child(auge)
	var auge2 := auge.duplicate() as MeshInstance3D
	auge2.position.x = -0.12
	_spieler.add_child(auge2)


func _baue_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	var box := VBoxContainer.new()
	box.position = Vector2(16.0, 16.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(box)
	_balken_aufmerksam = _baue_balken(box, I18nService.t("rpferd.zaehmen.aufmerksamkeit"), ROSA)
	_balken_ruhe = _baue_balken(box, I18nService.t("rpferd.zaehmen.ruhe"), TEAL)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position.y = 24.0
	_hint.text = I18nService.t("rpferd.zaehmen.anschleichen_hint")
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", CREME)
	_hint.add_theme_color_override("font_outline_color", INK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_hint)
	_feedback = Label.new()
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_feedback.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.position.y -= 70.0
	_feedback.add_theme_font_size_override("font_size", 34)
	_feedback.add_theme_color_override("font_outline_color", INK)
	_feedback.add_theme_constant_override("outline_size", 8)
	_feedback.modulate.a = 0.0
	_hud.add_child(_feedback)
	_puls = PulsRing.new()
	_puls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_puls.position.y -= 150.0
	_puls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_puls)
	_beruhigen_btn = Button.new()
	_beruhigen_btn.text = I18nService.t("rpferd.zaehmen.beruhigen")
	_beruhigen_btn.custom_minimum_size = Vector2(150.0, 64.0)
	_beruhigen_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_beruhigen_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_beruhigen_btn.position.y -= 96.0
	_beruhigen_btn.visible = false
	_beruhigen_btn.pressed.connect(_beruhigen_tipp)
	_hud.add_child(_beruhigen_btn)
	_ducken_btn = Button.new()
	_ducken_btn.text = I18nService.t("rpferd.zaehmen.ducken")
	_ducken_btn.toggle_mode = true
	_ducken_btn.custom_minimum_size = Vector2(110.0, 56.0)
	_ducken_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_ducken_btn.position += Vector2(24.0, -80.0)
	_ducken_btn.toggled.connect(func(an: bool) -> void: geduckt = an)
	_hud.add_child(_ducken_btn)


func _baue_balken(parent: Control, titel: String, farbe: Color) -> ColorRect:
	var label := Label.new()
	label.text = titel
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)
	var rahmen := ColorRect.new()
	rahmen.color = Color(INK.r, INK.g, INK.b, 0.25)
	rahmen.custom_minimum_size = Vector2(170.0, 14.0)
	rahmen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rahmen)
	var fill := ColorRect.new()
	fill.color = farbe
	fill.size = Vector2(0.0, 14.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rahmen.add_child(fill)
	return fill


## ------------------------------------------------------------ Darstellung


func _update_hud(delta: float) -> void:
	var a := float(zustand.get("aufmerksamkeit", 0.0)) / Taming.AUFMERKSAM_MAX
	_balken_aufmerksam.size.x = 170.0 * clampf(a, 0.0, 1.0)
	var ruhe := float(zustand.get("ruhe", 0.0)) / Taming.RUHE_ZIEL
	_balken_ruhe.size.x = 170.0 * clampf(ruhe, 0.0, 1.0)
	_balken_ruhe.get_parent_control().visible = str(zustand.get("phase")) != "anschleichen"
	if _feedback_t > 0.0:
		_feedback_t -= delta
		_feedback.modulate.a = clampf(_feedback_t / 0.4, 0.0, 1.0)
	if _puls_t > 0.0:
		_puls_t = maxf(0.0, _puls_t - delta / Taming.TAKT_S)
	_puls.set("staerke", _puls_t)
	_puls.visible = str(zustand.get("phase")) == "beruhigen"
	_puls.queue_redraw()


func _update_kamera(delta: float) -> void:
	var ziel := _spieler.position + Vector3(0.0, 2.4, 4.6)
	_kamera.position = _kamera.position.lerp(ziel, 1.0 - exp(-5.0 * delta))
	_kamera.look_at(_spieler.position * 0.4 + Vector3(0.0, 0.9, 0.0))


func _zeige_feedback(text: String, farbe: Color) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", farbe)
	_feedback.modulate.a = 1.0
	_feedback_t = 1.3


func _spiele_schnauben() -> void:
	var pfad := "res://assets/ranch/audio/sfx/pferd_schnauben_a.ogg"
	if not ResourceLoader.exists(pfad):
		AudioDirector.try_play(self, "gvz_pop")
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(pfad)
	player.bus = &"Sfx"
	player.pitch_scale = clampf(float(wildpferd.get("stimmPitch", 1.0)), 0.6, 1.4)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _lese_bewegung() -> Vector3:
	var richtung := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		richtung.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		richtung.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		richtung.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		richtung.x += 1.0
	return richtung.normalized() if richtung.length() > 0.0 else Vector3.ZERO


## Takt-Puls-Ring: pulsiert bei jedem Schnauben (staerke 1 → 0).
class PulsRing:
	extends Control

	var staerke := 0.0

	func _draw() -> void:
		if staerke <= 0.0:
			return
		var radius := 26.0 + 40.0 * (1.0 - staerke)
		var farbe := Color(0.37, 0.66, 0.63, staerke * 0.9)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, farbe, 5.0 * staerke + 1.5)
