extends Node3D
## ECHTE 3D-Turnhalle für Trampolin-Tricks (FB-4, MP-C-Politur): Sprungtuch
## mit Federn und Rahmen auf einem runden Teppich, Gooby (echtes Rig) springt
## METERGENAU (Spielhöhe = Weltmeter) mit Streck-/Stauchpose, jede Landung
## dippt das Tuch, wirft Staub auf und schickt eine Schockwelle über die
## Matte. Kulisse: Dielenboden mit Hallenlinien, Lambris + Fensterband mit
## warmem Licht, Sprossenwand, Wimpelkette (echte Farben), Turnmatten, Bank
## und Pflanze an den Querformat-Rändern. Die MECHANIK bleibt komplett in
## trampoline.gd/TrampolineLogic — diese Bühne ist reine Darstellung.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")

## Geteilte weiche Punkt-Textur der Bühnen-Kits (Staub-Motes im Fensterlicht).
const DOT_TEX := "res://assets/minigames/_3da_stage/vfx/circle_05.png"
## Oberkante des Sprungtuchs in Metern (Spielhöhe 0 = hier).
const MAT_Y := 0.55
const MAT_R := 1.15
const INK := Color(0.24, 0.19, 0.17)
## Pastelltöne der Wimpel — das Publikum trägt dieselbe Palette (W16).
const CROWD_TINTS: Array[Color] = [
	Color(0.95, 0.55, 0.66),
	Color(1.0, 0.82, 0.4),
	Color(0.38, 0.76, 0.7),
	Color(0.58, 0.8, 0.42),
]

var stage: Node3D
var gooby: Node3D

var _cloth: MeshInstance3D
var _shadow: MeshInstance3D
var _shock_ring: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _tier_mats: Array[StandardMaterial3D] = []
var _tier_chips: Array[Node3D] = []
var _tier_flash: Array[float] = [0.0, 0.0]
var _dust: GPUParticles3D
var _trail: GPUParticles3D
var _stars: Node3D
var _squash := 0.0
var _crowd_bodies: MultiMeshInstance3D
var _crowd_heads: MultiMeshInstance3D
var _crowd_ears: MultiMeshInstance3D
var _crowd_spots: Array[Vector3] = []
var _crowd_cheer := 0.0


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Helle Turnhalle — aber NICHT überbelichtet (bekannte Falle):
				# Sonne + Ambient bleiben unter 1, die Farben tragen die Wärme.
				"sky_top": Color(0.78, 0.86, 0.94),
				"sky_horizon": Color(0.94, 0.89, 0.78),
				"ground_horizon": Color(0.88, 0.8, 0.66),
				"ground_bottom": Color(0.7, 0.6, 0.48),
				"sun_dir": Vector3(-0.3, -0.9, -0.35),
				"sun_energy": 0.8,
				"ambient": 0.55,
				"fill_energy": 0.24,
				"glow": 0.3,
				"glow_threshold": 0.82,
				"shadow_distance": 22.0,
				"far": 70.0,
			}
		)
	)
	_build_hall()
	_build_side_props()
	_build_trampoline()
	_build_tiers()
	_build_gooby()
	_build_crowd()
	_build_sunlight()
	_build_fx()


func _build_hall() -> void:
	# Dielenboden + Plankenfugen (eine MultiMesh = 1 Draw-Call).
	add_child(Fx.ground(Vector2(30.0, 22.0), Color(0.84, 0.68, 0.5)))
	var seams := MultiMeshInstance3D.new()
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(30.0, 0.012, 0.05)
	seam_mesh.material = Fx.flat(Color(0.72, 0.58, 0.42, 1.0))
	var seam_mm := MultiMesh.new()
	seam_mm.transform_format = MultiMesh.TRANSFORM_3D
	seam_mm.mesh = seam_mesh
	seam_mm.instance_count = 10
	for i in 10:
		seam_mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.005, -5.0 + float(i) * 1.2))
		)
	seams.multimesh = seam_mm
	add_child(seams)
	# Hallenlinien wie auf echten Turnhallenböden (teal + rosa).
	for entry: Array in [
		[Color(0.35, 0.72, 0.68), -0.9, 0.09], [Color(0.93, 0.6, 0.68), 2.3, 0.06]
	]:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(30.0, 0.014, float(entry[2]))
		line_mesh.material = Fx.flat(entry[0])
		line.mesh = line_mesh
		line.position = Vector3(0.0, 0.012, float(entry[1]))
		add_child(line)
	# Rückwand: Lambris unten, Creme in der Mitte, Fensterband oben.
	for entry: Array in [
		[Color(0.88, 0.76, 0.6), 0.0, 2.2],
		[Color(0.95, 0.88, 0.76), 2.2, 2.8],
		[Color(0.55, 0.68, 0.8), 5.0, 2.6],
	]:
		var wall := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(30.0, float(entry[2]), 0.3)
		mesh.material = Fx.flat(entry[0])
		wall.mesh = mesh
		wall.position = Vector3(0.0, float(entry[1]) + float(entry[2]) * 0.5, -5.6)
		add_child(wall)
	# Sockelleiste trennt Lambris und Cremeband sauber.
	var skirt := MeshInstance3D.new()
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(30.0, 0.14, 0.34)
	skirt_mesh.material = Fx.flat(Color(0.76, 0.6, 0.45))
	skirt.mesh = skirt_mesh
	skirt.position = Vector3(0.0, 2.2, -5.58)
	add_child(skirt)
	_build_windows()
	_build_flags()
	_build_banner()
	_build_ladder()
	_build_poster()


## Fensterband: warme Scheiben MIT Kreuzsprossen — vorher weiße Löcher.
func _build_windows() -> void:
	var wins := MultiMeshInstance3D.new()
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(1.7, 1.3, 0.1)
	var win_mat := Fx.flat(Color(0.99, 0.93, 0.72))
	win_mat.emission_enabled = true
	win_mat.emission = Color(1.0, 0.9, 0.65)
	win_mat.emission_energy_multiplier = 0.4
	win_mesh.material = win_mat
	var win_mm := MultiMesh.new()
	win_mm.transform_format = MultiMesh.TRANSFORM_3D
	win_mm.mesh = win_mesh
	win_mm.instance_count = 6
	for i in 6:
		win_mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(-7.5 + float(i) * 3.0, 5.75, -5.42))
		)
	wins.multimesh = win_mm
	add_child(wins)
	# Sprossen: je Fenster ein Kreuz (eine MultiMesh für alle Balken).
	var bars := MultiMeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.8, 0.09, 0.06)
	bar_mesh.material = Fx.flat(Color(0.99, 0.97, 0.94))
	var bar_mm := MultiMesh.new()
	bar_mm.transform_format = MultiMesh.TRANSFORM_3D
	bar_mm.mesh = bar_mesh
	bar_mm.instance_count = 12
	for i in 6:
		var x := -7.5 + float(i) * 3.0
		bar_mm.set_instance_transform(i * 2, Transform3D(Basis.IDENTITY, Vector3(x, 5.75, -5.36)))
		bar_mm.set_instance_transform(
			i * 2 + 1,
			Transform3D(
				Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(0.78, 1.0, 1.0)),
				Vector3(x, 5.75, -5.36)
			)
		)
	bars.multimesh = bar_mm
	add_child(bars)


## Wimpelkette mit Durchhang — Instanzfarben brauchen vertex_color_use_as_albedo,
## sonst bleiben alle Wimpel blass-rosa (der Vorher-Fehler).
func _build_flags() -> void:
	var flags := MultiMeshInstance3D.new()
	var flag_mesh := PrismMesh.new()
	flag_mesh.size = Vector3(0.4, 0.5, 0.04)
	var flag_mat := Fx.flat(Color(1.0, 1.0, 1.0))
	flag_mat.vertex_color_use_as_albedo = true
	flag_mesh.material = flag_mat
	var flag_mm := MultiMesh.new()
	flag_mm.transform_format = MultiMesh.TRANSFORM_3D
	flag_mm.use_colors = true
	flag_mm.mesh = flag_mesh
	flag_mm.instance_count = 11
	var tints: Array[Color] = [
		Color(0.95, 0.55, 0.66),
		Color(1.0, 0.82, 0.4),
		Color(0.38, 0.76, 0.7),
		Color(0.58, 0.8, 0.42),
	]
	for i in 11:
		var t := (float(i) + 0.5) / 11.0
		var x := -8.0 + t * 16.0
		var y := 5.15 - sin(t * PI) * 0.5  # W14 Quick-Win: Platz fürs höhere Banner
		flag_mm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, PI), Vector3(x, y, -5.3)))
		flag_mm.set_instance_color(i, tints[i % tints.size()])
	flags.multimesh = flag_mm
	add_child(flags)


## Banner „GOOBY GYM" — breit genug für den Schriftzug (vorher Überlauf).
func _build_banner() -> void:
	var banner := MeshInstance3D.new()
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(4.5, 0.95, 0.1)
	banner_mesh.material = Fx.flat(Color(0.91, 0.45, 0.58))
	banner.mesh = banner_mesh
	# W14 Quick-Win: 3,2 m lag genau in Goobys Apex-Zone — der Star verdeckte
	# den Schriftzug in fast jedem Frame (Audit c=3). 4,1 m hängt frei darüber.
	banner.position = Vector3(0.0, 4.1, -5.4)
	add_child(banner)
	var trim := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(4.66, 1.11, 0.06)
	trim_mesh.material = Fx.flat(Color(0.99, 0.95, 0.9))
	trim.mesh = trim_mesh
	trim.position = Vector3(0.0, 4.1, -5.44)
	add_child(trim)
	var text := Label3D.new()
	text.text = "GOOBY GYM"
	text.font_size = 150
	text.pixel_size = 0.0032
	text.modulate = Color(1.0, 0.98, 0.94, 0.98)
	text.outline_size = 26
	text.outline_modulate = Color(INK.r, INK.g, INK.b, 0.85)
	text.position = Vector3(0.0, 4.1, -5.33)
	add_child(text)


## Sprossenwand links (zwei Holme + Sprossen als EINE MultiMesh).
func _build_ladder() -> void:
	var rungs := MultiMeshInstance3D.new()
	var rung_mesh := CylinderMesh.new()
	rung_mesh.top_radius = 0.045
	rung_mesh.bottom_radius = 0.045
	rung_mesh.height = 1.1
	rung_mesh.radial_segments = 8
	rung_mesh.material = Fx.flat(Color(0.85, 0.71, 0.53))
	var rung_mm := MultiMesh.new()
	rung_mm.transform_format = MultiMesh.TRANSFORM_3D
	rung_mm.mesh = rung_mesh
	rung_mm.instance_count = 8
	for i in 8:
		rung_mm.set_instance_transform(
			i,
			Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-1.9, 0.7 + float(i) * 0.42, -5.3))
		)
	rungs.multimesh = rung_mm
	add_child(rungs)
	for x: float in [-2.42, -1.38]:
		var pole := MeshInstance3D.new()
		var pole_mesh := BoxMesh.new()
		pole_mesh.size = Vector3(0.1, 3.8, 0.1)
		pole_mesh.material = Fx.flat(Color(0.72, 0.54, 0.38))
		pole.mesh = pole_mesh
		pole.position = Vector3(x, 2.2, -5.32)
		add_child(pole)


## Motivationsposter rechts neben dem Trampolin (füllt die Hochkant-Wand).
func _build_poster() -> void:
	var backing := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.86, 1.1, 0.05)
	mesh.material = Fx.flat(Color(0.99, 0.97, 0.92))
	backing.mesh = mesh
	backing.position = Vector3(1.72, 1.7, -5.42)
	backing.rotation_degrees.z = -2.0
	add_child(backing)
	var inner := MeshInstance3D.new()
	var inner_mesh := BoxMesh.new()
	inner_mesh.size = Vector3(0.72, 0.82, 0.05)
	inner_mesh.material = Fx.flat(Color(0.42, 0.76, 0.7))
	inner.mesh = inner_mesh
	inner.position = Vector3(1.72, 1.78, -5.4)
	inner.rotation_degrees.z = -2.0
	add_child(inner)
	var text := Label3D.new()
	text.text = "HOP!"
	text.font_size = 110
	text.pixel_size = 0.003
	text.modulate = Color(1.0, 0.98, 0.94)
	text.outline_size = 20
	text.outline_modulate = Color(INK.r, INK.g, INK.b, 0.8)
	text.position = Vector3(1.72, 1.78, -5.36)
	text.rotation_degrees.z = -2.0
	add_child(text)


## Turnmatten, Bank, Ball und Pflanze: füllen die Querformat-Ränder, ohne
## die Hochkant-Bühne (±2,2 m sichtbar) zuzustellen.
func _build_side_props() -> void:
	var mat_colors: Array[Color] = [Color(0.42, 0.62, 0.85), Color(1.0, 0.8, 0.42)]
	for i in 2:
		var pad := MeshInstance3D.new()
		var pad_mesh := BoxMesh.new()
		pad_mesh.size = Vector3(2.3, 0.34, 1.5)
		pad_mesh.material = Fx.flat(mat_colors[i])
		pad.mesh = pad_mesh
		pad.position = Vector3(-4.1 + float(i) * 0.25, 0.17 + float(i) * 0.36, -3.3)
		pad.rotation_degrees.y = 4.0 - float(i) * 7.0
		add_child(pad)
	# Zwei Bänke fürs Publikum (Befund 2): rechts wie gehabt, die zweite
	# hinten links vor der Rückwand — beide bekommen Mini-Gooby-Fans.
	_add_bench(Vector3(4.1, 0.0, -3.6))
	_add_bench(Vector3(-3.0, 0.0, -4.9))
	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.27
	ball_mesh.height = 0.54
	ball_mesh.material = Fx.flat(Color(0.95, 0.55, 0.66))
	ball.mesh = ball_mesh
	ball.position = Vector3(3.4, 0.27, -2.2)
	add_child(ball)
	var pot := MeshInstance3D.new()
	var pot_mesh := CylinderMesh.new()
	pot_mesh.top_radius = 0.3
	pot_mesh.bottom_radius = 0.22
	pot_mesh.height = 0.5
	pot_mesh.radial_segments = 10
	pot_mesh.material = Fx.flat(Color(0.85, 0.55, 0.4))
	pot.mesh = pot_mesh
	pot.position = Vector3(-4.5, 0.25, -4.8)
	add_child(pot)
	var leaves := MeshInstance3D.new()
	var leaves_mesh := SphereMesh.new()
	leaves_mesh.radius = 0.5
	leaves_mesh.height = 1.2
	leaves_mesh.material = Fx.flat(Color(0.42, 0.66, 0.4))
	leaves.mesh = leaves_mesh
	leaves.position = Vector3(-4.5, 1.05, -4.8)
	add_child(leaves)


## Turnbank (Sitzbrett + zwei Beine) an `at` (Bodenhöhe y=0).
func _add_bench(at: Vector3) -> void:
	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(2.2, 0.12, 0.55)
	seat_mesh.material = Fx.flat(Color(0.82, 0.64, 0.46))
	seat.mesh = seat_mesh
	seat.position = at + Vector3(0.0, 0.5, 0.0)
	add_child(seat)
	for dx: float in [-0.85, 0.85]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.14, 0.5, 0.5)
		leg_mesh.material = Fx.flat(Color(0.62, 0.47, 0.34))
		leg.mesh = leg_mesh
		leg.position = at + Vector3(dx, 0.25, 0.0)
		add_child(leg)


func _build_trampoline() -> void:
	# Runder Teppich verankert das Trampolin auf dem großen Dielenboden.
	var rug := MeshInstance3D.new()
	var rug_mesh := CylinderMesh.new()
	rug_mesh.top_radius = 2.3
	rug_mesh.bottom_radius = 2.3
	rug_mesh.height = 0.02
	rug_mesh.radial_segments = 26
	rug_mesh.material = Fx.flat(Color(0.93, 0.8, 0.72))
	rug.mesh = rug_mesh
	rug.position = Vector3(0.0, 0.012, 0.0)
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rug)
	# Rahmenring, vier Beine, Federn und das dippende Sprungtuch.
	var frame := MeshInstance3D.new()
	var frame_mesh := TorusMesh.new()
	frame_mesh.inner_radius = MAT_R + 0.02
	frame_mesh.outer_radius = MAT_R + 0.14
	frame_mesh.rings = 28
	frame_mesh.material = Fx.flat(Color(0.42, 0.32, 0.3))
	frame.mesh = frame_mesh
	frame.position.y = MAT_Y
	add_child(frame)
	var legs := MultiMeshInstance3D.new()
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.05
	leg_mesh.bottom_radius = 0.06
	leg_mesh.height = MAT_Y
	leg_mesh.radial_segments = 8
	leg_mesh.material = Fx.flat(Color(0.35, 0.28, 0.27))
	var leg_mm := MultiMesh.new()
	leg_mm.transform_format = MultiMesh.TRANSFORM_3D
	leg_mm.mesh = leg_mesh
	leg_mm.instance_count = 4
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		leg_mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(cos(a) * MAT_R, MAT_Y * 0.5, sin(a) * MAT_R))
		)
	legs.multimesh = leg_mm
	add_child(legs)
	var springs := MultiMeshInstance3D.new()
	var spring_mesh := CylinderMesh.new()
	spring_mesh.top_radius = 0.028
	spring_mesh.bottom_radius = 0.028
	spring_mesh.height = 0.17
	spring_mesh.radial_segments = 6
	spring_mesh.material = Fx.flat(Color(0.55, 0.58, 0.63), 0.45)
	var spring_mm := MultiMesh.new()
	spring_mm.transform_format = MultiMesh.TRANSFORM_3D
	spring_mm.mesh = spring_mesh
	spring_mm.instance_count = 14
	for i in 14:
		var a := TAU * float(i) / 14.0
		var basis := Basis(Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5)), PI * 0.5)
		spring_mm.set_instance_transform(
			i, Transform3D(basis, Vector3(cos(a) * (MAT_R + 0.02), MAT_Y, sin(a) * (MAT_R + 0.02)))
		)
	springs.multimesh = spring_mm
	add_child(springs)
	_cloth = MeshInstance3D.new()
	var cloth_mesh := CylinderMesh.new()
	cloth_mesh.top_radius = MAT_R
	cloth_mesh.bottom_radius = MAT_R * 0.94
	cloth_mesh.height = 0.06
	cloth_mesh.radial_segments = 28
	cloth_mesh.material = Fx.flat(Color(0.35, 0.79, 0.72), 0.7)
	_cloth.mesh = cloth_mesh
	_cloth.position.y = MAT_Y - 0.03
	add_child(_cloth)
	_shadow = Fx.blob_shadow(0.75, 0.3)
	_shadow.position = Vector3(0.0, MAT_Y + 0.015, 0.0)
	add_child(_shadow)
	# TorusMesh liegt bereits flach in der xz-Ebene — NICHT kippen, sonst
	# steht die Schockwelle als Bogen über dem Tuch.
	_shock_ring = Fx.ring(0.5, 0.05, Color(0.35, 0.79, 0.72))
	_shock_mat = _shock_ring.mesh.material as StandardMaterial3D
	_shock_ring.position.y = MAT_Y + 0.06
	_shock_ring.visible = false
	add_child(_shock_ring)
	# Warmes Hallenlicht über dem Trampolin: hebt Gooby aus der Pastellwand.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.72)
	lamp.light_energy = 1.6
	lamp.omni_range = 8.0
	lamp.position = Vector3(0.0, 4.6, 1.6)
	add_child(lamp)


func _build_tiers() -> void:
	# Höhenmarken ×2/×3: leuchtendes Band + Chip mit Label an der Seite.
	var tiers: Array[float] = [
		float(TrampolineLogic.TRAMP["TIER2_APEX"]), float(TrampolineLogic.TRAMP["TIER3_APEX"])
	]
	for i in tiers.size():
		var y := MAT_Y + tiers[i]
		var tint := Color(1.0, 0.78, 0.3) if i == 1 else Color(0.35, 0.79, 0.72)
		var band := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(4.4, 0.05, 0.05)
		var mat := Fx.glow(tint, 0.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)
		mesh.material = mat
		band.mesh = mesh
		band.position = Vector3(0.0, y, -0.6)
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
		_tier_mats.append(mat)
		var chip := Node3D.new()
		chip.position = Vector3(1.85, y, -0.6)
		add_child(chip)
		var plate := MeshInstance3D.new()
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(0.56, 0.34, 0.06)
		plate_mesh.material = Fx.flat(tint)
		plate.mesh = plate_mesh
		chip.add_child(plate)
		var label := Label3D.new()
		label.text = "×3" if i == 1 else "×2"
		label.font_size = 120
		label.pixel_size = 0.002
		label.outline_size = 18
		label.outline_modulate = Color(INK.r, INK.g, INK.b, 0.8)
		label.position.z = 0.04
		chip.add_child(label)
		_tier_chips.append(chip)


func _build_gooby() -> void:
	gooby = Actor.new()
	gooby.position = Vector3(0.0, MAT_Y, 0.0)
	add_child(gooby)
	gooby.mount(1.05)
	gooby.base_emotion = "happy"


## W16 Befund 2 (M2-Muster danceParty): Mini-Gooby-Publikum als drei
## MultiMeshes (Körper, Köpfe, Ohren). Fans sitzen auf beiden Bänken und
## stehen an der Rückwand (dort sieht sie auch das Hochformat).
func _build_crowd() -> void:
	_crowd_spots = [
		Vector3(3.5, 0.56, -3.6),
		Vector3(4.1, 0.56, -3.62),
		Vector3(4.7, 0.56, -3.58),
		Vector3(-3.35, 0.56, -4.9),
		Vector3(-2.65, 0.56, -4.92),
		Vector3(-2.05, 0.0, -4.85),
		Vector3(-1.6, 0.0, -5.0),
		Vector3(1.6, 0.0, -4.95),
		Vector3(2.05, 0.0, -4.8),
	]
	var body := SphereMesh.new()
	body.radius = 0.2
	body.height = 0.36
	body.radial_segments = 10
	body.rings = 5
	var body_mat := Fx.flat(Color(0.93, 0.87, 0.78))
	body_mat.vertex_color_use_as_albedo = true
	body.material = body_mat
	_crowd_bodies = _crowd_layer(body, _crowd_spots.size())
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	head.radial_segments = 10
	head.rings = 5
	head.material = body.material
	_crowd_heads = _crowd_layer(head, _crowd_spots.size())
	var ear := SphereMesh.new()
	ear.radius = 0.045
	ear.height = 0.22
	ear.radial_segments = 6
	ear.rings = 3
	ear.material = body.material
	_crowd_ears = _crowd_layer(ear, _crowd_spots.size() * 2)
	for i in _crowd_spots.size():
		var tint := Color(0.93, 0.87, 0.78).lerp(CROWD_TINTS[i % CROWD_TINTS.size()], 0.45)
		_crowd_bodies.multimesh.set_instance_color(i, tint)
		_crowd_heads.multimesh.set_instance_color(i, tint.lightened(0.12))
		_crowd_ears.multimesh.set_instance_color(i * 2, tint.lightened(0.12))
		_crowd_ears.multimesh.set_instance_color(i * 2 + 1, tint.lightened(0.12))
	_pose_crowd(0.0)


## Ein MultiMesh-Layer des Publikums (Körper/Köpfe/Ohren teilen das Muster).
func _crowd_layer(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Publikum posen: phasenversetztes Wippen; bei Jubel (_crowd_cheer) werden
## die Hüpfer hoch und schnell — Muster danceParty `_pose_crowd`.
func _pose_crowd(pulse: float) -> void:
	if _crowd_bodies == null:
		return
	var bodies := _crowd_bodies.multimesh
	var heads := _crowd_heads.multimesh
	var ears := _crowd_ears.multimesh
	var amp := 0.03 + _crowd_cheer * 0.18
	var beat := 4.0 + _crowd_cheer * 3.5
	for i in _crowd_spots.size():
		var base := _crowd_spots[i]
		var hop := maxf(0.0, sin(pulse * beat + float(i) * 1.7)) * amp
		var sway := sin(pulse * 2.6 + float(i)) * 0.05
		var at := base + Vector3(sway * 0.4, hop, 0.0)
		bodies.set_instance_transform(i, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.2, 0.0)))
		heads.set_instance_transform(
			i, Transform3D(Basis(Vector3.BACK, sway), at + Vector3(0.0, 0.42, 0.0))
		)
		for side in 2:
			var ear_x := (-0.07 if side == 0 else 0.07) + sway * 0.5
			ears.set_instance_transform(
				i * 2 + side,
				Transform3D(
					Basis(Vector3.BACK, sway * 2.0), at + Vector3(ear_x, 0.56 + hop * 0.3, 0.0)
				)
			)


## Befund 6: Fensterlicht LEBT — schräge Sonnenstrahl-Quads von den Scheiben
## plus träge Staub-Motes in der Hallenluft (1 Draw-Call je Strahl + 1 für
## die Motes; Pollen-Muster von hide_seek).
func _build_sunlight() -> void:
	for x: float in [-1.5, 1.5, 4.5]:
		add_child(_light_beam(Vector3(x, 5.6, -5.3), Vector3(x - 1.3, 0.1, -2.4)))
	var motes := (
		Puff
		. stream(
			DOT_TEX,
			{
				"amount": 24,
				"lifetime": 7.0,
				"size": 0.08,
				"dir": Vector3(-0.2, -0.1, 0.15),
				"spread": 30.0,
				"speed": Vector2(0.1, 0.35),
				"gravity": Vector3(0.0, -0.02, 0.0),
				"color": Color(1.0, 0.95, 0.72, 0.4),
				"color_end": Color(1.0, 0.9, 0.6, 0.0),
				"box": Vector3(4.5, 2.4, 1.6),
				"local": false,
			}
		)
	)
	motes.position = Vector3(0.0, 3.2, -3.0)
	add_child(motes)


## Weicher additiver Lichtstrahl von `top` (Fenster) nach `bottom` (Boden);
## der Alphaverlauf läuft am Boden auf null aus.
func _light_beam(top: Vector3, bottom: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, top.distance_to(bottom))
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.albedo_color = Color(1.0, 0.93, 0.66, 0.14)
	mat.albedo_texture = tex
	quad.material = mat
	var beam := MeshInstance3D.new()
	beam.mesh = quad
	var up := (top - bottom).normalized()
	var x_axis := up.cross(Vector3.BACK).normalized()
	var z_axis := x_axis.cross(up).normalized()
	beam.transform = Transform3D(Basis(x_axis, up, z_axis), (top + bottom) * 0.5)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return beam


func _build_fx() -> void:
	_dust = (
		Fx
		. particles(
			{
				"color": Color(0.9, 0.82, 0.68, 0.8),
				"amount": 18,
				"lifetime": 0.7,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.6),
				"spread": 80.0,
				"gravity": Vector3(0.0, -3.0, 0.0),
				"size": Vector2(0.08, 0.2),
			}
		)
	)
	add_child(_dust)
	_trail = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.93, 0.7, 0.5),
				"amount": 20,
				"lifetime": 0.5,
				"speed": Vector2(0.1, 0.4),
				"spread": 30.0,
				"gravity": Vector3.ZERO,
				"size": Vector2(0.1, 0.22),
				"additive": true,
			}
		)
	)
	add_child(_trail)
	# Sternchen über dem Kopf nach der Po-Landung.
	_stars = Node3D.new()
	for i in 3:
		var star := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.055
		mesh.height = 0.11
		mesh.material = Fx.glow(Color(1.0, 0.85, 0.35), 1.6)
		star.mesh = mesh
		star.position = Vector3(
			cos(TAU * float(i) / 3.0) * 0.3, 0.0, sin(TAU * float(i) / 3.0) * 0.3
		)
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.add_child(star)
	_stars.visible = false
	add_child(_stars)


## Beide Orientierungen: gleiche Bildhöhe (Sprunghöhe MUSS sichtbar bleiben),
## das Querformat gewinnt automatisch Breite dazu.
func apply_size(size: Vector2) -> void:
	stage.apply_size(size)
	var landscape := size.x > size.y
	stage.camera.position = Vector3(0.0, 2.7, 8.6)
	stage.camera.look_at(Vector3(0.0, 2.55, 0.0), Vector3.UP)
	stage.set_half_height(3.3 if landscape else 3.5, 8.6)
	for i in _tier_chips.size():
		_tier_chips[i].position.x = 3.1 if landscape else 1.85


## W16 Intro-Totale (M1): die Kamera schwebt aus der Hallen-Übersicht
## (Banner + Fensterband im Bild) in die Spielpose; k=1 entspricht exakt
## der apply_size-Pose — danach übernimmt wieder apply_size allein.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = Vector3(-1.7 * e, 2.7 + 1.6 * e, 8.6 + 2.8 * e)
	stage.camera.look_at(Vector3(0.0, 2.55 + 0.7 * e, 0.0), Vector3.UP)


## Publikum jubeln lassen (Dreierpack, ×3-Durchbruch, Boost) — der Hüpfer
## klingt über sync langsam wieder ab.
func crowd_cheer(strength := 1.0) -> void:
	_crowd_cheer = clampf(maxf(_crowd_cheer, strength), 0.0, 1.0)


## Befund 5: Höhenband + Chip blitzen beim Stufen-Durchbruch (0 = ×2, 1 = ×3).
func tier_flash(i: int) -> void:
	if i >= 0 and i < _tier_flash.size():
		_tier_flash[i] = 1.0


## Jeden Frame aus trampoline.gd: Höhe/Tricks/Schock in die Bühne spiegeln.
func sync(
	height: float,
	vy: float,
	stagger_left: float,
	tricking: float,
	trick_spin: float,
	last_trick: String,
	apex: float,
	shock: float,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.position.y = MAT_Y + height
	if tricking > 0.0:
		# Salto kippt vorwärts, Drehung wirbelt um die Hochachse, Schraube rollt.
		if last_trick == "flip":
			gooby.rotation = Vector3(trick_spin, 0.0, 0.0)
		elif last_trick == "spin":
			gooby.rotation = Vector3(0.0, trick_spin, 0.0)
		else:
			gooby.rotation = Vector3(0.0, trick_spin * 0.5, trick_spin)
	else:
		gooby.rotation = gooby.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 14.0))
	_pose_stretch(height, vy, stagger_left, shock, delta)
	# Sprungtuch dippt beim Aufprall und wölbt sich leicht auf.
	var dip := shock * 0.3
	_cloth.position.y = MAT_Y - 0.03 - dip
	_cloth.scale = Vector3(1.0 + dip * 0.3, 1.0, 1.0 + dip * 0.3)
	_shadow.scale = Vector3.ONE * clampf(1.25 - height * 0.18, 0.35, 1.25)
	var ring_t := 1.0 - shock
	_shock_ring.visible = shock > 0.05
	if _shock_ring.visible:
		_shock_ring.scale = Vector3.ONE * (0.4 + ring_t * 2.6)
		_shock_mat.albedo_color.a = shock * 0.7
	# Höhenmarken leuchten und pulsieren, sobald der aktuelle Apex sie
	# erreicht; beim Stufen-Durchbruch blitzen Band + Chip (tier_flash).
	var tiers: Array[float] = [
		float(TrampolineLogic.TRAMP["TIER2_APEX"]), float(TrampolineLogic.TRAMP["TIER3_APEX"])
	]
	for i in _tier_mats.size():
		var reached := apex >= tiers[i]
		var flash := _tier_flash[i]
		_tier_flash[i] = maxf(0.0, flash - delta * 1.4)
		var glow := (1.0 + 0.35 * sin(pulse * 7.0)) if reached else 0.0
		_tier_mats[i].emission_energy_multiplier = glow + flash * 2.2
		_tier_mats[i].albedo_color.a = maxf(0.85 if reached else 0.4, flash)
		_tier_chips[i].scale = Vector3.ONE * (1.0 + flash * 0.35)
	# Publikum wippt mit; Jubel (Dreierpack/×3/Boost) klingt langsam ab.
	_crowd_cheer = maxf(0.0, _crowd_cheer - delta * 0.55)
	_pose_crowd(pulse)
	# Flugspur nur bei ordentlich Tempo.
	_trail.global_position = gooby.global_position + Vector3(0.0, 0.5, 0.0)
	_trail.emitting = absf(vy) > 3.0 and stagger_left <= 0.0
	# Benommen-Sternchen kreisen nach der Po-Landung.
	_stars.visible = stagger_left > 0.0
	if _stars.visible:
		_stars.position = gooby.position + Vector3(0.0, 1.35, 0.0)
		_stars.rotation.y = pulse * 4.0


## Streck-/Stauchpose (nur Optik): steigen streckt, die Landung staucht kurz,
## nach der Po-Landung sitzt Gooby platt gedrückt da.
func _pose_stretch(
	height: float, vy: float, stagger_left: float, shock: float, delta: float
) -> void:
	_squash = maxf(0.0, _squash - delta * 5.0)
	if shock > 0.9:
		_squash = 1.0
	if stagger_left > 0.0:
		gooby.scale = gooby.scale.lerp(Vector3(1.16, 0.78, 1.16), minf(1.0, delta * 10.0))
		return
	var near_mat := clampf(1.0 - height * 1.6, 0.0, 1.0)
	var s := clampf(vy * 0.022, -0.1, 0.18) - _squash * 0.3 * near_mat
	gooby.scale = Vector3(1.0 - s * 0.5, 1.0 + s, 1.0 - s * 0.5)


## Bildschirmanker über Gooby (Landefenster-Ring, float_text).
func gooby_screen() -> Vector2:
	return stage.to_screen(gooby.global_position + Vector3(0.0, 0.55, 0.0))


## JEDE Landung: Staub + Tuch-Dip (der Dip läuft über den shock-Parameter).
func land_fx(strength := 0.6) -> void:
	Fx.burst(_dust, Vector3(0.0, MAT_Y + 0.08, 0.35))
	if strength > 0.75:
		stage.pulse_glow(0.35)


func boost_fx() -> void:
	gooby.emote("ecstatic", 0.8)
	gooby.play_for("celebrate", 0.7)
	stage.pulse_glow(0.7)
	crowd_cheer(0.55)


func butt_fx() -> void:
	gooby.emote("dizzy", 1.6)
	Fx.burst(_dust, Vector3(0.0, MAT_Y + 0.1, 0.0))


func trick_fx() -> void:
	gooby.emote("ecstatic", 0.6)
