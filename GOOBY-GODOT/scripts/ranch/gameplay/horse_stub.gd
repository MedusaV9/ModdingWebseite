class_name RanchHorseStub
extends Node3D
## Pferde-ATTRAPPE (RANCH-2): prozedurales Low-Poly-Pferd aus Primitiven,
## bis RANCH-1s echtes Modell landet. Die API hier ist der VERTRAG
## (s. /tmp/gooby-godot/handoffs/RANCH2-needs.md §2): set_farbe/set_gait/
## tick/head_pivot/equip/body_height — Reiten, Pflege und beide Minispiele
## sprechen NUR diese Methoden. ~13 Draw-Calls; Blickrichtung ist -z
## (Godot-Vorwärts), Boden bei y=0.

## Fellfarben-Ids → [Fell, Mähne/Schweif].
const FELL := {
	"braun": [Color("#8B5A33"), Color("#4F3018")],
	"schwarz": [Color("#3A3A3C"), Color("#232324")],
	"weiss": [Color("#E8E4DA"), Color("#C9C2B4")],
	"fuchs": [Color("#B4552D"), Color("#7A3418")],
	"palomino": [Color("#D6A65A"), Color("#F2E8D5")],
	"schecke": [Color("#9C6B3F"), Color("#F0EAE0")],
}

## Rumpf-Oberkante (Sitzhöhe) in Metern.
const RUECKEN_Y := 1.06
const BEIN_LAENGE := 0.72
## Bein-Schwungwinkel (rad) je Gangart.
const BEIN_AMP := {"stand": 0.0, "schritt": 0.32, "trab": 0.5, "galopp": 0.78}

var gait := "stand"

var _fell_mat := StandardMaterial3D.new()
var _dunkel_mat := StandardMaterial3D.new()
var _phase := 0.0
var _kopf: Node3D
var _beine: Array[Node3D] = []
var _gear: Dictionary = {}


func _ready() -> void:
	_fell_mat.roughness = 0.9
	_dunkel_mat.roughness = 0.9
	_build_koerper()
	set_farbe("braun")


## Fellfarbe setzen (Ids: RanchPlaySlices.FELLFARBEN).
func set_farbe(id: String) -> void:
	var paar: Array = FELL.get(id, FELL["braun"])
	_fell_mat.albedo_color = paar[0]
	_dunkel_mat.albedo_color = paar[1]


## Gangart für die Beinanimation ("stand"|"schritt"|"trab"|"galopp").
func set_gait(id: String) -> void:
	if RanchRideFeel.TEMPO.has(id):
		gait = id


## Jeden Frame: Schrittphase/Beine/Kopf treiben. `tempo` nur fürs Feintuning
## der Phase (0 = steht); der Aufrufer pausiert einfach, indem er nicht tickt.
func tick(delta: float, tempo: float = -1.0) -> void:
	var hz := RanchRideFeel.schritt_hz(gait)
	if tempo >= 0.0 and gait != "stand":
		var ziel := RanchRideFeel.zieltempo(gait)
		if ziel > 0.01:
			hz *= clampf(tempo / ziel, 0.35, 1.25)
	_phase = fposmod(_phase + hz * delta, 1.0)
	_animiere(_phase)


## Kopf-Knoten fürs Kopfnicken (ride_controller addiert den Nick-Versatz).
func head_pivot() -> Node3D:
	return _kopf


## Ausrüstung anlegen/abnehmen (farbe null = abnehmen).
func equip(slot: String, farbe: Variant) -> void:
	if _gear.has(slot):
		(_gear[slot] as Node3D).queue_free()
		_gear.erase(slot)
	if not (farbe is String):
		return
	var aufsatz := RanchGearMeshes.build(slot, farbe)
	if aufsatz == null:
		return
	match slot:
		"sattel":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.06, 0.05)
		"decke":
			aufsatz.position = Vector3(0.0, RUECKEN_Y + 0.02, 0.05)
		"halfter":
			# Das Nasenband ist auf die RanchPferd-Schnauze (+z) dimensioniert;
			# die Attrappe blickt -z und hat ein viel kleineres Maul.
			aufsatz.position = Vector3(0.0, 0.0, -0.28)
			aufsatz.rotation.y = PI
			aufsatz.scale = Vector3.ONE * 0.45
	if slot == "halfter" and _kopf != null:
		_kopf.add_child(aufsatz)
	else:
		add_child(aufsatz)
	_gear[slot] = aufsatz


## Sitzhöhe (Sattel-Oberkante) für den Gooby-Sitz.
func body_height() -> float:
	return RUECKEN_Y + 0.12


## Aktuelle Schrittphase (0..1) — Reit-Controller synct Kopfnicken/Hufe.
func phase() -> float:
	return _phase


func _build_koerper() -> void:
	var rumpf := _teil(_kapsel(0.34, 1.5), _fell_mat, Vector3(0.0, 0.82, 0.0))
	rumpf.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var hals := _teil(_box(0.24, 0.52, 0.3), _fell_mat, Vector3(0.0, 1.12, -0.62))
	hals.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	_kopf = Node3D.new()
	_kopf.position = Vector3(0.0, 1.44, -0.86)
	add_child(_kopf)
	var schaedel := _teil(_box(0.22, 0.24, 0.34), _fell_mat, Vector3(0.0, 0.0, -0.04))
	remove_child(schaedel)
	_kopf.add_child(schaedel)
	var maul := _teil(_box(0.16, 0.16, 0.22), _fell_mat, Vector3(0.0, -0.04, -0.28))
	remove_child(maul)
	_kopf.add_child(maul)
	for seite: float in [-1.0, 1.0]:
		var ohr := _teil(_box(0.06, 0.16, 0.05), _dunkel_mat, Vector3(0.08 * seite, 0.18, 0.06))
		remove_child(ohr)
		_kopf.add_child(ohr)
	var maehne := _teil(_box(0.08, 0.5, 0.14), _dunkel_mat, Vector3(0.0, 1.22, -0.5))
	maehne.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	var schweif := _teil(_box(0.1, 0.5, 0.12), _dunkel_mat, Vector3(0.0, 0.92, 0.82))
	schweif.rotation_degrees = Vector3(30.0, 0.0, 0.0)
	for i in 4:
		var vorn := i < 2
		var links := i % 2 == 0
		var pivot := Node3D.new()
		pivot.position = Vector3(0.2 * (-1.0 if links else 1.0), 0.78, -0.52 if vorn else 0.52)
		add_child(pivot)
		var bein := _teil(
			_box(0.11, BEIN_LAENGE, 0.12), _dunkel_mat, Vector3(0.0, -BEIN_LAENGE * 0.5, 0.0)
		)
		remove_child(bein)
		pivot.add_child(bein)
		_beine.append(pivot)


## Diagonale Beinpaare schwingen; Galopp springt in Sprung-Paaren.
func _animiere(phase01: float) -> void:
	var amp := float(BEIN_AMP.get(gait, 0.0))
	for i in _beine.size():
		var vorn := i < 2
		var links := i % 2 == 0
		var offset := 0.0
		if gait == "galopp":
			offset = 0.0 if vorn else 0.5
		else:
			offset = 0.0 if vorn == links else 0.5
		_beine[i].rotation.x = sin((phase01 + offset) * TAU) * amp
	if _kopf != null:
		_kopf.rotation.x = sin(phase01 * TAU) * (0.06 if gait != "stand" else 0.02)


func _teil(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _box(w: float, h: float, d: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	return mesh


func _kapsel(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh
