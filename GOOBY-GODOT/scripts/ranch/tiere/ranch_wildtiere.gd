class_name RanchWildtiere
extends Node3D
## Wildtier-Manager der Ranch-Region (RW-1): setzt die pure RanchWildLogik
## in Szene um. Einzeltiere (Rehe, Füchse, Hasen, Enten, Wildpferde) sind
## billige GLB-/Primitiv-Knoten, deren Verhalten in einem 10-Hz-Sim-Tick
## läuft; Schwärme (Vögel, Schmetterlinge, Glühwürmchen) sind je EIN
## MultiMesh. „Leben reduziert“ (city.lebenReduziert) halbiert Herden und
## schaltet Schwärme ab (RanchWildLogik.budget).

const TIER_GLB := {
	"reh": "res://assets/ranch/tiere/reh_gooby.glb",
	"fuchs": "res://assets/ranch/tiere/fuchs_gooby.glb",
	"ente": "res://assets/ranch/tiere/ente_gooby.glb",
	"wildpferd": "res://assets/ranch/tiere/pferd_lowpoly.glb",
}

## Ziel-Körperhöhe je Art in m (GLBs werden über ihre AABB normiert).
const TIER_HOEHE := {"reh": 1.35, "fuchs": 0.62, "ente": 0.42, "wildpferd": 1.7}

## Sim-Tick der Verhaltenslogik (s).
const SIM_SCHRITT := 0.1

var tiere: Array[Dictionary] = []

var _seed_wert := 0
var _sim_rest := 0.0
var _rng := RandomNumberGenerator.new()
var _voegel: MultiMeshInstance3D
var _schmetterlinge: MultiMeshInstance3D
var _gluehwuermchen: MultiMeshInstance3D
var _schwarm_anker: Dictionary = {}
var _zeit := 0.0


## Baut alle Tiere anhand der Karte (Heimatpunkte je Zone) + Budget.
func einrichten(leben_reduziert: bool, seed_wert: int) -> void:
	_seed_wert = seed_wert
	_rng.seed = seed_wert + 31
	var budget := RanchWildLogik.budget(leben_reduziert)
	var waeldchen := RanchKarte.zone("waeldchen")
	var weidetal := RanchKarte.zone("weidetal")
	var see := RanchKarte.zone("see")
	var lichtung: Array = waeldchen["lichtung"]
	_gruppe("reh", int(budget["reh"]), Vector2(float(lichtung[0]), float(lichtung[1])))
	_gruppe("fuchs", int(budget["fuchs"]), Vector2(float(lichtung[0]) + 90.0, -480.0))
	var wt_spawn: Array = weidetal["spawn"]
	_gruppe("hase", int(budget["hase"]), Vector2(float(wt_spawn[0]) - 60.0, float(wt_spawn[1])))
	var steg: Array = see["steg"]
	# Nah am Stegkopf — vom Ufer aus gut sichtbar (statt weit draussen).
	_gruppe("ente", int(budget["ente"]), Vector2(float(steg[0]) + 12.0, float(steg[1]) + 14.0))
	var weide: Array = weidetal["wildpferde_weide"]
	_gruppe("wildpferd", int(budget["wildpferd"]), Vector2(float(weide[0]), float(weide[1])))
	_baue_schwaerme(budget)


## Ein Frame: 10-Hz-Verhaltens-Sim + weiche Knoten-Bewegung + Schwärme.
func tick(delta: float, stunde: float, wetter_typ: String, reiter_pos: Vector3) -> void:
	_zeit += delta
	var reiter := Vector2(reiter_pos.x, reiter_pos.z)
	_sim_rest += delta
	while _sim_rest >= SIM_SCHRITT:
		_sim_rest -= SIM_SCHRITT
		for eintrag: Dictionary in tiere:
			var art := str(eintrag["daten"]["art"])
			var an := RanchWildLogik.aktiv(art, stunde, wetter_typ)
			(eintrag["node"] as Node3D).visible = an
			if an:
				eintrag["daten"] = RanchWildLogik.schritt(
					eintrag["daten"], SIM_SCHRITT, reiter, _rng.randf()
				)
	for eintrag: Dictionary in tiere:
		_stelle_tier(eintrag, delta)
	_tick_schwaerme(stunde, wetter_typ)


## --------------------------------------------------------- Einzeltiere


func _gruppe(art: String, anzahl: int, heim: Vector2) -> void:
	for i in anzahl:
		var versatz := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(3.0, 14.0)
		var daten := RanchWildLogik.neues_tier(art, heim + versatz, float(i) / maxf(1.0, anzahl))
		var node := _baue_tier_node(art)
		node.position = _boden(heim + versatz)
		node.rotation.y = _rng.randf() * TAU
		add_child(node)
		tiere.append({"daten": daten, "node": node})


func _baue_tier_node(art: String) -> Node3D:
	if art == "hase":
		return _baue_hase()
	var pfad := str(TIER_GLB[art])
	if not ResourceLoader.exists(pfad):
		return _baue_hase()
	var szene: PackedScene = load(pfad)
	var wurzel := Node3D.new()
	wurzel.name = art.capitalize()
	var modell: Node3D = szene.instantiate()
	var hoehe := _aabb_hoehe(modell)
	if hoehe > 0.01:
		modell.scale = Vector3.ONE * (float(TIER_HOEHE[art]) / hoehe)
	wurzel.add_child(modell)
	return wurzel


## Gooby-Hase aus Primitiven (kein Kit-Asset): runder Körper, lange Ohren.
func _baue_hase() -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Hase"
	var fell := Color("#C9B29B")
	_kugel(wurzel, Vector3(0.0, 0.24, 0.0), Vector3(0.22, 0.2, 0.28), fell)
	_kugel(wurzel, Vector3(0.0, 0.42, -0.16), Vector3(0.15, 0.14, 0.15), fell)
	for seite: float in [-1.0, 1.0]:
		var ohr := _kugel(
			wurzel, Vector3(seite * 0.05, 0.6, -0.18), Vector3(0.035, 0.12, 0.05), fell
		)
		ohr.rotation.z = seite * -0.15
	_kugel(wurzel, Vector3(0.0, 0.26, 0.16), Vector3(0.07, 0.07, 0.07), Color(0.98, 0.96, 0.93))
	for seite: float in [-1.0, 1.0]:
		_kugel(
			wurzel,
			Vector3(seite * 0.06, 0.46, -0.28),
			Vector3(0.02, 0.028, 0.012),
			Color(0.13, 0.12, 0.14)
		)
	return wurzel


## Weiche Knoten-Bewegung zum Sim-Zustand + Blick in Laufrichtung + Hüpfen.
func _stelle_tier(eintrag: Dictionary, delta: float) -> void:
	var node: Node3D = eintrag["node"]
	if not node.visible:
		return
	var daten: Dictionary = eintrag["daten"]
	var ziel := _boden(daten["pos"] as Vector2)
	var art := str(daten["art"])
	if art == "ente" and RanchGelaende.ist_wasser(ziel.x, ziel.z):
		# Deutlich ueber der Wasserscheibe (Disc-Oberkante -1.075), sonst
		# taucht der Rumpf unter die Flaeche und die Ente ist unsichtbar.
		ziel.y = RanchGelaende.WASSER_HOEHE + 0.15
	var vorher := node.position
	node.position = vorher.lerp(ziel, minf(1.0, delta * 6.0))
	var richtung := Vector2(node.position.x - vorher.x, node.position.z - vorher.z)
	if richtung.length_squared() > 0.00002:
		var soll := atan2(-richtung.x, -richtung.y)
		node.rotation.y = lerp_angle(node.rotation.y, soll, minf(1.0, delta * 7.0))
	if RanchWildLogik.laeuft(daten):
		var hz := 9.0 if art == "hase" else 5.0
		node.position.y += absf(sin(_zeit * hz + float(daten["phase"]) * TAU)) * 0.12


## ------------------------------------------------------------ Schwärme


func _baue_schwaerme(budget: Dictionary) -> void:
	var see_mitte: Array = RanchKarte.zone("see")["see_mitte"]
	var lichtung: Array = RanchKarte.zone("waeldchen")["lichtung"]
	_schwarm_anker = {
		"vogel": Vector3(float(see_mitte[0]) - 150.0, 55.0, float(see_mitte[1]) - 120.0),
		"schmetterling": _boden(Vector2(-80.0, 60.0)),
		"gluehwuermchen": _boden(Vector2(float(lichtung[0]), float(lichtung[1]))),
	}
	_voegel = _schwarm_mm(
		int(budget["vogel"]), Vector3(0.5, 0.1, 0.24), Color(0.32, 0.3, 0.36), false
	)
	_voegel.name = "Voegel"
	_schmetterlinge = _schwarm_mm(
		int(budget["schmetterling"]), Vector3(0.16, 0.05, 0.14), Color(0.95, 0.78, 0.4), false
	)
	_schmetterlinge.name = "Schmetterlinge"
	_gluehwuermchen = _schwarm_mm(
		int(budget["gluehwuermchen"]), Vector3(0.08, 0.08, 0.08), Color(0.85, 1.0, 0.5), true
	)
	_gluehwuermchen.name = "Gluehwuermchen"


func _schwarm_mm(
	anzahl: int, groesse: Vector3, farbe: Color, leuchtet: bool
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if leuchtet:
		mat.emission_enabled = true
		mat.emission = farbe
		mat.emission_energy_multiplier = 2.0
	mesh.material = mat
	mm.mesh = mesh
	mm.instance_count = maxi(anzahl, 0)
	for i in mm.instance_count:
		mm.set_instance_transform(
			i, Transform3D(Basis.from_scale(groesse * 2.0), Vector3(0, -1000, 0))
		)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = anzahl > 0
	add_child(mmi)
	return mmi


func _tick_schwaerme(stunde: float, wetter_typ: String) -> void:
	_tick_schwarm(_voegel, "vogel", stunde, wetter_typ, _vogel_pos)
	_tick_schwarm(_schmetterlinge, "schmetterling", stunde, wetter_typ, _schmetterling_pos)
	_tick_schwarm(_gluehwuermchen, "gluehwuermchen", stunde, wetter_typ, _wurm_pos)


func _tick_schwarm(
	mmi: MultiMeshInstance3D, art: String, stunde: float, wetter_typ: String, pos_fn: Callable
) -> void:
	if mmi == null or mmi.multimesh.instance_count == 0:
		return
	var an := RanchWildLogik.aktiv(art, stunde, wetter_typ)
	mmi.visible = an
	if not an:
		return
	var mm := mmi.multimesh
	for i in mm.instance_count:
		var alt := mm.get_instance_transform(i)
		mm.set_instance_transform(i, Transform3D(alt.basis, pos_fn.call(i)))


## Vogelschwarm: zwei Ketten ziehen große Kreise am Himmel (Horizont-Deko).
func _vogel_pos(i: int) -> Vector3:
	var anker: Vector3 = _schwarm_anker["vogel"]
	var gruppe := i % 2
	var basis_winkel := _zeit * (0.11 + float(gruppe) * 0.04) + float(gruppe) * PI
	var winkel := basis_winkel - floorf(float(i) / 2.0) * 0.09
	var radius := 180.0 + float(gruppe) * 90.0
	return (
		anker
		+ Vector3(
			cos(winkel) * radius,
			sin(_zeit * 0.8 + float(i)) * 3.0 + float(gruppe) * 14.0,
			sin(winkel) * radius
		)
	)


## Schmetterlinge flattern in Lissajous-Bögen um die Blumenwiese.
func _schmetterling_pos(i: int) -> Vector3:
	var anker: Vector3 = _schwarm_anker["schmetterling"]
	var f := float(i)
	var x := anker.x + sin(_zeit * 0.5 + f * 1.7) * (9.0 + fmod(f * 3.1, 12.0))
	var z := anker.z + cos(_zeit * 0.4 + f * 2.3) * (9.0 + fmod(f * 2.3, 14.0))
	var y := RanchGelaende.hoehe(x, z) + 0.7 + absf(sin(_zeit * 2.2 + f)) * 1.1
	return Vector3(x, y, z)


## Glühwürmchen pulsieren nachts über der Lichtung (+ leichtes Driften).
func _wurm_pos(i: int) -> Vector3:
	var anker: Vector3 = _schwarm_anker["gluehwuermchen"]
	var f := float(i)
	var x := anker.x + sin(_zeit * 0.23 + f * 2.9) * (6.0 + fmod(f * 1.9, 22.0))
	var z := anker.z + cos(_zeit * 0.19 + f * 1.3) * (6.0 + fmod(f * 2.7, 22.0))
	var y := RanchGelaende.hoehe(x, z) + 0.6 + sin(_zeit * 1.1 + f * 0.8) * 0.5 + 0.6
	return Vector3(x, y, z)


## ------------------------------------------------------------- Werkzeug


func _boden(p: Vector2) -> Vector3:
	return Vector3(p.x, RanchGelaende.hoehe(p.x, p.y), p.y)


func _aabb_hoehe(modell: Node3D) -> float:
	var min_y := INF
	var max_y := -INF
	for kind in modell.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = kind
		var aabb := mi.get_aabb()
		min_y = minf(min_y, aabb.position.y)
		max_y = maxf(max_y, aabb.end.y)
	if min_y > max_y:
		return 0.0
	return max_y - min_y


func _kugel(parent: Node3D, pos: Vector3, halb: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mi.mesh = mesh
	mi.scale = halb * 2.0
	mi.position = pos
	mi.material_override = RanchPferd.material(farbe)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
