class_name AcWallpaper
extends ColorRect
## Der AC-Look für ALLE Screens: Cream-Wash + langsam schräg driftendes
## Pattern (Web-acui-Kacheln, kopiert nach `assets/ui/patterns/`).
## Einfach als unterstes Kind in jede Screen-Szene legen, Full-Rect-Anchors.
##
## Reduced Motion: hört auf `UiTheme.reduced_motion_changed` (Duck-Typing,
## kein harter Autoload-Zwang) und friert den Drift über den Shader-Uniform ein.

const SHADER := preload("res://scripts/ui/wallpaper_drift.gdshader")
const PATTERN_DIR := "res://assets/ui/patterns/"

## Pattern-Name ohne Präfix/Endung, z. B. "leaves", "dots", "arcade".
@export var pattern: String = "leaves":
	set(value):
		pattern = value
		_apply_pattern()

## Grundfarbe unter dem Pattern (Screen-Wash).
@export var wash: Color = AcTokens.BG_CREAM:
	set(value):
		wash = value
		_set_uniform("wash", wash)

## Pattern-Deckkraft — Web-Guardrail: ≤ 0.06.
@export_range(0.0, 0.2) var pattern_opacity: float = AcTokens.DRIFT_OPACITY:
	set(value):
		pattern_opacity = value
		_set_uniform("opacity", pattern_opacity)

var _mat: ShaderMaterial


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	color = AcTokens.BG_CREAM
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_uniform("drift", AcTokens.DRIFT_TILES_PER_SEC)
	_set_uniform("wash", wash)
	_set_uniform("opacity", pattern_opacity)
	_apply_pattern()
	_update_rect_size()
	resized.connect(_update_rect_size)
	_hook_reduced_motion()


func set_pattern_by_name(name_without_prefix: String) -> void:
	pattern = name_without_prefix


func _apply_pattern() -> void:
	if _mat == null:
		return
	var path := "%spattern_%s.png" % [PATTERN_DIR, pattern]
	if not ResourceLoader.exists(path):
		push_warning("Wallpaper-Pattern fehlt: %s" % path)
		return
	_set_uniform("tile", load(path))


func _update_rect_size() -> void:
	_set_uniform("rect_size", size)


func _set_uniform(uniform: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(uniform, value)


func _hook_reduced_motion() -> void:
	var svc := get_node_or_null("/root/UiTheme")
	if svc == null:
		return
	if svc.has_signal("reduced_motion_changed"):
		svc.reduced_motion_changed.connect(_on_reduced_motion_changed)
	if "reduced_motion" in svc:
		_on_reduced_motion_changed(svc.reduced_motion)


func _on_reduced_motion_changed(enabled: bool) -> void:
	_set_uniform("motion_scale", 0.0 if enabled else 1.0)
