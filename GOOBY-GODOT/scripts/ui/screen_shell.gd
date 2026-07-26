class_name ScreenShell
extends RefCounted
## FB3 — DIE gemeinsame Screen-Hülle: bündelt die FIX1-Bausteine (`UiScale`,
## Safe-Area, Touch-Floor) zu EINEM wiederverwendbaren Satz statischer
## Helfer, damit jeder Vollbild-Screen dieselben Regeln anwendet statt
## eigene Festpixel-Ränder zu erfinden (P0 „UI klebt am Rand / skaliert
## nicht mit der Gerätegröße“).
##
## Muster (siehe FriendsScreen/ArcadeScreen):
##   var m := ScreenShell.metrics(get_viewport())
##   ScreenShell.frame(_rows, m)            # Safe-Area + skalierte Ränder
##   ScreenShell.touch_target(_back, m)     # Tippfläche ≥ Touch-Floor
##   ScreenShell.scale_fonts(self, m.f)     # Theme-Schriften × UiScale
## — bei `Viewport.size_changed` erneut aufrufen.

## Randabstand des Inhalts zur Safe-Area (Design-px, skaliert mit f).
const EDGE_X := 16.0
const EDGE_Y := 12.0
## Meta-Keys: gemerkte Design-Basis bzw. Opt-out fürs Schrift-Skalieren.
const META_FONT_BASE := "fb3_font_base"
const META_FONT_SKIP := "fb3_font_skip"


## Alle Layout-Kenngrößen EINMAL pro Durchlauf einsammeln.
static func metrics(vp: Viewport, safe_override := Rect2()) -> Dictionary:
	var canvas := Vector2(vp.get_visible_rect().size)
	var f := UiScale.for_viewport(vp)
	# Touch-Floor: physisches 44-pt-Minimum (touch_px_per_pt ist NICHT vom
	# Design-Deckel begrenzt) — nie kleiner als die Canvas-Heuristik.
	var floor_px := maxf(
		HudLayoutLogic.touch_floor_canvas(canvas),
		float(AcTokens.TOUCH_FLOOR) * UiScale.touch_px_per_pt(vp)
	)
	return {
		"f": f,
		"canvas": canvas,
		"insets": UiScale.safe_insets_canvas(vp, safe_override),
		"floor_px": floor_px,
	}


## Wurzel-Container eines Vollbild-Screens in die Safe-Area einpassen
## (Anker FULL_RECT + Insets + skalierte Ränder).
static func frame(rows: Control, m: Dictionary, edge_x := EDGE_X, edge_y := EDGE_Y) -> void:
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = float(insets["left"]) + edge_x * f
	rows.offset_right = -float(insets["right"]) - edge_x * f
	rows.offset_top = float(insets["top"]) + edge_y * f
	rows.offset_bottom = -float(insets["bottom"]) - edge_y * f


## Tippfläche auf den physischen Touch-Floor heben (beide Achsen — kurze
## Labels wie „Auto“ unterschreiten sonst die Breite).
static func touch_target(ctl: Control, m: Dictionary) -> void:
	var floor_px: float = m["floor_px"]
	ctl.custom_minimum_size = ctl.custom_minimum_size.max(Vector2(floor_px, floor_px))


## Breite einer zentrierten Karte: Wunschbreite × f, aber nie breiter als
## die Safe-Area minus Seitenränder (PanelSheetLayout-Regel für Karten,
## die kein Bottom-Sheet sind).
static func card_width(m: Dictionary, base_width: float) -> float:
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var f: float = m["f"]
	var avail := (
		canvas.x
		- float(insets["left"])
		- float(insets["right"])
		- 2.0 * PanelSheetLayout.MARGIN * f
	)
	return minf(base_width * f, maxf(avail, 0.0))


## Höhen-Deckel einer zentrierten Karte (Inhalt darüber scrollt).
static func card_max_height(m: Dictionary) -> float:
	var canvas: Vector2 = m["canvas"]
	var insets: Dictionary = m["insets"]
	var safe_h := canvas.y - float(insets["top"]) - float(insets["bottom"])
	return safe_h * PanelSheetLayout.MAX_HEIGHT_SHARE


## Theme-Schriften des Teilbaums mit f skalieren. Die Design-Basis wird
## beim ersten Besuch in Meta gemerkt (vorhandene Overrides = Design-px),
## damit wiederholte Aufrufe von der BASIS statt vom letzten Ergebnis
## skalieren. Nodes mit META_FONT_SKIP bleiben unangetastet.
static func scale_fonts(root: Control, f: float) -> void:
	for node in _font_nodes(root):
		var base := _font_base(node)
		if base <= 0:
			continue
		node.add_theme_font_size_override("font_size", int(maxf(roundf(base * f), 10.0)))


static func _font_nodes(root: Control) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Label or node is Button or node is LineEdit:
			if not node.has_meta(META_FONT_SKIP):
				out.append(node)
	return out


static func _font_base(ctl: Control) -> int:
	if ctl.has_meta(META_FONT_BASE):
		return int(ctl.get_meta(META_FONT_BASE))
	# Effektive Größe beim ERSTEN Besuch = Design-Basis (Override der
	# Screen-Builder, Theme-Variation oder Theme-Default — Screens bauen
	# in Design-px, bevor skaliert wird).
	var base := ctl.get_theme_font_size("font_size")
	ctl.set_meta(META_FONT_BASE, base)
	return base
