class_name RcompArena
extends RefCounted
## Turnierplatz-Arena (RW-5) — statische Bau-Helfer für die 3D-Szene.
## Passt zur RW-1-Zone `turnierplatz` (arena-Rect 96×60 m, flaches
## Plateau), läuft aber standalone am Ursprung: Sandplatz, Zaunring mit
## Einritt-Lücke, Tribüne mit Publikum, Fahnen, Podium. Wiederholtes
## läuft als MultiMesh (Draw-Call-Budget ≤ 350, RW-4-Muster).

const SAND := Color(0.87, 0.76, 0.56)
const GRAS := Color(0.56, 0.78, 0.45)
const HOLZ := Color(0.79, 0.55, 0.35)
const HOLZ_DUNKEL := Color(0.55, 0.38, 0.24)
const CREME := Color(0.95, 0.94, 0.87)
const FAHNEN_FARBEN: Array[Color] = [
	Color(0.91, 0.55, 0.63), Color(0.37, 0.66, 0.63), Color(0.95, 0.69, 0.3)
]
## Sandplatz (x/z, Meter) — Mitte am Ursprung.
const ARENA_RECT := Rect2(-30.0, -18.0, 60.0, 36.0)
## Erweiterte Reit-Grenzen (Geländeritt nutzt die Wiese drumherum).
const FELD_RECT := Rect2(-95.0, -70.0, 190.0, 140.0)


## Boden: Wiese + Sandplatz + Einritt-Streifen.
static func baue_boden(welt: Node3D) -> void:
	_quader(welt, Vector3(0.0, -0.15, 0.0), Vector3(220.0, 0.3, 170.0), GRAS)
	var sand := _quader(
		welt,
		Vector3(ARENA_RECT.get_center().x, 0.02, ARENA_RECT.get_center().y),
		Vector3(ARENA_RECT.size.x, 0.06, ARENA_RECT.size.y),
		SAND
	)
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Zaunring um ein Rect (Pfosten + zwei Latten als MultiMeshes);
## im Süden bleibt eine 6-m-Einritt-Lücke.
static func baue_zaun(welt: Node3D, rect: Rect2) -> void:
	var punkte: Array[Vector3] = []
	var schritt := 2.0
	var x := rect.position.x
	while x <= rect.end.x + 0.01:
		punkte.append(Vector3(x, 0.0, rect.position.y))
		if absf(x - rect.get_center().x) > 3.0:
			punkte.append(Vector3(x, 0.0, rect.end.y))
		x += schritt
	var z := rect.position.y + schritt
	while z <= rect.end.y - schritt + 0.01:
		punkte.append(Vector3(rect.position.x, 0.0, z))
		punkte.append(Vector3(rect.end.x, 0.0, z))
		z += schritt
	var pfosten_mesh := BoxMesh.new()
	pfosten_mesh.size = Vector3(0.14, 1.1, 0.14)
	var pfosten := _multi(welt, pfosten_mesh, HOLZ_DUNKEL, punkte.size())
	for i in punkte.size():
		pfosten.multimesh.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, punkte[i] + Vector3(0.0, 0.55, 0.0))
		)
	var latte_mesh := BoxMesh.new()
	latte_mesh.size = Vector3(schritt, 0.09, 0.06)
	var latten := _multi(welt, latte_mesh, CREME, punkte.size() * 2)
	var idx := 0
	for i in punkte.size():
		var p := punkte[i]
		var laengs := absf(p.z - rect.position.y) < 0.1 or absf(p.z - rect.end.y) < 0.1
		var basis := Basis.IDENTITY if laengs else Basis(Vector3.UP, PI * 0.5)
		for hoehe: float in [0.45, 0.9]:
			latten.multimesh.set_instance_transform(
				idx, Transform3D(basis, p + Vector3(0.0, hoehe, 0.0))
			)
			idx += 1


## Tribüne an der Nordseite: Stufen + Dach + Publikum (Kugel-MultiMesh).
## `zuschauer` skaliert mit RW-4s Tribünen-Ausbau (Basis 10).
static func baue_tribuene(welt: Node3D, zuschauer: int) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.position = Vector3(0.0, 0.0, ARENA_RECT.position.y - 4.5)
	welt.add_child(wurzel)
	for stufe in 3:
		_quader(
			wurzel,
			Vector3(0.0, 0.3 + stufe * 0.55, -float(stufe) * 1.15),
			Vector3(26.0, 0.55, 1.2),
			HOLZ if stufe % 2 == 0 else HOLZ_DUNKEL
		)
	var dach := _quader(wurzel, Vector3(0.0, 3.1, -1.2), Vector3(27.0, 0.18, 4.6), FAHNEN_FARBEN[0])
	dach.rotation.x = 0.12
	var kugel := SphereMesh.new()
	kugel.radius = 0.34
	kugel.height = 0.68
	kugel.radial_segments = 8
	kugel.rings = 4
	var menge := clampi(zuschauer, 0, 24)
	if menge > 0:
		var publikum := _multi(wurzel, kugel, Color(0.98, 0.83, 0.55), menge)
		var rng := GoobyRng.new(4711)
		for i in menge:
			var reihe := i % 3
			var platz := -11.0 + (float(i) / 3.0) * (22.0 / maxf(1.0, ceilf(menge / 3.0)))
			publikum.multimesh.set_instance_transform(
				i,
				Transform3D(
					Basis.IDENTITY,
					Vector3(
						platz + rng.next() * 1.4,
						1.0 + reihe * 0.55,
						-float(reihe) * 1.15 + rng.next() * 0.3
					)
				)
			)
	return wurzel


## Fahnenmasten mit Wimpeln an den vier Ecken.
static func baue_fahnen(welt: Node3D, rect: Rect2) -> void:
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.07
	mast_mesh.bottom_radius = 0.09
	mast_mesh.height = 4.2
	mast_mesh.radial_segments = 6
	var ecken: Array[Vector3] = [
		Vector3(rect.position.x, 0.0, rect.position.y),
		Vector3(rect.end.x, 0.0, rect.position.y),
		Vector3(rect.position.x, 0.0, rect.end.y),
		Vector3(rect.end.x, 0.0, rect.end.y),
	]
	var masten := _multi(welt, mast_mesh, CREME, ecken.size())
	for i in ecken.size():
		masten.multimesh.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, ecken[i] + Vector3(0.0, 2.1, 0.0))
		)
	var wimpel_mesh := PrismMesh.new()
	wimpel_mesh.size = Vector3(1.2, 0.7, 0.08)
	var wimpel := _multi(welt, wimpel_mesh, FAHNEN_FARBEN[2], ecken.size())
	for i in ecken.size():
		wimpel.multimesh.set_instance_transform(
			i,
			Transform3D(
				Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, PI * 0.25),
				ecken[i] + Vector3(0.0, 3.9, 0.0)
			)
		)


## Deko-Bäume rund ums Feld (ein MultiMesh).
static func baue_baeume(welt: Node3D, seed_wert: int) -> void:
	var kugel := SphereMesh.new()
	kugel.radius = 1.8
	kugel.height = 3.6
	kugel.radial_segments = 10
	kugel.rings = 5
	var baeume := _multi(welt, kugel, Color(0.4, 0.66, 0.4), 18)
	baeume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := GoobyRng.new(seed_wert)
	for i in 18:
		var winkel := TAU * i / 18.0 + rng.next() * 0.3
		var radius := 62.0 + rng.next() * 28.0
		baeume.multimesh.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * (0.8 + rng.next() * 0.6)),
				Vector3(cos(winkel) * radius, 2.0, sin(winkel) * radius * 0.75)
			)
		)


## Siegerpodium (1./2./3.) an pos; Rückgabe = Wurzel mit `platz_punkt(i)`.
static func baue_podium(welt: Node3D, pos: Vector3) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.position = pos
	welt.add_child(wurzel)
	var hoehen: Array[float] = [1.0, 0.65, 0.4]
	var offsets: Array[float] = [0.0, -3.4, 3.4]
	var farben: Array[Color] = [Color(0.95, 0.69, 0.3), Color(0.8, 0.82, 0.86), HOLZ]
	for i in 3:
		_quader(
			wurzel,
			Vector3(offsets[i], hoehen[i] * 0.5, 0.0),
			Vector3(3.0, hoehen[i], 3.0),
			farben[i]
		)
	return wurzel


## Standpunkt (lokal) für Platz i (0-basiert) auf dem Podium.
static func podium_punkt(platz: int) -> Vector3:
	var hoehen: Array[float] = [1.0, 0.65, 0.4]
	var offsets: Array[float] = [0.0, -3.4, 3.4]
	var i := clampi(platz, 0, 2)
	return Vector3(offsets[i], hoehen[i], 0.0)


## ---------------------------------------------------------------- intern


static func _quader(parent: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mi.mesh = mesh
	mi.material_override = RanchPferd.material(farbe)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _multi(parent: Node3D, mesh: Mesh, farbe: Color, anzahl: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = maxi(0, anzahl)
	mmi.multimesh = mm
	mmi.material_override = RanchPferd.material(farbe)
	parent.add_child(mmi)
	return mmi
