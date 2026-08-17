class_name CustomizeMaterials
extends RefCounted
## Material-Schicht des Gestalten-Modus (HAUS-CUSTOM). EIN Ansatz für alles
## (Wände, Böden, Fassade, Grundstück) — derselbe Umfärbe-Trick wie beim
## Möbel-Shader `scripts/shop/furniture_variant.gdshader` (CONTENT-B):
## Graustufen-MUSTER (prozedural, EINMAL pro Muster erzeugt) × Palettenfarbe
## über `assets/home/materials/surface_recolor.gdshader` (Welt-UV-Kachelung).
##
## Mobile-Budget: pro (Muster, Farbe) existiert EIN gecachtes ShaderMaterial,
## das alle Flächen teilen; Texturen sind 128²-Graustufen. Vorschau-Kacheln
## rechnen dieselbe Formel auf der CPU (`preview_texture`) — kein Render-Pass,
## kein Asset-Wildwuchs.

## Bezugshelligkeit der Muster (mittlere „Papier“-Fläche der Generatoren).
const REFERENCE_LUMINANCE := 0.78
const TEX_PX := 128
const BASE_MATERIAL := preload("res://assets/home/materials/surface_base.tres")

## EINZIGE Farbquelle des Gestalten-Modus (AC-Pastelle + Holz-/Steintöne).
## Anzeigenamen: `strings/<locale>/customize.json` → `customize.farbe.<id>`.
const PALETTE := {
	"weiss": Color("#FFFFFF"),
	"creme": Color("#FFF6EC"),
	"rose": Color("#FFD5E5"),
	"pink": Color("#FF7BA9"),
	"koralle": Color("#FFC2B4"),
	"butter": Color("#FFEFC2"),
	"sonnengelb": Color("#FFD166"),
	"ocker": Color("#D9A441"),
	"mint": Color("#C9F0E0"),
	"salbei": Color("#D6E5C6"),
	"blattgruen": Color("#8FD06C"),
	"tannengruen": Color("#4E7D5B"),
	"himmel": Color("#CFE9F5"),
	"teal": Color("#59C9B9"),
	"marine": Color("#4A6FA5"),
	"lavendel": Color("#E2D6F5"),
	"flieder": Color("#C9B6E8"),
	"schiefer": Color("#AEBBC7"),
	"grau_hell": Color("#CFCBC4"),
	"grau": Color("#9C968E"),
	"anthrazit": Color("#55514B"),
	"sandstein": Color("#E3D3B4"),
	"terracotta": Color("#C97B4A"),
	"ziegelrot": Color("#B5533C"),
	"eiche_hell": Color("#D9B98C"),
	"eiche": Color("#C9A36B"),
	"nussbaum": Color("#8A6642"),
	"walnuss": Color("#5F4630"),
}

## Muster-Metadaten: Weltmeter pro Kachel, Umfärbe-Stärke, Rauheit.
## Fehlende Felder = Standard (1.0 m, Stärke 1.0, Rauheit 0.95).
const MUSTER_META := {
	"uni": {},
	"punkte": {"meter": 0.8},
	"streifen": {"meter": 0.72},
	"streifen_fein": {"meter": 0.4},
	"blumen": {"meter": 0.9},
	"ranken": {"meter": 0.8},
	"paneel": {},
	"karo": {"meter": 0.6},
	"kacheln": {"meter": 0.8, "rauheit": 0.55},
	"rauten": {"meter": 0.7},
	"dielen": {"meter": 1.4, "rauheit": 0.8},
	"fischgraet": {"meter": 0.9, "rauheit": 0.8},
	"wuerfel": {"meter": 0.96, "rauheit": 0.8},
	"fliesen": {"meter": 1.2, "rauheit": 0.5},
	"schach": {"meter": 1.0, "rauheit": 0.5},
	"teppich": {"rauheit": 1.0},
	"stein": {"meter": 1.5},
	"rasen": {"meter": 1.2, "rauheit": 1.0},
	"rasen_lang": {"meter": 1.0, "rauheit": 1.0},
	"wildblumen": {"meter": 1.6, "staerke": 0.45, "rauheit": 1.0},
	"kies": {"meter": 0.9},
	"platten": {"meter": 1.4},
	"sand": {"meter": 1.1, "rauheit": 1.0},
	"waldboden": {"meter": 1.5, "rauheit": 1.0},
	"weg_platten": {"meter": 0.7},
	"weg_rund": {"meter": 0.7},
	"weg_ziegel": {"meter": 0.5},
	"weg_schach": {"meter": 0.6},
}

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var _flats: Dictionary = {}
static var _previews: Dictionary = {}


## Palettenfarbe (unbekannte ID → Creme, nie ein Absturz).
static func farbe(farb_id: String) -> Color:
	return PALETTE.get(farb_id, PALETTE["creme"])


static func ist_farbe(farb_id: String) -> bool:
	return PALETTE.has(farb_id)


static func hat_muster(muster: String) -> bool:
	return MUSTER_META.has(muster)


## Graustufen-Muster-Textur (einmal erzeugt, dann gecacht + geteilt).
static func pattern_texture(muster: String) -> ImageTexture:
	if _textures.has(muster):
		return _textures[muster]
	var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
	for y in TEX_PX:
		for x in TEX_PX:
			img.set_pixel(x, y, _pixel(muster, x, y))
	var tex := ImageTexture.create_from_image(img)
	_textures[muster] = tex
	return tex


## Geteiltes Flächen-Material (Muster × Palette) — Wände/Böden/Grundstück.
static func surface(muster: String, farb_id: String) -> ShaderMaterial:
	var key := "%s|%s" % [muster, farb_id]
	if _materials.has(key):
		return _materials[key]
	var meta: Dictionary = MUSTER_META.get(muster, {})
	var mat: ShaderMaterial = BASE_MATERIAL.duplicate()
	mat.set_shader_parameter("tint", farbe(farb_id))
	mat.set_shader_parameter("muster_tex", pattern_texture(muster))
	mat.set_shader_parameter("meter_pro_kachel", float(meta.get("meter", 1.0)))
	mat.set_shader_parameter("strength", float(meta.get("staerke", 1.0)))
	mat.set_shader_parameter("roughness_value", float(meta.get("rauheit", 0.95)))
	mat.set_shader_parameter("reference_luminance", REFERENCE_LUMINANCE)
	_materials[key] = mat
	return mat


## Geteiltes einfarbiges Material (Türen, Rahmen, Zäune, Dach, Schilder).
static func flat(farb_id: String, rauheit := 0.9) -> StandardMaterial3D:
	var key := "%s|%.2f" % [farb_id, rauheit]
	if _flats.has(key):
		return _flats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe(farb_id)
	mat.roughness = rauheit
	_flats[key] = mat
	return mat


## CPU-Spiegel der Shader-Formel (Vorschau-Kacheln + Tests).
static func blend(source: Color, farb_id: String, staerke := 1.0) -> Color:
	var tint := farbe(farb_id)
	var level := clampf(source.get_luminance() / REFERENCE_LUMINANCE, 0.35, 1.15)
	var recolored := Color(tint.r * level, tint.g * level, tint.b * level, source.a)
	return source.lerp(recolored, staerke)


## Prozedurales Vorschaubild einer (Muster, Farbe)-Kombination — für die
## Options-Kacheln im Gestalten-Screen (kein Extra-Asset, gecacht).
static func preview_texture(muster: String, farb_id: String, px := 96) -> ImageTexture:
	var key := "%s|%s|%d" % [muster, farb_id, px]
	if _previews.has(key):
		return _previews[key]
	var staerke := float(MUSTER_META.get(muster, {}).get("staerke", 1.0))
	var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
	for y in TEX_PX:
		for x in TEX_PX:
			img.set_pixel(x, y, blend(_pixel(muster, x, y), farb_id, staerke))
	if px != TEX_PX:
		img.resize(px, px, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	_previews[key] = tex
	return tex


## Cache leeren (Tests).
static func reset_cache() -> void:
	_textures = {}
	_materials = {}
	_flats = {}
	_previews = {}


# ── Muster-Generatoren (Graustufen-Helligkeit pro Pixel) ─────────────────────


static func _pixel(muster: String, x: int, y: int) -> Color:
	if muster == "wildblumen":
		return _m_wildblumen(x, y)
	var v := _wert(muster, x, y)
	return Color(v, v, v)


static func _wert(muster: String, x: int, y: int) -> float:
	var v := 0.85
	match muster:
		"uni":
			v = 0.86 + (_hash(x / 4, y / 4) - 0.5) * 0.03
		"punkte":
			v = _m_punkte(x, y)
		"streifen":
			v = 0.87 if (x / 16) % 2 == 0 else 0.7
		"streifen_fein":
			v = 0.7 if x % 16 < 3 else 0.88
		"blumen":
			v = _m_blumen(x, y)
		"ranken":
			v = _m_ranken(x, y)
		"paneel":
			v = _m_paneel(x, y)
		"karo":
			v = _m_karo(x, y)
		"kacheln":
			v = _m_raster(x, y, 32, 2, 0.88)
		"rauten":
			v = 0.85 if ((x + y) / 32 + (x - y + 256) / 32) % 2 == 0 else 0.68
		"dielen":
			v = _m_dielen(x, y)
		"fischgraet":
			v = _m_fischgraet(x, y)
		"wuerfel":
			v = _m_wuerfel(x, y)
		"fliesen":
			v = _m_raster(x, y, 64, 3, 0.9)
		"schach", "weg_schach":
			v = 0.9 if ((x / 32) + (y / 32)) % 2 == 0 else 0.62
		"teppich":
			v = 0.8 + (_hash(x / 2, y / 2) - 0.5) * 0.1
		"stein":
			v = _m_stein(x, y)
		"rasen":
			v = _m_rasen(x, y)
		"rasen_lang":
			v = _m_rasen_lang(x, y)
		"kies":
			v = 0.68 + _hash(x / 5, y / 5) * 0.2 + (_hash(x, y) - 0.5) * 0.06
		"platten":
			v = _m_raster(x, y, 64, 4, 0.84)
		"sand":
			v = 0.7 if _hash(x, y) > 0.97 else 0.88 + (_hash(x, y) - 0.5) * 0.05
		"waldboden":
			v = _m_waldboden(x, y)
		"weg_platten":
			v = _m_raster(x, y, 42, 4, 0.85)
		"weg_rund":
			v = _m_weg_rund(x, y)
		"weg_ziegel":
			v = _m_weg_ziegel(x, y)
	return clampf(v, 0.0, 1.0)


## Deterministisches 2D-Rauschen (0..1) — kein RNG-Zustand, kachelbar genug.
static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) % 2147483647
	h = ((h ^ (h >> 13)) * 1274126177) % 2147483647
	return float(absi(h) % 10000) / 10000.0


## Kachel-/Fliesenraster: dunkle Fugen, leichte Ton-Variation pro Feld.
static func _m_raster(x: int, y: int, feld: int, fuge: int, hell: float) -> float:
	if x % feld < fuge or y % feld < fuge:
		return 0.55
	return hell + (_hash(x / feld, y / feld) - 0.5) * 0.05


static func _m_punkte(x: int, y: int) -> float:
	var row := y / 32
	var cx := (x + (row % 2) * 16) % 32 - 16
	var cy := y % 32 - 16
	if cx * cx + cy * cy < 36:
		return 0.62
	return 0.86


static func _m_blumen(x: int, y: int) -> float:
	var row := y / 64
	var lx := (x + (row % 2) * 32) % 64
	var ly := y % 64
	var dx := lx - 32
	var dy := ly - 32
	if dx * dx + dy * dy < 20:
		return 0.96
	for k in 5:
		var winkel := TAU * k / 5.0
		var px := dx - int(round(cos(winkel) * 9.0))
		var py := dy - int(round(sin(winkel) * 9.0))
		if px * px + py * py < 30:
			return 0.63
	return 0.88 + (_hash(x / 8, y / 8) - 0.5) * 0.02


static func _m_ranken(x: int, y: int) -> float:
	var col := x / 32
	var lx := x % 32
	var welle := 16.0 + sin(y * 0.2 + col * 2.1) * 4.0
	var abstand := absf(lx - welle)
	if abstand < 1.6:
		return 0.62
	if y % 16 < 3 and abstand < 5.0:
		return 0.68
	return 0.87


static func _m_paneel(x: int, y: int) -> float:
	if x % 32 < 2:
		return 0.55
	return 0.82 + _hash(x / 32, 0) * 0.06 + (_hash(x / 32, y / 8) - 0.5) * 0.04


static func _m_karo(x: int, y: int) -> float:
	var sx := (x / 16) % 2 == 0
	var sy := (y / 16) % 2 == 0
	if sx and sy:
		return 0.66
	if sx or sy:
		return 0.78
	return 0.9


static func _m_dielen(x: int, y: int) -> float:
	var row := y / 21
	if y % 21 < 2:
		return 0.5
	if (x + row * 43) % 128 < 2:
		return 0.5
	var brett := (x + row * 43) / 128
	return 0.8 + (_hash(row, brett) - 0.5) * 0.12 + (_hash(x, row) - 0.5) * 0.03


static func _m_fischgraet(x: int, y: int) -> float:
	var col := x / 16
	var diagonale := (x + y) if col % 2 == 0 else (x - y + 256)
	if diagonale % 16 < 2:
		return 0.55
	return 0.82 + (_hash(diagonale / 16, col) - 0.5) * 0.1


static func _m_wuerfel(x: int, y: int) -> float:
	var bx := x / 32
	var by := y / 32
	var quer := (bx + by) % 2 == 0
	if (y % 8 < 1) if quer else (x % 8 < 1):
		return 0.6
	return 0.82 + (_hash(bx, by) - 0.5) * 0.06


static func _m_stein(x: int, y: int) -> float:
	var row := y / 42
	var ox := int(_hash(row, 7) * 40.0)
	if (x + ox) % 56 < 3 or y % 42 < 3:
		return 0.55
	return 0.8 + (_hash((x + ox) / 56, row) - 0.5) * 0.1


static func _m_rasen(x: int, y: int) -> float:
	var v := 0.8 + (_hash(x, y) - 0.5) * 0.12
	if _hash(x / 8, y / 8) > 0.9:
		v += 0.08
	return v


static func _m_rasen_lang(x: int, y: int) -> float:
	var v := 0.72 + (_hash(x, y) - 0.5) * 0.08
	if _hash(x / 3, y / 12) > 0.72:
		v = 0.88
	return v


static func _m_waldboden(x: int, y: int) -> float:
	var v := 0.62 + _hash(x / 16, y / 16) * 0.18 + (_hash(x, y) - 0.5) * 0.05
	if _hash(x / 6, y / 6) > 0.93:
		v = 0.85
	return v


static func _m_weg_rund(x: int, y: int) -> float:
	var row := y / 64
	var cx := (x + (row % 2) * 32) % 64 - 32
	var cy := y % 64 - 32
	var d2 := cx * cx + cy * cy
	if d2 < 24 * 24:
		return 0.85 + (_hash(x / 64, row) - 0.5) * 0.06
	if d2 < 28 * 28:
		return 0.68
	return 0.55


static func _m_weg_ziegel(x: int, y: int) -> float:
	var row := y / 16
	if y % 16 < 2 or (x + (row % 2) * 16) % 32 < 2:
		return 0.55
	return 0.82 + (_hash((x + (row % 2) * 16) / 32, row) - 0.5) * 0.08


## Wildblumenwiese ist das EINE farbige Muster: der Shader lässt mit
## staerke 0.45 die Blüten-Farben durchscheinen (Grün kommt von der Palette).
static func _m_wildblumen(x: int, y: int) -> Color:
	var g := 0.62 + (_hash(x, y) - 0.5) * 0.1 + _hash(x / 8, y / 8) * 0.08
	var basis := Color(g * 0.82, g, g * 0.7)
	var row := y / 16
	var lx := (x + (row % 2) * 8) % 16 - 8
	var ly := y % 16 - 8
	if lx * lx + ly * ly < 6 and _hash(x / 16 + 3, row) > 0.55:
		var bluete := _hash(x / 16, row)
		if bluete > 0.75:
			return Color("#FF7BA9")
		if bluete > 0.5:
			return Color("#FFEFC2")
		if bluete > 0.25:
			return Color("#FFFFFF")
		return Color("#C9B6E8")
	return basis
