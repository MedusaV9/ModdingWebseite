class_name BootLadebalken
extends Control
## W14/LOADING, Optik W16/G4 — der Möhren-Ladebalken des Boot-Covers in der
## Alt-Web-Balken-Optik (GOOBY/src/ui/styles.css `.mg-loading-bar`,
## Z. 5132–5150): flacher Pill-Track in color-mix(Möhre 18 %, Cream), die
## Füllung als 90°-Verlauf MOEHRE→MOEHRE_HELL über die Füllbreite — dasselbe
## Rezept wie der Teal-Balken der Veil-Karte (loading_veil_balken.gd), nur
## in Möhre. An der Füllkante bleibt der geliebte Möhrenkopf mit
## Blattschopf, jetzt als weiß beringter Mini-Sticker (Web-Sticker-Sprache
## `.mg-loading-motif`: weißer Ring + weicher Schatten statt Ink-Kontur).
## Der Track sitzt im UNTEREN Teil des Controls (TRACK_ANTEIL) — der Raum
## darüber gehört dem Blattschopf, nichts wird geclippt.
##
## EHRLICHKEIT: `set_progress` setzt das ECHTE Ziel; die Anzeige gleitet nur
## HINTERHER (nie voraus) — der Balken zeigt nie mehr an, als wirklich
## geladen ist. Reduced Motion (set_animated(false)) springt direkt; seit
## W16/G4 verdrahtet das Boot-Cover den Schalter wirklich (RM-Entscheid P22:
## das Gleiten ist eine Dauer-Animation im _process und wird eingefroren).

const MOEHRE := Color("#FF8C42")
const MOEHRE_HELL := Color("#FFB374")
const BLATT := Color("#7FBF6A")
const BLATT_DUNKEL := Color("#5E9C4C")
## Web color-mix(in srgb, FILL 18%, var(--bg-cream)) — Anteil des Tracks.
const TRACK_MIX := 0.18
## Anteil der Control-Höhe für den Pill-Track (Rest = Luft für den Schopf).
const TRACK_ANTEIL := 0.5
## Halbrunde Pill-Kappen (Segmentzahl wie loading_veil_balken.gd).
const KAPPEN_SEGMENTE := 7

## Anzeige-Glättung in Anteilen/Sekunde (nur vorwärts Richtung Ziel).
const GLEIT_TEMPO := 1.6

var _ziel := 0.0
var _anzeige := 0.0
var _animated := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_animated)


func _process(delta: float) -> void:
	if _anzeige >= _ziel:
		return
	_anzeige = minf(_ziel, _anzeige + GLEIT_TEMPO * delta)
	queue_redraw()


## ECHTER Fortschritt 0..1 (Ziel der Anzeige; sie holt nur auf, nie voraus).
func set_progress(ratio: float) -> void:
	_ziel = clampf(ratio, 0.0, 1.0)
	if not _animated:
		_anzeige = _ziel
	queue_redraw()


func get_progress() -> float:
	return _ziel


## Geglätteter Anzeigewert (Tests: nie über dem echten Ziel).
func anzeige_wert() -> float:
	return _anzeige


## Reduced Motion: keine Gleit-Animation, Anzeige springt aufs echte Ziel.
func set_animated(animated: bool) -> void:
	_animated = animated
	set_process(animated)
	if not animated:
		_anzeige = _ziel
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var track_h := maxf(4.0, size.y * TRACK_ANTEIL)
	var track := Rect2(0.0, size.y - track_h, size.x, track_h)
	_pill(track, AcTokens.BG_CREAM.lerp(MOEHRE, TRACK_MIX))
	var fuell_w := _anzeige * track.size.x
	if fuell_w < 0.5:
		return
	fuell_w = maxf(fuell_w, track_h)
	_gradient_pill(Rect2(track.position, Vector2(fuell_w, track_h)))
	_moehrenkopf(Vector2(fuell_w, track.position.y + track_h / 2.0), track_h)


## Der Füllkopf: kleine runde Möhre mit Blattschopf an der Füllkante —
## weiß beringter Mini-Sticker (Web `.mg-loading-motif`-Sprache).
func _moehrenkopf(spitze: Vector2, track_h: float) -> void:
	var r := track_h * 0.85
	# Blattschopf zuerst (liegt HINTER dem Möhren-Kopf).
	for blatt_info: Array in [[-0.55, BLATT_DUNKEL], [0.5, BLATT_DUNKEL], [0.0, BLATT]]:
		var neigung := float(blatt_info[0])
		var von := spitze + Vector2(neigung * r * 0.4, -r * 0.5)
		var bis := von + Vector2(neigung * r * 1.0, -r * 1.25)
		draw_line(von, bis, blatt_info[1], r * 0.45)
		draw_circle(bis, r * 0.24, blatt_info[1])
	# Weicher Pop-Schatten + weißer Ring statt der alten Ink-Kontur.
	draw_circle(spitze + Vector2(0.0, r * 0.12), r * 1.16, AcTokens.SHADOW_SOFT_COLOR)
	draw_circle(spitze, r + maxf(1.5, r * 0.18), AcTokens.WHITE)
	draw_circle(spitze, r, MOEHRE)
	draw_circle(spitze + Vector2(-r * 0.28, -r * 0.3), r * 0.3, MOEHRE_HELL)


## Pill (halbrunde Kappen) einfarbig — Track-Bett des Balkens.
func _pill(rect: Rect2, farbe: Color) -> void:
	draw_colored_polygon(_pill_punkte(rect), farbe)


## Füllung mit horizontalem MOEHRE→MOEHRE_HELL-Verlauf über die Füllbreite
## (Web linear-gradient(90deg, …) — Rezept wie loading_veil_balken.gd).
func _gradient_pill(rect: Rect2) -> void:
	var punkte := _pill_punkte(rect)
	var farben := PackedColorArray()
	for punkt in punkte:
		var k := clampf((punkt.x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
		farben.append(MOEHRE.lerp(MOEHRE_HELL, k))
	draw_polygon(punkte, farben)


static func _pill_punkte(rect: Rect2) -> PackedVector2Array:
	var r := minf(rect.size.y / 2.0, rect.size.x / 2.0)
	var mitte_y := rect.position.y + rect.size.y / 2.0
	var punkte := PackedVector2Array()
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := -PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.end.x - r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	for i in KAPPEN_SEGMENTE + 1:
		var winkel := PI / 2.0 + PI * float(i) / float(KAPPEN_SEGMENTE)
		punkte.append(Vector2(rect.position.x + r + cos(winkel) * r, mitte_y + sin(winkel) * r))
	return punkte
