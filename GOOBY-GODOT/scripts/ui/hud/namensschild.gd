class_name HudNamensschild
extends PanelContainer
## G8/IDEA-J2 — Namensschild: der Frost-Pill-Chip (AcTokens.FROST über die
## Theme-Variation `StatusCapsuleMini`), der im Querformat die Beschriftung
## der icon-only Cockpit-Kacheln übernimmt — als Parade beim ersten Layout,
## on-demand beim Langdruck und dauerhaft im Coachmark-Modus (dann bevorzugt
## mit der gepflegten `hud.<id>.kurz`-Kurzform statt blindem Ellipsis).
##
## Schilder sind REINE Anzeige: mouse_filter IGNORE (sie schlucken keine
## Taps, tauchen in keiner Tippflächen-Wache auf) und liegen in der Gruppe
## `hud_namensschilder`, damit Playtest-Flows sie ohne Baum-Wissen finden.

## Wunsch-Schriftgröße in Design-px (skaliert mit f, nie unter MIN_FONT_PX).
const FONT_PX := 12
const MIN_FONT_PX := 10
## Gruppe für Flows/Wachen (Sichtbarkeits-Sonden ohne Baumkenntnis).
const GRUPPE := &"hud_namensschilder"

var _label: Label


## Schild bauen (noch ohne Text — `beschrifte()` wählt Voll-/Kurzform).
static func bauen(schild_name: String, f: float) -> HudNamensschild:
	var schild := HudNamensschild.new()
	schild.name = schild_name
	schild.theme_type_variation = &"StatusCapsuleMini"
	schild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "SchildText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	# Font FEST setzen (Baloo-2 700 wie Buttons): Messung und Rendern nutzen
	# dieselbe Quelle, unabhängig davon, ob das Schild schon im Baum hängt.
	label.add_theme_font_override("font", ThemeService.font(700))
	label.add_theme_font_size_override("font_size", schild.wunsch_px(f))
	schild.add_child(label)
	schild._label = label
	return schild


## Gepflegte Kurzform `hud.<id>.kurz` (leer, wenn keine gepflegt ist).
static func kurz_text(id: StringName) -> String:
	var key := "hud.%s.kurz" % String(id)
	return I18nService.t(key) if I18nService.has_key(key) else ""


func _ready() -> void:
	add_to_group(GRUPPE)


## Text für die Kachel `id` wählen und setzen: voller Name, wenn er in
## `verfuegbar` px lesbar passt, sonst die Kurzform (J2: bewusste Kurzform
## statt abgeschnittener Wörter). `kurz_zuerst` = Coachmark-Dauerschilder
## (kompakt halten, damit die Karte daneben Platz behält).
func beschrifte(id: StringName, f: float, verfuegbar: float, kurz_zuerst: bool) -> void:
	var voll := I18nService.t("hud." + String(id))
	var kurz := kurz_text(id)
	if kurz_zuerst and kurz != "":
		voll = kurz
	var wahl := HudLabelFit.kurzform_wahl(
		_label.get_theme_font("font"), voll, kurz, wunsch_px(f), verfuegbar
	)
	_label.text = str(wahl["text"])
	_label.add_theme_font_size_override("font_size", int(wahl["px"]))
	reset_size()
	size = get_combined_minimum_size()


func text_anzeige() -> String:
	return _label.text


## Schild-Schriftgröße für Skala f (Design-px × f, Lesbarkeits-Boden).
func wunsch_px(f: float) -> int:
	return int(maxf(float(FONT_PX) * f, float(MIN_FONT_PX)))
