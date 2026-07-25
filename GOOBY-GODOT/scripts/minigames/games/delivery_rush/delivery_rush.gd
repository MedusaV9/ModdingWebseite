extends MinigameBase
## Liefer-Hetze (deliveryRush) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## DeliveryRushLogic (zahlengleich zum Web): 3 Pakete an 3 verschiedene
## Landmarken, 4-m-Abwurfring +50, Crash −5 (Boden 0), markiertes Paket
## −20 bei Schaden / +15 sauber, Zeitbonus +max(0, 120 − s) nach Abwurf 3.
##
## 2D-STICKER statt 3D (begründet): die Web-Fassung fuhr eine three.js-Stadt in
## Verfolgerperspektive. Die Logik ist reine (x, z)-Mathematik auf einem
## 9×9-Kachelraster — eine Draufsicht-Sticker-Stadt zeigt Ziel, Abwurfring und
## Verkehr GLEICHZEITIG (in der Verfolgerkamera braucht es dafür einen
## Kompass) und spart die komplette 3D-Stadt-Pipeline. Kein Meter ändert sich.
##
## AUTOHAUS-HOOK: `car_speed_mult` bleibt 1.0 — hier hängt später das im
## Autohaus gekaufte Auto (Tempo/Handling) dran. Bewusst NICHT implementiert.

const Logic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")

## Basis-Höchsttempo des Lieferwagens (m/s, §C4-Rampe).
const VAN_TOP_SPEED := 13.0
const VAN_ACCEL := 9.0
const VAN_TURN_RATE := 2.4
## Abseits der Straße bremst der Wagen auf diesen Anteil.
const OFFROAD_FACTOR := 0.45
## Sichtfeld der Verfolgerkamera auf der KURZEN Bildkante (Weltmeter). Feste
## Pixel-pro-Meter ließen die 180-m-Stadt in der Bühnenmitte schrumpfen und
## rundherum leere Wiese stehen — jetzt folgt der Zoom der Bühnengröße.
const VISIBLE_SHORT_M := 68.0
## Fahrzeugmaße in Weltmetern (Lieferwagen und Verkehr).
const VAN_LEN_M := 7.0
const VAN_WIDTH_M := 3.4
const CAR_LEN_M := 5.2
const CAR_WIDTH_M := 2.6
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Verkehr: Grundzahl der Autos auf dem Ring, ×TRAFFIC_DENSITY_MULT.
const TRAFFIC_BASE := 6
const TRAFFIC_SPEED := 7.5
const TRAFFIC_HIT_M := 3.4
const CRASH_COOLDOWN_SEC := 1.5

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var leg_elapsed := 0.0
var crashes := 0
var drops := 0
var parcel := 0
var fragile_index := 0
var fragile_damaged := false
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false
## Hook: kommt später aus dem Autohaus (Tempo/Handling des gekauften Autos).
var car_speed_mult := 1.0

var van_pos := Vector2.ZERO
var van_heading := 0.0
var van_speed := 0.0
var steer := 0.0

var _grid: Array = []
var _colliders: Array[Dictionary] = []
var _targets: Array[String] = []
var _drop_points: Array[Vector2] = []
var _traffic: Array[Dictionary] = []
var _endless_state: Dictionary = {}
var _crash_cool := 0.0
var _ppm := 7.0
var _ui := 1.0
var _time_label: Label
var _target_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.DELIVERY, ctx.difficulty)
	rng = ctx.rng()
	_grid = Logic.build_grid()
	_colliders = Logic.layout_colliders()
	var ids: Array[String] = []
	for row: Dictionary in Logic.LANDMARKS:
		ids.append(str(row["id"]))
	_targets = Logic.pick_deliveries(rng, ids)
	fragile_index = Logic.pick_fragile_parcel(rng)
	_rebuild_drop_points()
	_endless_state = Logic.create_endless_state(int(tune["ENDLESS_EXPIRED_LIMIT"]))
	var start := Logic.tile_to_world(Logic.SHOP_TILE.x, Logic.SHOP_TILE.y)
	van_pos = Vector2(start.x + 6.5, start.y)
	van_heading = -PI * 0.5
	_spawn_traffic()
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
	_ppm = clampf(minf(view_size.x, view_size.y) / VISIBLE_SHORT_M, 3.0, 22.0)
	position = Vector2.ZERO
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_target_label.position = Vector2(pad, 44.0 * _ui)
	_target_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 46.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	leg_elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	_crash_cool = maxf(0.0, _crash_cool - delta)
	var before := van_pos
	_step_van(delta)
	_step_traffic(delta)
	_check_drop(before)
	if Logic.parcel_expired(leg_elapsed, tune):
		_expire_parcel()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		steer = _steer_from(event.position) if event.pressed else 0.0
	elif event is InputEventScreenDrag:
		steer = _steer_from(event.position)


## Aktuelles Lieferziel (Weltpunkt des Abwurfrings).
func current_drop() -> Vector2:
	if parcel < _drop_points.size():
		return _drop_points[parcel]
	return Vector2.ZERO


func _steer_from(pos: Vector2) -> float:
	return clampf((pos.x - view_size.x * 0.5) / (view_size.x * 0.4), -1.0, 1.0)


func _anchor_of(id: String) -> Dictionary:
	for row: Dictionary in Logic.LANDMARKS:
		if str(row["id"]) == id:
			return {"x": float(row["x"]), "z": float(row["z"])}
	return {"x": 0.0, "z": 0.0}


## Abwurfringe der aktuellen Zielliste neu ausrechnen (aus den Kollidern raus).
func _rebuild_drop_points() -> void:
	_drop_points.clear()
	for id in _targets:
		var p := Logic.drop_point(_anchor_of(id), _colliders)
		_drop_points.append(Vector2(float(p["x"]), float(p["z"])))


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_target_label = Label.new()
	_target_label.theme_type_variation = &"CaptionLabel"
	add_child(_target_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.deliveryRush.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf Straße/Wiese — heller Text mit weichem Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.18, 0.24, 0.16, 0.45))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _spawn_traffic() -> void:
	var count := MinigameFrameworkLogic.js_round(TRAFFIC_BASE * float(tune["TRAFFIC_DENSITY_MULT"]))
	for i in count:
		(
			_traffic
			. append(
				{
					"s": rng.next() * 480.0,
					"speed": TRAFFIC_SPEED * (0.8 + rng.next() * 0.5),
					"cross": i % 3 == 2,
					"lane": 2.5 if rng.next() < 0.5 else -2.5,
				}
			)
		)


func _step_van(delta: float) -> void:
	van_heading += steer * VAN_TURN_RATE * delta
	var top := VAN_TOP_SPEED * float(tune["SPEED_MULT"]) * car_speed_mult
	var tile := Logic.world_to_tile(van_pos.x, van_pos.y)
	if not Logic.is_road(tile.x, tile.y):
		top *= OFFROAD_FACTOR
	van_speed = move_toward(van_speed, top, VAN_ACCEL * delta)
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
		car["s"] = fposmod(float(car["s"]) + float(car["speed"]) * delta, 480.0)
		var p := _traffic_pos(car)
		if _crash_cool <= 0.0 and p.distance_to(van_pos) <= TRAFFIC_HIT_M:
			_crash()


## Position eines Verkehrsautos auf seinem geschlossenen Kurs.
func _traffic_pos(car: Dictionary) -> Vector2:
	var lane := float(car["lane"])
	if bool(car["cross"]):
		# Kreuzstraße r = 4 (z = 0), hin und zurück.
		var s := fmod(float(car["s"]), 240.0)
		var x := (s if s <= 120.0 else 240.0 - s) - 60.0
		return Vector2(x, lane)
	var s2 := float(car["s"])
	if s2 < 120.0:
		return Vector2(-60.0 + s2, -60.0 + lane)
	if s2 < 240.0:
		return Vector2(60.0 - lane, -60.0 + (s2 - 120.0))
	if s2 < 360.0:
		return Vector2(60.0 - (s2 - 240.0), 60.0 - lane)
	return Vector2(-60.0 + lane, 60.0 - (s2 - 360.0))


func _crash() -> void:
	_crash_cool = CRASH_COOLDOWN_SEC
	crashes += 1
	var prev := score
	score = Logic.apply_crash(score)
	var extra := Logic.fragile_crash_penalty(fragile_index, parcel, fragile_damaged)
	if extra > 0:
		fragile_damaged = true
		score = maxi(0, score - extra)
		_set_banner(I18nService.t("mg.deliveryRush.fragile_broken", {"n": extra}))
	else:
		_set_banner(I18nService.t("mg.deliveryRush.crash", {"n": int(tune["CRASH_PENALTY"])}))
	van_speed *= 0.2
	AudioDirector.try_play(self, "mg_spill", 0.85)
	if ctx.juice != null:
		ctx.juice.shake(0.5)
		ctx.juice.hit_freeze(70)
	ctx.report_score(score, score - prev)


func _check_drop(before: Vector2) -> void:
	if parcel >= _targets.size():
		return
	var center := current_drop()
	var hit := Logic.segment_hits_drop(
		{"x": before.x, "z": before.y},
		{"x": van_pos.x, "z": van_pos.y},
		{"x": center.x, "z": center.y},
		float(tune["DROP_RADIUS_M"])
	)
	if not hit:
		return
	var prev := score
	score = Logic.apply_drop(score)
	var bonus := Logic.fragile_delivery_bonus(fragile_index, parcel, fragile_damaged)
	if bonus > 0:
		score += bonus
	drops += 1
	parcel += 1
	leg_elapsed = 0.0
	AudioDirector.try_play(self, "mg_perfect")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.float_text(_project(center), "+%d" % (score - prev), Color(1.0, 0.82, 0.35))
	_set_banner(
		I18nService.t("mg.deliveryRush.delivered", {"n": drops, "max": int(tune["PARCELS"])})
	)
	ctx.report_score(score, score - prev)
	if drops >= int(tune["PARCELS"]):
		if bool(tune["ENDLESS"]):
			# Endlos: neue Runde Ziele, weiterfahren bis 3 Pakete verfallen.
			var ids: Array[String] = []
			for row: Dictionary in Logic.LANDMARKS:
				ids.append(str(row["id"]))
			_targets = Logic.pick_deliveries(rng, ids)
			_rebuild_drop_points()
			parcel = 0
			drops = 0
			fragile_index = Logic.pick_fragile_parcel(rng)
			fragile_damaged = false
			return
		_finish_with_bonus()


func _expire_parcel() -> void:
	leg_elapsed = 0.0
	AudioDirector.try_play(self, "mg_junk")
	var ended := Logic.record_expiry(_endless_state)
	_set_banner(
		I18nService.t(
			"mg.deliveryRush.expired",
			{"n": int(_endless_state["expired"]), "max": int(_endless_state["limit"])}
		)
	)
	if ended:
		_finish()
		return
	parcel = mini(parcel + 1, _targets.size() - 1)


func _finish_with_bonus() -> void:
	var prev := score
	var bonus := Logic.time_bonus(elapsed, tune)
	score += bonus
	ctx.report_score(score, score - prev)
	_set_banner(I18nService.t("mg.deliveryRush.time_bonus", {"n": bonus}))
	AudioDirector.try_play(self, "mg_win")
	_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "drops": drops, "crashes": crashes, "elapsed": elapsed})


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.6


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.deliveryRush.expired_count",
			{"n": int(_endless_state["expired"]), "max": int(_endless_state["limit"])}
		)
	else:
		_time_label.text = I18nService.t("mg.game.time", {"sec": int(elapsed)})
	if parcel < _targets.size():
		var name_key := "mg.deliveryRush.spot.%s" % _targets[parcel]
		var mark := " ★" if parcel == fragile_index else ""
		_target_label.text = I18nService.t(
			"mg.deliveryRush.target",
			{"name": I18nService.t(name_key) + mark, "n": drops + 1, "max": int(tune["PARCELS"])}
		)


## Weltmeter (x, z) → Bildschirmpixel (Verfolgerkamera auf dem Wagen).
func _project(world: Vector2) -> Vector2:
	return (world - van_pos) * _ppm + view_size * 0.5


func _draw() -> void:
	_draw_city()
	_draw_drop_ring()
	_draw_traffic()
	_draw_van()
	_draw_compass()
	_draw_banner()


func _draw_city() -> void:
	var k := _ppm
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.63, 0.82, 0.56))
	var tile_px := Logic.TILE_M * k
	for r in Logic.GRID:
		for c in Logic.GRID:
			var w := Logic.tile_to_world(r, c)
			var pos := _project(w) - Vector2(tile_px, tile_px) * 0.5
			if (
				pos.x > view_size.x
				or pos.y > view_size.y
				or pos.x + tile_px < 0.0
				or pos.y + tile_px < 0.0
			):
				continue
			var kind := str((_grid[r][c] as Dictionary)["kind"])
			var rect := Rect2(pos, Vector2(tile_px, tile_px))
			if kind == "road":
				_draw_road_tile(rect, r, c)
			elif kind == "block":
				draw_rect(rect, Color(0.7, 0.86, 0.62))
			else:
				draw_rect(rect, Color(0.58, 0.79, 0.52))
	for b in _colliders:
		var pos := _project(Vector2(float(b["minX"]), float(b["minZ"])))
		var size := (
			Vector2(float(b["maxX"]) - float(b["minX"]), float(b["maxZ"]) - float(b["minZ"])) * k
		)
		if (
			pos.x > view_size.x
			or pos.y > view_size.y
			or pos.x + size.x < 0.0
			or pos.y + size.y < 0.0
		):
			continue
		# Häuser bekommen einen versetzten Schatten, damit die Draufsicht
		# nicht wie ein flacher Grundriss wirkt.
		draw_rect(Rect2(pos + size * 0.08, size), Color(0.35, 0.3, 0.28, 0.16))
		draw_rect(Rect2(pos, size), Color(0.93, 0.82, 0.72))
		draw_rect(Rect2(pos, size), Color(0.66, 0.5, 0.44), false, maxf(2.0, k * 0.3))
		draw_rect(
			Rect2(pos + Vector2(0.0, size.y * 0.55), Vector2(size.x, size.y * 0.45)),
			Color(0.85, 0.68, 0.58)
		)
	for row: Dictionary in Logic.LANDMARKS:
		var pos := _project(Vector2(float(row["x"]), float(row["z"])))
		draw_circle(pos, k * 1.6, Color(0.98, 0.72, 0.36, 0.85))
		draw_circle(pos, k * 0.8, Color(1.0, 0.96, 0.86))


## Eine Straßenkachel mit Gehweg und Mittelstrich. Die Striche folgen den
## befahrbaren Nachbarn, damit Kreuzungen frei bleiben — die alte Variante
## setzte nur einen Klecks in die Kachelmitte und las sich wie Konfetti.
func _draw_road_tile(rect: Rect2, r: int, c: int) -> void:
	var t := rect.size.x
	draw_rect(rect, Color(0.42, 0.43, 0.47))
	var walk := t * 0.09
	var kerb := Color(0.74, 0.73, 0.7, 0.55)
	var east := Logic.is_road(r, c + 1)
	var west := Logic.is_road(r, c - 1)
	var north := Logic.is_road(r - 1, c)
	var south := Logic.is_road(r + 1, c)
	if not north:
		draw_rect(Rect2(rect.position, Vector2(t, walk)), kerb)
	if not south:
		draw_rect(Rect2(rect.position.x, rect.end.y - walk, t, walk), kerb)
	if not west:
		draw_rect(Rect2(rect.position, Vector2(walk, t)), kerb)
	if not east:
		draw_rect(Rect2(rect.end.x - walk, rect.position.y, walk, t), kerb)
	var dash := Color(0.95, 0.92, 0.7, 0.6)
	var lw := maxf(1.5, t * 0.035)
	var mid := rect.get_center()
	var crossing := (east or west) and (north or south)
	if east or west:
		_draw_dashes(
			Vector2(rect.position.x, mid.y), Vector2(rect.end.x, mid.y), dash, lw, crossing
		)
	if north or south:
		_draw_dashes(
			Vector2(mid.x, rect.position.y), Vector2(mid.x, rect.end.y), dash, lw, crossing
		)


## Gestrichelte Mittellinie; auf Kreuzungen bleibt die Mitte frei.
func _draw_dashes(from: Vector2, to: Vector2, tint: Color, width: float, gap_center: bool) -> void:
	var steps := 4
	for i in steps:
		var a := float(i) / float(steps) + 0.12 / float(steps)
		var b := float(i + 1) / float(steps) - 0.12 / float(steps)
		if gap_center and i in [1, 2]:
			continue
		draw_line(from.lerp(to, a), from.lerp(to, b), tint, width)


func _draw_drop_ring() -> void:
	if parcel >= _drop_points.size():
		return
	var pos := _project(current_drop())
	var r := float(tune["DROP_RADIUS_M"]) * _ppm
	var pulse := 0.7 + 0.3 * sin(elapsed * 4.0)
	draw_circle(pos, r * 1.35, Color(1.0, 0.85, 0.35, 0.16 * pulse))
	draw_arc(pos, r, 0.0, TAU, 28, Color(1.0, 0.82, 0.3, pulse), maxf(3.0, _ppm * 0.7))
	draw_arc(pos, r * 0.55, 0.0, TAU, 20, Color(1.0, 0.95, 0.7, 0.7), maxf(2.0, _ppm * 0.35))


func _draw_traffic() -> void:
	var half := Vector2(CAR_WIDTH_M, CAR_LEN_M) * _ppm * 0.5
	for car in _traffic:
		var pos := _project(_traffic_pos(car))
		if (
			pos.x < -half.y * 2.0
			or pos.y < -half.y * 2.0
			or pos.x > view_size.x + half.y * 2.0
			or pos.y > view_size.y + half.y * 2.0
		):
			continue
		draw_rect(Rect2(pos - half + half * 0.22, half * 2.0), Color(0.3, 0.26, 0.24, 0.18))
		draw_rect(Rect2(pos - half, half * 2.0), Color(0.85, 0.35, 0.4))
		draw_rect(
			Rect2(pos - half * Vector2(0.7, 0.55), half * Vector2(1.4, 0.8)),
			Color(0.9, 0.95, 1.0, 0.85)
		)


func _draw_van() -> void:
	var pos := view_size * 0.5
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var side := Vector2(-dir.y, dir.x)
	var nose := VAN_LEN_M * _ppm * 0.54
	var tail := VAN_LEN_M * _ppm * 0.46
	var half_w := VAN_WIDTH_M * _ppm * 0.5
	var body := PackedVector2Array(
		[
			pos + dir * nose + side * half_w * 0.9,
			pos + dir * nose - side * half_w * 0.9,
			pos - dir * tail - side * half_w,
			pos - dir * tail + side * half_w,
		]
	)
	var shadow := PackedVector2Array()
	for p in body:
		shadow.append(p + Vector2(_ppm * 0.35, _ppm * 0.45))
	draw_colored_polygon(shadow, Color(0.25, 0.22, 0.2, 0.2))
	draw_colored_polygon(body, Color(0.98, 0.86, 0.45))
	draw_polyline(
		body + PackedVector2Array([body[0]]), Color(0.6, 0.44, 0.22), maxf(2.0, _ppm * 0.3)
	)
	draw_line(
		pos + dir * nose + side * half_w * 0.8,
		pos + dir * nose - side * half_w * 0.8,
		Color(0.6, 0.85, 1.0),
		maxf(3.0, _ppm * 0.6)
	)
	# Paketstapel auf dem Dach zeigt die Restpakete.
	var left := maxi(0, int(tune["PARCELS"]) - drops)
	var box := Vector2(1.3, 0.9) * _ppm
	for i in left:
		var col := (
			Color(0.95, 0.55, 0.35) if (parcel + i) == fragile_index else Color(0.82, 0.65, 0.45)
		)
		draw_rect(Rect2(pos - side * box.x * 0.5 - dir * (box.y * (0.3 + i * 1.15)), box), col)
	if _crash_cool > 0.0:
		draw_arc(
			pos,
			VAN_LEN_M * _ppm * 0.75,
			0.0,
			TAU,
			20,
			Color(1.0, 0.4, 0.35, _crash_cool / CRASH_COOLDOWN_SEC),
			maxf(2.0, _ppm * 0.4)
		)


## Kompass-Pfeil zum aktuellen Abwurfring (bleibt am Bildschirmrand sichtbar).
func _draw_compass() -> void:
	if parcel >= _drop_points.size():
		return
	var to := current_drop() - van_pos
	if to.length() < 1.0:
		return
	var dir := to.normalized()
	var center := view_size * 0.5
	var radius := minf(view_size.x, view_size.y) * 0.32
	var tip := center + dir * radius
	var side := Vector2(-dir.y, dir.x)
	var a := 16.0 * _ui
	draw_colored_polygon(
		PackedVector2Array(
			[
				tip + dir * a,
				tip - dir * a * 0.5 + side * a * 0.62,
				tip - dir * a * 0.5 - side * a * 0.62,
			]
		),
		Color(1.0, 0.8, 0.3, 0.92)
	)
	var font := ThemeService.font(700)
	var w := 110.0 * _ui
	draw_string(
		font,
		tip + dir * a * 1.5 - Vector2(w * 0.5, 0.0),
		"%d m" % int(to.length()),
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(13, int(18.0 * _ui)),
		Color(0.25, 0.2, 0.18)
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
		Color(0.25, 0.18, 0.16, alpha)
	)
