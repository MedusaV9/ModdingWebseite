extends RefCounted
## Figuren-Fabrik der GvZ-3D-Bühne (FB-4): baut die prozeduralen Chibi-Goobys
## (13 Turmtypen, 10 Zombie-Typen), den Boss-Müllwagen, Projektile, Drops,
## Panik-Mäher und das Haus. Reine statische Fabrik ohne Zustand — die Bühne
## (gvz_stage3d.gd) hängt die Knoten ein und posiert sie pro Frame.
## Farbwelt = GvzArt (die 2D-Vorlage bleibt der Look-Kanon).

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CREAM := Color("#F9EDD6")
const MINT := Color("#C7E2C0")
const MINT_DARK := Color("#A8CCA2")
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const NUTELLA := Color("#5C3A21")
const CARROT := Color("#F08A3C")
const CARROT_LEAF := Color("#7AB35C")
const ICE := Color("#A8D8F0")
const STAR_GOLD := Color("#FFD34D")
const BERRY_RED := Color("#E0655F")
const MELON_GREEN := Color("#6DB54E")
const BALLOON_RED := Color("#F28B82")
const METAL := Color("#9DA6AD")
const CONE_ORANGE := Color("#F2A03C")
const INK := Color("#241C18")


## Chibi-Gooby (Kugelkörper, Ohren, Augen), nominell ~1.0 hoch, Blick +z.
static func chibi(body_color: Color, with_eyes := true) -> Node3D:
	var root := Node3D.new()
	var mat := Fx.flat(body_color)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 0.72
	body_mesh.material = mat
	body.mesh = body_mesh
	body.position.y = 0.36
	body.scale = Vector3(1.0, 1.1, 0.92)
	root.add_child(body)
	var ear_mesh := CapsuleMesh.new()
	ear_mesh.radius = 0.085
	ear_mesh.height = 0.4
	ear_mesh.material = mat
	for side: float in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.15, 0.82, -0.02)
		ear.rotation.z = -side * 0.25
		root.add_child(ear)
	if with_eyes:
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.045
		eye_mesh.height = 0.09
		eye_mesh.material = Fx.flat(INK)
		for side: float in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			eye.position = Vector3(side * 0.12, 0.5, 0.29)
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(eye)
	return root


static func tower(type: String) -> Node3D:
	match type:
		"schnarch_knolle":
			return _knolle()
		"boom_beere":
			return _berry()
	var body := CREAM if type != "goldi" else Color("#F6D98A")
	var root := chibi(body)
	match type:
		"moehrenschuetze":
			root.add_child(_band(CARROT_LEAF))
			root.add_child(_cannon(Vector3(0.0, 0.52, 0.24)))
		"doppelmoehre":
			root.add_child(_band(BERRY_RED))
			root.add_child(_cannon(Vector3(-0.1, 0.58, 0.22)))
			root.add_child(_cannon(Vector3(0.12, 0.44, 0.26)))
		"nutella_sammler":
			root.add_child(_jar(Vector3(0.0, 0.16, 0.34)))
		"goldi":
			root.add_child(_jar(Vector3(0.0, 0.16, 0.34)))
			root.add_child(_sparkle(Vector3(-0.3, 0.95, 0.1)))
			root.add_child(_sparkle(Vector3(0.32, 0.75, 0.0)))
		"dicker_bert":
			root.scale = Vector3.ONE * 1.2
			root.add_child(_shield(Vector3(0.0, 0.45, 0.4)))
		"eis_gooby":
			root.add_child(_beanie())
		"magnet_gooby":
			root.add_child(_magnet(Vector3(0.26, 0.66, 0.18)))
		"trampolin_gooby":
			root.add_child(_tramp_disc())
		"pust_gooby":
			root.add_child(_puff(Vector3(0.1, 0.6, 0.42), 0.1))
			root.add_child(_puff(Vector3(0.24, 0.68, 0.52), 0.07))
		"sternchen_gooby":
			root.add_child(_antenna_star())
		"melonen_meier":
			root.add_child(_melon(Vector3(-0.3, 0.2, 0.22)))
	return root


## Zombie-Figur + benannte Schaltteile: {node, figure, armor?, mound?,
## balloon?, slow} — die Bühne blendet Rüstung/Hügel/Ballon/Frost pro Frame.
static func zombie(type: String) -> Dictionary:
	var root := Node3D.new()
	# Etwas tiefer als GvzArt.MINT: unter 3D-Sonne + Ambient bleicht das
	# 2D-Pastell sonst zu Weiß aus und die Untoten sind nicht mehr lesbar.
	var body := Color("#A9D0A0") if type != "maulwurf" else Color("#8A6B54")
	var figure := chibi(body)
	root.add_child(figure)
	figure.add_child(_zombie_arm(Vector3(-0.1, 0.42, 0.3)))
	figure.add_child(_zombie_arm(Vector3(0.12, 0.36, 0.32)))
	var record := {"node": root, "figure": figure}
	match type:
		"huetchen":
			var cone := _traffic_cone()
			figure.add_child(cone)
			record["armor"] = cone
		"eimer":
			var bucket := _bucket()
			figure.add_child(bucket)
			record["armor"] = bucket
		"sprinter":
			figure.add_child(_band(BERRY_RED))
		"zeitungsopa":
			var paper := _newspaper()
			figure.add_child(paper)
			record["armor"] = paper
		"tuersteher":
			figure.add_child(_vest())
			var shield := _riot_shield()
			figure.add_child(shield)
			record["armor"] = shield
		"maulwurf":
			var mound := _mole_mound()
			root.add_child(mound)
			mound.visible = false
			record["mound"] = mound
		"ballon":
			var balloon := _balloon()
			figure.add_child(balloon)
			record["balloon"] = balloon
	var slow := _sparkle(Vector3(-0.3, 0.95, 0.1))
	(slow.mesh as SphereMesh).material = Fx.glow(ICE, 1.2)
	figure.add_child(slow)
	slow.visible = false
	record["slow"] = slow
	return record


## Boss Knurps: Müllwagen + gekrönter Zombie-König; {node, puffs} — die
## Qualm-Bälle werden mit der Boss-Phase sichtbar.
static func boss() -> Dictionary:
	var root := Node3D.new()
	var truck := MeshInstance3D.new()
	var truck_mesh := BoxMesh.new()
	truck_mesh.size = Vector3(0.7, 0.55, 1.15)
	truck_mesh.material = Fx.flat(Color("#7B8794"))
	truck.mesh = truck_mesh
	truck.position.y = 0.45
	root.add_child(truck)
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(0.62, 0.3, 0.34)
	cab_mesh.material = Fx.flat(Color("#5A6572"))
	cab.mesh = cab_mesh
	cab.position = Vector3(0.0, 0.55, 0.62)
	root.add_child(cab)
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.16
	wheel_mesh.bottom_radius = 0.16
	wheel_mesh.height = 0.1
	wheel_mesh.material = Fx.flat(Color("#3E3A45"))
	for fz: float in [-0.4, 0.4]:
		for side: float in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(side * 0.38, 0.16, fz)
			root.add_child(wheel)
	var king := chibi(MINT)
	king.scale = Vector3.ONE * 0.7
	king.position.y = 0.72
	root.add_child(king)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.16
	crown_mesh.bottom_radius = 0.12
	crown_mesh.height = 0.12
	crown_mesh.material = Fx.glow(STAR_GOLD, 0.7)
	crown.mesh = crown_mesh
	crown.position.y = 0.68
	king.add_child(crown)
	var puffs: Array = []
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.11
	puff_mesh.height = 0.22
	puff_mesh.material = Fx.glass(Color(0.4, 0.38, 0.36, 0.5), true)
	for i in 2:
		var puff := MeshInstance3D.new()
		puff.mesh = puff_mesh
		puff.position = Vector3(0.0, 1.0 + 0.14 * float(i), -0.6 - 0.16 * float(i))
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible = false
		root.add_child(puff)
		puffs.append(puff)
	return {"node": root, "puffs": puffs}


## Projektil-Poolknoten: alle vier Arten als Kinder, Meta "kinds" schaltet um.
static func projectile() -> Node3D:
	var root := Node3D.new()
	var kinds := {}
	var carrot := MeshInstance3D.new()
	var carrot_mesh := CylinderMesh.new()
	carrot_mesh.top_radius = 0.0
	carrot_mesh.bottom_radius = 0.06
	carrot_mesh.height = 0.26
	carrot_mesh.radial_segments = 8
	carrot_mesh.material = Fx.glow(CARROT, 0.35)
	carrot.mesh = carrot_mesh
	# Spitze (top_radius 0) zeigt nach +x — die Flugrichtung der Möhren.
	carrot.rotation.z = -PI * 0.5
	root.add_child(carrot)
	kinds["carrot"] = carrot
	var frost := glow_ball(ICE, 0.09, 1.2)
	root.add_child(frost)
	kinds["frost"] = frost
	var star := glow_ball(STAR_GOLD, 0.09, 1.4)
	root.add_child(star)
	kinds["star"] = star
	var melon := glow_ball(MELON_GREEN, 0.12, 0.4)
	root.add_child(melon)
	kinds["melon"] = melon
	root.set_meta("kinds", kinds)
	root.visible = false
	return root


static func drop() -> Node3D:
	var root := Node3D.new()
	var blob := glow_ball(NUTELLA, 0.16, 0.55)
	root.add_child(blob)
	var ring := Fx.ring(0.2, 0.025, Color(1.0, 0.9, 0.5))
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.02
	root.add_child(ring)
	root.visible = false
	return root


## Panik-Gooby auf Rollbrett (das Rasenmäher-Äquivalent).
static func mower() -> Node3D:
	var root := Node3D.new()
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.34, 0.07, 0.56)
	board_mesh.material = Fx.flat(WOOD)
	board.mesh = board_mesh
	board.position.y = 0.12
	root.add_child(board)
	var wheel_mesh := SphereMesh.new()
	wheel_mesh.radius = 0.07
	wheel_mesh.height = 0.14
	wheel_mesh.material = Fx.flat(INK)
	for fz: float in [-0.2, 0.2]:
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.position = Vector3(0.0, 0.07, fz)
		root.add_child(wheel)
	var rider := chibi(CREAM)
	rider.scale = Vector3.ONE * 0.52
	rider.position.y = 0.16
	rider.rotation.y = -0.3
	root.add_child(rider)
	return root


## Haus mit Veranda-Seite: die verteidigte Basis am linken Feldrand.
static func house() -> Node3D:
	var root := Node3D.new()
	var walls := MeshInstance3D.new()
	var walls_mesh := BoxMesh.new()
	walls_mesh.size = Vector3(2.2, 1.7, 2.0)
	walls_mesh.material = Fx.flat(Color("#F2E3C8"))
	walls.mesh = walls_mesh
	walls.position.y = 0.85
	root.add_child(walls)
	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.6, 1.1, 2.4)
	roof_mesh.material = Fx.flat(Color("#C96F5A"))
	roof.mesh = roof_mesh
	roof.position.y = 2.25
	root.add_child(roof)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.5, 0.95, 0.06)
	door_mesh.material = Fx.flat(WOOD_DARK)
	door.mesh = door_mesh
	door.position = Vector3(0.3, 0.48, 1.01)
	root.add_child(door)
	var window := MeshInstance3D.new()
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(0.55, 0.5, 0.06)
	window_mesh.material = Fx.glow(Color(1.0, 0.93, 0.7), 0.5)
	window.mesh = window_mesh
	window.position = Vector3(-0.55, 1.05, 1.01)
	root.add_child(window)
	return root


static func glow_ball(color: Color, radius: float, energy: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = Fx.glow(color, energy)
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## ── Turm-Sonderformen ────────────────────────────────────────────────────


static func _knolle() -> Node3D:
	var root := Node3D.new()
	var blob := MeshInstance3D.new()
	var blob_mesh := SphereMesh.new()
	blob_mesh.radius = 0.34
	blob_mesh.height = 0.62
	blob_mesh.material = Fx.flat(Color("#C9A36B"))
	blob.mesh = blob_mesh
	blob.position.y = 0.3
	root.add_child(blob)
	var leaf := MeshInstance3D.new()
	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 0.08
	leaf_mesh.height = 0.3
	leaf_mesh.radial_segments = 6
	leaf_mesh.material = Fx.flat(CARROT_LEAF)
	leaf.mesh = leaf_mesh
	leaf.position.y = 0.72
	root.add_child(leaf)
	return root


static func _berry() -> Node3D:
	var root := Node3D.new()
	var berry := glow_ball(BERRY_RED, 0.32, 0.45)
	berry.position.y = 0.34
	root.add_child(berry)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.025
	stem_mesh.bottom_radius = 0.025
	stem_mesh.height = 0.18
	stem_mesh.material = Fx.flat(CARROT_LEAF)
	stem.mesh = stem_mesh
	stem.position = Vector3(0.06, 0.72, 0.0)
	stem.rotation.z = -0.3
	root.add_child(stem)
	return root


## ── Anbau-Teile ──────────────────────────────────────────────────────────


static func _band(color: Color) -> MeshInstance3D:
	var band := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.3
	mesh.height = 0.09
	mesh.material = Fx.flat(color)
	band.mesh = mesh
	band.position.y = 0.62
	return band


static func _cannon(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.07
	barrel_mesh.bottom_radius = 0.09
	barrel_mesh.height = 0.3
	barrel_mesh.material = Fx.flat(WOOD)
	barrel.mesh = barrel_mesh
	barrel.rotation.x = PI * 0.42
	root.add_child(barrel)
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.05
	tip_mesh.height = 0.16
	tip_mesh.radial_segments = 8
	tip_mesh.material = Fx.flat(CARROT)
	tip.mesh = tip_mesh
	tip.rotation.x = PI * 0.42 + PI * 0.5
	tip.position = Vector3(0.0, 0.05, 0.22)
	root.add_child(tip)
	return root


static func _jar(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var glass := MeshInstance3D.new()
	var glass_mesh := CylinderMesh.new()
	glass_mesh.top_radius = 0.12
	glass_mesh.bottom_radius = 0.12
	glass_mesh.height = 0.2
	glass_mesh.material = Fx.flat(NUTELLA)
	glass.mesh = glass_mesh
	root.add_child(glass)
	var lid := MeshInstance3D.new()
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.13
	lid_mesh.bottom_radius = 0.13
	lid_mesh.height = 0.05
	lid_mesh.material = Fx.flat(Color("#EFE6D8"))
	lid.mesh = lid_mesh
	lid.position.y = 0.12
	root.add_child(lid)
	return root


static func _shield(at: Vector3) -> MeshInstance3D:
	var shield := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.24
	mesh.bottom_radius = 0.24
	mesh.height = 0.07
	mesh.material = Fx.flat(WOOD_DARK)
	shield.mesh = mesh
	shield.position = at
	shield.rotation.x = PI * 0.5
	return shield


static func _beanie() -> Node3D:
	var root := Node3D.new()
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.26
	cap_mesh.height = 0.3
	cap_mesh.material = Fx.flat(ICE)
	cap.mesh = cap_mesh
	cap.position.y = 0.76
	root.add_child(cap)
	var pom := MeshInstance3D.new()
	var pom_mesh := SphereMesh.new()
	pom_mesh.radius = 0.06
	pom_mesh.height = 0.12
	pom_mesh.material = Fx.flat(Color.WHITE)
	pom.mesh = pom_mesh
	pom.position.y = 0.94
	root.add_child(pom)
	return root


static func _magnet(at: Vector3) -> MeshInstance3D:
	var magnet := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.06
	mesh.outer_radius = 0.13
	mesh.rings = 16
	mesh.ring_segments = 8
	mesh.material = Fx.flat(BERRY_RED)
	magnet.mesh = mesh
	magnet.position = at
	magnet.rotation.x = PI * 0.5
	return magnet


static func _tramp_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.46
	mesh.height = 0.09
	mesh.material = Fx.flat(Color("#7FB6D9"))
	disc.mesh = mesh
	disc.position.y = 0.05
	return disc


static func _puff(at: Vector3, radius: float) -> MeshInstance3D:
	var puff := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = Fx.glass(Color(0.94, 0.98, 1.0, 0.8), true)
	puff.mesh = mesh
	puff.position = at
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return puff


static func _antenna_star() -> Node3D:
	var root := Node3D.new()
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.015
	stem_mesh.bottom_radius = 0.015
	stem_mesh.height = 0.2
	stem_mesh.material = Fx.flat(INK)
	stem.mesh = stem_mesh
	stem.position.y = 0.98
	root.add_child(stem)
	var star := glow_ball(STAR_GOLD, 0.09, 1.4)
	star.position.y = 1.12
	root.add_child(star)
	return root


static func _melon(at: Vector3) -> MeshInstance3D:
	var melon := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	mesh.material = Fx.flat(MELON_GREEN)
	melon.mesh = mesh
	melon.position = at
	return melon


static func _sparkle(at: Vector3) -> MeshInstance3D:
	var node := glow_ball(STAR_GOLD, 0.05, 1.6)
	node.position = at
	return node


static func _zombie_arm(at: Vector3) -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.3
	mesh.material = Fx.flat(MINT_DARK)
	arm.mesh = mesh
	arm.position = at
	arm.rotation.x = PI * 0.42
	return arm


static func _traffic_cone() -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.17
	mesh.height = 0.32
	mesh.radial_segments = 10
	mesh.material = Fx.flat(CONE_ORANGE)
	cone.mesh = mesh
	cone.position.y = 0.94
	return cone


static func _bucket() -> MeshInstance3D:
	var bucket := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.19
	mesh.bottom_radius = 0.14
	mesh.height = 0.24
	mesh.material = Fx.flat(METAL)
	bucket.mesh = mesh
	bucket.position.y = 0.92
	return bucket


static func _newspaper() -> MeshInstance3D:
	var paper := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.22, 0.02)
	mesh.material = Fx.flat(Color("#EDE7DA"))
	paper.mesh = mesh
	paper.position = Vector3(0.0, 0.42, 0.38)
	paper.rotation.x = -0.3
	return paper


static func _vest() -> MeshInstance3D:
	var vest := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.34
	mesh.height = 0.18
	mesh.material = Fx.flat(Color("#3E3A45"))
	vest.mesh = mesh
	vest.position.y = 0.3
	return vest


static func _riot_shield() -> MeshInstance3D:
	var shield := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.5, 0.03)
	mesh.material = Fx.glass(Color(0.75, 0.85, 0.92, 0.75))
	shield.mesh = mesh
	shield.position = Vector3(0.0, 0.4, 0.46)
	return shield


static func _mole_mound() -> MeshInstance3D:
	var mound := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.34
	mesh.height = 0.68
	mesh.material = Fx.flat(Color("#8A6B54"))
	mound.mesh = mesh
	mound.scale = Vector3(1.0, 0.4, 1.0)
	return mound


static func _balloon() -> Node3D:
	var root := Node3D.new()
	var string := MeshInstance3D.new()
	var string_mesh := CylinderMesh.new()
	string_mesh.top_radius = 0.012
	string_mesh.bottom_radius = 0.012
	string_mesh.height = 0.45
	string_mesh.material = Fx.flat(INK)
	string.mesh = string_mesh
	string.position.y = 1.05
	root.add_child(string)
	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.22
	ball_mesh.height = 0.44
	ball_mesh.material = Fx.flat(BALLOON_RED)
	ball.mesh = ball_mesh
	ball.position.y = 1.42
	root.add_child(ball)
	return root
