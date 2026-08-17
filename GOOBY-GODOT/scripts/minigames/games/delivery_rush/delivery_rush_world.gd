extends Node3D
## 3D-Stadt der Liefer-Hetze (Agent 3D-B): das 9×9-Kachelraster der Logik als
## echte Kenney-Stadt — Ring-und-Kreuz-Straßen, Häuserblocks, Bäume, sechs
## Landmarken und der Verkehr. Vorbild ist die Web-Fassung
## (GOOBY/src/minigames/games/deliveryRush.js), die dieselbe Stadt in three.js
## fährt.
##
## Achsen: die Logik rechnet in (x, z) Weltmetern, x nach Osten, z nach Süden.
## Godot nimmt genau diese Zahlen — Logik-z ist Godot-z, es wird NICHTS
## gespiegelt. Die Kamera hängt hinter dem Wagen und schaut in Fahrtrichtung.
##
## Die Stadt ist STATISCH und wird einmal in MultiMeshes gegossen (Straßen,
## Häuser, Bäume). Nur Verkehr und Abwurfring bekommen pro Frame neue Posen.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Logic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")

const CITY := "res://assets/city/gebaeude/"
## Häuserparade. Die Web-Fassung zieht ihre Blocks aus demselben Kenney-Kit;
## der Wolkenkratzer ist bewusst dabei, sonst bleibt die Skyline zweistöckig
## und die Straße wird zur Landstraße statt zur Häuserschlucht.
const HOUSES: Array[String] = [
	CITY + "building-a.glb",
	CITY + "building-c.glb",
	CITY + "building-e.glb",
	CITY + "building-g.glb",
	CITY + "building-skyscraper-a.glb",
	CITY + "building-f.glb",
]
const TREE := "res://assets/city/natur/tree_default.glb"
const BUSH := "res://assets/city/natur/plant_bush.glb"
const TRAFFIC_CARS: Array[String] = [
	"res://assets/city/autos/sedan.glb",
	"res://assets/city/autos/taxi.glb",
	"res://assets/city/autos/suv.glb",
]

## Farben der Stadtfläche (Web: helle Wiese, dunkler Asphalt, sandiger Gehweg).
## Abendband: das grelle Mittagsgrün stach neben dem Pfirsichhimmel heraus.
## Asphalt aufgehellt (0,33 → 0,42): unter der Abendsonne fielen die Straßen
## zu FAST-SCHWARZEN Flächen zusammen und schluckten Striche und Route.
const GRASS := Color(0.5, 0.66, 0.42)
const ASPHALT := Color(0.42, 0.43, 0.48)
const WALK := Color(0.79, 0.71, 0.58)
const DASH := Color(0.95, 0.92, 0.7)
## Laternen (Web: kaykit-city/streetlight entlang der Ringstraße).
const LAMP_POST := Color(0.3, 0.31, 0.34)
const LAMP_HEAD := Color(1.0, 0.89, 0.62)

## Fahrbahnbreite innerhalb einer 20-m-Kachel (Rest ist Gehweg/Wiese).
const ROAD_W := 13.0
const WALK_W := 17.0
## Landmarken-Signalfarben (Reihenfolge = Logic.LANDMARKS).
const LANDMARK_TINTS: Array[Color] = [
	Color(0.98, 0.62, 0.32),
	Color(0.56, 0.83, 0.95),
	Color(0.6, 0.86, 0.72),
	Color(0.78, 0.66, 0.95),
	Color(0.68, 0.88, 0.5),
	Color(0.98, 0.78, 0.4),
]

## W19: Stelen-Versatz (m) neben die Parkbucht. Die Shop-Stele stand EXAKT auf
## dem Van-Spawn (46,5 | −20) — jede Runde begann mit einem orangen Mast quer
## durch die Verfolgerkamera (Playtest-Beleg 022_erste_lieferung_beat.png).
## Der Abwurfring bleibt an der Bucht (Logik unberührt), nur der Beacon rückt
## an den Blockrand daneben.
const STELE_OFFSETS := {"shop": Vector2(0.0, -5.0)}

var traffic_prop: Node3D
## Boden-Punkte (x, z) aller Landmarken-Stelen — für den W19-Kamera-Wächter.
var stele_punkte: Array[Vector2] = []

var _props: Array[Node3D] = []


func build(colliders: Array, rng: GoobyRng) -> void:
	_build_ground()
	_build_roads()
	_build_houses(colliders, rng)
	_build_greens(rng)
	_build_lamps()
	_build_skyline(rng)
	_build_landmarks()
	traffic_prop = _prop(Models.parts(TRAFFIC_CARS[0], 2.4), 16, true)


func layer_count() -> int:
	var total := 1
	for prop in _props:
		total += prop.call("layer_count")
	return total


func _build_ground() -> void:
	var span := Logic.TILE_M * float(Logic.GRID) + 120.0
	var grass := Fx.ground(Vector2(span, span), GRASS, -0.08)
	add_child(grass)


## Straßen: Asphaltplatte + Gehwegplatte je Kachel, dazu Mittelstriche.
## Alles in drei MultiMeshes — die 41 Straßenkacheln kosten 3 Draw-Calls.
func _build_roads() -> void:
	var walk_prop := _prop([_slab(WALK_W, WALK, 0.02)], 64)
	# Bauplatz-Pflaster: die Web-Fassung legt auf JEDE Blockkachel eine volle
	# `tile-low`-Platte. Ohne die stand unsere Stadt auf einer Wiese — zwischen
	# Bordstein und Hauswand lagen 6 m Gras und die Straße las sich als
	# Landstraße statt als Häuserschlucht.
	var block_prop := _prop([_slab(Logic.TILE_M, WALK.darkened(0.06), 0.015)], 32)
	# Asphalt-OBERKANTE exakt auf y = 0 (Platte ist 0,05 dick, Mitte −0,025):
	# Van, Verkehr, Routenpfeile und Abgabering posieren alle auf y = 0 —
	# vorher lag der Deckel bei 0,055 und jedes Fahrzeug steckte 5,5 cm im
	# Asphalt (FB-4-Bugfix „Autos schweben/versinken").
	var road_prop := _prop([_slab(ROAD_W, ASPHALT, -0.025)], 128)
	var dash_prop := _prop([_dash_part()], 200)
	for prop in [walk_prop, block_prop, road_prop, dash_prop]:
		prop.call("begin")
	for r in Logic.GRID:
		for c in Logic.GRID:
			var w := Logic.tile_to_world(r, c)
			var at := Vector3(w.x, 0.0, w.y)
			if not Logic.is_road(r, c):
				if _inside_block(r, c):
					block_prop.call("push", Transform3D(Basis.IDENTITY, at))
				continue
			walk_prop.call("push", Transform3D(Basis.IDENTITY, at))
			_push_asphalt(road_prop, r, c, at)
			_push_dashes(dash_prop, r, c, at)
	for prop in [walk_prop, block_prop, road_prop, dash_prop]:
		prop.call("flush")


## Asphalt je Kachel auf VOLLE Kachellänge ziehen — in Fahrtrichtung, nicht
## quer. Die quadratische Platte (ROAD_W × ROAD_W) mittig auf der Kachel ließ
## zwischen den Kacheln Lücken: die Stadt sah aus wie ein Raster einzelner
## schwarzer Flecken statt wie ein Straßennetz.
func _push_asphalt(prop: Node3D, r: int, c: int, at: Vector3) -> void:
	var stretch := Logic.TILE_M / ROAD_W
	var horizontal := Logic.is_road(r, c + 1) or Logic.is_road(r, c - 1)
	var vertical := Logic.is_road(r - 1, c) or Logic.is_road(r + 1, c)
	if not horizontal and not vertical:
		prop.call("push", Transform3D(Basis.IDENTITY, at))
		return
	if horizontal:
		var wide := Basis.IDENTITY.scaled(Vector3(stretch, 1.0, 1.0))
		prop.call("push", Transform3D(wide, at))
	if vertical:
		var tall := Basis.IDENTITY.scaled(Vector3(1.0, 1.0, stretch))
		prop.call("push", Transform3D(tall, at))


## Mittelstriche folgen den befahrbaren Nachbarn; Kreuzungen bleiben frei.
func _push_dashes(prop: Node3D, r: int, c: int, at: Vector3) -> void:
	var east := Logic.is_road(r, c + 1)
	var west := Logic.is_road(r, c - 1)
	var north := Logic.is_road(r - 1, c)
	var south := Logic.is_road(r + 1, c)
	var crossing := (east or west) and (north or south)
	var half := Logic.TILE_M * 0.5
	for i in 4:
		if crossing and (i == 1 or i == 2):
			continue
		var f := (float(i) + 0.5) / 4.0 * 2.0 - 1.0
		if east or west:
			prop.call("push", Transform3D(Basis.IDENTITY, at + Vector3(f * half, 0.0, 0.0)))
		if north or south:
			var turn := Basis(Vector3.UP, PI * 0.5)
			prop.call("push", Transform3D(turn, at + Vector3(0.0, 0.0, f * half)))


## Häuser: pro Kollider ein Kenney-Gebäude, auf die Kollidergröße eingepasst.
func _build_houses(colliders: Array, rng: GoobyRng) -> void:
	var buckets: Array = []
	var props: Array[Node3D] = []
	for path in HOUSES:
		buckets.append([])
		props.append(_prop(Models.parts(path, 13.0), 20))
	for box: Dictionary in colliders:
		var idx := int(rng.next() * float(HOUSES.size())) % HOUSES.size()
		var cx := (float(box["minX"]) + float(box["maxX"])) * 0.5
		var cz := (float(box["minZ"]) + float(box["maxZ"])) * 0.5
		var yaw := float(int(rng.next() * 4.0)) * PI * 0.5
		(buckets[idx] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, 0.0, cz)))
	for i in props.size():
		props[i].call("begin")
		for xf: Transform3D in buckets[i]:
			props[i].call("push", xf)
		props[i].call("flush")


## Grün am Stadtrand und Büsche auf dem Bürgersteig.
##
## Die Blockkacheln sind seit dem Pflaster-Umbau bebaut — Bäume mitten im
## Innenhof sah ohnehin niemand, Büsche VOR der Hauswand dagegen schon.
func _build_greens(rng: GoobyRng) -> void:
	var tree_prop := _prop(Models.parts_by_height(TREE, 7.0), 80)
	var bush_prop := _prop(Models.parts(BUSH, 2.2), 80)
	tree_prop.call("begin")
	bush_prop.call("begin")
	for r in Logic.GRID:
		for c in Logic.GRID:
			if Logic.is_road(r, c):
				continue
			var w := Logic.tile_to_world(r, c)
			for _i in 2:
				if _inside_block(r, c):
					var edge := Logic.TILE_M * 0.44
					var jx := (rng.next() - 0.5) * 2.0 * edge
					var jz := edge * (1.0 if rng.next() < 0.5 else -1.0)
					if rng.next() < 0.5:
						var swap := jx
						jx = jz
						jz = swap
					# Büsche stehen auf dem Bauplatz-Pflaster (Deckel 0,04).
					bush_prop.call(
						"push", Transform3D(Basis.IDENTITY, Vector3(w.x + jx, 0.04, w.y + jz))
					)
					continue
				var rx := (rng.next() - 0.5) * Logic.TILE_M * 0.8
				var rz := (rng.next() - 0.5) * Logic.TILE_M * 0.8
				var yaw := rng.next() * TAU
				# Bäume stehen auf der Wiese (−0,08) — vorher schwebten sie 8 cm.
				tree_prop.call(
					"push", Transform3D(Basis(Vector3.UP, yaw), Vector3(w.x + rx, -0.08, w.y + rz))
				)
	tree_prop.call("flush")
	bush_prop.call("flush")


## Laternenreihe an den Straßen: schlanker Mast mit warmem Kopf. Im Abendband
## sind das die einzigen echten Lichtpunkte — sie geben der Schlucht Maßstab.
func _build_lamps() -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.09
	post.bottom_radius = 0.13
	post.height = 6.0
	post.radial_segments = 6
	post.rings = 1
	post.material = Fx.flat(LAMP_POST)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.5, 0.14, 0.14)
	arm.material = post.material
	var head := BoxMesh.new()
	head.size = Vector3(0.7, 0.2, 0.34)
	head.material = Fx.glow(LAMP_HEAD, 1.3)
	# Warmer Lichtschein um jeden Lampenkopf: in der Dämmerung „brennen" die
	# Laternen erst mit Halo — vorher waren es nur gelbe Klötzchen. Ein Quad
	# im selben MultiProp = ein einziger zusätzlicher Draw-Call für ALLE.
	var halo := QuadMesh.new()
	halo.size = Vector2(2.2, 2.2)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.4, Color(1.0, 1.0, 1.0, 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_color = Color(1.0, 0.8, 0.45, 0.26)
	halo_mat.albedo_texture = tex
	halo_mat.disable_receive_shadows = true
	halo.material = halo_mat
	var parts: Array = [
		{"mesh": post, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0))},
		{"mesh": arm, "xform": Transform3D(Basis.IDENTITY, Vector3(0.7, 5.9, 0.0))},
		{"mesh": head, "xform": Transform3D(Basis.IDENTITY, Vector3(1.3, 5.75, 0.0))},
		{"mesh": halo, "xform": Transform3D(Basis.IDENTITY, Vector3(1.3, 5.75, 0.0))},
	]
	var prop := _prop(parts, 64)
	prop.call("begin")
	var edge := WALK_W * 0.5 - 0.9
	for r in Logic.GRID:
		for c in Logic.GRID:
			if not Logic.is_road(r, c):
				continue
			var w := Logic.tile_to_world(r, c)
			var vertical := Logic.is_road(r - 1, c) or Logic.is_road(r + 1, c)
			var side := 1.0 if (r + c) % 2 == 0 else -1.0
			# Laternen stehen auf dem Gehweg (Deckel 0,045).
			var at := Vector3(w.x, 0.045, w.y)
			var yaw := 0.0
			if vertical:
				at.x += side * edge
				yaw = 0.0 if side < 0.0 else PI
			else:
				at.z += side * edge
				yaw = PI * 0.5 if side < 0.0 else -PI * 0.5
			prop.call("push", Transform3D(Basis(Vector3.UP, yaw), at))
	prop.call("flush")


func _inside_block(r: int, c: int) -> bool:
	return r >= 1 and r <= Logic.RING_MAX and c >= 1 and c <= Logic.RING_MAX


## Ferne Skyline hinter dem Stadtrand.
##
## Der Wagen ist auf ±90 m geklemmt (`_step_van`), diese Häuser stehen ab
## 112 m — unerreichbar, ohne Kollider, und der Tiefennebel (Ende 140 m) macht
## Silhouetten daraus. Auf der ÄUSSEREN Ringstraße schaute man vorher über
## eine leere Wiese bis zum Horizont; jetzt steht dort Stadt.
func _build_skyline(rng: GoobyRng) -> void:
	var haze := Fx.flat(Color(0.83, 0.68, 0.62), 1.0)
	var prop := _prop_tinted(Models.parts(CITY + "building-skyscraper-a.glb", 16.0), 48, haze)
	prop.call("set_shadows", false)
	prop.call("begin")
	for side in 4:
		for i in 12:
			var along := (float(i) - 5.5) * 22.0 + (rng.next() - 0.5) * 8.0
			var out := 112.0 + rng.next() * 26.0
			var at := Vector3(along, 0.0, -out)
			if side == 1:
				at = Vector3(along, 0.0, out)
			elif side == 2:
				at = Vector3(-out, 0.0, along)
			elif side == 3:
				at = Vector3(out, 0.0, along)
			var tall := Basis.IDENTITY.scaled(Vector3(1.0, 0.7 + rng.next() * 0.9, 1.0))
			prop.call("push", Transform3D(tall.rotated(Vector3.UP, rng.next() * TAU), at))
	prop.call("flush")


## Landmarken: bunte Signalstelen, damit man das Ziel schon von weitem sieht.
## Sie stehen NEBEN der Parkbucht (STELE_OFFSETS), nie im Fahr-/Kamerapfad.
func _build_landmarks() -> void:
	for i in Logic.LANDMARKS.size():
		var row: Dictionary = Logic.LANDMARKS[i]
		var off: Vector2 = STELE_OFFSETS.get(str(row["id"]), Vector2.ZERO)
		var at := Vector2(float(row["x"]) + off.x, float(row["z"]) + off.y)
		stele_punkte.append(at)
		var tint: Color = LANDMARK_TINTS[i % LANDMARK_TINTS.size()]
		# Schlank wie ein Laternenmast. Die erste Fassung war 1,4 m dick mit einer
		# 3-m-Leuchtkugel obendrauf — fuhr der Wagen daran vorbei, stand ein
		# Betonpfeiler mitten im Bild und die überstrahlte Kugel fraß den Himmel.
		var pole := CylinderMesh.new()
		pole.top_radius = 0.16
		pole.bottom_radius = 0.24
		pole.height = 10.0
		pole.radial_segments = 8
		pole.rings = 1
		pole.material = Fx.flat(tint.darkened(0.15))
		var mi := MeshInstance3D.new()
		mi.mesh = pole
		mi.position = Vector3(at.x, 5.0, at.y)
		add_child(mi)
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 12
		ball.rings = 6
		ball.material = Fx.glow(tint, 1.05)
		var top := MeshInstance3D.new()
		top.mesh = ball
		# W14 Quick-Win: 7,5 m lag EXAKT auf Hochkant-Kamerahöhe (7,6 m) — an
		# Abwurfringen fraß die Kugel den Bildschirm. 10,5 m ist sicher darüber.
		top.position = Vector3(at.x, 10.5, at.y)
		add_child(top)


func _slab(size: float, color: Color, y: float) -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3(Logic.TILE_M, 0.05, Logic.TILE_M)
	box.material = Fx.flat(color)
	var scale_v := Vector3(size / Logic.TILE_M, 1.0, size / Logic.TILE_M)
	# Gehweg deckt die ganze Kachel, Asphalt nur den mittleren Streifen —
	# die Skalierung steckt im eingebackenen Teil-Offset, nicht in der Pose.
	return {
		"mesh": box,
		"xform": Transform3D(Basis.IDENTITY.scaled(scale_v), Vector3(0.0, y, 0.0)),
	}


func _dash_part() -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 0.04, 0.34)
	box.material = Fx.flat(DASH)
	# Knapp über der Asphalt-Oberkante (y = 0) — vorher schwebten die Striche
	# 4 cm über der Fahrbahn.
	return {"mesh": box, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.005, 0.0))}


func _prop(parts: Array, cap: int, colored := false) -> Node3D:
	return _prop_tinted(parts, cap, null, colored)


func _prop_tinted(parts: Array, cap: int, material: Material, colored := false) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, colored, material)
	_props.append(node)
	return node
