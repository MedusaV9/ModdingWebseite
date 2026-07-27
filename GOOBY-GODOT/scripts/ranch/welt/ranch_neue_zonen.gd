class_name RanchNeueZonen
extends RefCounted
## Zonen-Ausstattung des WELT-1-Ausbaus: baut je NEUE Zone eine eigene
## Deko-Gruppe (Node3D, Muster RanchZonenDeko) — Bergmassiv (Hängebrücke,
## Gipfelkreuz, Geröll, Serpentinen-Steinmänner, Bergsee-Schilf),
## Blumenwiese (Lavendel-Reihen + Bienenstöcke), Moor (Stege, Binsen,
## Totholz, Irrlicht), Ruine (Turm + Mauerreste + Schutt), Strand
## (Ruderboot, Sonnenschirm, Treibholz, Muschel), Obstgarten (Baumraster
## mit Früchten, Leiter, Picknick) und Kornfeld (Kornreihen mit Gassen,
## Kornkreis, Vogelscheuche, Kürbisse). Wiederholtes IMMER als MultiMesh
## (1 Draw-Call je Sorte), Kleinteile mit Sichtweiten-Culling.

const ASSETS := "res://assets/ranch"

const STEIN_GRAU := Color(0.62, 0.6, 0.58)
const STEIN_ALT := Color(0.55, 0.52, 0.5)
const HOLZ_ALT := Color(0.62, 0.55, 0.47)
const SEIL_BRAUN := Color(0.48, 0.38, 0.26)
const BOOT_ROT := Color(0.72, 0.4, 0.34)
const SCHIRM_ROSA := Color(0.94, 0.62, 0.66)
const STROH_GELB := Color(0.87, 0.74, 0.45)
const IRRLICHT_BLAU := Color(0.55, 0.85, 1.0, 0.85)

## Kleinteil-Sichtweite der neuen Zonen (Meter, Budget).
const KLEIN_SICHT_M := 180.0

var _seed_wert := 0
var _bau: RanchBau


func _init(seed_wert: int) -> void:
	_seed_wert = seed_wert


## Baut alle neuen Zonen-Gruppen unter `wurzel`; Rückgabe zone_id → Gruppe
## (die Szene merged das in ihr Abstands-Streaming).
func baue(wurzel: Node3D) -> Dictionary:
	_bau = RanchBau.new(wurzel)
	var gruppen := {}
	gruppen["bergmassiv"] = _baue_bergmassiv(wurzel)
	gruppen["blumenwiese"] = _baue_blumenwiese(wurzel)
	gruppen["moor"] = _baue_moor(wurzel)
	gruppen["ruine"] = _baue_ruine(wurzel)
	gruppen["strand"] = _baue_strand(wurzel)
	gruppen["obstgarten"] = _baue_obstgarten(wurzel)
	gruppen["kornfeld"] = _baue_kornfeld(wurzel)
	return gruppen


## --------------------------------------------------------- Bergmassiv


func _baue_bergmassiv(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "bergmassiv")
	var zone := RanchKarte.zone("bergmassiv")
	_baue_haengebruecke(gruppe)
	_baue_gipfelkreuz(gruppe, zone)
	_baue_geroell(gruppe, zone)
	_baue_bergsee_ufer(gruppe, zone)
	_baue_serpentinen_marken(gruppe)
	var spawn: Array = zone["spawn"]
	var schild := _bau.baue_schild(
		Vector3(float(spawn[0]) + 6.0, 0.0, float(spawn[1]) + 6.0),
		I18nService.t("rwelt.zone.bergmassiv"),
		I18nService.t("rwelt.hud.plateau")
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	# Text zeigt zur Plateau-Mitte (sonst liest man ihn spiegelverkehrt).
	schild.rotation.y = PI
	return gruppe


## Hängebrücke über die Schlucht: Planken folgen der reit_hoehe-Deckkurve
## (Durchhang), Seile + Pfosten als eigene MultiMeshes.
func _baue_haengebruecke(gruppe: Node3D) -> void:
	var daten: Dictionary = RanchKarte.bruecken()[0]
	var a := Vector2(float(daten["a"][0]), float(daten["a"][1]))
	var b := Vector2(float(daten["b"][0]), float(daten["b"][1]))
	var breite := float(daten["breite"])
	var planken: Array = []
	var pfosten: Array = []
	var seile: Array = []
	var n := 20
	var richtung := (b - a).normalized()
	var quer := Vector2(-richtung.y, richtung.x)
	var vorher := Vector3.ZERO
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		var y := RanchGelaende.reit_hoehe(p.x, p.y) - 0.06
		var basis := Basis(Vector3.UP, atan2(richtung.x, richtung.y))
		basis = basis.scaled(Vector3(breite + 0.7, 0.11, 2.0))
		planken.append(Transform3D(basis, Vector3(p.x, y, p.y)))
		var deck := Vector3(p.x, y, p.y)
		if i % 4 == 0:
			for seite: float in [-1.0, 1.0]:
				var pp := p + quer * seite * (breite / 2.0 + 0.25)
				var pb := Basis(Vector3.UP, 0.0).scaled(Vector3(0.13, 1.15, 0.13))
				pfosten.append(Transform3D(pb, Vector3(pp.x, y + 0.55, pp.y)))
		if i > 0:
			for seite: float in [-1.0, 1.0]:
				seile.append(_seil_transform(vorher, deck, quer, seite, breite))
		vorher = deck
	_multimesh_box(gruppe, "BrueckenPlanken", Vector3.ONE, planken, RanchBau.HOLZ_HELL)
	_multimesh_box(gruppe, "BrueckenPfosten", Vector3.ONE, pfosten, RanchBau.HOLZ_DUNKEL)
	_multimesh_box(gruppe, "BrueckenSeile", Vector3.ONE, seile, SEIL_BRAUN)


## Seil-Segment als gestreckter, zum Gefälle gedrehter Box-Transform.
func _seil_transform(
	von: Vector3, bis: Vector3, quer: Vector2, seite: float, breite: float
) -> Transform3D:
	var versatz := Vector3(quer.x, 0.0, quer.y) * seite * (breite / 2.0 + 0.25)
	var start := von + versatz + Vector3(0.0, 1.05, 0.0)
	var ende := bis + versatz + Vector3(0.0, 1.05, 0.0)
	var mitte := (start + ende) / 2.0
	var laenge := start.distance_to(ende)
	var flach := Vector2(ende.x - start.x, ende.z - start.z).length()
	var basis := Basis(Vector3.UP, atan2(ende.x - start.x, ende.z - start.z))
	basis = basis.rotated(basis.x.normalized(), -atan2(ende.y - start.y, maxf(flach, 0.01)))
	return Transform3D(basis.scaled(Vector3(0.06, 0.06, laenge)), mitte)


func _baue_gipfelkreuz(gruppe: Node3D, zone: Dictionary) -> void:
	var gipfel: Array = zone["gipfel"]
	var gx := float(gipfel[0])
	var gz := float(gipfel[1])
	var boden := RanchGelaende.hoehe(gx, gz)
	_quader(gruppe, Vector3(gx, boden + 2.6, gz), Vector3(0.34, 5.2, 0.34), HOLZ_ALT)
	_quader(gruppe, Vector3(gx, boden + 4.1, gz), Vector3(2.2, 0.34, 0.34), HOLZ_ALT)
	var steine: Array = []
	for i in 5:
		var skala := 3.0 - float(i) * 0.5
		var basis := Basis(Vector3.UP, float(i) * 1.3).scaled(Vector3.ONE * skala)
		steine.append(Transform3D(basis, Vector3(gx, boden + float(i) * 0.42 - 0.2, gz)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_smallA.glb" % ASSETS, steine)


## Geröllfelder: kleine Felsen an den steilen Flanken (deterministisch).
func _baue_geroell(gruppe: Node3D, zone: Dictionary) -> void:
	var rng := _rng(31)
	var rect := RanchKarte.zone_rect(zone)
	var brocken: Array = []
	for _i in 240:
		var p := _zufall_in(rect, rng)
		var h := RanchGelaende.hoehe(p.x, p.y)
		if h < 22.0 or h > 60.0:
			continue
		var n := RanchGelaende.normale(p.x, p.y)
		if n.y > 0.94:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * rng.randf_range(1.2, 3.4))
		brocken.append(Transform3D(basis, Vector3(p.x, h - 0.1, p.y)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_smallA.glb" % ASSETS, brocken)


func _baue_bergsee_ufer(gruppe: Node3D, zone: Dictionary) -> void:
	var mitte: Array = zone["bergsee_mitte"]
	var mx := float(mitte[0])
	var mz := float(mitte[1])
	var radius := float(zone["bergsee_radius"])
	var wasser := float(zone["bergsee_wasser"])
	var rng := _rng(32)
	var schilf: Array = []
	for _i in 34:
		var w := rng.randf() * TAU
		var p := Vector2(mx, mz) + Vector2.from_angle(w) * radius * rng.randf_range(1.05, 1.3)
		var h := RanchGelaende.hoehe(p.x, p.y)
		if h > wasser - 0.2:
			schilf.append(_boden_transform(p, w, rng.randf_range(2.4, 3.6)))
	_bau.baue_multimesh(gruppe, "%s/natur/grass_large.glb" % ASSETS, schilf, "", KLEIN_SICHT_M)
	var rosen: Array = []
	for _i in 8:
		var w := rng.randf() * TAU
		var p := Vector2(mx, mz) + Vector2.from_angle(w) * radius * rng.randf_range(0.2, 0.7)
		var basis := Basis(Vector3.UP, w).scaled(Vector3.ONE * rng.randf_range(2.0, 3.0))
		rosen.append(Transform3D(basis, Vector3(p.x, wasser + 0.06, p.y)))
	_multimesh_flora(gruppe, "seerose", rosen)


## Steinmänner entlang der Serpentine: man SIEHT immer, wo es weitergeht.
func _baue_serpentinen_marken(gruppe: Node3D) -> void:
	var punkte := RanchKarte.wegpunkte("huegelkamm", "bergmassiv")
	var steine: Array = []
	for i in punkte.size() - 1:
		var mitte: Vector3 = (punkte[i] + punkte[i + 1]) / 2.0
		var seit := (punkte[i + 1] - punkte[i]).cross(Vector3.UP).normalized() * 3.2
		for lage in 3:
			var skala := 1.8 - float(lage) * 0.45
			var basis := Basis(Vector3.UP, float(i + lage) * 1.1).scaled(Vector3.ONE * skala)
			var fuss := mitte + seit
			var y := RanchGelaende.hoehe(fuss.x, fuss.z) + float(lage) * 0.26
			steine.append(Transform3D(basis, Vector3(fuss.x, y, fuss.z)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_smallA.glb" % ASSETS, steine)


## -------------------------------------------------------- Blumenwiese


func _baue_blumenwiese(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "blumenwiese")
	var zone := RanchKarte.zone("blumenwiese")
	var feld: Array = zone["lavendel_rect"]
	var rect := Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3]))
	var rng := _rng(41)
	var lavendel: Array = []
	var reihen := int(rect.size.y / 5.0)
	for reihe in reihen:
		var z := rect.position.y + 3.0 + float(reihe) * 5.0
		var x := rect.position.x + 3.0
		while x < rect.end.x - 3.0:
			var p := Vector2(x + rng.randf_range(-0.4, 0.4), z + rng.randf_range(-0.5, 0.5))
			if not RanchGelaende.ist_wasser(p.x, p.y):
				lavendel.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(1.0, 1.35)))
			x += 1.9
	_multimesh_flora(gruppe, "lavendel", lavendel)
	_baue_bienenstoecke(gruppe)
	var blumen: Array = []
	for _i in 70:
		var p := _zufall_in(RanchKarte.zone_rect(zone), rng)
		if not rect.has_point(p) and not RanchGelaende.ist_wasser(p.x, p.y):
			blumen.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.4, 3.4)))
	_bau.baue_multimesh(gruppe, "%s/natur/flower_purpleA.glb" % ASSETS, blumen, "", KLEIN_SICHT_M)
	return gruppe


func _baue_bienenstoecke(gruppe: Node3D) -> void:
	var fund := RanchEntdeckungen.fundort("lavendel_bienen")
	var p := RanchEntdeckungen.position_von(fund)
	for i in 3:
		var pos := Vector3(p.x + float(i) * 2.4 - 2.4, 0.0, p.y + float(i % 2) * 1.6)
		pos.y = RanchGelaende.hoehe(pos.x, pos.z)
		_quader(gruppe, pos + Vector3(0.0, 0.55, 0.0), Vector3(1.1, 1.1, 1.1), _bienen_farbe(i))
		_quader(gruppe, pos + Vector3(0.0, 1.22, 0.0), Vector3(1.3, 0.24, 1.3), HOLZ_ALT)


## Bienenstock-Farbvariation (Pastell-Gelbtöne).
func _bienen_farbe(i: int) -> Color:
	return STROH_GELB.lerp(Color(0.95, 0.87, 0.62), float(i) * 0.35)


## --------------------------------------------------------------- Moor


func _baue_moor(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "moor")
	var zone := RanchKarte.zone("moor")
	_baue_stege(gruppe)
	var rng := _rng(51)
	var binsen: Array = []
	for paar: Array in zone["tuempel"]:
		var mitte := Vector2(float(paar[0]), float(paar[1]))
		for _i in 30:
			var w := rng.randf() * TAU
			var p := mitte + Vector2.from_angle(w) * rng.randf_range(9.0, 20.0)
			if not RanchGelaende.ist_wasser(p.x, p.y):
				binsen.append(_boden_transform(p, w, rng.randf_range(1.1, 1.7)))
	_multimesh_flora(gruppe, "binse", binsen)
	var rosen: Array = []
	for paar: Array in zone["tuempel"]:
		for _i in 4:
			var p := Vector2(float(paar[0]), float(paar[1]))
			p += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 6.0)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = basis.scaled(Vector3.ONE * rng.randf_range(2.2, 3.2))
			rosen.append(Transform3D(basis, Vector3(p.x, -0.6, p.y)))
	_multimesh_flora(gruppe, "seerose", rosen)
	var totholz: Array = []
	for _i in 14:
		var p := _zufall_in(RanchKarte.zone_rect(zone), rng)
		if not RanchGelaende.ist_wasser(p.x, p.y):
			totholz.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.6, 4.2)))
	_bau.baue_multimesh(gruppe, "%s/natur/log.glb" % ASSETS, totholz)
	_baue_irrlicht(gruppe)
	return gruppe


## Holzstege durchs nasse Moor: Planken-MultiMesh entlang einer Polyline.
func _baue_stege(gruppe: Node3D) -> void:
	var pfad: Array[Vector2] = [
		Vector2(788.0, -96.0),
		Vector2(812.0, -128.0),
		Vector2(836.0, -158.0),
		Vector2(842.0, -172.0),
		Vector2(820.0, -200.0),
	]
	var planken: Array = []
	var pfosten: Array = []
	for i in pfad.size() - 1:
		var von := pfad[i]
		var bis := pfad[i + 1]
		var schritte := maxi(1, int(von.distance_to(bis) / 1.4))
		var rot := atan2(bis.x - von.x, bis.y - von.y)
		for s in schritte:
			var p := von.lerp(bis, float(s) / float(schritte))
			var y := maxf(RanchGelaende.hoehe(p.x, p.y), -0.75) + 0.42
			var basis := Basis(Vector3.UP, rot).scaled(Vector3(2.2, 0.1, 1.2))
			planken.append(Transform3D(basis, Vector3(p.x, y, p.y)))
			if s % 5 == 0:
				for seite: float in [-1.0, 1.0]:
					var quer := Vector2(cos(rot), -sin(rot)) * seite * 1.0
					var fb := Basis(Vector3.UP, 0.0).scaled(Vector3(0.14, 1.3, 0.14))
					pfosten.append(Transform3D(fb, Vector3(p.x + quer.x, y - 0.55, p.y + quer.y)))
	_multimesh_box(gruppe, "MoorStegPlanken", Vector3.ONE, planken, RanchBau.HOLZ_HELL)
	_multimesh_box(gruppe, "MoorStegPfosten", Vector3.ONE, pfosten, RanchBau.HOLZ_DUNKEL)


## Irrlicht: schwebendes blaues Funkeln + schwaches Licht am Fundort.
func _baue_irrlicht(gruppe: Node3D) -> void:
	var fund := RanchEntdeckungen.fundort("moor_irrlicht")
	var p := RanchEntdeckungen.position_von(fund)
	var y := RanchGelaende.hoehe(p.x, p.y) + 1.6
	var funkel := MeshInstance3D.new()
	funkel.name = "Irrlicht"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = IRRLICHT_BLAU
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	funkel.mesh = quad
	funkel.position = Vector3(p.x, y, p.y)
	funkel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gruppe.add_child(funkel)
	var licht := OmniLight3D.new()
	licht.name = "IrrlichtSchein"
	licht.position = Vector3(p.x, y, p.y)
	licht.light_color = Color(0.55, 0.85, 1.0)
	licht.light_energy = 1.1
	licht.omni_range = 9.0
	gruppe.add_child(licht)


## -------------------------------------------------------------- Ruine


func _baue_ruine(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "ruine")
	var zone := RanchKarte.zone("ruine")
	var turm: Array = zone["turm"]
	var tx := float(turm[0])
	var tz := float(turm[1])
	var boden := RanchGelaende.hoehe(tx, tz)
	var rumpf := MeshInstance3D.new()
	rumpf.name = "Turm"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 4.4
	mesh.bottom_radius = 5.2
	mesh.height = 11.0
	mesh.radial_segments = 12
	mesh.material = RanchPferd.material(STEIN_GRAU)
	rumpf.mesh = mesh
	rumpf.position = Vector3(tx, boden + 5.5, tz)
	gruppe.add_child(rumpf)
	var zinnen: Array = []
	for i in 9:
		var w := float(i) / 9.0 * TAU
		var p := Vector2(tx, tz) + Vector2.from_angle(w) * 4.3
		var hoch := 11.4 - (3.4 if i >= 5 and i <= 7 else 0.0)
		var basis := Basis(Vector3.UP, -w).scaled(Vector3(1.3, 1.6, 0.9))
		zinnen.append(Transform3D(basis, Vector3(p.x, boden + hoch, p.y)))
	_multimesh_box(gruppe, "TurmZinnen", Vector3.ONE, zinnen, STEIN_ALT)
	_baue_mauerreste(gruppe, tx, tz, boden)
	var rng := _rng(61)
	var schutt: Array = []
	for _i in 40:
		var p := (
			Vector2(tx, tz) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 26.0)
		)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3.ONE * rng.randf_range(1.6, 3.6))
		schutt.append(Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y), p.y)))
	_bau.baue_multimesh(gruppe, "%s/natur/rock_smallA.glb" % ASSETS, schutt)
	_baue_schatztruhe(gruppe, tx, tz, boden)
	return gruppe


func _baue_mauerreste(gruppe: Node3D, tx: float, tz: float, boden: float) -> void:
	var steine: Array = []
	for seite in 3:
		var w := float(seite) * TAU / 3.0 + 0.5
		var start := Vector2(tx, tz) + Vector2.from_angle(w) * 9.0
		var richtung := Vector2.from_angle(w + PI / 2.0)
		for i in 6:
			var p := start + richtung * float(i) * 2.1
			var hoch := maxf(0.8, 2.8 - float(i) * 0.45)
			var basis := Basis(Vector3.UP, -w).scaled(Vector3(2.0, hoch, 1.0))
			var y := RanchGelaende.hoehe(p.x, p.y) + hoch / 2.0
			steine.append(Transform3D(basis, Vector3(p.x, y, p.y)))
	_multimesh_box(gruppe, "MauerReste", Vector3.ONE, steine, STEIN_GRAU)
	_quader(gruppe, Vector3(tx + 5.4, boden + 1.4, tz + 1.0), Vector3(0.3, 2.8, 2.4), STEIN_ALT)


## Schatztruhe im Turm (Fundort ruine_schatz) — Muster RanchFundorteBau.
func _baue_schatztruhe(gruppe: Node3D, tx: float, tz: float, boden: float) -> void:
	var truhe := Node3D.new()
	truhe.name = "TruheRuine"
	truhe.position = Vector3(tx + 1.2, boden, tz - 0.8)
	truhe.rotation.y = 0.7
	gruppe.add_child(truhe)
	_quader(truhe, Vector3(0.0, 0.5, 0.0), Vector3(1.6, 1.0, 1.1), Color("#8A5B3C"))
	_quader(truhe, Vector3(0.0, 1.08, 0.0), Vector3(1.7, 0.28, 1.2), Color("#8A5B3C"))
	_quader(truhe, Vector3(0.0, 0.75, 0.0), Vector3(1.72, 0.18, 1.14), Color("#E8C96E"))


## -------------------------------------------------------------- Strand


func _baue_strand(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "strand")
	var zone := RanchKarte.zone("strand")
	var bucht: Array = zone["bucht_mitte"]
	var mitte := Vector2(float(bucht[0]), float(bucht[1]))
	var radius := float(zone["bucht_radius"])
	_baue_ruderboot(gruppe, mitte, radius)
	_baue_sonnenschirm(gruppe, mitte, radius)
	var rng := _rng(71)
	var treibholz: Array = []
	for _i in 8:
		var w := PI * 0.7 + rng.randf() * PI * 0.6
		var p := mitte + Vector2.from_angle(w) * radius * rng.randf_range(1.0, 1.2)
		if not RanchGelaende.ist_wasser(p.x, p.y):
			treibholz.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.2, 3.4)))
	_bau.baue_multimesh(gruppe, "%s/natur/log.glb" % ASSETS, treibholz)
	_baue_muschel(gruppe)
	return gruppe


func _baue_ruderboot(gruppe: Node3D, mitte: Vector2, radius: float) -> void:
	var p := mitte + Vector2.from_angle(PI * 0.85) * (radius * 1.02)
	var boot := Node3D.new()
	boot.name = "Ruderboot"
	boot.position = Vector3(p.x, maxf(RanchGelaende.hoehe(p.x, p.y), -0.9) + 0.3, p.y)
	boot.rotation.y = 0.8
	gruppe.add_child(boot)
	_quader(boot, Vector3(0.0, 0.0, 0.0), Vector3(1.6, 0.55, 3.6), BOOT_ROT)
	_quader(boot, Vector3(0.0, 0.1, 0.0), Vector3(1.1, 0.5, 3.0), Color(0.9, 0.85, 0.74))
	_quader(boot, Vector3(0.0, 0.32, 0.4), Vector3(1.5, 0.12, 0.4), RanchBau.HOLZ_DUNKEL)
	var ruder := _quader(boot, Vector3(1.0, 0.45, -0.4), Vector3(0.1, 0.1, 2.4), HOLZ_ALT)
	ruder.rotation.y = 0.5


func _baue_sonnenschirm(gruppe: Node3D, mitte: Vector2, radius: float) -> void:
	var p := mitte + Vector2.from_angle(PI * 1.12) * (radius * 1.14)
	var y := RanchGelaende.hoehe(p.x, p.y)
	_quader(gruppe, Vector3(p.x, y + 1.3, p.y), Vector3(0.12, 2.6, 0.12), HOLZ_ALT)
	var schirm := MeshInstance3D.new()
	schirm.name = "Sonnenschirm"
	var kegel := CylinderMesh.new()
	kegel.top_radius = 0.05
	kegel.bottom_radius = 2.2
	kegel.height = 0.9
	kegel.radial_segments = 10
	kegel.material = RanchPferd.material(SCHIRM_ROSA)
	schirm.mesh = kegel
	schirm.position = Vector3(p.x, y + 2.7, p.y)
	gruppe.add_child(schirm)
	_quader(
		gruppe,
		Vector3(p.x + 2.2, y + 0.03, p.y + 0.8),
		Vector3(1.6, 0.06, 2.6),
		Color(0.62, 0.84, 0.9)
	)


## Riesenmuschel am Sandsaum (Fundort strand_muschel).
func _baue_muschel(gruppe: Node3D) -> void:
	var fund := RanchEntdeckungen.fundort("strand_muschel")
	var p := RanchEntdeckungen.position_von(fund)
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var muschel := Node3D.new()
	muschel.name = "Muschel"
	muschel.position = Vector3(p.x, boden, p.y)
	gruppe.add_child(muschel)
	for i in 5:
		var w := (float(i) - 2.0) * 0.32
		var lamelle := _quader(
			muschel,
			Vector3(sin(w) * 0.5, 0.42, cos(w) * 0.1 - 0.1),
			Vector3(0.42, 0.85, 0.16),
			Color(0.96, 0.86, 0.9).lerp(Color(0.94, 0.72, 0.78), absf(w))
		)
		lamelle.rotation.z = w
		lamelle.rotation.x = -0.5
	var perle := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.18
	kugel.height = 0.36
	kugel.material = RanchPferd.material(Color(0.98, 0.95, 0.88))
	perle.mesh = kugel
	perle.position = Vector3(0.0, 0.24, 0.28)
	muschel.add_child(perle)


## ---------------------------------------------------------- Obstgarten


func _baue_obstgarten(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "obstgarten")
	var zone := RanchKarte.zone("obstgarten")
	var feld: Array = zone["baumraster"]
	var rect := Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3]))
	var rng := _rng(81)
	var baeume: Array = []
	var fruechte: Array = []
	var spalten := int(rect.size.x / 24.0)
	var reihen := int(rect.size.y / 24.0)
	for sx in spalten:
		for sz in reihen:
			var p := Vector2(
				rect.position.x + 12.0 + float(sx) * 24.0 + rng.randf_range(-2.5, 2.5),
				rect.position.y + 12.0 + float(sz) * 24.0 + rng.randf_range(-2.5, 2.5)
			)
			var boden := RanchGelaende.hoehe(p.x, p.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = basis.scaled(Vector3.ONE * rng.randf_range(5.4, 6.6))
			baeume.append(Transform3D(basis, Vector3(p.x, boden - 0.2, p.y)))
			for _f in 3:
				var fw := rng.randf() * TAU
				var fp := p + Vector2.from_angle(fw) * rng.randf_range(0.6, 1.8)
				var fb := Basis(Vector3.UP, fw).scaled(Vector3.ONE * 0.22)
				fruechte.append(
					Transform3D(fb, Vector3(fp.x, boden + rng.randf_range(2.4, 3.6), fp.y))
				)
	_bau.baue_multimesh(gruppe, "%s/natur/tree_oak.glb" % ASSETS, baeume)
	_multimesh_box(gruppe, "Fruechte", Vector3.ONE, fruechte, Color(0.86, 0.3, 0.28))
	_baue_ernte_ecke(gruppe, rect)
	return gruppe


func _baue_ernte_ecke(gruppe: Node3D, rect: Rect2) -> void:
	var p := Vector2(rect.end.x - 16.0, rect.end.y - 14.0)
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var leiter := Node3D.new()
	leiter.name = "Leiter"
	leiter.position = Vector3(p.x, boden, p.y)
	leiter.rotation.z = 0.3
	gruppe.add_child(leiter)
	for seite: float in [-0.4, 0.4]:
		_quader(leiter, Vector3(seite, 1.6, 0.0), Vector3(0.1, 3.2, 0.1), HOLZ_ALT)
	for i in 5:
		_quader(
			leiter, Vector3(0.0, 0.5 + float(i) * 0.55, 0.0), Vector3(0.85, 0.08, 0.08), HOLZ_ALT
		)
	for i in 3:
		var kp := p + Vector2(1.8 + float(i) * 1.3, 1.2 - float(i) * 0.8)
		var korb_y := RanchGelaende.hoehe(kp.x, kp.y)
		_quader(gruppe, Vector3(kp.x, korb_y + 0.25, kp.y), Vector3(0.8, 0.5, 0.8), HOLZ_ALT)
		_quader(
			gruppe,
			Vector3(kp.x, korb_y + 0.55, kp.y),
			Vector3(0.7, 0.14, 0.7),
			Color(0.86, 0.3, 0.28)
		)
	_quader(
		gruppe,
		Vector3(p.x - 4.0, RanchGelaende.hoehe(p.x - 4.0, p.y + 3.0) + 0.04, p.y + 3.0),
		Vector3(2.6, 0.06, 2.6),
		Color(0.95, 0.72, 0.7)
	)


## ------------------------------------------------------------ Kornfeld


func _baue_kornfeld(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "kornfeld")
	var zone := RanchKarte.zone("kornfeld")
	var feld: Array = zone["feld_rect"]
	var rect := Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3]))
	var kreis := RanchEntdeckungen.position_von(RanchEntdeckungen.fundort("kornkreis"))
	var rng := _rng(91)
	var halme: Array = []
	var spalten := int(rect.size.x / 2.0)
	var reihen := int(rect.size.y / 2.0)
	for sx in spalten:
		if sx % 12 >= 10:
			continue
		for sz in reihen:
			if sz % 17 >= 16:
				continue
			var p := Vector2(
				rect.position.x + 1.0 + float(sx) * 2.0 + rng.randf_range(-0.45, 0.45),
				rect.position.y + 1.0 + float(sz) * 2.0 + rng.randf_range(-0.45, 0.45)
			)
			if p.distance_to(kreis) < 16.0:
				continue
			halme.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(0.95, 1.3)))
	_multimesh_flora(gruppe, "korn", halme)
	_baue_kornkreis(gruppe, kreis)
	_baue_vogelscheuche(gruppe, Vector2(rect.get_center().x, rect.position.y - 8.0))
	var kuerbisse: Array = []
	for _i in 14:
		var p := Vector2(
			rng.randf_range(rect.position.x, rect.end.x), rect.end.y + rng.randf_range(3.0, 10.0)
		)
		kuerbisse.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(1.6, 2.6)))
	_bau.baue_multimesh(gruppe, "%s/natur/crop_pumpkin.glb" % ASSETS, kuerbisse, "", KLEIN_SICHT_M)
	return gruppe


## Kornkreis-Fundort: plattgedrückter Ring aus flachen Gold-Scheiben.
func _baue_kornkreis(gruppe: Node3D, kreis: Vector2) -> void:
	var ringe: Array = []
	for i in 14:
		var w := float(i) / 14.0 * TAU
		var p := kreis + Vector2.from_angle(w) * 9.0
		var basis := Basis(Vector3.UP, w).scaled(Vector3(2.4, 0.08, 1.2))
		ringe.append(Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y) + 0.1, p.y)))
	_multimesh_box(gruppe, "KornkreisRing", Vector3.ONE, ringe, WeltFlora.KORN_GOLD)


func _baue_vogelscheuche(gruppe: Node3D, p: Vector2) -> void:
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var scheuche := Node3D.new()
	scheuche.name = "Vogelscheuche"
	scheuche.position = Vector3(p.x, boden, p.y)
	gruppe.add_child(scheuche)
	_quader(scheuche, Vector3(0.0, 1.5, 0.0), Vector3(0.18, 3.0, 0.18), HOLZ_ALT)
	_quader(scheuche, Vector3(0.0, 2.2, 0.0), Vector3(2.2, 0.16, 0.16), HOLZ_ALT)
	_quader(scheuche, Vector3(0.0, 1.7, 0.0), Vector3(0.9, 1.2, 0.5), Color(0.55, 0.62, 0.8))
	_quader(scheuche, Vector3(0.0, 2.65, 0.0), Vector3(0.5, 0.5, 0.5), STROH_GELB)
	var hut := MeshInstance3D.new()
	var kegel := CylinderMesh.new()
	kegel.top_radius = 0.05
	kegel.bottom_radius = 0.55
	kegel.height = 0.45
	kegel.radial_segments = 8
	kegel.material = RanchPferd.material(STROH_GELB.darkened(0.2))
	hut.mesh = kegel
	hut.position = Vector3(0.0, 3.05, 0.0)
	scheuche.add_child(hut)


## ------------------------------------------------------------- Werkzeug


func _gruppe(wurzel: Node3D, zone_id: String) -> Node3D:
	var gruppe := Node3D.new()
	gruppe.name = "Deko_%s" % zone_id
	wurzel.add_child(gruppe)
	return gruppe


func _rng(salz: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_wert + salz
	return rng


func _zufall_in(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y)
	)


func _boden_transform(p: Vector2, drehung: float, skala: float, einsenken := 0.0) -> Transform3D:
	var basis := Basis(Vector3.UP, drehung).scaled(Vector3.ONE * skala)
	return Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y) + einsenken, p.y))


## MultiMesh aus WeltFlora-Sorte (Kleinteil-Sichtweite inklusive).
func _multimesh_flora(wurzel: Node3D, sorte: String, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var mesh := WeltFlora.mesh(sorte)
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_Flora_%s" % sorte
	mmi.multimesh = mm
	mmi.visibility_range_end = KLEIN_SICHT_M * 1.6
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## MultiMesh aus Einheits-Boxen (Basis-Skala steckt in den Transforms).
func _multimesh_box(
	wurzel: Node3D, mm_name: String, box: Vector3, transforms: Array, farbe: Color
) -> void:
	if transforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = box
	mesh.material = RanchPferd.material(farbe)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	wurzel.add_child(mmi)


func _quader(wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = RanchPferd.material(farbe)
	mi.mesh = mesh
	mi.position = pos
	wurzel.add_child(mi)
	return mi
