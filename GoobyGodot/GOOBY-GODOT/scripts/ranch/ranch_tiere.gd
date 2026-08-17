class_name RanchTier
extends Node3D
## Ranch-Weidetiere (RANCH-1): Kuh, Schaf und Huhn — prozedural im
## GOOBY-Stil (rund, pastellig, große Augen), bewusst BILLIGER als das
## Pferd (~10 Meshes pro Tier, Kleinteile ohne Schatten). Sanfte
## Idle-Animation (Grasen/Wippen/Picken) in _process; `update_tier(dt)`
## ist der pure Schritt für Tests.
##
##   add_child(RanchTier.neu("kuh", Color("#F5EFE4"), Color("#7A5C43")))

const ART_KUH := "kuh"
const ART_SCHAF := "schaf"
const ART_HUHN := "huhn"

const AUGEN_WEISS := Color(0.99, 0.99, 0.97)
const AUGEN_INK := Color(0.13, 0.12, 0.14)

var art := ART_KUH
var farbe := Color(0.95, 0.93, 0.88)
var akzent := Color(0.48, 0.36, 0.26)

var _zeit := 0.0
var _phase_versatz := 0.0
var _kopf: Node3D


static func neu(tier_art: String, fell: Color, tier_akzent := Color.TRANSPARENT) -> RanchTier:
	var tier := RanchTier.new()
	tier.art = tier_art
	tier.farbe = fell
	tier.akzent = tier_akzent if tier_akzent.a > 0.0 else fell.darkened(0.35)
	return tier


func _ready() -> void:
	_phase_versatz = fmod(absf(position.x * 3.1 + position.z * 1.7), TAU)
	match art:
		ART_SCHAF:
			_baue_schaf()
		ART_HUHN:
			_baue_huhn()
		_:
			_baue_kuh()


func _process(delta: float) -> void:
	update_tier(delta)


## Pure Idle-Schritt: Kopf nickt (Grasen/Picken), Körper wippt minimal.
func update_tier(dt: float) -> void:
	if _kopf == null:
		return
	_zeit += dt
	var phase := _zeit * TAU * 0.35 + _phase_versatz
	var tiefe := 0.22 if art == ART_HUHN else 0.14
	_kopf.rotation.x = maxf(0.0, sin(phase)) * tiefe
	_kopf.position.y = _kopf_hoehe() - maxf(0.0, sin(phase)) * 0.05
	rotation.z = sin(phase * 0.5) * 0.008


func _kopf_hoehe() -> float:
	match art:
		ART_HUHN:
			return 0.42
		ART_SCHAF:
			return 0.62
		_:
			return 0.78


## ------------------------------------------------------------- Bau-Helfer


func _baue_kuh() -> void:
	var rumpf := _knoten(Vector3(0.0, 0.62, 0.0))
	_kugel(rumpf, Vector3.ZERO, Vector3(0.5, 0.42, 0.7), farbe, true)
	# Flecken: flache Akzent-Kugeln auf dem Rücken.
	_kugel(rumpf, Vector3(0.22, 0.18, 0.18), Vector3(0.2, 0.1, 0.24), akzent, false)
	_kugel(rumpf, Vector3(-0.2, 0.2, -0.24), Vector3(0.18, 0.09, 0.2), akzent, false)
	_kopf = _knoten(Vector3(0.0, _kopf_hoehe(), 0.62))
	_kugel(_kopf, Vector3.ZERO, Vector3(0.26, 0.24, 0.26), farbe, true)
	_kugel(_kopf, Vector3(0.0, -0.08, 0.16), Vector3(0.18, 0.12, 0.12), farbe.lightened(0.3), false)
	_augen(_kopf, 0.13, 0.07, 0.17)
	for seite: float in [-1.0, 1.0]:
		_kugel(_kopf, Vector3(seite * 0.24, 0.14, -0.02), Vector3(0.1, 0.05, 0.06), akzent, false)
	_beine(0.34, 0.44, 0.24)


func _baue_schaf() -> void:
	var rumpf := _knoten(Vector3(0.0, 0.5, 0.0))
	# Wolle: eine große + vier kleine Puschel-Kugeln.
	_kugel(rumpf, Vector3.ZERO, Vector3(0.42, 0.36, 0.52), farbe, true)
	_kugel(rumpf, Vector3(0.16, 0.2, 0.14), Vector3(0.18, 0.15, 0.18), farbe.lightened(0.1), false)
	_kugel(rumpf, Vector3(-0.16, 0.2, -0.1), Vector3(0.17, 0.14, 0.18), farbe.lightened(0.1), false)
	_kugel(rumpf, Vector3(0.0, 0.14, -0.34), Vector3(0.16, 0.14, 0.14), farbe.lightened(0.1), false)
	_kopf = _knoten(Vector3(0.0, _kopf_hoehe(), 0.46))
	_kugel(_kopf, Vector3.ZERO, Vector3(0.2, 0.19, 0.2), akzent.lightened(0.45), true)
	_kugel(_kopf, Vector3(0.0, 0.14, -0.02), Vector3(0.16, 0.1, 0.14), farbe, false)
	_augen(_kopf, 0.1, 0.06, 0.13)
	_beine(0.24, 0.34, 0.18)


func _baue_huhn() -> void:
	var rumpf := _knoten(Vector3(0.0, 0.26, 0.0))
	_kugel(rumpf, Vector3.ZERO, Vector3(0.2, 0.18, 0.24), farbe, true)
	_kugel(rumpf, Vector3(0.0, 0.06, -0.2), Vector3(0.1, 0.12, 0.08), farbe.darkened(0.12), false)
	_kopf = _knoten(Vector3(0.0, _kopf_hoehe(), 0.16))
	_kugel(_kopf, Vector3.ZERO, Vector3(0.12, 0.12, 0.12), farbe, true)
	# Kamm + Schnabel.
	_kugel(
		_kopf, Vector3(0.0, 0.12, 0.0), Vector3(0.05, 0.06, 0.08), Color(0.91, 0.32, 0.29), false
	)
	_kegel(_kopf, Vector3(0.0, -0.02, 0.14), 0.04, 0.1, Color(0.95, 0.73, 0.35))
	_augen(_kopf, 0.06, 0.035, 0.08)
	for seite: float in [-1.0, 1.0]:
		var bein := _knoten(Vector3(seite * 0.06, 0.12, 0.0))
		_zylinder(bein, Vector3(0.0, -0.07, 0.0), 0.016, 0.14, Color(0.95, 0.73, 0.35))


## Zwei große Augen + Pupillen (x-Versatz, Pupillengröße, Augengröße).
func _augen(kopf: Node3D, versatz: float, pupille: float, groesse: float) -> void:
	for seite: float in [-1.0, 1.0]:
		var auge := Node3D.new()
		auge.position = Vector3(seite * versatz, 0.04, groesse * 0.9)
		kopf.add_child(auge)
		_kugel(
			auge, Vector3.ZERO, Vector3(groesse, groesse * 1.1, groesse * 0.55), AUGEN_WEISS, false
		)
		_kugel(
			auge,
			Vector3(0.0, 0.0, groesse * 0.4),
			Vector3(pupille, pupille * 1.2, pupille * 0.5),
			AUGEN_INK,
			false
		)


func _beine(x: float, hoehe: float, z: float) -> void:
	for ecke: Vector2 in [Vector2(-x, z), Vector2(x, z), Vector2(-x, -z), Vector2(x, -z)]:
		var bein := _knoten(Vector3(ecke.x, hoehe * 0.5, ecke.y))
		_zylinder(bein, Vector3.ZERO, 0.07, hoehe, farbe.darkened(0.18))


func _knoten(pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	return node


func _kugel(
	parent: Node3D, pos: Vector3, groesse: Vector3, color: Color, schatten: bool
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _mesh_knoten(parent, mesh, pos, groesse * 2.0, color, schatten)


func _kegel(parent: Node3D, pos: Vector3, radius: float, hoehe: float, color: Color) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.01
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 8
	var knoten := _mesh_knoten(parent, mesh, pos, Vector3.ONE, color, false)
	knoten.rotation.x = deg_to_rad(90.0)
	return knoten


func _zylinder(
	parent: Node3D, pos: Vector3, radius: float, hoehe: float, color: Color
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 10
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
