class_name HomeIcons
extends RefCounted
## Gezeichnete Icons für Haus/Werkstatt/Garten/Goobay — KEINE rohen Emojis
## im UI (Projektregel): jedes Symbol ist hier bewusst als Form definiert
## und wird zur Laufzeit in eine kleine Textur gemalt (gecacht).
##
## Farben kommen ausschließlich aus den AC-Theme-Tokens (AcTokens), damit
## die Icons zum globalen Theme passen und nirgends eine Farbe hartkodiert
## in einer UI-Datei landet.

const SIZE := 32
## Stimmungsstufen des Goobay-Käufers (0 = bester Laune … 4 = sauer).
const STIMMUNG_FARBEN: Array[Color] = [
	AcTokens.LEAF, AcTokens.LEAF_DARK, AcTokens.YELLOW, AcTokens.STAT_HUNGER, AcTokens.DANGER
]

static var _cache: Dictionary = {}


## Icon-Textur zu einer Id (gecacht). Unbekannte Id → neutraler Punkt.
static func texture(icon_id: String) -> ImageTexture:
	if _cache.has(icon_id):
		return _cache[icon_id]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw(img, icon_id)
	var tex := ImageTexture.create_from_image(img)
	_cache[icon_id] = tex
	return tex


## Stimmungs-Icon des Käufers (Doc D §5.4 — das lesbare Spiel-Signal).
static func stimmung(stufe: int) -> ImageTexture:
	return texture("stimmung%d" % clampi(stufe, 0, STIMMUNG_FARBEN.size() - 1))


## Fertiges TextureRect für UI-Zeilen.
static func node(icon_id: String, px := 24) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture(icon_id)
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func reset_cache() -> void:
	_cache = {}


static func _draw(img: Image, icon_id: String) -> void:
	if icon_id.begins_with("stimmung"):
		_gesicht(img, int(icon_id.substr(8)))
		return
	match icon_id:
		"stock":
			_stab(img, AcTokens.INK, 0.62)
		"blatt":
			_kreis(img, Vector2(16, 16), 11.0, AcTokens.LEAF)
			_stab(img, AcTokens.LEAF_DARK, 0.28)
		"holz":
			_rechteck(img, Rect2(5, 11, 22, 10), AcTokens.INK_SOFT)
			_kreis(img, Vector2(7, 16), 4.0, AcTokens.YELLOW_DARK)
		"eisen":
			_rechteck(img, Rect2(4, 13, 24, 8), AcTokens.INK_FAINT)
			_rechteck(img, Rect2(4, 13, 24, 3), AcTokens.SKY_SOFT)
		"naegel":
			for x in [9, 16, 23]:
				_rechteck(img, Rect2(x - 1, 10, 3, 14), AcTokens.INK_FAINT)
				_rechteck(img, Rect2(x - 4, 8, 9, 3), AcTokens.INK_SOFT)
		"muenze":
			_kreis(img, Vector2(16, 16), 12.0, AcTokens.GOLD)
			_kreis(img, Vector2(16, 16), 8.0, AcTokens.YELLOW_DARK)
		"wasser":
			_kreis(img, Vector2(16, 19), 9.0, AcTokens.STAT_HYGIENE)
			_dreieck(img, Vector2(16, 5), 9.0, AcTokens.STAT_HYGIENE)
		"wind":
			for y in [10, 16, 22]:
				_rechteck(img, Rect2(4, y, 20 - (y - 10), 3), AcTokens.INK_FAINT)
		"sonne":
			_kreis(img, Vector2(16, 16), 8.0, AcTokens.YELLOW)
			for i in 8:
				var winkel := TAU * i / 8.0
				_kreis(
					img,
					Vector2(16, 16) + Vector2(cos(winkel), sin(winkel)) * 12.0,
					2.0,
					AcTokens.YELLOW_DARK
				)
		"schatten":
			_kreis(img, Vector2(16, 16), 11.0, AcTokens.SKY_SOFT)
			_halbkreis(img, Vector2(16, 16), 11.0, AcTokens.INK_SOFT)
		"gewaechshaus":
			_rechteck(img, Rect2(6, 14, 20, 13), AcTokens.SKY_SOFT)
			_dreieck(img, Vector2(16, 4), 11.0, AcTokens.TEAL)
			_rechteck(img, Rect2(14, 19, 5, 8), AcTokens.TEAL_DARK)
		"schloss":
			_rechteck(img, Rect2(8, 15, 16, 12), AcTokens.INK_SOFT)
			_ring(img, Vector2(16, 13), 7.0, 3.0, AcTokens.INK_FAINT)
		"lager":
			_rechteck(img, Rect2(5, 10, 22, 16), AcTokens.YELLOW_DARK)
			_rechteck(img, Rect2(14, 10, 4, 16), AcTokens.PAPER_SHADE)
		"hammer":
			_rechteck(img, Rect2(9, 12, 4, 16), AcTokens.YELLOW_DARK)
			_rechteck(img, Rect2(6, 5, 14, 8), AcTokens.INK_FAINT)
			_rechteck(img, Rect2(20, 7, 6, 4), AcTokens.INK_SOFT)
		"pfeil_hoch":
			_dreieck(img, Vector2(16, 6), 10.0, AcTokens.LEAF_DARK)
			_rechteck(img, Rect2(13, 16, 6, 11), AcTokens.LEAF_DARK)
		"hand":
			_kreis(img, Vector2(16, 18), 9.0, AcTokens.PINK)
			_rechteck(img, Rect2(12, 5, 3, 10), AcTokens.PINK_DARK)
			_rechteck(img, Rect2(17, 5, 3, 10), AcTokens.PINK_DARK)
		"kreuz":
			_diagonale(img, AcTokens.DANGER, false)
			_diagonale(img, AcTokens.DANGER, true)
		_:
			_kreis(img, Vector2(16, 16), 8.0, AcTokens.INK_FAINT)


## Käufer-Gesicht: Farbe UND Mundkurve ändern sich (doppelt lesbar).
static func _gesicht(img: Image, stufe: int) -> void:
	var index := clampi(stufe, 0, STIMMUNG_FARBEN.size() - 1)
	_kreis(img, Vector2(16, 16), 14.0, STIMMUNG_FARBEN[index])
	_kreis(img, Vector2(11, 13), 2.0, AcTokens.INK)
	_kreis(img, Vector2(21, 13), 2.0, AcTokens.INK)
	var kruemmung := 5.0 - index * 2.5
	for x in range(9, 24):
		var t := (x - 16.0) / 7.0
		var y := 21.0 + kruemmung * (1.0 - t * t) - kruemmung * 0.5
		_kreis(img, Vector2(x, y), 1.2, AcTokens.INK)


static func _kreis(img: Image, mitte: Vector2, radius: float, farbe: Color) -> void:
	var r2 := radius * radius
	for y in SIZE:
		for x in SIZE:
			if Vector2(x, y).distance_squared_to(mitte) <= r2:
				img.set_pixel(x, y, farbe)


static func _ring(img: Image, mitte: Vector2, radius: float, dicke: float, farbe: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(mitte)
			if d <= radius and d >= radius - dicke and y <= mitte.y:
				img.set_pixel(x, y, farbe)


static func _halbkreis(img: Image, mitte: Vector2, radius: float, farbe: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			if x >= mitte.x and Vector2(x, y).distance_to(mitte) <= radius:
				img.set_pixel(x, y, farbe)


static func _rechteck(img: Image, rect: Rect2, farbe: Color) -> void:
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
				img.set_pixel(x, y, farbe)


static func _dreieck(img: Image, spitze: Vector2, hoehe: float, farbe: Color) -> void:
	for i in int(hoehe):
		var y := int(spitze.y) + i
		if y < 0 or y >= SIZE:
			continue
		for x in range(int(spitze.x - i), int(spitze.x + i + 1)):
			if x >= 0 and x < SIZE:
				img.set_pixel(x, y, farbe)


static func _stab(img: Image, farbe: Color, dicke: float) -> void:
	for i in SIZE:
		for d in range(-int(dicke * 4), int(dicke * 4) + 1):
			var x := clampi(i + d, 0, SIZE - 1)
			img.set_pixel(x, SIZE - 1 - i, farbe)


static func _diagonale(img: Image, farbe: Color, gespiegelt: bool) -> void:
	for i in range(6, SIZE - 6):
		for d in [-2, -1, 0, 1, 2]:
			var x := clampi(i + d, 0, SIZE - 1)
			var y := (SIZE - 1 - i) if gespiegelt else i
			img.set_pixel(x, clampi(y, 0, SIZE - 1), farbe)
