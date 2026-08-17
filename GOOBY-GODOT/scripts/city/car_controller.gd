class_name CarController
extends Node3D
## Spieler-Auto (W3a CITY) — Port von GOOBY/src/city/carController.js:
## physics-lite + verzeihend, KEINE Physik-Engine (kinematisch integriert).
## Auto-Throttle 9→13 m/s, Lenk-Tiefpass τ=120 ms + 90°/s-Yaw-Cap, sanfte
## Spur-Assist-Feder, weiche AABB-Kollisionen (slide + Tempoverlust).
## Zahlen: CityCarFeel (1:1 aus carFeel.js/DRIVE_TUNING). NEU (M1-Auftrag):
## Rückwärtsgang — Bremse im Stand gedrückt halten fährt rückwärts.
##
## Steer-Vorzeichen-KONTRAKT (Web §G3.1-a): set_steer(v>0) = rechts AUF DEM
## SCHIRM unter der Chase-Cam ⇒ heading NIMMT AB. Die EINE Negation sitzt
## hier an der Anwendungsstelle — nie in CityCarFeel.

signal wall_hit
signal stuck

const CAR_GLB := "res://assets/city/autos/sedan.glb"

## Kollisions-AABBs {min_x, max_x, min_z, max_z} (Gebäude/Props) — von der
## Stadtszene gesetzt.
var colliders: Array[Dictionary] = []
## W18/4-B12: Park-Pad-Mitten (Welt-XZ) + Radius — von der Stadtszene
## gesetzt (karte.parkplatz_welt je Ort). Innerhalb dieses Radius darf die
## gehaltene Bremse das Auto GANZ anhalten (kein Kriech-Minimum), damit der
## Betreten-Prompt kein 10-s-Rollfenster mehr ist.
var park_pads: Array[Vector3] = []
var park_pad_radius := 7.0
## Fahr-Grenzen (halbe Weltbreite/-tiefe in m, minus Rand).
var welt_halb := Vector2(140.0, 110.0)
## Scheinwerfer an (W4-P3 POLISH-8, nachts) — VOR add_child setzen.
var licht_an := false

var heading := 0.0
var speed := 0.0
var frozen := false

var _steer := 0.0
var _steer_smoothed := 0.0
var _braking := false
var _reverse := false
var _ramp_time := 0.0
var _wall_contact := false
var _stuck_t := 0.0
var _prev_xz := Vector2.ZERO
var _modell: Node3D
var _licht_nodes: Array[Node3D] = []


func _ready() -> void:
	var szene: PackedScene = load(CAR_GLB)
	if szene != null:
		_modell = szene.instantiate()
		_modell.scale = Vector3.ONE * CityCarFeel.CAR_SCALE
		add_child(_modell)
		if licht_an:
			_baue_scheinwerfer(_modell)
	position.y = CityCarFeel.ROAD_Y
	_prev_xz = Vector2(position.x, position.z)


## W18/J4 Tagesrhythmus: Scheinwerfer zur Laufzeit schalten — lazy gebaut
## (die Szene startet oft am Tag), danach nur noch Sichtbarkeit toggeln.
func setze_licht(an: bool) -> void:
	if an == licht_an and not (an and _licht_nodes.is_empty()):
		licht_an = an
		return
	licht_an = an
	if an and _licht_nodes.is_empty() and _modell != null:
		_baue_scheinwerfer(_modell)
	for node in _licht_nodes:
		node.visible = an


## Nachts: zwei warme Emissiv-Kugeln vorn + EIN kleines Omni-Licht als
## Straßenschein (nur das Spielerauto — Mobile-Licht-Budget A §7).
func _baue_scheinwerfer(modell: Node3D) -> void:
	var front := 0.6
	for mesh in modell.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var aabb := mi.get_aabb()
		front = maxf(front, mi.position.z + aabb.position.z + aabb.size.z)
	for seite: float in [-1.0, 1.0]:
		var licht := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.05
		kugel.height = 0.1
		kugel.radial_segments = 8
		kugel.rings = 4
		licht.mesh = kugel
		licht.material_override = CityAmbiente.leuchten_material(Color(1.0, 0.95, 0.75), 2.4)
		licht.position = Vector3(seite * 0.22, 0.25, front)
		modell.add_child(licht)
		_licht_nodes.append(licht)
	var schein := OmniLight3D.new()
	schein.light_color = Color(1.0, 0.92, 0.7)
	schein.light_energy = 1.1
	schein.omni_range = 9.0
	schein.shadow_enabled = false
	schein.position = Vector3(0.0, 1.0, front * CityCarFeel.CAR_SCALE + 2.5)
	add_child(schein)
	_licht_nodes.append(schein)


func _physics_process(delta: float) -> void:
	update_fahrt(delta)


## set_steer-Kontrakt (Web): v −1 (schirm-links) … +1 (schirm-rechts).
func set_steer(v: float) -> void:
	_steer = clampf(v, -1.0, 1.0)


func set_brake(on: bool) -> void:
	_braking = on


## Rückwärtsgang (NEU M1): solange an, fährt das Auto langsam rückwärts.
func set_reverse(on: bool) -> void:
	_reverse = on


func set_frozen(on: bool) -> void:
	frozen = on


func teleport(x: float, z: float, neues_heading := NAN) -> void:
	position = Vector3(x, CityCarFeel.ROAD_Y, z)
	if not is_nan(neues_heading):
		heading = neues_heading
	speed = 0.0
	_ramp_time = 0.0
	_stuck_t = 0.0
	_prev_xz = Vector2(x, z)
	rotation.y = heading


func steering() -> Dictionary:
	return {"raw": _steer, "smoothed": _steer_smoothed}


## Ein Fahr-Schritt (aus _physics_process; Tests rufen es direkt mit dt).
func update_fahrt(dt: float) -> void:
	if dt <= 0.0:
		return
	if frozen:
		speed = maxf(0.0, speed - CityCarFeel.BRAKE_DECEL * dt)
		rotation.y = heading
		return
	if _reverse:
		_schritt_rueckwaerts(dt)
	else:
		_schritt_vorwaerts(dt)
	_kollidiere()
	_stuck_watchdog(dt)
	_prev_xz = Vector2(position.x, position.z)
	rotation.y = heading


## Steht das Auto auf (bzw. nah genug an) einem Park-Pad? (XZ-Distanz)
func auf_parkpad() -> bool:
	var xz := Vector2(position.x, position.z)
	for pad in park_pads:
		if xz.distance_to(Vector2(pad.x, pad.z)) <= park_pad_radius:
			return true
	return false


func _schritt_vorwaerts(dt: float) -> void:
	_ramp_time += dt
	var target := CityCarFeel.target_speed(_ramp_time)
	speed = CityCarFeel.step_speed(speed, target, _braking, dt, _braking and auf_parkpad())
	if _braking and speed <= 0.0:
		# W18/4-B12: Voll-Stopp auf dem Pad — ein stehendes Auto lenkt nicht,
		# der Spur-Assist zieht es nicht mehr seitwärts Richtung Fahrspur.
		speed = 0.0
		return
	_steer_smoothed = CityCarFeel.smooth_steer(_steer_smoothed, _steer, dt)
	var damp := CityCarFeel.speed_damp(speed)
	# Die EINE Negation (§G3.1-a): steer +1 = schirm-rechts ⇒ heading −.
	heading += CityCarFeel.steer_yaw_rate(-_steer_smoothed, CityCarFeel.STEER_RATE, damp) * dt
	heading = CityCarFeel.wrap_angle(heading)
	_spur_assist(dt)
	position.x += sin(heading) * speed * dt
	position.z += cos(heading) * speed * dt


func _schritt_rueckwaerts(dt: float) -> void:
	_ramp_time = 0.0
	speed = minf(CityCarFeel.REVERSE_SPEED, speed + CityCarFeel.REVERSE_ACCEL * dt)
	_steer_smoothed = CityCarFeel.smooth_steer(_steer_smoothed, _steer, dt)
	# Rückwärts: gleiche Schirm-Konvention (Heck schwenkt zur Daumen-Seite).
	heading += CityCarFeel.steer_yaw_rate(_steer_smoothed, CityCarFeel.STEER_RATE, 0.85) * dt
	heading = CityCarFeel.wrap_angle(heading)
	position.x -= sin(heading) * speed * dt
	position.z -= cos(heading) * speed * dt


## Spur-Assist-Feder (§C7.2): sanft Richtung Kardinale + Spurmitte; hart aus
## bei ≥ 40 % Auslenkung. Kachel-Lattice ist um die Weltmitte zentriert —
## Spurmitte = Kachelmitte ± LANE_OFFSET_M (Rechtsverkehr).
func _spur_assist(dt: float) -> void:
	var kardinale := roundf(heading / (PI / 2.0)) * (PI / 2.0)
	var diff := CityCarFeel.wrap_angle(kardinale - heading)
	var rate := CityCarFeel.assist_rate(diff, _steer)
	if rate == 0.0:
		return
	heading += signf(diff) * minf(absf(diff), absf(rate) * dt)
	var tile_m := 20.0
	var center_x := roundf(position.x / tile_m) * tile_m
	var center_z := roundf(position.z / tile_m) * tile_m
	var dir_idx := wrapi(roundi(kardinale / (PI / 2.0)), 0, 4)
	var k := minf(1.0, CityCarFeel.LANE_LATERAL_RATE * CityCarFeel.assist_fade(diff) * dt)
	var lane := CityCarFeel.LANE_OFFSET_M
	match dir_idx:
		0:
			position.x += (center_x - lane - position.x) * k
		1:
			position.z += (center_z + lane - position.z) * k
		2:
			position.x += (center_x + lane - position.x) * k
		_:
			position.z += (center_z - lane - position.z) * k


## Weiche AABB-Kollisionen (Web collide()): rausdrücken, sliden, einmaliger
## Tempoverlust pro Kontakt-Episode.
func _kollidiere() -> void:
	var hit := false
	if absf(position.x) > welt_halb.x:
		position.x = signf(position.x) * welt_halb.x
		hit = true
	if absf(position.z) > welt_halb.y:
		position.z = signf(position.z) * welt_halb.y
		hit = true
	var r := CityCarFeel.CAR_RADIUS_M
	for b in colliders:
		var cx := clampf(position.x, float(b["min_x"]), float(b["max_x"]))
		var cz := clampf(position.z, float(b["min_z"]), float(b["max_z"]))
		var dx := position.x - cx
		var dz := position.z - cz
		var d2 := dx * dx + dz * dz
		if d2 >= r * r:
			continue
		hit = true
		if d2 > 0.000001:
			var d := sqrt(d2)
			position.x += dx / d * (r - d)
			position.z += dz / d * (r - d)
		else:
			# W18/4-B12: Zentrum IM Kollider — sanft durch die NÄCHSTE
			# Seite raus statt pauschal nach Westen (der pauschale
			# `min_x - r`-Sprung war der 16-m-Punch durch die POW-Front).
			var west := position.x - float(b["min_x"])
			var ost := float(b["max_x"]) - position.x
			var nord := position.z - float(b["min_z"])
			var sued := float(b["max_z"]) - position.z
			var nah := minf(minf(west, ost), minf(nord, sued))
			if nah == west:
				position.x = float(b["min_x"]) - r
			elif nah == ost:
				position.x = float(b["max_x"]) + r
			elif nah == nord:
				position.z = float(b["min_z"]) - r
			else:
				position.z = float(b["max_z"]) + r
	if hit and not _wall_contact:
		speed *= CityCarFeel.WALL_SPEED_MULT
		wall_hit.emit()
	_wall_contact = hit


## Wedge-Watchdog (Web F4 P1-1): Throttle drückt, Position steht → stuck.
func _stuck_watchdog(dt: float) -> void:
	var moved := Vector2(position.x, position.z).distance_to(_prev_xz)
	var steht := moved < CityCarFeel.STUCK_MAX_MOVE_SPEED * dt
	if not _braking and not _reverse and speed > CityCarFeel.STUCK_MIN_CMD_SPEED and steht:
		_stuck_t += dt
		if _stuck_t >= CityCarFeel.STUCK_TRIGGER_SEC:
			_stuck_t = 0.0
			stuck.emit()
	else:
		_stuck_t = 0.0
