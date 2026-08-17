class_name FotoRahmen
extends RefCounted
## W13C FOTOWERK (P1 Punkt 16, Web-Parität photoMode.js drawFrame, erweitert):
## 6 prozedurale Foto-Rahmen — alles GEZEICHNET (CanvasItem-Draw + Theme-Font),
## KEINE Bild-Assets. Die puren Anteile (Katalog, Rotation, Streu-Positionen,
## Polaroid-Geometrie) sind headless testbar; `Overlay` ist ein schlankes
## Control, das im Sucher lebt und beim Auslösen SICHTBAR bleibt — so wird der
## gewählte Rahmen in die gespeicherte Aufnahme mitgeknipst.
##
## Kontext-Schlüssel (alle optional): datum (Polaroid/Stempel), gruss
## (Postkarte, fertig lokalisiert), stempel (Stempel-Ecke), seed (Streu).

## Reihenfolge = Auswahl-Rotation im Sucher ("kein" zuerst).
const RAHMEN: Array[Dictionary] = [
	{"id": "kein", "label_key": "foto.rahmen.kein"},
	{"id": "polaroid", "label_key": "foto.rahmen.polaroid"},
	{"id": "herzen", "label_key": "foto.rahmen.herzen"},
	{"id": "sterne", "label_key": "foto.rahmen.sterne"},
	{"id": "postkarte", "label_key": "foto.rahmen.postkarte"},
	{"id": "filmstreifen", "label_key": "foto.rahmen.filmstreifen"},
	{"id": "stempel", "label_key": "foto.rahmen.stempel"},
]

## Polaroid: Papier + Tinte 1:1 aus photoMode.js drawFrame.
const POLAROID_PAPIER := Color("#FFF9F2")
const POLAROID_TINTE := Color("#4A3B36")
const POLAROID_RAND_ANTEIL := 0.045  # der Breite
const POLAROID_FUSS_ANTEIL := 0.14  # der Höhe (klassischer dicker Fuß)
## Sterne: Web-Konfetti-Palette; Herzchen: GOOBY-Rosa-Trio.
const STERN_FARBEN: Array[Color] = [
	Color("#FFD166"), Color("#F49CBB"), Color("#6FC3B8"), Color("#B9AEF0"), Color("#FFF6EC")
]
const HERZ_FARBEN: Array[Color] = [Color("#E4707E"), Color("#F49CBB"), Color("#FF7BA9")]
const STREU_SEED := 42  # Web-Parität: deterministisches Konfetti
const STREU_ANZAHL := 90
const STREU_BAND_ANTEIL := 0.075  # der Breite
## Postkarte: Creme-Rand + Luftpost-Streifen (rot/blau im Wechsel).
const POST_PAPIER := Color("#FFF6EC")
const POST_ROT := Color("#D6494F")
const POST_BLAU := Color("#3D6FB8")
## Filmstreifen: dunkles Band + helle Perforationslöcher.
const FILM_BAND := Color(0.09, 0.07, 0.11)
const FILM_LOCH := Color(0.97, 0.95, 0.9)
## Stempel-Ecke: halbtransparente Stempel-Tinte, leicht verdreht.
const STEMPEL_TINTE := Color(0.76, 0.27, 0.31, 0.85)


static func ids() -> Array[String]:
	var out: Array[String] = []
	for rahmen in RAHMEN:
		out.append(str(rahmen["id"]))
	return out


static func label_key(rahmen_id: String) -> String:
	for rahmen in RAHMEN:
		if str(rahmen["id"]) == rahmen_id:
			return str(rahmen["label_key"])
	return ""


static func ist_gueltig(rahmen_id: String) -> bool:
	return not label_key(rahmen_id).is_empty()


## Auswahl-Rotation: der nächste Rahmen im Katalog (unbekannt → erster).
static func naechster(rahmen_id: String) -> String:
	var liste := ids()
	var index := liste.find(rahmen_id)
	return liste[(index + 1) % liste.size()]


## Polaroid-Geometrie (pur, für Painter UND Tests).
static func polaroid_masse(size: Vector2) -> Dictionary:
	return {
		"rand": size.x * POLAROID_RAND_ANTEIL,
		"fuss": size.y * POLAROID_FUSS_ANTEIL,
	}


## Deterministisches Rand-Konfetti (Web-LCG seed*1664525+1013904223): Einträge
## {pos, radius, rot, farbe} entlang der 4 Kanten (i%4), alle im `band`.
static func streu(size: Vector2, band: float, anzahl: int, start_seed: int) -> Array[Dictionary]:
	var zustand := start_seed & 0xFFFFFFFF
	var out: Array[Dictionary] = []
	for i in anzahl:
		zustand = _lcg(zustand)
		var r1 := _lcg01(zustand)
		zustand = _lcg(zustand)
		var r2 := _lcg01(zustand)
		zustand = _lcg(zustand)
		var farbe := int(_lcg01(zustand) * 97.0)
		zustand = _lcg(zustand)
		var radius := (0.012 + _lcg01(zustand) * 0.014) * size.x
		zustand = _lcg(zustand)
		var rot := _lcg01(zustand) * PI
		var pos := Vector2.ZERO
		match i % 4:
			0:
				pos = Vector2(r1 * size.x, r2 * band)
			1:
				pos = Vector2(r1 * size.x, size.y - r2 * band)
			2:
				pos = Vector2(r1 * band, r2 * size.y)
			_:
				pos = Vector2(size.x - r1 * band, r2 * size.y)
		out.append({"pos": pos, "radius": radius, "rot": rot, "farbe": farbe})
	return out


## Web-LCG (photoMode.js): 32-Bit-Schritt + Normierung auf [0..1).
static func _lcg(zustand: int) -> int:
	return (zustand * 1664525 + 1013904223) & 0xFFFFFFFF


static func _lcg01(zustand: int) -> float:
	return float(zustand) / 4294967296.0


## 5-zackiger Stern (10 Punkte, Innenradius 0,45 — Web-Parität).
static func stern_punkte(radius: float) -> PackedVector2Array:
	var punkte := PackedVector2Array()
	for i in 10:
		var rr := radius if i % 2 == 0 else radius * 0.45
		var winkel := PI / 5.0 * float(i) - PI / 2.0
		punkte.append(Vector2(cos(winkel), sin(winkel)) * rr)
	return punkte


## Herz als Polygon (parametrische Herzkurve, 24 Stützpunkte).
static func herz_punkte(radius: float) -> PackedVector2Array:
	var punkte := PackedVector2Array()
	for i in 24:
		var t := TAU * float(i) / 24.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		punkte.append(Vector2(x, y) * (radius / 16.0))
	return punkte


## Rahmen auf ein CanvasItem malen (Sucher-Overlay; wird mitgeknipst, weil
## das Overlay beim Auslösen sichtbar bleibt).
static func zeichne(ci: CanvasItem, size: Vector2, rahmen_id: String, kontext: Dictionary) -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	match rahmen_id:
		"polaroid":
			_male_polaroid(ci, size, kontext)
		"herzen":
			_male_streu(ci, size, kontext, true)
		"sterne":
			_male_streu(ci, size, kontext, false)
		"postkarte":
			_male_postkarte(ci, size, kontext)
		"filmstreifen":
			_male_filmstreifen(ci, size)
		"stempel":
			_male_stempel(ci, size, kontext)
		_:
			pass


# ── Painter (nur Draw-Aufrufe, Geometrie kommt aus den puren Helfern) ─────────


static func _male_polaroid(ci: CanvasItem, size: Vector2, kontext: Dictionary) -> void:
	var masse := polaroid_masse(size)
	var rand := float(masse["rand"])
	var fuss := float(masse["fuss"])
	ci.draw_rect(Rect2(0.0, 0.0, size.x, rand), POLAROID_PAPIER)
	ci.draw_rect(Rect2(0.0, 0.0, rand, size.y), POLAROID_PAPIER)
	ci.draw_rect(Rect2(size.x - rand, 0.0, rand, size.y), POLAROID_PAPIER)
	ci.draw_rect(Rect2(0.0, size.y - fuss, size.x, fuss), POLAROID_PAPIER)
	var schrift := _schrift(ci)
	var gross := maxi(int(size.y * 0.045), 10)
	var text := str(kontext.get("datum", ""))
	var basis := Vector2(0.0, size.y - fuss * 0.5 + float(gross) * 0.35)
	ci.draw_string(schrift, basis, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, gross, POLAROID_TINTE)
	# Herzchen rechts neben der Handschrift-Zeile (Web-Gag, als Pfad-Kunst).
	var breite := schrift.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, gross).x
	var hr := size.y * 0.014
	var herz_pos := Vector2(size.x / 2.0 + breite / 2.0 + hr * 2.2, size.y - fuss * 0.5)
	_male_polygon(ci, herz_pos, 0.0, herz_punkte(hr), HERZ_FARBEN[0])


static func _male_streu(ci: CanvasItem, size: Vector2, kontext: Dictionary, herzen: bool) -> void:
	var band := size.x * STREU_BAND_ANTEIL
	var start_seed := int(kontext.get("seed", STREU_SEED))
	for eintrag in streu(size, band, STREU_ANZAHL, start_seed):
		var radius := float(eintrag["radius"])
		var punkte := herz_punkte(radius) if herzen else stern_punkte(radius)
		var palette := HERZ_FARBEN if herzen else STERN_FARBEN
		var farbe: Color = palette[int(eintrag["farbe"]) % palette.size()]
		_male_polygon(ci, eintrag["pos"], float(eintrag["rot"]), punkte, farbe)


static func _male_postkarte(ci: CanvasItem, size: Vector2, kontext: Dictionary) -> void:
	var rand := size.x * 0.03
	ci.draw_rect(Rect2(0.0, 0.0, size.x, rand), POST_PAPIER)
	ci.draw_rect(Rect2(0.0, size.y - rand, size.x, rand), POST_PAPIER)
	ci.draw_rect(Rect2(0.0, 0.0, rand, size.y), POST_PAPIER)
	ci.draw_rect(Rect2(size.x - rand, 0.0, rand, size.y), POST_PAPIER)
	# Luftpost-Streifen: rote/blaue Balken im Wechsel, alle 4 Kanten.
	var schritt := rand * 2.2
	var balken := schritt * 0.55
	var dicke := rand * 0.5
	var index := 0
	var x := rand
	while x + balken < size.x - rand:
		var farbe := POST_ROT if index % 2 == 0 else POST_BLAU
		ci.draw_rect(Rect2(x, rand * 0.25, balken, dicke), farbe)
		ci.draw_rect(Rect2(x, size.y - rand * 0.75, balken, dicke), farbe)
		x += schritt
		index += 1
	index = 0
	var y := rand
	while y + balken < size.y - rand:
		var farbe := POST_ROT if index % 2 == 0 else POST_BLAU
		ci.draw_rect(Rect2(rand * 0.25, y, dicke, balken), farbe)
		ci.draw_rect(Rect2(size.x - rand * 0.75, y, dicke, balken), farbe)
		y += schritt
		index += 1
	# „Grüße aus …“-Schriftzug oben links, mit weichem Schatten fürs Foto.
	var schrift := _schrift(ci)
	var gross := maxi(int(size.y * 0.058), 12)
	var gruss := str(kontext.get("gruss", ""))
	var pos := Vector2(rand * 2.2, rand * 2.0 + float(gross))
	var links := HORIZONTAL_ALIGNMENT_LEFT
	var schatten := Color(0.0, 0.0, 0.0, 0.4)
	ci.draw_string(schrift, pos + Vector2(2.0, 2.0), gruss, links, -1, gross, schatten)
	ci.draw_string(schrift, pos, gruss, links, -1, gross, POST_PAPIER)


static func _male_filmstreifen(ci: CanvasItem, size: Vector2) -> void:
	var band := size.y * 0.12
	ci.draw_rect(Rect2(0.0, 0.0, size.x, band), FILM_BAND)
	ci.draw_rect(Rect2(0.0, size.y - band, size.x, band), FILM_BAND)
	var loch_b := size.x * 0.042
	var loch_h := band * 0.42
	var schritt := loch_b * 2.0
	var x := loch_b * 0.5
	while x + loch_b < size.x:
		ci.draw_rect(Rect2(x, (band - loch_h) / 2.0, loch_b, loch_h), FILM_LOCH)
		var unten_y := size.y - band + (band - loch_h) / 2.0
		ci.draw_rect(Rect2(x, unten_y, loch_b, loch_h), FILM_LOCH)
		x += schritt


static func _male_stempel(ci: CanvasItem, size: Vector2, kontext: Dictionary) -> void:
	var radius := size.x * 0.14
	var pos := Vector2(size.x - radius * 1.4, size.y - radius * 1.4)
	ci.draw_set_transform(pos, -0.22, Vector2.ONE)
	ci.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, STEMPEL_TINTE, radius * 0.06, true)
	ci.draw_arc(Vector2.ZERO, radius * 0.8, 0.0, TAU, 48, STEMPEL_TINTE, radius * 0.03, true)
	var schrift := _schrift(ci)
	var gross := maxi(int(radius * 0.24), 9)
	var text := str(kontext.get("stempel", ""))
	var datum := str(kontext.get("datum", ""))
	var text_basis := Vector2(-radius, -float(gross) * 0.15)
	var breite := radius * 2.0
	ci.draw_string(
		schrift, text_basis, text, HORIZONTAL_ALIGNMENT_CENTER, breite, gross, STEMPEL_TINTE
	)
	var datum_gross := maxi(int(float(gross) * 0.7), 8)
	var datum_basis := Vector2(-radius, float(gross) * 0.95)
	ci.draw_string(
		schrift, datum_basis, datum, HORIZONTAL_ALIGNMENT_CENTER, breite, datum_gross, STEMPEL_TINTE
	)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _male_polygon(
	ci: CanvasItem, pos: Vector2, rot: float, punkte: PackedVector2Array, farbe: Color
) -> void:
	ci.draw_set_transform(pos, rot, Vector2.ONE)
	ci.draw_colored_polygon(punkte, farbe)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _schrift(ci: CanvasItem) -> Font:
	if ci is Control:
		var schrift := (ci as Control).get_theme_default_font()
		if schrift != null:
			return schrift
	return ThemeDB.fallback_font


## Sucher-Overlay: liegt UNTER der Bedien-UI und bleibt beim Auslösen
## sichtbar — deshalb landet der Rahmen automatisch in der Aufnahme.
class Overlay:
	extends Control

	var rahmen_id := "kein":
		set(value):
			rahmen_id = value
			queue_redraw()
	var kontext: Dictionary = {}:
		set(value):
			kontext = value
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	func _draw() -> void:
		FotoRahmen.zeichne(self, size, rahmen_id, kontext)
