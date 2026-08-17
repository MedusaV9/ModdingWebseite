class_name GeistChip
extends HBoxContainer
## W19/GEIST — dezenter „Geist“-Chip in der Host-Top-Bar: kleines
## Gespenst-Icon (selbst gezeichnet, kein Emoji-Font-Risiko) + Live-Delta
## („+12“ / „−5“) zum gespeicherten Bestlauf. Bewusst statisch (kein Puls,
## keine Tweens) — damit ist der Chip per Konstruktion Reduced-Motion-fair
## und unaufdringlich. Der Host zeigt/versteckt ihn (Gating: nur mit
## Rekord-Kurve UND Live-Score-Fluss) und baut ihn mit der Top-Bar ab.

## Icon-Grundmaß in Design-px (skaliert über skaliere(f) mit der Top-Bar).
const ICON_PX := 16.0
## Vor dem Bestlauf: Erfolgs-Grün der Token-Palette (s. Results-Zeilen).
const FARBE_VORN := Color(0.24, 0.5, 0.24)
## Hinter dem Bestlauf: warmes, ruhiges Rot (kein Alarm-Signal).
const FARBE_HINTEN := Color(0.78, 0.42, 0.3)
## Gleichstand: neutrales Braun (wie die „Best“-Zeile der Results-Karte).
const FARBE_NEUTRAL := Color(0.55, 0.42, 0.35)
## Geist-Ton des Icons (weiches Lavendel-Grau — lesbar auf Creme).
const FARBE_GEIST := Color(0.58, 0.55, 0.74, 0.9)

var _icon: GeistIcon
var _label: Label
## Wächter gegen Label-Neuaufbau pro Frame (Host ruft zeige_delta im Takt).
var _letztes_delta := -2_147_483_648


func _init() -> void:
	name = "GeistChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_icon = GeistIcon.new()
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_label = Label.new()
	_label.theme_type_variation = &"CaptionLabel"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	hide()


## Live-Delta anzeigen (idempotent — gleicher Wert kostet nichts).
func zeige_delta(delta: int) -> void:
	if delta == _letztes_delta:
		return
	_letztes_delta = delta
	_label.text = GeistRekord.delta_text(delta)
	var farbe := FARBE_NEUTRAL
	if delta > 0:
		farbe = FARBE_VORN
	elif delta < 0:
		farbe = FARBE_HINTEN
	_label.add_theme_color_override("font_color", farbe)


## Rundenwechsel: Delta-Cache leeren + verstecken (frisches Gating im Host).
func setze_zurueck() -> void:
	_letztes_delta = -2_147_483_648
	_label.text = ""
	hide()


## Mit der ZENTRALEN UiScale-Regel skalieren (Host ruft das in
## _apply_metrics; die Label-Schrift skaliert ScreenShell.scale_fonts).
func skaliere(f: float) -> void:
	_icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX) * maxf(f, 1.0)


## Kleines Gespenst (Kuppel + Zickzack-Saum + Augen), zeichnet sich selbst —
## auch die Results-Karte nutzt es für die „Geist geschlagen!“-Zeile.
class GeistIcon:
	extends Control

	## Geist-Ton (Kopie von FARBE_GEIST — innere Klassen sehen den äußeren
	## Scope nicht).
	var farbe := Color(0.58, 0.55, 0.74, 0.9)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		var cx := w * 0.5
		var r := w * 0.5
		var punkte := PackedVector2Array()
		# Kuppel: Halbkreis von rechts (0) über oben (PI/2) nach links (PI).
		for i in 9:
			var t := PI * float(i) / 8.0
			punkte.append(Vector2(cx + r * cos(t), r - r * sin(t)))
		# Linke Flanke + Zickzack-Saum (3 Wellen) + rechte Flanke.
		punkte.append(Vector2(0.0, h * 0.85))
		punkte.append(Vector2(w / 6.0, h * 0.68))
		punkte.append(Vector2(w * 2.0 / 6.0, h * 0.85))
		punkte.append(Vector2(cx, h * 0.68))
		punkte.append(Vector2(w * 4.0 / 6.0, h * 0.85))
		punkte.append(Vector2(w * 5.0 / 6.0, h * 0.68))
		punkte.append(Vector2(w, h * 0.85))
		draw_colored_polygon(punkte, farbe)
		var augen := Color(0.25, 0.2, 0.32, 0.95)
		draw_circle(Vector2(w * 0.36, h * 0.4), w * 0.08, augen)
		draw_circle(Vector2(w * 0.64, h * 0.4), w * 0.08, augen)
