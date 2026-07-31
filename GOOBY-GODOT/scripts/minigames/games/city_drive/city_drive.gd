extends MinigameBase
## City Drive / Einkaufsfahrt (cityDrive) als ARCADE-Runde (W13B/DRIVE) —
## die Godot-Fassung des §C4.7-Münzlaufs aus GOOBY/src/minigames/games/
## cityDrive.js. MECHANIK-Zahlen aus CityDriveLogic (Web-verbatim wo es Web-
## Zahlen gibt, Ableitungen dort dokumentiert): 90 s freie Fahrt, 26 aktive
## Münzen (+10, Respawn), Checkpoint-Ringe (+30, Ankunfts-Semantik der
## Trips), Crash = Tempo × 0.3 + ctx.strike() — der 3. Crash zündet die
## Teleport-Cutscene des HOSTS (Abschlepp-Semantik DRIVE.CRASHES_FOR_TOW).
##
## ECHTES 3D nach dem deliveryRush-Muster (Agent 3D-B): 7×7-Kenney-Stadt,
## Verfolgerkamera, Gooby fährt SICHTBAR auf dem Dach mit. Das FAHRGEFÜHL
## nutzt die CityCarFeel-Mathe (Tempo-Dämpfung der Lenkung) plus die
## Web-Arcade-Rampe 9 → 15 m/s aus der Logik.
##
## AUTOHAUS (Doc G §6): ctx.car (vom Host injiziert) bringt das GEWÄHLTE
## Auto — GLB + Karosseriefarbe für die Optik, CarStatsLogic-Multiplikatoren
## (Tempo/Lenkung/Boost) über Logic.with_car in die Fahrparameter.
##
## KEIN Screenshake beim Fahren (Motion-Comfort-Regel) — Crashes bekommen
## Frame-Freeze, Randblitz und eine Gooby-Grimasse.

const Logic := preload("res://scripts/minigames/games/city_drive/city_drive_logic.gd")
const World := preload("res://scripts/minigames/games/city_drive/city_drive_world.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAR_DIR := "res://assets/city/autos"
const FALLBACK_CAR_GLB := "sedan.glb"
## Fahrzeugmaße in Weltmetern (Spielerauto + Verkehr).
const CAR_WIDTH_M := 2.8
const TRAFFIC_HIT_M := 3.2
const TRAFFIC_BASE := 5
const TRAFFIC_SPEED := 6.5
## Ringstraßen-Geometrie des 7×7-Rasters: Ringkante bei ±40 m.
const RING_M := 40.0
const RING_LAP_M := 320.0
const CROSS_LAP_M := 160.0
## Verfolgerkamera (Meter hinter/über dem Wagen) — deliveryRush-Muster.
const CAM_BACK := 10.5
const CAM_LIFT := 5.2
const CAM_LOOK_AHEAD := 9.0
const CAM_PORTRAIT_LIFT := 2.2
const CAM_PORTRAIT_BACK := 1.5
const CAM_PORTRAIT_AHEAD := 3.0
const CAM_PORTRAIT_AIM_DOWN := 1.4
const HFOV_BASE := 84.0
const HFOV_KICK := 7.0
const STREAK_RATE: Array = [[8.0, 0.0], [11.0, 5.0], [15.0, 11.0]]
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
const HINT_FADE_SEC := 7.0
const GOOBY_H := 1.7
## Autopilot (nur Screenshots/Zertifizierung): so scharf zielt er.
const BOT_STEER_GAIN := 1.6

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var pickups := 0
var checkpoints := 0
var crashes := 0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false
## Für Screenshot-/Zertifizierungsläufe: der Autopilot jagt Münzen.
var autoplay := false

var van_pos := Vector2.ZERO
var van_heading := 0.0
var van_speed := 0.0
var steer := 0.0

var _colliders: Array[Dictionary] = []
var _coins: Array[Vector2] = []
var _checkpoint := Vector2.ZERO
var _traffic: Array[Dictionary] = []
var _crash_cool := 0.0
var _ui := 1.0
var _time_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0
var _stage: Node3D
var _world: Node3D
var _van: Node3D
var _gooby: Node3D
var _ring: Node3D
var _streaks: MultiMeshInstance3D
var _pop: GPUParticles3D
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_ready := false


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.ARCADE, ctx.difficulty)
	tune = Logic.with_car(tune, ctx.car.get("mults"))
	rng = ctx.rng()
	_colliders = Logic.layout_colliders()
	_coins = Logic.scatter_coins(rng, int(tune["COINS_ACTIVE"]))
	# Start unten auf der Ringstraße, Blick nach Osten.
	van_pos = Vector2(0.0, RING_M)
	van_heading = PI * 0.5
	_checkpoint = Logic.next_checkpoint(rng, van_pos)
	_spawn_traffic()
	_build_stage()
	_build_hud()
	_sync_world(0.0)
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.call("apply_size", view_size)
	_layout_hud()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	_crash_cool = maxf(0.0, _crash_cool - delta)
	if autoplay:
		_autopilot()
	_step_van(delta)
	_step_traffic(delta)
	_check_pickups()
	_check_checkpoint()
	_update_labels()
	_fade_hint()
	if Logic.round_over(elapsed, tune):
		_finish_time_up()
		return
	_sync_world(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		steer = _steer_from(event.position) if event.pressed else 0.0
	elif event is InputEventScreenDrag:
		steer = _steer_from(event.position)
	elif event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				steer = -1.0 if event.pressed else 0.0
			KEY_RIGHT, KEY_D:
				steer = 1.0 if event.pressed else 0.0


func _steer_from(pos: Vector2) -> float:
	return clampf((pos.x - view_size.x * 0.5) / (view_size.x * 0.4), -1.0, 1.0)


## Autopilot: jagt die nächste Münze (Checkpoints nimmt er unterwegs mit).
## Greift NUR an `steer` an — dort, wo sonst der Finger liegt.
func _autopilot() -> void:
	var target := _nearest_coin()
	var to := target - van_pos
	if to.length() < 0.5:
		return
	var want := atan2(to.x, -to.y)
	var diff := wrapf(want - van_heading, -PI, PI)
	steer = clampf(diff * BOT_STEER_GAIN, -1.0, 1.0)


func _nearest_coin() -> Vector2:
	var best := _checkpoint
	var best_d := van_pos.distance_to(_checkpoint)
	for coin in _coins:
		var d := van_pos.distance_to(coin)
		if d < best_d:
			best_d = d
			best = coin
	return best


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Dasselbe Web-ABENDBAND wie die deliveryRush-Stadt
				# (CITY_BANDS.dusk stammt aus cityDrive.js selbst).
				"sky_top": Color(0.86, 0.63, 0.55),
				"sky_horizon": Color(0.933, 0.706, 0.576),
				"ground_horizon": Color(0.72, 0.63, 0.55),
				"ground_bottom": Color(0.4, 0.42, 0.4),
				"fog_color": Color(0.933, 0.706, 0.576),
				"fog_from": 55.0,
				"fog_to": 140.0,
				"glow": 0.32,
				"sun_dir": Vector3(-0.5, -0.5, -0.7),
				"sun_color": Color(1.0, 0.855, 0.706),
				"sun_energy": 0.72,
				"ambient_color": Color(0.9, 0.79, 0.71),
				"ambient": 1.2,
				"fill_color": Color(0.72, 0.76, 0.92),
				"fill_energy": 0.5,
				"saturation": 1.22,
				"contrast": 1.07,
				"hfov": HFOV_BASE,
				"shadow_distance": 60.0,
				"far": 380.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", _colliders, ctx.rng(), int(tune["COINS_ACTIVE"]))
	_build_car()
	_build_ring()
	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 14, Vector2(3.4, 4.6), Vector2(6.0, 14.0), Vector2(0.045, 1.0))
	_pop = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.85, 0.4, 1.0),
				"amount": 20,
				"lifetime": 0.8,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(2.0, 5.0),
				"spread": 180.0,
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.12, 0.3),
			}
		)
	)
	_stage.add_child(_pop)


## Spielerauto = das GEWÄHLTE Autohaus-Auto (ctx.car: glb + farbe), Fallback
## Start-Sedan. Gooby thront sichtbar auf dem Dach (deliveryRush-Muster).
func _build_car() -> void:
	_van = Node3D.new()
	_stage.add_child(_van)
	var glb := "%s/%s" % [CAR_DIR, str(ctx.car.get("glb", FALLBACK_CAR_GLB))]
	if not ResourceLoader.exists(glb):
		glb = "%s/%s" % [CAR_DIR, FALLBACK_CAR_GLB]
	var body := Models.node(glb, CAR_WIDTH_M, true)
	_tint_car(body, str(ctx.car.get("farbe", "")))
	_van.add_child(body)
	var size := Models.fitted_size(glb, CAR_WIDTH_M)
	_gooby = GoobyMount.new()
	_gooby.call("mount", GOOBY_H, true, false)
	_gooby.position = Vector3(0.0, size.y * 0.99, -size.z * 0.18)
	_van.add_child(_gooby)


## Karosserie-Tint wie im Autohaus (city_bau.faerbe-Muster): Material-
## Duplikate aller Meshes Richtung Wagenfarbe lerpen.
func _tint_car(node: Node3D, hex: String) -> void:
	if hex.is_empty():
		return
	var farbe := Color.from_string(hex, Color.WHITE)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.65)
				mi.set_surface_override_material(i, kopie)


## Checkpoint-Ring: rosa Reifen + Lichtsäule (Gold gehört den Münzen).
func _build_ring() -> void:
	_ring = Node3D.new()
	_stage.add_child(_ring)
	var radius := float(tune["CHECKPOINT_RADIUS_M"])
	var torus := Fx.ring(radius, 0.42, Color(0.95, 0.36, 0.62))
	torus.rotation_degrees.x = -90.0
	torus.position.y = 0.2
	_ring.add_child(torus)
	var beam := CylinderMesh.new()
	beam.top_radius = radius * 0.82
	beam.bottom_radius = radius * 0.82
	beam.height = 22.0
	beam.radial_segments = 18
	beam.rings = 1
	beam.material = Fx.glass(Color(0.98, 0.5, 0.72, 0.16), true)
	var pillar := MeshInstance3D.new()
	pillar.mesh = beam
	pillar.position.y = 11.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(pillar)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_tint_label(_time_label)
	add_child(_time_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.cityDrive.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint_label(_hint_label)
	add_child(_hint_label)
	_update_labels()


func _tint_label(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.24, 0.16, 0.5))
	label.add_theme_constant_override("outline_size", 7)


func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 46.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _spawn_traffic() -> void:
	var count := MinigameFrameworkLogic.js_round(TRAFFIC_BASE * float(tune["TRAFFIC_DENSITY_MULT"]))
	for i in count:
		(
			_traffic
			. append(
				{
					"s": rng.next() * RING_LAP_M,
					"speed": TRAFFIC_SPEED * (0.8 + rng.next() * 0.5),
					"cross": i % 3 == 2,
					"lane": 2.5 if rng.next() < 0.5 else -2.5,
					"tint": Color(0.85, 0.35, 0.4) if i % 2 == 0 else Color(0.42, 0.62, 0.9),
				}
			)
		)


# ── Simulation ────────────────────────────────────────────────────────────


func _step_van(delta: float) -> void:
	# CityCarFeel-Gefühl: Tempo-Dämpfung der Lenkung + Handling-Multiplikator.
	var damp := CityCarFeel.speed_damp(van_speed)
	van_heading += steer * Logic.steer_rate(tune) * damp * delta
	var target := Logic.target_speed(elapsed, tune)
	var tile := Logic.world_to_tile(van_pos.x, van_pos.y)
	if not Logic.is_road(tile.x, tile.y):
		target *= 0.45
	van_speed = Logic.step_speed(van_speed, target, delta, tune)
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var next_pos := van_pos + dir * van_speed * delta
	if _blocked(next_pos):
		van_speed *= 0.3
		AudioDirector.try_play(self, "mg_junk", 0.9)
	else:
		van_pos = next_pos
	var limit := Logic.TILE_M * (Logic.GRID * 0.5)
	van_pos.x = clampf(van_pos.x, -limit, limit)
	van_pos.y = clampf(van_pos.y, -limit, limit)


func _blocked(pos: Vector2) -> bool:
	for b in _colliders:
		if (
			pos.x > float(b["minX"])
			and pos.x < float(b["maxX"])
			and pos.y > float(b["minZ"])
			and pos.y < float(b["maxZ"])
		):
			return true
	return false


func _step_traffic(delta: float) -> void:
	for car in _traffic:
		car["s"] = fposmod(float(car["s"]) + float(car["speed"]) * delta, RING_LAP_M)
		var p := _traffic_pos(car)
		if _crash_cool <= 0.0 and p.distance_to(van_pos) <= TRAFFIC_HIT_M:
			_crash()


## Position eines Verkehrsautos auf seinem geschlossenen Kurs (Ring ±40 m
## bzw. Kreuzstraße — dasselbe Streckenzug-Muster wie deliveryRush).
func _traffic_pos(car: Dictionary) -> Vector2:
	var lane := float(car["lane"])
	if bool(car["cross"]):
		var s := fmod(float(car["s"]), CROSS_LAP_M)
		var half := CROSS_LAP_M * 0.5
		var x := (s if s <= half else CROSS_LAP_M - s) - RING_M
		return Vector2(x, lane)
	var s2 := float(car["s"])
	var leg := RING_LAP_M * 0.25
	if s2 < leg:
		return Vector2(-RING_M + s2, -RING_M + lane)
	if s2 < leg * 2.0:
		return Vector2(RING_M - lane, -RING_M + (s2 - leg))
	if s2 < leg * 3.0:
		return Vector2(RING_M - (s2 - leg * 2.0), RING_M - lane)
	return Vector2(-RING_M + lane, RING_M - (s2 - leg * 3.0))


func _traffic_dir(car: Dictionary) -> Vector2:
	var probe := {
		"s": fposmod(float(car["s"]) + 0.4, RING_LAP_M), "lane": car["lane"], "cross": car["cross"]
	}
	var step := _traffic_pos(probe) - _traffic_pos(car)
	return step.normalized() if step.length() > 0.001 else Vector2(0.0, 1.0)


## Crash = Web-Abschlepp-Pfad: Tempo × 0.3, 2 s Schonfrist, ctx.strike() —
## der HOST zählt und zündet ab dem 3. Strike die Teleport-Cutscene
## (DRIVE.CRASHES_FOR_TOW). Kein Punktabzug (Web-Parität: Crashes kosten
## im City Drive Zeit + Abschleppen, keine Münzen).
func _crash() -> void:
	_crash_cool = float(tune["CRASH_INVULN_SEC"])
	crashes += 1
	van_speed *= float(tune["CRASH_SPEED_MULT"])
	AudioDirector.try_play(self, "mg_spill", 0.85)
	_gooby.call("emote", "dizzy", 1.5)
	# KEIN Screenshake: Dauerfahrt, Motion-Comfort-Regel.
	if ctx.juice != null:
		ctx.juice.hit_freeze(70)
		ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
		ctx.juice.sfx("game_miss")
	var result := ctx.strike()
	_set_banner(
		I18nService.t(
			"mg.cityDrive.crash", {"n": int(result["strikes"]), "max": int(tune["STRIKE_LIMIT"])}
		)
	)
	if bool(result["teleport"]):
		# Die „Emotion“ der Host-Cutscene: das eingefrorene letzte Bild
		# zeigt Gooby traurig — der Host legt Veil + Text darüber.
		_gooby.call("emote", "sad", 2.5)
		_gooby.call("tick", 0.05)


func _check_pickups() -> void:
	var radius := float(tune["PICKUP_RADIUS_M"])
	for i in _coins.size():
		if van_pos.distance_to(_coins[i]) > radius:
			continue
		var prev := score
		score = Logic.apply_pickup(score, tune)
		pickups += 1
		# Arcade-Respawn (§C4.7): der Slot wandert woandershin.
		var fresh := Logic.scatter_coins(rng, 1)
		var collected := _coins[i]
		_coins[i] = fresh[0] if not fresh.is_empty() else _coins[i]
		AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(mini(pickups, 8)))
		Fx.burst(_pop, Vector3(collected.x, 1.0, collected.y))
		if ctx.juice != null:
			ctx.juice.float_text(
				_project(collected), "+%d" % (score - prev), Color(1.0, 0.82, 0.35)
			)
		ctx.report_score(score, score - prev)


func _check_checkpoint() -> void:
	if van_pos.distance_to(_checkpoint) > float(tune["CHECKPOINT_RADIUS_M"]):
		return
	var prev := score
	score = Logic.apply_checkpoint(score, tune)
	checkpoints += 1
	var reached := _checkpoint
	_checkpoint = Logic.next_checkpoint(rng, van_pos)
	AudioDirector.try_play(self, "mg_win", 1.0 + 0.04 * float(mini(checkpoints, 5)))
	_stage.call("pulse_glow", 1.0)
	_gooby.call("emote", "ecstatic", 1.4)
	Fx.burst(_pop, Vector3(reached.x, 1.2, reached.y))
	if ctx.juice != null:
		ctx.juice.float_text(_project(reached), "+%d" % (score - prev), Color(0.98, 0.5, 0.72))
		ctx.juice.overlay_ring(_project(reached), Color(0.98, 0.5, 0.72), 76.0)
		ctx.juice.hit_freeze(50)
	_set_banner(I18nService.t("mg.cityDrive.checkpoint", {"n": checkpoints}))
	ctx.report_score(score, score - prev)


## Timer abgelaufen (nur Nicht-Endlos): Null-Crash-Bonus, dann Rundenende.
func _finish_time_up() -> void:
	if finished:
		return
	var bonus := Logic.zero_crash_bonus(crashes, tune)
	if bonus > 0:
		var prev := score
		score += bonus
		ctx.report_score(score, score - prev)
		_set_banner(I18nService.t("mg.cityDrive.zero_crash", {"n": bonus}))
	AudioDirector.try_play(self, "mg_win")
	if ctx.juice != null:
		ctx.juice.win_moment()
	finished = true
	running = false
	(
		ctx
		. report_end(
			{
				"score": score,
				"pickups": pickups,
				"checkpoints": checkpoints,
				"crashes": crashes,
				"elapsed": elapsed,
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.6


func _fade_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t("mg.cityDrive.endless_coins", {"n": pickups})
	else:
		_time_label.text = I18nService.t(
			"mg.game.time", {"sec": int(ceil(Logic.time_left(elapsed, tune)))}
		)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


func _sync_world(delta: float) -> void:
	_stage.call("tick", delta)
	_gooby.call("tick", delta)
	_sync_van()
	_sync_traffic()
	_sync_coins()
	_sync_ring()
	_sync_camera(delta)


func _sync_van() -> void:
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var right := Vector3.UP.cross(fwd).normalized()
	var lean := clampf(steer * van_speed / float(tune["MAX_SPEED"]), -1.0, 1.0)
	var basis := Basis(right, Vector3.UP, fwd) * Basis(Vector3.BACK, -lean * 0.06)
	_van.transform = Transform3D(basis, Vector3(van_pos.x, 0.0, van_pos.y))


func _sync_traffic() -> void:
	var prop: Node3D = _world.get("traffic_prop")
	prop.call("begin")
	for car in _traffic:
		var p := _traffic_pos(car)
		var d := _traffic_dir(car)
		var fwd := Vector3(d.x, 0.0, d.y)
		var right := Vector3.UP.cross(fwd).normalized()
		var pose := Transform3D(Basis(right, Vector3.UP, fwd), Vector3(p.x, 0.0, p.y))
		prop.call("push", pose, car["tint"])
	prop.call("flush")


## Münzen drehen sich gemeinsam (ein MultiMesh, ein Draw-Call).
func _sync_coins() -> void:
	var prop: Node3D = _world.get("coin_prop")
	prop.call("begin")
	var spin := Basis(Vector3.UP, elapsed * 2.2)
	var bob := 0.12 * sin(elapsed * 3.0)
	for coin in _coins:
		prop.call("push", Transform3D(spin, Vector3(coin.x, bob, coin.y)))
	prop.call("flush")


func _sync_ring() -> void:
	_ring.position = Vector3(_checkpoint.x, 0.0, _checkpoint.y)
	var pulse := 1.0 + 0.08 * sin(elapsed * 4.0)
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_ring.rotation.y = elapsed * 0.6


func _sync_camera(delta: float) -> void:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var lift := CAM_LIFT + (0.0 if landscape else CAM_PORTRAIT_LIFT)
	var back := CAM_BACK + (0.0 if landscape else CAM_PORTRAIT_BACK)
	var here := Vector3(van_pos.x, 0.0, van_pos.y)
	var wanted := here - fwd * back + Vector3(0.0, lift, 0.0)
	var ahead := CAM_LOOK_AHEAD - (0.0 if landscape else CAM_PORTRAIT_AHEAD)
	var aim_y := 1.6 - (0.0 if landscape else CAM_PORTRAIT_AIM_DOWN)
	var look := here + fwd * ahead + Vector3(0.0, aim_y, 0.0)
	if not _cam_ready:
		_cam_pos = wanted
		_cam_look = look
		_cam_ready = true
	_cam_pos = _cam_pos.lerp(wanted, minf(1.0, delta * 6.0))
	_cam_look = _cam_look.lerp(look, minf(1.0, delta * 9.0))
	cam.position = _cam_pos
	if _cam_pos.distance_to(_cam_look) > 0.05:
		cam.look_at(_cam_look, Vector3.UP)
	var band01 := clampf(van_speed / float(tune["MAX_SPEED"]), 0.0, 1.0)
	_stage.call("set_fov_bonus", HFOV_KICK * band01)
	_streaks.set("enabled", not _reduced_motion())
	_streaks.call("update", delta, van_speed, SpeedLines.rate_at(van_speed, STREAK_RATE))


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


## Weltmeter (x, z) → Bildschirmpixel (für Fließtexte und den Kompass).
func _project(world: Vector2) -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return view_size * 0.5
	return cam.unproject_position(Vector3(world.x, 1.0, world.y))


# ── 2D-Overlay (Kompass zum Checkpoint + Banner) ──────────────────────────


func _draw() -> void:
	_draw_compass()
	_draw_banner()


## Kompass-Pfeil zum Checkpoint-Ring (Verfolgerkamera: der Ring steht oft
## hinter Häusern) — Pfeil in FAHRZEUG-Koordinaten (oben = geradeaus).
func _draw_compass() -> void:
	var to := _checkpoint - van_pos
	if to.length() < 1.0:
		return
	var fwd := Vector2(sin(van_heading), -cos(van_heading))
	var side := Vector2(-fwd.y, fwd.x)
	var local := Vector2(to.dot(side), -to.dot(fwd)).normalized()
	var center := Vector2(view_size.x * 0.5, view_size.y * 0.5)
	var radius := minf(view_size.x, view_size.y) * 0.3
	var tip := center + local * radius
	var perp := Vector2(-local.y, local.x)
	var a := 16.0 * _ui
	draw_colored_polygon(
		PackedVector2Array(
			[
				tip + local * a,
				tip - local * a * 0.5 + perp * a * 0.62,
				tip - local * a * 0.5 - perp * a * 0.62,
			]
		),
		Color(0.98, 0.5, 0.72, 0.92)
	)
	var font := ThemeService.font(700)
	var w := 110.0 * _ui
	draw_string(
		font,
		tip + local * a * 1.5 - Vector2(w * 0.5, 0.0),
		"%d m" % int(to.length()),
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(13, int(18.0 * _ui)),
		Color(1.0, 0.98, 0.92)
	)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.2, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 420.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.22),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(18, int(28.0 * _ui)),
		Color(1.0, 0.99, 0.94, alpha)
	)
