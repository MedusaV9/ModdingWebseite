extends Node3D
## 3D-Welt des Spielzeug-Rennens (Agent 3D-B): ein Kinderzimmerboden mit
## Holzdielen, rundem Ringelteppich, Bauklotz-Skyline und dem ECHTEN
## Kenney-toy-car-kit-Kurs — dieselbe Bauart wie die Web-Fassung
## (GOOBY/src/minigames/games/toyRacer.js), nur mit MultiMesh statt N Knoten.
##
## Achsen: identisch zur Logik. Der Spline liefert Streckeneinheiten, alles
## wird mit WORLD_SCALE auf Meter gebracht. Es wird NICHTS gespiegelt — die
## Kamera ist frei und schaut den Kurs so an, wie die Logik ihn baut.
##
## Der Kurs ist STATISCH: Dielen, Teppich, Skyline, Streckenteile und Tore
## werden EINMAL in ihre MultiMeshes geschrieben. Nur Item-Kisten und
## abgeworfene Bauklötze bekommen pro Frame frische Posen.

## Nur zum Abtasten des Splines — die Welt hält KEINE zweite Kopie der
## Spline-Mathematik, sie fragt dieselbe Logik wie das Spiel.
const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const KIT := "res://assets/minigames/toy_racer/toy-car-kit/"

## Modellname aus der Logik → GLB (die Logik nennt nur den Web-Dateinamen).
const PIECE_GLB := {
	"track-narrow-straight": KIT + "track-narrow-straight.glb",
	"track-narrow-straight-bump-up": KIT + "track-narrow-straight-bump-up.glb",
	"track-narrow-straight-bump-down": KIT + "track-narrow-straight-bump-down.glb",
	"track-narrow-corner-small": KIT + "track-narrow-corner-small.glb",
	"track-narrow-corner-large": KIT + "track-narrow-corner-large.glb",
	"track-narrow-curve": KIT + "track-narrow-curve.glb",
	"track-narrow-looping": KIT + "track-narrow-looping.glb",
}
const GATE_FINISH := KIT + "gate-finish.glb"
const GATE := KIT + "gate.glb"
const ITEM_BOX := KIT + "item-box.glb"
const CONE := KIT + "item-cone.glb"
const BANANA := KIT + "item-banana.glb"

## Kinderzimmer-Requisiten (MP-F Tiefenpolitur): das Zimmer bekommt Wände,
## Fensterlicht, Möbel-Silhouetten und Teddy-Zuschauer — vorher endete der
## Boden in einer leeren Farbverlaufs-Wand.
const FURN := "res://assets/furniture/"
const BEAR := FURN + "bear.glb"
const BOOKS := FURN + "books.glb"
const PILLOW := FURN + "pillow.glb"
const FLOOR_LAMP := FURN + "lampRoundFloor.glb"
const PLANT := FURN + "pottedPlant.glb"
const BOOKCASE := FURN + "bookcaseOpenLow.glb"
const CHAIR := FURN + "chairCushion.glb"

## Zimmermaße: der Dielenboden ist 190 m — die Wände stehen an seiner Kante.
const ROOM_HALF := 95.0
const WALL_H := 30.0
const WALL_TINT := Color(0.92, 0.83, 0.7)
const SKIRT_TINT := Color(0.62, 0.44, 0.29)
## Fensterlicht: warmes Glühen auf der Nordwand + Lichtfleck auf dem Boden.
const WINDOW_GLOW := Color(1.0, 0.97, 0.88)

## Gitterrichtung (0=+z · 1=−x · 2=−z · 3=+x) → Drehung des Streckenteils.
const DIR_ROT_Y: Array[float] = [0.0, -PI * 0.5, PI, PI * 0.5]
const DIRS_V: Array = [[0.0, 1.0], [-1.0, 0.0], [0.0, -1.0], [1.0, 0.0]]

## Web-Farben: warmes Kinderzimmer, Pastell-Teppich, Bauklotz-Bunt.
const PLANK_A := Color(0.75, 0.54, 0.35)
const PLANK_B := Color(0.81, 0.6, 0.41)
## Web: rgba(120,70,30,0.35) ÜBER der Dielenfarbe — also eine leichte
## Abdunklung, kein schwarzer Strich. Ausgemischt bleibt ein warmes Braun.
## Dezenter als die Web-Zahl: der Nebel reicht hier bis 150 m (damit die
## Bauklotz-Skyline lesbar bleibt), also liegt der Dielenboden bis zur Wand
## offen. Mit dem kräftigeren Fugenton legte sich über die Ferne ein
## Karomuster statt eines Bodens.
const PLANK_SEAM := Color(0.7, 0.5, 0.32)
const RUG_RINGS: Array[Color] = [
	Color(0.56, 0.78, 0.91),
	Color(0.97, 0.82, 0.38),
	Color(0.95, 0.63, 0.71),
	Color(0.61, 0.85, 0.54),
	Color(0.78, 0.61, 0.88),
	Color(0.95, 0.63, 0.71),
	Color(0.56, 0.78, 0.91),
	Color(1.0, 0.96, 0.93),
]
const BLOCK_COLORS: Array[Color] = [
	Color(0.95, 0.47, 0.47),
	Color(0.49, 0.76, 0.37),
	Color(0.44, 0.72, 0.91),
	Color(0.95, 0.76, 0.31),
	Color(0.78, 0.61, 0.88),
	Color(0.95, 0.62, 0.3),
]
## Wie oft die Dielenkachel über die 190-m-Ebene läuft.
##
## Web: 160-m-Ebene, `tex.repeat.set(6, 6)`, 8 Dielen je Kachel → eine Diele ist
## gut DREI Meter breit. Mit den alten 26 Wiederholungen war eine Diele 0,9 m
## schmal: aus Kamerahöhe wurde daraus ein flimmerndes Orange-Rauschen statt
## eines Holzbodens. 7 Wiederholungen auf 190 m treffen die Web-Dielenbreite.
const PLANK_TILE := 7.0

var center := Vector3.ZERO

var box_prop: Node3D
var block_prop: Node3D

var _scale := 2.6
var _pieces: Array[Node3D] = []


## Kurs aufbauen. `track` ist das Logik-Dictionary, `world_scale` = WORLD_SCALE.
func build(track: Dictionary, world_scale: float, seed_value: int) -> void:
	_scale = world_scale
	center = _track_center(track)
	_build_floor(track)
	_build_room()
	_build_furniture()
	_build_rug(track)
	_build_skyline(track, seed_value)
	_build_track(track)
	_build_gates(track)
	_build_clutter(track)
	_build_spectators(track)
	box_prop = _prop(Models.parts(ITEM_BOX, 0.62, false), 12)
	block_prop = _prop(_block_parts(), 8, true)


func layer_count() -> int:
	var total := 2 + RUG_RINGS.size()
	for prop in _pieces:
		total += prop.call("layer_count")
	total += box_prop.call("layer_count") + block_prop.call("layer_count")
	return total


## Weltpunkt einer Spline-Stützstelle mit seitlichem Versatz, in Metern.
func world_at(sample: Dictionary, lat: float) -> Vector3:
	var p: Array = sample["p"]
	var r: Array = sample["right"]
	return (
		Vector3(
			float(p[0]) + float(r[0]) * lat,
			float(p[1]) + float(r[1]) * lat,
			float(p[2]) + float(r[2]) * lat
		)
		* _scale
	)


# ── Boden ─────────────────────────────────────────────────────────────────


## Holzdielen: eine kleine Bild-Textur (Rechtecke, keine Pixelschleife) auf
## einer großen Ebene — genau wie die Web-Canvas-Textur, nur billiger.
func _build_floor(_track: Dictionary) -> void:
	var image := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for row in 8:
		image.fill_rect(Rect2i(0, row * 16, 128, 15), PLANK_A if row % 2 == 0 else PLANK_B)
		image.fill_rect(Rect2i((row * 48 + 20) % 128, row * 16, 3, 15), PLANK_SEAM)
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	var mat := Fx.flat(Color.WHITE, 0.9)
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(PLANK_TILE, PLANK_TILE, 1.0)
	# NEAREST ließ die Dielen in der Ferne hart aliasen; anisotrop gefiltert
	# legt sich der Boden flach in die Tiefe, statt zu flimmern.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := PlaneMesh.new()
	plane.size = Vector2(190.0, 190.0)
	plane.material = mat
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = plane
	floor_mi.position = Vector3(center.x, -0.09, center.z)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)


## Zimmerwände mit Sockelleiste — der Boden endet an einer WAND, nicht in
## einem Farbverlauf. Dazu ein „Fenster" (warmes Leuchtquad) auf der Nordwand
## und sein Lichtfleck auf den Dielen: sofortiges Kinderzimmer-Gefühl,
## vier + vier Instanzen in zwei MultiMeshes plus zwei Quads.
func _build_room() -> void:
	var wall := BoxMesh.new()
	wall.size = Vector3(ROOM_HALF * 2.0, WALL_H, 1.0)
	wall.material = Fx.flat(WALL_TINT, 0.96)
	var wall_prop := _prop([{"mesh": wall, "xform": Transform3D.IDENTITY}], 4)
	wall_prop.call("set_shadows", false)
	var skirt := BoxMesh.new()
	skirt.size = Vector3(ROOM_HALF * 2.0, 1.2, 1.16)
	skirt.material = Fx.flat(SKIRT_TINT, 0.85)
	var skirt_prop := _prop([{"mesh": skirt, "xform": Transform3D.IDENTITY}], 4)
	skirt_prop.call("set_shadows", false)
	wall_prop.call("begin")
	skirt_prop.call("begin")
	for k in 4:
		var yaw := float(k) * PI * 0.5
		var out := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -ROOM_HALF)
		var basis := Basis(Vector3.UP, yaw)
		var base := Vector3(center.x, 0.0, center.z) + out
		wall_prop.call("push", Transform3D(basis, base + Vector3(0.0, WALL_H * 0.5 - 0.1, 0.0)))
		skirt_prop.call("push", Transform3D(basis, base + Vector3(0.0, 0.5, 0.0)))
	wall_prop.call("flush")
	skirt_prop.call("flush")
	_build_window()


## Fenster auf der Nordwand (−z) + Lichtfleck auf dem Boden davor.
func _build_window() -> void:
	var pane := QuadMesh.new()
	pane.size = Vector2(24.0, 17.0)
	var glow := Fx.glow(WINDOW_GLOW, 0.9)
	glow.disable_fog = true
	pane.material = glow
	var frame := BoxMesh.new()
	frame.size = Vector3(26.0, 19.0, 0.8)
	frame.material = Fx.flat(Color(0.99, 0.97, 0.93), 0.9)
	var win := MeshInstance3D.new()
	win.mesh = frame
	win.position = Vector3(center.x - 18.0, 15.0, center.z - ROOM_HALF + 0.4)
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(win)
	var pane_mi := MeshInstance3D.new()
	pane_mi.mesh = pane
	pane_mi.position = Vector3(0.0, 0.0, 0.55)
	pane_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(pane_mi)
	# Kreuzsprosse, damit das Leuchtquad als Fenster liest.
	for bar_size: Vector3 in [Vector3(1.1, 19.0, 0.9), Vector3(26.0, 1.1, 0.9)]:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = bar_size
		mesh.material = frame.material
		bar.mesh = mesh
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.add_child(bar)
	var patch := QuadMesh.new()
	patch.size = Vector2(30.0, 20.0)
	var patch_mat := Fx.glass(Color(1.0, 0.97, 0.86, 0.13), true)
	patch_mat.disable_receive_shadows = true
	patch.material = patch_mat
	var patch_mi := MeshInstance3D.new()
	patch_mi.mesh = patch
	patch_mi.rotation_degrees.x = -90.0
	patch_mi.position = Vector3(center.x - 18.0, -0.03, center.z - ROOM_HALF + 16.0)
	patch_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch_mi)


## Riesige Möbel-Silhouetten an den Wänden — im Spielzeugmaßstab sind Regal,
## Stuhl, Stehlampe und Topfpflanze Zimmer-hohe Landmarken, an denen man
## beim Runden fahren die Himmelsrichtung abliest.
func _build_furniture() -> void:
	var cx := center.x
	var cz := center.z
	_furn(BOOKCASE, 34.0, Vector3(cx + ROOM_HALF - 10.0, -0.09, cz - 22.0), -PI * 0.5)
	_furn(CHAIR, 22.0, Vector3(cx - ROOM_HALF + 16.0, -0.09, cz + 26.0), PI * 0.35)
	_furn(FLOOR_LAMP, 12.0, Vector3(cx - 40.0, -0.09, cz - ROOM_HALF + 9.0), 0.0)
	_furn(PLANT, 14.0, Vector3(cx + 38.0, -0.09, cz - ROOM_HALF + 10.0), 0.6)
	_furn(BOOKS, 16.0, Vector3(cx + ROOM_HALF - 14.0, -0.09, cz + 34.0), 0.9)
	_furn(PILLOW, 20.0, Vector3(cx - 30.0, -0.09, cz + ROOM_HALF - 12.0), 0.3)


func _furn(path: String, width: float, pos: Vector3, yaw: float) -> void:
	var node := Models.node(path, width)
	node.position = pos
	node.rotation.y = yaw
	add_child(node)


## Teddy-Zuschauer nah an der Strecke: drei Bären sitzen am Teppichrand und
## „schauen zu" — plus ein Bücherstapel-Podest. Nähe schlägt Menge.
func _build_spectators(track: Dictionary) -> void:
	var radius := float(track["lapLen"]) * _scale * 0.235
	var poses: Array = [
		{"ang": 0.65, "w": 4.6},
		{"ang": 2.7, "w": 3.8},
		{"ang": 4.5, "w": 5.2},
	]
	for spec: Dictionary in poses:
		var ang := float(spec["ang"])
		var pos := Vector3(
			center.x + cos(ang) * (radius + 4.0), -0.09, center.z + sin(ang) * (radius + 4.0)
		)
		var bear := Models.node(BEAR, float(spec["w"]))
		bear.position = pos
		# Blick zur Ringmitte — Zuschauer schauen aufs Rennen.
		bear.rotation.y = atan2(center.x - pos.x, center.z - pos.z)
		add_child(bear)
	var books := Models.node(BOOKS, 6.0)
	var bang := 1.7
	books.position = Vector3(
		center.x + cos(bang) * (radius + 5.0), -0.09, center.z + sin(bang) * (radius + 5.0)
	)
	books.rotation.y = bang
	add_child(books)


## Ringelteppich: konzentrische Scheiben statt einer 512er-Textur — das sind
## acht Draw-Calls, aber pixelscharfe Ringe und kein Textur-Aufbau zur Laufzeit.
func _build_rug(track: Dictionary) -> void:
	var radius := float(track["lapLen"]) * _scale * 0.21
	for i in RUG_RINGS.size():
		var disc := CylinderMesh.new()
		var r := radius * (1.0 - float(i) / float(RUG_RINGS.size()))
		disc.top_radius = maxf(0.4, r)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 40
		disc.rings = 0
		disc.material = Fx.flat(RUG_RINGS[i], 0.95)
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		# ACHTUNG: Die Kenney-Fahrbahn liegt bei y = 0. Der Teppich muss KOMPLETT
		# darunter bleiben, sonst deckt die innerste Scheibe die ganze Strecke zu
		# (genau dieser Fehler ließ den Kurs zuerst verschwinden).
		mi.position = Vector3(center.x, -0.05 + float(i) * 0.004, center.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Bauklotz-Skyline rund um den Teppich — EIN MultiMesh mit Instanzfarben.
func _build_skyline(track: Dictionary, seed_value: int) -> void:
	var rng := GoobyRng.new((seed_value ^ 0x5EED10AD) & 0xFFFFFFFF)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var mat := Fx.flat(Color.WHITE, 0.65)
	mat.vertex_color_use_as_albedo = true
	cube.material = mat
	var prop := _prop([{"mesh": cube, "xform": Transform3D.IDENTITY}], 48, true)
	var radius := float(track["lapLen"]) * _scale * 0.24
	prop.call("begin")
	var idx := 0
	for i in 30:
		var ang := (float(i) / 30.0) * TAU + rng.next() * 0.15
		var r := radius + 2.5 + rng.next() * 7.0
		var sz := 1.2 + rng.next() * 2.2
		var height := sz * (0.7 + rng.next() * 1.4)
		var basis := Basis(Vector3.UP, rng.next() * PI).scaled(Vector3(sz, height, sz))
		var pos := Vector3(center.x + cos(ang) * r, height * 0.5, center.z + sin(ang) * r)
		prop.call("push", Transform3D(basis, pos), BLOCK_COLORS[idx % BLOCK_COLORS.size()])
		idx += 1
	for tower in 4:
		var ang := (float(tower) / 4.0) * TAU + 0.5
		var r := radius + 5.0 + rng.next() * 4.0
		var bx := center.x + cos(ang) * r
		var bz := center.z + sin(ang) * r
		for level in 4:
			var sz := 2.4 - float(level) * 0.35
			var basis := Basis(Vector3.UP, float(level) * 0.4).scaled(Vector3(sz, 2.0, sz))
			var pos := Vector3(bx, float(level) * 2.0 + 1.0, bz)
			prop.call(
				"push", Transform3D(basis, pos), BLOCK_COLORS[(idx * 2) % BLOCK_COLORS.size()]
			)
			idx += 1
	prop.call("flush")


# ── Kurs ──────────────────────────────────────────────────────────────────


## Streckenteile: pro GLB-Sorte EIN MultiMesh, einmal befüllt. Die Teile
## bewegen sich nie — der Kurs ist ein geschlossener Ring, die Kamera fährt.
func _build_track(track: Dictionary) -> void:
	var by_model: Dictionary = {}
	for piece: Dictionary in track["pieces"]:
		var key := str(piece["model"])
		if not by_model.has(key):
			by_model[key] = []
		(by_model[key] as Array).append(piece)
	for key: String in by_model:
		var path: String = PIECE_GLB.get(key, "")
		if path.is_empty():
			continue
		var list: Array = by_model[key]
		var prop := _prop(Models.parts(path, 0.0, false), maxi(2, list.size()))
		prop.call("begin")
		for piece: Dictionary in list:
			prop.call("push", _piece_pose(piece))
		prop.call("flush")


## Pose eines Streckenteils (Web: Ursprungsversatz entlang der Fahrtrichtung,
## Höhe +0,7 Einheiten, weil die Kenney-Fahrbahn über dem Modellursprung liegt).
func _piece_pose(piece: Dictionary) -> Transform3D:
	var dir := int(piece["dir"])
	var d: Array = DIRS_V[dir]
	var off := float(piece.get("originOffset", 0.0))
	var basis := Basis(Vector3.UP, DIR_ROT_Y[dir]).scaled(Vector3.ONE * _scale)
	var pos := Vector3(
		(float(piece["x"]) + float(d[0]) * off) * _scale,
		(float(piece["y"]) + 0.7) * _scale * 0.999,
		(float(piece["z"]) + float(d[1]) * off) * _scale
	)
	return Transform3D(basis, pos)


func _build_gates(track: Dictionary) -> void:
	_place_single(GATE_FINISH, track, 0.0, 0.82, true)
	_place_single(GATE, track, float(track["lapLen"]) * 0.55, 0.82, true)


## Spielzeug-Kram am Streckenrand (Hütchen, Banane) — reine Deko wie im Web.
func _build_clutter(track: Dictionary) -> void:
	var lap := float(track["lapLen"])
	_place_lat(CONE, track, lap * 0.3, 0.95)
	_place_lat(CONE, track, lap * 0.32, -0.95)
	_place_lat(BANANA, track, lap * 0.7, 1.05)


func _place_single(path: String, track: Dictionary, s: float, rel: float, aim: bool) -> void:
	var sample: Dictionary = Logic.point_at(track, s)
	var node := Models.node(path, 0.0, false)
	node.scale = Vector3.ONE * (_scale * rel)
	var p: Array = sample["p"]
	node.position = Vector3(float(p[0]), float(p[1]), float(p[2])) * _scale
	if aim:
		var t: Array = sample["t"]
		node.rotation.y = atan2(float(t[0]), float(t[2]))
	add_child(node)


func _place_lat(path: String, track: Dictionary, s: float, lat: float) -> void:
	var sample: Dictionary = Logic.point_at(track, s)
	var node := Models.node(path, 0.0, false)
	node.scale = Vector3.ONE * (_scale * 0.7)
	node.position = world_at(sample, lat)
	add_child(node)


# ── Bewegliche Requisiten ─────────────────────────────────────────────────


## Abgeworfener Bauklotz: bunter Würfel mit Noppe.
func _block_parts() -> Array:
	var cube := BoxMesh.new()
	cube.size = Vector3(0.36, 0.36, 0.36) * _scale
	cube.material = Fx.flat(Color(0.87, 0.36, 0.33), 0.6)
	var stud := CylinderMesh.new()
	stud.top_radius = 0.1 * _scale
	stud.bottom_radius = stud.top_radius
	stud.height = 0.09 * _scale
	stud.radial_segments = 10
	stud.rings = 0
	stud.material = Fx.flat(Color(0.95, 0.55, 0.5), 0.6)
	return [
		{"mesh": cube, "xform": Transform3D.IDENTITY},
		{
			"mesh": stud,
			"xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22 * _scale, 0.0)),
		},
	]


func _prop(parts: Array, cap: int, colored := false) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, colored)
	_pieces.append(node)
	return node


func _track_center(track: Dictionary) -> Vector3:
	var samples: Array = track["samples"]
	var sum := Vector3.ZERO
	for smp: Dictionary in samples:
		var p: Array = smp["p"]
		sum += Vector3(float(p[0]), 0.0, float(p[2]))
	return sum / maxf(1.0, float(samples.size())) * _scale
