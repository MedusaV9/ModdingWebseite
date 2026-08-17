class_name RcompArena
extends RefCounted
## Turnierplatz-Arena (RW-5) — statische Bau-Helfer für die 3D-Szene.
## Passt zur RW-1-Zone `turnierplatz` (arena-Rect 96×60 m, flaches
## Plateau), läuft aber standalone am Ursprung: Sandplatz, Zaunring mit
## Einritt-Lücke, Tribüne mit Publikum, Fahnen, Podium. Wiederholtes
## läuft als MultiMesh (Draw-Call-Budget ≤ 350, RW-4-Muster).

## W14: Sand/Gras einen Tick tiefer/waermer — die 0.87er/0.78er-Albedos
## brannten unter dem Arena-Licht weiss aus (GAMESQA-Audit c=1,
## s. comp_lauf._baue_stage; Gras-Referenz: hide_seek 0.5/0.74/0.42).
## W16 Eich-Runde 2: W14 landete erst bei Boden-Luma ~209 — das Zielband
## der "gut"-Referenz hide_seek ist ~150–170. SAND/GRAS/CREME runter
## (Scout-Vorschlag §6), der Rest kommt ueber Tonemapper+Exposure in
## comp_lauf (gemessen: zusammen ~165 im Band).
const SAND := Color(0.67, 0.56, 0.39)
const GRAS := Color(0.46, 0.66, 0.36)
const HOLZ := Color(0.79, 0.55, 0.35)
const HOLZ_DUNKEL := Color(0.55, 0.38, 0.24)
const CREME := Color(0.9, 0.87, 0.78)
const FAHNEN_FARBEN: Array[Color] = [
	Color(0.91, 0.55, 0.63), Color(0.37, 0.66, 0.63), Color(0.95, 0.69, 0.3)
]
## Sandplatz (x/z, Meter) — Mitte am Ursprung.
const ARENA_RECT := Rect2(-30.0, -18.0, 60.0, 36.0)
## Erweiterte Reit-Grenzen (Geländeritt nutzt die Wiese drumherum).
const FELD_RECT := Rect2(-95.0, -70.0, 190.0, 140.0)


## Boden: Wiese + Sandplatz + Sand-Zeichnung (W16 §6: der schattenfreie
## Sand fuellte die halbe Bildflaeche strukturlos).
static func baue_boden(welt: Node3D) -> void:
	_quader(welt, Vector3(0.0, -0.15, 0.0), Vector3(220.0, 0.3, 170.0), GRAS)
	var sand := _quader(
		welt,
		Vector3(ARENA_RECT.get_center().x, 0.02, ARENA_RECT.get_center().y),
		Vector3(ARENA_RECT.size.x, 0.06, ARENA_RECT.size.y),
		SAND
	)
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_baue_sand_zeichnung(welt)


## Sand-Zeichnung: dunklere Bande innen am Zaunrand + Hufspur-Streifen auf
## den Reitlinien — EIN MultiMesh (1 Draw-Call), deterministisch geseedet.
static func _baue_sand_zeichnung(welt: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.016, 1.0)
	var zeichnung := _multi(welt, mesh, SAND.darkened(0.09), 14)
	zeichnung.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var idx := 0
	for seite: float in [-1.0, 1.0]:
		zeichnung.multimesh.set_instance_transform(
			idx,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(ARENA_RECT.size.x - 1.0, 1.0, 1.3)),
				Vector3(0.0, 0.052, seite * (ARENA_RECT.end.y - 0.75))
			)
		)
		zeichnung.multimesh.set_instance_transform(
			idx + 1,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.3, 1.0, ARENA_RECT.size.y - 4.0)),
				Vector3(seite * (ARENA_RECT.end.x - 0.75), 0.052, 0.0)
			)
		)
		idx += 2
	var rng := GoobyRng.new(2412)
	for i in 10:
		var laenge := 5.0 + rng.next() * 7.0
		zeichnung.multimesh.set_instance_transform(
			idx + i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(laenge, 1.0, 0.5 + rng.next() * 0.4)),
				Vector3(rng.next() * 42.0 - 21.0, 0.062, rng.next() * 24.0 - 12.0)
			)
		)


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


## Tribüne an der Nordseite: Stufen + Dach + Mini-Gooby-Publikum (W16 §6:
## danceParty-Muster M2 statt hautfarbener Kugeln). `zuschauer` skaliert
## mit RW-4s Tribünen-Ausbau (Basis 10). Das Publikum hängt als Meta
## "publikum" an der Wurzel — `publikum_tick()` animiert Sway/Jubel.
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
	var menge := clampi(zuschauer, 0, 24)
	if menge > 0:
		var rng := GoobyRng.new(4711)
		var plaetze: Array[Vector3] = []
		for i in menge:
			var reihe := i % 3
			var platz := -11.0 + (float(i) / 3.0) * (22.0 / maxf(1.0, ceilf(menge / 3.0)))
			plaetze.append(
				Vector3(
					platz + rng.next() * 1.4,
					0.58 + reihe * 0.55,
					-float(reihe) * 1.15 + rng.next() * 0.3
				)
			)
		wurzel.set_meta("publikum", baue_publikum(wurzel, plaetze))
	return wurzel


## Mini-Gooby-Publikum (M2, danceParty-`_build_crowd`-Muster): drei
## MultiMeshes (Körper/Köpfe/Ohren) mit Instanzfarben. Eigenes Material —
## NICHT der geteilte RanchPferd-Cache, `vertex_color_use_as_albedo` würde
## sonst auf alle Nutzer der Farbe durchschlagen. Auch der Parcours
## (parcours_deko) konsumiert diesen Helfer.
static func baue_publikum(parent: Node3D, plaetze: Array[Vector3]) -> Node3D:
	var publikum := Node3D.new()
	parent.add_child(publikum)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	var koerper := _publikum_multi(publikum, 0.3, 0.56, plaetze.size(), mat)
	var koepfe := _publikum_multi(publikum, 0.18, 0.36, plaetze.size(), mat)
	var ohren := _publikum_multi(publikum, 0.055, 0.3, plaetze.size() * 2, mat)
	for i in plaetze.size():
		var tint := Color(0.24, 0.16, 0.38).lerp(FAHNEN_FARBEN[i % FAHNEN_FARBEN.size()], 0.3)
		koerper.multimesh.set_instance_color(i, tint)
		koepfe.multimesh.set_instance_color(i, tint.lightened(0.12))
		ohren.multimesh.set_instance_color(i * 2, tint.lightened(0.12))
		ohren.multimesh.set_instance_color(i * 2 + 1, tint.lightened(0.12))
	publikum.set_meta("plaetze", plaetze)
	publikum.set_meta("koerper", koerper.multimesh)
	publikum.set_meta("koepfe", koepfe.multimesh)
	publikum.set_meta("ohren", ohren.multimesh)
	publikum_tick(publikum, 0.0, 0.0)
	return publikum


## Publikum posen: sanfter Takt-Sway; `jubel` (0..1) hebt den Hüpfer
## (Sterne/Zieleinlauf/Zeremonie). Aufrufer ticken pro Frame und dämpfen
## jubel selbst; Reduced Motion gaten sie ebenfalls selbst.
static func publikum_tick(publikum: Node3D, zeit: float, jubel: float) -> void:
	if publikum == null or not publikum.has_meta("plaetze"):
		return
	var plaetze: Array = publikum.get_meta("plaetze")
	var koerper: MultiMesh = publikum.get_meta("koerper")
	var koepfe: MultiMesh = publikum.get_meta("koepfe")
	var ohren: MultiMesh = publikum.get_meta("ohren")
	var staerke := clampf(jubel, 0.0, 1.0)
	for i in plaetze.size():
		var hop := maxf(0.0, sin(zeit * 5.6 + float(i) * 1.7)) * (0.04 + 0.26 * staerke)
		var sway := sin(zeit * 2.3 + float(i) * 0.9) * 0.05
		var at: Vector3 = plaetze[i] + Vector3(sway * 0.4, hop, 0.0)
		koerper.set_instance_transform(i, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.3, 0.0)))
		koepfe.set_instance_transform(
			i, Transform3D(Basis(Vector3.BACK, sway), at + Vector3(0.0, 0.66, 0.0))
		)
		for seite in 2:
			var ohr_x := (-0.09 if seite == 0 else 0.09) + sway * 0.5
			ohren.set_instance_transform(
				i * 2 + seite,
				Transform3D(
					Basis(Vector3.BACK, sway * 2.0), at + Vector3(ohr_x, 0.9 + hop * 0.3, 0.0)
				)
			)


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


## Deko-Bäume rund ums Feld: Kronen + Stämme (je EIN MultiMesh, identische
## Plätze). W16 §6: vorher schwebten die Kronen stammlos auf fixem y=2.0 —
## kleine Exemplare hingen sichtbar in der Luft. Jetzt skaliert die Höhe
## mit, die Krone sitzt bodenbündig auf ihrem Stamm.
static func baue_baeume(welt: Node3D, seed_wert: int) -> void:
	var rng := GoobyRng.new(seed_wert)
	var plaetze: Array[Vector3] = []
	var groessen: Array[float] = []
	for i in 18:
		var winkel := TAU * i / 18.0 + rng.next() * 0.3
		var radius := 62.0 + rng.next() * 28.0
		plaetze.append(Vector3(cos(winkel) * radius, 0.0, sin(winkel) * radius * 0.75))
		groessen.append(0.8 + rng.next() * 0.6)
	var kugel := SphereMesh.new()
	kugel.radius = 1.8
	kugel.height = 3.6
	kugel.radial_segments = 10
	kugel.rings = 5
	var kronen := _multi(welt, kugel, Color(0.4, 0.66, 0.4), plaetze.size())
	kronen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stamm := CylinderMesh.new()
	stamm.top_radius = 0.16
	stamm.bottom_radius = 0.22
	stamm.height = 2.2
	stamm.radial_segments = 6
	var staemme := _multi(welt, stamm, HOLZ_DUNKEL, plaetze.size())
	staemme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in plaetze.size():
		var s := groessen[i]
		kronen.multimesh.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * s), plaetze[i] + Vector3(0.0, 2.75 * s, 0.0)
			)
		)
		staemme.multimesh.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * s), plaetze[i] + Vector3(0.0, 1.1 * s, 0.0)
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


## Publikum-Teilmesh (Kugel) mit Instanzfarben; `mat` liegt am Mesh, damit
## `use_colors` greift (material_override würde die Instanzfarben schlucken).
static func _publikum_multi(
	parent: Node3D, radius: float, hoehe: float, anzahl: int, mat: StandardMaterial3D
) -> MultiMeshInstance3D:
	var kugel := SphereMesh.new()
	kugel.radius = radius
	kugel.height = hoehe
	kugel.radial_segments = 8
	kugel.rings = 4
	kugel.material = mat
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = kugel
	mm.instance_count = maxi(0, anzahl)
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


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
