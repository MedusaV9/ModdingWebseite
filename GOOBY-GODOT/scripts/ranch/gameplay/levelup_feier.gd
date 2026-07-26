class_name RanchLevelUpFeier
extends Control
## Level-Up-Moment eines Pferds (RW-2, IDEAS-3 Kap. 2.5): kurzer Feier-
## Overlay im JuiceKit-Stil — Konfetti, Gold-Titel, `ui_levelup`-Ton,
## optional die Meilenstein-Geschenk-Zeile (rpferd.meilenstein.*).
## Kein Screenshake (Reit-Grundsatz); Reduced Motion laesst das Konfetti
## weg, Text + Ton bleiben. Raeumt sich nach ~2,6 s selbst auf.
##
## Aufruf (RANCH-1/HUD, nach RanchHorseLevels.xp_buchen):
##   RanchLevelUpFeier.zeige_in(overlay, "Luna", 5, ergebnis["meilensteine"])

const DAUER_S := 2.6
const GOLD := Color("#F2B04C")
const CREME := Color("#FFF6E8")
const INK := Color("#3B3630")

var pferd_name := ""
var level := 2
var meilensteine: Array = []

var _alter_s := 0.0


## Fabrik: Feier bauen, einhaengen und Ton anstossen.
static func zeige_in(
	parent: Node, name_str: String, neues_level: int, geschenke: Array = []
) -> RanchLevelUpFeier:
	var feier := RanchLevelUpFeier.new()
	feier.pferd_name = name_str
	feier.level = neues_level
	feier.meilensteine = geschenke.duplicate()
	parent.add_child(feier)
	return feier


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	_baue_texte()
	if not _reduced_motion():
		_baue_konfetti()
	AudioDirector.try_play(self, "ui_levelup")
	if not meilensteine.is_empty():
		AudioDirector.try_play(self, "mg_golden", 1.05)


func _process(delta: float) -> void:
	_alter_s += delta
	if _alter_s >= DAUER_S:
		queue_free()
		return
	# Weiches Aus- und Einblenden ohne Tween-Abhaengigkeit.
	var rest := DAUER_S - _alter_s
	modulate.a = clampf(minf(_alter_s / 0.25, rest / 0.5), 0.0, 1.0)


func _baue_texte() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var titel := Label.new()
	titel.text = I18nService.t("rpferd.levelup.titel", {"level": level})
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 52)
	titel.add_theme_color_override("font_color", GOLD)
	titel.add_theme_color_override("font_outline_color", INK)
	titel.add_theme_constant_override("outline_size", 10)
	box.add_child(titel)
	var unter := Label.new()
	unter.text = I18nService.t("rpferd.levelup.untertitel", {"name": pferd_name})
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unter.add_theme_font_size_override("font_size", 22)
	unter.add_theme_color_override("font_color", CREME)
	unter.add_theme_color_override("font_outline_color", INK)
	unter.add_theme_constant_override("outline_size", 6)
	box.add_child(unter)
	for geschenk: Variant in meilensteine:
		var key := "rpferd.meilenstein.%s" % geschenk
		if not I18nService.has_key(key):
			continue
		var zeile := Label.new()
		zeile.text = "%s %s" % [I18nService.t("rpferd.meilenstein.titel"), I18nService.t(key)]
		zeile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zeile.add_theme_font_size_override("font_size", 19)
		zeile.add_theme_color_override("font_color", GOLD.lightened(0.2))
		zeile.add_theme_color_override("font_outline_color", INK)
		zeile.add_theme_constant_override("outline_size", 5)
		box.add_child(zeile)


func _baue_konfetti() -> void:
	var particles := CPUParticles2D.new()
	particles.position = Vector2(size.x * 0.5, -12.0) if size.x > 0.0 else Vector2(480.0, -12.0)
	particles.one_shot = true
	particles.emitting = true
	particles.amount = 80
	particles.lifetime = 1.8
	particles.explosiveness = 0.85
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(maxf(size.x * 0.4, 120.0), 6.0)
	particles.direction = Vector2.DOWN
	particles.spread = 28.0
	particles.gravity = Vector2(0.0, 380.0)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 190.0
	particles.angular_velocity_min = -240.0
	particles.angular_velocity_max = 240.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	particles.hue_variation_min = -0.5
	particles.hue_variation_max = 0.5
	particles.color = GOLD
	add_child(particles)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
