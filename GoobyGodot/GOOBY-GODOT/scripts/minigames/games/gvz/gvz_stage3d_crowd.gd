extends Node3D
## Figuren-MENGE der GvZ-3D-Bühne als MultiMesh-Instanzen (MP-G, erweitert
## für Eval C-technik Befund 2): egal wie viele Untote schlurfen, Türme
## wachen, Mäher warten, Projektile fliegen oder Gläser funkeln — jedes
## Körperteil/Anbauteil ist EIN MultiMesh und damit EIN Draw-Call. Die Bühne
## ruft pro Frame begin() → add_zombie()/add_tower()/add_mower()/
## add_projectile()/add_drop() → commit(). Instanzfarben machen Typ-Tönung,
## Wut-Röte und den weißen Trefferblitz OHNE Materialwechsel möglich.
## Alle Primitiv-Meshes sind bewusst NIEDRIG segmentiert (Chibi-Figuren
## sind ~50 px groß — 4k-Tris-Default-Kugeln sprengten den 250k-Richtwert).

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAP := 48
## Körper/Ohren/Augen teilen sich Zombies, Türme und Mäher-Reiter.
const BODY_CAP := 104
const PAIR_CAP := 208

const INK := Color("#241C18")
const METAL := Color("#9DA6AD")
const CONE_ORANGE := Color("#F2A03C")
const BALLOON_RED := Color("#F28B82")
const ICE := Color("#A8D8F0")
const PAPER := Color("#EDE7DA")
const MOUND_BROWN := Color("#8A6B54")
const CREAM := Color("#F9EDD6")
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const NUTELLA := Color("#5C3A21")
const CARROT := Color("#F08A3C")
const CARROT_LEAF := Color("#7AB35C")
const STAR_GOLD := Color("#FFD34D")
const BERRY_RED := Color("#E0655F")
const MELON_GREEN := Color("#6DB54E")
const LID_CREAM := Color("#EFE6D8")

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

## Körpertönung je Turmtyp (aus der alten Props-Fabrik übernommen).
const TOWER_BODY := {
	"moehrenschuetze": CREAM,
	"doppelmoehre": Color("#F6DFC4"),
	"nutella_sammler": Color("#F2DCAE"),
	"goldi": Color("#F6D98A"),
	"dicker_bert": Color("#EFE0C4"),
	"eis_gooby": Color("#DDEEF8"),
	"magnet_gooby": Color("#E8E2DC"),
	"trampolin_gooby": Color("#D8E6F4"),
	"pust_gooby": Color("#EAF4F2"),
	"sternchen_gooby": Color("#EFE2F4"),
	"melonen_meier": Color("#E4F0CE"),
}

## part-id → {node, mm, cap, used}
var _parts: Dictionary = {}
## part-id → Array[Transform3D] lokale Teil-Transformationen relativ Figur.
var _local: Dictionary = {}
## DAS geteilte Flat-Material aller getönten Parts (Material-Dedup).
var _flat_white: StandardMaterial3D


func _init() -> void:
	_build_parts()


func begin() -> void:
	for id: Variant in _parts:
		(_parts[id] as Dictionary)["used"] = 0


func commit() -> void:
	for id: Variant in _parts:
		var part: Dictionary = _parts[id]
		var used := int(part["used"])
		(part["mm"] as MultiMesh).visible_instance_count = used
		# Leere Parts komplett ausblenden — sonst zahlt jedes ungenutzte
		# MultiMesh trotzdem seinen Draw-Call (z. B. Ballon in Level 1).
		(part["node"] as MultiMeshInstance3D).visible = used > 0


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
	_chibi(figure, tint)
	var dark := tint.darkened(0.16)
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
		_push("glow_ice", figure * _glow_at(Vector3(-0.3, 0.95, 0.1), 0.06), Color.WHITE)


## Einen Turm einreihen (ersetzt die alte Ein-Knoten-pro-Turm-Fabrik —
## Draw-Call-Budget). `base` trägt Zellposition, Blick + Reihen-Skalierung.
func add_tower(type: String, base: Transform3D) -> void:
	match type:
		"schnarch_knolle":
			_knolle(base)
			return
		"boom_beere":
			_berry(base)
			return
	var fig := base
	if type == "dicker_bert":
		fig = base * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.24), Vector3.ZERO)
	_chibi(fig, TOWER_BODY.get(type, CREAM) as Color)
	match type:
		"moehrenschuetze":
			_push("tower_band", fig * _local_one("tower_band"), CARROT_LEAF)
			_cannon(fig, Vector3(0.0, 0.52, 0.26), 1.15)
		"doppelmoehre":
			_push("tower_band", fig * _local_one("tower_band"), BERRY_RED)
			_cannon(fig, Vector3(-0.13, 0.6, 0.22), 1.0)
			_cannon(fig, Vector3(0.14, 0.44, 0.26), 1.0)
		"nutella_sammler":
			_jar(fig, Vector3(0.0, 0.16, 0.34))
			_push("glow_gold", fig * _glow_at(Vector3(0.16, 0.42, 0.4), 0.05), Color.WHITE)
		"goldi":
			_jar(fig, Vector3(0.0, 0.16, 0.34))
			_push("glow_gold", fig * _glow_at(Vector3(-0.3, 0.95, 0.1), 0.05), Color.WHITE)
			_push("glow_gold", fig * _glow_at(Vector3(0.32, 0.75, 0.0), 0.05), Color.WHITE)
		"dicker_bert":
			_push("tower_band", fig * _local_one("tower_band"), WOOD_DARK)
			_push("shield", fig * _local_one("shield"), WOOD_DARK)
		"eis_gooby":
			_push("cap", fig * _local_one("cap"), ICE)
			_push("pom", fig * _local_one("pom"), Color.WHITE)
			_push("glow_ice", fig * _glow_at(Vector3(0.24, 0.62, 0.3), 0.05), Color.WHITE)
		"magnet_gooby":
			_push("tower_band", fig * _local_one("tower_band"), METAL)
			_push("magnet", fig * _local_one("magnet"), BERRY_RED)
		"trampolin_gooby":
			_push("disc", fig * _local_one("disc"), Color("#7FB6D9"))
		"pust_gooby":
			_push("puff", fig * _glow_at(Vector3(0.1, 0.6, 0.44), 0.11), Color.WHITE)
			_push("puff", fig * _glow_at(Vector3(0.26, 0.68, 0.56), 0.08), Color.WHITE)
		"sternchen_gooby":
			_push("stem", fig * _local_one("stem"), INK)
			_push("glow_gold", fig * _glow_at(Vector3(0.0, 1.12, 0.0), 0.09), Color.WHITE)
		"melonen_meier":
			_push("melon", fig * _local_one("melon"), MELON_GREEN)


## Panik-Gooby auf Rollbrett (5 Bahnen × 8 Meshes waren 40 Draw-Calls).
func add_mower(base: Transform3D) -> void:
	_push("board", base * _local_one("board"), WOOD)
	for fz: float in [-0.2, 0.2]:
		var wheel := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.556), Vector3(0.0, 0.07, fz))
		_push("eye", base * wheel, INK)
	var rider := (
		base
		* Transform3D(Basis(Vector3.UP, -0.3).scaled(Vector3.ONE * 0.52), Vector3(0.0, 0.16, 0.0))
	)
	_chibi(rider, CREAM)


## Projektil einreihen: Möhre als Glow-Kegel, alles andere als Glow-Ball.
func add_projectile(kind: String, base: Transform3D) -> void:
	match kind:
		"carrot":
			_push("proj_carrot", base * _local_one("proj_carrot"), Color.WHITE)
		"frost":
			_push("glow_ice", base * _glow_at(Vector3.ZERO, 0.09), Color.WHITE)
		"melon":
			_push("glow_melon", base * _glow_at(Vector3.ZERO, 0.12), Color.WHITE)
		_:
			_push("glow_gold", base * _glow_at(Vector3.ZERO, 0.09), Color.WHITE)


## Nutella-Drop als Mini-Glas: Glas + Deckel + Funkel + Gold-Ring.
func add_drop(base: Transform3D) -> void:
	_push("drop_glass", base * Transform3D.IDENTITY, Color.WHITE)
	_push("lid", base * _local_one("lid"), LID_CREAM)
	_push("glow_gold", base * _glow_at(Vector3(0.12, 0.24, 0.06), 0.05), Color.WHITE)
	_push("drop_ring", base * _local_one("drop_ring"), Color.WHITE)


## ── Figur-Bausteine ──────────────────────────────────────────────────────


## Chibi-Gooby (Körper, Ohren, Augen) — geteilt von Zombies/Türmen/Reitern.
func _chibi(figure: Transform3D, tint: Color) -> void:
	_push("body", figure * _local_one("body"), tint)
	for xf: Transform3D in _local["ear"]:
		_push("ear", figure * xf, tint)
	for xf: Transform3D in _local["eye"]:
		_push("eye", figure * xf, INK)


func _knolle(base: Transform3D) -> void:
	var blob := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.861, 1.0)), Vector3(0.0, 0.3, 0.0))
	_push("body", base * blob, Color("#C9A36B"))
	_push("leaf", base * _local_one("leaf"), CARROT_LEAF)


func _berry(base: Transform3D) -> void:
	_push("glow_berry", base * _glow_at(Vector3(0.0, 0.34, 0.0), 0.32), Color.WHITE)
	var stem := Transform3D(
		Basis(Vector3.BACK, -0.3).scaled(Vector3(1.67, 0.9, 1.67)), Vector3(0.06, 0.72, 0.0)
	)
	_push("stem", base * stem, CARROT_LEAF)


func _cannon(fig: Transform3D, at: Vector3, size: float) -> void:
	var mount := fig * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), at)
	_push("barrel", mount * Transform3D(Basis(Vector3.RIGHT, PI * 0.42), Vector3.ZERO), WOOD)
	var tip := Transform3D(Basis(Vector3.RIGHT, PI * 0.42 + PI * 0.5), Vector3(0.0, 0.05, 0.22))
	_push("tip", mount * tip, CARROT)


func _jar(fig: Transform3D, at: Vector3) -> void:
	var mount := fig * Transform3D(Basis.IDENTITY, at)
	_push("jar", mount, NUTELLA)
	_push("lid", mount * _local_one("lid"), LID_CREAM)


## Glow-/Glas-Ball-Transform: Basis-Kugel r=0.1 → Zielradius per Skalierung.
func _glow_at(at: Vector3, radius: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (radius / 0.1)), at)


## ── Aufbau ────────────────────────────────────────────────────────────────


func _build_parts() -> void:
	_build_zombie_parts()
	_build_tower_parts()
	_build_prop_parts()
	_build_locals()


func _build_zombie_parts() -> void:
	_part("body", _sphere(0.34, 0.72), BODY_CAP, true)
	_part("ear", _capsule(0.085, 0.4), PAIR_CAP, false)
	_part("eye", _sphere(0.045, 0.09, true), PAIR_CAP, false)
	_part("arm", _capsule(0.05, 0.3), CAP * 2, false)
	_part("cone", _cylinder(0.0, 0.17, 0.32, 10), CAP, false)
	_part("bucket", _cylinder(0.19, 0.14, 0.24), CAP, false)
	var paper := BoxMesh.new()
	paper.size = Vector3(0.3, 0.22, 0.02)
	_part("paper", paper, CAP, false)
	_part("vest", _cylinder(0.3, 0.34, 0.18), CAP, false)
	var riot := BoxMesh.new()
	riot.size = Vector3(0.34, 0.5, 0.03)
	var riot_mat := Fx.glass(Color(1.0, 1.0, 1.0, 0.75))
	riot_mat.vertex_color_use_as_albedo = true
	_part("riot", riot, CAP, false, riot_mat)
	_part("band", _cylinder(0.3, 0.3, 0.09), CAP, false)
	_part("mound", _sphere(0.34, 0.68), CAP, false)
	_part("balloon_string", _cylinder(0.012, 0.012, 0.45, 6), CAP, false)
	_part("balloon", _sphere(0.22, 0.44), CAP, false)
	_part("glow_ice", _sphere(0.1, 0.2, true), CAP, false, Fx.glow(ICE, 1.2))


func _build_tower_parts() -> void:
	_part("tower_band", _cylinder(0.3, 0.3, 0.09), CAP, false)
	_part("barrel", _cylinder(0.07, 0.09, 0.3), CAP, false)
	_part("tip", _cylinder(0.0, 0.05, 0.16, 8), CAP, false)
	_part("jar", _cylinder(0.12, 0.12, 0.2), CAP, false)
	_part("lid", _cylinder(0.135, 0.135, 0.05), CAP, false)
	_part("shield", _cylinder(0.24, 0.24, 0.07), CAP, false)
	_part("cap", _sphere(0.26, 0.3), CAP, false)
	_part("pom", _sphere(0.06, 0.12, true), CAP, false)
	var magnet := TorusMesh.new()
	magnet.inner_radius = 0.06
	magnet.outer_radius = 0.13
	magnet.rings = 16
	magnet.ring_segments = 8
	_part("magnet", magnet, CAP, false)
	_part("disc", _cylinder(0.42, 0.46, 0.09), CAP, false)
	_part("puff", _sphere(0.1, 0.2, true), CAP, false, Fx.glass(Color(0.94, 0.98, 1.0, 0.8), true))
	_part("stem", _cylinder(0.015, 0.015, 0.2, 6), CAP, false)
	_part("melon", _sphere(0.2, 0.4), CAP, false)
	_part("leaf", _cylinder(0.0, 0.08, 0.3, 6), CAP, false)
	# Fixfarbige Glow-Materialien (Emission kennt KEINE Instanzfarbe — die
	# Leucht-Farbwelt der alten Einzel-Fabrik bleibt so erhalten).
	_part("glow_gold", _sphere(0.1, 0.2, true), CAP, false, Fx.glow(STAR_GOLD, 1.5))
	_part("glow_berry", _sphere(0.1, 0.2, true), CAP, false, Fx.glow(BERRY_RED, 0.45))


func _build_prop_parts() -> void:
	var board := BoxMesh.new()
	board.size = Vector3(0.34, 0.07, 0.56)
	_part("board", board, 8, true)
	_part("glow_melon", _sphere(0.1, 0.2, true), CAP, false, Fx.glow(MELON_GREEN, 0.4))
	_part("proj_carrot", _cylinder(0.0, 0.06, 0.26, 8), CAP, false, Fx.glow(CARROT, 0.35))
	_part("drop_glass", _cylinder(0.13, 0.11, 0.2), CAP, false, Fx.glow(NUTELLA, 0.35))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.192
	ring.outer_radius = 0.22
	ring.rings = 16
	ring.ring_segments = 6
	_part("drop_ring", ring, CAP, false, Fx.glow(Color(1.0, 0.9, 0.5), 1.1))


## Niedrig segmentierte Grundkörper (Draw-Budget-Pass, Eval C Befund 2):
## Chibi-Teile sind auf dem Bildschirm klein — Default-Kugeln (64×32 ≈ 4k
## Tris) trieben den Primitive-Zähler auf das ~2,5-fache des Richtwerts.
func _sphere(radius: float, height: float, tiny := false) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12 if tiny else 24
	mesh.rings = 6 if tiny else 12
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


func _cylinder(top: float, bottom: float, height: float, segments := 14) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return mesh


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
	_local["tower_band"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 0.0))]
	_local["shield"] = [Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.45, 0.42))]
	_local["cap"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.76, 0.0))]
	_local["pom"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.94, 0.0))]
	_local["magnet"] = [Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.28, 0.68, 0.2))]
	_local["disc"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))]
	_local["stem"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.98, 0.0))]
	_local["melon"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.94, 0.0))]
	_local["leaf"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.72, 0.0))]
	_local["board"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0))]
	_local["lid"] = [Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0))]
	# Möhren-Spitze zeigt nach +x (Flugrichtung), Ring liegt flach am Boden.
	_local["proj_carrot"] = [Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3.ZERO)]
	_local["drop_ring"] = [Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.12, 0.0))]


func _local_one(id: String) -> Transform3D:
	return (_local[id] as Array)[0]


## Ein Part = EIN MultiMesh = EIN Draw-Call. Ohne `mat` gibt es das
## geteilte weiße Flat-Material mit Instanzfarben-Tönung; fixfarbige
## Materialien (Glow/Glass) kommen fertig herein und ignorieren Farben.
func _part(
	id: String, mesh: PrimitiveMesh, cap: int, shadow: bool, mat: StandardMaterial3D = null
) -> void:
	if mat == null:
		if _flat_white == null:
			_flat_white = Fx.flat(Color.WHITE)
			_flat_white.vertex_color_use_as_albedo = true
		mat = _flat_white
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
