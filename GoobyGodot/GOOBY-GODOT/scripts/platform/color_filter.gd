class_name ColorFilter
extends CanvasLayer
## RW-7 — Vollbild-Farbfilter für Barrierefreiheit (Doc §4.3):
## Farbfehlsichtigkeits-Modi (Daltonisierung Protan/Deutan/Tritan) und
## hoher Kontrast als Screen-Space-Pass über der kompletten UI+3D-Ausgabe.
##
## WICHTIG (Doc): der Filter ist eine ZUSATZ-Hilfe — Formen/Icons/Text
## bleiben die primäre Kodierung im Spiel. Der Layer liegt unter dem
## Perf-Overlay (120) und über HUD/Panels; Maus/Touch gehen durch.

const LAYER_INDEX := 110

var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = LAYER_INDEX
	_rect = ColorRect.new()
	_rect.name = "FilterRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = _build_shader()
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


## mode: "aus"|"protan"|"deutan"|"tritan"; high_contrast schaltet den
## Kontrast-Boost dazu. Beides aus → Filter unsichtbar (0 Kosten).
func configure(mode: String, high_contrast: bool) -> void:
	if _rect == null:
		return
	var mode_idx := ["aus", "protan", "deutan", "tritan"].find(mode)
	if mode_idx < 0:
		mode_idx = 0
	_material.set_shader_parameter("mode", mode_idx)
	_material.set_shader_parameter("contrast", 1.22 if high_contrast else 1.0)
	_rect.visible = mode_idx != 0 or high_contrast


func is_active() -> bool:
	return _rect != null and _rect.visible


func current_mode() -> int:
	if _material == null:
		return 0
	return int(_material.get_shader_parameter("mode"))


## Daltonisierung: Defizit in LMS simulieren, Fehler auf sichtbare Kanäle
## umverteilen (Standard-Ansatz nach Fidaner/Machado); Kontrast als
## einfacher Pivot-Boost um 0.5.
func _build_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float contrast = 1.0;

const mat3 RGB2LMS = mat3(
	vec3(17.8824, 3.45565, 0.0299566),
	vec3(43.5161, 27.1554, 0.184309),
	vec3(4.11935, 3.86714, 1.46709));
const mat3 LMS2RGB = mat3(
	vec3(0.0809444479, -0.0102485335, -0.000365296938),
	vec3(-0.130504409, 0.0540193266, -0.00412161469),
	vec3(0.116721066, -0.113614708, 0.693511405));

void fragment() {
	vec3 rgb = texture(screen_tex, SCREEN_UV).rgb;
	if (mode != 0) {
		vec3 lms = RGB2LMS * rgb;
		vec3 sim_lms = lms;
		if (mode == 1) {
			sim_lms.x = 2.02344 * lms.y - 2.52581 * lms.z;
		} else if (mode == 2) {
			sim_lms.y = 0.494207 * lms.x + 1.24827 * lms.z;
		} else {
			sim_lms.z = -0.395913 * lms.x + 0.801109 * lms.y;
		}
		vec3 sim_rgb = LMS2RGB * sim_lms;
		vec3 err = rgb - sim_rgb;
		vec3 shifted = vec3(0.0,
			0.7 * err.r + err.g,
			0.7 * err.r + err.b);
		rgb = clamp(rgb + shifted, 0.0, 1.0);
	}
	rgb = clamp((rgb - vec3(0.5)) * contrast + vec3(0.5), 0.0, 1.0);
	COLOR = vec4(rgb, 1.0);
}
"""
	return shader
