class_name BootLadebalken
extends Control
## W14/LOADING — der niedliche Ladebalken des Boot-Covers: AC-Papier-Kapsel
## (Ink-Outline + Boden-Lippe wie die Web-.btn-Optik) mit Möhren-Füllung und
## einem kleinen Möhren-Kopf samt Blattschopf an der Füllkante. Rein
## vektorgezeichnet (draw_*), damit er ohne weitere Assets überall skaliert.
##
## EHRLICHKEIT: `set_progress` setzt das ECHTE Ziel; die Anzeige gleitet nur
## HINTERHER (nie voraus) — der Balken zeigt nie mehr an, als wirklich
## geladen ist. Reduced Motion (set_animated(false)) springt direkt.

const PAPIER := Color("#FFFAF2")
const PAPIER_SCHATTEN := Color("#F6EAD8")
const INK := Color("#4A3B36")
const MOEHRE := Color("#FF8C42")
const MOEHRE_HELL := Color("#FFB374")
const MOEHRE_DUNKEL := Color("#E8702A")
const BLATT := Color("#7FBF6A")
const BLATT_DUNKEL := Color("#5E9C4C")

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
	var h := size.y
	var w := size.x
	if h <= 0.0 or w <= 0.0:
		return
	var radius := h / 2.0
	var outline := maxf(2.0, h * 0.11)
	# Kapsel: Ink-Outline, Papier-Fläche, Boden-Lippe (PAPIER_SCHATTEN).
	_kapsel(Rect2(Vector2.ZERO, size), radius, INK)
	var innen := Rect2(Vector2(outline, outline), size - Vector2(outline, outline) * 2.0)
	_kapsel(innen, radius - outline, PAPIER)
	var lippe_h := maxf(2.0, h * 0.14)
	var lippe := Rect2(
		Vector2(innen.position.x, innen.end.y - lippe_h), Vector2(innen.size.x, lippe_h)
	)
	_kapsel(lippe, lippe_h / 2.0, PAPIER_SCHATTEN)
	_fuellung(innen, radius, outline)


func _fuellung(innen: Rect2, radius: float, outline: float) -> void:
	var pad := maxf(1.5, outline * 0.6)
	var spur := Rect2(innen.position + Vector2(pad, pad), innen.size - Vector2(pad, pad) * 2.0)
	var min_w := spur.size.y
	var fuell_w := _anzeige * spur.size.x
	if fuell_w < 0.5:
		return
	fuell_w = maxf(fuell_w, min_w)
	var fuellung := Rect2(spur.position, Vector2(fuell_w, spur.size.y))
	_kapsel(fuellung, fuellung.size.y / 2.0, MOEHRE)
	# Glanz-Streifen oben + dunkler Boden: die Möhre wirkt rund statt flach.
	var glanz := Rect2(
		fuellung.position + Vector2(fuellung.size.y * 0.25, fuellung.size.y * 0.12),
		Vector2(
			maxf(0.0, fuellung.size.x - fuellung.size.y * 0.5), maxf(1.5, fuellung.size.y * 0.2)
		)
	)
	if glanz.size.x > 1.0:
		_kapsel(glanz, glanz.size.y / 2.0, MOEHRE_HELL)
	var boden := Rect2(
		fuellung.position + Vector2(0.0, fuellung.size.y * 0.72),
		Vector2(fuellung.size.x, fuellung.size.y * 0.28)
	)
	_kapsel(boden, boden.size.y / 2.0, MOEHRE_DUNKEL)
	_moehrenkopf(Vector2(fuellung.end.x, fuellung.position.y + fuellung.size.y / 2.0), radius)


## Der Füllkopf: eine kleine runde Möhre mit Blattschopf an der Füllkante.
func _moehrenkopf(spitze: Vector2, radius: float) -> void:
	var r := radius * 0.95
	# Blattschopf zuerst (liegt HINTER dem Möhren-Kopf).
	for blatt_info: Array in [[-0.55, BLATT_DUNKEL], [0.5, BLATT_DUNKEL], [0.0, BLATT]]:
		var neigung := float(blatt_info[0])
		var von := spitze + Vector2(neigung * r * 0.4, -r * 0.45)
		var bis := von + Vector2(neigung * r * 1.1, -r * 1.35)
		draw_line(von, bis, blatt_info[1], r * 0.5)
		draw_circle(bis, r * 0.26, blatt_info[1])
	draw_circle(spitze, r + maxf(1.5, r * 0.22), INK)
	draw_circle(spitze, r, MOEHRE)
	draw_circle(spitze + Vector2(-r * 0.28, -r * 0.3), r * 0.3, MOEHRE_HELL)


func _kapsel(rect: Rect2, radius: float, farbe: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = farbe
	box.set_corner_radius_all(int(maxf(0.0, radius)))
	draw_style_box(box, rect)
