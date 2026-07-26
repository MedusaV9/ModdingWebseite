extends MinigameBase
## Spielzeug-Rennen (toyRacer) — Spiel-Szene. Die GESAMTE Rennmechanik läuft
## in ToyRacerLogic (zahlengleich zum Web): 3 Runden auf einem gesäten
## Spielzeug-Kurs gegen 3 Gummiband-KI-Karts, Halten = Drift laden,
## Loslassen = 1,2 s Schub, Item-Kisten je ⅓ Runde, neben der Strecke 40 %
## langsamer. Punkte = Platzbonus + 2·Überholer + Driftmeter/10.
##
## ECHTES 3D (Agent 3D-B): der Kurs ist der ECHTE Kenney-toy-car-kit-Ring auf
## einem Kinderzimmerboden, die Karts sind car-kit-Modelle und Gooby sitzt
## SICHTBAR im roten Renner. Die Kamera hängt hinterm Kart und schwenkt im
## Looping auf eine feste Stuntkamera daneben — dieselbe Regel wie im Web.
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter (Godot rendert 3D immer hinter den CanvasItems).
##
## KEIN Screenshake (Motion-Comfort-Regel für Fahr-Spiele) — Tempo wird über
## FOV-Kick und Speed-Lines erzählt.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `kart_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Karts liefert.

const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const World := preload("res://scripts/minigames/games/toy_racer/toy_racer_world.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAR_DIR := "res://assets/minigames/toy_racer/car-kit/"
## Fahrzeuge in Startreihenfolge — [0] ist das Spieler-Kart.
const KART_MODELS: Array[String] = [
	CAR_DIR + "race.glb",
	CAR_DIR + "taxi.glb",
	CAR_DIR + "police.glb",
	CAR_DIR + "hatchback-sports.glb",
]

## Verfolgerkamera (Web: 5,8 m hinter, 3,1 m über dem Kart).
const CAM_BACK := 6.0
## Kameraneigung ist hier das ganze Spiel: der Blickwinkel nach unten ist
## atan((LIFT − 0,4) / (BACK + LOOK_AHEAD)). Wird er größer als der halbe
## senkrechte Blickwinkel (~26°), rutscht der HORIZONT aus dem Bild und die
## Szene liest sich als Draufsicht — genau das passierte bei 4,5/4,6. Mit
## 2,8/6,0/1,6 liegt er bei ~18°: Kart unten im Bild, Kurs und Bauklotz-
## Skyline darüber, wie in der Web-Fassung.
const CAM_LIFT := 2.8
const CAM_LOOK_AHEAD := 1.6
## Hochkant ist der senkrechte Blickwinkel doppelt so groß (Stage3D deckelt bei
## 96°). Mit der Querformat-Neigung landete der Horizont bei 40 % Bildhöhe und
## darüber standen zwei Drittel nackte Zimmerwand. Also hochkant HÖHER stehen
## und NÄHER vor das Kart schauen — das kippt die Sicht nach unten auf den Kurs.
const CAM_PORTRAIT_LIFT := 1.7
const CAM_PORTRAIT_AHEAD := -1.1
## Stuntkamera im Looping: so weit seitlich aus der Ringebene heraus. Das Web
## stand 14 m daneben und schaute auf die RINGMITTE — der Ring füllte damit das
## Bild und das Kart schrumpfte auf ein paar Pixel. Wir rücken näher und
## schauen zwischen Ringmitte und Kart: der Ring bleibt lesbar, das Kart (und
## Gooby darin) bleibt groß.
const LOOP_CAM_SIDE := 7.0
const LOOP_CAM_BACK := 1.2
const LOOP_CAM_LIFT := 1.2
## 0 = nur Ringmitte (Web), 1 = nur Kart. Dazwischen schwenkt die Stuntkamera
## dem Kart sanft hinterher, ohne die Ringebene zu kreuzen.
const LOOP_CAM_TRACK := 0.75
## Waagerechter Blickwinkel + Schub-Kick (Web: 58° fov +6).
const HFOV_BASE := 82.0
const HFOV_KICK := 8.0
## Kartbreite in Metern (Web: 0,36 Streckeneinheiten × WORLD_SCALE).
const KART_W := 0.36
## Bildabstand (px bei 1200er Kante), den ein näher stehendes KI-Kart zu Goobys
## Sitz halten muss, damit ein Beweisfoto ihn wirklich zeigt.
const CLEAR_SHOT_PX := 170.0
## Ab dieser waagerechten Tangentenlänge folgt die Kamera dem Kurs wieder
## (im Looping zeigt die Tangente senkrecht — sonst überschlägt sich die Sicht).
const FLAT_TANGENT_MIN := 0.45
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Nach so vielen Sekunden blendet der Hinweis aus.
const HINT_FADE_SEC := 7.0

## Autohaus-Haken: später vom Host befüllbar.
var kart_skin := ""
var speed_bonus := 0.0

## Für Screenshot-/Zertifizierungsläufe: der Logik-Bot übernimmt.
var autoplay := false

var tune: Dictionary = {}
var race: Dictionary = {}
var score := 0
## Überhol-Serie ohne Rempler (nur Anzeige/Feel — Combo-Ton steigt mit).
var overtake_streak := 0
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _paid_drift := 0
var _steer: Variant = null
var _drift_held := false
var _want_item := false
var _press_t := 0.0
var _elapsed := 0.0
var _end_t := 0.0
var _ending := false
var _ui := 1.0
var _scale := 2.6
var _cam_fwd := Vector3(0.0, 0.0, 1.0)
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_ready := false
var _spark_t := 0.0
var _lap_label: Label
var _pos_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0
var _stage: Node3D
var _world: Node3D
var _karts: Array[Node3D] = []
var _gooby: Node3D
var _shield: MeshInstance3D
var _streaks: MultiMeshInstance3D
var _sparks: GPUParticles3D
var _confetti: GPUParticles3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.RACER, ctx.difficulty)
	race = Logic.create_race(ctx.run_seed, tune)
	_scale = float(tune["WORLD_SCALE"])
	_build_stage()
	_build_hud()
	_snap_camera()
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


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _lap_label == null:
		return
	var pad := 20.0 * _ui
	_lap_label.position = Vector2(pad, 10.0 * _ui)
	_lap_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_pos_label.position = Vector2(pad, 48.0 * _ui)
	_pos_label.add_theme_font_size_override("font_size", int(16.0 * _ui))
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2(14.0 * _ui, view_size.y - 44.0 * _ui)
	_hint_label.size = Vector2(maxf(120.0, view_size.x - 28.0 * _ui), 38.0 * _ui)


func _process(delta: float) -> void:
	if finished:
		return
	var dt := minf(delta, 0.1)
	_elapsed += dt
	_banner_t = maxf(0.0, _banner_t - dt)
	if _ending:
		_end_t += dt
		_sync_world(dt)
		if _end_t >= 1.2:
			_finish()
		queue_redraw()
		return
	if not is_active():
		return

	Logic.step_race(race, dt, _take_input())
	_play_events()
	# Driftmeter zahlen live aus (§C10.1 Punkteformel).
	var drift_pts := int(
		floorf(float(race["karts"][0]["driftMeters"]) / float(tune["DRIFT_METERS_DIV"]))
	)
	if drift_pts > _paid_drift:
		_add_score(drift_pts - _paid_drift)
		_paid_drift = drift_pts
	_sync_world(dt)
	_update_labels()
	_fade_hint()
	queue_redraw()


## Im Autoplay fährt der Logik-Bot (zahlengleich zum Web-`?autoplay=1`).
func _take_input() -> Dictionary:
	if autoplay:
		return Logic.bot_input(race)
	var out := {"steer": _steer, "drifting": _drift_held, "useItem": _want_item}
	_want_item = false
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _ending:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_drift_held = true
			_press_t = _elapsed
			_steer_to(event.position.x)
		else:
			# Kurzer Druck ist ein Tipp (Item) — kein Mikro-Drift.
			if _elapsed - _press_t < 0.22:
				race["karts"][0]["driftCharge"] = 0.0
				_want_item = true
			_drift_held = false
	elif event is InputEventScreenDrag:
		_steer_to(event.position.x)
	elif event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_LEFT:
				_nudge_steer(-1.0 if event.pressed else 0.0)
			KEY_RIGHT:
				_nudge_steer(1.0 if event.pressed else 0.0)
			KEY_SPACE:
				_drift_held = event.pressed
			KEY_ENTER:
				if event.pressed:
					_want_item = true


func _steer_to(px: float) -> void:
	var nx := clampf(px / maxf(1.0, view_size.x) * 2.0 - 1.0, -1.0, 1.0)
	var hard := float(tune["LAT_HARD_MAX"])
	_steer = clampf(nx * 1.2, -hard, hard)


func _nudge_steer(dir: float) -> void:
	if dir == 0.0:
		_steer = null
		return
	_steer = dir * float(tune["LAT_HARD_MAX"])


func _add_score(delta: int) -> void:
	if delta == 0:
		return
	score += delta
	ctx.report_score(score, delta)


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Warme Kinderzimmerwand (Web: #F7E3C8) statt Himmel — der
				# Kurs liegt in einem Zimmer, kein Außenlicht.
				"sky_top": Color(0.94, 0.86, 0.75),
				"sky_horizon": Color(0.97, 0.89, 0.78),
				"ground_horizon": Color(0.9, 0.8, 0.68),
				"ground_bottom": Color(0.62, 0.45, 0.3),
				"fog_color": Color(0.97, 0.89, 0.78),
				# Die Bauklotz-Skyline steht 30–60 m weit draußen. Mit dem alten
				# Nebel (26→62) verschluckte sie sich komplett in der Wandfarbe;
				# im Web liest man die bunten Klötze klar. Nebel bleibt drin —
				# aber erst als Tiefenandeutung HINTER der Skyline.
				"fog_from": 55.0,
				"fog_to": 150.0,
				"glow": 0.26,
				# Web: DirectionalLight(0xffe9c4, 0.9) bei (6, 12, 4);
				# HemisphereLight(0xfff4e0, 0xd8b48c, 1.1) — Mittelwert unten.
				"sun_dir": Vector3(-0.42, -0.82, -0.28),
				"sun_color": Color(1.0, 0.914, 0.769),
				"sun_energy": 0.9,
				"ambient_color": Color(0.923, 0.831, 0.708),
				"ambient": 1.1,
				"contrast": 1.05,
				"saturation": 1.18,
				"fill_color": Color(0.85, 0.7, 0.55),
				"fill_energy": 0.14,
				"hfov": HFOV_BASE,
				"shadow_distance": 34.0,
				"far": 240.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", race["track"], _scale, int(race["seed"]))
	_build_karts()
	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 16, Vector2(2.4, 3.4), Vector2(5.0, 11.0))
	_sparks = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.78, 0.35, 1.0),
				"amount": 16,
				"lifetime": 0.45,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(1.4, 3.4),
				"spread": 90.0,
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.06, 0.15),
			}
		)
	)
	_stage.add_child(_sparks)
	_confetti = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.85, 0.5, 1.0),
				"amount": 26,
				"lifetime": 1.1,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(2.0, 4.6),
				"spread": 180.0,
				"gravity": Vector3(0.0, -4.0, 0.0),
				"size": Vector2(0.08, 0.2),
			}
		)
	)
	_stage.add_child(_confetti)


## Vier Karts als echte car-kit-Modelle; im ersten sitzt Gooby.
func _build_karts() -> void:
	var karts: Array = race["karts"]
	for i in karts.size():
		var group := Node3D.new()
		var path := KART_MODELS[i % KART_MODELS.size()]
		group.add_child(Models.node(path, KART_W * _scale, true))
		_stage.add_child(group)
		_karts.append(group)
	_gooby = GoobyMount.new()
	# Web: scale 0.42 auf dem Roh-Rig, Sitz bei (0, 0.34, −0.12). Das Kart
	# fährt nach +z, Gooby schaut also NICHT weg von der Kamera — die Kamera
	# steht hinterm Kart, das Rig zeigt von Haus aus in Fahrtrichtung.
	# Web: 0,47 m. Aus 4,5 m Höhe ist das ein Krümel — im Spielzeugmaßstab darf
	# der Fahrer ruhig comic-groß aus dem Cockpit ragen, dann SIEHT man ihn.
	_gooby.call("mount", 0.66 * float(tune.get("RENDER_SCALE_MULT", 1.0)), true, false)
	_gooby.position = Vector3(0.0, 0.38, -0.1)
	_karts[0].add_child(_gooby)
	var bubble := SphereMesh.new()
	bubble.radius = 0.75
	bubble.height = 1.5
	bubble.radial_segments = 18
	bubble.rings = 10
	bubble.material = Fx.glass(Color(0.49, 0.83, 0.94, 0.3), true)
	_shield = MeshInstance3D.new()
	_shield.mesh = bubble
	_shield.position.y = 0.4
	_shield.visible = false
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_karts[0].add_child(_shield)


func _build_hud() -> void:
	_lap_label = Label.new()
	_lap_label.theme_type_variation = &"HeadlineLabel"
	add_child(_lap_label)
	_pos_label = Label.new()
	_pos_label.theme_type_variation = &"CaptionLabel"
	# CaptionLabel ist standardmäßig sehr blass — auf der hellen HUD-Platte
	# braucht die Platz-/Item-Zeile kräftigere Tinte.
	_pos_label.add_theme_color_override("font_color", Color(0.35, 0.29, 0.27))
	add_child(_pos_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.toyRacer.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf der dunklen Fahrbahn — heller Text mit Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.94))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.16, 0.13, 0.12, 0.45))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


func _sync_world(dt: float) -> void:
	_stage.call("tick", dt)
	_gooby.call("tick", dt)
	_sync_karts()
	_sync_boxes()
	_sync_blocks()
	_sync_camera(dt)
	_drift_sparks(dt)


## Kart-Posen aus dem Spline: der Rahmen ist (rechts, oben, vorwärts). Der
## Logik-`right` zeigt nach LINKS (Linkskurven-Konvention), eine Basis daraus
## wäre gespiegelt — deshalb wird die echte X-Achse neu gebildet.
func _sync_karts() -> void:
	var track: Dictionary = race["track"]
	var karts: Array = race["karts"]
	for i in karts.size():
		var kart: Dictionary = karts[i]
		var smp := Logic.point_at(track, float(kart["s"]))
		var up := _v3(smp["up"]).normalized()
		var fwd := _v3(smp["t"]).normalized()
		var right := up.cross(fwd).normalized()
		var basis := Basis(right, up, fwd)
		if bool(kart["drifting"]):
			basis = (
				basis * Basis(Vector3.UP, 0.28 * (1.0 if float(kart["lateral"]) >= 0.0 else -1.0))
			)
		if float(kart["stunT"]) > 0.0:
			basis = basis * Basis(Vector3.BACK, sin(_elapsed * 30.0) * 0.15)
		var pos := _world_at(smp, float(kart["lateral"])) + up * 0.02
		_karts[i].transform = Transform3D(basis, pos)
	_shield.visible = bool(karts[0]["shield"])


func _sync_boxes() -> void:
	var track: Dictionary = race["track"]
	var spin := Basis(Vector3.UP, _elapsed * 2.2)
	var prop: Node3D = _world.get("box_prop")
	prop.call("begin")
	for row: Dictionary in track["itemRows"]:
		var smp := Logic.point_at(track, float(row["s"]))
		for box: Dictionary in row["boxes"]:
			if float(box["respawnT"]) > 0.0:
				continue
			var pos := _world_at(smp, float(box["lat"])) + Vector3(0.0, 0.24, 0.0)
			prop.call("push", Transform3D(spin, pos))
	prop.call("flush")


func _sync_blocks() -> void:
	var track: Dictionary = race["track"]
	var prop: Node3D = _world.get("block_prop")
	prop.call("begin")
	for i in (race["blocks"] as Array).size():
		var block: Dictionary = race["blocks"][i]
		var smp := Logic.point_at(track, float(block["s"]))
		var pos := _world_at(smp, float(block["lat"])) + Vector3(0.0, 0.18, 0.0)
		var tint: Color = World.BLOCK_COLORS[i % World.BLOCK_COLORS.size()]
		prop.call("push", Transform3D(Basis(Vector3.UP, float(i) * 0.6), pos), tint)
	prop.call("flush")


## Verfolgerkamera. Im Looping steht sie fest NEBEN dem Ring (Stuntkamera),
## sonst hinter dem Kart — genau die Regel der Web-Fassung.
func _sync_camera(dt: float) -> void:
	var track: Dictionary = race["track"]
	var player: Node3D = _karts[0]
	var ps := float(race["karts"][0]["s"])
	var smp := Logic.point_at(track, ps)
	var flat := Vector3(float((smp["t"] as Array)[0]), 0.0, float((smp["t"] as Array)[2]))
	if flat.length() > FLAT_TANGENT_MIN:
		_cam_fwd = flat.normalized()
	var wanted := player.position
	var look := player.position
	var zone := _loop_zone_at(track, ps)
	if not zone.is_empty():
		var apex := Logic.point_at(track, (float(zone["s0"]) + float(zone["s1"])) * 0.5)
		var ap: Array = apex["p"]
		var ring := Vector3(float(ap[0]), float(ap[1]) * 0.5, float(ap[2])) * _scale
		look = ring.lerp(player.position, LOOP_CAM_TRACK)
		var perp := Vector3(-_cam_fwd.z, 0.0, _cam_fwd.x)
		if _cam_ready and (_cam_pos - ring).dot(perp) < 0.0:
			perp = -perp
		# Ausgangspunkt ist NICHT die Ringmitte, sondern die Höhe des Karts:
		# so bleibt es beim Überschlag bildmittig statt als Punkt am Ringrand.
		var anchor := Vector3(ring.x, lerpf(ring.y, player.position.y, 0.7), ring.z)
		wanted = anchor + perp * LOOP_CAM_SIDE - _cam_fwd * LOOP_CAM_BACK
		wanted.y += LOOP_CAM_LIFT
	else:
		var lift := CAM_LIFT + (0.0 if landscape else CAM_PORTRAIT_LIFT)
		var ahead := CAM_LOOK_AHEAD + (0.0 if landscape else CAM_PORTRAIT_AHEAD)
		wanted = player.position - _cam_fwd * CAM_BACK
		wanted.y = maxf(player.position.y + lift, lift)
		look = player.position + _cam_fwd * ahead + Vector3(0.0, 0.4, 0.0)
		var dodged := _dodge_loop_plane(track, ps, player.position, wanted)
		if dodged != wanted:
			# Seitlich ausgewichen: der Vorausblick würde das Spieler-Kart
			# an den Bildrand schieben — jetzt zählt nur noch, dass man ES sieht.
			look = player.position + Vector3(0.0, 0.4, 0.0)
			wanted = dodged
	if not _cam_ready:
		_cam_pos = wanted
		_cam_look = look
		_cam_ready = true
	_cam_pos = _cam_pos.lerp(wanted, minf(1.0, dt * 4.0))
	_cam_look = _cam_look.lerp(look, minf(1.0, dt * 6.0))
	var cam: Camera3D = _stage.get("camera")
	cam.position = _cam_pos
	if _cam_pos.distance_to(_cam_look) > 0.05:
		cam.look_at(_cam_look, Vector3.UP)
	var boosting := float(race["karts"][0]["boostT"]) > 0.0
	_stage.call("set_fov_bonus", HFOV_KICK if boosting else 0.0)
	var speed := float(race["karts"][0]["speed"]) * _scale
	_streaks.set("enabled", boosting and not _reduced_motion())
	_streaks.call("update", dt, speed, 10.0 if boosting else 0.0)


## Zertifizierungs-Haken (Screenshots): Im Looping-Abschnitt steht die Kamera
## als Stuntkamera neben dem Ring — das Spieler-Kart verschwindet dann leicht
## hinter der Röhre. Das Beweisfoto soll auf freier Strecke entstehen.
##
## Zweite Bedingung: das Gummiband-Feld drängelt sich zeitweise auf einem Meter
## zusammen, dann parkt ein KI-Kart genau vor Goobys Cockpit. Geprüft wird
## deshalb die tatsächliche VERDECKUNG (näher an der Kamera UND im selben
## Bildfleck), nicht der Abstand im Raum — zwei Karts nebeneinander sind ja
## völlig in Ordnung.
func screenshot_ready() -> bool:
	var track: Dictionary = race["track"]
	var ps := float(race["karts"][0]["s"])
	if not _loop_zone_at(track, ps).is_empty():
		return false
	var player: Node3D = _karts[0]
	if _dodge_loop_plane(track, ps, player.position, player.position) != player.position:
		return false
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return true
	var seat := _gooby.global_position
	if cam.is_position_behind(seat):
		return false
	var seat_px := cam.unproject_position(seat)
	var seat_far := cam.global_position.distance_to(seat)
	var block := CLEAR_SHOT_PX * maxf(view_size.x, view_size.y) / 1200.0
	for i in range(1, _karts.size()):
		var other := _karts[i].global_position
		if cam.is_position_behind(other):
			continue
		if cam.global_position.distance_to(other) >= seat_far:
			continue
		if cam.unproject_position(other).distance_to(seat_px) < block:
			return false
	return true


## Steht die Kamera selbst gerade IN einem Looping-Abschnitt, würde sie durch
## das Band schneiden — dann rutscht sie seitlich aus der Ringebene.
func _dodge_loop_plane(
	track: Dictionary, ps: float, player_pos: Vector3, wanted: Vector3
) -> Vector3:
	var lap := float(track["lapLen"])
	var cam_s := fmod(fmod(ps - CAM_BACK, lap) + lap, lap)
	for z: Dictionary in track["loopZones"]:
		if cam_s < float(z["s0"]) - 0.5 or cam_s > float(z["s1"]) + 0.5:
			continue
		var perp := Vector3(-_cam_fwd.z, 0.0, _cam_fwd.x)
		if _cam_ready and (_cam_pos - player_pos).dot(perp) < 0.0:
			perp = -perp
		return wanted + perp * 5.0 + _cam_fwd * 2.4
	return wanted


func _loop_zone_at(track: Dictionary, s: float) -> Dictionary:
	for z: Dictionary in track["loopZones"]:
		if s >= float(z["s0"]) - 0.4 and s <= float(z["s1"]) + 0.2:
			return z
	return {}


## Funken am Heck, solange die Driftladung wächst (reduced-motion-gated).
func _drift_sparks(dt: float) -> void:
	_spark_t = maxf(0.0, _spark_t - dt)
	var kart: Dictionary = race["karts"][0]
	if not bool(kart["drifting"]) or float(kart["driftCharge"]) < 0.05:
		return
	if _spark_t > 0.0 or _reduced_motion():
		return
	_spark_t = 0.09
	Fx.burst(_sparks, _karts[0].global_transform * Vector3(0.0, 0.12, -0.5))


func _world_at(sample: Dictionary, lat: float) -> Vector3:
	return _world.call("world_at", sample, lat)


static func _v3(arr: Array) -> Vector3:
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


func _snap_camera() -> void:
	_cam_ready = false
	_sync_karts()
	_sync_camera(1.0)


# ── Ereignisse ────────────────────────────────────────────────────────────


func _play_events() -> void:
	var events: Array = race["events"]
	for ev: Dictionary in events:
		_handle_event(ev)
	events.clear()
	if bool(race["ended"]) and not _ending:
		_ending = true
		_end_t = 0.0


## Ereignisse der KI-Karts bleiben stumm — nur der Bauklotz-Treffer knallt
## auch beim Nachbarn hörbar; alles andere gehört dem Spieler-Kart.
func _handle_event(ev: Dictionary) -> void:
	var kind := str(ev["type"])
	if int(ev.get("kart", 0)) != 0:
		if kind == "blockHit":
			AudioDirector.try_play(self, "mg_spill")
		return
	match kind:
		"boost":
			AudioDirector.try_play(self, "mg_combo")
			_set_banner(I18nService.t("mg.toyRacer.boost"))
			_stage.call("pulse_glow", 0.9)
			_gooby.call("emote", "ecstatic", 1.0)
			Fx.burst(_sparks, _karts[0].global_position)
			if ctx.juice != null:
				ctx.juice.overlay_ring(_player_px(), Color(0.55, 0.85, 1.0), 70.0)
				ctx.juice.sfx("game_whoosh", 1.1)
		"pickup":
			AudioDirector.try_play(self, "gvz_collect")
			_set_banner(I18nService.t("mg.toyRacer.item_%s" % str(ev["item"])))
			_stage.call("pulse_glow", 0.4)
		"turbo":
			AudioDirector.try_play(self, "mg_golden")
			_set_banner(I18nService.t("mg.toyRacer.turbo"))
			_stage.call("pulse_glow", 1.2)
		"shield":
			AudioDirector.try_play(self, "mg_perfect")
			_set_banner(I18nService.t("mg.toyRacer.shield"))
		"blockDrop":
			AudioDirector.try_play(self, "gvz_place")
			_set_banner(I18nService.t("mg.toyRacer.block_drop"))
		"blockHit":
			AudioDirector.try_play(self, "mg_spill")
			_set_banner(I18nService.t("mg.toyRacer.block_hit"))
			_gooby.call("emote", "dizzy", 1.5)
			overtake_streak = 0
			# KEIN Screenshake: Dauerfahrt, Motion-Comfort-Regel.
			if ctx.juice != null:
				ctx.juice.hit_freeze(80)
				ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
				ctx.juice.sfx("game_miss")
				ctx.juice.show_combo(0)
		"shieldPop":
			AudioDirector.try_play(self, "gvz_balloon")
			_set_banner(I18nService.t("mg.toyRacer.shield_pop"))
		"offtrack":
			AudioDirector.try_play(self, "mg_junk")
			_set_banner(I18nService.t("mg.toyRacer.offtrack"))
			_gooby.call("emote", "scared", 0.8)
			overtake_streak = 0
			if ctx.juice != null:
				ctx.juice.show_combo(0)
		"overtake":
			overtake_streak += 1
			# Überhol-Serie klingt pro Stufe einen Halbton höher.
			AudioDirector.try_play(self, "mg_good", FeelSfx.combo_pitch(overtake_streak))
			_add_score(int(tune["OVERTAKE_POINTS"]))
			_float(
				"+%d" % int(tune["OVERTAKE_POINTS"]),
				_player_px() - Vector2(0.0, 40.0),
				Color(0.34, 0.75, 0.44)
			)
			_gooby.call("emote", "ecstatic", 0.9)
			if ctx.juice != null:
				ctx.juice.overlay_ring(_player_px(), Color(0.6, 0.95, 0.6), 60.0)
				if overtake_streak >= 2:
					ctx.juice.show_combo(overtake_streak)
		"lap":
			AudioDirector.try_play(self, "gvz_wave")
			_set_banner(
				(
					I18nService.t("mg.toyRacer.final_lap")
					if bool(ev["final"])
					else I18nService.t("mg.toyRacer.lap", {"n": int(ev["lap"])})
				)
			)
		"chainRace":
			AudioDirector.try_play(self, "mg_win")
			_set_banner(
				I18nService.t("mg.toyRacer.chain", {"n": int(ev["races"]), "p": int(ev["rank"])})
			)
			var banked := int(round(float(ev["banked"]) * float(tune["SCORE_MULT"])))
			if banked > score:
				_add_score(banked - score)
			_paid_drift = 0
			_stage.call("pulse_glow", 1.4)
			Fx.burst(_confetti, _karts[0].global_position + Vector3(0.0, 1.2, 0.0))
		"finish":
			var rank := int(ev["rank"])
			_set_banner(
				(
					I18nService.t("mg.toyRacer.finish_first")
					if rank == 1
					else I18nService.t("mg.toyRacer.finish_place", {"p": rank})
				)
			)
			_gooby.call("emote", "ecstatic" if rank <= 2 else "happy", 3.0)
			_stage.call("pulse_glow", 1.5)
			Fx.burst(_confetti, _karts[0].global_position + Vector3(0.0, 1.2, 0.0))
			if rank == 1 and ctx.juice != null:
				# Platz 1: Zeitlupe + Goldblitz + Konfetti-Regen.
				AudioDirector.try_play(self, "mg_win")
				ctx.juice.win_moment()
			elif ctx.juice != null:
				ctx.juice.sfx("game_lose" if rank >= 4 else "game_win")
			else:
				AudioDirector.try_play(self, "mg_win")


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	var meta := Logic.run_meta(race)
	(
		ctx
		. report_end(
			{
				"score": Logic.run_score(race),
				"rank": int(race["finishRank"]),
				"races": int(meta["races"]),
				"wins": int(meta["wins"]),
				"overtakes": int(race["overtakes"]),
				"driftMeters": int(floorf(float(race["karts"][0]["driftMeters"]))),
			}
		)
	)


func _float(text: String, pos: Vector2, color: Color) -> void:
	if ctx.juice != null:
		ctx.juice.float_text(pos, text, color)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.3


func _player_px() -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null or _karts.is_empty():
		return view_size * 0.5
	return cam.unproject_position(_karts[0].global_position)


func _fade_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - _elapsed) / 1.2, 0.0, 1.0)


func _update_labels() -> void:
	var rank := int(race["finishRank"]) if bool(race["ended"]) else Logic.player_rank(race)
	if bool(tune["ENDLESS"]):
		_lap_label.text = I18nService.t(
			"mg.toyRacer.chain_pill",
			{"n": int(race["chainRaces"]) + 1, "lap": Logic.player_lap(race)}
		)
	else:
		_lap_label.text = I18nService.t(
			"mg.toyRacer.lap_pill", {"n": Logic.player_lap(race), "total": int(tune["LAPS"])}
		)
	var item := str(race["karts"][0]["item"])
	_pos_label.text = (
		I18nService
		. t(
			"mg.toyRacer.stats",
			{
				"p": rank,
				"item":
				(
					I18nService.t("mg.toyRacer.item_none")
					if item.is_empty()
					else I18nService.t("mg.toyRacer.item_%s_short" % item)
				),
			}
		)
	)


# ── 2D-Overlay (HUD-Platte, Driftmeter, Banner über der 3D-Szene) ─────────


func _draw() -> void:
	_draw_hud_panel()
	_draw_drift_meter()
	_draw_banner()


## Weiche Unterlage für die HUD-Labels (die Labels sind Control-Kinder und
## werden NACH _draw gezeichnet, liegen also darüber).
func _draw_hud_panel() -> void:
	var pad := 10.0 * _ui
	var w := minf(224.0 * _ui, view_size.x * 0.4)
	var rect := Rect2(pad, pad * 0.6, w, 106.0 * _ui)
	_draw_soft_panel(rect, Color(1.0, 0.98, 0.94, 0.86), 16.0 * _ui)


## Abgerundete Platte ohne StyleBox: vier Kreise plus zwei Rechtecke.
func _draw_soft_panel(rect: Rect2, tint: Color, radius: float) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y), tint)
	draw_rect(Rect2(rect.position.x, rect.position.y + r, rect.size.x, rect.size.y - r * 2.0), tint)
	for corner in [
		Vector2(r, r),
		Vector2(rect.size.x - r, r),
		Vector2(r, rect.size.y - r),
		Vector2(rect.size.x - r, rect.size.y - r)
	]:
		draw_circle(rect.position + corner, r, tint)


func _draw_drift_meter() -> void:
	var kart: Dictionary = race["karts"][0]
	var charge := clampf(float(kart["driftCharge"]), 0.0, 1.0)
	# Sitzt UNTER den beiden HUD-Zeilen auf derselben Platte.
	var w := minf(184.0 * _ui, view_size.x * 0.33)
	var h := 11.0 * _ui
	var origin := Vector2(20.0 * _ui, 80.0 * _ui)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.24, 0.2, 0.22, 0.28))
	var ready := charge >= float(tune["DRIFT_MIN_CHARGE"])
	draw_rect(
		Rect2(origin, Vector2(w * charge, h)),
		Color(0.35, 0.75, 0.95) if ready else Color(1.0, 0.7, 0.35)
	)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.55, 0.47, 0.42, 0.6), false, maxf(1.5, _ui))
	var gate := origin.x + w * float(tune["DRIFT_MIN_CHARGE"])
	draw_line(
		Vector2(gate, origin.y - 2.0 * _ui),
		Vector2(gate, origin.y + h + 2.0 * _ui),
		Color(0.45, 0.38, 0.34, 0.85),
		maxf(1.5, 2.0 * _ui)
	)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 440.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.17),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(18, int(26.0 * _ui)),
		Color(1.0, 0.99, 0.94, alpha)
	)
