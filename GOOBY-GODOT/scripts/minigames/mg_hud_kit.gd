class_name MgHudKit
extends RefCounted
## W21/P5 — DER gemeinsame In-Game-HUD-Standard der Minispiele
## (UI-DESIGN-ACNH §8/P5). Vorher hatte jedes Spiel eine EIGENE HUD-Welt
## (Befund mg_spiele: „sechs eigene Welten" — weiß+Saum, Chip auf Plate,
## nackte Labels, Fix-Pixel); dieses Kit trägt EINE Chip-/Banner-/Feier-
## Sprache über alle Spiele. Es lebt NEBEN hint_feel.gd (der Steuer-
## Hinweis-Kanon bleibt dort) und fasst KEINE Host-Dateien an.
##
## API (alle statisch):
##   MgHudKit.ui_scale(view)                  # DER _ui-Faktor (Kurzkante/390)
##   MgHudKit.font_px(design, ui)             # Skala×f, Boden FONT_MIN_PX
##   MgHudKit.style_chip(wert, zeile, ui)     # Zähler-Chip: Tinte auf Frost
##   MgHudKit.layout_chip(wert, zeile, ui)    # Standard-Anker oben links
##   MgHudKit.chip_rect(wert, zeile, ui)      # Pillen-Rect (für Draw + Tests)
##   MgHudKit.draw_chip(canvas, plate, …)     # Frost-Pille hinter den Labels
##   MgHudKit.install_chip(hud, wert, zeile, ui_cb)  # Ranch-Muster (draw-Hook)
##   MgHudKit.banner_alpha(t_left)            # Banner-Ausblendkurve (PUR)
##   MgHudKit.draw_banner(canvas, plate, view, ui, text, t_left, gold)
##   MgHudKit.bar_h(ui)                       # EINE Balkenhöhe (AcTokens.BAR_H)
##   MgHudKit.draw_progress(canvas, plate, rect, frac, fill)
##   MgHudKit.feier_beat(host, view, ui, text, rng)  # Pop+Sparkle, RM-gated
##
## Typo-MINIMUM: kein effektiver HUD-Text unter FONT_MIN_PX (der
## 9–12-px-Befund TP-1/„Letterbox") — jede Schriftgröße läuft über
## font_px(). Alle Maße sind Entwurfs-px × ui (AcTokens.px-Rundung).

## Entwurfs-Kurzkante: der etablierte _ui-Kanon der Spiele (Kurzkante/390,
## geklemmt 0,75–3,0 — hide_seek/harbor_hopper-Muster, jetzt EINE Quelle).
const DESIGN_SHORT := 390.0
const UI_MIN := 0.75
const UI_MAX := 3.0

## Lesbarkeits-Boden: kein effektiver HUD-Text unter 14 px (Befund „9–12 px
## im Letterbox"). Bewusst über dem AcTokens.font_px-Boden (10).
const FONT_MIN_PX := 14

## Chip (Score-/Zähler-Pille): Wert-Zeile + Unterzeile auf EINER Frost-
## Pille. Größen von der Typo-Skala (SIZE_BUTTON/SIZE_CAPTION) — löst die
## 34-px-Headline-Klötze ab (HUD-Fläche ≤ 6 %, Abnahme §8/P5).
const CHIP_VALUE_D := float(AcTokens.SIZE_BUTTON)
const CHIP_CAPTION_D := float(AcTokens.SIZE_CAPTION)
const CHIP_PAD_D := Vector2(12.0, 6.0)
const CHIP_ORIGIN_D := Vector2(16.0, 10.0)
## Zeilen-Versatz Wert → Unterzeile (Entwurfs-px).
const CHIP_ROW_STEP_D := 32.0

## Milchglas-Ton der Plates (hint_feel-/deliveryRush-Kanon) — Banner und
## Hinweis-Plates aller Spiele nutzen dieselbe warme Creme.
const PLATE_TINT := Color(1.0, 0.99, 0.94)
const PLATE_ALPHA := 0.72

## Banner-Standard: EINE Größe/Optik (teaParty/memoryMatch/carrotCatch-
## Muster generalisiert) — Milchglas-Plate, Tinte + heller Saum, Umbruch.
const BANNER_FONT_D := 26.0
const BANNER_W_D := 460.0
const BANNER_TOP_FRAC := 0.26
const BANNER_PAD_D := Vector2(18.0, 10.0)
const BANNER_GOLD_PLATE := Color(1.0, 0.93, 0.62, 0.82)
const BANNER_GOLD_INK := Color(0.62, 0.4, 0.1)
const BANNER_INK := Color(0.32, 0.24, 0.28)

## Feier-Beat: kleine Gold-Pille poppt am Beat-Punkt auf (MotionKit.pop_in)
## + Papier-Sparkle (MotionKit.papier_puff, RNG injizierbar) — RM-gated
## über MotionKit. NICHT für Routine spammen (§6.3: pro Moment EIN Effekt).
const FEIER_S := 1.4
const FEIER_FONT_D := float(AcTokens.SIZE_BUTTON)
const FEIER_Y_FRAC := 0.4
const FEIER_META := &"_mg_feier_beat"


## DER _ui-Faktor der Minispiele: Kurzkante/DESIGN_SHORT, geklemmt.
static func ui_scale(view_size: Vector2) -> float:
	return clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, UI_MIN, UI_MAX)


## Skalierte Schriftgröße mit Typo-MINIMUM (round()-Konvention wie
## AcTokens.px, aber Boden FONT_MIN_PX statt 10).
static func font_px(design: float, ui: float) -> int:
	return maxi(AcTokens.px(design, ui), FONT_MIN_PX)


## Milchglas-Farbe für Plates (Banner-/Hinweis-Ton, EINE Quelle).
static func plate_color(alpha := PLATE_ALPHA) -> Color:
	return Color(PLATE_TINT, alpha)


## ── Chip (Score-/Zähler-Pille) ────────────────────────────────────────────


## Chip-Typo: Wert als Tinte, Unterzeile weicher — beide auf der Frost-
## Pille, deshalb OHNE Kontur (der Saum war die Krücke nackter Labels).
static func style_chip(value: Label, caption: Label, ui: float) -> void:
	value.add_theme_font_size_override("font_size", font_px(CHIP_VALUE_D, ui))
	value.add_theme_color_override("font_color", AcTokens.INK)
	value.add_theme_constant_override("outline_size", 0)
	if caption == null:
		return
	caption.add_theme_font_size_override("font_size", font_px(CHIP_CAPTION_D, ui))
	caption.add_theme_color_override("font_color", AcTokens.INK_SOFT)
	caption.add_theme_constant_override("outline_size", 0)


## Standard-Anker oben links: Wert-Zeile + Unterzeile im festen Raster.
## reset_size: Labels wachsen nur — nach einem Resize (großes ui → kleines
## ui) bliebe `size` sonst auf dem alten Riesen-Maß stehen und die Pille
## (chip_rect misst `size`) würde weit über die 6-%-Abnahme hinauswachsen.
static func layout_chip(value: Label, caption: Label, ui: float, origin_d := CHIP_ORIGIN_D) -> void:
	value.reset_size()
	value.position = origin_d * ui
	if caption != null:
		caption.reset_size()
		caption.position = Vector2(origin_d.x, origin_d.y + CHIP_ROW_STEP_D) * ui


## Pillen-Rect um Wert (+ Unterzeile, falls sichtbar) — Draw UND Tests
## messen dieselbe Geometrie.
static func chip_rect(value: Label, caption: Label, ui: float) -> Rect2:
	var pad := CHIP_PAD_D * ui
	var wide := value.size.x
	var tall := value.size.y
	if caption != null and not caption.text.is_empty():
		wide = maxf(wide, caption.size.x)
		tall = caption.position.y + caption.size.y - value.position.y
	return Rect2(value.position - pad, Vector2(wide, tall) + pad * 2.0)


## Frost-Pille hinter den Chip-Labels (Kapsel-Sprache der HUD-Stats).
static func draw_chip(
	canvas: CanvasItem, plate: StyleBoxFlat, value: Label, caption: Label, ui: float
) -> Rect2:
	var rect := chip_rect(value, caption, ui)
	plate.bg_color = AcTokens.FROST
	plate.set_corner_radius_all(AcTokens.RADIUS_PILL)
	canvas.draw_style_box(plate, rect)
	return rect


## Ranch-Muster (wie HintFeel.install): stylt die Labels und hängt den
## Pillen-Maler an den HUD-Layer — die Pille liegt ÜBER der 3D-Szene,
## aber UNTER den Label-Kindern.
static func install_chip(hud: Control, value: Label, caption: Label, ui: Callable) -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	hud.draw.connect(func() -> void: draw_chip(hud, plate, value, caption, float(ui.call())))
	return plate


## ── Banner-Standard ──────────────────────────────────────────────────────


## Sichtbarkeit des Banners aus der Restzeit (PUR für Tests) — dieselbe
## Kurve, die tea/memory/carrot etabliert haben.
static func banner_alpha(t_left: float) -> float:
	return clampf(t_left * 1.4, 0.0, 1.0)


## PURE Umbruch-Breite des Banners (der SH-2-Vertrag lebt jetzt HIER):
## min(92 % Viewport, 460×ui) — jede umbrochene Zeile bleibt im Bild,
## auch im schmalen Letterbox-Hochkant (~289 px).
static func banner_wrap_width(view_w: float, ui: float) -> float:
	return minf(view_w * 0.92, BANNER_W_D * ui)


## DER Banner: mittig bei view.y·0.26, Milchglas-Plate (gold = Feier-Ton),
## Tinte mit hellem Saum, lange Texte brechen um. Gibt das Plate-Rect
## zurück (Tests/Flanken-Deko).
static func draw_banner(
	canvas: CanvasItem,
	plate: StyleBoxFlat,
	view: Vector2,
	ui: float,
	text: String,
	t_left: float,
	gold := false
) -> Rect2:
	if t_left <= 0.0 or text.is_empty():
		return Rect2()
	var font := ThemeService.font(800)
	var alpha := banner_alpha(t_left)
	var size := font_px(BANNER_FONT_D, ui)
	var w := banner_wrap_width(view.x, ui)
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, size)
	var top := view.y * BANNER_TOP_FRAC
	var pad := BANNER_PAD_D * ui
	plate.set_corner_radius_all(AcTokens.px(float(AcTokens.RADIUS_ROW), ui))
	var fill := BANNER_GOLD_PLATE if gold else Color(PLATE_TINT, 0.74)
	fill.a *= alpha
	plate.bg_color = fill
	var rect := Rect2(Vector2((view.x - text_size.x) * 0.5, top) - pad, text_size + pad * 2.0)
	canvas.draw_style_box(plate, rect)
	var ink := BANNER_GOLD_INK if gold else BANNER_INK
	ink.a = alpha
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((view.x - w) * 0.5, top + font.get_ascent(size))
	canvas.draw_multiline_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, -1, maxi(3, AcTokens.px(5.0, ui)), rim
	)
	canvas.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, -1, ink)
	return rect


## ── Ziel-/Fortschritts-Anzeige ───────────────────────────────────────────


## EINE Balkenhöhe für alle Spiel-Fortschritte (AcTokens.BAR_H × ui).
static func bar_h(ui: float) -> float:
	return float(AcTokens.px(float(AcTokens.BAR_H), ui))


## Dunkler Milchglas-Track (memoryMatch-Muster) — der Balken liest sich
## über jeder 3D-Szene.
static func progress_plate() -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.32, 0.24, 0.2, 0.4)
	return plate


## Fortschritt in ein Rect malen: Pill-Track + Füll-Fraktion.
static func draw_progress(
	canvas: CanvasItem, plate: StyleBoxFlat, rect: Rect2, frac: float, fill: Color
) -> void:
	plate.set_corner_radius_all(AcTokens.RADIUS_PILL)
	canvas.draw_style_box(plate, rect.grow(2.0))
	var teil := clampf(frac, 0.0, 1.0)
	if teil > 0.0:
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * teil, rect.size.y)), fill)


## ── Feier-Beat ───────────────────────────────────────────────────────────


## Kleiner Feier-Moment am Spiel-Beat (Schaf im Pferch, Paar gefunden,
## Welle überstanden …): Gold-Pille poppt auf (MotionKit.pop_in) + Papier-
## Sparkle (MotionKit.papier_puff) — BEIDE Reduced-Motion-gated (Endzustand
## sofort, keine Flöckchen). rng nur in Tests injizieren; Spiele lassen ihn
## null, damit der Sparkle NIE den Sim-RNG-Strom (GoobyRng) anzapft.
## Anti-Stapeln: ein neuer Beat ersetzt den noch stehenden.
static func feier_beat(
	host: CanvasItem, view: Vector2, ui: float, text: String, rng: RandomNumberGenerator = null
) -> Control:
	if host.has_meta(FEIER_META):
		var alt: Variant = host.get_meta(FEIER_META)
		if alt is Control and is_instance_valid(alt):
			(alt as Control).queue_free()
	var beat := Control.new()
	beat.name = "FeierBeat"
	beat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beat.z_index = 20
	var panel := PanelContainer.new()
	panel.name = "Plate"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := StyleBoxFlat.new()
	plate.bg_color = BANNER_GOLD_PLATE
	plate.set_corner_radius_all(AcTokens.RADIUS_PILL)
	var pad := BANNER_PAD_D * ui
	plate.content_margin_left = pad.x
	plate.content_margin_right = pad.x
	plate.content_margin_top = pad.y
	plate.content_margin_bottom = pad.y
	panel.add_theme_stylebox_override("panel", plate)
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.add_theme_font_override("font", ThemeService.font(800))
	label.add_theme_font_size_override("font_size", font_px(FEIER_FONT_D, ui))
	label.add_theme_color_override("font_color", BANNER_GOLD_INK)
	panel.add_child(label)
	beat.add_child(panel)
	host.add_child(beat)
	panel.reset_size()
	beat.size = panel.size
	beat.position = Vector2(view.x * 0.5, view.y * FEIER_Y_FRAC) - beat.size * 0.5
	host.set_meta(FEIER_META, beat)
	MotionKit.pop_in(beat)
	MotionKit.papier_puff(beat, MotionKit.PUFF_TEILE, rng)
	var tween := beat.create_tween()
	tween.tween_interval(FEIER_S)
	if not MotionKit.reduced(beat):
		tween.tween_property(beat, "modulate:a", 0.0, 0.25)
	tween.tween_callback(beat.queue_free)
	return beat
