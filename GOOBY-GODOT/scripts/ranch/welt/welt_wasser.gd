class_name WeltWasser
extends RefCounted
## Wasser-Bibliothek (VIS-1, Trailer-Review „Seen wirken wie flache blaue
## Kreise"): baut das radiale Scheiben-Mesh (UV.x = Radius-Anteil 0..1,
## damit wasser.gdshader Tiefenverlauf + Schaumsaum kennt) und die
## ShaderMaterialien je Gewässer-Sorte (klar / moor / bach). Alle
## Materialien landen in einer Registry — der RanchWetterController
## treibt darüber die `regen`-Kräuselung. PURE genug für Headless-Tests.

const SHADER := "res://scripts/ranch/welt/wasser.gdshader"

## Sorten-Presets: Tief-/Flach-/Schaumfarbe, Wellen, Fluss, Band-Modus.
const SORTEN := {
	"klar":
	{
		"tief": Color(0.09, 0.29, 0.42, 0.94),
		"flach": Color(0.4, 0.72, 0.74, 0.62),
		"schaum": Color(0.96, 1.0, 1.0, 0.85),
		"welle": 1.0,
		"fluss": 0.0,
		"band": 0.0,
	},
	"moor":
	{
		"tief": Color(0.16, 0.21, 0.16, 0.95),
		"flach": Color(0.35, 0.42, 0.3, 0.8),
		"schaum": Color(0.62, 0.68, 0.55, 0.8),
		"welle": 0.35,
		"fluss": 0.0,
		"band": 0.0,
	},
	"bach":
	{
		"tief": Color(0.14, 0.36, 0.46, 0.88),
		"flach": Color(0.45, 0.74, 0.76, 0.6),
		"schaum": Color(0.96, 1.0, 1.0, 0.85),
		"welle": 0.7,
		"fluss": 2.2,
		"band": 1.0,
	},
}

static var _scheibe_cache: Mesh = null
static var _mat_cache: Dictionary = {}
static var _mats: Array[ShaderMaterial] = []


## Einheits-Wasserscheibe (Radius 1, XZ-Ebene) mit RADIALEM UV.x —
## konzentrische Ringe geben dem Vertex-Wogen genug Auflösung. COLOR.r
## spiegelt den Radius (der Shader liest den Ufer-Anteil aus COLOR.r).
static func scheibe_mesh() -> Mesh:
	if _scheibe_cache != null:
		return _scheibe_cache
	_scheibe_cache = _scheibe(1.0, 40, func(r: float, _w: float) -> float: return r)
	return _scheibe_cache


## Wasserscheibe MIT Gelände-Wissen: der Ufer-Anteil je Vertex kommt aus
## der ECHTEN Wassertiefe (Geländehöhe unterm Spiegel) — Tiefenverlauf
## und Schaumsaum liegen dadurch an der sichtbaren Uferlinie, nicht am
## (vom Gelände beschnittenen) Mesh-Rand. `hoehe_fn(x, z)` liefert die
## Geländehöhe, `tief_ab` Meter Wassertiefe = „tiefes" Wasser.
static func gelaende_scheibe_mesh(
	mitte: Vector2, radius: float, wasser_y: float, hoehe_fn: Callable, tief_ab := 2.2
) -> Mesh:
	var anteil_fn := func(r: float, w: float) -> float:
		var p := mitte + Vector2.from_angle(w) * r * radius
		var tiefe: float = wasser_y - float(hoehe_fn.call(p.x, p.y))
		var anteil := clampf(1.0 - tiefe / maxf(tief_ab, 0.1), 0.0, 1.0)
		# Liegt der Mesh-Rand im offenen Wasser (Bucht), läuft er in eine
		# Schaumkante aus statt hart abzuschneiden.
		return maxf(anteil, clampf((r - 0.88) / 0.12, 0.0, 1.0))
	return _scheibe(1.0, 48, anteil_fn)


## Scheiben-Fabrik: `anteil_fn(radius_anteil, winkel) -> Ufer-Anteil 0..1`
## landet in COLOR.r (und im UV.x als Fallback). Gleichmäßig dichte Ringe,
## damit der gebackene Ufer-Anteil die Uferlinie fein genug abtastet.
static func _scheibe(radius: float, segmente: int, anteil_fn: Callable) -> Mesh:
	var ringe: Array[float] = []
	for i in 22:
		ringe.append(float(i) / 21.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segmente:
		var w0 := float(s) / float(segmente) * TAU
		var w1 := float(s + 1) / float(segmente) * TAU
		for r in ringe.size() - 1:
			var r0 := ringe[r] * radius
			var r1 := ringe[r + 1] * radius
			var ecken: Array[Vector3] = [
				Vector3(cos(w0) * r0, 0.0, sin(w0) * r0),
				Vector3(cos(w1) * r0, 0.0, sin(w1) * r0),
				Vector3(cos(w1) * r1, 0.0, sin(w1) * r1),
				Vector3(cos(w0) * r1, 0.0, sin(w0) * r1),
			]
			var uvw: Array[Vector2] = [
				Vector2(ringe[r], w0),
				Vector2(ringe[r], w1),
				Vector2(ringe[r + 1], w1),
				Vector2(ringe[r + 1], w0),
			]
			# Godot-Winding: Vorderseite = im Uhrzeigersinn (von +Y gesehen).
			for idx: int in [0, 2, 1, 0, 3, 2]:
				var anteil: float = anteil_fn.call(uvw[idx].x, uvw[idx].y)
				st.set_normal(Vector3.UP)
				st.set_color(Color(anteil, 0.0, 0.0))
				st.set_uv(Vector2(uvw[idx].x, uvw[idx].y / TAU))
				st.add_vertex(ecken[idx])
	return st.commit()


## ShaderMaterial einer Gewässer-Sorte (gecacht + in der Wetter-Registry).
static func material(sorte: String) -> ShaderMaterial:
	if _mat_cache.has(sorte):
		return _mat_cache[sorte]
	var preset: Dictionary = SORTEN.get(sorte, SORTEN["klar"])
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter("farbe_tief", preset["tief"])
	mat.set_shader_parameter("farbe_flach", preset["flach"])
	mat.set_shader_parameter("schaum_farbe", preset["schaum"])
	mat.set_shader_parameter("welle_staerke", preset["welle"])
	mat.set_shader_parameter("fliess_tempo", preset["fluss"])
	mat.set_shader_parameter("band_modus", preset["band"])
	_mat_cache[sorte] = mat
	_mats.append(mat)
	return mat


## Alle Wasser-Materialien — der Wetter-Controller setzt hier `regen`.
static func materialien() -> Array[ShaderMaterial]:
	return _mats


static func reset_for_tests() -> void:
	_scheibe_cache = null
	_mat_cache = {}
	_mats = []
