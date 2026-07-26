class_name CustomizeIcons
extends RefCounted
## Prozedurale Vorschaubilder für die Options-Kacheln des Gestalten-Screens
## (HAUS-CUSTOM, Regel: „Vorschaubilder prozedural erzeugen, kein
## Extra-Asset-Wildwuchs"). Flächen-Optionen (Tapeten/Böden/Grundstück/Wege)
## zeigen ihr getöntes Muster (CustomizeMaterials.preview_texture), alle
## anderen bekommen einfache gezeichnete Glyphen (Dachform, Briefkasten,
## Vordach, Zaun, Hausnummern-Schild) in der aktuellen Farbe.

const PX := 96
const HINTERGRUND := Color("#FFFAF2")
const KONTUR := Color("#4A3B36")

static var _cache: Dictionary = {}


## Kachelbild einer Katalog-Option in einer Palettenfarbe.
static func option_preview(art: String, id: String, farb_id: String) -> ImageTexture:
	var def := CustomizeCatalog.def(art, id)
	var muster := str(def.get("muster", ""))
	if muster != "":
		return CustomizeMaterials.preview_texture(muster, farb_id, PX)
	var key := "%s|%s|%s" % [art, id, farb_id]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	img.fill(HINTERGRUND)
	var farbe := CustomizeMaterials.farbe(farb_id)
	match art:
		"dachForm":
			_dachform(img, id, farbe)
		"hausnummer":
			_hausnummer(img, id)
		"briefkasten":
			_briefkasten(img, id, farbe)
		"vordach":
			_vordach(img, id, farbe)
		"zaun":
			_zaun(img, id, farbe)
		"weg":
			_leer(img)
		"grundBoden":
			_leer(img)
		_:
			_leer(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func reset_cache() -> void:
	_cache = {}


# ── Glyphen ──────────────────────────────────────────────────────────────────


## „Keins"-Kachel: dezenter Schrägstrich.
static func _leer(img: Image) -> void:
	for i in PX:
		for b in 4:
			var x := i
			var y := PX - 1 - i + b - 2
			if y >= 0 and y < PX:
				img.set_pixel(x, y, Color("#CFCBC4"))


static func _dachform(img: Image, id: String, farbe: Color) -> void:
	var dunkel := farbe.darkened(0.2)
	match id:
		"walm":
			_trapez(img, 14, 60, 82, 60, 34, 30, 62, 30, farbe)
			_rect(img, 10, 60, 86, 66, dunkel)
		"flach":
			_rect(img, 14, 40, 82, 52, farbe)
			_rect(img, 10, 52, 86, 58, dunkel)
		_:
			_trapez(img, 14, 62, 82, 62, 47, 24, 49, 24, farbe)
			_rect(img, 10, 62, 86, 68, dunkel)
	_rect(img, 26, 68, 70, 86, Color("#FFF6EC"))


static func _hausnummer(img: Image, id: String) -> void:
	match id:
		"emaille":
			_rect(img, 24, 26, 72, 70, Color("#4A6FA5"))
			_rect(img, 28, 30, 68, 66, Color("#5C81B7"))
			_rect(img, 44, 40, 52, 58, Color("#FFFFFF"))
		"modern":
			_rect(img, 34, 18, 62, 78, Color("#55514B"))
			_rect(img, 44, 36, 52, 62, Color("#FFFFFF"))
		_:
			_rect(img, 22, 28, 74, 68, Color("#C9A36B"))
			_rect(img, 26, 32, 70, 64, Color("#D9B98C"))
			_rect(img, 44, 40, 52, 58, Color("#4A3B36"))


static func _briefkasten(img: Image, id: String, farbe: Color) -> void:
	_rect(img, 45, 50, 51, 88, Color("#8A6642"))
	match id:
		"kugel":
			_kreis(img, 48, 36, 18, farbe)
		"holz":
			_rect(img, 28, 30, 68, 52, farbe)
			_trapez(img, 24, 30, 72, 30, 40, 20, 56, 20, farbe.darkened(0.2))
		"modern":
			_rect(img, 36, 20, 60, 56, farbe)
			_rect(img, 40, 28, 56, 32, Color("#FFFFFF"))
		_:
			_rect(img, 26, 30, 70, 52, farbe)
			_rect(img, 64, 14, 68, 32, Color("#FFD166"))


static func _vordach(img: Image, id: String, farbe: Color) -> void:
	if id == "keins":
		_leer(img)
		return
	_trapez(img, 12, 56, 84, 56, 24, 28, 72, 28, farbe)
	if id == "markise_gestreift":
		for streifen in 4:
			var x0 := 22 + streifen * 16
			_trapez(img, x0 + 4, 56, x0 + 10, 56, x0 + 6, 28, x0 + 10, 28, Color("#FFFAF2"))
	if id == "vordach_holz":
		_rect(img, 18, 56, 24, 80, farbe.darkened(0.25))
		_rect(img, 72, 56, 78, 80, farbe.darkened(0.25))
	else:
		for zacke in 6:
			_rect(img, 14 + zacke * 12, 56, 22 + zacke * 12, 66, farbe.darkened(0.12))


static func _zaun(img: Image, id: String, farbe: Color) -> void:
	if id == "keins":
		_leer(img)
		return
	if id == "hecke":
		for k in 5:
			_kreis(img, 14 + k * 17, 52, 14, farbe)
		_rect(img, 4, 56, 92, 80, farbe.darkened(0.08))
		return
	var breite: int = {"latten": 8, "staketen": 6, "metall": 3}.get(id, 8)
	var schritt: int = {"latten": 16, "staketen": 18, "metall": 12}.get(id, 16)
	var x := 10
	while x < 86:
		_rect(img, x, 28, x + breite, 84, farbe)
		if id == "staketen":
			_kreis(img, x + int(breite / 2.0), 28, int(breite / 2.0) + 1, farbe)
		x += schritt
	_rect(img, 6, 40, 90, 46, farbe.darkened(0.15))
	_rect(img, 6, 66, 90, 72, farbe.darkened(0.15))


# ── Zeichen-Helfer ───────────────────────────────────────────────────────────


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, farbe: Color) -> void:
	for y in range(maxi(0, y0), mini(PX, y1)):
		for x in range(maxi(0, x0), mini(PX, x1)):
			img.set_pixel(x, y, farbe)


static func _kreis(img: Image, cx: int, cy: int, r: int, farbe: Color) -> void:
	for y in range(maxi(0, cy - r), mini(PX, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(PX, cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, farbe)


## Gefülltes Trapez zwischen Unterkante (u0..u1 bei yu) und Oberkante
## (o0..o1 bei yo) — reicht für Dächer und Markisen.
static func _trapez(
	img: Image,
	u0: int,
	yu0: int,
	u1: int,
	yu1: int,
	o0: int,
	yo0: int,
	o1: int,
	yo1: int,
	farbe: Color
) -> void:
	var y_oben := mini(yo0, yo1)
	var y_unten := maxi(yu0, yu1)
	for y in range(maxi(0, y_oben), mini(PX, y_unten)):
		var t := float(y - y_oben) / maxf(1.0, float(y_unten - y_oben))
		var links := int(lerpf(float(o0), float(u0), t))
		var rechts := int(lerpf(float(o1), float(u1), t))
		for x in range(maxi(0, links), mini(PX, rechts)):
			img.set_pixel(x, y, farbe)
