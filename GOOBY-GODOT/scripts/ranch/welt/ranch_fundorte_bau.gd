class_name RanchFundorteBau
extends RefCounted
## Visuals der Entdeckungsorte (FB-2 „Dinge zum Erkunden"): baut je
## Fundort aus RanchEntdeckungen eine kleine, lesbare Landmarke —
## Wasserfall mit Gischt, Höhle mit dunklem Eingang, den alten Baum,
## Steinkreis, Aussichts-Steinhaufen und die versteckten Truhen mit
## Funkel-Quad. Alles aus Kit-Assets + Pastell-Primitiven; wiederholte
## Steine als MultiMesh (Draw-Call-Budget), Gischt-Partikel skalieren
## über den Qualitäts-Partikelfaktor.

const ASSETS := "res://assets/ranch"

const TRUHE_HOLZ := Color("#8A5B3C")
const TRUHE_GOLD := Color("#E8C96E")
const FUNKEL_GELB := Color(1.0, 0.92, 0.55, 0.85)
const WASSER_FALL := Color(0.45, 0.76, 0.96, 0.95)
const GISCHT_WEISS := Color(0.96, 0.99, 1.0, 0.8)
const HOEHLE_DUNKEL := Color(0.10, 0.09, 0.11)

var _bau: RanchBau
var _partikel_faktor := 1.0


func _init(partikel_faktor := 1.0) -> void:
	_partikel_faktor = clampf(partikel_faktor, 0.0, 1.0)


## Baut alle Fundort-Visuals unter `wurzel`; Rückgabe = Gruppe.
func baue(wurzel: Node3D) -> Node3D:
	var gruppe := Node3D.new()
	gruppe.name = "Fundorte"
	wurzel.add_child(gruppe)
	_bau = RanchBau.new(gruppe)
	_baue_wasserfall(gruppe)
	_baue_hoehle(gruppe)
	_baue_alten_baum(gruppe)
	_baue_steinkreis(gruppe)
	_baue_steinhaufen(gruppe, "aussicht_kamm")
	_baue_aussicht_see(gruppe)
	for id: String in ["truhe_wald", "truhe_scheune", "truhe_ufer"]:
		_baue_truhe(gruppe, id)
	return gruppe


## ------------------------------------------------------------- Fundorte


## Wasserfall: hohe Felswand quer zur Anreise, breites Fallband mit
## Schaumstreifen, Kaskadenstufe, Becken mit Gischtkranz + Partikel.
## (Review-Iteration: die erste Fassung war ein flacher Glas-Quader.)
func _baue_wasserfall(gruppe: Node3D) -> void:
	var p := _pos("wasserfall")
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var blick := _blick("wasserfall")
	var richtung := (blick - p).normalized()
	var rot := atan2(richtung.x, richtung.y)
	var rot_basis := Basis(Vector3.UP, rot)
	var wf := Node3D.new()
	wf.name = "Wasserfall"
	wf.position = Vector3(p.x, boden, p.y)
	wf.rotation.y = rot
	gruppe.add_child(wf)
	var kante := 9.0
	# Klippe: gestufte Fels-Quader (rock_largeA ist nativ nur 0,26 m hoch —
	# als Wand skaliert wirkte er wie ein Kieshaufen). Mittelblock trägt die
	# Kante, niedrigere Schultern + Kronen-Blöcke brechen die Silhouette,
	# dunkle Grau-Braun-Töne statt Creme (Mittagslicht wusch alles aus).
	var fels_warm := Color(0.55, 0.49, 0.45)
	var fels_hell := Color(0.64, 0.58, 0.52)
	var klippe: Array[Array] = [
		[Vector3(0.0, kante / 2.0 - 0.8, -2.6), Vector3(11.0, kante + 1.6, 4.6), 0.0, fels_warm],
		[Vector3(-7.8, kante * 0.28, -2.0), Vector3(6.6, kante * 0.56, 4.4), 0.24, fels_hell],
		[Vector3(7.8, kante * 0.32, -2.0), Vector3(6.6, kante * 0.64, 4.4), -0.2, fels_hell],
		[Vector3(-3.6, kante + 0.4, -2.2), Vector3(4.2, 2.6, 3.4), 0.5, fels_hell],
		[Vector3(3.2, kante + 0.9, -2.4), Vector3(3.4, 3.6, 3.0), -0.4, fels_warm],
		[Vector3(0.2, kante + 0.1, -1.5), Vector3(6.4, 1.6, 2.6), 0.12, fels_hell],
	]
	for teil: Array in klippe:
		var block := _quader(wf, teil[0], teil[1], teil[3], false)
		block.rotation.y = float(teil[2])
	# Boulder-Akzente am Wandfuß + zwei Wächter-Felsen am Becken.
	var felsen: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = RanchKarte.seed_wert() + 401
	for i in 6:
		var quer := (float(i) - 2.5) * 2.9
		var lokal := Vector3(
			quer + rng.randf_range(-0.6, 0.6), -0.3, 0.6 + rng.randf_range(0.0, 0.9)
		)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3(rng.randf_range(3.4, 5.0), rng.randf_range(6.0, 9.0), 3.4))
		felsen.append(Transform3D(rot_basis * basis, wf.position + rot_basis * lokal))
	for seite: float in [-1.0, 1.0]:
		var basis := Basis(Vector3.UP, seite * 0.8).scaled(Vector3(5.0, 8.0, 5.0))
		felsen.append(
			Transform3D(
				rot_basis * basis, wf.position + rot_basis * Vector3(seite * 7.4, -0.4, 4.4)
			)
		)
	_bau.baue_multimesh(gruppe, "%s/natur/rock_largeA.glb" % ASSETS, felsen)
	# Fallband (breit) + zwei Seitenbänder + Kaskadenstufe auf halber Höhe.
	var fall := _quader(
		wf, Vector3(0.0, kante / 2.0, 0.3), Vector3(6.4, kante, 0.6), WASSER_FALL, true
	)
	fall.name = "WasserfallBand"
	for seite: float in [-1.0, 1.0]:
		_quader(
			wf,
			Vector3(seite * 4.1, kante * 0.32, 0.25),
			Vector3(1.5, kante * 0.64, 0.5),
			WASSER_FALL,
			true
		)
	_quader(wf, Vector3(0.0, kante * 0.52, 0.85), Vector3(4.6, 0.7, 1.1), GISCHT_WEISS, true)
	# Schaumstreifen klar VOR dem Band (schmale weiße Bahnen).
	for x: float in [-1.7, -0.4, 1.1, 2.2]:
		_quader(
			wf, Vector3(x, kante / 2.0, 0.74), Vector3(0.34, kante * 0.94, 0.06), GISCHT_WEISS, true
		)
	# Becken: Gischtkranz (weiß, größer) unter der Wasserscheibe (blau).
	_scheibe(wf, Vector3(0.0, 0.10, 3.2), 7.0, GISCHT_WEISS)
	_scheibe(wf, Vector3(0.0, 0.16, 3.2), 6.2, Color(0.55, 0.79, 0.94, 0.85))
	_scheibe(wf, Vector3(0.0, 0.22, 1.2), 3.2, GISCHT_WEISS)
	var gischt := GPUParticles3D.new()
	gischt.name = "WasserfallGischt"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(2.8, 0.4, 1.0)
	mat.direction = Vector3(0.0, 1.0, 0.4)
	mat.spread = 35.0
	mat.initial_velocity_min = 1.6
	mat.initial_velocity_max = 3.2
	mat.gravity = Vector3(0.0, -3.4, 0.0)
	gischt.process_material = mat
	gischt.amount = maxi(6, int(round(36.0 * _partikel_faktor)))
	gischt.lifetime = 1.5
	gischt.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 14.0, 16.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var gischt_mat := _unlit(GISCHT_WEISS)
	gischt_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = gischt_mat
	gischt.draw_pass_1 = quad
	gischt.position = Vector3(0.0, 0.5, 1.4)
	wf.add_child(gischt)


## Höhle: Felsbogen + dunkler Eingang am Hügelkamm-Fuß.
func _baue_hoehle(gruppe: Node3D) -> void:
	var p := _pos("hoehle")
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var blick := _blick("hoehle")
	var richtung := (blick - p).normalized()
	var rot := atan2(richtung.x, richtung.y)
	var felsen: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = RanchKarte.seed_wert() + 402
	for i in 9:
		var winkel := rot + PI / 2.0 + float(i) / 8.0 * PI
		var fp := p + Vector2.from_angle(winkel + PI / 2.0) * rng.randf_range(3.0, 6.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var skala := rng.randf_range(4.5, 8.0)
		# Y deutlich überhöht (nativer Fels ist flach) -> lesbarer Felsbogen.
		basis = basis.scaled(Vector3(skala, skala * rng.randf_range(2.2, 3.2), skala))
		felsen.append(
			Transform3D(basis, Vector3(fp.x, RanchGelaende.hoehe(fp.x, fp.y) - 0.6, fp.y))
		)
	_bau.baue_multimesh(gruppe, "%s/natur/rock_largeA.glb" % ASSETS, felsen)
	var eingang := MeshInstance3D.new()
	eingang.name = "HoehlenEingang"
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 2.4
	scheibe.bottom_radius = 2.9
	scheibe.height = 0.3
	scheibe.radial_segments = 16
	scheibe.material = _unlit(HOEHLE_DUNKEL)
	eingang.mesh = scheibe
	eingang.position = Vector3(p.x, boden + 2.2, p.y)
	eingang.rotation = Vector3(PI / 2.0, rot, 0.0)
	eingang.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gruppe.add_child(eingang)


## Der alte Baum: riesiger Solitär mit Blumenring und Sitz-Stümpfen.
func _baue_alten_baum(gruppe: Node3D) -> void:
	var p := _pos("alter_baum")
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var baum := _bau.lade_glb("%s/natur/tree_fat.glb" % ASSETS, 26.0)
	if baum != null:
		baum.name = "AlterBaum"
		baum.position = Vector3(p.x, boden - 0.5, p.y)
		gruppe.add_child(baum)
	var stuempfe: Array = []
	var blumen: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = RanchKarte.seed_wert() + 403
	for i in 3:
		var winkel := float(i) / 3.0 * TAU + 0.5
		var sp := p + Vector2.from_angle(winkel) * 7.5
		var basis := Basis(Vector3.UP, winkel).scaled(Vector3.ONE * 3.0)
		stuempfe.append(Transform3D(basis, Vector3(sp.x, RanchGelaende.hoehe(sp.x, sp.y), sp.y)))
	for _i in 16:
		var winkel := rng.randf() * TAU
		var bp := p + Vector2.from_angle(winkel) * rng.randf_range(9.0, 14.0)
		var basis := Basis(Vector3.UP, winkel).scaled(Vector3.ONE * rng.randf_range(2.4, 3.4))
		blumen.append(Transform3D(basis, Vector3(bp.x, RanchGelaende.hoehe(bp.x, bp.y), bp.y)))
	_bau.baue_multimesh(gruppe, "%s/natur/stump_round.glb" % ASSETS, stuempfe)
	_bau.baue_multimesh(
		gruppe, "%s/natur/flower_yellowA.glb" % ASSETS, blumen, "", RanchBau.KLEINTEIL_SICHT_M
	)


## Steinkreis: acht aufrechte Menhire + flacher Mittelstein. rock_largeA
## ist nativ nur 0,26 m hoch — für 3,5–4,5 m Menhire braucht es Y-Skala ~15.
func _baue_steinkreis(gruppe: Node3D) -> void:
	var p := _pos("steinkreis")
	var steine: Array = []
	for i in 8:
		var winkel := float(i) / 8.0 * TAU
		var sp := p + Vector2.from_angle(winkel) * 7.0
		var basis := Basis(Vector3.UP, -winkel)
		basis = basis.scaled(Vector3(2.2, 15.5 + 2.5 * sin(float(i) * 2.1), 2.0))
		steine.append(
			Transform3D(basis, Vector3(sp.x, RanchGelaende.hoehe(sp.x, sp.y) - 0.3, sp.y))
		)
	var mitte_basis := Basis(Vector3.UP, 0.4).scaled(Vector3(4.6, 2.4, 4.6))
	steine.append(Transform3D(mitte_basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y) - 0.2, p.y)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_largeA.glb" % ASSETS, steine)


## Steinhaufen (Cairn) für Aussichtspunkte.
func _baue_steinhaufen(gruppe: Node3D, id: String) -> void:
	var p := _pos(id)
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var steine: Array = []
	for i in 4:
		var skala := 2.4 - float(i) * 0.45
		var basis := Basis(Vector3.UP, float(i) * 1.1).scaled(Vector3.ONE * skala)
		steine.append(Transform3D(basis, Vector3(p.x + 3.0, boden + float(i) * 0.55, p.y + 3.0)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_smallA.glb" % ASSETS, steine)


## See-Aussicht: Geländer aus Zaunlatten + Sitz-Stamm Richtung See.
func _baue_aussicht_see(gruppe: Node3D) -> void:
	var p := _pos("aussicht_see")
	var blick := _blick("aussicht_see")
	var richtung := (blick - p).normalized()
	var rot := atan2(richtung.x, richtung.y)
	var latten: Array = []
	for i in 5:
		var quer := Vector2(richtung.y, -richtung.x) * (float(i) - 2.0) * 2.4
		var lp := p + richtung * 4.0 + quer
		var basis := Basis(Vector3.UP, rot + PI / 2.0).scaled(Vector3.ONE * 2.6)
		latten.append(Transform3D(basis, Vector3(lp.x, RanchGelaende.hoehe(lp.x, lp.y), lp.y)))
	_bau.baue_multimesh(gruppe, "%s/natur/fence_simple.glb" % ASSETS, latten)
	var stamm := _bau.lade_glb("%s/natur/log.glb" % ASSETS, 4.0)
	if stamm != null:
		stamm.position = Vector3(p.x - richtung.x * 2.0, RanchGelaende.hoehe(p.x, p.y), p.y)
		stamm.rotation.y = rot + PI / 2.0
		gruppe.add_child(stamm)
	_baue_steinhaufen(gruppe, "aussicht_see")


## Versteckte Truhe: Holzkorpus, Golddeckel-Band, Funkel-Quad obendrauf.
func _baue_truhe(gruppe: Node3D, id: String) -> void:
	var p := _pos(id)
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var truhe := Node3D.new()
	truhe.name = "Truhe_%s" % id
	truhe.position = Vector3(p.x, boden, p.y)
	truhe.rotation.y = p.x * 0.7
	gruppe.add_child(truhe)
	_quader(truhe, Vector3(0.0, 0.5, 0.0), Vector3(1.6, 1.0, 1.1), TRUHE_HOLZ, false)
	_quader(truhe, Vector3(0.0, 1.08, 0.0), Vector3(1.7, 0.28, 1.2), TRUHE_HOLZ, false)
	_quader(truhe, Vector3(0.0, 0.75, 0.0), Vector3(1.72, 0.18, 1.14), TRUHE_GOLD, false)
	var funkel := MeshInstance3D.new()
	funkel.name = "Funkel"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var mat := _unlit(FUNKEL_GELB)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	funkel.mesh = quad
	funkel.position = Vector3(0.0, 2.0, 0.0)
	funkel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	truhe.add_child(funkel)


## ------------------------------------------------------------- Werkzeug


func _pos(id: String) -> Vector2:
	return RanchEntdeckungen.position_von(RanchEntdeckungen.fundort(id))


func _blick(id: String) -> Vector2:
	var blick: Array = RanchEntdeckungen.fundort(id)["blick"]
	return Vector2(float(blick[0]), float(blick[1]))


func _quader(
	wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color, unshaded: bool
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = _unlit(farbe) if unshaded else RanchPferd.material(farbe)
	mi.mesh = mesh
	mi.position = pos
	if unshaded:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)
	return mi


## Flache Wasser-/Schaumscheibe (unshaded, ohne Schatten).
func _scheibe(wurzel: Node3D, pos: Vector3, radius: float, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.12
	mesh.radial_segments = 22
	mesh.material = _unlit(farbe)
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)
	return mi


func _unlit(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = farbe
	if farbe.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
