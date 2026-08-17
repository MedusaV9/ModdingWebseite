class_name OrtSchild
extends Label3D
## Ortsschild über Stadt-Gebäuden (VIS-2, Trailer-Review „extrem klein und
## kaum lesbar“): ein Billboard-Label3D, das ab REF_DISTANZ mit der
## Kamera-Entfernung MITWÄCHST — auf dem Bildschirm unterschreitet die
## Schrift also nie ihre Mindestgröße. Sehr weit weg blendet das Schild
## weich aus statt zu einem unlesbaren Pixelhaufen zu schrumpfen. Für den
## Kontrast sitzt hinter der Schrift eine weiche Tafel (setze_tafel):
## tagsüber Creme hinter Tinten-Schrift, nachts der warme Glow (city_bau).
## Mobil-Budget: pro Schild 1 Label + 1 Quad, ein Distanz-Check pro Frame.

## Bis zu dieser Entfernung (m) bleibt das Schild in Weltgröße (Nah-Optik
## unverändert); dahinter wächst es linear mit — konstante Bildschirmgröße.
const REF_DISTANZ := 40.0
## Obergrenze des Mitwachsens — hoch genug für den Trailer-Überflug
## (~150 m), niedrig genug, dass ferne Schilder nicht kollidieren.
const SKALA_MAX := 4.5
## Ab hier weich ausblenden; ab FADE_ENDE ist das Schild unsichtbar —
## sehr ferne Schilder verschwinden, statt sich gegenseitig zu überlagern.
const FADE_START := 190.0
const FADE_ENDE := 260.0

## Weiche Karten-Textur (Alpha innen voll, aussen sanft auslaufend) für die
## Tages-Tafel — der radiale Nacht-Glow ist tagsüber praktisch unsichtbar.
static var _karten_tex: GradientTexture2D

var _basis_pixel_size := 0.0
var _basis_alpha := 1.0
var _tafel: MeshInstance3D
var _tafel_material: StandardMaterial3D
var _tafel_basis_alpha := 1.0


## Skalierungsfaktor für eine Kamera-Entfernung — PURE (Tests).
static func skala_fuer_distanz(distanz: float) -> float:
	return clampf(distanz / REF_DISTANZ, 1.0, SKALA_MAX)


## Sichtbarkeit für eine Kamera-Entfernung: 1 nah, 0 ab FADE_ENDE — PURE.
static func alpha_fuer_distanz(distanz: float) -> float:
	if distanz <= FADE_START:
		return 1.0
	return 1.0 - clampf((distanz - FADE_START) / (FADE_ENDE - FADE_START), 0.0, 1.0)


func _ready() -> void:
	_basis_pixel_size = pixel_size
	_basis_alpha = modulate.a


## Weiche Kontrast-Tafel hinter der Schrift (ersetzt eine vorhandene).
## `farbe` inkl. Alpha; `energie` = Emission (nachts Glow, tagsüber ~0.25);
## `kartig` = Tages-Look: deckende Karte mit weicher Kante statt Glow-Blob.
func setze_tafel(farbe: Color, energie: float, kartig := false) -> void:
	if _tafel != null:
		# Sofort aus dem Baum: gibt den Namen "SchildTafel" frei, sonst
		# wuerde die Ersatz-Tafel beim add_child auto-umbenannt.
		remove_child(_tafel)
		_tafel.queue_free()
	_tafel_material = CityAmbiente.schild_glow_material(farbe)
	_tafel_material.emission_energy_multiplier = energie
	if kartig:
		_tafel_material.albedo_texture = _karten_textur()
		_tafel_material.emission_texture = _karten_textur()
	_tafel_basis_alpha = farbe.a
	var quad := QuadMesh.new()
	var basis := _basis_pixel_size if _basis_pixel_size > 0.0 else pixel_size
	var breite := float(text.length()) * float(font_size) * basis
	quad.size = Vector2(maxf(4.0, breite * 0.62) + 3.0, 3.4)
	_tafel = MeshInstance3D.new()
	_tafel.name = "SchildTafel"
	_tafel.mesh = quad
	_tafel.material_override = _tafel_material
	_tafel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tafel)


static func _karten_textur() -> GradientTexture2D:
	if _karten_tex == null:
		var verlauf := Gradient.new()
		verlauf.set_offset(0, 0.0)
		verlauf.set_color(0, Color(1, 1, 1, 1))
		verlauf.set_offset(1, 1.0)
		verlauf.set_color(1, Color(1, 1, 1, 0))
		verlauf.add_point(0.72, Color(1, 1, 1, 0.95))
		var tex := GradientTexture2D.new()
		tex.gradient = verlauf
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_SQUARE
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_karten_tex = tex
	return _karten_tex


func _process(_delta: float) -> void:
	var kamera := get_viewport().get_camera_3d()
	if kamera == null or not is_inside_tree():
		return
	var distanz := global_position.distance_to(kamera.global_position)
	var skala := skala_fuer_distanz(distanz)
	var alpha := alpha_fuer_distanz(distanz)
	pixel_size = _basis_pixel_size * skala
	modulate.a = _basis_alpha * alpha
	outline_modulate.a = alpha
	visible = alpha > 0.01
	if _tafel != null:
		# Tafel-Material billboardet selbst (keep_scale) — Node-Scale reicht.
		_tafel.scale = Vector3.ONE * skala
		_tafel_material.albedo_color.a = _tafel_basis_alpha * alpha
