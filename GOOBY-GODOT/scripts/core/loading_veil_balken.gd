class_name LoadingVeilBalken
extends ProgressBar
## W16/VEIL — Teal-Verlaufsbalken der Veil-Karte (Web-Parität: POLISH-D
## `.mg-loading-bar`, GOOBY/src/ui/styles.css Z. 5132-5150): Pill-Track in
## color-mix(Teal 18 %, Cream), Füllung als 90°-Verlauf TEAL→Himmelblau,
## der sich wie im Web über die FÜLLBREITE spannt.
##
## Bleibt eine echte ProgressBar (FROZEN %Progress-Contract: value/visible
## steuert weiter das Veil) — nur die Optik ist ersetzt: Theme-Füllung wird
## geleert und der Verlauf in _draw als Pill-Polygon mit Vertex-Farben
## gezeichnet.

## Web linear-gradient(90deg, var(--teal), #7fd4ff) — das Himmelblau ist
## im Web ein Literal ohne Token, hier ebenso (AcTokens bleibt unberührt).
const HIMMEL := Color("#7FD4FF")
const KAPPEN_SEGMENTE := 7


func _ready() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = track_farbe()
	track.set_corner_radius_all(AcTokens.RADIUS_PILL)
	add_theme_stylebox_override("background", track)
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	value_changed.connect(func(_wert: float) -> void: queue_redraw())


func _draw() -> void:
	var breite := size.x * clampf(ratio, 0.0, 1.0)
	if breite <= 0.5:
		return
	var rect := Rect2(0.0, 0.0, breite, size.y)
	zeichne_gradient_pill(self, rect, rect)


## Web color-mix(in srgb, var(--teal) 18%, var(--bg-cream)).
static func track_farbe() -> Color:
	return AcTokens.BG_CREAM.lerp(AcTokens.TEAL, 0.18)


## Pill (halbrunde Kappen) mit horizontalem TEAL→HIMMEL-Verlauf zeichnen.
## `spanne` = Rechteck, über das sich der Verlauf spannt (fürs Sweep-Band
## auch außerhalb des sichtbaren Ausschnitts `rect`).
static func zeichne_gradient_pill(ziel: CanvasItem, rect: Rect2, spanne: Rect2) -> void:
	var punkte := pill_punkte(rect)
	if punkte.size() < 3:
		return
	var farben := PackedColorArray()
	for punkt in punkte:
		var k := clampf((punkt.x - spanne.position.x) / maxf(spanne.size.x, 1.0), 0.0, 1.0)
		farben.append(AcTokens.TEAL.lerp(HIMMEL, k))
	ziel.draw_polygon(punkte, farben)


## Punktliste der Pill — separat und statisch, damit degenerierte Listen
## VOR draw_polygon testbar abgefangen sind (Eval-2026-08 Befund 6):
## Fällt die Füllbreite unter die Höhe (Sweep-Ein-/Austritt, schmaler
## Balkenstand), kollabieren beide Kappenzentren auf denselben Punkt.
## Die alte Zwei-Kappen-Schleife erzeugte dort doppelte Nahtpunkte und —
## weil beide Zentren getrennt gerundet wurden (float32, große x-Werte) —
## minimal selbstschneidende Nähte: `draw_polygon` scheiterte mit
## „Invalid polygon data, triangulation failed“. Deshalb zeichnet der
## Schmalfall jetzt EINEN geschlossenen Kreisbogen um das gemeinsame
## Zentrum (keine Naht, keine Duplikate); der halbe Pixel Übergang puffert
## Sub-Pixel-Stadien. Unzeichenbare Rects (Breite/Höhe ≤ 0) → leere Liste.
static func pill_punkte(rect: Rect2) -> PackedVector2Array:
	var r := minf(rect.size.y, rect.size.x) / 2.0
	var punkte := PackedVector2Array()
	if r <= 0.0:
		return punkte
	var mitte_y := rect.position.y + rect.size.y / 2.0
	if rect.size.x <= rect.size.y + 0.5:
		var mitte := Vector2(rect.position.x + rect.size.x / 2.0, mitte_y)
		for i in 2 * KAPPEN_SEGMENTE:
			var winkel := TAU * float(i) / float(2 * KAPPEN_SEGMENTE)
			punkte.append(mitte + Vector2(cos(winkel), sin(winkel)) * r)
		return punkte
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := -PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.end.x - r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.position.x + r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	return punkte
