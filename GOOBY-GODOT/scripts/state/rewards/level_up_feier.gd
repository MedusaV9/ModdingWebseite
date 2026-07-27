class_name LevelUpFeier
extends Control
## Level-Up-Feier im Hauptspiel (EF-1, EVAL-1 D8): kurzer Vollbild-Moment
## nach dem Results-Count-Up — Gold-Titel „Level {level}!“, Münz-Bonus-Zeile,
## `ui_levelup`-Stinger und Konfetti-Regen. Muster übernommen von der
## fertigen Ranch-Feier (`scripts/ranch/gameplay/levelup_feier.gd`), aber
## eigenständig, weil die Ranch-Klasse Pferde-Strings + Meilensteine trägt.
## Reduced Motion: Konfetti fällt weg, Text + Ton bleiben. Räumt sich nach
## DAUER_S selbst auf. Kein Screenshake (globaler Wohlfühl-Grundsatz).

const DAUER_S := 2.6
const GOLD := Color("#F2B04C")
const CREME := Color("#FFF6E8")
const INK := Color("#3B3630")
const KONFETTI_TEILE := 110

var level := 2
var bonus_coins := 0

var _alter_s := 0.0


## Fabrik: Feier bauen, einhängen und Ton anstoßen.
static func zeige_in(parent: Node, neues_level: int, coins := 0) -> LevelUpFeier:
	var feier := LevelUpFeier.new()
	feier.name = "LevelUpFeier"
	feier.level = neues_level
	feier.bonus_coins = coins
	parent.add_child(feier)
	return feier


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 95
	_baue_texte()
	var breite := size.x if size.x > 0.0 else 960.0
	RewardFx.konfetti_2d(self, KONFETTI_TEILE, breite)
	AudioDirector.try_play(self, "ui_levelup")
	if bonus_coins > 0:
		AudioDirector.try_play(self, "ui_coins", 1.08)


func _process(delta: float) -> void:
	_alter_s += delta
	if _alter_s >= DAUER_S:
		queue_free()
		return
	# Weiches Ein- und Ausblenden ohne Tween-Abhängigkeit (Ranch-Muster).
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
	titel.text = I18nService.t("rewards.levelup.titel", {"level": level})
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 52)
	titel.add_theme_color_override("font_color", GOLD)
	titel.add_theme_color_override("font_outline_color", INK)
	titel.add_theme_constant_override("outline_size", 10)
	box.add_child(titel)
	var unter := Label.new()
	if bonus_coins > 0:
		unter.text = I18nService.t("rewards.levelup.untertitel", {"coins": bonus_coins})
	else:
		unter.text = I18nService.t("rewards.levelup.weiter")
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unter.add_theme_font_size_override("font_size", 22)
	unter.add_theme_color_override("font_color", CREME)
	unter.add_theme_color_override("font_outline_color", INK)
	unter.add_theme_constant_override("outline_size", 6)
	box.add_child(unter)
