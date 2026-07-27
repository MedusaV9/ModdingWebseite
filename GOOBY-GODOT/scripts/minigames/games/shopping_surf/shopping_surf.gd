extends MinigameBase
## Gooby Einkaufs-Surf (shoppingSurf) — Spiel-Szene. Die GESAMTE Mechanik
## läuft über ShoppingSurfRun.step_run(), also bit-genau die Web-Simulation:
## 3 Spuren à 1,6 m, Tempo 8 → 16 m/s, Wagen/Kisten/Passanten/Markisen/
## Pfützen/Bordsteinlücken, Münzen ×2 mit Power-up, Beinahe-Treffer +2,
## 3 Crashes = Aus. Der View füttert nur Eingaben hinein und spielt die
## zurückgelieferten Ereignisse als Klang, Juice und Banner ab.
##
## ECHTES 3D (Agent 3D-B): eine Pastell-Einkaufsstraße als Node3D-Welt mit
## Verfolgerkamera, Kenney-Ladenzeile, Markisen, Straßenmöbel, Tiefen-Nebel
## und dem ECHTEN Gooby-Rig, das wirklich läuft, springt und rutscht.
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter (Godot rendert 3D hinter den CanvasItems, HUD liegt oben).
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `cart_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Fahrzeuge liefert.

const Logic := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_logic.gd")
const Run := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_run.gd")
const World := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_world.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Verfolgerkamera (Web: 0/3.2/−5.5 mit Blick auf 0/1,0/+8 — hier gespiegelt,
## denn die Godot-Logik zählt nach −z). Fester Neigungswinkel statt Blickpunkt:
## so sitzt Gooby hoch- wie querformatig auf derselben Bildhöhe.
const CAM_HEIGHT := 2.5
const CAM_BACK := 5.0
## Aus Web-Position und Blickpunkt sind das ≈ 9° Neigung. Mit 15,5° stand Gooby
## als Fleck in der Bildmitte und darunter lag ein halber Bildschirm Asphalt.
const CAM_PITCH := 10.5
const CAM_PORTRAIT_LIFT := 0.5
const CAM_PORTRAIT_BACK := 0.7
const CAM_PORTRAIT_PITCH := 3.5
## §G4.8-Tempojuice: waagerechter Blickwinkel + Kick über das Tempoband.
## Die Web-Kamera rendert 55° senkrecht auf 16:10 — das sind ≈ 79° waagerecht.
## Mit 92° schrumpfte die Ladenzeile zur Modelleisenbahn.
const HFOV_BASE := 80.0
const HFOV_KICK := 12.0
const SPEED_BAND := Vector2(8.0, 16.0)
const STREAK_RATE: Array = [[10.0, 0.0], [13.0, 5.0], [16.0, 11.0]]
## Sichtweite (m) und Nahgrenze hinter der Kamera.
const DRAW_Z := -62.0
const DRAW_NEAR_Z := 1.4
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Nach so vielen Sekunden blendet der Wisch-Hinweis aus.
const HINT_FADE_SEC := 5.0
## Farbe je Power-up (Würfelfarbe + Glow-Puls).
const POWER_TINT := {
	"magnet": Color(0.55, 0.85, 1.0),
	"x2": Color(1.0, 0.84, 0.36),
	"shield": Color(0.4, 0.72, 0.98),
	"turbo": Color(1.0, 0.62, 0.3),
}

## Autohaus-Haken: später vom Host befüllbar.
var cart_skin := ""
var speed_bonus := 0.0

## Für Screenshot-/Zertifizierungsläufe: der §C8.7-Bot übernimmt.
var autoplay := false

var tune: Dictionary = {}
var run: Dictionary = {}
var score := 0
## Münz-Serie ohne Crash/Pfütze (nur Anzeige/Feel — Combo-Ton steigt mit).
var coin_run := 0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _ui := 1.0
## Kamera-Rückfall mit dem Tempo (Meter, weich) — statt Mikro-Zittern.
var _cam_back_extra := 0.0
## Fahrtwind-Takt (s bis zum nächsten Whoosh) ab hohem Tempoband.
var _wind_t := 0.0
var _swipe_from := Vector2.ZERO
var _swipe_live := false
var _held: Dictionary = {}
var _banner := ""
var _banner_t := 0.0
var _flash_t := 0.0
var _score_label: Label
var _stat_label: Label
var _hint_label: Label
var _stage: Node3D
var _world: Node3D
var _gooby: Node3D
var _shadow: MeshInstance3D
var _shield_vis: MeshInstance3D
var _magnet_vis: MeshInstance3D
var _streaks: MultiMeshInstance3D
var _dust: GPUParticles3D
var _sparkle: GPUParticles3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SURF, ctx.difficulty)
	run = Run.create_run(ctx.rng(), "arcade", tune)
	_build_stage()
	_build_hud()
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
		_place_camera(0.0)
	_layout_labels()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var dt := minf(delta, 0.1)
	_banner_t = maxf(0.0, _banner_t - dt)
	_flash_t = maxf(0.0, _flash_t - dt)
	var input := _take_input()
	_handle_events(Run.step_run(run, dt, input))
	_publish_score()
	_update_labels()
	_fade_hint()
	_sync_world(dt)
	queue_redraw()
	if bool(run["ended"]) and not finished:
		_finish()


## Wischen (Touch) und Pfeiltasten (Desktop/Tests) — beide erzeugen die
## flankengetriggerten Eingabe-Flags, die stepRun erwartet.
func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_from = event.position
			_swipe_live = true
		elif _swipe_live:
			_swipe_live = false
			_resolve_swipe(event.position - _swipe_from)
	elif event is InputEventScreenDrag and _swipe_live:
		var delta: Vector2 = event.position - _swipe_from
		if delta.length() >= 42.0:
			_swipe_live = false
			_resolve_swipe(delta)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_held["left"] = true
			KEY_RIGHT, KEY_D:
				_held["right"] = true
			KEY_UP, KEY_W, KEY_SPACE:
				_held["jump"] = true
			KEY_DOWN, KEY_S:
				_held["slide"] = true


## Welt (x, y, z) → Bildschirmpixel des Viewports (für Float-Texte).
func project(wx: float, wy: float, wz: float) -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return view_size * 0.5
	return cam.unproject_position(Vector3(wx, wy, wz))


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# §C10.1: eigener Look — Pastellrosa statt Renner-Blau (Web: 0xffe1ec).
				"sky_top": Color(1.0, 0.79, 0.87),
				"sky_horizon": Color(1.0, 0.882, 0.925),
				"ground_horizon": Color(0.9, 0.8, 0.82),
				"ground_bottom": Color(0.58, 0.46, 0.51),
				"fog_color": Color(1.0, 0.882, 0.925),
				"fog_from": 30.0,
				"fog_to": 86.0,
				"glow": 0.26,
				# Web: DirectionalLight(0xfff0d8, 0.95) bei (−5, 10, −4);
				# HemisphereLight(0xfff3e6, 0xd9b8c4, 1.05) — Mittelwert als Umgebung.
				"sun_dir": Vector3(0.42, -0.84, 0.34),
				"sun_color": Color(1.0, 0.941, 0.847),
				"sun_energy": 0.95,
				"ambient_color": Color(0.925, 0.86, 0.86),
				"ambient": 1.05,
				"fill_energy": 0.16,
				"fill_color": Color(1.0, 0.86, 0.9),
				"hfov": HFOV_BASE,
				"shadow_distance": 34.0,
				"far": 170.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", float((tune["OBSTACLES"] as Dictionary)["awning"]["gapY"]))

	_gooby = GoobyMount.new()
	_stage.add_child(_gooby)
	_gooby.call("mount", float(tune["STAND_HEIGHT"]) * float(tune["RENDER_SCALE_MULT"]))
	_shadow = Fx.blob_shadow(0.42, 0.32)
	_stage.add_child(_shadow)
	_build_auras()

	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 16, Vector2(2.4, 3.4), Vector2(4.0, 9.0))

	_dust = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.93, 0.9, 0.85),
				"amount": 10,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 0.95,
				"speed": Vector2(1.0, 2.4),
				"spread": 60.0,
				"size": Vector2(0.06, 0.14),
			}
		)
	)
	_stage.add_child(_dust)
	_sparkle = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.86, 0.55, 1.0),
				"amount": 14,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(1.2, 3.2),
				"spread": 180.0,
				"gravity": Vector3(0.0, -1.6, 0.0),
				"size": Vector2(0.05, 0.13),
			}
		)
	)
	_stage.add_child(_sparkle)
	_place_camera(0.0)


func _build_auras() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = Fx.glass(Color(0.39, 0.71, 0.96, 0.26))
	_shield_vis = MeshInstance3D.new()
	_shield_vis.mesh = sphere
	_shield_vis.visible = false
	_shield_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_shield_vis)

	_magnet_vis = Fx.ring(0.95, 0.05, Color(0.45, 0.82, 1.0))
	_magnet_vis.rotation_degrees.x = -90.0
	_magnet_vis.visible = false
	_stage.add_child(_magnet_vis)


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	_tint(_score_label)
	add_child(_score_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	_tint(_stat_label)
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.shoppingSurf.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint(_hint_label)
	add_child(_hint_label)
	_update_labels()


## Heller Text mit weichem Schattenrand — er liegt jetzt auf einer 3D-Szene.
func _tint(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0.28, 0.14, 0.2, 0.62))
	label.add_theme_constant_override("outline_size", 8)


func _layout_labels() -> void:
	if _score_label == null:
		return
	var pad := 14.0 * _ui
	_score_label.position = Vector2(pad, 8.0 * _ui)
	_score_label.add_theme_font_size_override("font_size", int(24.0 * _ui))
	_stat_label.position = Vector2(pad, 42.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(13.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 52.0 * _ui)
	_hint_label.size = Vector2(hint_w, 46.0 * _ui)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _resolve_swipe(delta: Vector2) -> void:
	if delta.length() < 28.0:
		return
	if absf(delta.x) > absf(delta.y):
		_held["right" if delta.x > 0.0 else "left"] = true
	elif delta.y < 0.0:
		_held["jump"] = true
	else:
		_held["slide"] = true


## Gesammelte Flanken abholen (und leeren); im Autoplay fährt der Bot.
func _take_input() -> Dictionary:
	if autoplay:
		return Run.bot_input(run)
	var out := _held
	_held = {}
	return out


func _handle_events(events: Array) -> void:
	for e: Dictionary in events:
		_handle_event(e)


func _handle_event(e: Dictionary) -> void:
	match str(e["type"]):
		"lane":
			AudioDirector.try_play(self, "ui_chip", 1.2)
		"jump":
			AudioDirector.try_play(self, "mg_good", 1.35)
			_gooby.call("play", "hop")
		"slide":
			AudioDirector.try_play(self, "mg_junk", 1.3)
		"coin":
			_on_coin(e)
		"nearMiss":
			_on_near_miss(e)
		"powerup":
			_on_powerup(str(e["kind"]))
		"powerupEnd":
			_set_banner(I18nService.t("mg.shoppingSurf.%s_end" % str(e["kind"])))
		"puddle":
			coin_run = 0
			AudioDirector.try_play(self, "mg_spill", 0.9)
			if ctx.juice != null:
				ctx.juice.sfx("game_miss")
				ctx.juice.show_combo(0)
			_set_banner(I18nService.t("mg.shoppingSurf.puddle"))
			_splash()
		"shieldPop":
			_on_shield_pop()
		"crash":
			_on_crash(int(e["crashes"]))
		"telegraph":
			AudioDirector.try_play(self, "ui_tick", 1.1)
		_:
			pass


func _on_coin(e: Dictionary) -> void:
	coin_run += 1
	# Münz-Serie klettert hörbar die Tonleiter hoch.
	AudioDirector.try_play(self, "mg_good", FeelSfx.combo_pitch(coin_run))
	var at := Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
	if not _reduced_motion():
		Fx.burst(_sparkle, at)
	if ctx.juice == null:
		return
	ctx.juice.float_text(
		project(at.x, at.y + 0.45, at.z), "+%d" % int(e["value"]), Color(1.0, 0.84, 0.42)
	)
	ctx.juice.overlay_ring(project(at.x, at.y + 0.45, at.z), Color(1.0, 0.84, 0.42), 46.0)


func _on_near_miss(e: Dictionary) -> void:
	var streak := int(e["streak"])
	# Beinahe-Treffer-Serie: Ton klettert pro Stufe einen Halbton.
	AudioDirector.try_play(
		self, "mg_combo" if streak > 1 else "mg_perfect", 1.1 * FeelSfx.combo_pitch(streak)
	)
	_set_banner(I18nService.t("mg.shoppingSurf.near", {"streak": streak}))
	_gooby.call("emote", "ecstatic", 0.8)
	if ctx.juice == null:
		return
	ctx.juice.float_text(
		Vector2(view_size.x * 0.5 - 60.0 * _ui, view_size.y * 0.44),
		I18nService.t("mg.shoppingSurf.near_pop"),
		Color(0.72, 1.0, 0.86)
	)
	if streak >= 2:
		ctx.juice.show_combo(streak)
	if streak >= 3:
		_stage.call("pulse_glow", 0.8)
		ctx.juice.edge_glow(0.45, Color(0.72, 1.0, 0.86))


func _on_powerup(kind: String) -> void:
	AudioDirector.try_play(self, "mg_golden")
	_set_banner(I18nService.t("mg.shoppingSurf.%s" % kind))
	_gooby.call("emote", "ecstatic", 1.1)
	_stage.call("pulse_glow", 1.0)
	if not _reduced_motion():
		Fx.burst(_sparkle, Vector3(Run.player_x(run), 1.0, 0.0))
	if ctx.juice != null and kind == "turbo":
		ctx.juice.slowmo(0.55, 220)


func _on_shield_pop() -> void:
	AudioDirector.try_play(self, "mg_junk")
	_set_banner(I18nService.t("mg.shoppingSurf.shield_pop"))
	_flash_t = 0.35
	Fx.burst(_sparkle, Vector3(Run.player_x(run), 0.9, 0.0))
	_stage.call("pulse_glow", 0.7)


func _on_crash(crashes: int) -> void:
	coin_run = 0
	AudioDirector.try_play(self, "mg_spill")
	_flash_t = 0.45
	var left := maxi(0, int(tune["ARCADE_MAX_CRASHES"]) - crashes)
	Fx.burst(_dust, Vector3(Run.player_x(run), 0.25, -0.5))
	if left > 0:
		_set_banner(I18nService.t("mg.shoppingSurf.crash", {"left": left}))
		_gooby.call("emote", "sad", 1.2)
	else:
		_gooby.call("emote", "dizzy", 4.0)
	if ctx.juice == null:
		return
	# Kein Screenshake: der Surf ist ein Dauer-Vorwärtsflug (Motion-Comfort).
	ctx.juice.hit_freeze(110)
	ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
	ctx.juice.sfx("game_miss")
	ctx.juice.show_combo(0)


func _splash() -> void:
	if _reduced_motion():
		return
	Fx.burst(_dust, Vector3(Run.player_x(run), 0.1, -0.3))


func _publish_score() -> void:
	var total := Run.run_score(run)
	if total == score:
		return
	var delta := total - score
	score = total
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_lose")
	var result := Run.run_meta(run)
	result["score"] = Run.run_score(run)
	ctx.report_end(result)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.25


## Der Hinweis steht unten mitten im Bild — nach ein paar Sekunden hat man ihn
## gelesen, danach gehört die Stelle Gooby.
func _fade_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - float(run["elapsed"])) / 1.2, 0.0, 1.0)


func _update_labels() -> void:
	_score_label.text = I18nService.t(
		"mg.shoppingSurf.distance", {"m": int(floor(float(run["distanceM"])))}
	)
	_stat_label.text = (
		I18nService
		. t(
			"mg.shoppingSurf.stats",
			{
				"coins": int(run["coins"]),
				"left": maxi(0, int(tune["ARCADE_MAX_CRASHES"]) - int(run["crashes"])),
				"near": int(run["nearMisses"]),
			}
		)
	)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


func _sync_world(dt: float) -> void:
	_stage.call("tick", dt)
	_gooby.call("tick", dt)
	(_world.get("band") as RefCounted).call("advance", Run.current_speed(run) * dt)
	_sync_player(dt)
	_sync_props()
	_sync_camera(dt)


func _sync_player(dt: float) -> void:
	var px := Run.player_x(run)
	var py := Run.player_y(run)
	var sliding := float(run["slideT"]) >= 0.0
	var squash := float(tune["SLIDE_HEIGHT"]) / float(tune["STAND_HEIGHT"]) if sliding else 1.0
	var target := Vector3(1.0 + (1.0 - squash) * 0.55, squash, 1.0 + (1.0 - squash) * 0.55)
	_gooby.scale = _gooby.scale.lerp(target, minf(1.0, dt * 16.0))
	_gooby.position = Vector3(px, py, 0.0)
	# Körperneigung beim Spurwechsel — deutlich sichtbar, klingt von selbst ab.
	_gooby.rotation.z = (float((tune["LANE_X"] as Array)[int(run["lane"])]) - px) * -0.42
	var invuln := float(run["invulnT"])
	_gooby.visible = invuln <= 0.0 or fmod(invuln * 12.0, 2.0) < 1.0
	_gooby.call("run", 0.0 if sliding else 1.0)
	_shadow.position = Vector3(px, 0.03, 0.0)
	_shadow.scale = Vector3.ONE * maxf(0.45, 1.0 - py * 0.35)
	var pu: Dictionary = run["pu"]
	_shield_vis.visible = bool(pu["shield"])
	_shield_vis.position = Vector3(px, py + 0.55, 0.0)
	_shield_vis.rotation.y += dt * 1.5
	_magnet_vis.visible = float(pu["magnetT"]) > 0.0
	_magnet_vis.position = Vector3(px, py + 0.12, 0.0)
	_magnet_vis.rotation.y += dt * 2.4


func _sync_props() -> void:
	var t := float(run["elapsed"])
	_world.call("begin_props")
	for ob: Dictionary in run["obstacles"]:
		var z := float(ob["z"])
		if z < DRAW_Z or z > DRAW_NEAR_Z:
			continue
		_world.call(
			"push_obstacle",
			str(ob["kind"]),
			float(ob["x"]),
			z,
			float(ob["halfW"]),
			t * 3.0 + z * 0.4
		)
	for c: Dictionary in run["coinItems"]:
		var cz := float(c["z"])
		if cz < DRAW_Z or cz > DRAW_NEAR_Z:
			continue
		_world.call("push_coin", float(c["x"]), float(c["y"]), cz, t * 4.0 + cz * 0.3)
	for p: Dictionary in run["powerupItems"]:
		var pz := float(p["z"])
		if pz < DRAW_Z or pz > DRAW_NEAR_Z:
			continue
		var tint: Color = POWER_TINT.get(str(p["kind"]), Color(1.0, 0.9, 0.6))
		_world.call(
			"push_power", float(p["x"]), 0.6 + sin(t * 3.2 + pz * 0.2) * 0.08, pz, t * 2.0, tint
		)
	_world.call("flush_props")
	(_world.get("band") as RefCounted).call("flush")


## Verfolgerkamera + §G4.8-Tempojuice (FOV-Kick, Streifen, Kamera-Rückfall,
## Fahrtwind). KEIN Zittern/Shake — Motion-Comfort-Regel der Dauerlauf-Spiele.
func _sync_camera(dt: float) -> void:
	var reduced := _reduced_motion()
	var speed := Run.current_speed(run)
	var band01 := clampf(
		(speed - SPEED_BAND.x) / maxf(0.001, SPEED_BAND.y - SPEED_BAND.x), 0.0, 1.0
	)
	_cam_back_extra = lerpf(_cam_back_extra, band01 * 0.85, minf(1.0, dt * 2.5))
	_place_camera(0.0 if reduced else _cam_back_extra)
	_stage.call("set_fov_bonus", HFOV_KICK * band01)
	_streaks.set("enabled", not reduced)
	_streaks.call("update", dt, speed, SpeedLines.rate_at(speed, STREAK_RATE))
	_wind_t -= dt
	if band01 >= 0.5 and _wind_t <= 0.0:
		_wind_t = 1.1 + (1.0 - band01) * 1.6
		FeelSfx.play(self, "game_whoosh", 0.85 + band01 * 0.5)


func _place_camera(back_extra: float) -> void:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var lift := 0.0 if landscape else CAM_PORTRAIT_LIFT
	var back := 0.0 if landscape else CAM_PORTRAIT_BACK
	var pitch := CAM_PITCH + (0.0 if landscape else CAM_PORTRAIT_PITCH)
	var follow := Run.player_x(run) * 0.32
	cam.position = Vector3(
		follow, CAM_HEIGHT + lift + back_extra * 0.22, CAM_BACK + back + back_extra
	)
	cam.rotation = Vector3(deg_to_rad(-pitch), 0.0, 0.0)


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


# ── 2D-Overlay (Powerup-Leiste, Banner, Crash-Blitz über der 3D-Szene) ────


func _draw() -> void:
	_draw_powerup_bar()
	_draw_banner()
	_draw_flash()


func _draw_powerup_bar() -> void:
	var pu: Dictionary = run["pu"]
	var font := ThemeService.font(700)
	var size := maxi(12, int(17.0 * _ui))
	var w := 168.0 * _ui
	var x := view_size.x - w - 14.0 * _ui
	var y := 12.0 * _ui
	var rows: Array[Array] = []
	if float(pu["x2T"]) > 0.0:
		rows.append(["mg.shoppingSurf.x2_short", float(pu["x2T"]), Color(1.0, 0.86, 0.4)])
	if float(pu["magnetT"]) > 0.0:
		rows.append(["mg.shoppingSurf.magnet_short", float(pu["magnetT"]), Color(0.6, 0.88, 1.0)])
	if float(pu["turboT"]) > 0.0:
		rows.append(["mg.shoppingSurf.turbo_short", float(pu["turboT"]), Color(1.0, 0.66, 0.34)])
	for row in rows:
		draw_string(
			font,
			Vector2(x, y + size),
			"%s %.1fs" % [I18nService.t(str(row[0])), float(row[1])],
			HORIZONTAL_ALIGNMENT_RIGHT,
			w,
			size,
			row[2]
		)
		y += size * 1.4


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.5, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 440.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.2),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(16, int(23.0 * _ui)),
		Color(1.0, 0.97, 0.86, alpha)
	)


## Roter Randblitz bei Crash/Schildtreffer — Feedback ohne Vollbild-Overlay.
func _draw_flash() -> void:
	if _flash_t <= 0.0:
		return
	var a := clampf(_flash_t * 1.6, 0.0, 0.55)
	var band := minf(view_size.x, view_size.y) * 0.09
	draw_rect(Rect2(0.0, 0.0, view_size.x, band), Color(0.95, 0.35, 0.4, a))
	draw_rect(Rect2(0.0, view_size.y - band, view_size.x, band), Color(0.95, 0.35, 0.4, a))
