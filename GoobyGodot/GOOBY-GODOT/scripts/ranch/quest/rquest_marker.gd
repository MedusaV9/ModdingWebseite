class_name RQuestMarker
extends Node3D
## Welt-Marker der Quest-Systeme (RW-3): schwebender Doppelkegel-Rhombus
## mit Ring, wie man ihn aus AC-artigen Spielen kennt. Zwei Arten:
##   "vergabe" (goldgelb)  — dieser NPC hat eine Quest für dich.
##   "abgabe"  (frischgrün) — eine Quest kann hier abgegeben werden.
## Bewusst billig (2 Kegel + 1 Torus, unshaded über RanchPferd.material);
## `update_marker(dt)` ist der pure Animations-Schritt für Tests.

const FARBEN := {
	"vergabe": Color("#F2B134"),
	"abgabe": Color("#67B99A"),
}
const DREH_PRO_S := 1.6
const BOB_HOEHE := 0.12
const BOB_PRO_S := 2.2

var art := "vergabe"

var _zeit := 0.0
var _rhombus: Node3D
var _basis_y := 0.0


static func neu(marker_art: String) -> RQuestMarker:
	var marker := RQuestMarker.new()
	marker.art = marker_art if FARBEN.has(marker_art) else "vergabe"
	marker.name = "QuestMarker"
	return marker


func _ready() -> void:
	var farbe: Color = FARBEN.get(art, FARBEN["vergabe"])
	_basis_y = position.y
	_rhombus = Node3D.new()
	add_child(_rhombus)
	_kegel(_rhombus, Vector3(0.0, 0.11, 0.0), farbe, false)
	_kegel(_rhombus, Vector3(0.0, -0.11, 0.0), farbe, true)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = RanchPferd.material(farbe.lightened(0.25))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, -0.34, 0.0)
	add_child(ring)


func _process(delta: float) -> void:
	update_marker(delta)


## Pure Animations-Schritt: Drehen + sanftes Auf-und-ab-Schweben.
func update_marker(dt: float) -> void:
	_zeit += dt
	if _rhombus != null:
		_rhombus.rotation.y = fmod(_zeit * DREH_PRO_S, TAU)
	position.y = _basis_y + sin(_zeit * BOB_PRO_S) * BOB_HOEHE


func _kegel(parent: Node3D, pos: Vector3, farbe: Color, kopfueber: bool) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.13
	mesh.height = 0.22
	mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if not kopfueber:
		mi.rotation.z = PI
	mi.material_override = RanchPferd.material(farbe)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
