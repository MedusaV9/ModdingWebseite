class_name McGoobyRangFeier
extends Control
## Rang-Aufstiegs-Moment des McGooby-Ladens (W20 Top-10 #1, Doc §6.1):
## kurzer Feier-Beat, wenn der Laden-Rang am Schicht-Ende steigt — Gold-
## Titel, großes Sterne-Band, `ui_levelup`-Stinger, Erfolgs-Haptik und
## Konfetti-Regen. Muster übernommen von `LevelUpFeier`
## (scripts/state/rewards/level_up_feier.gd), aber eigenständig, weil hier
## Laden-Strings + Sterne-Band statt Level-Zahl leben.
##
## Layer-Kontext (CanvasLayer-Falle, W18-Lehre): die Schicht-Szene ist ein
## plain Control unter dem SceneRouter — Raum-/Home-HUD-Layer (5/10/…/90)
## sind während der Schicht nicht montiert. Der Beat hängt deshalb als
## LETZTES Szenen-Kind mit z_index 95 ÜBER der Ende-Karte; mouse_filter
## IGNORE lässt „Noch eine Schicht“/„Feierabend“ tappbar.
##
## Reduced Motion: Konfetti fällt weg (RewardFx-Gate), Text + Ton bleiben.
## Räumt sich nach DAUER_S selbst auf. Kein Screenshake (Wohlfühl-Grundsatz).

const DAUER_S := 2.6
const GOLD := Color("#F2B04C")
const CREME := Color("#FFF6E8")
const INK := Color("#3B3630")
const KONFETTI_TEILE := 90

var stern := 1

var _alter_s := 0.0


## Fabrik: Feier bauen, als letztes Kind einhängen, Ton + Haptik anstoßen.
static func zeige_in(parent: Node, neuer_stern: int) -> McGoobyRangFeier:
	var feier := McGoobyRangFeier.new()
	feier.name = "RangFeier"
	feier.stern = neuer_stern
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
	Haptics.success(self)


func _process(delta: float) -> void:
	_alter_s += delta
	if _alter_s >= DAUER_S:
		queue_free()
		return
	# Weiches Ein- und Ausblenden ohne Tween-Abhängigkeit (Ranch-Muster).
	var rest := DAUER_S - _alter_s
	modulate.a = clampf(minf(_alter_s / 0.25, rest / 0.5), 0.0, 1.0)


func _baue_texte() -> void:
	# Milchglas-Plate hinter dem Text (Banner-Muster, W19-Liefer-Hetze-
	# Lehre): der Beat liegt ÜBER der textreichen Ende-Karte — ohne Plate
	# kollidieren Gold-Titel und Kassenzeilen zu unlesbarem Text-auf-Text.
	var plate := PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stil := StyleBoxFlat.new()
	# Fast deckend (Toast-Grammatik): bei halbtransparenter Plate blutete
	# die Kassen-Typo der Ende-Karte weiter durch (Playtest-Befund W20).
	stil.bg_color = Color(INK, 0.94)
	stil.set_corner_radius_all(22)
	stil.content_margin_left = 30.0
	stil.content_margin_right = 30.0
	stil.content_margin_top = 16.0
	stil.content_margin_bottom = 18.0
	plate.add_theme_stylebox_override("panel", stil)
	add_child(plate)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(box)
	var titel := Label.new()
	titel.text = I18nService.t("dlc_mcgooby.fortschritt.aufstieg_titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 46)
	titel.add_theme_color_override("font_color", GOLD)
	titel.add_theme_color_override("font_outline_color", INK)
	titel.add_theme_constant_override("outline_size", 10)
	box.add_child(titel)
	var band := Label.new()
	band.name = "SterneBand"
	band.text = McGoobyFortschritt.sterne_band(stern)
	band.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_theme_font_size_override("font_size", 40)
	band.add_theme_color_override("font_color", GOLD)
	band.add_theme_color_override("font_outline_color", INK)
	band.add_theme_constant_override("outline_size", 8)
	box.add_child(band)
	var unter := Label.new()
	unter.text = I18nService.t("dlc_mcgooby.fortschritt.aufstieg_unter", {"n": stern})
	unter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unter.add_theme_font_size_override("font_size", 22)
	unter.add_theme_color_override("font_color", CREME)
	unter.add_theme_color_override("font_outline_color", INK)
	unter.add_theme_constant_override("outline_size", 6)
	box.add_child(unter)
