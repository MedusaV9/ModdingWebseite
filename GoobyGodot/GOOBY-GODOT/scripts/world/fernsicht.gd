class_name WeltFernsicht
extends Node3D
## Fernsicht-Kulisse (FB-2 „Berge & Landschaften"): drei Silhouetten-Ringe
## um die Spielwelt — sanfte Hügelkette, mittlere Bergkette, ferne hohe
## Kette mit Schneekappen — plus ein Fernwiesen-Ring, der die Lücke
## zwischen Geländerand und Bergfuß schließt. Alles unshaded (4 Draw-Calls
## gesamt, keine Schatten); die Dunst-Färbung kommt pro Tick über
## `faerbe()` aus den Himmel-Farben (GoobyHimmel), zusätzlich hazed der
## permanente Fernnebel (Environment-Fog) die Ringe nach Distanz.

## Ringe von nah nach fern: Radius (muss außerhalb der Kartenecken liegen —
## WELT-1: die Karte reicht bis Ecke ~1640 m), Kammhöhe, Grundton und
## Dunst-Anteil Richtung Horizont-Farbe.
const RINGE: Array[Dictionary] = [
	{"radius": 1780.0, "hoehe": 120.0, "ton": Color(0.42, 0.62, 0.38), "dunst": 0.18},
	{"radius": 2120.0, "hoehe": 280.0, "ton": Color(0.38, 0.50, 0.68), "dunst": 0.34},
	{"radius": 2520.0, "hoehe": 430.0, "ton": Color(0.46, 0.52, 0.74), "dunst": 0.52},
]

## Segmentzahl je Ring (Silhouette bleibt auch nah am Rand rund).
const SEGMENTE := 160

## Fußhöhe der Ringe (deutlich unter dem Gelände — kein Spalt am Horizont).
const FUSS_Y := -60.0

## Fernwiesen-Ring: schließt den Boden zwischen Kartenrand und Bergfuß.
## WELT-1: die Innenkante folgt dem RECHTECKIGEN Kartenrand (einrichten
## nimmt das Karten-Rect entgegen); ohne Rect fällt sie auf den alten
## Kreis-Radius zurück.
const WIESE_INNEN := 640.0
const WIESE_AUSSEN := 2650.0
const WIESE_Y := 0.9
const WIESE_TON := Color(0.60, 0.78, 0.47)

var _materialien: Array[StandardMaterial3D] = []
var _wiese_material: StandardMaterial3D


## Baut alle Ringe + Fernwiese (deterministisch über `seed_wert`).
## `innen_rect`: Kartenrand, an dem die Fernwiese INNEN anliegt (Rect2()
## = alter Kreis-Fallback).
func einrichten(seed_wert: int, innen_rect := Rect2()) -> void:
	for i in RINGE.size():
		var konfig: Dictionary = RINGE[i]
		var material := _unlit(Color.WHITE)
		_materialien.append(material)
		var ring := _baue_ring(konfig, seed_wert + i * 101, material, i == RINGE.size() - 1)
		ring.name = "Bergring_%d" % i
		add_child(ring)
	_wiese_material = _unlit(WIESE_TON)
	var wiese := _baue_wiese(innen_rect)
	wiese.name = "Fernwiese"
	add_child(wiese)
	faerbe(Color(0.8, 0.89, 0.97), 1.0)


## Dunst-Färbung nachziehen: Ring-Ton wird je nach Dunst-Anteil Richtung
## Horizont-Farbe gezogen; `licht` (0..1) dunkelt die Nacht ab.
func faerbe(horizont: Color, licht: float) -> void:
	var helligkeit := lerpf(0.22, 1.0, clampf(licht, 0.0, 1.0))
	for i in _materialien.size():
		var konfig: Dictionary = RINGE[i]
		var ton: Color = konfig["ton"]
		var farbe := ton.lerp(horizont, float(konfig["dunst"]))
		_materialien[i].albedo_color = Color(
			farbe.r * helligkeit, farbe.g * helligkeit, farbe.b * helligkeit
		)
	if _wiese_material != null:
		var wiese := WIESE_TON.lerp(horizont, 0.24)
		_wiese_material.albedo_color = Color(
			wiese.r * helligkeit, wiese.g * helligkeit, wiese.b * helligkeit
		)


## Deterministische Kammhöhe (0..1) eines Rings am Winkel — PURE, damit
## Tests die Silhouette prüfen können (kein RNG, nur Sinus-Mix).
static func kamm_profil(winkel: float, salz: int) -> float:
	var s := float(salz)
	var grob := 0.5 + 0.28 * sin(winkel * 3.0 + s * 1.7) + 0.22 * sin(winkel * 7.0 + s * 3.1)
	var fein := 0.12 * sin(winkel * 13.0 + s * 5.3) + 0.08 * sin(winkel * 23.0 + s * 0.7)
	return clampf(grob + fein, 0.12, 1.0)


## ------------------------------------------------------------------ intern


func _baue_ring(
	konfig: Dictionary, salz: int, material: StandardMaterial3D, schnee: bool
) -> MeshInstance3D:
	var radius := float(konfig["radius"])
	var hoehe := float(konfig["hoehe"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spitzen: PackedFloat32Array = []
	for i in SEGMENTE + 1:
		var winkel := TAU * float(i % SEGMENTE) / float(SEGMENTE)
		spitzen.append(FUSS_Y + hoehe * kamm_profil(winkel, salz))
	for i in SEGMENTE:
		var w0 := TAU * float(i) / float(SEGMENTE)
		var w1 := TAU * float(i + 1) / float(SEGMENTE)
		var unten0 := Vector3(cos(w0) * radius, FUSS_Y, sin(w0) * radius)
		var unten1 := Vector3(cos(w1) * radius, FUSS_Y, sin(w1) * radius)
		var oben0 := Vector3(cos(w0) * radius, spitzen[i], sin(w0) * radius)
		var oben1 := Vector3(cos(w1) * radius, spitzen[i + 1], sin(w1) * radius)
		var farbe0 := _kamm_farbe(spitzen[i], hoehe, schnee)
		var farbe1 := _kamm_farbe(spitzen[i + 1], hoehe, schnee)
		var fuss := Color(0.90, 0.93, 1.0)
		_dreieck(st, [unten0, oben0, unten1], [fuss, farbe0, fuss])
		_dreieck(st, [unten1, oben0, oben1], [fuss, farbe0, farbe1])
	var mesh := st.commit()
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Riesen-AABB nie aus Versehen distanz-cullen.
	mi.ignore_occlusion_culling = true
	return mi


## Kamm-Vertexfarbe: oben leicht dunkler für Tiefe; Schneekappen heller.
func _kamm_farbe(spitze_y: float, hoehe: float, schnee: bool) -> Color:
	var anteil := clampf((spitze_y - FUSS_Y) / maxf(hoehe, 0.001), 0.0, 1.0)
	var farbe := Color(1, 1, 1).lerp(Color(0.78, 0.80, 0.90), anteil * 0.6)
	if schnee and anteil > 0.72:
		farbe = farbe.lerp(Color(1.18, 1.18, 1.22), (anteil - 0.72) / 0.28)
	return farbe


func _dreieck(st: SurfaceTool, punkte: Array, farben: Array) -> void:
	for i in 3:
		st.set_color(farben[i])
		st.set_normal(Vector3.UP)
		st.add_vertex(punkte[i])


func _baue_wiese(innen_rect: Rect2) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in SEGMENTE + 1:
		var winkel := TAU * float(i % SEGMENTE) / float(SEGMENTE)
		var richtung := Vector3(cos(winkel), 0.0, sin(winkel))
		var innen := richtung * _innen_abstand(winkel, innen_rect)
		st.set_normal(Vector3.UP)
		st.add_vertex(innen + Vector3(0.0, WIESE_Y, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(richtung * WIESE_AUSSEN + Vector3(0.0, WIESE_Y, 0.0))
	var mesh := st.commit()
	mesh.surface_set_material(0, _wiese_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.ignore_occlusion_culling = true
	return mi


## Abstand der Wiesen-Innenkante am Winkel: Schnittpunkt des Strahls vom
## Ursprung mit dem Karten-Rect (Slab-Test) — ohne Rect der alte Kreis.
static func _innen_abstand(winkel: float, innen_rect: Rect2) -> float:
	if innen_rect.size.x <= 0.0 or innen_rect.size.y <= 0.0:
		return WIESE_INNEN
	var richtung := Vector2(cos(winkel), sin(winkel))
	var t := INF
	if absf(richtung.x) > 0.0001:
		var grenze_x := innen_rect.end.x if richtung.x > 0.0 else innen_rect.position.x
		t = minf(t, grenze_x / richtung.x)
	if absf(richtung.y) > 0.0001:
		var grenze_z := innen_rect.end.y if richtung.y > 0.0 else innen_rect.position.y
		t = minf(t, grenze_z / richtung.y)
	if not is_finite(t) or t <= 0.0:
		return WIESE_INNEN
	return t


func _unlit(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = farbe
	# Der Environment-Fog wusch die Ringe zu Einheitsgrau aus — die Dunst-
	# Färbung kommt stattdessen deterministisch aus faerbe() (dunst-Lerp).
	mat.disable_fog = true
	return mat
