class_name ShakeSecret
extends Node
## Schüttel-Secret (W13B GESCHICHTEN, Doc F §5): liest im Haus das
## Accelerometer (`Input.get_accelerometer()` — auf iOS echt, sonst
## Vector3.ZERO) und eskaliert über die pure ShakeLogic in 3 Stufen:
##   1  Haus wackelt — Kamera-Mikro-Wackeln, Staub-Partikel von der Decke,
##      Möbel-Klirr-SFX, Gooby guckt erschrocken („?!“-Bubble).
##   2  Stärker — Gooby duckt sich und krallt sich am Boden fest
##      (grip_floor-Rig-Clip, seit W13C statt Kipp-Transform-Hack).
##   3  Fake-Ragdoll-Flug (Positions-Tween durchs Zimmer + panischer
##      ragdoll_flail-Rig-Clip, seit W13C statt rotation:x-Spin) + witziger
##      Schrei, danach Beschwerde-Bubble und nach
##      5 s wieder happy. Reduced Motion: Stufe 3 ohne Flug, nur Bubble.
## Counter `shakes` (Stufe 1 je Episode) und `shakeStage3` laufen über den
## bestehenden achievements.counters-Mechanismus (Sticker-Request s.
## W13-requests.md). Cooldown 10 min nach Stufe 3 — zeitinjiziert über
## `ingest(accel, dt, now_ms)`, das Tests direkt mit synthetischen
## Sequenzen füttern. Einbau: home_entry._on_travel_finished → attach_to.

const COMPLAIN_S := 5.0
const FLIGHT_HOP_S := 0.45

var logic := ShakeLogic.new()
## Testbar/injizierbar: liefert das aktuelle Accelerometer-Sample.
var accel_provider: Callable = Callable()
var rng := RandomNumberGenerator.new()

var _room: Node
var _episode_stage := 0
var _last_stage3_ms := 0
var _busy := false
var _grip_active := false


## An einen Raum hängen (idempotent pro Raum — Muster InteractablesHost).
static func attach_to(room: Node) -> ShakeSecret:
	var existing := room.get_node_or_null("ShakeSecret")
	if existing is ShakeSecret:
		return existing
	var secret := ShakeSecret.new()
	secret.name = "ShakeSecret"
	room.add_child(secret)
	secret.setup(room)
	return secret


## Episoden-Zähler (Stufe 1 erreicht) — Sticker/Recap lesen ihn.
static func mark_shake(gs: Object) -> void:
	_bump_counter(gs, "shakes")


## Volle Eskalation (Stufe 3) — Grundlage des Sticker-Requests.
static func mark_stage3(gs: Object) -> void:
	_bump_counter(gs, "shakeStage3")


func setup(room: Node) -> void:
	_room = room
	rng.randomize()


func _process(delta: float) -> void:
	ingest(_read_accel(), delta, _now_ms())


## Kernpfad (headless testbar): Sample + Zeit rein, Episoden-Stufe raus.
## Feuert beim Hochschalten die Stufen-Inszenierung; im 10-min-Cooldown
## nach Stufe 3 (zeitinjiziert) bleibt alles still.
func ingest(accel: Vector3, dt: float, now_ms: int) -> int:
	if _busy:
		return _episode_stage
	if not ShakeLogic.cooldown_ready(_last_stage3_ms, now_ms):
		logic.reset()
		return 0
	if _room != null and _room.has_method("is_build_mode_active") and _room.is_build_mode_active():
		return _episode_stage
	var stage := logic.feed(accel, dt)
	# Lokale Laufvariable: Stufe 3 kann _episode_stage synchron auf 0
	# zurücksetzen (kein Gooby/Reduced Motion) — die Member-Variable in der
	# Schleifenbedingung wäre dann eine Endlos-Eskalation.
	var reached := _episode_stage
	while reached < stage:
		reached += 1
		_episode_stage = reached
		_enter_stage(reached, now_ms)
	if stage == 0 and _episode_stage > 0 and not _busy:
		_calm_down()
	return _episode_stage


func cooldown_until_ms() -> int:
	return 0 if _last_stage3_ms <= 0 else _last_stage3_ms + ShakeLogic.COOLDOWN_MS


# ── Stufen-Inszenierung ──────────────────────────────────────────────────────


func _enter_stage(stage: int, now_ms: int) -> void:
	match stage:
		1:
			ShakeSecret.mark_shake(_game_state())
			_fx_stufe1()
		2:
			_fx_stufe2()
		3:
			ShakeSecret.mark_stage3(_game_state())
			_last_stage3_ms = now_ms
			logic.reset()
			_fx_stufe3()


## Stufe 1: Mikro-Wackeln + Deckenstaub + Möbel-Klirr, Gooby erschrickt.
func _fx_stufe1() -> void:
	AudioDirector.try_play(self, "gvz_balloon")
	_camera_wobble(0.035, 5)
	_dust_burst(24)
	var gooby := _gooby()
	if gooby != null and gooby.get("rig") != null:
		gooby.rig.set_emotion("scared")
	_say(I18nService.t("shake.stufe1"))


## Stufe 2: kräftiger — Gooby wirft sich hin und krallt sich am Boden fest.
func _fx_stufe2() -> void:
	AudioDirector.try_play(self, "mg_spill")
	_camera_wobble(0.07, 8)
	_dust_burst(40)
	var gooby := _gooby()
	if gooby != null:
		gooby.cancel_walk()
		gooby.set_wander_enabled(false)
		# W13C (Request CLIPS): echter grip_floor-Loop (geduckt, Pfoten
		# krallen, Ohren flach) statt des manuellen Kipp-Transform-Hacks.
		if gooby.get("rig") != null:
			gooby.rig.set_emotion("scared")
			gooby.rig.play_clip("grip_floor")
		_grip_active = true
	_say(I18nService.t("shake.stufe2"))


## Stufe 3: Fake-Ragdoll-Flug + Schrei, Beschwerde, nach 5 s wieder happy.
## Reduced Motion: kein Flug, nur Bubble (+ Counter/Cooldown wie sonst).
func _fx_stufe3() -> void:
	_busy = true
	var gooby := _gooby()
	if gooby == null or not is_inside_tree():
		_finish_stage3(null)
		return
	_release_grip(gooby)
	if _reduced_motion():
		_say(I18nService.t("shake.beschwerde"))
		await get_tree().create_timer(COMPLAIN_S).timeout
		_finish_stage3(gooby)
		return
	_say(I18nService.t("shake.schrei"))
	AudioDirector.try_play(self, "pet_squish", 1.5)
	_camera_wobble(0.1, 10)
	await _flight(gooby)
	AudioDirector.try_play(self, "gvz_boom")
	if gooby.get("rig") != null:
		gooby.rig.set_emotion("dizzy")
	_say(I18nService.t("shake.beschwerde"))
	if is_inside_tree():
		await get_tree().create_timer(COMPLAIN_S).timeout
	_finish_stage3(gooby)


## Wirbel durchs Zimmer: 2 Zufallspunkte + Rückkehr, Rig dreht Loopings —
## dasselbe Tween-Fake-Tumble-Muster wie beim Kleber-Stuhl-Event.
func _flight(gooby: Node3D) -> void:
	var start: Vector3 = gooby.global_position
	var rig: Node3D = gooby.get("rig")
	# W13C (Request CLIPS): panisches ragdoll_flail-Rudern statt des
	# rotation:x-Spin-Tweens; _finish_stage3 holt via „idle" zurück.
	if rig != null:
		rig.play_clip("ragdoll_flail")
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for hop in 2:
		var ziel := start + _flight_offset()
		tw.tween_property(gooby, "global_position", ziel, FLIGHT_HOP_S)
		tw.tween_callback(func() -> void: AudioDirector.try_play(self, "gvz_pop"))
	tw.tween_property(gooby, "global_position", start, FLIGHT_HOP_S)
	await tw.finished


func _flight_offset() -> Vector3:
	return Vector3(
		rng.randf_range(-1.4, 1.4), rng.randf_range(0.9, 1.8), rng.randf_range(-1.0, 1.0)
	)


func _finish_stage3(gooby: Node) -> void:
	if gooby != null:
		_release_grip(gooby)
		if gooby.get("rig") != null:
			gooby.rig.set_emotion("happy")
		gooby.play_clip("idle")
		gooby.set_wander_enabled(true)
		_say(I18nService.t("shake.wieder_gut"))
	_busy = false
	_episode_stage = 0


## Ruhe vor Stufe 3: Episode klingt still ab, Gooby rappelt sich auf.
func _calm_down() -> void:
	_episode_stage = 0
	var gooby := _gooby()
	if gooby == null:
		return
	_release_grip(gooby)
	if gooby.get("rig") != null:
		gooby.rig.set_emotion("happy")
	gooby.set_wander_enabled(true)


func _release_grip(gooby: Node) -> void:
	if not _grip_active:
		return
	_grip_active = false
	# Zurück in den move-State — die Pose kam aus dem grip_floor-Clip,
	# nicht aus Transforms (W13C, Request CLIPS).
	if gooby != null and gooby.get("rig") != null:
		gooby.rig.play_clip("idle")


# ── FX-Bausteine ─────────────────────────────────────────────────────────────


## Kamera-Mikro-Wackeln über h/v_offset (kämpft nicht mit dem CameraRig,
## der nur die Transform fährt). Reduced Motion: aus.
func _camera_wobble(strength: float, pulses: int) -> void:
	if not is_inside_tree() or _reduced_motion():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var base_h := camera.h_offset
	var base_v := camera.v_offset
	var tw := create_tween()
	for pulse in pulses:
		var off_h := base_h + rng.randf_range(-strength, strength)
		var off_v := base_v + rng.randf_range(-strength, strength)
		tw.tween_property(camera, "h_offset", off_h, 0.05)
		tw.parallel().tween_property(camera, "v_offset", off_v, 0.05)
	tw.tween_property(camera, "h_offset", base_h, 0.08)
	tw.parallel().tween_property(camera, "v_offset", base_v, 0.08)


## Staub rieselt von der Decke (EIN one-shot GPUParticles3D, Mobile-Budget;
## Muster wetter_fx). Zentriert über Gooby, sonst über der Raummitte.
func _dust_burst(amount: int) -> void:
	if _reduced_motion():
		return
	var mount := _room as Node3D
	if mount == null:
		return
	var dust := GPUParticles3D.new()
	dust.name = "ShakeStaub"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(2.2, 0.05, 1.8)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 8.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.6
	mat.gravity = Vector3(0.0, -2.5, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	dust.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.albedo_color = Color(0.87, 0.8, 0.68, 0.7)
	quad.material = quad_mat
	dust.draw_pass_1 = quad
	dust.amount = amount
	dust.lifetime = 1.6
	dust.one_shot = true
	dust.explosiveness = 0.85
	var gooby := _gooby()
	var center := Vector3.ZERO if gooby == null else (gooby as Node3D).position
	dust.position = Vector3(center.x, 2.6, center.z)
	mount.add_child(dust)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)


# ── Helfer ───────────────────────────────────────────────────────────────────


static func _bump_counter(gs: Object, key: String) -> void:
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var counters: Variant = state.get("achievements", {}).get("counters")
			if counters is Dictionary:
				counters[key] = int(counters.get(key, 0)) + 1
	)
	gs.notify_slice_changed("achievements")


func _read_accel() -> Vector3:
	if accel_provider.is_valid():
		return accel_provider.call()
	return Input.get_accelerometer()


func _now_ms() -> int:
	var gs := _game_state()
	if gs != null and gs.get("clock") != null:
		return gs.clock.now_ms()
	return int(Time.get_unix_time_from_system() * 1000.0)


func _game_state() -> Object:
	if _room != null and _room.has_method("game_state"):
		return _room.game_state()
	return get_node_or_null("/root/GameState")


func _gooby() -> Node:
	if _room != null and _room.has_method("gooby"):
		return _room.gooby()
	return null


func _say(text: String) -> void:
	if _room != null and _room.has_method("say"):
		_room.say(text)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()
