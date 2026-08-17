extends RefCounted
## W21: geteilter Steuer-Hinweis-Kanon der Minispiele. install/fade/draw
## tragen das deliveryRush-Muster (M6: dunkle Tinte auf Milchglas-Plate,
## Fade nach HINT_FADE_SEC Sim-Sekunden) auf die Ranch-3D-Spiele
## (herde/parcours) — vorher lag dort nackte SoftLabel-Schrift unlesbar auf
## Gras bzw. Himmel (Playtest w21_mg_ranch_quer/062). clamp_size nutzen
## AUCH deliveryRush/starHopper/memoryMatch: es ist die Godot-sichere Art,
## einem Autowrap-Label Breite + echte Umbruch-Höhe zu geben (s. dort).
## Die Spiele positionieren das Label selbst (_layout_hud) und melden ihre
## Sim-Uhr als Callable — sie startet je Level/Lauf wieder bei 0, damit der
## Hinweis zu jedem Neustart kurz zurückkommt.

## Nach so vielen Sim-Sekunden blendet der Steuer-Hinweis aus (M6-Kanon).
const HINT_FADE_SEC := 7.0


## Sichtbarkeit des Hinweises: 1 → 0 über 1,2 s VOR HINT_FADE_SEC
## (dieselbe Kurve wie DeliveryRushFeel.hint_alpha).
static func hint_alpha_at(t: float) -> float:
	return clampf((HINT_FADE_SEC - t) / 1.2, 0.0, 1.0)


## Stylt Label UND Plate zusammen (Tinte + heller Saum, Radius 12) und
## hängt den Plate-Maler an den HUD-Layer: die Plate liegt ÜBER der
## 3D-Szene, aber UNTER dem Label-Text (Kind-Canvas-Items über Eltern-Draw).
static func install(hud: Control, label: Label, plate: StyleBoxFlat, zeit: Callable) -> void:
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Ohne Autowrap klemmt Labels Mindestbreite bei der vollen Textbreite —
	# `size` ließe sich nie unter den schmalen Viewport drücken.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.42, 0.24, 0.16))
	label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	plate.set_corner_radius_all(12)
	hud.draw.connect(func() -> void: draw_hint_plate(hud, plate, label, float(zeit.call())))


## Breite setzen + Höhe an die frische Umbruch-Mindesthöhe klemmen. WICHTIG
## in drei Schritten: set_size klemmt die Höhe an der GECACHTEN Mindesthöhe
## (Controls cachen get_combined_minimum_size; Resize allein invalidiert
## NICHT) — bei einem frischen Label (Breite ~0) wäre das „jedes Wort eine
## Zeile" (~2300 px hoch, Befund w14-Test). Deshalb: Breite setzen, Cache
## invalidieren, dann klemmt der zweite Aufruf an der echten Zeilenhöhe.
static func clamp_size(label: Label, width: float) -> Vector2:
	label.size = Vector2(width, 0.0)
	label.update_minimum_size()
	label.size = Vector2(width, 0.0)
	return label.size


## Pro Frame: Label und Plate hängen am selben Alpha (deliveryRush-Muster);
## queue_redraw stößt den Plate-Maler an.
static func fade_hint(hud: Control, label: Label, t: float) -> void:
	if label == null or hud == null:
		return
	label.modulate.a = hint_alpha_at(t)
	hud.queue_redraw()


## Milchglas-Plate hinter dem Hinweis (Geometrie = Label-Rect).
static func draw_hint_plate(hud: CanvasItem, plate: StyleBoxFlat, label: Label, t: float) -> void:
	var alpha := hint_alpha_at(t)
	if label == null or alpha <= 0.0:
		return
	plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * alpha)
	hud.draw_style_box(plate, Rect2(label.position - Vector2(0.0, 2.0), label.size))
