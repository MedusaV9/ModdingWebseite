extends Node3D
## ECHTE 3D-Teestube (FB-4, MP-A-Politur): Gooby steht als Gastgeber NEBEN dem
## Tisch (sichtbar!), die Kanne schwebt über der Glastasse und kippt beim
## Gießen, der Tee steigt als echter Zylinder, das Zielband liegt als grünes
## Glasband mit Kantenringen UM die Tasse, der Perfect-Ring pulsiert, sobald
## der Tee im Band steht. Servierte Tassen rutschen SICHTBAR nach links raus
## (Ghost-Tasse) statt zu verschwinden; Verschütten hinterlässt eine Pfütze.
## Kulisse: Stube mit Rückwand, Fenster, Bordüre, Wimpeln, Pendelleuchte,
## Küchenzeile (Kenney furniture-kit) und Törtchen (Tiny Treats). Die MECHANIK
## bleibt komplett in tea_party.gd/TeaPartyLogic — diese Bühne ist Darstellung.
##
## W17/G4-Politur: Intro-Totale (establish, M1), Bildschirm-Anker für das
## 2D-Füllmeter (fill_screen_anchors), Tropfen-Partikel im Gieß-Strahl (M3)
## und Reduced-Motion-Gates für die eigenen Fx.burst-Aufrufe (Q2 — das
## geteilte Fx-Kit bleibt unberührt).

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const KIT := "res://assets/minigames/veggie_chop/"
const TREATS := "res://assets/minigames/purble_place/tinytreats/"
const SWEETS := "res://assets/minigames/purble_place/"

## Belichtungs-Kontrakt (test_mpa_stages.gd): Pastell ≠ ausgewaschen.
## Wichtig: Ambient kommt aus dem HIMMEL (sky_contribution 1.0) — deshalb
## drosseln sky_energy UND ambient gemeinsam die Grundhelligkeit.
const STAGE_CFG := {
	"sky_top": Color(0.76, 0.64, 0.53),
	"sky_horizon": Color(0.82, 0.7, 0.58),
	"ground_horizon": Color(0.7, 0.57, 0.45),
	"ground_bottom": Color(0.46, 0.37, 0.3),
	"sky_energy": 0.72,
	"sun_dir": Vector3(-0.5, -0.8, -0.35),
	"sun_color": Color(1.0, 0.93, 0.8),
	"sun_energy": 0.52,
	"ambient": 0.38,
	"fill_energy": 0.14,
	"glow": 0.2,
	"shadow_distance": 14.0,
	"hfov": 44.0,
	"far": 60.0,
}

const TEA := Color(0.6, 0.36, 0.13)
const GLASS := Color(0.82, 0.91, 0.95, 0.3)
const BAND := Color(0.36, 0.74, 0.42, 0.42)
const BAND_EDGE := Color(0.3, 0.68, 0.36)
const PERFECT := Color(1.0, 0.68, 0.16)
const WOOD := Color(0.58, 0.42, 0.29)
const WALL := Color(0.88, 0.76, 0.66)
const WAINSCOT := Color(0.74, 0.55, 0.45)

## Tassenmaße (Meter) — level 1.0 entspricht der vollen Innenhöhe.
const CUP_H := 0.34
const CUP_R := 0.17
const TABLE_H := 0.76
## Tassen-Rutschweg beim Servieren (Meter, von rechts herein).
const SLIDE_M := 1.9
## Ghost-Tasse: Rutschdauer nach links raus (Sekunden).
const GHOST_SEC := 0.55

var stage: Node3D
var gooby: Node3D

var _cup_root: Node3D
var _tea: MeshInstance3D
var _tea_top: MeshInstance3D
var _mat_top_fill: StandardMaterial3D
var _mat_top_good: StandardMaterial3D
var _mat_top_perfect: StandardMaterial3D
var _band_shell: MeshInstance3D
var _band_lo: MeshInstance3D
var _band_hi: MeshInstance3D
var _perfect_ring: MeshInstance3D
var _perfect_mat: StandardMaterial3D
var _kettle: Node3D
var _stream: MeshInstance3D
var _splash: GPUParticles3D
var _drops: GPUParticles3D
var _steam: GPUParticles3D
var _confetti: GPUParticles3D
var _spill_burst: GPUParticles3D
var _puddle: MeshInstance3D
var _puddle_mat: StandardMaterial3D
var _puddle_age := 99.0
var _ghost: Node3D
var _ghost_tea: MeshInstance3D
var _ghost_age := 99.0
var _kettle_tilt := 0.0
var _pulse := 0.0
## Spielpose der Kamera (apply_size merkt sie sich; establish blendet hinein).
var _play_cam_pos := Vector3(0.0, 1.38, 2.5)
var _play_look := Vector3(0.0, 1.1, 0.0)


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	stage.build(STAGE_CFG)
	stage.set_hfov(44.0, 58.0)
	stage.camera.position = Vector3(0.0, 1.38, 2.5)
	stage.camera.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
	_build_room()
	_build_table()
	_build_cup()
	_build_ghost()
	_build_kettle()
	_build_gooby()
	_build_fx()


func _build_room() -> void:
	_build_floor()
	_build_wall()
	_build_kitchen_row()
	_build_shelf()
	_build_bunting()
	_build_lamp()


func _build_floor() -> void:
	add_child(Fx.ground(Vector2(16.0, 12.0), Color(0.58, 0.44, 0.32)))
	# Dielenfugen geben dem Boden Richtung und Tiefe (1 Draw-Call).
	var seams := MultiMeshInstance3D.new()
	var seam := BoxMesh.new()
	seam.size = Vector3(0.035, 0.012, 12.0)
	seam.material = Fx.flat(Color(0.5, 0.37, 0.27))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = seam
	mm.instance_count = 12
	for i in 12:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(-4.95 + float(i) * 0.9, 0.008, 0.0))
		)
	seams.multimesh = mm
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seams)
	# Zweifarbiger Teppich unter dem Tisch.
	for entry: Array in [[1.85, Color(0.85, 0.56, 0.55)], [1.5, Color(0.95, 0.78, 0.72)]]:
		var rug := MeshInstance3D.new()
		var rug_mesh := CylinderMesh.new()
		rug_mesh.top_radius = float(entry[0])
		rug_mesh.bottom_radius = float(entry[0])
		rug_mesh.height = 0.02
		rug_mesh.radial_segments = 28
		rug_mesh.material = Fx.flat(entry[1])
		rug.mesh = rug_mesh
		rug.position.y = 0.011 + (0.004 if float(entry[0]) < 1.6 else 0.0)
		rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rug)


func _build_wall() -> void:
	# Rückwand + Bordüre: schließt die obere Bildhälfte, statt Leere zu zeigen.
	var wall := MeshInstance3D.new()
	var wall_mesh := PlaneMesh.new()
	wall_mesh.size = Vector2(16.0, 7.0)
	wall_mesh.orientation = PlaneMesh.FACE_Z
	wall_mesh.material = Fx.flat(WALL)
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 3.5, -3.2)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	var wainscot := MeshInstance3D.new()
	var ws_mesh := BoxMesh.new()
	ws_mesh.size = Vector3(16.0, 1.05, 0.05)
	ws_mesh.material = Fx.flat(WAINSCOT)
	wainscot.mesh = ws_mesh
	wainscot.position = Vector3(0.0, 0.52, -3.16)
	wainscot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wainscot)
	var trim := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(16.0, 0.08, 0.06)
	trim_mesh.material = Fx.flat(Color(0.95, 0.88, 0.8))
	trim.mesh = trim_mesh
	trim.position = Vector3(0.0, 1.08, -3.15)
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trim)
	_build_window()


func _build_window() -> void:
	# Warm leuchtendes Fenster mit Kreuz + Gardinen rechts oben im Bild.
	var win := Node3D.new()
	win.position = Vector3(1.7, 2.35, -3.14)
	add_child(win)
	var glass := MeshInstance3D.new()
	var glass_mesh := PlaneMesh.new()
	glass_mesh.size = Vector2(1.35, 1.15)
	glass_mesh.orientation = PlaneMesh.FACE_Z
	glass_mesh.material = Fx.glow(Color(0.99, 0.9, 0.68), 0.55)
	glass.mesh = glass_mesh
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(glass)
	var frame_mat := Fx.flat(Color(0.93, 0.86, 0.78))
	for bar: Array in [
		[Vector3(0.0, 0.61, 0.02), Vector3(1.5, 0.09, 0.05)],
		[Vector3(0.0, -0.61, 0.02), Vector3(1.5, 0.09, 0.05)],
		[Vector3(-0.72, 0.0, 0.02), Vector3(0.09, 1.3, 0.05)],
		[Vector3(0.72, 0.0, 0.02), Vector3(0.09, 1.3, 0.05)],
		[Vector3(0.0, 0.0, 0.02), Vector3(0.06, 1.3, 0.04)],
		[Vector3(0.0, 0.0, 0.02), Vector3(1.5, 0.06, 0.04)],
	]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = bar[1]
		beam_mesh.material = frame_mat
		beam.mesh = beam_mesh
		beam.position = bar[0]
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.add_child(beam)
	var curtain_mat := Fx.flat(Color(0.9, 0.62, 0.6))
	for side: float in [-1.0, 1.0]:
		var curtain := MeshInstance3D.new()
		var curtain_mesh := BoxMesh.new()
		curtain_mesh.size = Vector3(0.22, 1.42, 0.07)
		curtain_mesh.material = curtain_mat
		curtain.mesh = curtain_mesh
		curtain.position = Vector3(side * 0.85, 0.0, 0.05)
		curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.add_child(curtain)


func _build_kitchen_row() -> void:
	# Küchenzeile als Mittelgrund-Kulisse.
	var row := Node3D.new()
	row.position = Vector3(0.0, 0.0, -2.6)
	add_child(row)
	for i in 4:
		var cab := Models.node(KIT + "kitchenCabinet.glb", 1.1)
		cab.position.x = -1.65 + float(i) * 1.1
		row.add_child(cab)
	var sink := Models.node(KIT + "kitchenSink.glb", 1.1)
	sink.position.x = 2.75
	row.add_child(sink)
	for i in 3:
		var upper := Models.node(KIT + "kitchenCabinetUpper.glb", 1.1)
		upper.position = Vector3(-1.1 + float(i) * 1.1, 1.5, 0.0)
		row.add_child(upper)
	var rack := Models.node(KIT + "tinytreats/dishrack_plates.gltf", 0.62)
	rack.position = Vector3(2.7, 0.93, -2.5)
	add_child(rack)
	# Törtchen auf der Arbeitsplatte — die Teestube hat Kundschaft verdient.
	for entry: Array in [
		[TREATS + "macaron_pink.gltf", 0.2, -1.7],
		[TREATS + "macaron_blue.gltf", 0.2, -1.35],
		[SWEETS + "cake.glb", 0.42, 0.6],
		[SWEETS + "cupcake.glb", 0.24, 1.4],
		[TREATS + "stand_mixer.gltf", 0.5, -2.15],
	]:
		var treat := Models.node(str(entry[0]), float(entry[1]))
		treat.position = Vector3(float(entry[2]), 0.93, -2.5)
		add_child(treat)


func _build_shelf() -> void:
	# Bord links oben: Kanne + Tassen — füllt die linke obere Bildecke.
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.7, 0.07, 0.42)
	shelf_mesh.material = Fx.flat(WOOD)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(-1.9, 2.25, -2.95)
	shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shelf)
	for entry: Array in [
		[KIT + "tinytreats/mug_red.gltf", 0.22, -2.45],
		[KIT + "tinytreats/pot.gltf", 0.34, -1.9],
		[KIT + "tinytreats/mug_red.gltf", 0.22, -1.4],
	]:
		var prop := Models.node(str(entry[0]), float(entry[1]))
		prop.position = Vector3(float(entry[2]), 2.29, -2.95)
		_no_shadow(prop)
		add_child(prop)


func _build_bunting() -> void:
	# Wimpelkette in zwei Farben über der Küchenzeile.
	for pass_i in 2:
		var flags := MultiMeshInstance3D.new()
		var flag := PrismMesh.new()
		flag.size = Vector3(0.26, 0.3, 0.02)
		flag.material = Fx.flat(Color(0.93, 0.6, 0.66) if pass_i == 0 else Color(0.55, 0.78, 0.66))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = flag
		mm.instance_count = 5
		for i in 5:
			var t := (float(i * 2 + pass_i)) / 9.0
			var droop := sin(t * PI) * 0.34
			mm.set_instance_transform(
				i,
				Transform3D(
					Basis(Vector3.BACK, PI + (t - 0.5) * 0.4),
					Vector3(-2.4 + t * 4.8, 3.4 - droop, -2.4)
				)
			)
		flags.multimesh = mm
		flags.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flags)


func _build_lamp() -> void:
	# Pendelleuchte über dem Tisch: füllt den Vordergrund oben, wirft warmes
	# Licht-Gefühl auf die Szene (nur Optik, kein echtes Licht).
	var cord := MeshInstance3D.new()
	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.015
	cord_mesh.bottom_radius = 0.015
	cord_mesh.height = 1.4
	cord_mesh.material = Fx.flat(Color(0.4, 0.3, 0.25))
	cord.mesh = cord_mesh
	cord.position = Vector3(0.0, 3.5, -0.2)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cord)
	var shade := MeshInstance3D.new()
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.13
	shade_mesh.bottom_radius = 0.28
	shade_mesh.height = 0.22
	shade_mesh.radial_segments = 20
	shade_mesh.material = Fx.flat(Color(0.92, 0.66, 0.6))
	shade.mesh = shade_mesh
	shade.position = Vector3(0.0, 2.72, -0.2)
	add_child(shade)
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.08
	bulb_mesh.height = 0.16
	bulb_mesh.material = Fx.glow(Color(1.0, 0.9, 0.66), 1.3)
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(0.0, 2.64, -0.2)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)


func _build_table() -> void:
	var leg := MeshInstance3D.new()
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.09
	leg_mesh.bottom_radius = 0.14
	leg_mesh.height = TABLE_H
	leg_mesh.material = Fx.flat(Color(0.55, 0.4, 0.27))
	leg.mesh = leg_mesh
	leg.position.y = TABLE_H * 0.5
	add_child(leg)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 0.95
	top_mesh.bottom_radius = 0.95
	top_mesh.height = 0.06
	top_mesh.radial_segments = 32
	top_mesh.material = Fx.flat(Color(0.88, 0.6, 0.58))
	top.mesh = top_mesh
	top.position.y = TABLE_H
	add_child(top)
	# Tischdeko hinten (außerhalb des Tassen-Rutschwegs): Teller mit Törtchen.
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.2
	plate_mesh.bottom_radius = 0.16
	plate_mesh.height = 0.025
	plate_mesh.radial_segments = 20
	plate_mesh.material = Fx.flat(Color(0.97, 0.94, 0.9), 0.4)
	plate.mesh = plate_mesh
	plate.position = Vector3(-0.52, TABLE_H + 0.045, -0.38)
	add_child(plate)
	for entry: Array in [
		[TREATS + "macaron_yellow.gltf", 0.17, -0.58, -0.42],
		[SWEETS + "strawberry.glb", 0.14, -0.44, -0.3],
		[SWEETS + "cookie.glb", 0.17, 0.55, -0.42],
	]:
		var sweet := Models.node(str(entry[0]), float(entry[1]))
		sweet.position = Vector3(float(entry[2]), TABLE_H + 0.06, float(entry[3]))
		_no_shadow(sweet)
		add_child(sweet)


## Glastasse + Untertasse + Henkel + Tee-Säule + Zielband, verschiebbar.
func _build_cup() -> void:
	_cup_root = Node3D.new()
	_cup_root.position = Vector3(0.0, TABLE_H + 0.032, 0.35)
	add_child(_cup_root)
	_build_cup_body(_cup_root)
	# Tee-Oberfläche: Scheibe, die im Band grün und im Perfect-Kern gold glüht
	# — DIE „jetzt loslassen"-Anzeige direkt am Geschehen.
	_mat_top_fill = Fx.glow(TEA.lightened(0.18), 0.25)
	_mat_top_good = Fx.glow(Color(0.5, 0.85, 0.5), 0.9)
	_mat_top_perfect = Fx.glow(PERFECT, 1.5)
	_tea_top = MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = CUP_R - 0.024
	top_mesh.bottom_radius = CUP_R - 0.024
	top_mesh.height = 0.012
	top_mesh.radial_segments = 20
	top_mesh.material = _mat_top_fill
	_tea_top.mesh = top_mesh
	_tea_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(_tea_top)
	# Zielband (good) als Glasband mit klaren Kantenringen, Perfect als
	# pulsierender Goldring.
	_band_shell = MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = CUP_R + 0.028
	band_mesh.bottom_radius = CUP_R + 0.028
	band_mesh.height = 1.0
	band_mesh.material = Fx.glass(BAND, true)
	_band_shell.mesh = band_mesh
	_band_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(_band_shell)
	_band_lo = _band_edge_ring()
	_cup_root.add_child(_band_lo)
	_band_hi = _band_edge_ring()
	_cup_root.add_child(_band_hi)
	_perfect_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = CUP_R + 0.022
	ring_mesh.outer_radius = CUP_R + 0.055
	_perfect_mat = Fx.glow(PERFECT, 1.4)
	ring_mesh.material = _perfect_mat
	_perfect_ring.mesh = ring_mesh
	_perfect_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(_perfect_ring)


## Untertasse + Tee-Säule + Glaswand + Henkel in einen Wurzelknoten bauen
## (geteilt von echter Tasse und Ghost-Tasse).
func _build_cup_body(parent: Node3D) -> void:
	var saucer := MeshInstance3D.new()
	var saucer_mesh := CylinderMesh.new()
	saucer_mesh.top_radius = CUP_R + 0.1
	saucer_mesh.bottom_radius = CUP_R + 0.04
	saucer_mesh.height = 0.03
	saucer_mesh.material = Fx.flat(Color(0.99, 0.96, 0.92), 0.4)
	saucer.mesh = saucer_mesh
	saucer.name = "Untertasse"
	saucer.position.y = 0.005
	parent.add_child(saucer)
	var tea := MeshInstance3D.new()
	var tea_mesh := CylinderMesh.new()
	tea_mesh.top_radius = CUP_R - 0.025
	tea_mesh.bottom_radius = CUP_R - 0.025
	tea_mesh.height = 1.0
	tea_mesh.material = Fx.flat(TEA, 0.25)
	tea.mesh = tea_mesh
	tea.name = "Tee"
	parent.add_child(tea)
	if parent == _cup_root:
		_tea = tea
	else:
		_ghost_tea = tea
	var wall := MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = CUP_R
	wall_mesh.bottom_radius = CUP_R - 0.02
	wall_mesh.height = CUP_H
	wall_mesh.material = Fx.glass(GLASS)
	wall.mesh = wall_mesh
	wall.position.y = 0.02 + CUP_H * 0.5
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wall)
	var handle := MeshInstance3D.new()
	var handle_mesh := TorusMesh.new()
	handle_mesh.inner_radius = 0.035
	handle_mesh.outer_radius = 0.075
	handle_mesh.material = Fx.flat(Color(0.99, 0.96, 0.92), 0.4)
	handle.mesh = handle_mesh
	handle.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	handle.position = Vector3(CUP_R + 0.04, 0.02 + CUP_H * 0.55, 0.0)
	parent.add_child(handle)


func _band_edge_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = CUP_R + 0.024
	mesh.outer_radius = CUP_R + 0.044
	mesh.rings = 24
	mesh.ring_segments = 8
	mesh.material = Fx.glow(BAND_EDGE, 0.8)
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring


## Ghost-Tasse: die servierte Tasse rutscht sichtbar nach links vom Tisch.
func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.visible = false
	add_child(_ghost)
	_build_cup_body(_ghost)


func _build_kettle() -> void:
	_kettle = Node3D.new()
	_kettle.position = Vector3(0.0, TABLE_H + 0.72, 0.35)
	add_child(_kettle)
	var body := Models.node(KIT + "tinytreats/kettle.gltf", 0.42)
	# Tülle zeigt nach −x; Pivot mittig, damit das Kippen natürlich wirkt.
	body.position.y = -0.15
	_kettle.add_child(body)
	_stream = MeshInstance3D.new()
	var stream_mesh := CylinderMesh.new()
	stream_mesh.top_radius = 0.022
	stream_mesh.bottom_radius = 0.03
	stream_mesh.height = 1.0
	stream_mesh.material = Fx.glow(TEA.lightened(0.12), 0.7)
	_stream.mesh = stream_mesh
	_stream.visible = false
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)


func _build_gooby() -> void:
	# HINTER dem Tisch links, Oberkörper über der Platte — Gastgeber mit Blick
	# zur Tasse. (Im Hochformat ist die Frustum-Halbbreite bei z≈0 nur ~0,9 m;
	# neben dem Tisch wäre er abgeschnitten.)
	gooby = Actor.new()
	gooby.position = Vector3(-0.68, 0.0, -0.98)
	add_child(gooby)
	gooby.mount(1.7, 0.45)
	gooby.base_emotion = "happy"
	gooby.add_child(Fx.blob_shadow(0.55))


func _build_fx() -> void:
	_splash = (
		Fx
		. particles(
			{
				"color": Color(0.82, 0.55, 0.24, 0.9),
				"amount": 14,
				"lifetime": 0.4,
				"speed": Vector2(0.3, 0.9),
				"spread": 70.0,
				"gravity": Vector3(0.0, -3.0, 0.0),
				"size": Vector2(0.015, 0.04),
			}
		)
	)
	_splash.emitting = false
	add_child(_splash)
	# W17/G4 M3: Tropfen IM Strahl — der Gieß-Moment glitzert, statt dass
	# nur ein statischer Zylinder steht (Gate: sync-Flag `reduced`).
	_drops = (
		Fx
		. particles(
			{
				"color": Color(0.88, 0.62, 0.28, 0.85),
				"amount": 16,
				"lifetime": 0.35,
				"speed": Vector2(0.2, 0.5),
				"spread": 9.0,
				"gravity": Vector3(0.0, -4.5, 0.0),
				"size": Vector2(0.012, 0.03),
				"additive": true,
			}
		)
	)
	add_child(_drops)
	_steam = (
		Fx
		. particles(
			{
				"color": Color(1.0, 1.0, 1.0, 0.3),
				"amount": 10,
				"lifetime": 1.3,
				"speed": Vector2(0.1, 0.3),
				"spread": 12.0,
				"gravity": Vector3(0.0, 0.5, 0.0),
				"size": Vector2(0.04, 0.1),
			}
		)
	)
	_steam.emitting = false
	add_child(_steam)
	_confetti = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.82, 0.4, 0.95),
				"amount": 22,
				"lifetime": 0.8,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.9, 2.2),
				"spread": 75.0,
				"gravity": Vector3(0.0, -3.5, 0.0),
				"size": Vector2(0.03, 0.08),
				"additive": true,
			}
		)
	)
	add_child(_confetti)
	_spill_burst = (
		Fx
		. particles(
			{
				"color": Color(0.62, 0.4, 0.18, 0.9),
				"amount": 18,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.6, 1.6),
				"spread": 85.0,
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.02, 0.06),
			}
		)
	)
	add_child(_spill_burst)
	# Tee-Pfütze nach dem Verschütten (skaliert auf, blasst aus).
	_puddle = MeshInstance3D.new()
	var puddle_mesh := CylinderMesh.new()
	puddle_mesh.top_radius = 0.3
	puddle_mesh.bottom_radius = 0.3
	puddle_mesh.height = 0.008
	puddle_mesh.radial_segments = 20
	_puddle_mat = Fx.glass(Color(TEA.r, TEA.g, TEA.b, 0.6), true)
	puddle_mesh.material = _puddle_mat
	_puddle.mesh = puddle_mesh
	_puddle.visible = false
	_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puddle)


## Jeden Frame aus tea_party._process: Zustand → Posen. `reduced` gatet die
## dekorativen Gieß-Partikel (Q2); Default false hält die Alt-Aufrufe
## (test_mpa_stages) unverändert.
func sync(
	level: float, band: Dictionary, holding: bool, cup_slide: float, delta: float, reduced := false
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	_pulse += delta
	# Tasse rutscht beim Servieren von rechts herein.
	_cup_root.position.x = cup_slide * SLIDE_M
	# Tee-Säule (Pivot unten): Höhe = level · CUP_H, minimal 1 mm gegen Flackern.
	var fill := clampf(level, 0.0, 1.12) * CUP_H
	_tea.scale = Vector3(1.0, maxf(0.001, fill), 1.0)
	_tea.position.y = 0.02 + fill * 0.5
	_tea.visible = fill > 0.004
	_tea_top.position.y = 0.02 + fill + 0.008
	_tea_top.visible = _tea.visible
	_sync_band(level, band)
	_sync_kettle(level, holding, cup_slide, fill, delta, reduced)
	_sync_ghost(delta)
	_sync_puddle(delta)
	# Gooby fiebert mit: beim Gießen leicht vorgebeugt zur Tasse.
	var lean := 0.1 if holding else 0.03
	gooby.rotation.z = sin(_pulse * (7.0 if holding else 2.2)) * lean * 0.4 - lean


func _sync_band(level: float, band: Dictionary) -> void:
	var center := float(band.get("center", 0.7))
	var half := float(band.get("half", 0.075))
	_band_shell.scale = Vector3(1.0, maxf(0.001, 2.0 * half * CUP_H), 1.0)
	_band_shell.position.y = 0.02 + center * CUP_H
	_band_lo.position.y = 0.02 + (center - half) * CUP_H
	_band_hi.position.y = 0.02 + (center + half) * CUP_H
	_perfect_ring.position.y = 0.02 + center * CUP_H
	# Anzeige am Geschehen: im Band grün, im Perfect-Kern gold + Ring-Puls.
	var in_band := absf(level - center) <= half
	var in_perfect := absf(level - center) <= half * 0.34
	if in_perfect:
		_tea_top.set_surface_override_material(0, _mat_top_perfect)
	elif in_band:
		_tea_top.set_surface_override_material(0, _mat_top_good)
	else:
		_tea_top.set_surface_override_material(0, _mat_top_fill)
	var pulse_scale := 1.0 + (0.08 * sin(_pulse * 9.0) if in_band else 0.0)
	_perfect_ring.scale = Vector3(pulse_scale, 1.0, pulse_scale)
	_perfect_mat.emission_energy_multiplier = 2.2 if in_band else 1.1


func _sync_kettle(
	level: float, holding: bool, cup_slide: float, fill: float, delta: float, reduced := false
) -> void:
	# Kanne folgt der Tasse, kippt beim Gießen und schaukelt sanft im Leerlauf.
	_kettle_tilt = lerpf(_kettle_tilt, 0.55 if holding else 0.0, minf(1.0, delta * 9.0))
	_kettle.position.x = _cup_root.position.x
	_kettle.position.y = TABLE_H + 0.72 + (0.0 if holding else sin(_pulse * 1.6) * 0.02)
	_kettle.rotation.z = -_kettle_tilt
	var pouring := holding and cup_slide <= 0.01
	_stream.visible = pouring
	# Q2: dekorative Gieß-Partikel unter Reduced Motion aus (Gate hier an der
	# eigenen Call-Site — der Strahl selbst bleibt als Anzeige sichtbar).
	_splash.emitting = pouring and not reduced
	_drops.emitting = pouring and not reduced
	_steam.emitting = level > 0.55
	if pouring:
		var spout := _kettle.global_position + Vector3(-0.24, -0.08, 0.0)
		var brim := _cup_root.global_position + Vector3(0.0, 0.02 + fill, 0.0)
		var length := maxf(0.05, spout.y - brim.y)
		_stream.scale = Vector3(1.0, length, 1.0)
		_stream.global_position = Vector3(brim.x, brim.y + length * 0.5, brim.z)
		_splash.global_position = brim
		_drops.global_position = Vector3(brim.x, brim.y + length * 0.55, brim.z)
	_steam.global_position = _cup_root.global_position + Vector3(0.0, CUP_H + 0.1, 0.0)


func _sync_ghost(delta: float) -> void:
	if _ghost_age >= GHOST_SEC:
		_ghost.visible = false
		return
	_ghost_age += delta
	var t := clampf(_ghost_age / GHOST_SEC, 0.0, 1.0)
	var eased := t * t
	_ghost.position.x = -eased * 2.6
	_ghost.visible = t < 1.0


func _sync_puddle(delta: float) -> void:
	if _puddle_age >= 1.2:
		_puddle.visible = false
		return
	_puddle_age += delta
	var t := clampf(_puddle_age / 1.2, 0.0, 1.0)
	_puddle.visible = true
	_puddle.scale = Vector3(0.4 + t * 0.9, 1.0, 0.4 + t * 0.9)
	_puddle_mat.albedo_color = Color(TEA.r, TEA.g, TEA.b, 0.6 * (1.0 - t))


## Bildschirmpunkt der Tasse (Anker für float_text).
func cup_screen() -> Vector2:
	return stage.to_screen(_cup_root.global_position + Vector3(0.0, CUP_H * 0.5, 0.0))


## Layout-Hook aus apply_view.
func apply_size(size: Vector2) -> void:
	stage.apply_size(size)
	var portrait := size.y > size.x
	# Hochkant: näher heran und höher zielen, damit Tisch + Kanne + Kulisse das
	# Bild füllen statt leerem Boden in der unteren Bildhälfte. Die Pose wird
	# gemerkt, damit establish() auch nach Resizes exakt hier landet.
	_play_cam_pos = Vector3(0.0, 1.34, 2.3) if portrait else Vector3(0.0, 1.32, 2.9)
	_play_look = Vector3(0.0, 1.16 if portrait else 1.0, 0.0)
	stage.camera.position = _play_cam_pos
	stage.camera.look_at(_play_look, Vector3.UP)


## W17/G4 M1: Intro-Totale — die Kamera schwebt aus einer weiter gefassten
## Stuben-Totale (Fenster, Bord, Küchenzeile im Bild) in die Spielpose;
## establish(1) == exakte Spielpose (Muster carrot_guard/star_hopper).
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = _play_cam_pos + Vector3(-0.6, 0.55, 1.05) * e
	stage.camera.look_at(_play_look + Vector3(0.0, 0.3, 0.0) * e, Vector3.UP)


## W17/G4 M4: Bildschirm-Anker des Füllwegs (Level 0 und 1) RECHTS neben der
## Tassen-RUHEPOSITION (slide = 0, daher konstant statt mitrutschend) —
## Grundlage für das 2D-Füllmeter im HUD von tea_party.gd.
func fill_screen_anchors() -> Dictionary:
	var base := Vector3(CUP_R + 0.14, TABLE_H + 0.032 + 0.02, 0.35)
	return {
		"bottom": stage.to_screen(base),
		"top": stage.to_screen(base + Vector3(0.0, CUP_H, 0.0)),
	}


## Servierte Tasse mit Füllstand `level` sichtbar nach links rausrutschen.
func serve_ghost(level: float) -> void:
	var fill := clampf(level, 0.0, 1.12) * CUP_H
	_ghost_tea.scale = Vector3(1.0, maxf(0.001, fill), 1.0)
	_ghost_tea.position.y = 0.02 + fill * 0.5
	_ghost.position = Vector3(0.0, TABLE_H + 0.032, 0.35)
	_ghost.visible = true
	_ghost_age = 0.0


## Perfect-Feier; `reduced` lässt Emote/Glühen, gatet aber Hüpfer + Konfetti
## (Q2 — Reduced-Motion-Gate an der eigenen Fx.burst-Call-Site).
func celebrate(reduced := false) -> void:
	gooby.play_for("celebrate", 1.2)
	gooby.emote("ecstatic", 1.2)
	stage.pulse_glow(0.7)
	if reduced:
		return
	gooby.hop(0.4, 0.25)
	Fx.burst(_confetti, _cup_root.global_position + Vector3(0.0, CUP_H + 0.25, 0.0))


func cheer() -> void:
	gooby.play_for("wave", 0.9)
	gooby.emote("happy", 0.9)


## Spill-Reaktion; die Pfütze bleibt als STATISCHES Feedback auch unter
## Reduced Motion, nur der Partikel-Burst wird gegated (Q2).
func groan(reduced := false) -> void:
	gooby.emote("dizzy", 1.2)
	gooby.play_for("idle", 0.2)
	_puddle.position = _cup_root.global_position + Vector3(0.28, 0.045, 0.12)
	_puddle_age = 0.0
	if reduced:
		return
	Fx.burst(_spill_burst, _cup_root.global_position + Vector3(0.0, CUP_H, 0.0))


## Schattenwurf eines geladenen Modells rekursiv abschalten (Deko-Kleinkram).
func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)
