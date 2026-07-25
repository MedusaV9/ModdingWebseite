extends MinigameBase
## Hafen-Hüpfer (harborHopper) — Spiel-Szene. Die GESAMTE Mechanik läuft in
## HarborHopperLogic.HarborEngine (zahlengleich zum Web): Kisten +4, Netzringe
## +2, Bojen/Molen −3 + Slow, Wellenkämme mittig = +30 % für 2 s (kettbar),
## Möwe klaut nach 4 s Spurstillstand, Horn räumt Bojen (2 Ladungen).
##
## ECHTES 3D (Agent 3D-B): ein Morgenkanal als Node3D-Welt mit Verfolger-
## kamera, Kaimauern, Hafenstädtchen, Tiefen-Nebel und dem ECHTEN Gooby-Rig,
## das SICHTBAR im Kenney-Kutter sitzt und mitrollt. Der MinigameBase-Vertrag
## bleibt: Wurzel ist Node2D, die 3D-Welt hängt darunter.
##
## Achsenregel: die Engine zählt `rel = z_objekt − z_boot` nach VORNE positiv,
## Godot schaut nach −z. Der View setzt deshalb world_z = −rel und fasst keine
## Engine-Zahl an. Ziehen nach rechts fährt nach rechts.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `boat_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Boote liefert.

const Logic := preload("res://scripts/minigames/games/harbor_hopper/harbor_hopper_logic.gd")
const World := preload("res://scripts/minigames/games/harbor_hopper/harbor_hopper_world.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const HULL := "res://assets/minigames/harbor_hopper/watercraft-kit/boat-fishing-small.glb"

## Rumpflänge in Metern (Web: `fitModel(hull, 2.1)` = längste Kante).
const HULL_LEN := 2.1
## Verfolgerkamera (Web: 0/3.3/−5.2 mit Blick auf 0/0,8/+7 — hier gespiegelt).
const CAM_HEIGHT := 2.95
const CAM_BACK := 4.5
const CAM_PITCH := 12.5
const CAM_PORTRAIT_LIFT := 0.6
const CAM_PORTRAIT_BACK := 0.9
const CAM_PORTRAIT_PITCH := 3.0
const HFOV_BASE := 90.0
const HFOV_KICK := 9.0
const SPEED_BAND := Vector2(5.5, 9.0)
const STREAK_RATE: Array = [[6.5, 0.0], [8.0, 4.0], [9.5, 8.0]]
## Sichtweite (m) und Nahgrenze (m) — beides in Engine-„rel"-Metern.
const DRAW_FAR_M := 58.0
const DRAW_NEAR_M := -4.5
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Nach so vielen Sekunden blendet der Hinweis aus.
const HINT_FADE_SEC := 6.0
## So viele Kisten passen sichtbar aufs Vordeck.
const DECK_CRATES := 6

## Autohaus-Haken: später vom Host befüllbar.
var boat_skin := ""
var speed_bonus := 0.0

## Für Screenshot-/Zertifizierungsläufe: der §C10.1-Skipper übernimmt.
var autoplay := false

var tune: Dictionary = {}
var engine: RefCounted
var score := 0
var boosts := 0
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _bot: RefCounted
var _drag_x: Variant = null
var _horn_queued := false
var _touch_from := Vector2.ZERO
var _touch_moved := false
var _horn_flash := 0.0
var _gull_t := 0.0
var _gull_mode := ""
var _wake := 0.0
var _ui := 1.0
var _time_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0
var _stage: Node3D
var _world: Node3D
var _boat: Node3D
var _gooby: Node3D
var _gull: Node3D
var _horn_cone: MeshInstance3D
var _deck: Array[MeshInstance3D] = []
var _streaks: MultiMeshInstance3D
var _spray: GPUParticles3D
var _sparkle: GPUParticles3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.HARBOR, ctx.difficulty)
	engine = Logic.HarborEngine.new(ctx.rng(), tune)
	_bot = Logic.Bot.new(tune)
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
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_stat_label.position = Vector2(pad, 44.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2(pad, view_size.y - 44.0 * _ui)
	_hint_label.size = Vector2(maxf(120.0, view_size.x - pad * 2.0), 38.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var dt := minf(delta, float(tune["MAX_DT"]))
	_banner_t = maxf(0.0, _banner_t - dt)
	_horn_flash = maxf(0.0, _horn_flash - dt)
	if _gull_mode != "":
		_gull_t += dt
	var input := _take_input()
	var events: Array = engine.step(input, dt)
	_wake += Logic.speed_of(engine.state, tune) * dt
	for ev: Dictionary in events:
		_handle_event(ev)
	var total := Logic.hopper_score(engine.state, tune)
	if total != score:
		ctx.report_score(total, total - score)
		score = total
	if bool(engine.state["ended"]):
		_finish()
		return
	_update_labels()
	_fade_hint()
	_sync_world(dt)
	queue_redraw()


## Zeigen/Ziehen steuert, Tippen hupt. Im Autoplay fährt der Bot.
func _take_input() -> Dictionary:
	if autoplay:
		var plan: Dictionary = _bot.control(engine.state, engine.items, engine.piers, engine.waves)
		return plan
	var out := {"targetX": _drag_x, "horn": _horn_queued}
	_horn_queued = false
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_from = event.position
			_touch_moved = false
			_steer_to(event.position.x)
		else:
			if not _touch_moved:
				_horn_queued = true
			_drag_x = null
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_touch_from) > 10.0:
			_touch_moved = true
		_steer_to(event.position.x)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_nudge(-1.0)
			KEY_RIGHT, KEY_D:
				_nudge(1.0)
			KEY_SPACE:
				_horn_queued = true


## Welt (x, y, rel_z voraus) → Bildschirmpixel des Viewports.
func project(wx: float, wy: float, rel_z: float) -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return view_size * 0.5
	return cam.unproject_position(Vector3(wx, wy, -rel_z))


func _steer_to(px: float) -> void:
	var nx := clampf(px / maxf(1.0, view_size.x) * 2.0 - 1.0, -1.0, 1.0)
	_drag_x = nx * float(tune["CHANNEL_HALF_W"]) * 1.25


## Tastatur-Komfort: eine Spurbreite nach links/rechts zielen.
func _nudge(dir: float) -> void:
	var half_w := float(tune["CHANNEL_HALF_W"])
	var base := float(_drag_x) if _drag_x != null else float(engine.state["x"])
	_drag_x = clampf(base + dir * half_w * 0.6, -half_w, half_w)


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Morgenhafen: warmer Himmel über türkisem Wasser (§C10.1).
				"sky_top": Color(0.62, 0.86, 0.88),
				"sky_horizon": Color(0.741, 0.91, 0.886),
				# Die UNTERE Himmelshälfte muss den Dunst treffen, nicht das
				# Wasser: `fog_sky_affect` ist 0, der Himmel wird also NICHT
				# eingenebelt. Mit dunklem Teal darunter zog sich quer über den
				# Horizont ein harter dunkler Balken, wo das Wasser aufhört —
				# im Web geht Kanal in Dunst über, ohne sichtbare Kante.
				"ground_horizon": Color(0.741, 0.91, 0.886),
				"ground_bottom": Color(0.68, 0.86, 0.85),
				"fog_color": Color(0.741, 0.91, 0.886),
				"fog_from": 26.0,
				"fog_to": 78.0,
				"glow": 0.34,
				# Web: DirectionalLight(0xFFE3B8, 1.0) bei (−6, 4.5, 10);
				# HemisphereLight(0xD8F5EF, 0x1F5F5C, 1.05) — Mittelwert unten.
				"sun_dir": Vector3(0.55, -0.42, -0.85),
				"sun_color": Color(1.0, 0.89, 0.722),
				"sun_energy": 0.8,
				# Kräftiges Teal im Umgebungslicht kippte die Schattenseiten der
				# Kaimauern ins Olivgrüne — heller und entsättigter halten die
				# Mauern ihren Sandstein, ohne die Morgenstimmung zu verlieren.
				"ambient_color": Color(0.66, 0.8, 0.79),
				"ambient": 1.45,
				"fill_energy": 0.34,
				"fill_color": Color(0.72, 0.88, 0.88),
				# Das Wasser ist UNSHADED, seine Textur trägt exakt den
				# Web-Teal (47, 143, 138). Die Bühnen-Vorgabe (Sättigung 1,14)
				# drückte den Rotkanal davon auf 7 herunter — aus dem ruhigen
				# Hafenwasser wurde grelles Neon-Türkis. 1,0 lässt die gebackene
				# Farbe durch.
				"saturation": 1.0,
				"contrast": 1.0,
				"hfov": HFOV_BASE,
				"shadow_distance": 30.0,
				"far": 260.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", float(tune["CHANNEL_HALF_W"]), float(tune["RING_RADIUS"]))

	_boat = Node3D.new()
	_stage.add_child(_boat)
	# Einpassen nach LÄNGSTER Kante (Web-`fitModel`): der Kutter ist 2,1 m lang.
	# Nach Breite einzupassen blies ihn früher auf halbe Kanalbreite auf.
	var hull := Models.node(HULL, Models.width_for_max(HULL, HULL_LEN), false)
	hull.position.y = 0.32
	# Der Kenney-Rumpf zeigt mit dem Bug nach +z; Godot fährt nach −z, also
	# einmal umdrehen — sonst fährt der Kutter rückwärts durch den Kanal.
	hull.rotation.y = PI
	_boat.add_child(hull)
	_gooby = GoobyMount.new()
	# Gooby SITZT sichtbar im Achterschiff (Web: y 0,55 / z −0,35 bei Fahrt
	# nach +z → hier z +0,35) und schaut mit dem Bug von der Kamera weg.
	# Web: 0,62 m. Aus 5 m Verfolgerdistanz blieb davon ein weißer Punkt übrig —
	# im Kutter darf der Schiffer ruhig comic-groß über der Reling sitzen.
	_gooby.call("mount", 0.86 * float(tune["RENDER_SCALE_MULT"]), true, true)
	_gooby.position = Vector3(0.0, 0.5, 0.28)
	_boat.add_child(_gooby)
	_build_deck_crates()
	_build_gull()
	_build_horn_cone()
	# Die Morgensonne steht flach (Web-Licht bei y = 4,5) — der Kutter warf
	# damit einen riesigen, harten Schlagschatten quer über den halben Kanal.
	# Das Web rendert auf dem Wasser gar keinen Schatten; die Kaimauern
	# behalten ihren, nur das Boot wirft keinen mehr. Aufgeschoben, weil das
	# Gooby-Rig seine Meshes erst in _ready() aus dem GLB einhängt.
	_no_shadow(_boat)
	_no_shadow.call_deferred(_boat)

	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 14, Vector2(2.6, 3.6), Vector2(4.0, 9.0))

	_spray = (
		Fx
		. particles(
			{
				"color": Color(0.86, 0.97, 1.0, 0.85),
				"amount": 26,
				"lifetime": 0.7,
				"speed": Vector2(0.8, 2.2),
				"spread": 34.0,
				"direction": Vector3(0.0, 1.0, 0.6),
				"gravity": Vector3(0.0, -3.4, 0.0),
				"size": Vector2(0.05, 0.14),
			}
		)
	)
	_spray.emitting = true
	_stage.add_child(_spray)
	_sparkle = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.55, 1.0),
				"amount": 14,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(1.2, 3.0),
				"spread": 180.0,
				"gravity": Vector3(0.0, -1.6, 0.0),
				"size": Vector2(0.05, 0.13),
			}
		)
	)
	_stage.add_child(_sparkle)
	_place_camera(0.0)


## Ladung stapelt sich auf dem Vordeck (Web: 6 Kisten, erst sichtbar wenn
## eingesammelt) — der beste Fortschrittsanzeiger, den das Spiel hat.
func _build_deck_crates() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, 0.24, 0.24)
	mesh.material = Fx.flat(Color(0.69, 0.54, 0.41))
	for i in DECK_CRATES:
		var crate := MeshInstance3D.new()
		crate.mesh = mesh
		crate.position = Vector3(
			-0.14 if i % 2 == 0 else 0.14, 0.5 + floorf(float(i) / 2.0) * 0.25, -0.68
		)
		crate.rotation.y = fmod(float(i) * 0.7, 0.5)
		crate.visible = false
		_boat.add_child(crate)
		_deck.append(crate)


## Schattenwurf im ganzen Teilbaum abschalten (auch für später eingehängte
## Kisten reicht ein Aufruf, weil sie schon stehen).
func _no_shadow(node: Node) -> void:
	var geo := node as GeometryInstance3D
	if geo != null:
		geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)


## Möwe: Körper + zwei Flügel, animiert im _sync_gull().
func _build_gull() -> void:
	_gull = Node3D.new()
	_gull.visible = false
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.16
	body_mesh.height = 0.3
	body_mesh.radial_segments = 10
	body_mesh.rings = 6
	body_mesh.material = Fx.flat(Color(0.98, 0.98, 1.0))
	body.mesh = body_mesh
	_gull.add_child(body)
	for side: float in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(0.42, 0.03, 0.16)
		wing_mesh.material = Fx.flat(Color(0.9, 0.92, 0.98))
		wing.mesh = wing_mesh
		wing.position = Vector3(side * 0.27, 0.04, 0.0)
		wing.name = "Wing%d" % (0 if side < 0.0 else 1)
		_gull.add_child(wing)
	var beak := MeshInstance3D.new()
	var beak_mesh := BoxMesh.new()
	beak_mesh.size = Vector3(0.07, 0.05, 0.14)
	beak_mesh.material = Fx.flat(Color(0.98, 0.72, 0.2))
	beak.mesh = beak_mesh
	beak.position = Vector3(0.0, 0.0, -0.18)
	_gull.add_child(beak)
	_stage.add_child(_gull)


## Hupkegel: flaches Dreieck vor dem Bug, blitzt beim Hupen auf.
func _build_horn_cone() -> void:
	var reach := float(tune["HORN_CONE_M"])
	var spread := float(tune["HORN_CONE_SPREAD"])
	var base := float(tune["HORN_CONE_BASE"])
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, Fx.glass(Color(1.0, 0.94, 0.6, 0.3), true))
	var a := Vector3(-base, 0.0, 0.0)
	var b := Vector3(base, 0.0, 0.0)
	var c := Vector3(base + reach * spread, 0.0, -reach)
	var d := Vector3(-base - reach * spread, 0.0, -reach)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(d)
	mesh.surface_end()
	_horn_cone = MeshInstance3D.new()
	_horn_cone.mesh = mesh
	_horn_cone.position.y = 0.25
	_horn_cone.visible = false
	_horn_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_horn_cone)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_tint(_time_label)
	add_child(_time_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	_tint(_stat_label)
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.harborHopper.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint(_hint_label)
	add_child(_hint_label)
	_update_labels()


## Heller Text mit weichem Schattenrand — er liegt auf dem Wasser.
func _tint(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.94))
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.2, 0.3, 0.5))
	label.add_theme_constant_override("outline_size", 7)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _handle_event(ev: Dictionary) -> void:
	var boat_px := project(float(engine.state["x"]), 0.9, 0.0)
	match str(ev["type"]):
		"crate":
			AudioDirector.try_play(self, "mg_good")
			_float("+%d" % int(tune["CRATE_POINTS"]), boat_px, Color(1.0, 0.82, 0.4))
			_pop(0.9)
		"ring":
			AudioDirector.try_play(self, "gvz_collect")
			_float("+%d" % int(tune["RING_POINTS"]), boat_px, Color(0.54, 0.88, 0.82))
			_pop(0.7)
		"bump":
			AudioDirector.try_play(self, "mg_spill")
			_float("%d" % int(tune["BUMP_PENALTY"]), boat_px, Color(1.0, 0.42, 0.42))
			_gooby.call("emote", "dizzy", 1.4)
			if not _reduced_motion():
				Fx.burst(_spray, Vector3(float(engine.state["x"]), 0.3, 0.0))
			if ctx.juice != null:
				# KEIN Screenshake: Dauerfahrt, Motion-Comfort-Regel.
				ctx.juice.hit_freeze(70)
			_set_banner(I18nService.t("mg.harborHopper.bump"))
		"boost":
			boosts += 1
			AudioDirector.try_play(self, "mg_combo")
			_stage.call("pulse_glow", 0.8)
			_gooby.call("emote", "ecstatic", 1.1)
			var chain := int(ev["chain"])
			_set_banner(
				(
					I18nService.t("mg.harborHopper.boost_chain", {"n": chain})
					if chain > 1
					else I18nService.t("mg.harborHopper.boost")
				)
			)
		"buoyCleared":
			AudioDirector.try_play(self, "gvz_wave")
			_horn_flash = 0.5
			_set_banner(I18nService.t("mg.harborHopper.horn", {"n": int(ev["count"])}))
		"hornEmpty":
			AudioDirector.try_play(self, "ui_error")
			_set_banner(I18nService.t("mg.harborHopper.horn_empty"))
		"gullWarn":
			AudioDirector.try_play(self, "mg_junk")
			_gull_mode = "circle"
			_gull_t = 0.0
			_gooby.call("emote", "scared", 1.4)
			_set_banner(I18nService.t("mg.harborHopper.gull_warn"))
		"gullSteal":
			AudioDirector.try_play(self, "mg_lose")
			_gull_mode = "leave"
			_gull_t = 0.0
			_gooby.call("emote", "sad", 1.6)
			_float("-%d" % int(tune["CRATE_POINTS"]), boat_px, Color(1.0, 0.42, 0.42))
			_set_banner(I18nService.t("mg.harborHopper.gull_steal"))
		"gullLeave":
			if _gull_mode == "circle":
				_gull_mode = "leave"
				_gull_t = 0.0
		_:
			pass


## Kleiner Glitzer am Bug beim Einsammeln.
func _pop(strength: float) -> void:
	_stage.call("pulse_glow", strength * 0.5)
	if not _reduced_motion():
		Fx.burst(_sparkle, Vector3(float(engine.state["x"]), 0.7, -0.4))


func _float(text: String, pos: Vector2, color: Color) -> void:
	if ctx.juice != null:
		ctx.juice.float_text(pos, text, color)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	var s: Dictionary = engine.state
	(
		ctx
		. report_end(
			{
				"score": Logic.hopper_score(s, tune),
				"crates": int(s["crates"]),
				"rings": int(s["rings"]),
				"bumps": int(s["bumps"]),
				"steals": int(s["steals"]),
				"boosts": boosts,
				"distanceM": int(floorf(float(s["z"]))),
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _fade_hint() -> void:
	if _hint_label == null:
		return
	var elapsed := float(engine.state["elapsed"])
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


func _update_labels() -> void:
	var s: Dictionary = engine.state
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.harborHopper.bump_count",
			{"n": int(s["bumps"]), "max": int(tune["ENDLESS_BUMP_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(s["elapsed"]))))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t(
		"mg.harborHopper.stats", {"crates": int(s["crates"]), "horn": int(s["hornCharges"])}
	)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


func _sync_world(dt: float) -> void:
	_stage.call("tick", dt)
	_gooby.call("tick", dt)
	(_world.get("band") as RefCounted).call("advance", Logic.speed_of(engine.state, tune) * dt)
	# Das Wasser ist eine feste Fläche — nur die Kräuseltextur läuft mit der
	# gefahrenen Strecke, sonst steht der Kanal beim Fahren still.
	_world.call("scroll_water", float((engine.state as Dictionary)["z"]))
	_sync_boat(dt)
	_sync_props()
	_sync_gull()
	_sync_camera(dt)


func _sync_boat(dt: float) -> void:
	var s: Dictionary = engine.state
	var x := float(s["x"])
	var roll := clampf(float(s["vx"]) / float(tune["MAX_LATERAL_SPEED"]), -1.0, 1.0)
	var bob := 0.045 * sin(_wake * 2.6)
	_boat.position = Vector3(x, 0.05 + bob, 0.0)
	_boat.rotation = Vector3(sin(_wake * 1.7) * 0.02, roll * -0.08, roll * -0.22)
	var iframes := float(s["iframesT"])
	_boat.visible = iframes <= 0.0 or fmod(iframes * 12.0, 2.0) < 1.0
	_spray.global_position = Vector3(x, 0.06, 1.0)
	_horn_cone.visible = _horn_flash > 0.0
	_horn_cone.position.x = x
	if _horn_cone.visible:
		_horn_cone.transparency = clampf(1.0 - _horn_flash / 0.5, 0.0, 0.85)
	_sync_boat_tail(dt)


## Getrennt, damit `_sync_boat` kurz bleibt: Wellenreiten hebt den Bug.
func _sync_boat_tail(dt: float) -> void:
	var boost := float(engine.state["boostT"]) > 0.0
	var lift := 0.06 if boost else 0.0
	_boat.position.y = lerpf(_boat.position.y, _boat.position.y + lift, minf(1.0, dt * 6.0))
	_spray.amount_ratio = 1.0 if boost else 0.55
	var stacked := mini(DECK_CRATES, int(engine.state["crates"]))
	for i in _deck.size():
		_deck[i].visible = i < stacked


func _sync_props() -> void:
	var s: Dictionary = engine.state
	var base_z := float(s["z"])
	var half_w := float(tune["CHANNEL_HALF_W"])
	var t := float(s["elapsed"])
	_world.call("begin_props")
	for item: Dictionary in engine.items:
		if bool(item["gone"]):
			continue
		var rel := float(item["z"]) - base_z
		if rel > DRAW_FAR_M or rel < DRAW_NEAR_M:
			continue
		var bob := sin(t * 2.2 + rel * 0.5) * 0.06
		_world.call("push_item", str(item["type"]), float(item["x"]), -rel, bob, t * 1.4 + rel)
	for pier: Dictionary in engine.piers:
		var prel := float(pier["z"]) - base_z
		if prel > DRAW_FAR_M or prel < DRAW_NEAR_M:
			continue
		_world.call(
			"push_pier",
			float(pier["side"]),
			-prel,
			float(tune["PIER_REACH_M"]),
			float(tune["PIER_DEPTH_M"]),
			half_w
		)
	for wave: Dictionary in engine.waves:
		var wrel := float(wave["z"]) - base_z
		if wrel > DRAW_FAR_M or wrel < DRAW_NEAR_M:
			continue
		_world.call(
			"push_wave",
			-wrel,
			half_w,
			float(wave["sweetX"]),
			float(tune["SWEET_HALF_W"]),
			bool(wave["ridden"])
		)
	_world.call("flush_props")
	(_world.get("band") as RefCounted).call("flush")


func _sync_gull() -> void:
	if _gull_mode == "":
		_gull.visible = false
		return
	var x := float(engine.state["x"])
	_gull.visible = true
	if _gull_mode == "circle":
		_gull.position = Vector3(
			x + cos(_gull_t * 3.0) * 0.9, 1.6 + sin(_gull_t * 3.0) * 0.12, -0.4
		)
	else:
		_gull.position = Vector3(x + _gull_t * 2.2, 1.7 + _gull_t * 1.3, -0.4 - _gull_t * 1.1)
		if _gull_t > 1.6:
			_gull_mode = ""
	var flap := sin(_gull_t * 14.0) * 0.5
	for i in 2:
		var wing := _gull.get_node_or_null(NodePath("Wing%d" % i)) as Node3D
		if wing != null:
			wing.rotation.z = flap * (1.0 if i == 0 else -1.0)


## Verfolgerkamera + §G4.8-Tempojuice.
func _sync_camera(dt: float) -> void:
	var reduced := _reduced_motion()
	var speed := Logic.speed_of(engine.state, tune)
	var jitter := 0.0
	if not reduced and float(engine.state["boostT"]) > 0.0:
		jitter = 0.02
	_place_camera(jitter)
	var band01 := clampf(
		(speed - SPEED_BAND.x) / maxf(0.001, SPEED_BAND.y - SPEED_BAND.x), 0.0, 1.0
	)
	_stage.call("set_fov_bonus", HFOV_KICK * band01)
	_streaks.set("enabled", not reduced)
	_streaks.call("update", dt, speed, SpeedLines.rate_at(speed, STREAK_RATE))


func _place_camera(jitter: float) -> void:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var lift := 0.0 if landscape else CAM_PORTRAIT_LIFT
	var back := 0.0 if landscape else CAM_PORTRAIT_BACK
	var pitch := CAM_PITCH + (0.0 if landscape else CAM_PORTRAIT_PITCH)
	var follow := float(engine.state["x"]) * 0.4
	cam.position = Vector3(
		follow + randf_range(-jitter, jitter),
		CAM_HEIGHT + lift + randf_range(-jitter, jitter),
		CAM_BACK + back
	)
	cam.rotation = Vector3(deg_to_rad(-pitch), 0.0, 0.0)


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


# ── 2D-Overlay (Banner über der 3D-Szene) ────────────────────────────────


func _draw() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 440.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.16),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(18, int(26.0 * _ui)),
		Color(1.0, 0.99, 0.94, alpha)
	)
