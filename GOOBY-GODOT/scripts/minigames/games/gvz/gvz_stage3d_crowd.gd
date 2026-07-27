extends Node3D
## Zombie-MENGE der GvZ-3D-Bühne als MultiMesh-Instanzen (MP-G): egal wie
## viele Untote schlurfen, die ganze Horde kostet ~14 Draw-Calls statt ~9 pro
## Figur. Jedes Körperteil (Körper, Ohren, Augen, Arme) und jedes Anbauteil
## (Hütchen, Eimer, Zeitung, Weste, Schild, Stirnband, Hügel, Ballon, Frost)
## ist EIN MultiMesh; die Bühne ruft pro Frame begin() → add_zombie() →
## commit(). Instanzfarben machen Typ-Tönung, Wut-Röte und den weißen
## Trefferblitz OHNE Materialwechsel möglich.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAP := 48

const INK := Color("#241C18")
const METAL := Color("#9DA6AD")
const CONE_ORANGE := Color("#F2A03C")
const BALLOON_RED := Color("#F28B82")
const ICE := Color("#A8D8F0")
const PAPER := Color("#EDE7DA")
const MOUND_BROWN := Color("#8A6B54")

## Typ-Tönung der Körper: jeder Zombie-Typ ist auf einen Blick unterscheidbar.
const BODY_TINT := {
	"schlurfi": Color("#A9D0A0"),
	"huetchen": Color("#ABD3A6"),
	"eimer": Color("#9DC4A8"),
	"sprinter": Color("#BCDCA0"),
	"zeitungsopa": Color("#C2CFB8"),
	"tuersteher": Color("#8DBB90"),
	"maulwurf": Color("#8A6B54"),
	"ballon": Color("#A9D0A0"),
	"huepfer": Color("#A0D8BC"),
	"brocken": Color("#84AF82"),
}

## part-id → {node, mm, cap, used}
var _parts: Dictionary = {}
## part-id → Array[Transform3D] lokale Teil-Transformationen relativ Figur.
var _local: Dictionary = {}


func _init() -> void:
	_build_parts()


func begin() -> void:
	for id: Variant in _parts:
		(_parts[id] as Dictionary)["used"] = 0


func commit() -> void:
	for id: Variant in _parts:
		var part: Dictionary = _parts[id]
		(part["mm"] as MultiMesh).visible_instance_count = int(part["used"])


## Einen Zombie für DIESEN Frame einreihen. `base` = Wurzel-Transform
## (Position/Blickrichtung/Reihen-Skalierung), `anim`: dig, flying, armor,
## slow, raged, fig_y (Hüpf-/Flughöhe), wobble, lean, flash (0..1).
func add_zombie(type: String, base: Transform3D, anim: Dictionary) -> void:
	var flash := float(anim.get("flash", 0.0))
	if bool(anim.get("dig", false)):
		_push("mound", base * _local_one("mound"), MOUND_BROWN)
		return
	var tint: Color = BODY_TINT.get(type, BODY_TINT["schlurfi"])
	if bool(anim.get("raged", false)):
		tint = tint.lerp(Color(0.95, 0.5, 0.45), 0.45)
	if flash > 0.0:
		tint = tint.lerp(Color.WHITE, minf(1.0, flash * 1.4))
	var fig_basis := Basis.from_euler(
		Vector3(float(anim.get("lean", 0.0)), 0.0, float(anim.get("wobble", 0.0)))
	)
	if flash > 0.0:
		fig_basis = fig_basis.scaled(Vector3.ONE * (1.0 + 0.16 * flash))
	var figure := base * Transform3D(fig_basis, Vector3(0.0, float(anim.get("fig_y", 0.0)), 0.0))
	_push("body", figure * _local_one("body"), tint)
	var dark := tint.darkened(0.16)
	for xf: Transform3D in _local["ear"]:
		_push("ear", figure * xf, tint)
	for xf: Transform3D in _local["eye"]:
		_push("eye", figure * xf, INK)
	for xf: Transform3D in _local["arm"]:
		_push("arm", figure * xf, dark)
	if bool(anim.get("armor", false)):
		match type:
			"huetchen":
				_push("cone", figure * _local_one("cone"), CONE_ORANGE)
			"eimer":
				_push("bucket", figure * _local_one("bucket"), METAL)
			"zeitungsopa":
				_push("paper", figure * _local_one("paper"), PAPER)
			"tuersteher":
				_push("riot", figure * _local_one("riot"), Color(0.75, 0.85, 0.92))
	if type == "tuersteher":
		_push("vest", figure * _local_one("vest"), Color("#3E3A45"))
	if type == "sprinter":
		_push("band", figure * _local_one("band"), Color("#E0655F"))
	if bool(anim.get("flying", false)):
		_push("balloon_string", figure * _local_one("balloon_string"), INK)
		_push("balloon", figure * _local_one("balloon"), BALLOON_RED)
	if bool(anim.get("slow", false)):
		_push("frost", figure * _local_one("frost"), ICE)


## ── Aufbau ────────────────────────────────────────────────────────────────


func _build_parts() -> void:
	var body := SphereMesh.new()
	body.radius = 0.34
	body.height = 0.72
	_part("body", body, CAP, true)
	var ear := CapsuleMesh.new()
	ear.radius = 0.085
	ear.height = 0.4
	_part("ear", ear, CAP * 2, false)
	var eye := SphereMesh.new()
	eye.radius = 0.045
	eye.height = 0.09
	_part("eye", eye, CAP * 2, false)
	var arm := CapsuleMesh.new()
	arm.radius = 0.05
	arm.height = 0.3
	_part("arm", arm, CAP * 2, false)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.17
	cone.height = 0.32
	cone.radial_segments = 10
	_part("cone", cone, CAP, false)
	var bucket := CylinderMesh.new()
	bucket.top_radius = 0.19
	bucket.bottom_radius = 0.14
	bucket.height = 0.24
	_part("bucket", bucket, CAP, false)
	var paper := BoxMesh.new()
	paper.size = Vector3(0.3, 0.22, 0.02)
	_part("paper", paper, CAP, false)
	var vest := CylinderMesh.new()
	vest.top_radius = 0.3
	vest.bottom_radius = 0.34
	vest.height = 0.18
	_part("vest", vest, CAP, false)
	var riot := BoxMesh.new()
	riot.size = Vector3(0.34, 0.5, 0.03)
	_part("riot", riot, CAP, false, true)
	var band := CylinderMesh.new()
	band.top_radius = 0.3
	band.bottom_radius = 0.3
	band.height = 0.09
	_part("band", band, CAP, false)
	var mound := SphereMesh.new()
	mound.radius = 0.34
	mound.height = 0.68
	_part("mound", mound, CAP, false)
	var string := CylinderMesh.new()
	string.top_radius = 0.012
	string.bottom_radius = 0.012
	string.height = 0.45
	_part("balloon_string", string, CAP, false)
	var balloon := SphereMesh.new()
	balloon.radius = 0.22
	balloon.height = 0.44
	_part("balloon", balloon, CAP, false)
	var frost := SphereMesh.new()
	frost.radius = 0.06
	frost.height = 0.12
	_part("frost", frost, CAP, false, false, true)
	_build_locals()


## Lokale Transformationen 1:1 aus der alten Figuren-Fabrik (chibi + Anbauten).
func _build_locals() -> void:
	_local["body"] = [
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.1, 0.92)), Vector3(0.0, 0.36, 0.0))
	]
	var ears: Array = []
	var eyes: Array = []
	for side: float in [-1.0, 1.0]:
		ears.append(
			Transform3D(Basis(Vector3.BACK, -side * 0.25), Vector3(side * 0.15, 0.82, -0.02))
		)
		eyes.append(Transform3D(Basis.IDENTITY, Vector3(side * 0.12, 0.5, 0.29)))
	_local["ear"] = ears
	_local["eye"] = eyes
	var arm_rot := Basis(Vector3.RIGHT, PI * 0.42)
	_local["arm"] = [
		Transform3D(arm_rot, Vector3(-0.1, 0.42, 0.3)),
		Transform3D(arm_rot, Vector3(0.12, 0.36, 0.32)),
	]
	_local["cone"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.94, 0.0))]
	_local["bucket"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.92, 0.0))]
	_local["paper"] = [Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.42, 0.38))]
	_local["vest"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))]
	_local["riot"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.46))]
	_local["band"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 0.0))]
	_local["mound"] = [
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.4, 1.0)), Vector3(0.0, 0.1, 0.0))
	]
	_local["balloon_string"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 0.0))]
	_local["balloon"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 1.42, 0.0))]
	_local["frost"] = [Transform3D(Basis.IDENTITY, Vector3(-0.3, 0.95, 0.1))]


func _local_one(id: String) -> Transform3D:
	return (_local[id] as Array)[0]


func _part(
	id: String, mesh: PrimitiveMesh, cap: int, shadow: bool, glassy := false, glowy := false
) -> void:
	var mat: StandardMaterial3D
	if glassy:
		mat = Fx.glass(Color(1.0, 1.0, 1.0, 0.75))
	elif glowy:
		mat = Fx.glow(Color.WHITE, 1.2)
	else:
		mat = Fx.flat(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	if not shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_parts[id] = {"node": node, "mm": mm, "cap": cap, "used": 0}


func _push(id: String, xform: Transform3D, color: Color) -> void:
	var part: Dictionary = _parts[id]
	var used := int(part["used"])
	if used >= int(part["cap"]):
		return
	var mm := part["mm"] as MultiMesh
	mm.set_instance_transform(used, xform)
	mm.set_instance_color(used, color)
	part["used"] = used + 1
