class_name RanchPferd
extends Node3D
## Das Gooby-Ranch-Pferd (RANCH-1) — PROZEDURAL im GOOBY-Stil gebaut
## (rund, pastellig, große Augen), weil kein Kit ein Pferd liefert.
## Nur Godot-Primitive (Sphere/Capsule/Cylinder), Materialien werden über
## einen static-Cache pro Farbe geteilt. Kleinteile (Augen, Wangen, Mähne)
## werfen KEINE Schatten — hält die Draw-Calls der Ranch-Ansicht im Budget.
##
## Gangarten (User-Pflicht: Idle/Trab/Galopp) laufen als prozedurale
## Animation in _process: Diagonal-Beinpaare im Trab, Sprung-Paare im
## Galopp, Atmen/Schweifwedeln/Blinzeln im Stand. `update_gang(dt)` ist
## der pure Animations-Schritt (Tests rufen ihn direkt mit dt).
##
## Erfüllt zusätzlich den RANCH-2-Modell-VERTRAG (RANCH2-needs.md §2):
## set_farbe/set_gait/tick/head_pivot/equip/body_height/phase — Reiten,
## Pflege und Minispiele sprechen NUR diese Methoden. Blickrichtung ist
## -z (Godot-Vorwärts, wie die Attrappe), Boden bei y=0.
##
##   var pferd := RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
##   add_child(pferd)
##   pferd.set_gangart(RanchPferd.GANG_TRAB)

const GANG_IDLE := "idle"
const GANG_SCHRITT := "schritt"
const GANG_TRAB := "trab"
const GANG_GALOPP := "galopp"

## Frequenz (Hz) + Bein-Amplitude (rad) + Wipp-Höhe (m) je Gangart.
const GANG_PROFILE := {
	GANG_IDLE: {"hz": 0.45, "bein": 0.0, "wippe": 0.015, "nick": 0.03},
	GANG_SCHRITT: {"hz": 1.2, "bein": 0.3, "wippe": 0.03, "nick": 0.05},
	GANG_TRAB: {"hz": 2.1, "bein": 0.5, "wippe": 0.05, "nick": 0.08},
	GANG_GALOPP: {"hz": 2.9, "bein": 0.85, "wippe": 0.11, "nick": 0.16},
}
## RANCH-2-Gangart-Ids ("stand"...) → meine Profile.
const GAIT_ALIAS := {
	"stand": GANG_IDLE,
	"schritt": GANG_SCHRITT,
	"trab": GANG_TRAB,
	"galopp": GANG_GALOPP,
}
## Fellfarben-Ids (RanchPlaySlices.FELLFARBEN) → [Fell, Mähne] im
## Gooby-Pastell (bewusst heller/runder als die Attrappen-Farben).
const FELL := {
	"braun": [Color("#B98A5E"), Color("#6E4B2E")],
	"schwarz": [Color("#6B6470"), Color("#3E3944")],
	"weiss": [Color("#F2E9DC"), Color("#C9B79C")],
	"fuchs": [Color("#D98E5F"), Color("#8A4A2E")],
	"palomino": [Color("#D9A066"), Color("#8A5A33")],
	"schecke": [Color("#C98BB9"), Color("#8A5A7A")],
}
const HUF_FARBE := Color(0.36, 0.30, 0.28)
const AUGEN_WEISS := Color(0.99, 0.99, 0.97)
const AUGEN_INK := Color(0.13, 0.12, 0.14)
const WANGEN_ROSA := Color(0.97, 0.62, 0.66)

## Rücken-Oberkante (Sattel-Auflage) in Metern — für body_height/Gear.
const RUECKEN_Y := 1.42

static var _material_cache: Dictionary = {}

var farbe := Color("#D9A066")
var maehne_farbe := Color("#8A5A33")
var gangart := GANG_IDLE

var _zeit := 0.0
var _blinzel_zeit := 0.0
var _extern_tick_ms := -10000
var _rig: Node3D
var _rumpf: Node3D
var _kopf: Node3D
var _schweif: Array[Node3D] = []
var _beine: Array[Node3D] = []
var _augen: Array[Node3D] = []
var _ohren: Array[Node3D] = []
var _gear: Dictionary = {}
var _gear_farben: Dictionary = {}


## Fabrik: Pferd mit Fell- und Mähnenfarbe (Pack-Daten) bauen.
static func neu(fell: Color, maehne: Color) -> RanchPferd:
	var pferd := RanchPferd.new()
	pferd.farbe = fell
	pferd.maehne_farbe = maehne
	return pferd


## Geteiltes Pastell-Material pro Farbe (ein Material je Farbton im Spiel).
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.92
		_material_cache[key] = mat
	return _material_cache[key]


func _ready() -> void:
	_baue_pferd()


## Selbstläufer-Animation — pausiert, solange ein externer Treiber
## (RANCH-2-Reit-Controller) über tick() die Phase übernimmt.
func _process(delta: float) -> void:
	if Time.get_ticks_msec() - _extern_tick_ms > 500:
		update_gang(delta)


func set_gangart(gang: String) -> void:
	if GANG_PROFILE.has(gang):
		gangart = gang


## ------------------------------------------- RANCH-2-Vertrag (Modell-API)


## Fellfarbe per Id setzen (RanchPlaySlices.FELLFARBEN) — baut das Pferd
## bei Bedarf mit den neuen geteilten Materialien neu auf.
func set_farbe(id: String) -> void:
	var paar: Array = FELL.get(id, FELL["braun"])
	farbe = paar[0]
	maehne_farbe = paar[1]
	if _rig != null:
		_neu_bauen()


## Gangart per RANCH-2-Id ("stand"|"schritt"|"trab"|"galopp").
func set_gait(id: String) -> void:
	set_gangart(str(GAIT_ALIAS.get(id, id)))


## Externer Animations-Treiber (Reit-Controller): `tempo` (m/s) staucht/
## streckt die Schrittfrequenz relativ zum Gangart-Zieltempo — dieselbe
## Semantik wie horse_stub.tick.
func tick(delta: float, tempo: float = -1.0) -> void:
	_extern_tick_ms = Time.get_ticks_msec()
	var mult := 1.0
	if tempo >= 0.0 and gangart != GANG_IDLE:
		var ziel := RanchRideFeel.zieltempo(_ride_id())
		if ziel > 0.01:
			mult = clampf(tempo / ziel, 0.35, 1.25)
	update_gang(delta * mult)


## Kopf-Knoten fürs Kopfnicken beim Reiten.
func head_pivot() -> Node3D:
	return _kopf


## Ausrüstung anlegen/abnehmen (farbe null = abnehmen) — Gear-Meshes von
## RANCH-2 (RanchGearMeshes), Positionen auf meine Proportionen gelegt.
func equip(slot: String, gear_farbe: Variant) -> void:
	if _gear.has(slot):
		(_gear[slot] as Node3D).queue_free()
		_gear.erase(slot)
	_gear_farben.erase(slot)
	if not (gear_farbe is String):
		return
	var aufsatz := RanchGearMeshes.build(slot, gear_farbe)
	if aufsatz == null:
		return
	match slot:
		"sattel":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.06, 0.05)
			add_child(aufsatz)
		"decke":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.02, 0.05)
			add_child(aufsatz)
		"halfter":
			if _kopf == null:
				aufsatz.free()
				return
			aufsatz.position = Vector3(0.0, -0.06, 0.3)
			_kopf.add_child(aufsatz)
		_:
			aufsatz.free()
			return
	_gear[slot] = aufsatz
	_gear_farben[slot] = gear_farbe


## Sitzhöhe (Sattel-Oberkante) für den Gooby-Sitz.
func body_height() -> float:
	return RUECKEN_Y + 0.12


## Aktuelle Schrittphase (0..1) — Reit-Controller synct Kopfnicken/Hufe.
func phase() -> float:
	return fposmod(_zeit * float(GANG_PROFILE[gangart]["hz"]), 1.0)


func _ride_id() -> String:
	for id: String in GAIT_ALIAS:
		if str(GAIT_ALIAS[id]) == gangart:
			return id
	return "stand"


## Umbau bei Farbwechsel: Gear + Rig neu (Materialien sind farb-gecacht).
func _neu_bauen() -> void:
	var gear_kopie := _gear_farben.duplicate()
	for slot: String in _gear:
		(_gear[slot] as Node3D).queue_free()
	_gear = {}
	_gear_farben = {}
	if _rig != null:
		_rig.queue_free()
	_rig = null
	_rumpf = null
	_kopf = null
	_schweif = []
	_beine = []
	_augen = []
	_ohren = []
	_baue_pferd()
	for slot: String in gear_kopie:
		equip(slot, gear_kopie[slot])


## Ein Animations-Schritt (pure — Tests rufen es direkt mit dt).
func update_gang(dt: float) -> void:
	if _rumpf == null:
		return
	_zeit += dt
	_blinzel_zeit += dt
	var profil: Dictionary = GANG_PROFILE[gangart]
	var omega := TAU * float(profil["hz"])
	var phase := _zeit * omega
	_rumpf.position.y = 0.92 + sin(phase * 2.0) * float(profil["wippe"])
	_rumpf.rotation.x = sin(phase) * float(profil["nick"]) * 0.5
	_kopf.rotation.x = sin(phase + 0.6) * float(profil["nick"])
	if gangart == GANG_IDLE:
		# Atmen + Schweifwedeln + Ohren-Zucken im Stand.
		_rumpf.scale = Vector3.ONE * (1.0 + sin(phase) * 0.012)
		for i in _schweif.size():
			_schweif[i].rotation.y = sin(phase * 1.4 + float(i) * 0.7) * 0.28
		for i in _ohren.size():
			_ohren[i].rotation.z = sin(phase * 0.9 + float(i) * PI) * 0.10
		for bein in _beine:
			bein.rotation.x = lerpf(bein.rotation.x, 0.0, minf(1.0, dt * 6.0))
	else:
		_rumpf.scale = Vector3.ONE
		var amp := float(profil["bein"])
		for i in _beine.size():
			# Trab: Diagonalpaare (0+3 vs. 1+2). Galopp: vorn vs. hinten.
			var versatz := 0.0
			if gangart == GANG_TRAB:
				versatz = 0.0 if (i == 0 or i == 3) else PI
			else:
				versatz = 0.0 if i < 2 else PI * 0.62
			_beine[i].rotation.x = sin(phase + versatz) * amp
		for i in _schweif.size():
			_schweif[i].rotation.y = sin(phase + float(i) * 0.5) * 0.35
	_blinzle()


## Blinzeln: alle ~3,4 s klappen die Augen für einen Wimpernschlag zu.
func _blinzle() -> void:
	var zyklus := fmod(_blinzel_zeit, 3.4)
	var zu := zyklus > 3.25
	for auge in _augen:
		auge.scale.y = 0.12 if zu else 1.0


## ------------------------------------------------------------- Bau-Helfer


func _baue_pferd() -> void:
	# Rig um 180° gedreht: gebaut wird „Kopf Richtung +z“, nach außen zeigt
	# das Pferd Richtung -z (Godot-Vorwärts, RANCH-2-Vertrag).
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.rotation.y = PI
	add_child(_rig)
	_rumpf = Node3D.new()
	_rumpf.name = "Rumpf"
	_rumpf.position.y = 0.92
	_rig.add_child(_rumpf)
	# Runder Körper: Bauch-Kugel + Brust-Kugel (birnig wie Gooby selbst).
	_kugel(_rumpf, Vector3(0.0, 0.0, -0.12), Vector3(0.62, 0.56, 0.88), farbe, true)
	_kugel(_rumpf, Vector3(0.0, 0.06, 0.42), Vector3(0.52, 0.5, 0.5), farbe, true)
	# Hals: geneigte Kapsel nach vorn-oben.
	var hals := _kapsel(_rumpf, Vector3(0.0, 0.36, 0.58), 0.21, 0.62, farbe, true)
	hals.rotation.x = deg_to_rad(-38.0)
	_baue_kopf()
	_baue_maehne_und_schweif()
	_baue_beine()


func _baue_kopf() -> void:
	_kopf = Node3D.new()
	_kopf.name = "Kopf"
	_kopf.position = Vector3(0.0, 0.72, 0.78)
	_rumpf.add_child(_kopf)
	var hell := farbe.lightened(0.28)
	# Großer runder Kopf + helle Schnauze (Gooby-Proportionen).
	_kugel(_kopf, Vector3.ZERO, Vector3(0.4, 0.38, 0.42), farbe, true)
	_kugel(_kopf, Vector3(0.0, -0.1, 0.3), Vector3(0.26, 0.2, 0.24), hell, false)
	# Nüstern als Mini-Kugeln auf der Schnauze.
	for seite: float in [-1.0, 1.0]:
		_kugel(_kopf, Vector3(seite * 0.09, -0.07, 0.5), Vector3(0.035, 0.035, 0.02), farbe, false)
	# RIESIGE Augen: Weiß + Pupille + Glanzpunkt.
	for seite: float in [-1.0, 1.0]:
		var auge := Node3D.new()
		auge.position = Vector3(seite * 0.2, 0.1, 0.26)
		_kopf.add_child(auge)
		_augen.append(auge)
		_kugel(auge, Vector3.ZERO, Vector3(0.115, 0.13, 0.07), AUGEN_WEISS, false)
		_kugel(auge, Vector3(0.0, 0.0, 0.05), Vector3(0.06, 0.075, 0.035), AUGEN_INK, false)
		_kugel(auge, Vector3(0.025, 0.035, 0.08), Vector3(0.02, 0.02, 0.012), AUGEN_WEISS, false)
	# Rosa Wangen unter den Augen.
	for seite: float in [-1.0, 1.0]:
		_kugel(
			_kopf, Vector3(seite * 0.26, -0.05, 0.2), Vector3(0.07, 0.05, 0.04), WANGEN_ROSA, false
		)
	# Ohren: weiche Kegel, leicht nach außen gekippt.
	for seite: float in [-1.0, 1.0]:
		var ohr := Node3D.new()
		ohr.position = Vector3(seite * 0.18, 0.3, -0.05)
		_kopf.add_child(ohr)
		_ohren.append(ohr)
		var spitze := _kegel(ohr, Vector3.ZERO, 0.09, 0.22, farbe)
		spitze.rotation.z = seite * deg_to_rad(-16.0)
	# Stirnschopf in Mähnenfarbe.
	_kugel(_kopf, Vector3(0.0, 0.28, 0.16), Vector3(0.16, 0.1, 0.14), maehne_farbe, false)


func _baue_maehne_und_schweif() -> void:
	# Mähne: weiche Hügel den Hals entlang.
	for i in 4:
		var t := float(i) / 3.0
		var pos := Vector3(0.0, lerpf(0.62, 0.22, t), lerpf(0.66, 0.42, t))
		_kugel(_rumpf, pos, Vector3(0.11, 0.14, 0.15), maehne_farbe, false)
	# Puschel-Schweif: drei Kugeln, die im Wind wedeln.
	var wurzel := Node3D.new()
	wurzel.name = "Schweif"
	wurzel.position = Vector3(0.0, 0.18, -0.92)
	_rumpf.add_child(wurzel)
	var traeger := wurzel
	for i in 3:
		var glied := Node3D.new()
		glied.position = Vector3.ZERO if i == 0 else Vector3(0.0, -0.16, -0.1)
		traeger.add_child(glied)
		_schweif.append(glied)
		var groesse := 0.16 - float(i) * 0.035
		_kugel(glied, Vector3.ZERO, Vector3.ONE * groesse, maehne_farbe, false)
		traeger = glied


func _baue_beine() -> void:
	# Reihenfolge: vorn-links, vorn-rechts, hinten-links, hinten-rechts.
	var anker: Array[Vector3] = [
		Vector3(-0.3, -0.25, 0.48),
		Vector3(0.3, -0.25, 0.48),
		Vector3(-0.32, -0.25, -0.5),
		Vector3(0.32, -0.25, -0.5),
	]
	for pos in anker:
		var bein := Node3D.new()
		bein.position = pos
		_rumpf.add_child(bein)
		_beine.append(bein)
		_kapsel(bein, Vector3(0.0, -0.28, 0.0), 0.11, 0.56, farbe, true)
		var huf := _zylinder(bein, Vector3(0.0, -0.6, 0.02), 0.12, 0.1, HUF_FARBE)
		huf.rotation.x = 0.0


func _kugel(
	parent: Node3D, pos: Vector3, groesse: Vector3, color: Color, schatten: bool
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 10
	return _mesh_knoten(parent, mesh, pos, groesse * 2.0, color, schatten)


func _kapsel(
	parent: Node3D, pos: Vector3, radius: float, hoehe: float, color: Color, schatten: bool
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 14
	mesh.rings = 6
	return _mesh_knoten(parent, mesh, pos, Vector3.ONE, color, schatten)


func _kegel(parent: Node3D, pos: Vector3, radius: float, hoehe: float, color: Color) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 10
	return _mesh_knoten(parent, mesh, pos, Vector3.ONE, color, false)


func _zylinder(
	parent: Node3D, pos: Vector3, radius: float, hoehe: float, color: Color
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.06
	mesh.height = hoehe
	mesh.radial_segments = 12
	return _mesh_knoten(parent, mesh, pos, Vector3.ONE, color, true)


func _mesh_knoten(
	parent: Node3D, mesh: Mesh, pos: Vector3, skala: Vector3, color: Color, schatten: bool
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = skala
	mi.material_override = RanchPferd.material(color)
	if not schatten:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
