class_name RanchRideController
extends Node3D
## Reit-Controller (RANCH-2): Gooby reitet ein Pferd wie ein sanftes
## Fahrzeug — Gangarten Schritt/Trab/Galopp, Tiefpass-Lenkung, Sprünge,
## Verfolgerkamera mit Tempo-FOV, Kopfnicken, Staubpartikel und Hufschlag-
## Sounds über AudioDirector-Ids. ALLE Mathematik kommt aus RanchRideFeel
## (PURE, getestet); dieser Knoten ist nur die Verdrahtung.
##
## Einbau (RANCH-1): mounten, set_horse()/set_bounds()/set_bindung() rufen,
## optional use_camera=false, HUD-Buttons auf steer_input()/gait_up()/
## gait_down()/jump() verdrahten. Ohne HUD funktioniert die Tastatur
## (Pfeile/WASD, Hoch/Runter = Gangart, Leertaste = Sprung).

signal gait_changed(gait: String)
signal jumped
signal landed

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")

## Eigene Verfolgerkamera bauen (false, wenn die Welt schon eine hat).
@export var use_camera := true
## Tastatur-Direktsteuerung (Demo/Desktop); HUDs rufen die Methoden selbst.
@export var keyboard_input := true

var gait := "stand"
var tempo := 0.0
var heading := 0.0
var ausdauer := Feel.AUSDAUER_MAX
var active := true

var _horse: Node3D
var _steer_target := 0.0
var _steer := 0.0
var _sprung := {"y": 0.0, "vy": 0.0}
var _in_luft := false
var _bounds_center := Vector2.ZERO
var _bounds_half := Vector2(15.0, 15.0)
var _perks := {"tempo_mult": 1.0, "ausdauer_regen_mult": 1.0}
var _camera: Camera3D
var _dust: GPUParticles3D
var _kopf_basis_y := 0.0
var _phase_vorher := 0.0


func _ready() -> void:
	if _horse == null:
		var stub := RanchHorseStub.new()
		add_child(stub)
		set_horse(stub)
	_dust = _build_dust()
	add_child(_dust)
	if use_camera:
		_camera = Camera3D.new()
		_camera.current = true
		get_parent().add_child.call_deferred(_camera)
		_snap_camera.call_deferred()


func _exit_tree() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()


func _process(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	if keyboard_input:
		_poll_keyboard()
	_step_ride(delta)
	_step_visuals(delta)
	if _camera != null:
		_step_camera(delta)


## Pferd-Knoten übernehmen (Vertrag: RanchHorseStub-API). null = Attrappe.
func set_horse(node: Node3D) -> void:
	_horse = node
	if _horse != null and _horse.has_method("head_pivot"):
		var kopf: Node3D = _horse.head_pivot()
		if kopf != null:
			_kopf_basis_y = kopf.position.y


## Reit-Areal (Koppel) setzen: Mitte + Halbausdehnung in Metern (RANCH-1).
func set_bounds(center: Vector3, half: Vector2) -> void:
	_bounds_center = Vector2(center.x, center.z)
	_bounds_half = half


## Bindung des gerittenen Pferds → Tempo-/Ausdauer-Perks (RanchHorseCare).
func set_bindung(bindung: float) -> void:
	_perks = RanchHorseCare.reit_perks(bindung)


## Lenk-Eingabe -1..1 (HUD/Touch); Tastatur überschreibt bei keyboard_input.
func steer_input(value: float) -> void:
	_steer_target = clampf(value, -1.0, 1.0)


func gait_up() -> void:
	_wechsle_gangart(Feel.gangart_hoch(gait))


func gait_down() -> void:
	_wechsle_gangart(Feel.gangart_runter(gait))


## Absprung — nur ab Trab-Tempo und am Boden (Feel.kann_springen).
func jump() -> void:
	if not Feel.kann_springen(tempo, _sprung["y"]):
		return
	_sprung = {"y": 0.001, "vy": Feel.SPRUNG_VY}
	_in_luft = true
	jumped.emit()
	AudioDirector.try_play(self, "ui_open")


func _step_ride(delta: float) -> void:
	ausdauer = Feel.step_ausdauer(ausdauer, gait, delta, float(_perks["ausdauer_regen_mult"]))
	var effektiv := Feel.gangart_nach_ausdauer(gait, ausdauer, gait == "galopp")
	if effektiv != gait:
		gait = effektiv
		gait_changed.emit(gait)
	_steer = Feel.smooth_steer(_steer, _steer_target, delta)
	heading = Feel.wrap_angle(heading - Feel.steer_yaw_rate(_steer, tempo) * delta)
	tempo = Feel.step_tempo(tempo, Feel.zieltempo(gait, float(_perks["tempo_mult"])), delta)
	var vorwaerts := Vector2(sin(heading), cos(heading)) * -1.0
	var pos := Vector2(position.x, position.z) + vorwaerts * tempo * delta
	pos = Feel.clamp_bounds(pos, _bounds_center, _bounds_half)
	if _in_luft:
		_sprung = Feel.step_sprung(_sprung, delta)
		if float(_sprung["y"]) <= 0.0:
			_in_luft = false
			landed.emit()
			AudioDirector.try_play(self, "mg_good", 0.8)
	position = Vector3(pos.x, float(_sprung["y"]), pos.y)
	rotation.y = heading


func _step_visuals(delta: float) -> void:
	if _horse == null:
		return
	if _horse.has_method("set_gait"):
		_horse.set_gait(gait)
	if _horse.has_method("tick"):
		_horse.tick(delta, tempo)
	var phase := _phase_vorher
	if _horse.has_method("phase"):
		phase = float(_horse.phase())
	_spiele_hufschlaege(phase)
	if _horse.has_method("head_pivot"):
		var kopf: Node3D = _horse.head_pivot()
		if kopf != null:
			kopf.position.y = _kopf_basis_y + Feel.kopfnicken(phase, gait)
	_dust.amount_ratio = maxf(0.05, Feel.staub_anteil(gait))
	_dust.emitting = Feel.staub_anteil(gait) > 0.0 and not _in_luft


func _spiele_hufschlaege(phase: float) -> void:
	var schlaege := Feel.hufschlaege(_phase_vorher, phase)
	if phase < _phase_vorher:
		schlaege = Feel.hufschlaege(_phase_vorher, 1.0) + Feel.hufschlaege(0.0, phase)
	_phase_vorher = phase
	if schlaege <= 0 or _in_luft or gait == "stand":
		return
	# Hufschläge über SfxMap-Bestand: Galopp klopft (Holz-Knock), Schritt/
	# Trab tickt leise — eigene ranch_hoof_*-Ids sind bei W4-P1 angefragt.
	var id := "door_knock" if gait == "galopp" else "ui_tick"
	AudioDirector.try_play(self, id, 1.0 + randf_range(-0.04, 0.04))


func _step_camera(delta: float) -> void:
	var hinten := Vector3(sin(heading), 0.0, cos(heading))
	var ziel := position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT, 0.0)
	var f := Feel.cam_follow_factor(delta)
	_camera.position = _camera.position.lerp(ziel, f)
	_camera.look_at(position + Vector3(0.0, 1.2, 0.0) - hinten * 2.0)
	_camera.fov = lerpf(_camera.fov, Feel.fov_fuer_tempo(tempo), f)


func _snap_camera() -> void:
	if _camera == null:
		return
	var hinten := Vector3(sin(heading), 0.0, cos(heading))
	_camera.position = position + hinten * Feel.CAM_BACK + Vector3(0.0, Feel.CAM_HEIGHT, 0.0)
	_camera.look_at(position + Vector3(0.0, 1.2, 0.0))
	_camera.fov = Feel.fov_fuer_tempo(tempo)


func _poll_keyboard() -> void:
	var steer := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		steer -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		steer += 1.0
	_steer_target = steer


func _unhandled_key_input(event: InputEvent) -> void:
	if not keyboard_input or not active:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_UP, KEY_W:
			gait_up()
		KEY_DOWN, KEY_S:
			gait_down()
		KEY_SPACE:
			jump()


func _wechsle_gangart(neu: String) -> void:
	var effektiv := Feel.gangart_nach_ausdauer(neu, ausdauer, gait == "galopp")
	if effektiv == gait:
		return
	gait = effektiv
	gait_changed.emit(gait)


func _build_dust() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 0.7
	particles.emitting = false
	particles.local_coords = false
	particles.position = Vector3(0.0, 0.12, 0.62)
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.6)
	mat.spread = 32.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0.0, -0.4, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(0.76, 0.66, 0.5, 0.55)
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.8, 0.7, 0.55, 0.5)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh
	return particles
