class_name GoobyeUi
extends RefCounted
## Kleine UI-Bausteine des „Goo und Bye“ (G6/GOOBYE-B) — geteilt zwischen
## Laden- und Großmarkt-Szene, damit beide unter dem Datei-Deckel bleiben
## und die Karten überall gleich aussehen.


## Abgedunkeltes Overlay + zentrierte AcCard-Karte (Daumenzone-freundlich:
## die Karte sitzt mittig, der Knopf ist ihr unterstes Element).
## Ergebnis: {overlay, karte, box}.
static func karte_overlay(
	ui: Control, metrics: Dictionary, overlay_name: String, karte_basis := 380.0
) -> Dictionary:
	var overlay := Control.new()
	overlay.name = overlay_name
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(AcTokens.INK.r, AcTokens.INK.g, AcTokens.INK.b, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var karte := PanelContainer.new()
	karte.name = "Karte"
	karte.theme_type_variation = &"AcCard"
	karte.set_anchors_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	karte.custom_minimum_size = Vector2(ScreenShell.card_width(metrics, karte_basis), 0.0)
	overlay.add_child(karte)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	karte.add_child(box)
	return {"overlay": overlay, "karte": karte, "box": box}
