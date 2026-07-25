class_name CitySheetBausteine
extends RefCounted
## Gemeinsame UI-Bausteine der Ort-Sheets (POW!, Autohaus, Baumarkt,
## Wochenmarkt, Post). Reiner Builder (statisch) — Farben/Fonts kommen
## ausschließlich aus dem Projekt-Theme (Theme-Type-Variations), nie
## hartkodiert.
##
## GOTCHA (W3a-Handoff §1): Autowrap-Labels brauchen VOR `add_child` sowohl
## `custom_minimum_size.x` als auch `size.x`, sonst rechnet die Min-Höhe bei
## Breite 0 und das PanelSheet wächst schirmhoch und schrumpft nie zurück.

## Standard-Innenbreite eines Ort-Sheets.
const BREITE := 420.0
const TEXT_BREITE := 380.0
## Höhe der scrollenden Warenliste. Das Bottom-Sheet wächst mit dem Inhalt —
## über diesen Werten stößt es auf 1280×720 oben an den Bildrand.
const LISTE_HOEHE := 330.0
## Kurzform für Sheets, über denen noch eine Karte steht (POW!, Markt).
const LISTE_HOEHE_KURZ := 200.0
## Mindestbreite für Zweit-Knöpfe rechts („Alle 12“) — ohne sie franst die
## Knopfspalte pro Zeile unterschiedlich weit nach links aus.
const KNOPF_ZWEIT_BREITE := 92.0


## Wurzel-Box eines Sheet-Inhalts einrichten (Mindestbreite + Abstände).
static func richte_box_ein(box: VBoxContainer) -> void:
	box.custom_minimum_size = Vector2(BREITE, 0.0)
	box.add_theme_constant_override("separation", 10)


## Fließtext-Label (Autowrap-sicher) anhängen.
static func label(box: Control, text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(TEXT_BREITE, 0.0)
	l.size = Vector2(TEXT_BREITE, 0.0)
	if not variation.is_empty():
		l.theme_type_variation = variation
	box.add_child(l)
	return l


## Karten-Panel (AcCard) mit eigener VBox — für Info-/Erste-Male-Karten.
static func karte(box: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AcCard"
	panel.custom_minimum_size = Vector2(TEXT_BREITE, 0.0)
	box.add_child(panel)
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 6)
	panel.add_child(inhalt)
	return inhalt


## Münz-Stand-Zeile („Du hast N Münzen“).
static func coins_zeile(box: Control, coins: int) -> Label:
	return label(box, I18nService.t("city.laden.coins").format({"coins": coins}), "CaptionLabel")


## Waren-Zeile: Name (+ Zusatz) links, Kauf-Knopf rechts.
static func kauf_zeile(
	box: Control, titel: String, zusatz: String, knopf_text: String, aktiv: bool, bei_kauf: Callable
) -> HBoxContainer:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 12)
	box.add_child(zeile)
	var texte := VBoxContainer.new()
	texte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texte.add_theme_constant_override("separation", 0)
	zeile.add_child(texte)
	var name_label := Label.new()
	name_label.text = titel
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(240.0, 0.0)
	name_label.size = Vector2(240.0, 0.0)
	texte.add_child(name_label)
	if not zusatz.is_empty():
		var caption := Label.new()
		caption.text = zusatz
		caption.theme_type_variation = "CaptionLabel"
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.custom_minimum_size = Vector2(240.0, 0.0)
		caption.size = Vector2(240.0, 0.0)
		texte.add_child(caption)
	var btn := Button.new()
	btn.theme_type_variation = "AccentButton"
	btn.text = knopf_text
	btn.disabled = not aktiv
	btn.pressed.connect(bei_kauf)
	zeile.add_child(btn)
	return zeile


## Scroll-Bereich mit innerer VBox (lange Warenlisten).
static func scroll_liste(box: Control, hoehe: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, hoehe)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var liste := VBoxContainer.new()
	liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	liste.add_theme_constant_override("separation", 8)
	scroll.add_child(liste)
	return liste


## Preis-Chip-Text („120 ᴳ“) — Symbol nur in Chips, nie im Fließtext.
static func preis_text(preis: int) -> String:
	return I18nService.t("city.laden.kaufen").format({"preis": preis})


## Kleiner farbiger Farb-Wähl-Knopf (Autohaus-Lackierung).
static func farb_knopf(farbe: Color, gewaehlt: bool, bei_wahl: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(44.0, 44.0)
	btn.tooltip_text = ""
	btn.focus_mode = Control.FOCUS_NONE
	var stil := StyleBoxFlat.new()
	stil.bg_color = farbe
	stil.set_corner_radius_all(12)
	stil.set_border_width_all(4 if gewaehlt else 0)
	stil.border_color = AcTokens.INK
	btn.add_theme_stylebox_override("normal", stil)
	btn.add_theme_stylebox_override("hover", stil)
	btn.add_theme_stylebox_override("pressed", stil)
	btn.pressed.connect(bei_wahl)
	return btn
