class_name RanchZonenDeko
extends RefCounted
## Zonen-Ausstattung der Ranch-Region (RW-1): baut je Zone eine eigene
## Deko-Gruppe (Node3D) — der Hof über den bestehenden RanchBau (Bestand
## bleibt Bestand), die neuen Zonen mit Kit-Assets (Kenney Nature Kit)
## und Pastell-Primitiven. Die Szene schaltet die Gruppen über
## Sichtbarkeits-Abstände (Streaming ohne Ladebildschirm).

const ASSETS := "res://assets/ranch"
const GRAS_SHADER := "res://scripts/ranch/welt/gras_wind.gdshader"

const HOLZ_ALT := Color(0.62, 0.55, 0.47)
const ROT_ALT := Color(0.66, 0.42, 0.38)
const SAND := Color(0.89, 0.8, 0.62)
const HAUS_FARBEN: Array[Color] = [
	Color("#F2E3C9"), Color("#DCE9D5"), Color("#F4D8D8"), Color("#D8E4F0")
]

var windrad_rotor: Node3D
var gras_material: ShaderMaterial

var _seed_wert := 0
var _bau: RanchBau
var _mesh_cache: Dictionary = {}


func _init(seed_wert: int) -> void:
	_seed_wert = seed_wert


## Baut alle Zonen-Gruppen unter `wurzel`; Rückgabe zone_id → Gruppe
## (die Szene nutzt das fürs Abstands-Streaming).
func baue(wurzel: Node3D) -> Dictionary:
	_bau = RanchBau.new(wurzel)
	var gruppen := {}
	gruppen["hof"] = _baue_hof(wurzel)
	gruppen["waeldchen"] = _baue_waeldchen(wurzel)
	gruppen["see"] = _baue_see(wurzel)
	gruppen["huegelkamm"] = _baue_huegelkamm(wurzel)
	gruppen["bachlauf"] = _baue_bachlauf(wurzel)
	gruppen["scheune_alt"] = _baue_scheune_alt(wurzel)
	gruppen["turnierplatz"] = _baue_turnierplatz(wurzel)
	gruppen["hufingen"] = _baue_hufingen(wurzel)
	gruppen["weidetal"] = _baue_weidetal(wurzel)
	_baue_baeume(wurzel)
	_baue_gras(wurzel)
	return gruppen


## -------------------------------------------------------------- Hof


## Der bestehende Ranch-Hof (RanchWelt.hof_plan) auf seinem Plateau
## (hoehe_basis) — Gebäude, Koppeln, Reitplatz, Windrad, Teich, Trog, Tor.
func _baue_hof(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "hof")
	gruppe.position.y = float(RanchKarte.zone("hof")["hoehe_basis"]) + 0.02
	var plan := RanchWelt.hof_plan()
	var bau := RanchBau.new(gruppe)
	for weg: Dictionary in plan["wege"]:
		bau.baue_weg(weg["von"], weg["bis"], float(weg["breite"]))
	bau.baue_tor(plan["tor_pos"], I18nService.t("ranch.fahrt.schild_ranch"))
	bau.baue_reitplatz(plan["reitplatz"])
	bau.baue_teich(plan["teich_pos"])
	bau.baue_trog(plan["trog_pos"])
	windrad_rotor = bau.baue_windrad(plan["windrad_pos"])
	for geb: Dictionary in plan["gebaeude"]:
		var pos: Vector3 = geb["pos"]
		var rot := float(geb["rot_grad"])
		match str(geb["id"]):
			"scheune":
				bau.baue_scheune(pos, rot)
			"stall":
				bau.baue_stall(pos, rot)
			"haus":
				bau.baue_haus(pos, rot)
			"heulager":
				bau.baue_heulager(pos, rot)
	var latten: Array = []
	for koppel: Dictionary in plan["koppeln"]:
		for eintrag: Dictionary in RanchWelt.zaun_ring(
			koppel["rect"], 2.6, str(koppel["tor_seite"])
		):
			var basis := Basis(Vector3.UP, float(eintrag["rot"])).scaled(Vector3.ONE * 2.6)
			latten.append(Transform3D(basis, eintrag["pos"]))
	bau.baue_multimesh(gruppe, "%s/natur/fence_simple.glb" % ASSETS, latten)
	_baue_hoftiere(gruppe, plan)
	return gruppe


func _baue_hoftiere(gruppe: Node3D, plan: Dictionary) -> void:
	for pos: Vector3 in plan["kuehe"]:
		var kuh := RanchTier.neu("kuh", Color("#F5EFE4"), Color("#7A5C43"))
		kuh.position = pos
		kuh.rotation.y = pos.x * 0.3
		gruppe.add_child(kuh)
	for pos: Vector3 in plan["schafe"]:
		var schaf := RanchTier.neu("schaf", Color("#F7F3EA"))
		schaf.position = pos
		schaf.rotation.y = pos.z * 0.4
		gruppe.add_child(schaf)
	for pos: Vector3 in plan["huehner"]:
		var huhn := RanchTier.neu("huhn", Color("#F2C14E"))
		huhn.position = pos
		huhn.rotation.y = pos.x
		gruppe.add_child(huhn)


## -------------------------------------------------------- neue Zonen


func _baue_waeldchen(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "waeldchen")
	var zone := RanchKarte.zone("waeldchen")
	var lichtung: Array = zone["lichtung"]
	var mitte := Vector2(float(lichtung[0]), float(lichtung[1]))
	var rng := _rng(2)
	var stuempfe: Array = []
	var pilz_ringe: Array = []
	for _i in 7:
		var p := mitte + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 20.0)
		var t := _boden_transform(p, rng.randf() * TAU, rng.randf_range(2.2, 3.4))
		if rng.randf() < 0.5:
			stuempfe.append(t)
		else:
			pilz_ringe.append(t)
	_multimesh(gruppe, "natur/stump_round.glb", stuempfe)
	_multimesh(gruppe, "natur/log.glb", pilz_ringe)
	var bueschel: Array = []
	for _i in 26:
		var rect := RanchKarte.zone_rect(zone)
		var p := _zufall_in(rect, rng)
		if _frei(p) and p.distance_to(mitte) > 24.0:
			bueschel.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.6, 4.2)))
	_multimesh(gruppe, "natur/plant_bushLarge.glb", bueschel)
	return gruppe


func _baue_see(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "see")
	var zone := RanchKarte.zone("see")
	var steg: Array = zone["steg"]
	var mitte: Array = zone["see_mitte"]
	var start := Vector2(float(steg[0]), float(steg[1]))
	var richtung := (Vector2(float(mitte[0]), float(mitte[1])) - start).normalized()
	var deck_y := RanchGelaende.WASSER_HOEHE + 1.0
	var laenge := 16.0
	var deck := _quader(
		gruppe,
		Vector3(start.x, deck_y, start.y) + Vector3(richtung.x, 0.0, richtung.y) * laenge / 2.0,
		Vector3(2.6, 0.24, laenge),
		RanchBau.HOLZ_HELL
	)
	deck.rotation.y = atan2(richtung.x, richtung.y)
	for i in 4:
		var t := (float(i) + 0.5) / 4.0
		var fuss := start + richtung * laenge * t
		for seite: float in [-1.0, 1.0]:
			var quer := Vector2(-richtung.y, richtung.x) * seite * 1.1
			_quader(
				gruppe,
				Vector3(fuss.x + quer.x, deck_y - 1.1, fuss.y + quer.y),
				Vector3(0.28, 2.4, 0.28),
				RanchBau.HOLZ_DUNKEL
			)
	var schild := _bau.baue_schild(
		Vector3(start.x - richtung.x * 6.0, 0.0, start.y - richtung.y * 6.0),
		I18nService.t("rwelt.hud.steg_schild"),
		""
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	var rng := _rng(3)
	var schilf: Array = []
	for _i in 40:
		var winkel := rng.randf() * TAU
		var radius := float(zone["see_radius"]) * rng.randf_range(1.02, 1.25)
		var p := Vector2(float(mitte[0]), float(mitte[1])) + Vector2.from_angle(winkel) * radius
		if not RanchGelaende.ist_wasser(p.x, p.y):
			schilf.append(_boden_transform(p, winkel, rng.randf_range(3.2, 4.6)))
	_multimesh(gruppe, "natur/grass_large.glb", schilf)
	return gruppe


func _baue_huegelkamm(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "huegelkamm")
	var zone := RanchKarte.zone("huegelkamm")
	var punkt: Array = zone["aussichtspunkt"]
	var mitte := Vector2(float(punkt[0]), float(punkt[1]))
	var gipfel_y := RanchGelaende.hoehe(mitte.x, mitte.y)
	var zaun: Array = []
	for i in 9:
		var winkel := PI * 0.75 + float(i) / 8.0 * PI * 0.5
		var p := mitte + Vector2.from_angle(winkel) * 7.5
		var basis := Basis(Vector3.UP, -winkel).scaled(Vector3.ONE * 2.6)
		zaun.append(Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y), p.y)))
	_multimesh(gruppe, "natur/fence_simple.glb", zaun)
	var mast := _quader(
		gruppe, Vector3(mitte.x, gipfel_y + 2.6, mitte.y), Vector3(0.24, 5.2, 0.24), HOLZ_ALT
	)
	var fahne := _quader(
		gruppe,
		Vector3(mitte.x + 0.9, gipfel_y + 4.6, mitte.y),
		Vector3(1.7, 1.0, 0.06),
		Color("#D96C57")
	)
	fahne.rotation.z = -0.06
	mast.rotation.z = 0.0
	var schild := _bau.baue_schild(
		Vector3(mitte.x + 4.0, 0.0, mitte.y + 4.0), I18nService.t("rwelt.hud.aussicht"), ""
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	var rng := _rng(4)
	var felsen: Array = []
	for _i in 12:
		var p := _zufall_in(RanchKarte.zone_rect(zone), rng)
		if _frei(p):
			felsen.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.0, 5.0)))
	_multimesh(gruppe, "natur/rock_largeA.glb", felsen)
	return gruppe


func _baue_bachlauf(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "bachlauf")
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var bruecke: Array = bach["bruecke"]
	var glb := _bau.lade_glb("%s/natur/bridge_wood.glb" % ASSETS, 4.6)
	if glb != null:
		var bx := float(bruecke[0])
		var bz := float(bruecke[1])
		glb.position = Vector3(bx, RanchGelaende.hoehe(bx, bz) + 0.15, bz)
		glb.rotation.y = PI / 2.0
		gruppe.add_child(glb)
	var rng := _rng(5)
	var steine: Array = []
	for paar: Array in bach["punkte"]:
		for _i in 3:
			var p := Vector2(float(paar[0]), float(paar[1]))
			p += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.5, 9.0)
			if not RanchGelaende.ist_wasser(p.x, p.y):
				steine.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(0.9, 2.2)))
	_multimesh(gruppe, "natur/rock_smallA.glb", steine)
	return gruppe


## Alte verfallene Scheune: schiefe Wände, eingebrochenes Dach, warmes
## Geheimnis-Licht im Inneren, zugewachsen mit Büschen.
func _baue_scheune_alt(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "scheune_alt")
	var zone := RanchKarte.zone("scheune_alt")
	var pos: Array = zone["scheune"]
	var mitte := Vector3(
		float(pos[0]), RanchGelaende.hoehe(float(pos[0]), float(pos[1])), float(pos[1])
	)
	var rumpf := _quader(gruppe, mitte + Vector3(0.0, 3.0, 0.0), Vector3(16.0, 6.0, 11.0), ROT_ALT)
	rumpf.rotation.z = 0.045
	var dach := MeshInstance3D.new()
	var dach_mesh := PrismMesh.new()
	dach_mesh.size = Vector3(17.5, 2.6, 12.5)
	dach_mesh.material = RanchPferd.material(HOLZ_ALT)
	dach.mesh = dach_mesh
	dach.position = mitte + Vector3(0.8, 6.6, 0.0)
	dach.rotation.z = 0.16
	gruppe.add_child(dach)
	var rng := _rng(6)
	for i in 5:
		var brett := _quader(
			gruppe,
			mitte + Vector3(rng.randf_range(-8.0, 8.0), 0.5, rng.randf_range(5.0, 8.0)),
			Vector3(0.4, 3.0, 0.16),
			HOLZ_ALT
		)
		brett.rotation.z = rng.randf_range(-0.7, 0.7)
		brett.rotation.y = float(i)
	var licht := OmniLight3D.new()
	licht.name = "GeheimnisLicht"
	licht.position = mitte + Vector3(0.0, 2.4, 0.0)
	licht.light_color = Color(1.0, 0.82, 0.45)
	licht.light_energy = 1.6
	licht.omni_range = 12.0
	gruppe.add_child(licht)
	var schild := _bau.baue_schild(
		mitte + Vector3(10.0, 0.0, 6.0), I18nService.t("rwelt.hud.scheune_schild"), ""
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	var busch: Array = []
	for _i in 10:
		var p := (
			Vector2(mitte.x, mitte.z)
			+ Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.0, 16.0)
		)
		busch.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.4, 4.0)))
	_multimesh(gruppe, "natur/plant_bushLarge.glb", busch)
	return gruppe


## Turnierplatz: Sand-Arena + Zaunring + Wimpel (RW-5 baut den Wettbewerb).
func _baue_turnierplatz(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "turnierplatz")
	var zone := RanchKarte.zone("turnierplatz")
	var arena: Array = zone["arena"]
	var rect := Rect2(float(arena[0]), float(arena[1]), float(arena[2]), float(arena[3]))
	var basis_y := float(zone["hoehe_basis"])
	var sand := MeshInstance3D.new()
	var sand_mesh := PlaneMesh.new()
	sand_mesh.size = rect.size
	sand_mesh.material = RanchPferd.material(SAND)
	sand.mesh = sand_mesh
	sand.position = Vector3(rect.get_center().x, basis_y + 0.06, rect.get_center().y)
	gruppe.add_child(sand)
	var latten: Array = []
	for eintrag: Dictionary in RanchWelt.zaun_ring(rect, 2.6, "west"):
		var basis := Basis(Vector3.UP, float(eintrag["rot"])).scaled(Vector3.ONE * 2.6)
		var pos: Vector3 = eintrag["pos"]
		pos.y = basis_y
		latten.append(Transform3D(basis, pos))
	_multimesh(gruppe, "natur/fence_simple.glb", latten)
	for ecke: Vector2 in [
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.end.x, rect.end.y),
	]:
		_quader(gruppe, Vector3(ecke.x, basis_y + 2.2, ecke.y), Vector3(0.3, 4.4, 0.3), HOLZ_ALT)
		var wimpel := _quader(
			gruppe,
			Vector3(ecke.x + 0.7, basis_y + 4.1, ecke.y),
			Vector3(1.3, 0.8, 0.05),
			Color("#5FA8A0")
		)
		wimpel.rotation.z = -0.1
	var schild := _bau.baue_schild(
		Vector3(rect.position.x - 8.0, 0.0, rect.get_center().y),
		I18nService.t("rwelt.hud.turnier_schild"),
		""
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	return gruppe


## Dorfrand „Hufingen“: Straße + Pastell-Häuserzeile (RW-4 baut die Läden).
func _baue_hufingen(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "hufingen")
	var zone := RanchKarte.zone("hufingen")
	var basis_y := float(zone["hoehe_basis"])
	var spawn: Array = zone["spawn"]
	var ende: Array = zone["strasse_ende"]
	var von := Vector3(float(spawn[0]), basis_y + 0.08, float(spawn[1]))
	var bis := Vector3(float(ende[0]), basis_y + 0.08, float(ende[1]))
	var strasse := _quader(
		gruppe, (von + bis) / 2.0, Vector3(8.0, 0.1, von.distance_to(bis) + 8.0), RanchBau.WEG_GRAU
	)
	strasse.rotation.y = atan2(bis.x - von.x, bis.z - von.z)
	var richtung := Vector2(bis.x - von.x, bis.z - von.z).normalized()
	var quer := Vector2(-richtung.y, richtung.x)
	for i in 4:
		var t := (float(i) + 0.6) / 4.6
		var fuss := Vector2(von.x, von.z).lerp(Vector2(bis.x, bis.z), t)
		var seite := 1.0 if i % 2 == 0 else -1.0
		var haus_pos := fuss + quer * seite * 13.0
		_baue_haus(
			gruppe,
			Vector3(haus_pos.x, basis_y, haus_pos.y),
			HAUS_FARBEN[i % HAUS_FARBEN.size()],
			atan2(-quer.x * seite, -quer.y * seite)
		)
	var schild := _bau.baue_schild(
		von - Vector3(richtung.x, 0.0, richtung.y) * 10.0,
		I18nService.t("rwelt.hud.hufingen_schild"),
		""
	)
	schild.position.y = RanchGelaende.hoehe(schild.position.x, schild.position.z)
	return gruppe


func _baue_haus(gruppe: Node3D, pos: Vector3, farbe: Color, drehung: float) -> void:
	var haus := Node3D.new()
	haus.position = pos
	haus.rotation.y = drehung
	gruppe.add_child(haus)
	_quader(haus, Vector3(0.0, 2.4, 0.0), Vector3(10.0, 4.8, 8.0), farbe)
	var dach := MeshInstance3D.new()
	var dach_mesh := PrismMesh.new()
	dach_mesh.size = Vector3(11.2, 2.2, 9.2)
	dach_mesh.material = RanchPferd.material(RanchBau.DACH_TEAL)
	dach.mesh = dach_mesh
	dach.position = Vector3(0.0, 5.9, 0.0)
	haus.add_child(dach)
	_quader(haus, Vector3(0.0, 1.4, 4.06), Vector3(1.5, 2.8, 0.12), RanchBau.HOLZ_DUNKEL)
	for seite: float in [-1.0, 1.0]:
		_quader(
			haus, Vector3(seite * 3.0, 2.6, 4.06), Vector3(1.7, 1.5, 0.12), Color(0.72, 0.86, 0.92)
		)


func _baue_weidetal(wurzel: Node3D) -> Node3D:
	var gruppe := _gruppe(wurzel, "weidetal")
	var zone := RanchKarte.zone("weidetal")
	var weide: Array = zone["wildpferde_weide"]
	var mitte := Vector2(float(weide[0]), float(weide[1]))
	var zaun: Array = []
	for i in 26:
		var winkel := float(i) / 26.0 * TAU
		var p := mitte + Vector2.from_angle(winkel) * 46.0
		var basis := Basis(Vector3.UP, -winkel + PI / 2.0).scaled(Vector3.ONE * 2.6)
		zaun.append(Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y), p.y)))
	_multimesh(gruppe, "natur/fence_simple.glb", zaun)
	var rng := _rng(7)
	var blumen: Array = []
	for _i in 60:
		var p := _zufall_in(RanchKarte.zone_rect(zone), rng)
		if _frei(p):
			blumen.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.6, 3.6)))
	_multimesh(gruppe, "natur/flower_purpleA.glb", blumen, RanchBau.KLEINTEIL_SICHT_M)
	return gruppe


## ------------------------------------------------- Bäume + Gras (global)


## Baumgruppen der ganzen Region: dichter Wald im Wäldchen, lockere
## Streuung überall sonst (drei Sorten = drei MultiMeshes).
func _baue_baeume(wurzel: Node3D) -> void:
	var rng := _rng(8)
	var wald_rect := RanchKarte.zone_rect(RanchKarte.zone("waeldchen"))
	var lichtung: Array = RanchKarte.zone("waeldchen")["lichtung"]
	var l_mitte := Vector2(float(lichtung[0]), float(lichtung[1]))
	var sorten := {
		"natur/tree_detailed.glb": [],
		"natur/tree_default.glb": [],
		"natur/tree_fat.glb": [],
	}
	var namen: Array = sorten.keys()
	for _i in 240:
		var p := _zufall_in(wald_rect, rng)
		if not _frei(p) or p.distance_to(l_mitte) < 26.0:
			continue
		var sorte := str(namen[rng.randi_range(0, namen.size() - 1)])
		(sorten[sorte] as Array).append(
			_boden_transform(p, rng.randf() * TAU, rng.randf_range(7.0, 11.0), -0.25)
		)
	var grenzen := RanchKarte.grenzen()
	for _i in 190:
		var p := _zufall_in(grenzen, rng)
		if not _frei(p) or wald_rect.has_point(p):
			continue
		var sorte := str(namen[rng.randi_range(0, namen.size() - 1)])
		(sorten[sorte] as Array).append(
			_boden_transform(p, rng.randf() * TAU, rng.randf_range(8.0, 12.0), -0.25)
		)
	for sorte: String in sorten:
		_multimesh(wurzel, sorte, sorten[sorte])


## Gras als EIN MultiMesh mit Wind-Shader (wogt per Uniform `wind`).
func _baue_gras(wurzel: Node3D) -> void:
	var rng := _rng(9)
	var grenzen := RanchKarte.grenzen()
	var transforms: Array = []
	for _i in 5200:
		var p := _zufall_in(grenzen, rng)
		if not _frei(p):
			continue
		transforms.append(_boden_transform(p, rng.randf() * TAU, rng.randf_range(2.6, 4.2), -0.04))
	var teile := _glb_meshes("%s/natur/grass_large.glb" % ASSETS)
	if teile.is_empty() or transforms.is_empty():
		return
	var mesh: Mesh = teile[0]["mesh"]
	gras_material = ShaderMaterial.new()
	gras_material.shader = load(GRAS_SHADER)
	gras_material.set_shader_parameter("halm_hoehe", mesh.get_aabb().size.y)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, (transforms[i] as Transform3D) * teile[0]["xform"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_GrasWind"
	mmi.multimesh = mm
	mmi.material_override = gras_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)
	var blumen_gelb: Array = []
	var blumen_rot: Array = []
	for i in transforms.size():
		if i % 12 == 0:
			var t: Transform3D = transforms[i]
			var ziel := blumen_gelb if i % 24 == 0 else blumen_rot
			ziel.append(Transform3D(t.basis, t.origin + Vector3(1.1, 0.0, 0.7)))
	_multimesh(wurzel, "natur/flower_yellowA.glb", blumen_gelb, RanchBau.KLEINTEIL_SICHT_M)
	_multimesh(wurzel, "natur/flower_redA.glb", blumen_rot, RanchBau.KLEINTEIL_SICHT_M)


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


## Frei für Deko? Kein Wasser, kein Weg (8 m Abstand), keine Bau-Plateaus.
func _frei(p: Vector2) -> bool:
	if RanchGelaende.ist_wasser(p.x, p.y):
		return false
	for zone_id: String in ["hof", "turnierplatz", "hufingen"]:
		if RanchKarte.zone_rect(RanchKarte.zone(zone_id)).grow(6.0).has_point(p):
			return false
	var see := RanchKarte.zone("see")
	var mitte: Array = see["see_mitte"]
	if p.distance_to(Vector2(float(mitte[0]), float(mitte[1]))) < float(see["see_radius"]) + 14.0:
		return false
	for weg: Dictionary in RanchKarte.wege():
		var punkte: Array = weg["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			var d := _segment_abstand(
				p, Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1]))
			)
			if d < 8.0:
				return false
	return true


func _segment_abstand(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _boden_transform(p: Vector2, drehung: float, skala: float, einsenken := 0.0) -> Transform3D:
	var basis := Basis(Vector3.UP, drehung).scaled(Vector3.ONE * skala)
	return Transform3D(basis, Vector3(p.x, RanchGelaende.hoehe(p.x, p.y) + einsenken, p.y))


func _multimesh(wurzel: Node3D, asset: String, transforms: Array, sicht_ende := 0.0) -> void:
	_bau.baue_multimesh(wurzel, "%s/%s" % [ASSETS, asset], transforms, "", sicht_ende)


func _quader(wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = RanchPferd.material(farbe)
	mi.mesh = mesh
	mi.position = pos
	wurzel.add_child(mi)
	return mi


func _glb_meshes(pfad: String) -> Array[Dictionary]:
	if _mesh_cache.has(pfad):
		return _mesh_cache[pfad]
	var teile: Array[Dictionary] = []
	if ResourceLoader.exists(pfad):
		var szene: PackedScene = load(pfad)
		var proto: Node3D = szene.instantiate()
		for mesh in proto.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = mesh
			var rel := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != proto:
				if n is Node3D:
					rel = (n as Node3D).transform * rel
				n = n.get_parent()
			teile.append({"mesh": mi.mesh, "xform": rel})
		proto.free()
	_mesh_cache[pfad] = teile
	return teile
