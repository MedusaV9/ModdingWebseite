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
	var r := minf(rect.size.y / 2.0, rect.size.x / 2.0)
	var mitte_y := rect.position.y + rect.size.y / 2.0
	var punkte := PackedVector2Array()
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := -PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.end.x - r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.position.x + r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	var farben := PackedColorArray()
	for punkt in punkte:
		var k := clampf((punkt.x - spanne.position.x) / maxf(spanne.size.x, 1.0), 0.0, 1.0)
		farben.append(AcTokens.TEAL.lerp(HIMMEL, k))
	ziel.draw_polygon(punkte, farben)
