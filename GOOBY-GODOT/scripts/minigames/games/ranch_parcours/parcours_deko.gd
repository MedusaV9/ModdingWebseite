extends RefCounted
## Ranch-Kulisse des Hindernis-Parcours (MP-G): Weide + Sandbahn mit
## Ideallinie, Streckenzaun, Tribüne mit Publikum, Start-/Ziel-Bogen mit
## Wimpelketten und Wiesen-Deko (Grasflecken, Blumen, Bäume mit Stamm) —
## alles MultiMesh-lastig fürs Draw-Call-Budget. Statische Fabrik ohne
## Zustand; parcours_game.gd ruft build() beim Lauf-Start.

## Ranch-Farbkanon (Werte wie RcompArena) — die Minispiele teilen die Optik
## des Turnierplatzes: Sandbahn, Holzzaun, Creme-Latten, Wimpel-Farben.
## W16 §6: SAND/CREME im Gleichschritt mit der Arena abgesenkt (Eich-Runde
## 2 aufs Boden-Luma-Zielband ~150–170; Creme-Latten waren ein Weissband).
const GRAS_GRUEN := Color(0.45, 0.66, 0.35)
const GRAS_DUNKEL := Color(0.4, 0.6, 0.31)
const SAND := Color(0.67, 0.56, 0.39)
const HOLZ := Color(0.79, 0.55, 0.35)
const HOLZ_DUNKEL := Color(0.55, 0.38, 0.24)
const CREME := Color(0.9, 0.87, 0.78)
const FAHNEN: Array[Color] = [
	Color(0.91, 0.55, 0.63), Color(0.37, 0.66, 0.63), Color(0.95, 0.69, 0.3)
]


## Baut die komplette Kulisse; Rückgabe = Tribünen-Publikum (Node3D mit
## RcompArena-Publikum-Meta) für den Jubel-Tick in parcours_game.
static func build(welt: Node3D, laenge: float, ctx: MinigameCtx) -> Node3D:
	# Weide: ein langes, breites Band + Sandbahn in der Mitte.
	var gras := MeshInstance3D.new()
	var gras_mesh := BoxMesh.new()
	gras_mesh.size = Vector3(laenge + 80.0, 0.3, 44.0)
	gras.mesh = gras_mesh
	gras.material_override = RanchPferd.material(GRAS_GRUEN)
	gras.position = Vector3(laenge * 0.5, -0.15, 0.0)
	welt.add_child(gras)
	var bahn := MeshInstance3D.new()
	var bahn_mesh := BoxMesh.new()
	bahn_mesh.size = Vector3(laenge + 20.0, 0.06, 3.4)
	bahn.mesh = bahn_mesh
	bahn.material_override = RanchPferd.material(SAND)
	bahn.position = Vector3(laenge * 0.5, 0.02, 0.0)
	bahn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(bahn)
	# Ideallinie: heller Streifen in Bahnmitte — die Linie, auf der Pferd
	# und Sprungmarker laufen (Lesehilfe, keine Mechanik).
	var linie := MeshInstance3D.new()
	var linie_mesh := BoxMesh.new()
	linie_mesh.size = Vector3(laenge + 20.0, 0.02, 0.16)
	linie.mesh = linie_mesh
	linie.material_override = RanchPferd.material(Color(0.93, 0.85, 0.66))
	linie.position = Vector3(laenge * 0.5, 0.06, 0.0)
	linie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(linie)
	_streckenzaun(welt, laenge)
	var publikum := _tribuene(welt, laenge, ctx)
	_ziel(welt, laenge)
	_wiese_deko(welt, laenge, ctx)
	return publikum


## Ranch-Zaun beidseits der Bahn: Pfosten als EIN MultiMesh + vier lange
## Creme-Latten — dieselbe Optik wie der Turnierplatz (RcompArena).
static func _streckenzaun(welt: Node3D, laenge: float) -> void:
	var schritt := 3.0
	var count := int((laenge + 36.0) / schritt)
	var pfosten_mesh := BoxMesh.new()
	pfosten_mesh.size = Vector3(0.14, 1.05, 0.14)
	var pfosten := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pfosten_mesh
	mm.instance_count = count * 2
	for i in count:
		var at_x := -14.0 + float(i) * schritt
		for j in 2:
			mm.set_instance_transform(
				i * 2 + j, Transform3D(Basis.IDENTITY, Vector3(at_x, 0.5, 4.6 if j == 0 else -4.6))
			)
	pfosten.multimesh = mm
	pfosten.material_override = RanchPferd.material(HOLZ_DUNKEL)
	welt.add_child(pfosten)
	for seite: float in [-1.0, 1.0]:
		for hoehe: float in [0.42, 0.82]:
			var latte := MeshInstance3D.new()
			var latte_mesh := BoxMesh.new()
			latte_mesh.size = Vector3(laenge + 36.0, 0.08, 0.06)
			latte.mesh = latte_mesh
			latte.material_override = RanchPferd.material(CREME)
			latte.position = Vector3(laenge * 0.5 - 2.0, hoehe, seite * 4.6)
			latte.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			welt.add_child(latte)


## Tribüne mit Publikum nahe dem Start (bei ~12 % der Strecke sieht man sie
## schon in den ersten Sekunden UND beim ersten Sprung) + eine Wimpelkette
## am Start — Turnier-Stimmung wie auf dem Ranch-Turnierplatz. Rückgabe =
## Mini-Gooby-Publikum (W16 §6: RcompArena-Helfer statt Hautkugeln).
static func _tribuene(welt: Node3D, laenge: float, ctx: MinigameCtx) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.position = Vector3(laenge * 0.12, 0.0, -8.2)
	welt.add_child(wurzel)
	for stufe in 3:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(9.0, 0.55, 1.15)
		box.mesh = mesh
		box.material_override = RanchPferd.material(HOLZ if stufe % 2 == 0 else HOLZ_DUNKEL)
		box.position = Vector3(0.0, 0.3 + float(stufe) * 0.55, -float(stufe) * 1.15)
		wurzel.add_child(box)
	var dach := MeshInstance3D.new()
	var dach_mesh := BoxMesh.new()
	dach_mesh.size = Vector3(9.6, 0.16, 4.2)
	dach.mesh = dach_mesh
	dach.material_override = RanchPferd.material(FAHNEN[2])
	dach.position = Vector3(0.0, 3.0, -1.15)
	dach.rotation.x = 0.1
	dach.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(dach)
	var rng := ctx.rng(431)
	var plaetze: Array[Vector3] = []
	for i in 12:
		var reihe := i % 3
		plaetze.append(
			Vector3(
				-3.8 + float(i / 3) * 2.4 + rng.next() * 1.2,
				0.58 + float(reihe) * 0.55,
				-float(reihe) * 1.15 + rng.next() * 0.3
			)
		)
	var publikum := RcompArena.baue_publikum(wurzel, plaetze)
	# Start-Bogen: zwei Creme-Masten + Wimpelkette über der Bahn bei x = 0.
	for seite: float in [-1.0, 1.0]:
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.07
		mast_mesh.bottom_radius = 0.09
		mast_mesh.height = 3.3
		mast_mesh.radial_segments = 6
		mast.mesh = mast_mesh
		mast.material_override = RanchPferd.material(CREME)
		mast.position = Vector3(0.0, 1.65, seite * 4.6)
		welt.add_child(mast)
	wimpel_kette(welt, Vector3(0.0, 3.1, -4.6), Vector3(0.0, 3.1, 4.6))
	return publikum


## Ziel: Torbogen mit Querlatte und Wimpelkette am Kursende.
static func _ziel(welt: Node3D, laenge: float) -> void:
	for seite: float in [-1.0, 1.0]:
		var pfosten := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.14
		mesh.bottom_radius = 0.14
		mesh.height = 3.2
		pfosten.mesh = mesh
		pfosten.material_override = RanchPferd.material(Color(0.93, 0.55, 0.5))
		pfosten.position = Vector3(laenge, 1.6, seite * 2.2)
		welt.add_child(pfosten)
	var latte := MeshInstance3D.new()
	var latte_mesh := BoxMesh.new()
	latte_mesh.size = Vector3(0.16, 0.16, 4.8)
	latte.mesh = latte_mesh
	latte.material_override = RanchPferd.material(CREME)
	latte.position = Vector3(laenge, 3.2, 0.0)
	latte.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(latte)
	wimpel_kette(welt, Vector3(laenge, 3.15, -2.2), Vector3(laenge, 3.15, 2.2))


## Wimpelkette zwischen zwei Punkten: EIN MultiMesh mit Instanzfarben,
## leicht durchhängend — die Farben kommen aus dem Ranch-Fahnenkanon.
static func wimpel_kette(welt: Node3D, from: Vector3, to: Vector3) -> void:
	var count := maxi(5, int(from.distance_to(to) / 0.85))
	var prisma := PrismMesh.new()
	prisma.size = Vector3(0.42, 0.5, 0.04)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	prisma.material = mat
	var kette := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = prisma
	mm.instance_count = count
	var flip := Basis(Vector3.RIGHT, PI)
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var at := from.lerp(to, t) + Vector3(0.0, -sin(t * PI) * 0.4, 0.0)
		mm.set_instance_transform(i, Transform3D(flip, at))
		mm.set_instance_color(i, FAHNEN[i % FAHNEN.size()])
	kette.multimesh = mm
	kette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(kette)


## Wiesen-Struktur + Bäume: dunklere Grasflecken, Blumentupfer und Bäume
## MIT Stamm (statt schwebender Mint-Kugeln) — alles MultiMesh.
static func _wiese_deko(welt: Node3D, laenge: float, ctx: MinigameCtx) -> void:
	var rng := ctx.rng(917)
	var flecken := MultiMeshInstance3D.new()
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 0.5
	scheibe.bottom_radius = 0.5
	scheibe.height = 0.04
	scheibe.radial_segments = 8
	fmm.mesh = scheibe
	fmm.instance_count = 40
	for i in 40:
		var seite := -1.0 if i % 2 == 0 else 1.0
		var s := 0.8 + rng.next() * 2.2
		fmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(s, 1.0, s * (0.6 + rng.next() * 0.5))),
				Vector3(
					rng.next() * (laenge + 30.0) - 12.0, 0.005, seite * (2.4 + rng.next() * 12.0)
				)
			)
		)
	flecken.multimesh = fmm
	flecken.material_override = RanchPferd.material(GRAS_DUNKEL)
	flecken.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(flecken)
	var blumen := MultiMeshInstance3D.new()
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	var tupfer := SphereMesh.new()
	tupfer.radius = 0.09
	tupfer.height = 0.18
	tupfer.radial_segments = 6
	tupfer.rings = 3
	bmm.mesh = tupfer
	bmm.instance_count = 26
	for i in 26:
		var seite := -1.0 if i % 3 == 0 else 1.0
		bmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(rng.next() * (laenge + 24.0) - 10.0, 0.08, seite * (2.6 + rng.next() * 8.0))
			)
		)
	blumen.multimesh = bmm
	blumen.material_override = RanchPferd.material(Color(0.97, 0.9, 0.72))
	blumen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(blumen)
	# Bäume: Kronen + Stämme (je EIN MultiMesh, identische Plätze).
	var plaetze: Array[Vector3] = []
	var groessen: Array[float] = []
	for i in 26:
		var seite := -1.0 if i % 2 == 0 else 1.0
		plaetze.append(
			Vector3(rng.next() * (laenge + 40.0) - 16.0, 0.0, seite * (7.0 + rng.next() * 9.0))
		)
		groessen.append(0.75 + rng.next() * 0.6)
	var kronen := MultiMeshInstance3D.new()
	var kmm := MultiMesh.new()
	kmm.transform_format = MultiMesh.TRANSFORM_3D
	var kugel := SphereMesh.new()
	kugel.radius = 1.5
	kugel.height = 3.0
	kugel.radial_segments = 12
	kugel.rings = 6
	kmm.mesh = kugel
	kmm.instance_count = plaetze.size()
	for i in plaetze.size():
		kmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * groessen[i]),
				plaetze[i] + Vector3(0.0, 1.3 + groessen[i] * 1.1, 0.0)
			)
		)
	kronen.multimesh = kmm
	kronen.material_override = RanchPferd.material(Color(0.36, 0.6, 0.36))
	kronen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(kronen)
	var staemme := MultiMeshInstance3D.new()
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	var stamm := CylinderMesh.new()
	stamm.top_radius = 0.14
	stamm.bottom_radius = 0.18
	stamm.height = 1.8
	stamm.radial_segments = 6
	smm.mesh = stamm
	smm.instance_count = plaetze.size()
	for i in plaetze.size():
		smm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * groessen[i]),
				plaetze[i] + Vector3(0.0, 0.9 * groessen[i], 0.0)
			)
		)
	staemme.multimesh = smm
	staemme.material_override = RanchPferd.material(HOLZ_DUNKEL)
	staemme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	welt.add_child(staemme)
