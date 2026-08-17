class_name ZeitChip
extends PanelContainer
## W21/P4 (b) — Zeit-Chip der Host-Top-Bar: DIE einheitliche Rundenzeit
## des Rahmens (Timer-im-Spiel-Befund). Quelle ist die FRAMEWORK-Zeit des
## GeistRekord — sie läuft nur, solange das Spiel wirklich tickt (Pause/
## Strike-Freeze stehen, Zeitlupen dehnen wie im Spiel; Zeit bleibt
## injiziert/testbar). Frost-Kapsel + selbst gezeichnete Uhr (kein
## Emoji-Font-Risiko) + „M:SS“. Bewusst statisch (kein Puls) — Reduced-
## Motion-fair per Konstruktion. Spiele-eigene Timer-HUDs bleiben
## unangetastet (P5-Thema); der Host-Chip etabliert den Standard.

## Icon-Grundmaß in Design-px (= AcTokens.ICON_S — Inline-Glyphe im Chip;
## skaliert über skaliere(f) mit der Top-Bar).
const ICON_PX := 16.0

var _icon: UhrIcon
var _label: Label
## Wächter gegen Label-Neuaufbau pro Frame (Host tickt im _process-Takt).
var _letzte_sekunde := -1


func _init() -> void:
	name = "ZeitChip"
	theme_type_variation = &"StatusCapsuleMini"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var zeile := HBoxContainer.new()
	zeile.name = "Zeile"
	zeile.add_theme_constant_override("separation", AcTokens.SPACE_XS)
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zeile)
	_icon = UhrIcon.new()
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(_icon)
	_label = Label.new()
	_label.name = "ZeitLabel"
	_label.theme_type_variation = &"CaptionLabel"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(_label)
	zeige_zeit(0.0)


## „M:SS“ aus Sekunden (pur, testbar) — Negatives klemmt auf 0:00.
static func format_zeit(sekunden: float) -> String:
	var ganz := maxi(int(floorf(sekunden)), 0)
	return "%d:%02d" % [int(ganz / 60.0), ganz % 60]


## Rundenzeit anzeigen (idempotent — gleiche Sekunde kostet nichts).
func zeige_zeit(sekunden: float) -> void:
	var ganz := maxi(int(floorf(sekunden)), 0)
	if ganz == _letzte_sekunde:
		return
	_letzte_sekunde = ganz
	_label.text = format_zeit(sekunden)


## Rundenwechsel: zurück auf 0:00 (Host ruft das im Neustart-Pfad).
func setze_zurueck() -> void:
	_letzte_sekunde = -1
	zeige_zeit(0.0)


## Mit der ZENTRALEN UiScale-Regel skalieren (Host-_apply_metrics; die
## Label-Schrift skaliert ScreenShell.scale_fonts).
func skaliere(f: float) -> void:
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX) * maxf(f, 1.0)


## Kleine Uhr (Ring + zwei Zeiger), zeichnet sich selbst — Muster
## GeistChip.GeistIcon (kein Emoji-/Font-Glyph-Risiko auf iOS).
class UhrIcon:
	extends Control

	## Uhren-Ton (warmes Ink-Braun — Kopie, innere Klassen sehen den
	## äußeren Scope nicht; lesbar auf der Frost-Kapsel).
	var farbe := Color(0.2902, 0.2314, 0.2118, 0.85)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		var mitte := Vector2(w, h) * 0.5
		var r := minf(w, h) * 0.46
		draw_arc(mitte, r, 0.0, TAU, 24, farbe, maxf(1.4, r * 0.22))
		draw_line(mitte, mitte + Vector2(0.0, -r * 0.62), farbe, maxf(1.2, r * 0.18))
		draw_line(mitte, mitte + Vector2(r * 0.45, 0.0), farbe, maxf(1.2, r * 0.18))
