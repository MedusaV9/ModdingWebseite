class_name LoadingVeilKarte
extends PanelContainer
## W16/VEIL — Look der Veil-Karte im Stil der alten Web-Version (POLISH-D
## `.mg-loading-themed .mg-loading-card`, GOOBY/src/ui/styles.css
## Z. 5045-5178 + loadingVeil.js buildCard): 320 Design-px breite
## Papier-Karte (Radius 28, Hairline-Ring + Pop-Schatten), oben die
## Cover-Zone (152 px, Bild cover-gefittet, Lese-Shade, weiße Ready-Zeile,
## überlappender Motiv-Sticker), unten Titel + Teal-Verlaufsbalken +
## „Lädt…“-Zeile + Tipp.
##
## Diese Klasse baut NUR die Optik (StyleBoxen, Verläufe, Fonts, Maße —
## skaliert über die zentrale UiScale-Regel, FIX1); Verhalten/Varianten
## bleiben in loading_veil.gd. Die FROZEN Unique-Names (%Card %Cover
## %Title %Gooby %Laedt %Tip %Progress) liegen weiter in loading_veil.tscn.

## Web-Referenzmaße in Design-px (styles.css, 1rem = 16 px).
const BREITE := 320.0
const COVER_HOEHE := 152.0
const RADIUS := 28.0  # --card-radius-lg (1.75rem)
const BALKEN_HOEHE := 10.0
const BALKEN_ABSTAND_EXTRA := 2.0  # Balken-margin-top 10 − VBox-Abstand 8
const ZEILEN_ABSTAND := 8.0
const PAD_OBEN := 16.0
const PAD_SEITE := 20.0
const PAD_UNTEN := 18.0
const READY_LINKS := 16.0
const READY_UNTEN := 10.0
const STICKER_GROESSE := 72.0
const STICKER_RECHTS := 14.0
const STICKER_UEBERLAPP := 12.0
## Web-Schriftgrößen (px): Titel 1.125rem/700, Ready+Lädt 0.8125rem/700,
## Tipp 0.75rem/600 mit line-height 1.35.
const TITEL_PX := 18
const READY_PX := 13
const LAEDT_PX := 13
const TIPP_PX := 12
## Home/Trip-Fallback-Verlauf unterm Cover (loadingVeil.js Z. 666).
const FALLBACK_FARBEN: Array[Color] = [Color("#FFF6EC"), Color("#FFE9C7"), Color("#E8C896")]

var _f := 1.0
var _fs := 1.0

@onready var _clip: PanelContainer = $Clip
@onready var _cover_zone: Control = $Clip/CardBox/CoverZone
@onready var _fallback: TextureRect = $Clip/CardBox/CoverZone/Fallback
@onready var _shade: TextureRect = $Clip/CardBox/CoverZone/Shade
@onready var _ready_label: Label = %Ready
@onready var _sticker: Control = %Gooby
@onready var _body: MarginContainer = $Clip/CardBox/Body
@onready var _body_box: VBoxContainer = $Clip/CardBox/Body/BodyBox
@onready var _bar_zone: Control = $Clip/CardBox/Body/BodyBox/BarZone
@onready var _sweep: Control = %Sweep
@onready var _progress: ProgressBar = %Progress
@onready var _title: Label = %Title
@onready var _laedt: Label = %Laedt
@onready var _tip: Label = %Tip


func _ready() -> void:
	_f = UiScale.for_viewport(get_viewport())
	_fs = UiScale.font_scale(get_viewport())
	_stil_karte()
	_stil_cover()
	_stil_body()


## Skalierungsfaktor der Karte (FIX1) — fürs Pop-in-translateY des Veils.
func design_faktor() -> float:
	return _f


## G6/DLC-LOAD: Farbstimmung des Cover-Fallback-Verlaufs datengetrieben
## tauschen (DLC-Karten) — leer/zu kurz = zurück auf den Web-Standard.
## Nur der Verlauf wechselt; Radius, Ring, Schatten, Maße bleiben FROZEN.
func setze_fallback_farben(farben: Array[Color]) -> void:
	if _fallback == null:
		return
	var stops := farben if farben.size() >= 3 else FALLBACK_FARBEN
	_fallback.texture = _verlauf_textur(stops)


## Kartenkörper: Papier, Radius 28, Hairline-Ring (0 0 0 1px outline-soft)
## + Pop-Schatten (0 10px 30px rgba(74,59,54,.18)); der innere Clip-Panel
## schneidet Cover + Sticker an den runden Ecken ab (overflow: hidden).
func _stil_karte() -> void:
	var karte := StyleBoxFlat.new()
	karte.bg_color = AcTokens.PAPER
	karte.set_corner_radius_all(int(round(RADIUS * _f)))
	karte.set_border_width_all(maxi(1, int(round(_f))))
	karte.border_color = AcTokens.OUTLINE_SOFT
	karte.shadow_color = AcTokens.SHADOW_COLOR
	karte.shadow_size = int(round(15.0 * _f))
	karte.shadow_offset = Vector2(0.0, 10.0 * _f)
	add_theme_stylebox_override("panel", karte)
	var clip := StyleBoxFlat.new()
	clip.bg_color = AcTokens.PAPER
	clip.set_corner_radius_all(int(round((RADIUS - 1.0) * _f)))
	_clip.add_theme_stylebox_override("panel", clip)
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW


func _stil_cover() -> void:
	_cover_zone.custom_minimum_size = Vector2(BREITE, COVER_HOEHE) * _f
	_fallback.texture = _fallback_textur()
	_shade.texture = _shade_textur()
	_stil_ready()
	_stil_sticker()


## Ready-Zeile unten links: Weiß, 13 px/700, Textschatten (Web Z. 5088-96).
func _stil_ready() -> void:
	_label_stil(_ready_label, READY_PX, 700, AcTokens.WHITE)
	_ready_label.add_theme_color_override("font_shadow_color", Color(AcTokens.INK, 0.6))
	_ready_label.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(_f))))
	_ready_label.add_theme_constant_override("shadow_offset_x", 0)
	_ready_label.add_theme_constant_override("shadow_outline_size", int(round(4.0 * _f)))
	_ready_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ready_label.offset_left = READY_LINKS * _f
	_ready_label.offset_right = -READY_LINKS * _f
	_ready_label.offset_bottom = -READY_UNTEN * _f
	_ready_label.offset_top = -(READY_UNTEN + READY_PX * 1.6) * _f
	_ready_label.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Motiv-Sticker rechts unten, überlappt die Cover-Unterkante (Web:
## right 0.875rem, bottom -0.75rem, 4.5rem rund).
func _stil_sticker() -> void:
	_sticker.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_sticker.offset_right = -STICKER_RECHTS * _f
	_sticker.offset_left = -(STICKER_RECHTS + STICKER_GROESSE) * _f
	_sticker.offset_bottom = STICKER_UEBERLAPP * _f
	_sticker.offset_top = (STICKER_UEBERLAPP - STICKER_GROESSE) * _f


func _stil_body() -> void:
	_body.add_theme_constant_override("margin_top", int(round(PAD_OBEN * _f)))
	_body.add_theme_constant_override("margin_left", int(round(PAD_SEITE * _f)))
	_body.add_theme_constant_override("margin_right", int(round(PAD_SEITE * _f)))
	_body.add_theme_constant_override("margin_bottom", int(round(PAD_UNTEN * _f)))
	_body_box.add_theme_constant_override("separation", int(round(ZEILEN_ABSTAND * _f)))
	_label_stil(_title, TITEL_PX, 700, AcTokens.INK)
	_label_stil(_laedt, LAEDT_PX, 700, AcTokens.INK_SOFT)
	_label_stil(_tip, TIPP_PX, 600, AcTokens.INK_SOFT)
	# Web line-height 1.35 → Zusatzabstand über die Fontgröße.
	_tip.add_theme_constant_override("line_spacing", int(round(TIPP_PX * 0.35 * _fs)))
	_bar_zone.custom_minimum_size = Vector2(0.0, (BALKEN_HOEHE + BALKEN_ABSTAND_EXTRA) * _f)
	for balken: Control in [_sweep, _progress]:
		balken.set_anchors_preset(Control.PRESET_FULL_RECT)
		balken.offset_top = BALKEN_ABSTAND_EXTRA * _f


func _label_stil(label: Label, groesse: int, gewicht: int, farbe: Color) -> void:
	label.add_theme_font_override("font", _font(gewicht))
	label.add_theme_font_size_override("font_size", int(round(groesse * _fs)))
	label.add_theme_color_override("font_color", farbe)


static func _font(gewicht: int) -> FontVariation:
	var variante := FontVariation.new()
	variante.base_font = load(AcTokens.FONT_PATH)
	variante.variation_opentype = {"wght": gewicht}
	return variante


## Akzent-Verlauf unterm Cover-Bild (Fallback, wenn kein Bild lädt):
## linear-gradient(155deg, #fff6ec 0%, #ffe9c7 58%, #e8c896 100%).
static func _fallback_textur() -> GradientTexture2D:
	return _verlauf_textur(FALLBACK_FARBEN)


## Der 155°-Web-Verlauf mit austauschbaren Stops (Farbstimmung der
## DLC-Karten, G6/DLC-LOAD) — Winkel/Offsets bleiben die Web-Werte.
static func _verlauf_textur(farben: Array[Color]) -> GradientTexture2D:
	var verlauf := Gradient.new()
	verlauf.colors = PackedColorArray(farben)
	verlauf.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	var textur := GradientTexture2D.new()
	textur.gradient = verlauf
	# CSS 155° ≈ Richtungsvektor (0.42, 0.91) durch die Bildmitte.
	textur.fill_from = Vector2(0.29, 0.05)
	textur.fill_to = Vector2(0.71, 0.95)
	return textur


## Lese-Shade überm Cover: rgba(74,59,54,0) ab 40 % → rgba(74,59,54,.55).
static func _shade_textur() -> GradientTexture2D:
	var verlauf := Gradient.new()
	verlauf.colors = PackedColorArray(
		[Color(AcTokens.INK, 0.0), Color(AcTokens.INK, 0.0), Color(AcTokens.INK, 0.55)]
	)
	verlauf.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var textur := GradientTexture2D.new()
	textur.gradient = verlauf
	textur.fill_from = Vector2(0.5, 0.0)
	textur.fill_to = Vector2(0.5, 1.0)
	return textur
