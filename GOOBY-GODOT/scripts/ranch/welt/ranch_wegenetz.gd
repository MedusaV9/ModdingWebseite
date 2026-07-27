class_name RanchWegenetz
extends RefCounted
## Wegenetz-Ausstattung der offenen Welt (WELT-1): WEGWEISER mit
## Entfernungsangaben an jedem Zonen-Anschluss (man sieht IMMER, wohin es
## weitergeht), RASTPLÄTZE mit Bank + Feuerstelle an langen Strecken,
## WEIDEGATTER (fence_gate) an Zonen-Einfahrten und die FURT-Markierung
## am Bach. Die PLANUNG ist PURE + headless-testbar (wegweiser_plan,
## distanz_m); der Bau-Schritt setzt sie in wenige Meshes um — Label3D
## und Kleinteile mit Sichtweiten-Culling (Budget).

const SICHT_M := 170.0

## Rastplätze: [x, z] an langen Wegstrecken (Serpentinen-Fuß, Strandweg,
## Feldrand) — Bank, Feuerstelle, Sitzstämme.
const RASTPLAETZE: Array[Array] = [
	[130.0, -640.0],
	[688.0, 236.0],
	[-160.0, 806.0],
]

## Weidegatter: {weg-id, t entlang des Wegs} — Tor steht AUF dem Weg.
const GATTER: Array[Dictionary] = [
	{"von": "hof", "nach": "weidetal", "t": 0.45},
	{"von": "turnierplatz", "nach": "obstgarten", "t": 0.5},
	{"von": "scheune_alt", "nach": "kornfeld", "t": 0.55},
]

const HOLZ := Color(0.62, 0.55, 0.47)
const SCHILD_CREME := Color("#F4E9CD")
const INK := Color(0.32, 0.25, 0.2)
const FEUER_ORANGE := Color(1.0, 0.62, 0.25, 0.9)

## ------------------------------------------------------------- Planung


## Weglänge in Metern zwischen zwei Zonen (Polyline; 0.0 = kein Weg).
static func distanz_m(von_zone: String, nach_zone: String) -> float:
	var punkte := RanchKarte.wegpunkte(von_zone, nach_zone)
	var laenge := 0.0
	for i in punkte.size() - 1:
		laenge += Vector2(punkte[i].x, punkte[i].z).distance_to(
			Vector2(punkte[i + 1].x, punkte[i + 1].z)
		)
	return laenge


## Wegweiser-Plan: je Zone ein Pfosten am Weg-Anschluss mit einem Arm pro
## Nachbar-Zone (name_key + gerundete Distanz). PURE für Tests.
static func wegweiser_plan() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zone: Dictionary in RanchKarte.zonen():
		var zone_id := str(zone["id"])
		var nachbarn := RanchKarte.nachbarn(zone_id)
		if nachbarn.is_empty():
			continue
		var spawn: Array = zone["spawn"]
		var arme: Array[Dictionary] = []
		for nachbar: String in nachbarn:
			var ziel := RanchKarte.zone(nachbar)
			(
				arme
				. append(
					{
						"zone": nachbar,
						"name_key": str(ziel["name_key"]),
						"distanz_m": distanz_m(zone_id, nachbar),
					}
				)
			)
		(
			out
			. append(
				{
					"zone": zone_id,
					"pos": Vector2(float(spawn[0]) + 4.0, float(spawn[1]) - 4.0),
					"arme": arme,
				}
			)
		)
	return out


## ----------------------------------------------------------------- Bau


## Baut Wegweiser, Rastplätze, Gatter und Furt-Stangen unter `wurzel`.
static func baue(wurzel: Node3D) -> Node3D:
	var gruppe := Node3D.new()
	gruppe.name = "Wegenetz"
	wurzel.add_child(gruppe)
	for plan: Dictionary in wegweiser_plan():
		_baue_wegweiser(gruppe, plan)
	for platz: Array in RASTPLAETZE:
		_baue_rastplatz(gruppe, Vector2(float(platz[0]), float(platz[1])))
	var bau := RanchBau.new(gruppe)
	for gatter: Dictionary in GATTER:
		_baue_gatter(gruppe, bau, gatter)
	_baue_furt_stangen(gruppe)
	return gruppe


## Wegweiser: Pfosten + je Nachbar ein Brett-Arm mit "Name  123 m".
static func _baue_wegweiser(gruppe: Node3D, plan: Dictionary) -> void:
	var p: Vector2 = plan["pos"]
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var pfahl := Node3D.new()
	pfahl.name = "Wegweiser_%s" % str(plan["zone"])
	pfahl.position = Vector3(p.x, boden, p.y)
	gruppe.add_child(pfahl)
	_quader(pfahl, Vector3(0.0, 1.5, 0.0), Vector3(0.2, 3.0, 0.2), HOLZ)
	var arme: Array = plan["arme"]
	for i in arme.size():
		var arm: Dictionary = arme[i]
		var ziel := RanchKarte.zone(str(arm["zone"]))
		var spawn: Array = ziel["spawn"]
		var winkel := atan2(float(spawn[0]) - p.x, float(spawn[1]) - p.y)
		var arm_wurzel := Node3D.new()
		arm_wurzel.position = Vector3(0.0, 2.7 - float(i) * 0.42, 0.0)
		arm_wurzel.rotation.y = winkel
		pfahl.add_child(arm_wurzel)
		_quader(arm_wurzel, Vector3(0.0, 0.0, 0.85), Vector3(0.14, 0.34, 1.7), SCHILD_CREME)
		var text := Label3D.new()
		text.text = (
			"%s  %d m" % [I18nService.t(str(arm["name_key"])), int(float(arm["distanz_m"]))]
		)
		text.font_size = 52
		text.pixel_size = 0.006
		text.modulate = INK
		text.position = Vector3(0.09, 0.0, 0.85)
		text.rotation.y = -PI / 2.0
		text.visibility_range_end = SICHT_M
		arm_wurzel.add_child(text)


## Rastplatz: Bank, Steinring-Feuerstelle mit Flammen-Quad, Sitzstamm.
static func _baue_rastplatz(gruppe: Node3D, p: Vector2) -> void:
	var boden := RanchGelaende.hoehe(p.x, p.y)
	var platz := Node3D.new()
	platz.name = "Rastplatz"
	platz.position = Vector3(p.x, boden, p.y)
	platz.rotation.y = p.x * 0.1
	gruppe.add_child(platz)
	_quader(platz, Vector3(0.0, 0.5, -2.6), Vector3(2.4, 0.14, 0.7), HOLZ)
	_quader(platz, Vector3(-0.9, 0.25, -2.6), Vector3(0.16, 0.5, 0.6), HOLZ)
	_quader(platz, Vector3(0.9, 0.25, -2.6), Vector3(0.16, 0.5, 0.6), HOLZ)
	_quader(platz, Vector3(0.0, 0.85, -2.92), Vector3(2.4, 0.6, 0.1), HOLZ)
	for i in 7:
		var w := float(i) / 7.0 * TAU
		var sp := Vector2.from_angle(w) * 1.1
		var stein := _quader(
			platz, Vector3(sp.x, 0.18, sp.y), Vector3(0.4, 0.36, 0.4), Color(0.6, 0.58, 0.56)
		)
		stein.rotation.y = w
	_quader(platz, Vector3(0.2, 0.16, 0.0), Vector3(0.9, 0.16, 0.18), Color(0.4, 0.3, 0.22))
	_quader(platz, Vector3(-0.15, 0.16, 0.1), Vector3(0.8, 0.15, 0.17), Color(0.35, 0.26, 0.2))
	var flamme := MeshInstance3D.new()
	flamme.name = "Feuer"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = FEUER_ORANGE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	flamme.mesh = quad
	flamme.position = Vector3(0.0, 0.75, 0.0)
	flamme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flamme.visibility_range_end = SICHT_M
	platz.add_child(flamme)
	_quader(platz, Vector3(2.4, 0.3, 0.4), Vector3(0.55, 0.55, 2.2), Color(0.5, 0.4, 0.3))


## Weidegatter: Kit-Tor quer über den Weg, an Punkt t der Polyline.
static func _baue_gatter(gruppe: Node3D, bau: RanchBau, gatter: Dictionary) -> void:
	var punkte := RanchKarte.wegpunkte(str(gatter["von"]), str(gatter["nach"]))
	if punkte.size() < 2:
		return
	var t := clampf(float(gatter["t"]), 0.0, 1.0) * float(punkte.size() - 1)
	var i := mini(int(t), punkte.size() - 2)
	var p := punkte[i].lerp(punkte[i + 1], t - float(i))
	var richtung := punkte[i + 1] - punkte[i]
	var tor := bau.lade_glb("%s/natur/fence_gate.glb" % "res://assets/ranch", 3.4)
	if tor == null:
		return
	tor.name = "Gatter_%s_%s" % [str(gatter["von"]), str(gatter["nach"])]
	tor.position = Vector3(p.x, RanchGelaende.hoehe(p.x, p.z), p.z)
	tor.rotation.y = atan2(richtung.x, richtung.z) + PI / 2.0
	gruppe.add_child(tor)


## Furt: zwei Stangen-Paare markieren die sichere Bach-Querung.
static func _baue_furt_stangen(gruppe: Node3D) -> void:
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var furt: Array = bach["furt"]
	var fx := float(furt[0])
	var fz := float(furt[1])
	for ecke: Vector2 in [
		Vector2(-5.0, -3.0), Vector2(5.0, -3.0), Vector2(-5.0, 3.0), Vector2(5.0, 3.0)
	]:
		var p := Vector2(fx, fz) + ecke
		var boden := RanchGelaende.hoehe(p.x, p.y)
		var stange := _quader(
			gruppe, Vector3(p.x, boden + 0.8, p.y), Vector3(0.14, 1.6, 0.14), HOLZ
		)
		_quader(
			gruppe, Vector3(p.x, boden + 1.55, p.y), Vector3(0.3, 0.3, 0.3), Color(0.86, 0.42, 0.36)
		)
		stange.visibility_range_end = SICHT_M * 2.0


static func _quader(wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = RanchPferd.material(farbe)
	mi.mesh = mesh
	mi.position = pos
	wurzel.add_child(mi)
	return mi
