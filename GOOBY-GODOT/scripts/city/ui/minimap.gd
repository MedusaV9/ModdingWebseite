class_name CityMinimap
extends Control
## Minimap mit Orts-Pins (Doc E §1.4 „Wo bin ich, wo will ich hin?“): eine
## kleine Karten-Kachel oben links im Fahr-HUD. Gezeichnet wird direkt in
## `_draw` — kein Viewport, keine zweite Kamera, kein Render-Target: auf dem
## Handy kostet die Karte damit nur ein paar Rects pro Frame.
##
## Farben kommen aus dem Theme (AcTokens); die Pin-Farbe eines Orts ist sein
## Fassaden-Tint aus `city_map.json`, damit Pin und Haus dieselbe Farbe haben.
##
## G4/P16 (ui-reisen MITTEL 7): Zeichnung + Projektion binden an die REALE
## Kante statt an die Konstante — GOOBERANDO skaliert die Live-Karte damit
## dynamisch (`kachel` setzen), das Fahr-HUD behält seine 148er-Kachel.

## Kantenlänge der Karten-Kachel (px) — Default-/Fallback-Wert.
const GROESSE := 148.0
const RAND := 10.0
const PIN_R := 5.0
const SPIELER_R := 5.5
## Ein Pin blinkt nicht — er wächst, wenn man davorsteht.
const PIN_AKTIV_R := 8.0

## Wunsch-Kante in px (vor add_child setzen); _ready übernimmt sie als
## Mindestgröße, alles Zeichnen skaliert relativ zu GROESSE mit.
var kachel := GROESSE

var karte: CityMap

var _spieler := Vector3.ZERO
var _heading := 0.0
var _aktiv := ""
var _pins: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(kachel, kachel)
	size = size.max(Vector2(kachel, kachel))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_sammle_pins()


## Reale Kantenlänge: kurze Seite des gelegten Rects, sonst der Wunschwert.
## (Vertrag: ohne Layout — z. B. Tests ohne Tree — bleibt es die Kachel.)
func kante() -> float:
	var kurz := minf(size.x, size.y)
	return kurz if kurz > 0.0 else kachel


## Karte NACH dem Setzen von `karte` neu aufbauen (Tests/Live-Reload).
func aktualisiere_pins() -> void:
	_sammle_pins()
	queue_redraw()


## Spielerposition + Blickrichtung (Weltkoordinaten) übernehmen.
func setze_spieler(pos: Vector3, heading: float) -> void:
	_spieler = pos
	_heading = heading
	queue_redraw()


## Ort, vor dem gerade geparkt wird ("" = keiner) — sein Pin wird größer.
func setze_aktiv(ort_id: String) -> void:
	if _aktiv == ort_id:
		return
	_aktiv = ort_id
	queue_redraw()


func pins() -> Array[Dictionary]:
	return _pins


## Welt-XZ → Kachel-Pixel (PURE bis auf die reale Kachelkante).
func welt_zu_pixel(pos: Vector3) -> Vector2:
	var k := kante()
	if karte == null:
		return Vector2(k, k) * 0.5
	var halb := karte.welt_halb()
	var rand := RAND * (k / GROESSE)
	var innen := k - rand * 2.0
	var u := clampf((pos.x + halb.x) / (halb.x * 2.0), 0.0, 1.0)
	var v := clampf((pos.z + halb.y) / (halb.y * 2.0), 0.0, 1.0)
	return Vector2(rand + u * innen, rand + v * innen)


func _draw() -> void:
	var k := kante()
	var faktor := k / GROESSE
	var flaeche := Rect2(Vector2.ZERO, Vector2(k, k))
	draw_rect(flaeche, AcTokens.FROST, true)
	draw_rect(flaeche, AcTokens.OUTLINE_SOFT, false, 2.0 * faktor)
	_zeichne_strassen(faktor)
	for pin in _pins:
		var mitte: Vector2 = welt_zu_pixel(pin["welt"])
		var radius := (PIN_AKTIV_R if str(pin["id"]) == _aktiv else PIN_R) * faktor
		draw_circle(mitte, radius + 1.5 * faktor, AcTokens.PAPER)
		draw_circle(mitte, radius, pin["farbe"])
	_zeichne_spieler(faktor)


## Straßen-Lattice als dünne Linien — nur Reihen/Spalten, keine Tiles.
func _zeichne_strassen(faktor: float) -> void:
	if karte == null:
		return
	var gezeichnet := {}
	for tile in karte.strassen_tiles():
		for schritt: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nachbar := tile + schritt
			if not karte.ist_strasse(nachbar):
				continue
			var key := "%d_%d_%d_%d" % [tile.x, tile.y, nachbar.x, nachbar.y]
			if gezeichnet.has(key):
				continue
			gezeichnet[key] = true
			draw_line(
				welt_zu_pixel(karte.tile_zu_welt(tile)),
				welt_zu_pixel(karte.tile_zu_welt(nachbar)),
				AcTokens.TRACK_SOFT,
				3.0 * faktor
			)


## Spieler als kleines Dreieck in Fahrtrichtung (+Z = Süden = Bild unten).
func _zeichne_spieler(faktor: float) -> void:
	var mitte := welt_zu_pixel(_spieler)
	var r := SPIELER_R * faktor
	var vorn := Vector2(sin(_heading), cos(_heading))
	var quer := Vector2(-vorn.y, vorn.x)
	var punkte := PackedVector2Array(
		[
			mitte + vorn * r * 1.6,
			mitte - vorn * r + quer * r * 0.8,
			mitte - vorn * r - quer * r * 0.8,
		]
	)
	draw_colored_polygon(punkte, AcTokens.PINK)


func _sammle_pins() -> void:
	_pins.clear()
	if karte == null:
		return
	for eintrag: Dictionary in karte.orte():
		var fassade: Dictionary = eintrag.get("fassade", {})
		var hex := str(fassade.get("tint", ""))
		(
			_pins
			. append(
				{
					"id": str(eintrag.get("id", "")),
					"welt": karte.parkplatz_welt(str(eintrag.get("id", ""))),
					"farbe": Color(hex) if not hex.is_empty() else AcTokens.TEAL,
				}
			)
		)
	_pins.append({"id": "zuhause", "welt": karte.parkplatz_welt("zuhause"), "farbe": AcTokens.LEAF})
