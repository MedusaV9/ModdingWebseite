class_name GartenLeben
extends Node3D
## Ambient-Leben + Deko des GARTENS (EVAL-2026-08 Lens B, Befunde 5+7:
## „Garten wirkt leer“, „Belebung dosiert“): Trittstein-Weg ab der Haustür
## im Weg-Material des Spielers (kohärent mit dem Gestalten-Modus),
## Blumensaum + Büsche an den Zäunen, eine Wäscheleine (CatenaryLogic —
## dieselbe Kettenlinie wie die Girlanden) mit schwingender Wäsche, zwei
## kreisende Vögel, Schmetterlinge und eine Katze auf dem Zaun.
##
## BEWUSST BILLIG: geteilte Flat-/Surface-Materialien, MultiMesh für alle
## Wiederholer, EIN _process für alle Bewegungen. Deterministisch über
## einen festen Seed — Screenshots und Tests sehen immer denselben Garten.

const ASSETS := "res://assets/city/natur"
const BLUMEN_GLBS: Array[String] = ["flower_purpleA", "flower_redA", "flower_yellowA"]
const WAESCHE_FARBEN: Array[String] = ["himmel", "rose", "butter"]
## Leinen-Höhe an den Pfosten; Durchhang der Kettenlinie (m).
const LEINE_HOEHE := 1.5
const LEINE_DURCHHANG := 0.22
const VOGEL_HOEHE := 3.4
const FLUEGEL_TAKT := 9.0

var _zeit := 0.0
var _welt := Vector2.ZERO
var _voegel: Array[Dictionary] = []
var _falter: Array[Dictionary] = []
var _waesche: Array[Node3D] = []
var _fluegel: Array[Node3D] = []
var _katzen_schwanz: Node3D
var _sitzvogel: Node3D


## Zaun-Material des Gestalten-Modus (RoomBase-Außenwände rufen das —
## Farbe/Hecke des Spielers statt hartkodiertem Braun).
static func zaun_material(style: Dictionary) -> Material:
	return HouseExterior.teil_material("zaun", style)


## Zaun-Kappe: schmaler Handlauf auf der Oberkante eines Zaun-Segments
## (lokales Kind — macht Tür-/Fenster-Rebuilds automatisch mit).
static func zaun_kappe(
	segment: MeshInstance3D, along_x: bool, length: float, y0: float, y1: float
) -> Node3D:
	var kappe := MeshInstance3D.new()
	kappe.name = "ZaunKappe"
	var box := BoxMesh.new()
	var breite := RoomBase.WALL_THICKNESS + 0.08
	box.size = (
		Vector3(length + 0.04, 0.055, breite) if along_x else Vector3(breite, 0.055, length + 0.04)
	)
	kappe.mesh = box
	kappe.material_override = segment.material_override
	kappe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kappe.position = Vector3(0.0, (y1 - y0) * 0.5 + 0.0275, 0.0)
	return kappe


## An einen RoomBase-Raum hängen (nur Outdoor-Räume; idempotent).
static func attach_to(room: Node) -> GartenLeben:
	var room_def: Dictionary = room.room_def()
	if not bool(room_def.get("outdoor", false)):
		return null
	var vorhanden := room.get_node_or_null("GartenLeben")
	if vorhanden is GartenLeben:
		return vorhanden
	var leben := GartenLeben.new()
	leben.name = "GartenLeben"
	leben.baue(room_def, HouseStyleState.style(room.call("game_state")))
	room.add_child(leben)
	return leben


func baue(room_def: Dictionary, style: Dictionary) -> void:
	var zellen: Vector2i = room_def["grid"]
	_welt = Vector2(zellen.x * GridData.CELL_SIZE, zellen.y * GridData.CELL_SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("garten_leben")
	_baue_trittsteine(room_def, style)
	_baue_blumensaum(rng)
	_baue_waescheleine()
	_baue_voegel(rng)
	_baue_falter(rng)
	_baue_katze()


## Nachtruhe (EVAL-2026-08 Lens B „Belebung dosiert“): Vögel + Falter
## fliegen nur tagsüber — nachts übernehmen Katze und Fensterglut.
func stunde_anwenden(stunde: float) -> void:
	var tag := stunde >= 6.5 and stunde < 20.0
	for vogel: Dictionary in _voegel:
		(vogel["node"] as Node3D).visible = tag
	for falter: Dictionary in _falter:
		(falter["node"] as Node3D).visible = tag
	if _sitzvogel != null:
		_sitzvogel.visible = tag


func _process(delta: float) -> void:
	_zeit += delta
	_voegel_bewegen()
	_falter_bewegen()
	for i in _waesche.size():
		_waesche[i].rotation.x = sin(_zeit * 1.3 + i * 1.7) * 0.09
	for i in _fluegel.size():
		var winkel := sin(_zeit * FLUEGEL_TAKT + i) * 0.55
		_fluegel[i].rotation.z = winkel if i % 2 == 0 else -winkel
	if _katzen_schwanz != null:
		_katzen_schwanz.rotation.x = 0.35 + sin(_zeit * 1.8) * 0.22


# ── Weg + Pflanzen ───────────────────────────────────────────────────────────


## Trittsteine von der Haustür (Garten-Tür an der N-Wand) in den Garten —
## im Weg-Material des Gestalten-Modus (Zaun-/Weg-Wahl bleibt kohärent).
func _baue_trittsteine(room_def: Dictionary, style: Dictionary) -> void:
	var tuer_x := _welt.x * 0.5
	for door_def: Dictionary in room_def.get("doors", []):
		if str(door_def.get("wall", "")) == "N":
			tuer_x = RoomDefs.door_world_pos(room_def, door_def).x
	var material := HouseExterior.teil_material("weg", style)
	if material == null:
		material = CustomizeMaterials.surface("platten", "sandstein")
	for i in 4:
		var stein := MeshInstance3D.new()
		stein.name = "Trittstein%d" % i
		var scheibe := CylinderMesh.new()
		scheibe.top_radius = 0.3
		scheibe.bottom_radius = 0.33
		scheibe.height = 0.045
		stein.mesh = scheibe
		stein.material_override = material
		stein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var seite := 0.22 if i % 2 == 0 else -0.22
		stein.position = Vector3(tuer_x + seite, 0.024, 1.0 + i * 0.85)
		add_child(stein)


## Blumensaum + Büsche + Steine an den Zaun-Innenseiten (W/E/S) — drei
## Blumen-Sorten gemischt, damit die Beet-Ränder nicht monoton wirken.
func _baue_blumensaum(rng: RandomNumberGenerator) -> void:
	var je_sorte: Dictionary = {}
	for glb: String in BLUMEN_GLBS:
		je_sorte[glb] = [] as Array[Transform3D]
	for punkt: Vector3 in _saum_punkte(rng):
		var basis := (
			Basis(Vector3.UP, rng.randf() * TAU)
			* Basis.from_scale(Vector3.ONE * rng.randf_range(0.5, 0.75))
		)
		var sorte: String = BLUMEN_GLBS[rng.randi_range(0, BLUMEN_GLBS.size() - 1)]
		(je_sorte[sorte] as Array[Transform3D]).append(Transform3D(basis, punkt))
	for glb: String in BLUMEN_GLBS:
		HomeProps.multi_glb(self, "%s/%s.glb" % [ASSETS, glb], je_sorte[glb], "Saum_%s" % glb)
	var bueshe: Array[Transform3D] = []
	for ecke: Vector3 in [
		Vector3(0.7, 0.0, _welt.y - 0.7),
		Vector3(_welt.x - 0.7, 0.0, _welt.y - 0.7),
		Vector3(0.75, 0.0, _welt.y * 0.45),
	]:
		var basis := (
			Basis(Vector3.UP, rng.randf() * TAU)
			* Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.05))
		)
		bueshe.append(Transform3D(basis, ecke))
	HomeProps.multi_glb(self, "%s/plant_bush.glb" % ASSETS, bueshe, "SaumBusch")
	var steine: Array[Transform3D] = []
	for _i in 3:
		var punkt := Vector3(
			rng.randf_range(1.2, _welt.x - 1.2), 0.0, _welt.y - rng.randf_range(0.5, 0.9)
		)
		var basis := (
			Basis(Vector3.UP, rng.randf() * TAU)
			* Basis.from_scale(Vector3.ONE * rng.randf_range(0.7, 1.1))
		)
		steine.append(Transform3D(basis, punkt))
	HomeProps.multi_glb(self, "%s/rock_smallA.glb" % ASSETS, steine, "SaumStein")


## Punkte des Blumensaums entlang W-, E- und S-Zaun (Lücke an der Leine).
func _saum_punkte(rng: RandomNumberGenerator) -> Array[Vector3]:
	var punkte: Array[Vector3] = []
	var z := 1.0
	while z < _welt.y - 1.0:
		punkte.append(Vector3(0.42 + rng.randf() * 0.25, 0.0, z + rng.randf() * 0.3))
		z += 1.15
	z = 5.4
	while z < _welt.y - 1.0:
		punkte.append(Vector3(_welt.x - 0.42 - rng.randf() * 0.25, 0.0, z + rng.randf() * 0.3))
		z += 1.15
	var x := 1.3
	while x < _welt.x - 1.3:
		punkte.append(Vector3(x + rng.randf() * 0.35, 0.0, _welt.y - 0.42 - rng.randf() * 0.2))
		x += 1.25
	return punkte


# ── Wäscheleine ──────────────────────────────────────────────────────────────


## Wäscheleine am Ost-Zaun: zwei Holzpfosten, die Leine hängt als echte
## Kettenlinie (CatenaryLogic) durch, drei Tücher schwingen im _process.
func _baue_waescheleine() -> void:
	var x := _welt.x - 0.55
	var a := Vector3(x, LEINE_HOEHE, 1.4)
	var b := Vector3(x, LEINE_HOEHE, 4.4)
	for ende: Vector3 in [a, b]:
		var pfosten := HomeProps.box(Vector3(0.09, LEINE_HOEHE + 0.12, 0.09), "holz_dunkel")
		pfosten.name = "LeinenPfosten"
		pfosten.position = Vector3(ende.x, (LEINE_HOEHE + 0.12) * 0.5, ende.z)
		add_child(pfosten)
	var punkte := CatenaryLogic.punkte(a, b, 10, LEINE_DURCHHANG)
	_leine_mesh(punkte)
	var indizes: Array[int] = [3, 5, 7]
	for i in indizes.size():
		var halter := Node3D.new()
		halter.name = "Waesche%d" % i
		halter.position = punkte[indizes[i]]
		var tuch := HomeProps.box(Vector3(0.42, 0.5, 0.018), WAESCHE_FARBEN[i])
		tuch.position = Vector3(0.0, -0.26, 0.0)
		halter.add_child(tuch)
		add_child(halter)
		_waesche.append(halter)


## Leinen-Segmente als EIN MultiMesh dünner Stäbe entlang der Kettenlinie.
func _leine_mesh(punkte: Array[Vector3]) -> void:
	var stab := BoxMesh.new()
	stab.size = Vector3(0.014, 0.014, 1.0)
	stab.material = CustomizeMaterials.flat("grau_hell")
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = stab
	multi.instance_count = punkte.size() - 1
	for i in punkte.size() - 1:
		var von := punkte[i]
		var nach := punkte[i + 1]
		var mitte := (von + nach) * 0.5
		var basis := (
			Basis.looking_at(nach - von, Vector3.UP)
			* Basis.from_scale(Vector3(1.0, 1.0, von.distance_to(nach)))
		)
		multi.set_instance_transform(i, Transform3D(basis, mitte))
	var instanz := MultiMeshInstance3D.new()
	instanz.name = "Leine"
	instanz.multimesh = multi
	instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instanz)


# ── Tiere ────────────────────────────────────────────────────────────────────


## Zwei Vögel kreisen über dem Garten, einer sitzt auf dem Süd-Zaun.
func _baue_voegel(rng: RandomNumberGenerator) -> void:
	for i in 2:
		var vogel := _vogel_bauen("walnuss" if i == 0 else "schiefer")
		add_child(vogel)
		(
			_voegel
			. append(
				{
					"node": vogel,
					"radius": _welt.x * rng.randf_range(0.28, 0.4),
					"hoehe": VOGEL_HOEHE + i * 0.7,
					"tempo": rng.randf_range(0.35, 0.5) * (1.0 if i == 0 else -1.0),
					"phase": rng.randf() * TAU,
				}
			)
		)
	_sitzvogel = _vogel_bauen("terracotta")
	_sitzvogel.position = Vector3(_welt.x * 0.3, RoomBase.FENCE_HEIGHT + 0.05, _welt.y - 0.02)
	_sitzvogel.rotation.y = PI * 0.75
	add_child(_sitzvogel)


## Mini-Vogel aus drei Boxen: Körper + zwei Schlag-Flügel (im _process).
func _vogel_bauen(farbe: String) -> Node3D:
	var vogel := Node3D.new()
	vogel.name = "Vogel"
	var koerper := HomeProps.box(Vector3(0.13, 0.11, 0.24), farbe)
	koerper.position = Vector3(0.0, 0.05, 0.0)
	vogel.add_child(koerper)
	var schnabel := HomeProps.box(Vector3(0.04, 0.03, 0.06), "sonnengelb")
	schnabel.position = Vector3(0.0, 0.07, 0.14)
	vogel.add_child(schnabel)
	for seite: float in [-1.0, 1.0]:
		var fluegel := Node3D.new()
		fluegel.position = Vector3(seite * 0.065, 0.09, 0.0)
		var blatt := HomeProps.box(Vector3(0.2, 0.014, 0.11), farbe)
		blatt.position = Vector3(seite * 0.1, 0.0, 0.0)
		fluegel.add_child(blatt)
		vogel.add_child(fluegel)
		_fluegel.append(fluegel)
	return vogel


func _voegel_bewegen() -> void:
	var mitte := Vector3(_welt.x * 0.5, 0.0, _welt.y * 0.5)
	for vogel: Dictionary in _voegel:
		var winkel := _zeit * float(vogel["tempo"]) + float(vogel["phase"])
		var radius := float(vogel["radius"])
		var node: Node3D = vogel["node"]
		node.position = (
			mitte
			+ Vector3(
				cos(winkel) * radius,
				float(vogel["hoehe"]) + sin(_zeit * 1.7 + float(vogel["phase"])) * 0.2,
				sin(winkel) * radius
			)
		)
		var richtung := signf(float(vogel["tempo"]))
		node.rotation.y = -winkel + (0.0 if richtung > 0.0 else PI)


## Schmetterlinge flattern über dem Beet-Bereich (Lissajous-Wanderung).
func _baue_falter(rng: RandomNumberGenerator) -> void:
	for i in 3:
		var falter := Node3D.new()
		falter.name = "Falter%d" % i
		var farbe: String = ["rose", "sonnengelb", "flieder"][i]
		for seite: float in [-1.0, 1.0]:
			var wing := Node3D.new()
			wing.position = Vector3(seite * 0.01, 0.0, 0.0)
			var blatt := HomeProps.box(Vector3(0.09, 0.005, 0.07), farbe)
			blatt.position = Vector3(seite * 0.05, 0.0, 0.0)
			wing.add_child(blatt)
			falter.add_child(wing)
			_fluegel.append(wing)
		add_child(falter)
		(
			_falter
			. append(
				{
					"node": falter,
					"anker":
					Vector3(
						rng.randf_range(_welt.x * 0.25, _welt.x * 0.75),
						0.0,
						rng.randf_range(_welt.y * 0.35, _welt.y * 0.8)
					),
					"a": rng.randf_range(0.5, 0.8),
					"b": rng.randf_range(0.3, 0.55),
					"phase": rng.randf() * TAU,
				}
			)
		)


func _falter_bewegen() -> void:
	for falter: Dictionary in _falter:
		var phase := float(falter["phase"])
		var node: Node3D = falter["node"]
		var anker: Vector3 = falter["anker"]
		node.position = (
			anker
			+ Vector3(
				sin(_zeit * float(falter["a"]) + phase) * 1.3,
				0.62 + sin(_zeit * 2.3 + phase) * 0.16,
				cos(_zeit * float(falter["b"]) + phase) * 1.1
			)
		)


## Katze sitzt auf dem West-Zaun und wedelt gemächlich mit dem Schwanz.
func _baue_katze() -> void:
	var katze := Node3D.new()
	katze.name = "ZaunKatze"
	katze.position = Vector3(-0.06, RoomBase.FENCE_HEIGHT, _welt.y * 0.42)
	katze.rotation.y = PI * 0.5
	var koerper := HomeProps.box(Vector3(0.16, 0.17, 0.3), "metall")
	koerper.position = Vector3(0.0, 0.085, 0.0)
	katze.add_child(koerper)
	var brust := HomeProps.box(Vector3(0.1, 0.08, 0.02), "anstrich")
	brust.position = Vector3(0.0, 0.09, 0.16)
	katze.add_child(brust)
	var kopf := HomeProps.box(Vector3(0.14, 0.13, 0.12), "metall")
	kopf.position = Vector3(0.0, 0.23, 0.1)
	katze.add_child(kopf)
	for seite: float in [-1.0, 1.0]:
		var ohr := HomeProps.box(Vector3(0.04, 0.05, 0.02), "metall")
		ohr.position = Vector3(seite * 0.045, 0.315, 0.1)
		katze.add_child(ohr)
	_katzen_schwanz = Node3D.new()
	_katzen_schwanz.position = Vector3(0.0, 0.05, -0.15)
	var schwanz := HomeProps.box(Vector3(0.035, 0.3, 0.035), "metall")
	schwanz.position = Vector3(0.0, 0.14, 0.0)
	_katzen_schwanz.add_child(schwanz)
	katze.add_child(_katzen_schwanz)
	add_child(katze)
