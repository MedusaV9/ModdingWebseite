class_name PostFx
extends Node
## FEEL-AC — zentraler, mobil-tauglicher Post-Processing-Stapel für ALLE
## Szenen. Muster wie AudioDirector: bevorzugt Autoload (/root/Fx, Request
## liegt im project.godot-Handoff), sonst lazy-Fallback unter /root —
## beide Wege teilen denselben Zustand.
##
## Bausteine (bewusst billig — Ziel iPhone/Android):
##  - VIGNETTE + warme FARBKORREKTUR je Tageszeit + BLENDE: EIN Fullscreen-
##    ColorRect OHNE Screen-Read (nur ALU, 1 Draw-Call).
##  - EMOTIONS-PULS (kurzer Weichzeichner + Farbstoß): zweites Rect MIT
##    hint_screen_texture, aber nur während eines Pulses sichtbar —
##    versteckte CanvasItems kosten keinen Screen-Copy.
##  - BLOOM: glow_* am VORHANDENEN Environment der Szene (Räume bringen
##    ihres mit, s. room_base._build_environment) — nur Stufe "hoch",
##    exakt dieselbe Regel wie QualityService._apply_post_fx (kein Kampf).
##  - STIMMUNGS-SÄTTIGUNG: adjustment_saturation am selben Environment.
##  - TIEFENSCHÄRFE-Andeutung (nahaufnahme): CameraAttributesPractical auf
##    der aktiven Kamera — nur Stufe "hoch"; unter gl_compatibility still
##    wirkungslos (kein Crash).
##
## Abschaltbar über die VORHANDENE Qualitätsstufe (Einstellungen → Grafik →
## Nachbearbeitung, graphics.post_fx: aus/dezent/hoch — QualityService).
## Reduced Motion: Pulse werden mild (kein Blur, halber Farbstoß).

signal level_geaendert(level: String)

const NODE_NAME := "PostFx"
const AUTOLOAD_PFAD := "/root/Fx"
## CanvasLayer über der Szene/HUD, unter Dev-Overlays.
const LAYER_INDEX := 80
const PULS_ABKLING_PRO_S := 2.2
## Bloom NUR auf hellen Akzenten (Lampen, Glanzlichter) — Werte bewusst
## niedrig, sonst wäscht ein heller Innenraum komplett aus.
const GLOW_INTENSITAET := 0.35
const GLOW_BLOOM := 0.06
const GLOW_SCHWELLE := 1.05
const DOF_UEBERGANG_M := 1.4
const DOF_STAERKE := 0.065

## Vignette/Tint/Blende — reine ALU, kein Screen-Read (Mobile-Budget).
const OVERLAY_SHADER := """
shader_type canvas_item;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 blende = vec4(0.07, 0.06, 0.09, 0.0);

vec4 ueber(vec4 unten, vec4 oben) {
	float a = oben.a + unten.a * (1.0 - oben.a);
	vec3 rgb = oben.rgb * oben.a + unten.rgb * unten.a * (1.0 - oben.a);
	return vec4(rgb / max(a, 1e-5), a);
}

void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	d.x *= 1.15;
	float rand_wert = smoothstep(0.42, 0.78, length(d));
	vec4 vig = vec4(0.09, 0.07, 0.12, vignette * 0.5 * rand_wert);
	vec4 aus = ueber(tint, vig);
	aus = ueber(aus, blende);
	COLOR = aus;
}
"""

## Emotions-Puls — liest den Schirm (4 Taps), nur sichtbar während Puls.
const PULS_SHADER := """
shader_type canvas_item;
uniform sampler2D bild : hint_screen_texture, filter_linear;
uniform float staerke : hint_range(0.0, 1.0) = 0.0;
uniform vec4 farbe = vec4(1.0);
uniform float weich : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 s = texture(bild, uv).rgb;
	vec2 o = vec2(0.005) * staerke * weich;
	if (weich > 0.001) {
		s += texture(bild, uv + vec2(o.x, o.y)).rgb;
		s += texture(bild, uv + vec2(-o.x, o.y)).rgb;
		s += texture(bild, uv + vec2(o.x, -o.y)).rgb;
		s += texture(bild, uv + vec2(-o.x, -o.y)).rgb;
		s /= 5.0;
	}
	vec3 getoent = mix(s, s * 0.6 + farbe.rgb * 0.4, staerke * 0.55);
	COLOR = vec4(getoent, clamp(staerke, 0.0, 1.0) * 0.85);
}
"""

## Tageszeit → warme/kühle Tönung: [stunde, r, g, b, alpha] (linear
## interpoliert, 24 h zyklisch). Mittags neutral, abends warm, nachts kühl.
const TAGES_TINTS: Array = [
	[0.0, 0.45, 0.55, 0.85, 0.10],
	[5.0, 0.45, 0.55, 0.85, 0.10],
	[7.5, 1.0, 0.85, 0.62, 0.06],
	[11.0, 1.0, 1.0, 1.0, 0.0],
	[16.0, 1.0, 1.0, 1.0, 0.0],
	[19.0, 1.0, 0.72, 0.45, 0.08],
	[21.5, 0.55, 0.55, 0.85, 0.08],
	[24.0, 0.45, 0.55, 0.85, 0.10],
]

## Duplikat-Schutz für get_or_create (deferred add_child, s. AudioDirector).
static var _fallback: PostFx

## Tests: ersetzt /root/AppSettings bzw. das Ziel-Viewport.
var settings_override: Object = null
var viewport_override: Viewport = null
## Tests: −1 = AppSettings fragen, 0 = aus, 1 = an.
var reduced_motion_override := -1

var _layer: CanvasLayer = null
var _overlay: ColorRect = null
var _puls_rect: ColorRect = null
var _level := "dezent"
var _tint := Color(1.0, 1.0, 1.0, 0.0)
var _stimmung_saettigung := 1.0
var _puls := 0.0
var _blende := 0.0
var _blende_tween: Tween = null
var _dof_cam: Camera3D = null
var _dof_vorher: CameraAttributes = null


## Autoload /root/Fx bevorzugt, sonst lazy-Instanz unter /root.
static func get_or_create(from: Node) -> PostFx:
	var autoload := from.get_node_or_null(AUTOLOAD_PFAD)
	if autoload is PostFx:
		return autoload
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is PostFx:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := PostFx.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


func _ready() -> void:
	_baue_overlay()
	var settings := _settings()
	if settings != null and settings.has_signal("setting_changed"):
		settings.setting_changed.connect(_on_setting_changed)
	var quality := get_node_or_null("/root/Quality")
	if quality != null and quality.has_signal("quality_changed"):
		quality.quality_changed.connect(_on_quality_changed)
	refresh()


func _process(delta: float) -> void:
	if _puls <= 0.0:
		return
	_puls = maxf(_puls - PULS_ABKLING_PRO_S * delta, 0.0)
	_setze_puls_uniforms()
	if _puls <= 0.001:
		_puls = 0.0
		_puls_rect.visible = false


# ── Öffentliche API ───────────────────────────────────────────────────────────


## Aktive Stufe ("aus"/"dezent"/"hoch") — folgt QualityService/AppSettings.
func level() -> String:
	return _level


## Stufe neu ermitteln und alles anwenden (Boot, Settings-Wechsel, Tests).
func refresh() -> void:
	var vorher := _level
	_level = _ermittle_level()
	_wende_level_an()
	if _level != vorher:
		level_geaendert.emit(_level)


## Warme Farbkorrektur je Tageszeit (Stunde 0..24, zyklisch interpoliert).
func set_tageszeit(stunde: float) -> void:
	var h := fposmod(stunde, 24.0)
	for i in range(TAGES_TINTS.size() - 1):
		var a: Array = TAGES_TINTS[i]
		var b: Array = TAGES_TINTS[i + 1]
		if h < float(a[0]) or h > float(b[0]):
			continue
		var t := 0.0
		if float(b[0]) > float(a[0]):
			t = (h - float(a[0])) / (float(b[0]) - float(a[0]))
		_tint = Color(
			lerpf(float(a[1]), float(b[1]), t),
			lerpf(float(a[2]), float(b[2]), t),
			lerpf(float(a[3]), float(b[3]), t),
			lerpf(float(a[4]), float(b[4]), t)
		)
		break
	_setze_overlay_uniforms()


## Stimmungs-Sättigung: elend = leicht entsättigt, selig = leicht satter.
func set_stimmung(wert: float) -> void:
	_stimmung_saettigung = 0.96 + 0.08 * clampf(wert, 0.0, 100.0) / 100.0
	_wende_env_an()


## Kurzer Weichzeichner + Farbstoß bei starken Emotionen. Stufe "aus" =
## no-op; "dezent"/Reduced Motion = milder Farbstoß ohne Blur.
func emotions_puls(farbe: Color, staerke := 1.0) -> void:
	if _level == "aus" or _puls_rect == null:
		return
	var mild := _level != "hoch" or _reduziert()
	_puls = clampf(staerke, 0.0, 1.0) * (0.55 if mild else 1.0)
	var material := _puls_rect.material as ShaderMaterial
	material.set_shader_parameter("farbe", farbe)
	material.set_shader_parameter("weich", 0.0 if mild else 1.0)
	_setze_puls_uniforms()
	_puls_rect.visible = true


func puls_wert() -> float:
	return _puls


## Sanfte Blende (Szenenwechsel): zu = dunkel, auf = frei.
func blende_zu(dauer_s := 0.35) -> void:
	_blende_nach(1.0, dauer_s)


func blende_auf(dauer_s := 0.45) -> void:
	_blende_nach(0.0, dauer_s)


func blende_wert() -> float:
	return _blende


## Tiefenschärfe-Andeutung für Nahaufnahmen/Dialoge (nur Stufe "hoch";
## unter gl_compatibility wirkungslos, unter mobile/forward echt).
func nahaufnahme(aktiv: bool, fokus_m := 1.8) -> void:
	if aktiv and _level != "hoch":
		return
	var viewport := _viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_3d()
	if aktiv:
		if cam == null:
			return
		if _dof_cam == null:
			_dof_cam = cam
			_dof_vorher = cam.attributes
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = fokus_m + DOF_UEBERGANG_M
		attrs.dof_blur_far_transition = DOF_UEBERGANG_M
		attrs.dof_blur_amount = DOF_STAERKE
		_dof_cam.attributes = attrs
		return
	if _dof_cam != null and is_instance_valid(_dof_cam):
		_dof_cam.attributes = _dof_vorher
	_dof_cam = null
	_dof_vorher = null


func nahaufnahme_aktiv() -> bool:
	return _dof_cam != null


## Kosten-Messung (Artefakt-Probe druckt an/aus im Vergleich).
func messung() -> Dictionary:
	return {
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objekte": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}


func overlay_sichtbar() -> bool:
	return _layer != null and _layer.visible


# ── Aufbau / Anwendung ────────────────────────────────────────────────────────


func _baue_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PostFxLayer"
	_layer.layer = LAYER_INDEX
	add_child(_layer)
	_overlay = _fullscreen_rect("Overlay", OVERLAY_SHADER)
	_layer.add_child(_overlay)
	_puls_rect = _fullscreen_rect("Puls", PULS_SHADER)
	_puls_rect.visible = false
	_layer.add_child(_puls_rect)
	_setze_overlay_uniforms()


func _fullscreen_rect(rect_name: String, shader_code: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = shader_code
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	return rect


func _wende_level_an() -> void:
	if _layer != null:
		_layer.visible = _level != "aus"
	if _level == "aus":
		_puls = 0.0
		if _puls_rect != null:
			_puls_rect.visible = false
		nahaufnahme(false)
	_wende_env_an()
	_setze_overlay_uniforms()


## Glow/Sättigung nur am VORHANDENEN Szenen-Environment — Szenen ohne
## eigenes Environment bleiben unangetastet (Regel wie QualityService).
func _wende_env_an() -> void:
	var viewport := _viewport()
	if viewport == null:
		return
	var welt := viewport.find_world_3d()
	if welt == null or welt.environment == null:
		return
	var env := welt.environment
	env.glow_enabled = _level == "hoch"
	if env.glow_enabled:
		env.glow_intensity = GLOW_INTENSITAET
		env.glow_bloom = GLOW_BLOOM
		env.glow_hdr_threshold = GLOW_SCHWELLE
	env.adjustment_enabled = _level != "aus"
	env.adjustment_saturation = _stimmung_saettigung if _level != "aus" else 1.0


func _setze_overlay_uniforms() -> void:
	if _overlay == null:
		return
	var material := _overlay.material as ShaderMaterial
	material.set_shader_parameter("vignette", 0.35 if _level != "aus" else 0.0)
	material.set_shader_parameter("tint", _tint)
	material.set_shader_parameter("blende", Color(0.07, 0.06, 0.09, _blende))


func _setze_puls_uniforms() -> void:
	if _puls_rect == null:
		return
	(_puls_rect.material as ShaderMaterial).set_shader_parameter("staerke", _puls)


func _blende_nach(ziel: float, dauer_s: float) -> void:
	if _level == "aus" or _overlay == null:
		_blende = 0.0
		_setze_overlay_uniforms()
		return
	if _blende_tween != null and _blende_tween.is_valid():
		_blende_tween.kill()
	if dauer_s <= 0.0 or not is_inside_tree():
		_blende = ziel
		_setze_overlay_uniforms()
		return
	_blende_tween = create_tween()
	_blende_tween.tween_method(_setze_blende, _blende, ziel, dauer_s)


func _setze_blende(wert: float) -> void:
	_blende = clampf(wert, 0.0, 1.0)
	_setze_overlay_uniforms()


func _ermittle_level() -> String:
	var quality := get_node_or_null("/root/Quality")
	if settings_override == null and quality != null and quality.has_method("post_fx_level"):
		return str(quality.post_fx_level())
	var settings := _settings()
	if settings != null and settings.has_method("value_of"):
		return str(settings.value_of("graphics.post_fx"))
	return "dezent"


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "graphics.post_fx" or key == "graphics.preset":
		refresh()


func _on_quality_changed(_bundle: Dictionary) -> void:
	refresh()


func _settings() -> Object:
	if settings_override != null:
		return settings_override
	return get_node_or_null("/root/AppSettings")


func _viewport() -> Viewport:
	if viewport_override != null:
		return viewport_override
	if not is_inside_tree():
		return null
	return get_tree().root


func _reduziert() -> bool:
	if reduced_motion_override >= 0:
		return reduced_motion_override == 1
	var settings := _settings()
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
