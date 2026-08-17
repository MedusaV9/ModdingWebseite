class_name RNpcFigur
extends Node3D
## Sichtbare Ranch-NPC-Figur (RW-3) — bewusst BILLIG im RanchTier-Stil:
## entweder eine prozedurale Gooby-Variante (runder Hase, große Augen,
## Farb-/Größen-Variante + Rollen-Accessoire) oder eines der neuen
## Tier-GLBs aus assets/ranch/tiere/ (Zebra-Richter, Reh-Flüsterin,
## Post-Ente, Foto-Fuchs, Ranch-Katze). Dazu ein Namensschild (Label3D)
## und eine sanfte Idle-/Watschel-Animation; `update_figur(dt)` ist der
## pure Schritt für Tests.

const AUGEN_WEISS := Color(0.99, 0.99, 0.97)
const AUGEN_INK := Color(0.13, 0.12, 0.14)

var def: Dictionary = {}
var laeuft := false

var _zeit := 0.0
var _phase := 0.0
var _rumpf: Node3D
var _kopf: Node3D
var _glb_player: AnimationPlayer


static func neu(npc_def: Dictionary) -> RNpcFigur:
	var figur := RNpcFigur.new()
	figur.def = npc_def.duplicate(true)
	figur.name = "Npc_%s" % str(npc_def.get("id", "npc"))
	return figur


func _ready() -> void:
	_phase = fmod(absf(position.x * 2.3 + position.z * 1.1), TAU)
	var modell: Dictionary = def.get("modell") if def.get("modell") is Dictionary else {}
	if str(modell.get("art", "gooby")) == "glb":
		_baue_glb(modell)
	else:
		_baue_gooby(modell)
	_baue_schild()


func _process(delta: float) -> void:
	update_figur(delta)


## Pure Animations-Schritt: Idle-Wippen; beim Laufen Watschel-Rollen +
## Hüpf-Bob (GLB-Figuren schalten stattdessen ihre schritt-Animation).
func update_figur(dt: float) -> void:
	_zeit += dt
	var phase := _zeit * TAU * (1.6 if laeuft else 0.35) + _phase
	if _rumpf != null:
		_rumpf.position.y = _basis_hoehe() + absf(sin(phase)) * (0.09 if laeuft else 0.02)
		_rumpf.rotation.z = sin(phase) * (0.08 if laeuft else 0.015)
	if _kopf != null:
		_kopf.rotation.x = maxf(0.0, sin(phase * 0.5)) * 0.08


## Lauf-Zustand umschalten (Manager ruft das beim Stationswechsel).
func setze_laeuft(an: bool) -> void:
	if laeuft == an:
		return
	laeuft = an
	if _glb_player == null:
		return
	var wunsch := "schritt" if an else "idle"
	if _glb_player.has_animation(wunsch):
		_glb_player.play(wunsch)


## ------------------------------------------------------------ Bau-Helfer


func _groesse() -> float:
	var modell: Dictionary = def.get("modell") if def.get("modell") is Dictionary else {}
	return clampf(float(modell.get("groesse", 1.0)), 0.4, 1.6)


func _basis_hoehe() -> float:
	return 0.62 * _groesse()


func _baue_glb(modell: Dictionary) -> void:
	var pfad := str(modell.get("datei", ""))
	if not ResourceLoader.exists(pfad):
		# Notnagel: fehlt das GLB (Teil-Checkout), wird die Gooby-Variante
		# gebaut — die Ranch bleibt bewohnt statt unsichtbar.
		_baue_gooby(modell)
		return
	var szene: PackedScene = load(pfad)
	var glb: Node3D = szene.instantiate()
	glb.scale = Vector3.ONE * _groesse()
	add_child(glb)
	_glb_player = glb.find_child("AnimationPlayer", true, false)
	if _glb_player != null and _glb_player.has_animation("idle"):
		_glb_player.play("idle")


## Prozeduraler Chibi-Gooby: Rumpf, Kopf, Hasenohren, Augen, Füße —
## plus Rollen-Accessoire (kopftuch/brille/schuerze/strohhut/hut_feder/
## kappe/nadelkissen).
func _baue_gooby(modell: Dictionary) -> void:
	var fell := Color.from_string(str(modell.get("farbe", "#C89F7B")), Color("#C89F7B"))
	var akzent := Color.from_string(str(modell.get("akzent", "")), fell.darkened(0.35))
	var s := _groesse()
	_rumpf = _knoten(Vector3(0.0, _basis_hoehe(), 0.0))
	_kugel(_rumpf, Vector3.ZERO, Vector3(0.42, 0.4, 0.36) * s, fell, true)
	_kugel(
		_rumpf,
		Vector3(0.0, -0.06, 0.24) * s,
		Vector3(0.24, 0.2, 0.16) * s,
		fell.lightened(0.25),
		false
	)
	_kopf = _knoten(Vector3(0.0, _basis_hoehe() + 0.5 * s, 0.06 * s))
	_kugel(_kopf, Vector3.ZERO, Vector3(0.34, 0.32, 0.32) * s, fell, true)
	_kugel(
		_kopf,
		Vector3(0.0, -0.08, 0.26) * s,
		Vector3(0.14, 0.1, 0.08) * s,
		fell.lightened(0.3),
		false
	)
	for seite: float in [-1.0, 1.0]:
		var ohr := _knoten(Vector3(seite * 0.16 * s, _basis_hoehe() + 0.78 * s, 0.02 * s))
		ohr.rotation.z = seite * -0.18
		_kugel(ohr, Vector3.ZERO, Vector3(0.09, 0.3, 0.07) * s, fell, true)
		_kugel(
			ohr,
			Vector3(0.0, -0.02, 0.03) * s,
			Vector3(0.05, 0.2, 0.04) * s,
			fell.lightened(0.35),
			false
		)
		var fuss := _knoten(Vector3(seite * 0.16 * s, 0.1 * s, 0.06 * s))
		_kugel(fuss, Vector3.ZERO, Vector3(0.12, 0.09, 0.18) * s, fell.darkened(0.12), false)
	_augen(0.12 * s, 0.055 * s, 0.1 * s)
	_baue_accessoire(str(modell.get("accessoire", "")), fell, akzent, s)


func _augen(versatz: float, pupille: float, groesse: float) -> void:
	for seite: float in [-1.0, 1.0]:
		var auge := Node3D.new()
		auge.position = Vector3(seite * versatz, 0.05, groesse * 2.4)
		_kopf.add_child(auge)
		_kugel(
			auge, Vector3.ZERO, Vector3(groesse, groesse * 1.15, groesse * 0.5), AUGEN_WEISS, false
		)
		_kugel(
			auge,
			Vector3(0.0, 0.0, groesse * 0.35),
			Vector3(pupille, pupille * 1.2, pupille * 0.5),
			AUGEN_INK,
			false
		)


func _baue_accessoire(accessoire: String, _fell: Color, akzent: Color, s: float) -> void:
	match accessoire:
		"kopftuch":
			_kugel(
				_kopf, Vector3(0.0, 0.16, -0.04) * s, Vector3(0.3, 0.12, 0.28) * s, akzent, false
			)
		"brille":
			for seite: float in [-1.0, 1.0]:
				_torus(_kopf, Vector3(seite * 0.12, 0.05, 0.26) * s, 0.075 * s, akzent)
		"schuerze":
			_kugel(
				_rumpf, Vector3(0.0, -0.04, 0.3) * s, Vector3(0.26, 0.3, 0.05) * s, akzent, false
			)
		"strohhut", "hut_feder", "kappe":
			var hut_farbe := Color("#E5D291") if accessoire == "strohhut" else akzent
			_zylinder(_kopf, Vector3(0.0, 0.22, 0.0) * s, 0.34 * s, 0.03 * s, hut_farbe)
			_zylinder(_kopf, Vector3(0.0, 0.28, 0.0) * s, 0.17 * s, 0.12 * s, hut_farbe)
			if accessoire == "hut_feder":
				var feder := _knoten(_kopf.position + Vector3(0.14, 0.34, 0.0) * s)
				feder.rotation.z = -0.5
				_kugel(feder, Vector3.ZERO, Vector3(0.04, 0.16, 0.02) * s, Color("#D96A6A"), false)
		"nadelkissen":
			_kugel(
				_rumpf,
				Vector3(0.3, 0.1, 0.12) * s,
				Vector3(0.08, 0.08, 0.08) * s,
				Color("#D96A6A"),
				false
			)
		_:
			pass
	# Halstuch-Punkt als Mini-Detail für alle: bindet die Palette zusammen.
	_kugel(_rumpf, Vector3(0.0, 0.22, 0.2) * s, Vector3(0.1, 0.06, 0.08) * s, akzent, false)


## Namensschild überm Kopf (I18n `rnpc.<id>.name`).
func _baue_schild() -> void:
	var label := Label3D.new()
	label.text = I18nService.t("rnpc.%s.name" % str(def.get("id", "")))
	label.position = Vector3(0.0, _schild_hoehe(), 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.004
	label.modulate = Color(0.22, 0.18, 0.16)
	label.outline_size = 14
	label.outline_modulate = Color(1.0, 0.98, 0.93, 0.9)
	add_child(label)


func _schild_hoehe() -> float:
	var modell: Dictionary = def.get("modell") if def.get("modell") is Dictionary else {}
	if str(modell.get("art", "gooby")) == "glb":
		return 1.5 * _groesse() + 0.3
	# Ohrspitzen liegen bei ~1.7*s (Ohr-Knoten 1.4*s + y-Radius 0.3*s) —
	# das Schild schwebt sicher darüber statt in den Ohren zu kleben.
	return 1.75 * _groesse() + 0.3


func _knoten(pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	return node


func _kugel(
	parent: Node3D, pos: Vector3, groesse: Vector3, farbe: Color, schatten: bool
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _mesh_knoten(parent, mesh, pos, groesse * 2.0, farbe, schatten)


func _zylinder(
	parent: Node3D, pos: Vector3, radius: float, hoehe: float, farbe: Color
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 12
	return _mesh_knoten(parent, mesh, pos, Vector3.ONE, farbe, false)


func _torus(parent: Node3D, pos: Vector3, radius: float, farbe: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.7
	mesh.outer_radius = radius
	mesh.rings = 12
	mesh.ring_segments = 8
	var knoten := _mesh_knoten(parent, mesh, pos, Vector3.ONE, farbe, false)
	knoten.rotation.x = deg_to_rad(90.0)
	return knoten


func _mesh_knoten(
	parent: Node3D, mesh: Mesh, pos: Vector3, skala: Vector3, farbe: Color, schatten: bool
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = skala
	mi.material_override = RanchPferd.material(farbe)
	if not schatten:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
