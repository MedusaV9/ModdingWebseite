class_name McGoobyBuehne
extends Control
## Die McGooby-Bühne (G6/MCGOOBY-B, Doc §1 „Mitarbeiter-Gags“/§2.4): eine
## kleine Bühne im Laden — auf Knopfdruck betritt das Maskottchen (der
## goldene Löffel-Bögen-Kopf mit Ohren) die Bühne: Pop-in + Wackler +
## Konfetti-Regen, Fanfare (ranch_fanfare) und Kunden-Jubel
## (ranch_menge_jubel). EINMAL pro Schicht aktivierbar; die Schicht friert
## währenddessen ein (die Szene gated ihr _process über laeuft()).
##
## Kein Asset nötig: das Maskottchen ist komplett code-gezeichnet
## (StyleBoxFlat-Kreis + Ohren-Paneele), Muster AcWallpaper/Kulissen.
## Reduced Motion: keine Tweens/Konfetti, nur der Sound-Moment mit kurzer
## fester Dauer (eigene Delays selbst genullt — Projekt-Gotcha).

signal auftritt_fertig

## Farbwelt des Maskottchens (Parodie: goldene Bögen = Löffel mit Ohren).
const FARBE_GOLD := Color("#F2C14E")
const FARBE_GOLD_DUNKEL := Color("#C88F2E")
const FARBE_GESICHT := Color("#6B4A2B")
const KONFETTI_FARBEN: Array[Color] = [
	Color("#F2C14E"), Color("#E05F8D"), Color("#3FA89A"), Color("#6DB54E"), Color("#FFF3DC")
]

## Design-Größen (px, skalieren mit f in apply_metrics).
const KOPF_BASIS := 172.0
const OHR_BASIS := Vector2(34.0, 62.0)
const AUGE_BASIS := Vector2(14.0, 24.0)
const KONFETTI_BASIS := Vector2(10.0, 16.0)
const KONFETTI_ANZAHL := 10

## Tests raffen die Show (Dauer-Multiplikator, Muster GoobyeGrossmarktScene).
var tempo := 1.0

var _aufgetreten := false
var _laeuft := false
var _f := 1.0

var _dim: ColorRect
var _gruppe: VBoxContainer
var _kopf: PanelContainer
var _ohren: Array[PanelContainer] = []
var _augen: Array[ColorRect] = []
var _mund: Label
var _titel: Label
var _jubel: Label


func _ready() -> void:
	name = "BuehneOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.name = "BuehneDim"
	_dim.color = Color(0.24, 0.16, 0.12, 0.45)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var zentrum := CenterContainer.new()
	zentrum.name = "BuehneZentrum"
	zentrum.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zentrum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zentrum)
	_gruppe = VBoxContainer.new()
	_gruppe.name = "Maskottchen"
	_gruppe.add_theme_constant_override("separation", 10)
	_gruppe.alignment = BoxContainer.ALIGNMENT_CENTER
	zentrum.add_child(_gruppe)
	_baue_maskottchen()
	_titel = _zeile("BuehneTitel", &"TitleLabel", "dlc_mcgooby.buehne.auftritt")
	_jubel = _zeile("BuehneJubel", &"HeadlineLabel", "dlc_mcgooby.buehne.jubel")
	_jubel.modulate.a = 0.0


## ---------------------------------------------------------------- Ablauf


## Auftritt starten (1×/Schicht; die Szene bucht Save + Trinkgeld selbst).
func starte_auftritt() -> void:
	if _laeuft or _aufgetreten:
		return
	_aufgetreten = true
	_laeuft = true
	visible = true
	_jubel.modulate.a = 0.0
	AudioDirector.try_play(self, "ranch_fanfare")
	UiMotion.pop_in(_gruppe)
	_konfetti_regnen()
	# Eigene Zeitleiste, reduced-motion-gerecht selbst verkürzt (Delays
	# nullen sich nicht von allein — Projekt-Gotcha der Stagger-Muster).
	var takt := 0.12 if UiMotion.reduced(self) else 1.0
	var zeit := create_tween()
	zeit.tween_interval(maxf(0.05, 0.9 * tempo * takt))
	zeit.tween_callback(_jubel_moment)
	zeit.tween_interval(maxf(0.05, 1.3 * tempo * takt))
	zeit.tween_callback(_fertig)


func laeuft() -> bool:
	return _laeuft


func schon_aufgetreten() -> bool:
	return _aufgetreten


## Neue Schicht = neue Show erlaubt.
func reset() -> void:
	_aufgetreten = false
	_laeuft = false
	visible = false


func apply_metrics(m: Dictionary) -> void:
	_f = float(m.get("f", 1.0))
	_kopf.custom_minimum_size = Vector2.ONE * KOPF_BASIS * _f
	for ohr in _ohren:
		ohr.custom_minimum_size = OHR_BASIS * _f
	for auge in _augen:
		auge.custom_minimum_size = AUGE_BASIS * _f


## ---------------------------------------------------------------- Aufbau


func _baue_maskottchen() -> void:
	var ohren_zeile := HBoxContainer.new()
	ohren_zeile.name = "Ohren"
	ohren_zeile.add_theme_constant_override("separation", 46)
	ohren_zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	_gruppe.add_child(ohren_zeile)
	for seite in ["L", "R"]:
		var ohr := PanelContainer.new()
		ohr.name = "Ohr" + seite
		ohr.custom_minimum_size = OHR_BASIS
		var ohr_stil := StyleBoxFlat.new()
		ohr_stil.bg_color = FARBE_GOLD_DUNKEL
		ohr_stil.set_corner_radius_all(17)
		ohr.add_theme_stylebox_override("panel", ohr_stil)
		ohren_zeile.add_child(ohr)
		_ohren.append(ohr)
	_kopf = PanelContainer.new()
	_kopf.name = "Kopf"
	_kopf.custom_minimum_size = Vector2.ONE * KOPF_BASIS
	_kopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var kopf_stil := StyleBoxFlat.new()
	kopf_stil.bg_color = FARBE_GOLD
	kopf_stil.set_corner_radius_all(int(KOPF_BASIS))
	_kopf.add_theme_stylebox_override("panel", kopf_stil)
	_gruppe.add_child(_kopf)
	var gesicht := VBoxContainer.new()
	gesicht.add_theme_constant_override("separation", 8)
	gesicht.alignment = BoxContainer.ALIGNMENT_CENTER
	_kopf.add_child(gesicht)
	var augen_zeile := HBoxContainer.new()
	augen_zeile.add_theme_constant_override("separation", 30)
	augen_zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	gesicht.add_child(augen_zeile)
	for _i in 2:
		var auge := ColorRect.new()
		auge.color = FARBE_GESICHT
		auge.custom_minimum_size = AUGE_BASIS
		auge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		augen_zeile.add_child(auge)
		_augen.append(auge)
	_mund = Label.new()
	_mund.text = "‿‿"
	_mund.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mund.add_theme_color_override("font_color", FARBE_GESICHT)
	gesicht.add_child(_mund)


func _zeile(zeilen_name: String, variation: StringName, key: String) -> Label:
	var label := Label.new()
	label.name = zeilen_name
	label.theme_type_variation = variation
	label.text = I18nService.t(key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gruppe.add_child(label)
	return label


## ---------------------------------------------------------------- Show


func _jubel_moment() -> void:
	AudioDirector.try_play(self, "ranch_menge_jubel")
	_jubel.modulate.a = 1.0
	UiMotion.bounce(_jubel)
	UiMotion.wiggle(_kopf, 8.0)


func _fertig() -> void:
	_laeuft = false
	visible = false
	auftritt_fertig.emit()


## Konfetti-Regen: deterministische Bahnen (i-basiert, kein RNG nötig),
## fällt von oben durchs Bild und räumt sich selbst weg. Reduced Motion:
## gar kein Konfetti (Bewegungs-Effekt pur).
func _konfetti_regnen() -> void:
	if UiMotion.reduced(self) or not is_inside_tree():
		return
	var breite := size.x
	var hoehe := size.y
	for i in KONFETTI_ANZAHL:
		var schnipsel := ColorRect.new()
		schnipsel.color = KONFETTI_FARBEN[i % KONFETTI_FARBEN.size()]
		schnipsel.custom_minimum_size = KONFETTI_BASIS * _f
		schnipsel.size = KONFETTI_BASIS * _f
		schnipsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := breite * (0.5 + (float(i) - float(KONFETTI_ANZAHL - 1) / 2.0) * 0.07)
		schnipsel.position = Vector2(x, -40.0 * _f - float(i % 3) * 30.0 * _f)
		schnipsel.rotation_degrees = float(i * 36 % 90) - 45.0
		add_child(schnipsel)
		var fall := schnipsel.create_tween().set_parallel()
		var dauer := maxf(0.1, (1.4 + float(i % 4) * 0.2) * tempo)
		fall.tween_property(schnipsel, "position:y", hoehe + 40.0 * _f, dauer)
		fall.tween_property(
			schnipsel, "rotation_degrees", schnipsel.rotation_degrees + 180.0, dauer
		)
		fall.chain().tween_callback(schnipsel.queue_free)
