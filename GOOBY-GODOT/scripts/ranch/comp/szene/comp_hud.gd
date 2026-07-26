class_name RcompHud
extends Control
## Lauf-HUD der Wettbewerbe (RW-5): Zeit + Richter-Info oben links,
## Event-Callouts mittig, RW-2s Reit-Touch-HUD (Stick/Wische/Sprung) für
## die Reit-Disziplinen und der große "Jetzt!"-Knopf für die Schau-Kür.
## Einbau: hud.lauf = <RcompLauf> setzen, add_child (nach lauf.baue()).

const INK := Color("#3B3630")
const CREME := Color("#FFF6E8")
const GOLD := Color("#F2B04C")
const ROSA := Color("#E98CA0")
const TEAL := Color("#5FA8A0")

## Event-Typ → [String-Key, gut (bool)] für Callout + Sound.
const EVENT_TEXTE := {
	"perfekt": ["rcomp.lauf.perfekt", true],
	"hindernis_ok": ["", true],
	"abwurf": ["rcomp.lauf.abwurf", false],
	"verweigert": ["rcomp.lauf.verweigert", false],
	"tor_ok": ["rcomp.lauf.tor_ok", true],
	"tor_verpasst": ["rcomp.lauf.tor_verpasst", false],
	"beruehrung": ["rcomp.lauf.beruehrung", false],
	"aufgabe_ok": ["rcomp.lauf.aufgabe_ok", true],
	"aufgabe_ausgelassen": ["rcomp.lauf.aufgabe_ausgelassen", false],
	"tonne_ok": ["rcomp.lauf.tonne_ok", true],
	"tonne_um": ["rcomp.lauf.tonne_um", false],
	"runde": ["rcomp.lauf.runde", true],
	"windschatten": ["rcomp.lauf.windschatten", true],
	"figur_ok": ["rcomp.lauf.figur_ok", true],
	"gangart_ok": ["rcomp.lauf.gangart_ok", true],
	"gangart_wechsel": ["rcomp.lauf.wechsel_zu", true],
	"treffer": ["rcomp.lauf.treffer", true],
	"daneben": ["rcomp.lauf.daneben", false],
	"ziel": ["rcomp.lauf.ziel", true],
}

var lauf: RcompLauf

var _zeit_label: Label
var _info_label: Label
var _callout: Label
var _callout_t := 0.0
var _ride_hud: RanchRideHud
var _schau_label: Label
var _schau_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baue_kopf()
	_baue_callout()
	if lauf != null and lauf.controller != null:
		_ride_hud = RanchRideHud.new()
		_ride_hud.controller = lauf.controller
		add_child(_ride_hud)
	if lauf != null and lauf.disziplin == "schau":
		_baue_schau()
	if lauf != null:
		lauf.ereignis.connect(_auf_event)


func _process(delta: float) -> void:
	if lauf == null:
		return
	_zeit_label.text = I18nService.t("rcomp.hud.zeit", {"s": "%.1f" % lauf.zeit})
	_info_label.text = _info_text()
	if _callout_t > 0.0:
		_callout_t -= delta
		_callout.modulate.a = clampf(_callout_t / 0.35, 0.0, 1.0)
	_schau_puls()


## Freier Callout (Spiele nutzen ihn für Start-/Ziel-Momente).
func zeige_callout(text: String, farbe: Color = GOLD) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", farbe)
	_callout.modulate.a = 1.0
	_callout_t = 1.3


## ------------------------------------------------------------------ intern


func _info_text() -> String:
	var info := lauf.hud_info()
	if info.is_empty():
		return ""
	var params: Dictionary = {}
	var roh: Variant = info.get("params", {})
	if roh is Dictionary:
		params = (roh as Dictionary).duplicate()
	if params.has("name"):
		var prefix := (
			"rcomp.figur." if str(info.get("key")) == "rcomp.hud.figur" else "rcomp.aufgabe."
		)
		params["name"] = I18nService.t(prefix + str(params["name"]))
	if params.has("gangart"):
		params["gangart"] = I18nService.t("rpferd.gang.%s" % str(params["gangart"]))
	return I18nService.t(str(info.get("key", "")), params)


func _auf_event(event: Dictionary) -> void:
	var typ := str(event.get("typ", ""))
	if typ == "kommando":
		_zeige_kommando(str(event.get("id", "")))
		AudioDirector.try_play(self, "ui_open")
		return
	if not EVENT_TEXTE.has(typ):
		return
	var eintrag: Array = EVENT_TEXTE[typ]
	var gut := bool(eintrag[1])
	var key := str(eintrag[0])
	if lauf.disziplin == "schau" and (typ == "treffer" or typ == "daneben"):
		_schau_label.visible = false
	if key != "":
		var params := {
			"n": int(_num(event.get("nummer"), 0.0)),
			"punkte": int(_num(event.get("punkte"), 0.0)),
			"gangart": I18nService.t("rpferd.gang.%s" % str(event.get("gangart", "schritt"))),
		}
		zeige_callout(I18nService.t(key, params), GOLD if gut else ROSA)
	var laut := "mg_good" if gut else "mg_spill"
	if typ == "perfekt" or typ == "treffer" or typ == "ziel":
		laut = "mg_perfect"
	AudioDirector.try_play(self, laut)


func _baue_kopf() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-16.0, 12.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_zeit_label = Label.new()
	_zeit_label.theme_type_variation = &"HeadlineLabel"
	_zeit_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_zeit_label)
	_info_label = Label.new()
	_info_label.theme_type_variation = &"CaptionLabel"
	_info_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_info_label)


func _baue_callout() -> void:
	_callout = Label.new()
	_callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_callout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.add_theme_font_size_override("font_size", 40)
	_callout.add_theme_color_override("font_outline_color", INK)
	_callout.add_theme_constant_override("outline_size", 8)
	_callout.position.y -= 110.0
	_callout.modulate.a = 0.0
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_callout)


func _baue_schau() -> void:
	_schau_label = Label.new()
	_schau_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_schau_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_schau_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_schau_label.position.y += 90.0
	_schau_label.add_theme_font_size_override("font_size", 46)
	_schau_label.add_theme_color_override("font_color", CREME)
	_schau_label.add_theme_color_override("font_outline_color", INK)
	_schau_label.add_theme_constant_override("outline_size", 10)
	_schau_label.pivot_offset = Vector2.ZERO
	_schau_label.visible = false
	_schau_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_schau_label)
	_schau_btn = Button.new()
	_schau_btn.text = I18nService.t("rcomp.lauf.jetzt")
	_schau_btn.custom_minimum_size = Vector2(190, 84)
	_schau_btn.add_theme_font_size_override("font_size", 26)
	_schau_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_schau_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_schau_btn.position.y -= 130.0
	_schau_btn.pivot_offset = Vector2(95.0, 42.0)
	_schau_btn.pressed.connect(_schau_tipp)
	add_child(_schau_btn)


func _zeige_kommando(id: String) -> void:
	if _schau_label == null:
		return
	_schau_label.text = I18nService.t("rcomp.kommando.%s" % id)
	_schau_label.visible = true


func _schau_tipp() -> void:
	if lauf == null:
		return
	var wertung := lauf.tippe()
	if str(wertung.get("typ", "")) == "zu_frueh":
		zeige_callout(I18nService.t("rcomp.lauf.zu_frueh"), TEAL)


## Sprung-Puls des Schau-Knopfs, wenn der Idealmoment naht.
func _schau_puls() -> void:
	if _schau_btn == null or lauf == null or lauf.richter == null:
		return
	var countdown := (lauf.richter as RcompRichterSchau).countdown_s()
	if countdown > 0.0 and countdown < 1.0:
		_schau_btn.scale = Vector2.ONE * (1.0 + 0.14 * (1.0 - countdown))
	else:
		_schau_btn.scale = Vector2.ONE


func _unhandled_key_input(event: InputEvent) -> void:
	if lauf == null or lauf.disziplin != "schau" or not lauf.laeuft:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_SPACE:
		_schau_tipp()


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
