class_name McGoobySchichtDeko
extends Control
## W20 Stations-Deko der McGooby-Schicht (Top-10 #1, Teil b): je Station
## 1–2 kleine prozedurale Szenen-Details, damit sich die vier Tabs auch
## OPTISCH unterscheiden — reine _draw-Primitive im Gooby-Pastell-Look
## (ort_requisiten-Grammatik: sanfte Tints, keine neuen Assets):
##   grill      Rost-Platte + Flammen-Flacker dahinter (animiert),
##   belegen    Ticket-Turm-Podest: Teller auf Fuß + Mini-Zutaten-Stapel,
##   fritteuse  Öl-Becken + Korb-Gitter + sparsame Blubber-Blasen (animiert),
##   shake      Mixer + Becher-Regal mit drei Pastell-Bechern.
## Low-End-fair (llvmpipe): neu gezeichnet wird NUR, wenn die Deko sichtbar
## UND animiert ist (Grill/Fritteuse); Reduced Motion friert die Animation
## als statisches Bild ein (RewardFx.reduced_motion-Gate). Zeit ist ein
## einfacher Akkumulator (pinnbar in Tests), Zufall gibt es keinen —
## Flacker/Blasen laufen deterministisch über Sinus/Phasen-Konstanten.

## Wunschgröße in Design-px (Szene skaliert über skaliere(f)).
const BASIS := Vector2(200.0, 60.0)

## Pastell-Palette (abgestimmt auf die Runden-Skins in schicht_ui_teile).
const BRAUN := Color("#7A5230")
const CREME := Color("#FFF6E8")
const HELLBRAUN := Color("#D9C6A5")
const FLAMME := Color("#F2A65A")
const FLAMME_HELL := Color("#F5C97B")
const OEL := Color("#F4E7C0")
const OEL_RAND := Color("#E8C25A")
const GRUEN := Color("#8FBF6C")
const ROSA := Color("#F7C6D9")
const MINT := Color("#59C9B9")

## Blasen-/Flammen-Phasen (deterministisch, kein RNG — Doc §10.4-Geist).
const PHASEN: Array[float] = [0.0, 0.37, 0.61, 0.83]

var station_id := "grill"
## Animations-Zeit (Sekunden) — läuft nur sichtbar + ohne Reduced Motion;
## Tests pinnen sie direkt (deterministisches Bild).
var zeit := 0.0


## Fabrik: Deko bauen und als OBERSTES Kind der Stations-Box einhängen
## (die Apparatur steht über dem großen Stations-Knopf).
static func haenge_oben(box: Container, station: String) -> McGoobySchichtDeko:
	var deko := McGoobySchichtDeko.new()
	deko.name = station.capitalize() + "Deko"
	deko.station_id = station
	deko.custom_minimum_size = BASIS
	deko.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(deko)
	box.move_child(deko, 0)
	return deko


## Metrics-Anschluss der Szene (_apply_metrics): Design-px × Faktor f.
func skaliere(f: float) -> void:
	custom_minimum_size = BASIS * maxf(0.5, f)
	queue_redraw()


func _process(delta: float) -> void:
	# Nur Grill (Flammen) und Fritteuse (Blasen) leben — und auch die nur,
	# wenn sie wirklich zu sehen sind und Bewegung erwünscht ist.
	if station_id != "grill" and station_id != "fritteuse":
		return
	if not is_visible_in_tree() or RewardFx.reduced_motion(self):
		return
	zeit += delta
	queue_redraw()


func _draw() -> void:
	match station_id:
		"belegen":
			_zeichne_belegen()
		"fritteuse":
			_zeichne_fritteuse()
		"shake":
			_zeichne_shake()
		_:
			_zeichne_grill()


## Grill: warme Flammen flackern HINTER der dunklen Rost-Platte hervor.
func _zeichne_grill() -> void:
	var w := size.x
	var h := size.y
	var platte := Rect2(w * 0.18, h * 0.30, w * 0.64, h * 0.42)
	for i in 3:
		var flacker := 1.0 + 0.28 * sin(zeit * 6.0 + PHASEN[i] * TAU)
		var fx := platte.position.x + platte.size.x * (0.22 + 0.28 * i)
		var fy := platte.end.y + h * 0.06
		draw_circle(Vector2(fx, fy), h * 0.13 * flacker, FLAMME)
		draw_circle(Vector2(fx, fy - h * 0.05 * flacker), h * 0.07 * flacker, FLAMME_HELL)
	draw_rect(platte, BRAUN)
	for i in 4:
		var y := platte.position.y + platte.size.y * (0.2 + 0.2 * i)
		var hell := Color(CREME, 0.30)
		draw_line(Vector2(platte.position.x, y), Vector2(platte.end.x, y), hell, 2.0)


## Belegstation: Podest (Fuß + Teller) mit Mini-Zutaten-Stapel obendrauf.
func _zeichne_belegen() -> void:
	var w := size.x
	var h := size.y
	var mitte := w * 0.5
	draw_rect(Rect2(mitte - w * 0.05, h * 0.62, w * 0.10, h * 0.28), HELLBRAUN)
	draw_rect(Rect2(mitte - w * 0.22, h * 0.54, w * 0.44, h * 0.10), CREME)
	draw_circle(Vector2(mitte - w * 0.22, h * 0.59), h * 0.05, CREME)
	draw_circle(Vector2(mitte + w * 0.22, h * 0.59), h * 0.05, CREME)
	# Stapel: Brötchen-Deckel, Salat, Patty, Brötchen-Boden (flache Bänder).
	draw_rect(Rect2(mitte - w * 0.13, h * 0.44, w * 0.26, h * 0.09), OEL_RAND)
	draw_rect(Rect2(mitte - w * 0.15, h * 0.36, w * 0.30, h * 0.07), GRUEN)
	draw_rect(Rect2(mitte - w * 0.13, h * 0.28, w * 0.26, h * 0.07), BRAUN)
	draw_circle(Vector2(mitte, h * 0.24), h * 0.10, OEL_RAND)


## Fritteuse: Öl-Becken mit Korb-Gitter, sparsame Blasen steigen auf.
func _zeichne_fritteuse() -> void:
	var w := size.x
	var h := size.y
	var becken := Rect2(w * 0.22, h * 0.34, w * 0.56, h * 0.44)
	draw_rect(becken, OEL)
	draw_line(becken.position, Vector2(becken.end.x, becken.position.y), OEL_RAND, 3.0)
	var korb := Rect2(w * 0.30, h * 0.22, w * 0.28, h * 0.34)
	draw_rect(korb, Color(BRAUN, 0.85), false, 2.5)
	for i in 3:
		var x := korb.position.x + korb.size.x * (0.25 + 0.25 * i)
		draw_line(Vector2(x, korb.position.y), Vector2(x, korb.end.y), Color(BRAUN, 0.5), 1.5)
	draw_line(korb.position + Vector2(korb.size.x, 0.0), Vector2(w * 0.72, h * 0.10), BRAUN, 2.5)
	for i in PHASEN.size():
		var phase := fposmod(zeit * 0.45 + PHASEN[i], 1.0)
		var bx := becken.position.x + becken.size.x * (0.15 + 0.24 * i)
		var by := becken.end.y - becken.size.y * phase
		# Blasen als braune Ringe: gefüllte Creme-Kreise gingen auf dem
		# blassen Öl optisch unter (Beleg-Screenshot-Befund W20).
		var blase := Color(BRAUN, 0.55 * (1.0 - phase))
		draw_arc(Vector2(bx, by), h * 0.045, 0.0, TAU, 10, blase, 1.8)


## Shake-Bar: Mixer links, Becher-Regal mit drei Pastell-Bechern rechts.
func _zeichne_shake() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(w * 0.16, h * 0.34, w * 0.14, h * 0.44), MINT)
	draw_circle(Vector2(w * 0.23, h * 0.30), w * 0.055, Color(MINT, 0.85))
	draw_rect(Rect2(w * 0.13, h * 0.78, w * 0.20, h * 0.10), HELLBRAUN)
	draw_rect(Rect2(w * 0.42, h * 0.66, w * 0.44, h * 0.06), HELLBRAUN)
	# Goldgelb statt Creme in der Mitte: ein Creme-Becher verschwand vor
	# der Creme-Tapete (Beleg-Screenshot-Befund W20); dünne Kontur trägt.
	var becher_farben: Array[Color] = [ROSA, OEL_RAND, MINT]
	for i in 3:
		var bx := w * (0.46 + 0.14 * i)
		var becher := Rect2(bx, h * 0.38, w * 0.09, h * 0.28)
		draw_rect(becher, becher_farben[i])
		draw_rect(becher, Color(BRAUN, 0.35), false, 1.5)
		draw_line(Vector2(bx + w * 0.045, h * 0.38), Vector2(bx + w * 0.075, h * 0.22), BRAUN, 2.0)
