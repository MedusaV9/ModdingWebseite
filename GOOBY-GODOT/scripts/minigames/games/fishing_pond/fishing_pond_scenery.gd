extends RefCounted
## Angelteich-KULISSE: alles, was den Teich zu einem Ort macht.
##
## Agent MP-E (Tiefenpolitur): Anglerhütte mit warm leuchtendem Fenster,
## Schilfgürtel, Enten auf dem Wasser, Laterne am Steg, Fang-Eimer.
##
## W17/G4 (Paket G4-POND): zusätzlich (1) das komplette Dioramen-GELÄNDE —
## Ufermassen, Erdschichten, Wasser, Beckengrund, Bewuchs, Seerosen, Steg —
## 1:1 aus fishing_pond.gd hierher gezogen (die Hauptdatei kratzte am
## 1000-Zeilen-Limit; Werte/Reihenfolge unverändert), und (2) der Ring-Pool
## für Wasserkreise an der Einstichstelle der Schnur (M3).
##
## Nur Kulisse, keine Mechanik. Enten, Eimer und Ringe gehen als Nodes zurück
## an die Spielszene: die Enten paddeln in `_process`, der Eimer sammelt die
## Fänge, die Ringe pulsen NUR ohne Reduced Motion (Gate an der Call-Site).

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const ASSETS := "res://assets/minigames/fishing_pond/"

const HUT_WOOD := Color(0.42, 0.29, 0.22)
const HUT_ROOF := Color(0.3, 0.22, 0.24)
const REED_GREEN := Color(0.3, 0.45, 0.28)
const REED_TIP := Color(0.45, 0.3, 0.18)
const DUCK_BODY := Color(0.93, 0.88, 0.78)
const DUCK_HEAD := Color(0.35, 0.5, 0.32)
const BUCKET_TIN := Color(0.55, 0.58, 0.64)
const GRASS := Color(0.36, 0.53, 0.36)
const SOIL := Color(0.42, 0.31, 0.26)
const WOOD := Color(0.66, 0.47, 0.31)

## Innenmaße des Beckens (Logik: POND_HALF_W 1.8, MAX_DEPTH 3.9).
const POOL_HALF_W := 2.15
const POOL_FRONT_Z := 1.15
const POOL_BACK_Z := -1.8
const POOL_FLOOR_Y := -4.4
## Oberkante der Grasnarbe (die Wasserlinie ist y = 0).
const BANK_Y := 0.26
## Steghöhe über dem Wasser.
const DECK_Y := 0.44

## Lebenszeit eines Wasserrings (s) — danach ist er frei für den Pool.
const RIPPLE_LIFE := 1.1
const RIPPLE_POOL := 6

## Standplätze der Schilfbüschel: hinterm Becken und am linken Ufer — nie vor
## der Schnittkante (dort steht die Kamera) und nie überm Schwimmbereich.
const REED_SPOTS := [
	Vector3(-2.6, 0.26, -1.9),
	Vector3(-2.9, 0.26, -1.1),
	Vector3(-2.45, 0.26, -0.2),
	Vector3(2.5, 0.26, -1.95),
	Vector3(2.85, 0.26, -1.15),
	Vector3(-1.5, 0.26, -2.15),
	Vector3(0.6, 0.26, -2.2),
	Vector3(1.7, 0.26, -2.1),
]

## Ruheplätze der Enten auf dem Wasser (links, weg von Schnur und Schwimmern).
const DUCK_SPOTS := [
	Vector3(-1.35, 0.02, -1.25),
	Vector3(-0.65, 0.02, -1.55),
	Vector3(1.15, 0.02, -1.45),
]


## Baut die komplette Kulisse; gibt {"ducks": Node3D, "bucket": Node3D} zurück.
static func build(stage: Node3D) -> Dictionary:
	_hut(stage)
	_reeds(stage)
	_lantern(stage)
	return {"ducks": _ducks(stage), "bucket": _bucket(stage)}


## Dioramen-Gelände (W17/G4: 1:1 aus fishing_pond.gd): Ufer, Erdschichten,
## Wasser samt Beckengrund, Uferbewuchs, Seerosen und Anglersteg — in exakt
## der alten Aufbau-Reihenfolge. Gibt die Wasser-Spiegelfläche zurück (die
## Spielszene lässt sie mit der Dünung atmen).
static func build_terrain(stage: Node3D) -> MeshInstance3D:
	_banks(stage)
	var surface := _water(stage)
	_shore(stage)
	_deck(stage)
	return surface


## Milchglas-Platte hinter HUD-Labels/Bannern (M6 — Muster mpb_garden_kit).
static func hud_plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.99, 0.94, 0.72)
	box.set_corner_radius_all(16)
	return box


## W17/G4 M3: Ring-Pool für Wasserkreise an der Einstichstelle der Schnur.
## Flache Tori knapp über der Wasserlinie; expandieren und verblassen. Die
## Spielszene spawnt sie NUR ohne Reduced Motion (Q2: Gate an der Call-Site).
static func build_ripples(stage: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Ripples"
	for i in RIPPLE_POOL:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.93, 0.99, 1.0, 0.0)
		var ring := Props3D.torus(1.0, 0.028, mat)
		# Teilweise zur Kamera gekippt: flach auf dem Wasser wäre der Ring aus
		# der fast waagerechten Dioramen-Kamera (~7° Pitch) unsichtbar; so
		# liest er sich weiter als Wasserring UND bleibt deutlich zu sehen.
		ring.rotation.x = PI * 0.3
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		ring.set_meta("t", RIPPLE_LIFE)
		ring.set_meta("power", 1.0)
		ring.set_meta("mat", mat)
		holder.add_child(ring)
	stage.add_child(holder)
	return holder


## Einen freien Ring an `at` starten; sind alle aktiv, verfällt der Puls.
static func spawn_ripple(holder: Node3D, at: Vector3, power := 1.0) -> void:
	if holder == null:
		return
	for ring: MeshInstance3D in holder.get_children():
		if float(ring.get_meta("t")) < RIPPLE_LIFE:
			continue
		ring.set_meta("t", 0.0)
		ring.set_meta("power", power)
		ring.position = at
		return


## Ringe expandieren lassen und ausblenden (jeden Frame aus der Spielszene).
static func tick_ripples(holder: Node3D, delta: float) -> void:
	if holder == null:
		return
	for ring: MeshInstance3D in holder.get_children():
		var t := minf(RIPPLE_LIFE, float(ring.get_meta("t")) + delta)
		ring.set_meta("t", t)
		if t >= RIPPLE_LIFE:
			ring.visible = false
			continue
		var k := t / RIPPLE_LIFE
		var power := float(ring.get_meta("power"))
		var radius := 0.08 + 0.62 * power * k
		ring.visible = true
		ring.scale = Vector3(radius, 1.0, radius)
		(ring.get_meta("mat") as StandardMaterial3D).albedo_color.a = (0.55 * power * (1.0 - k))


## Enten paddeln: gemächliches Hin und Her um den Ruheplatz, Wippen mit der
## Dünung, Blick in Fahrtrichtung. Läuft jeden Frame aus der Spielszene.
static func tick_ducks(flock: Node3D, elapsed: float) -> void:
	if flock == null:
		return
	for duck: Node3D in flock.get_children():
		var home: Vector3 = duck.get_meta("home")
		var phase: float = duck.get_meta("phase")
		var t := elapsed * 0.32 + phase
		duck.position = Vector3(
			home.x + sin(t) * 0.42, home.y + sin(elapsed * 2.0 + phase) * 0.015, home.z
		)
		# Kopf (−z) in Fahrtrichtung: dx > 0 → yaw −π/2.
		var target_yaw := -signf(cos(t)) * PI * 0.5 + 0.2 * sin(elapsed * 1.3 + phase)
		duck.rotation.y = lerp_angle(duck.rotation.y, target_yaw, 0.04)


## Fang-Flüge: der gefangene Fisch segelt in einem Bogen vom Haken in den
## Eimer. Bei der Landung wächst eine Schwanzflosse aus dem Eimerwasser.
static func tick_flights(flights: Array, bucket: Node3D, delta: float) -> void:
	for i in range(flights.size() - 1, -1, -1):
		var f: Dictionary = flights[i]
		f["t"] = float(f["t"]) + delta / 0.55
		var t: float = minf(1.0, float(f["t"]))
		var node: Node3D = f["node"]
		var from: Vector3 = f["from"]
		var to: Vector3 = bucket.position + Vector3(0.0, 0.22, 0.0)
		node.position = from.lerp(to, t) + Vector3(0.0, sin(t * PI) * 0.9, 0.0)
		node.rotation.z = t * TAU * 1.5
		if t >= 1.0:
			_add_trophy(bucket, f.get("color", DUCK_HEAD))
			node.queue_free()
			flights.remove_at(i)


## Schwanzflosse im Eimer (max. 6): flachgedrückte Kugel in Artenfarbe, leicht
## gekippt — als ragte der Fisch kopfüber im Wasser.
static func _add_trophy(bucket: Node3D, color: Color) -> void:
	var count := int(bucket.get_meta("fins", 0))
	if count >= 6:
		return
	bucket.set_meta("fins", count + 1)
	var a := float(count) * 2.4
	var fin := Props3D.sphere(0.055, Props3D.flat(color, 0.6))
	fin.scale = Vector3(0.35, 1.25, 0.8)
	fin.position = Vector3(cos(a) * 0.06, 0.24, sin(a) * 0.06)
	fin.rotation.z = 0.35 * sin(a)
	bucket.add_child(fin)


# ------------------------------------------------- Gelände (aus fishing_pond)


## Ufermasse: drei große Erdblöcke mit Grasnarbe, vorn aufgeschnitten. Das
## Becken ist die Kerbe dazwischen — seine Innenflächen sind zugleich die
## Beckenwände, die man durch das Wasser sieht.
static func _banks(stage: Node3D) -> void:
	var soil := Props3D.flat(SOIL)
	var grass := Props3D.flat(GRASS)
	# Tief genug, dass die Schnittkante den unteren Bildrand IMMER füllt —
	# hochkant bleibt sonst ein schwarzer Streifen unter dem Becken stehen.
	var depth := BANK_Y + 14.0
	var mid := BANK_Y - depth * 0.5
	# Vor der Schnittkante darf NICHTS stehen: die Kamera liegt fast auf
	# Grasnarbenhöhe, jedes Stück Land davor würde das Becken verdecken.
	var side_len := POOL_FRONT_Z + 26.0
	var side_mid := POOL_FRONT_Z - side_len * 0.5
	for sign_x: float in [-1.0, 1.0]:
		var at := Vector3(sign_x * (POOL_HALF_W + 14.0), mid, side_mid)
		stage.add_child(Props3D.box(Vector3(28.0, depth, side_len), soil, at))
		stage.add_child(
			Props3D.box(
				Vector3(28.0, 0.16, side_len), grass, Vector3(at.x, BANK_Y - 0.07, side_mid)
			)
		)
	_strata(stage)
	var back_len := 88.0
	var back_mid := POOL_BACK_Z - back_len * 0.5
	stage.add_child(Props3D.box(Vector3(90.0, depth, back_len), soil, Vector3(0.0, mid, back_mid)))
	stage.add_child(
		Props3D.box(Vector3(90.0, 0.16, back_len), grass, Vector3(0.0, BANK_Y - 0.07, back_mid))
	)
	# Beckensohle aus hellem Sand — sie gibt der Tiefe einen Boden.
	var floor_z := (POOL_FRONT_Z + POOL_BACK_Z) * 0.5
	stage.add_child(
		Props3D.box(
			Vector3(POOL_HALF_W * 2.0, 0.4, POOL_FRONT_Z - POOL_BACK_Z),
			Props3D.flat(Color(0.55, 0.47, 0.36)),
			Vector3(0.0, POOL_FLOOR_Y - 0.2, floor_z)
		)
	)


## Erdschichten auf der Schnittfläche. Eine nackte Wand ist im Querformat die
## halbe Bildfläche; die Bänder machen daraus einen Bodenaufschluss mit
## Humus, Lehm, Sand und Kiesel — und geben dem Ausschnitt Maßstab.
static func _strata(stage: Node3D) -> void:
	var bands := [
		{"y": 0.02, "h": 0.36, "c": Color(0.34, 0.24, 0.2)},
		{"y": -0.7, "h": 1.1, "c": Color(0.5, 0.35, 0.28)},
		{"y": -2.1, "h": 1.7, "c": Color(0.44, 0.32, 0.3)},
		{"y": -3.9, "h": 1.9, "c": Color(0.56, 0.44, 0.35)},
		{"y": -7.0, "h": 4.4, "c": Color(0.35, 0.29, 0.32)},
	]
	for band: Dictionary in bands:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(26.0, float(band["h"]), 0.06)
		mesh.material = Props3D.flat(band["c"])
		var poses: Array = []
		for sign_x: float in [-1.0, 1.0]:
			poses.append(
				Props3D.pose(
					Vector3(sign_x * (POOL_HALF_W + 13.0), float(band["y"]), POOL_FRONT_Z + 0.02)
				)
			)
		stage.add_child(Props3D.swarm_mesh(mesh, poses, 8.0))


## Wasser: Spiegelfläche oben + Schnittscheibe vorn. Beide sind durchsichtig,
## die Scheibe färbt alles dahinter teichgrün ein — genau der Trick, mit dem
## die Web-Fassung ihren Querschnitt baut, hier aber vor echter Geometrie.
static func _water(stage: Node3D) -> MeshInstance3D:
	var floor_z := (POOL_FRONT_Z + POOL_BACK_Z) * 0.5
	var span := POOL_FRONT_Z - POOL_BACK_Z
	var top := Props3D.glass(Color(0.44, 0.76, 0.82, 0.42))
	top.emission_enabled = true
	top.emission = Color(0.95, 0.62, 0.42)
	top.emission_energy_multiplier = 0.35
	var surface := Props3D.ground(Vector2(POOL_HALF_W * 2.0, span), top, 0.0)
	surface.position.z = floor_z
	stage.add_child(surface)
	var pane := Props3D.box(
		Vector3(POOL_HALF_W * 2.0, -POOL_FLOOR_Y, 0.02),
		Props3D.glass(Color(0.2, 0.5, 0.58, 0.44)),
		Vector3(0.0, POOL_FLOOR_Y * 0.5, POOL_FRONT_Z)
	)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(pane)
	# Zweite Scheibe HINTER den Fischen: sie färbt nur die Beckenrückwand ein
	# und erzeugt so das Tiefengefälle, das eine einzelne Scheibe nicht kann.
	var murk := Props3D.box(
		Vector3(POOL_HALF_W * 2.0, -POOL_FLOOR_Y, 0.02),
		Props3D.glass(Color(0.1, 0.3, 0.4, 0.5)),
		Vector3(0.0, POOL_FLOOR_Y * 0.5, POOL_BACK_Z + 0.5)
	)
	murk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(murk)
	# Heller Saum auf der Wasserlinie — er trennt Luft und Wasser sichtbar.
	stage.add_child(
		Props3D.box(
			Vector3(POOL_HALF_W * 2.0, 0.028, 0.05),
			Props3D.glow(Color(1.0, 0.78, 0.55), 0.9),
			Vector3(0.0, 0.0, POOL_FRONT_Z)
		)
	)
	_underwater(stage)
	return surface


## Beckengrund: Steine und Wasserpflanzen als Massenware (ein Draw-Call je
## Sorte) — sie geben der Tiefe Maßstab und verstecken die nackte Sohle.
static func _underwater(stage: Node3D) -> void:
	var rocks: Array = []
	var weeds: Array = []
	for i in 9:
		var x := -POOL_HALF_W + 0.35 + 3.6 * float(i) / 8.0
		var z := POOL_BACK_Z + 0.4 + 1.9 * absf(sin(float(i) * 2.3))
		rocks.append(Props3D.pose(Vector3(x, POOL_FLOOR_Y, z), float(i) * 1.7, 0.9))
		if i % 2 == 0:
			weeds.append(Props3D.pose(Vector3(x + 0.2, POOL_FLOOR_Y, z - 0.3), float(i), 1.4))
	stage.add_child(Props3D.swarm(Props3D.parts(ASSETS + "rock_smallA.glb", 0.3), rocks))
	stage.add_child(
		Props3D.swarm(
			Props3D.parts(ASSETS + "grass_large.glb", 0.55, {"grass": Color(0.24, 0.5, 0.4)}), weeds
		)
	)


## Uferbewuchs: Schilfgürtel, Baumreihe, Büsche, Steine, Pilze — und das
## Ruderboot am linken Ufer. Alles hinter der Beckenkante.
static func _shore(stage: Node3D) -> void:
	# Zwei Sperrzonen: das Becken selbst (nichts wächst im Wasser) und ALLES
	# vor der Beckenkante — dort steht die Kamera. Ohne die zweite Regel
	# pflanzt der Kranz der großen Radien Bäume direkt vors Objektiv.
	var bank := func(at: Vector3) -> bool:
		if at.z > POOL_FRONT_Z + 1.4:
			return true
		return absf(at.x) < POOL_HALF_W + 0.5 and at.z > POOL_BACK_Z - 0.5
	var behind := func(at: Vector3) -> bool: return at.z > POOL_BACK_Z - 0.6
	var center := Vector3(0.0, BANK_Y, POOL_BACK_Z - 0.4)
	stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.55, 26, 3.3, center, 0.7, 0.3, bank)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "plant_bushLarge.glb", 0.8, 12, 5.2, center, 0.9, 1.4, bank)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "tree_default.glb", 3.6, 9, 8.6, center, 1.4, 0.6, behind)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "tree_pineRoundA.glb", 4.4, 8, 11.0, center, 1.8, 2.2, behind)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "tree_fat.glb", 3.2, 7, 14.5, center, 2.1, 1.1, behind)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "rock_largeA.glb", 0.62, 7, 4.4, center, 0.8, 2.8, bank)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "mushroom_red.glb", 0.26, 8, 4.0, center, 0.7, 3.5, bank)
	)
	var boat := Props3D.model(ASSETS + "boat-row-small.glb", 0.46)
	boat.position = Vector3(-4.1, BANK_Y - 0.05, POOL_FRONT_Z - 0.4)
	boat.rotation.y = -0.5
	Props3D.tint(boat, Color(0.78, 0.55, 0.36))
	stage.add_child(boat)
	_lilies(stage)
	# Tief stehende Abendsonne hinter der Baumreihe (Web: sun disc + glow).
	var sun := Props3D.halo(3.4, Color(1.0, 0.66, 0.36, 0.85))
	sun.position = Vector3(-9.0, 3.4, POOL_BACK_Z - 24.0)
	stage.add_child(sun)
	var bridge := Props3D.model(ASSETS + "bridge_wood.glb", 0.5)
	bridge.position = Vector3(-3.4, BANK_Y, POOL_BACK_Z - 1.2)
	bridge.scale = Vector3(1.6, 1.0, 1.6)
	Props3D.repaint(bridge, Props3D.NATURE)
	stage.add_child(bridge)


## Seerosen auf dem Wasser — sie geben der Spiegelfläche eine Oberfläche, an
## der man sie überhaupt als Wasser erkennt (eine leere Glasplatte tut das
## nicht). Sie liegen bewusst LINKS des Hakens und stören das Auswerfen nicht.
static func _lilies(stage: Node3D) -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 0.19
	pad.bottom_radius = 0.19
	pad.height = 0.025
	pad.radial_segments = 10
	pad.rings = 1
	pad.material = Props3D.flat(Color(0.33, 0.56, 0.35), 0.85)
	var pads: Array = []
	var spots := [
		Vector3(-1.62, 0.012, 0.45),
		Vector3(-1.15, 0.012, -0.35),
		Vector3(-1.85, 0.012, -0.95),
		Vector3(1.42, 0.012, -1.15),
	]
	for i in spots.size():
		pads.append(Props3D.pose(spots[i], float(i) * 1.3, 0.8 + 0.35 * float(i % 2)))
	stage.add_child(Props3D.swarm_mesh(pad, pads, 3.0))
	var bloom := Props3D.sphere(0.075, Props3D.glow(Color(0.98, 0.7, 0.82), 0.5))
	bloom.position = spots[0] + Vector3(0.05, 0.05, 0.0)
	stage.add_child(bloom)


## Anglersteg: Bohlen über der Wasserkante, zwei Pfähle ins Wasser.
static func _deck(stage: Node3D) -> void:
	var wood := Props3D.flat(WOOD, 0.85)
	var plank := BoxMesh.new()
	plank.size = Vector3(1.5, 0.07, 0.22)
	plank.material = wood
	var poses: Array = []
	for i in 6:
		poses.append(Props3D.pose(Vector3(1.72, DECK_Y, 0.62 - float(i) * 0.28)))
	stage.add_child(Props3D.swarm_mesh(plank, poses, 4.0))
	stage.add_child(
		Props3D.box(
			Vector3(1.58, 0.09, 1.78),
			Props3D.flat(WOOD.darkened(0.28), 0.9),
			Vector3(1.72, DECK_Y - 0.09, -0.09)
		)
	)
	for z: float in [0.5, -0.66]:
		stage.add_child(
			Props3D.cylinder(
				0.08, 1.5, Props3D.flat(WOOD.darkened(0.4), 0.95), Vector3(1.12, DECK_Y - 0.82, z)
			)
		)


## Anglerhütte am rechten Ufer hinter dem Steg: Bretterwände, Satteldach,
## warm leuchtendes Fenster — das Licht macht die Dämmerung erst gemütlich.
static func _hut(stage: Node3D) -> void:
	var hut := Node3D.new()
	hut.name = "Hut"
	var wood := Props3D.flat(HUT_WOOD, 0.9)
	hut.add_child(Props3D.box(Vector3(2.3, 1.5, 1.7), wood, Vector3(0.0, 0.75, 0.0)))
	# Bretterfugen als dunkle Streifen — sonst liest sich die Wand als Plastik.
	var seam := BoxMesh.new()
	seam.size = Vector3(2.32, 0.035, 1.72)
	seam.material = Props3D.flat(HUT_WOOD.darkened(0.35), 0.95)
	var seams: Array = []
	for i in 4:
		seams.append(Props3D.pose(Vector3(0.0, 0.3 + 0.34 * float(i), 0.0)))
	hut.add_child(Props3D.swarm_mesh(seam, seams, 4.0))
	var roof := PrismMesh.new()
	roof.size = Vector3(2.7, 0.85, 2.1)
	roof.material = Props3D.flat(HUT_ROOF, 0.85)
	hut.add_child(Props3D.mesh_node(roof, Vector3(0.0, 1.92, 0.0)))
	# Fenster zur Kamera: warmes Licht, der Blickfang der ganzen Uferzeile.
	hut.add_child(
		Props3D.box(
			Vector3(0.5, 0.44, 0.05),
			Props3D.glow(Color(1.0, 0.78, 0.42), 1.7),
			Vector3(-0.5, 0.95, 0.87)
		)
	)
	hut.add_child(
		Props3D.box(
			Vector3(0.42, 0.9, 0.05),
			Props3D.flat(HUT_WOOD.darkened(0.5)),
			Vector3(0.55, 0.45, 0.87)
		)
	)
	# Weit genug hinten, dass sie AUCH im schmalen Hochformat im Bild steht —
	# bei x 4,6 sah man dort nur noch die Laterne und eine Dachkante.
	hut.position = Vector3(3.3, 0.26, -5.2)
	hut.rotation.y = -0.35
	stage.add_child(hut)


## Schilfgürtel: Halme als eine MultiMesh, Kolben als zweite — zwei Draw-Calls
## für den ganzen Bewuchs. Jeder Standplatz bekommt 4–5 Halme mit Streuung.
static func _reeds(stage: Node3D) -> void:
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.016
	stalk.bottom_radius = 0.024
	stalk.height = 1.0
	stalk.radial_segments = 5
	stalk.rings = 1
	stalk.material = Props3D.flat(REED_GREEN, 0.9)
	var tip := CapsuleMesh.new()
	tip.radius = 0.04
	tip.height = 0.24
	tip.radial_segments = 6
	tip.rings = 2
	tip.material = Props3D.flat(REED_TIP, 0.9)
	var stalks: Array = []
	var tips: Array = []
	for s in REED_SPOTS.size():
		var spot: Vector3 = REED_SPOTS[s]
		for i in 5:
			var a := float(s * 5 + i) * 2.39996
			var off := Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.14)
			var h := 0.75 + 0.3 * absf(sin(a * 1.7))
			var at := spot + off
			var lean := 0.09 * sin(a * 3.1)
			var xf := Transform3D(
				Basis.from_euler(Vector3(lean, a, lean * 0.6)).scaled(Vector3(1.0, h, 1.0)),
				at + Vector3(0.0, h * 0.5, 0.0)
			)
			stalks.append(xf)
			if i % 2 == 0:
				tips.append(
					Transform3D(
						Basis.from_euler(Vector3(lean, a, lean * 0.6)),
						at + Vector3(0.0, h + 0.08, 0.0)
					)
				)
	stage.add_child(Props3D.swarm_mesh(stalk, stalks, 8.0))
	stage.add_child(Props3D.swarm_mesh(tip, tips, 8.0))


## Enten: Rumpf, Kopf, Schnabel — drei Blobs, die in `_tick_ducks` der
## Spielszene gemächlich paddeln und mit der Dünung wippen.
static func _ducks(stage: Node3D) -> Node3D:
	var flock := Node3D.new()
	flock.name = "Ducks"
	for i in DUCK_SPOTS.size():
		var duck := Node3D.new()
		var body := Props3D.sphere(0.11, Props3D.flat(DUCK_BODY, 0.8))
		body.position.y = 0.05
		body.scale = Vector3(1.0, 0.8, 1.45)
		duck.add_child(body)
		var tail := Props3D.sphere(0.05, Props3D.flat(DUCK_BODY.darkened(0.12), 0.8))
		tail.position = Vector3(0.0, 0.1, 0.15)
		tail.scale = Vector3(1.0, 0.7, 1.3)
		duck.add_child(tail)
		var head := Props3D.sphere(
			0.06, Props3D.flat(DUCK_HEAD if i % 2 == 0 else DUCK_BODY.darkened(0.06), 0.8)
		)
		head.position = Vector3(0.0, 0.17, -0.13)
		duck.add_child(head)
		var beak := Props3D.box(
			Vector3(0.045, 0.025, 0.07), Props3D.flat(Color(0.95, 0.62, 0.25), 0.7)
		)
		beak.position = Vector3(0.0, 0.16, -0.2)
		duck.add_child(beak)
		duck.position = DUCK_SPOTS[i]
		duck.set_meta("home", DUCK_SPOTS[i])
		duck.set_meta("phase", float(i) * 2.1)
		flock.add_child(duck)
	stage.add_child(flock)
	return flock


## Laterne am Stegpfahl: dunkler Mast, warm glühender Kopf plus Halo — sie
## beleuchtet Goobys Arbeitsplatz und spiegelt die Abendstimmung.
static func _lantern(stage: Node3D) -> void:
	var post := Node3D.new()
	post.name = "Lantern"
	post.add_child(
		Props3D.cylinder(
			0.035, 1.5, Props3D.flat(Color(0.3, 0.26, 0.24), 0.9), Vector3(0.0, 0.75, 0.0)
		)
	)
	post.add_child(
		Props3D.box(
			Vector3(0.14, 0.18, 0.14),
			Props3D.glow(Color(1.0, 0.8, 0.45), 2.0),
			Vector3(0.0, 1.5, 0.0)
		)
	)
	post.add_child(
		Props3D.box(
			Vector3(0.18, 0.04, 0.18),
			Props3D.flat(Color(0.24, 0.2, 0.2), 0.9),
			Vector3(0.0, 1.62, 0.0)
		)
	)
	var halo := Props3D.halo(0.5, Color(1.0, 0.75, 0.4, 0.4))
	halo.position = Vector3(0.0, 1.5, 0.0)
	post.add_child(halo)
	post.position = Vector3(2.6, 0.44, -0.85)
	stage.add_child(post)


## Fang-Eimer auf dem Steg: Blechzylinder mit dunklem Wasser drin. Die
## Spielszene lässt gefangene Fische hineinfliegen und steckt pro Fang eine
## Schwanzflosse hinein — der Punktestand wird als Ding in der Welt sichtbar.
static func _bucket(stage: Node3D) -> Node3D:
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	var tin := CylinderMesh.new()
	tin.top_radius = 0.16
	tin.bottom_radius = 0.12
	tin.height = 0.24
	tin.radial_segments = 12
	tin.rings = 1
	tin.material = Props3D.flat(BUCKET_TIN, 0.45)
	bucket.add_child(Props3D.mesh_node(tin, Vector3(0.0, 0.12, 0.0)))
	var water := CylinderMesh.new()
	water.top_radius = 0.135
	water.bottom_radius = 0.135
	water.height = 0.02
	water.radial_segments = 12
	water.rings = 1
	water.material = Props3D.flat(Color(0.14, 0.3, 0.36), 0.3)
	bucket.add_child(Props3D.mesh_node(water, Vector3(0.0, 0.2, 0.0)))
	var handle := Props3D.torus(0.15, 0.012, Props3D.flat(BUCKET_TIN.darkened(0.25), 0.4))
	handle.rotation.x = PI * 0.45
	handle.position.y = 0.2
	bucket.add_child(handle)
	bucket.position = Vector3(2.28, 0.44, 0.42)
	stage.add_child(bucket)
	return bucket
