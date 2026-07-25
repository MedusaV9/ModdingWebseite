extends MinigameBase
## Spielzeug-Rennen (toyRacer) — Spiel-Szene. Die GESAMTE Rennmechanik läuft
## in ToyRacerLogic (zahlengleich zum Web): 3 Runden auf einem gesäten
## Spielzeug-Kurs gegen 3 Gummiband-KI-Karts, Halten = Drift laden,
## Loslassen = 1,2 s Schub, Item-Kisten je ⅓ Runde, neben der Strecke 40 %
## langsamer. Punkte = Platzbonus + 2·Überholer + Driftmeter/10.
##
## 2D statt 3D (Web war three.js mit Kenney-Kart-GLBs): die GLBs gibt es im
## Godot-Projekt nicht. Statt eines Ersatz-3D-Kurses rendert diese Ansicht
## den ECHTEN Logik-Spline als Sticker-Band aus einer Verfolgerperspektive —
## jede Weltkoordinate kommt aus point_at(), inklusive der senkrechten
## Loopings. Kollisionen/Physik rechnet ohnehin die Logik in Weltkoordinaten,
## die Ansicht projiziert nur.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `kart_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Karts liefert.

const Logic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const Scenery := preload("res://scripts/minigames/games/toy_racer/toy_racer_scenery.gd")

## Kamera-Abstand hinter dem Kart (Streckeneinheiten).
const CAM_BEHIND := 3.4
## Sichtweite entlang des Splines (Streckeneinheiten).
const DRAW_AHEAD := 22.0
## Wie weit hinter das Kart das Band noch gezeichnet wird.
const DRAW_BEHIND := 2.6
## Bandschritt in Streckeneinheiten (2× die Logik-Abtastung = 0,5).
const RIBBON_STEP := 0.5
## Mindest-Vorwärtsabstand, ab dem projiziert wird (Nahclipping).
const NEAR_FWD := 0.9
## Teppichrand außerhalb der Fahrbahn.
const APRON := 0.62
## Kartbreite in Streckeneinheiten (Fahrbahn ist 1,0 breit).
const KART_W := 0.32
## Näher als das wird ein Kart nicht mehr gezeichnet (Riesen-Sticker).
const KART_NEAR := 1.5
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

## Autohaus-Haken: später vom Host befüllbar.
var kart_skin := ""
var speed_bonus := 0.0

var tune: Dictionary = {}
var race: Dictionary = {}
var score := 0
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
var _cam_pos := Vector3.ZERO
var _cam_h := Vector2(0.0, 1.0)
var _cam_y := 0.0
var _focal_px := 380.0
var _horizon_px := 150.0
var _cam_lift := 1.3
var _ui := 1.0
var _towers: Array[Dictionary] = []
var _lap_label: Label
var _pos_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0
var _spark_t := 0.0
var _sparks: Array[Dictionary] = []


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.RACER, ctx.difficulty)
	race = Logic.create_race(ctx.run_seed, tune)
	_build_towers()
	_snap_camera()
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
	_recompute_camera()
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
	_age_sparks(dt)
	if _ending:
		_end_t += dt
		if _end_t >= 1.2:
			_finish()
		queue_redraw()
		return
	if not is_active():
		return

	var input := {"steer": _steer, "drifting": _drift_held, "useItem": _want_item}
	_want_item = false
	Logic.step_race(race, dt, input)
	_play_events()
	# Driftmeter zahlen live aus (§C10.1 Punkteformel).
	var drift_pts := int(
		floorf(float(race["karts"][0]["driftMeters"]) / float(tune["DRIFT_METERS_DIV"]))
	)
	if drift_pts > _paid_drift:
		_add_score(drift_pts - _paid_drift)
		_paid_drift = drift_pts
	_emit_drift_sparks(dt)
	_track_camera(dt)
	_update_labels()
	queue_redraw()


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


# ── Kamera ────────────────────────────────────────────────────────────────


## Kamera hinter dem Kart, Kurs = geglättete Fahrtrichtung. Im Looping wird
## die letzte kräftige Horizontalrichtung gehalten (sonst überschlägt sich die
## Kamera mit dem Korkenzieher) — dieselbe Regel wie im Web.
func _track_camera(dt: float) -> void:
	var kart: Dictionary = race["karts"][0]
	var sample := Logic.point_at(race["track"], float(kart["s"]))
	var t: Array = sample["t"]
	var flat := Vector2(float(t[0]), float(t[2]))
	if flat.length() > 0.45:
		_cam_h = _cam_h.lerp(flat.normalized(), minf(1.0, dt * 5.0)).normalized()
	var world := _kart_world(kart, sample)
	var wanted := world - Vector3(_cam_h.x, 0.0, _cam_h.y) * CAM_BEHIND
	wanted.y = maxf(world.y, 0.0) + _cam_lift
	_cam_pos = _cam_pos.lerp(wanted, minf(1.0, dt * 5.0))
	_cam_y = _cam_pos.y


func _snap_camera() -> void:
	var kart: Dictionary = race["karts"][0]
	var sample := Logic.point_at(race["track"], float(kart["s"]))
	var t: Array = sample["t"]
	var flat := Vector2(float(t[0]), float(t[2]))
	_cam_h = flat.normalized() if flat.length() > 0.001 else Vector2(0.0, 1.0)
	var world := _kart_world(kart, sample)
	_cam_pos = world - Vector3(_cam_h.x, 0.0, _cam_h.y) * CAM_BEHIND
	_cam_pos.y = maxf(world.y, 0.0) + _cam_lift
	_cam_y = _cam_pos.y


## Weltpunkt eines Karts (Mittelspline + seitlicher Versatz).
func _kart_world(kart: Dictionary, sample: Dictionary) -> Vector3:
	return _lat_world(sample, float(kart["lateral"]))


## Weltpunkt bei seitlichem Versatz `lat` auf einer Spline-Stützstelle.
func _lat_world(sample: Dictionary, lat: float) -> Vector3:
	var p: Array = sample["p"]
	var r: Array = sample["right"]
	return Vector3(
		float(p[0]) + float(r[0]) * lat,
		float(p[1]) + float(r[1]) * lat,
		float(p[2]) + float(r[2]) * lat
	)


## Kamera-Zoom/Horizont aus dem Layout: die Fahrbahn füllt einen festen
## Anteil der Breite, das Kart sitzt auf einem festen Höhenanteil.
func _recompute_camera() -> void:
	var road_fill := 0.44 if landscape else 0.8
	var horizon_frac := 0.3 if landscape else 0.26
	var kart_frac := 0.74 if landscape else 0.72
	var half_w := float(tune["TRACK_HALF_W"]) + APRON
	_focal_px = road_fill * view_size.x * CAM_BEHIND / (2.0 * half_w)
	_horizon_px = view_size.y * horizon_frac
	_cam_lift = (view_size.y * kart_frac - _horizon_px) * CAM_BEHIND / _focal_px
	_cam_pos.y = _cam_lift
	_cam_y = _cam_pos.y


## Weltpunkt → Bildschirmpixel. Gibt `null` zurück, wenn der Punkt hinter der
## Nahebene liegt (Kurven schieben Stützstellen hinter die Kamera).
func project(world: Vector3) -> Variant:
	var dx := world.x - _cam_pos.x
	var dz := world.z - _cam_pos.z
	var fwd := dx * _cam_h.x + dz * _cam_h.y
	if fwd < NEAR_FWD:
		return null
	var lat := dx * _cam_h.y - dz * _cam_h.x
	var s := _focal_px / fwd
	return Vector2(view_size.x * 0.5 + lat * s, _horizon_px + (_cam_y - world.y) * s)


## Pixel pro Weltmeter in dieser Tiefe (für Sticker-Größen).
func _scale_of(world: Vector3) -> float:
	var fwd := (world.x - _cam_pos.x) * _cam_h.x + (world.z - _cam_pos.z) * _cam_h.y
	return _focal_px / maxf(NEAR_FWD, fwd)


func _depth_of(world: Vector3) -> float:
	return (world.x - _cam_pos.x) * _cam_h.x + (world.z - _cam_pos.z) * _cam_h.y


# ── Szenerie ──────────────────────────────────────────────────────────────


## Bauklotz-Türme rund um den Kurs — gesät aus dem Rennseed, damit die
## Kulisse zum Kurs passt und über Läufe hinweg reproduzierbar ist.
func _build_towers() -> void:
	var track: Dictionary = race["track"]
	var rng := GoobyRng.new((int(race["seed"]) ^ 0x7A17E00D) & 0xFFFFFFFF)
	var lap_len := float(track["lapLen"])
	var count := 16
	for i in count:
		var s := lap_len * float(i) / count
		var sample := Logic.point_at(track, s)
		var side := 1.0 if rng.next() < 0.5 else -1.0
		var dist := 2.4 + rng.next() * 3.2
		var base := _lat_world(sample, side * dist)
		if absf(base.y) > 0.4:
			continue
		var stack: Array[int] = []
		var high := 1 + int(rng.next() * 3.0)
		for _b in high:
			stack.append(int(rng.next() * 6.0))
		_towers.append({"pos": base, "stack": stack})


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
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
		"pickup":
			AudioDirector.try_play(self, "gvz_collect")
			_set_banner(I18nService.t("mg.toyRacer.item_%s" % str(ev["item"])))
		"turbo":
			AudioDirector.try_play(self, "mg_golden")
			_set_banner(I18nService.t("mg.toyRacer.turbo"))
			if ctx.juice != null:
				ctx.juice.bloom_pulse(1.2)
		"shield":
			AudioDirector.try_play(self, "mg_perfect")
			_set_banner(I18nService.t("mg.toyRacer.shield"))
		"blockDrop":
			AudioDirector.try_play(self, "gvz_place")
			_set_banner(I18nService.t("mg.toyRacer.block_drop"))
		"blockHit":
			AudioDirector.try_play(self, "mg_spill")
			_set_banner(I18nService.t("mg.toyRacer.block_hit"))
			if ctx.juice != null:
				ctx.juice.shake(0.5)
				ctx.juice.hit_freeze(80)
		"shieldPop":
			AudioDirector.try_play(self, "gvz_balloon")
			_set_banner(I18nService.t("mg.toyRacer.shield_pop"))
		"offtrack":
			AudioDirector.try_play(self, "mg_junk")
			_set_banner(I18nService.t("mg.toyRacer.offtrack"))
		"overtake":
			AudioDirector.try_play(self, "mg_good")
			_add_score(int(tune["OVERTAKE_POINTS"]))
			_float(
				"+%d" % int(tune["OVERTAKE_POINTS"]),
				_player_px() - Vector2(0.0, 40.0),
				Color(0.34, 0.75, 0.44)
			)
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
			if ctx.juice != null:
				ctx.juice.bloom_pulse(1.4)
		"finish":
			AudioDirector.try_play(self, "mg_win")
			var rank := int(ev["rank"])
			_set_banner(
				(
					I18nService.t("mg.toyRacer.finish_first")
					if rank == 1
					else I18nService.t("mg.toyRacer.finish_place", {"p": rank})
				)
			)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(1.5)


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
	return Vector2(view_size.x * 0.5, view_size.y * (0.78 if landscape else 0.74))


# ── HUD ───────────────────────────────────────────────────────────────────


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


# ── Drift-Funken ──────────────────────────────────────────────────────────


func _emit_drift_sparks(dt: float) -> void:
	var kart: Dictionary = race["karts"][0]
	_spark_t = maxf(0.0, _spark_t - dt)
	if not bool(kart["drifting"]) or float(kart["driftCharge"]) < 0.05:
		return
	if _spark_t > 0.0:
		return
	_spark_t = 0.06
	var charge := float(kart["driftCharge"])
	var base := _player_px() + Vector2(0.0, 12.0)
	for _i in 2:
		(
			_sparks
			. append(
				{
					"pos": base + Vector2(randf_range(-26.0, 26.0), randf_range(-6.0, 6.0)),
					"vel": Vector2(randf_range(-70.0, 70.0), randf_range(-140.0, -40.0)),
					"life": 0.35,
					"charge": charge,
				}
			)
		)


func _age_sparks(dt: float) -> void:
	for i in range(_sparks.size() - 1, -1, -1):
		var sp: Dictionary = _sparks[i]
		sp["life"] = float(sp["life"]) - dt
		if float(sp["life"]) <= 0.0:
			_sparks.remove_at(i)
			continue
		sp["pos"] = Vector2(sp["pos"]) + Vector2(sp["vel"]) * dt
		sp["vel"] = Vector2(sp["vel"]) + Vector2(0.0, 220.0 * dt)


# ── Zeichnen ──────────────────────────────────────────────────────────────


func _draw() -> void:
	Scenery.draw_room(self, view_size, _horizon_px)
	Scenery.draw_towers(self, _towers, project, _scale_of, _depth_of, NEAR_FWD, DRAW_AHEAD + 6.0)
	_draw_ribbon()
	_draw_item_boxes()
	_draw_blocks()
	_draw_karts()
	_draw_sparks()
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


## Fahrbahnband aus dem ECHTEN Logik-Spline (inkl. senkrechter Loopings).
func _draw_ribbon() -> void:
	var track: Dictionary = race["track"]
	var kart: Dictionary = race["karts"][0]
	var s0 := float(kart["s"]) - DRAW_BEHIND
	var half := float(tune["TRACK_HALF_W"])
	var segments: Array[Dictionary] = []
	var d := DRAW_AHEAD
	while d > -DRAW_BEHIND - RIBBON_STEP:
		var sa := s0 + DRAW_BEHIND + d
		var sb := sa + RIBBON_STEP
		var pa := Logic.point_at(track, sa)
		var pb := Logic.point_at(track, sb)
		var quad: Variant = _edge_quad(pa, pb, half + APRON)
		if quad != null:
			(
				segments
				. append(
					{
						"road": _edge_quad(pa, pb, half),
						"apron": quad,
						"sa": sa,
						"mid": _lat_world(pa, 0.0),
					}
				)
			)
		d -= RIBBON_STEP
	# Pastell-Ringstreifen des Spielteppichs — die Bänder hängen an der
	# absoluten Bogenlänge, laufen also stabil unter dem Kart durch.
	var rug_bands: Array[Color] = [
		Color(0.62, 0.81, 0.92),
		Color(0.97, 0.85, 0.5),
		Color(0.95, 0.72, 0.79),
		Color(0.68, 0.86, 0.62),
		Color(0.83, 0.73, 0.92),
	]
	for seg: Dictionary in segments:
		var band := int(floorf(float(seg["sa"]) / 1.5))
		var apron: Variant = seg["apron"]
		var road: Variant = seg["road"]
		draw_colored_polygon(apron, rug_bands[posmod(band, rug_bands.size())])
		if road == null:
			continue
		draw_colored_polygon(road, Color(0.42, 0.44, 0.5))
		var poly: PackedVector2Array = road
		var width := maxf(1.0, _scale_of(seg["mid"]) * 0.016)
		# Seitliche Plastikleisten der Spielzeugbahn
		draw_line(poly[0], poly[3], Color(0.28, 0.29, 0.34), width * 1.6)
		draw_line(poly[1], poly[2], Color(0.28, 0.29, 0.34), width * 1.6)
		# Gestrichelter Mittelstrich
		if posmod(int(floorf(float(seg["sa"]) / RIBBON_STEP)), 3) == 0:
			draw_line(
				(poly[0] + poly[1]) * 0.5,
				(poly[3] + poly[2]) * 0.5,
				Color(0.98, 0.96, 0.9, 0.7),
				width
			)
	# Start-Ziel-Linie
	_draw_finish_line()


## Ein Fahrbahn-Viereck zwischen zwei Stützstellen; `null` bei Nahclipping
## oder wenn die Projektion entartet (Kurven jenseits der Bildebene).
func _edge_quad(pa: Dictionary, pb: Dictionary, half: float) -> Variant:
	var a_l: Variant = project(_lat_world(pa, -half))
	var a_r: Variant = project(_lat_world(pa, half))
	var b_l: Variant = project(_lat_world(pb, -half))
	var b_r: Variant = project(_lat_world(pb, half))
	if a_l == null or a_r == null or b_l == null or b_r == null:
		return null
	var quad := PackedVector2Array([a_l, a_r, b_r, b_l])
	return quad if _quad_is_drawable(quad) else null


## Ein Viereck ist zeichenbar, wenn es konvex, nicht entartet und noch in
## Bildnähe liegt. Ohne diese Prüfung wirft Godot bei Kurven, deren Kanten
## hinter die Bildebene laufen, „triangulation failed".
func _quad_is_drawable(quad: PackedVector2Array) -> bool:
	var limit := maxf(view_size.x, view_size.y) * 3.0
	for point in quad:
		if absf(point.x) > limit or absf(point.y) > limit:
			return false
	var sign_seen := 0
	for i in 4:
		var a := quad[i]
		var b := quad[(i + 1) % 4]
		var c := quad[(i + 2) % 4]
		var cross := (b - a).cross(c - b)
		if absf(cross) < 0.35:
			continue
		var s := 1 if cross > 0.0 else -1
		if sign_seen == 0:
			sign_seen = s
		elif sign_seen != s:
			return false
	return sign_seen != 0


func _draw_finish_line() -> void:
	var track: Dictionary = race["track"]
	var half := float(tune["TRACK_HALF_W"])
	var pa := Logic.point_at(track, 0.0)
	var pb := Logic.point_at(track, 0.35)
	var cells := 8
	for i in cells:
		var f0 := -half + (2.0 * half) * i / cells
		var f1 := -half + (2.0 * half) * (i + 1) / cells
		var q0: Variant = project(_lat_world(pa, f0))
		var q1: Variant = project(_lat_world(pa, f1))
		var q2: Variant = project(_lat_world(pb, f1))
		var q3: Variant = project(_lat_world(pb, f0))
		if q0 == null or q1 == null or q2 == null or q3 == null:
			continue
		draw_colored_polygon(
			PackedVector2Array([q0, q1, q2, q3]),
			Color(0.98, 0.97, 0.94) if i % 2 == 0 else Color(0.2, 0.19, 0.22)
		)


func _draw_item_boxes() -> void:
	var track: Dictionary = race["track"]
	for row: Dictionary in track["itemRows"]:
		var sample := Logic.point_at(track, float(row["s"]))
		for box: Dictionary in row["boxes"]:
			if float(box["respawnT"]) > 0.0:
				continue
			var world := _lat_world(sample, float(box["lat"]))
			world.y += 0.16
			var pt: Variant = project(world)
			if pt == null:
				continue
			var s := _scale_of(world)
			if s > _focal_px / NEAR_FWD * 0.9:
				continue
			var r := s * 0.15
			var spin := 0.35 * sin(_elapsed * 2.2 + float(box["lat"]) * 3.0)
			var c: Vector2 = pt
			draw_colored_polygon(
				PackedVector2Array(
					[
						c + Vector2(-r, -r * 0.4 + spin * r),
						c + Vector2(0.0, -r * 1.2),
						c + Vector2(r, -r * 0.4 - spin * r),
						c + Vector2(0.0, r * 0.35),
					]
				),
				Color(1.0, 0.85, 0.35)
			)
			draw_circle(c + Vector2(0.0, -r * 0.42), r * 0.3, Color(1.0, 0.99, 0.85))


func _draw_blocks() -> void:
	var track: Dictionary = race["track"]
	for block: Dictionary in race["blocks"]:
		var sample := Logic.point_at(track, float(block["s"]))
		var world := _lat_world(sample, float(block["lat"]))
		world.y += 0.1
		var pt: Variant = project(world)
		if pt == null:
			continue
		var s := _scale_of(world)
		var w := s * 0.24
		var box := Rect2(Vector2(pt) - Vector2(w * 0.5, w * 0.8), Vector2(w, w * 0.8))
		draw_rect(box, Color(0.87, 0.36, 0.33))
		draw_rect(box, Color(0.58, 0.2, 0.18), false, maxf(1.0, w * 0.09))
		draw_circle(box.position + Vector2(w * 0.5, -w * 0.05), w * 0.16, Color(0.95, 0.55, 0.5))


func _draw_karts() -> void:
	var track: Dictionary = race["track"]
	var order: Array[Dictionary] = []
	var karts: Array = race["karts"]
	for i in karts.size():
		var kart: Dictionary = karts[i]
		var sample := Logic.point_at(track, float(kart["s"]))
		var world := _kart_world(kart, sample)
		var depth := _depth_of(world)
		if depth < KART_NEAR or depth > DRAW_AHEAD:
			continue
		order.append({"kart": kart, "world": world, "d": depth})
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) > float(b["d"])
	)
	# Lesbarkeit vor Tiefensortierung: das Spieler-Kart liegt immer obenauf,
	# sonst verdecken es die Verfolger direkt vor der Kamera.
	var player_entry: Dictionary = {}
	for entry: Dictionary in order:
		if bool((entry["kart"] as Dictionary)["isPlayer"]):
			player_entry = entry
			continue
		_draw_kart(entry["kart"], entry["world"])
	if player_entry.is_empty():
		return
	var world: Vector3 = player_entry["world"]
	var marker: Variant = project(world)
	if marker != null:
		var s := _scale_of(world)
		draw_arc(
			Vector2(marker) + Vector2(0.0, s * KART_W * 0.18),
			s * KART_W * 0.66,
			0.0,
			TAU,
			26,
			Color(1.0, 0.98, 0.9, 0.55),
			maxf(2.0, s * 0.012)
		)
	_draw_kart(player_entry["kart"], world)


func _draw_kart(kart: Dictionary, world: Vector3) -> void:
	var pt: Variant = project(world)
	if pt == null:
		return
	var c: Vector2 = pt
	var s := _scale_of(world)
	var is_player := bool(kart["isPlayer"])
	var ai_palette: Array[Color] = [
		Color(0.42, 0.66, 0.92), Color(0.55, 0.78, 0.4), Color(0.86, 0.71, 0.35)
	]
	var body := Color(0.95, 0.42, 0.36) if is_player else ai_palette[(int(kart["id"]) - 1) % 3]
	var w := s * KART_W
	var h := s * KART_W * 0.52
	var lean := 0.0
	if bool(kart["drifting"]):
		lean = w * 0.12 * (1.0 if float(kart["lateral"]) >= 0.0 else -1.0)
	if float(kart["stunT"]) > 0.0:
		lean += sin(_elapsed * 28.0) * w * 0.1
	# Schatten
	draw_circle(c + Vector2(0.0, h * 0.18), w * 0.5, Color(0.32, 0.22, 0.14, 0.28))
	# Schub-Flamme
	if float(kart["boostT"]) > 0.0:
		var flame := 0.6 + 0.4 * sin(_elapsed * 30.0)
		draw_colored_polygon(
			PackedVector2Array(
				[
					c + Vector2(-w * 0.22, h * 0.05),
					c + Vector2(w * 0.22, h * 0.05),
					c + Vector2(0.0, h * (0.6 + flame * 0.8)),
				]
			),
			Color(1.0, 0.72, 0.25, 0.85)
		)
	# Räder
	draw_rect(
		Rect2(c + Vector2(-w * 0.56 + lean, -h * 0.1), Vector2(w * 0.18, h * 0.5)),
		Color(0.2, 0.19, 0.22)
	)
	draw_rect(
		Rect2(c + Vector2(w * 0.38 + lean, -h * 0.1), Vector2(w * 0.18, h * 0.5)),
		Color(0.2, 0.19, 0.22)
	)
	# Karosserie
	var hull := PackedVector2Array(
		[
			c + Vector2(-w * 0.44 + lean * 1.4, -h * 0.55),
			c + Vector2(w * 0.44 + lean * 1.4, -h * 0.55),
			c + Vector2(w * 0.5 + lean, h * 0.25),
			c + Vector2(-w * 0.5 + lean, h * 0.25),
		]
	)
	draw_colored_polygon(hull, body)
	var rim := PackedVector2Array(hull)
	rim.append(hull[0])
	draw_polyline(rim, body.darkened(0.35), maxf(1.5, s * 0.018))
	# Heckspoiler
	draw_rect(
		Rect2(c + Vector2(-w * 0.3 + lean, -h * 0.72), Vector2(w * 0.6, h * 0.16)),
		body.darkened(0.2)
	)
	# Fahrer-Gooby
	var head := c + Vector2(lean * 1.6, -h * 1.0)
	draw_circle(head, w * 0.19, Color(0.99, 0.87, 0.72))
	draw_arc(head, w * 0.19, PI, TAU, 12, Color(0.24, 0.42, 0.66), maxf(1.5, s * 0.03))
	draw_circle(head + Vector2(-w * 0.07, 0.0), maxf(1.0, w * 0.03), Color(0.22, 0.16, 0.14))
	draw_circle(head + Vector2(w * 0.07, 0.0), maxf(1.0, w * 0.03), Color(0.22, 0.16, 0.14))
	if bool(kart["shield"]):
		draw_arc(
			c + Vector2(0.0, -h * 0.3),
			w * 0.72,
			0.0,
			TAU,
			26,
			Color(0.5, 0.85, 1.0, 0.7),
			maxf(2.0, s * 0.03)
		)
	if bool(kart["offTrack"]) and is_player:
		draw_arc(c + Vector2(0.0, h * 0.2), w * 0.6, 0.0, PI, 14, Color(0.85, 0.7, 0.4, 0.7), 3.0)


func _draw_sparks() -> void:
	for sp: Dictionary in _sparks:
		var life := float(sp["life"])
		var charge := float(sp["charge"])
		var color := (
			Color(1.0, 0.55, 0.25, life * 2.6)
			if charge < float(tune["DRIFT_MIN_CHARGE"])
			else Color(0.55, 0.85, 1.0, life * 2.6)
		)
		draw_circle(Vector2(sp["pos"]), 3.0 + life * 6.0, color)


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
	draw_string(
		font,
		Vector2(view_size.x * 0.5 - 220.0, view_size.y * 0.17),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		440.0,
		26,
		Color(0.28, 0.2, 0.18, alpha)
	)
