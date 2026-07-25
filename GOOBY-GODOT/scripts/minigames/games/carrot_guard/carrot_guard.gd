extends MinigameBase
## Karottenwache (carrotGuard) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## CarrotGuardLogic (zahlengleich zum Web, Bot-zertifiziert): 3×3 Erdhügel,
## Maulwürfe bleiben 0,9 s → 0,5 s oben, 10 Karotten im Beet, Treffer +1, jede
## 5er-Kombo +3, entwischt einer klaut er eine Karotte. Nach je 20 Treffern
## kommt der Maulwurfkönig (3 Taps, +8 + 2 Münzen). 45 s oder Beet leer;
## Endlos endet nach drei geklauten Karotten.
## Optik: Beet-Reihen mit gezeichneten Karotten, Hügel mit dicker Outline.

const MOUND := Color("A8794E")
const MOUND_DARK := Color("8A6039")
const MOLE := Color("7A6355")

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var combo := 0
var bonks := 0
var kings_spawned := 0
var carrots := 10
var elapsed := 0.0
var next_spawn := 0.0
var last_tap_at := -INF
var moles: Array[Dictionary] = []
var king: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _carrot_label: Label
var _hint_label: Label
var _holes: Array[Rect2] = []
var _pulse := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = CarrotGuardLogic.apply_difficulty(CarrotGuardLogic.GUARD, ctx.difficulty)
	rng = ctx.rng()
	carrots = int(tune["CARROTS"])
	next_spawn = CarrotGuardLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
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
	position = Vector2.ZERO
	var grid := int(tune.get("GRID", 3))
	var top := 108.0 if not landscape else 66.0
	# Hochkant bleibt unten Platz fürs Karottenbeet, quer wandert es nach rechts.
	var bed := 108.0 if not landscape else 0.0
	var right := 0.0 if not landscape else view_size.x * 0.26
	var avail := Vector2(view_size.x - 32.0 - right, maxf(120.0, view_size.y - top - bed - 52.0))
	var cell := minf(avail.x, avail.y) / float(grid)
	var board := cell * grid
	var origin := Vector2((view_size.x - right - board) * 0.5, top + (avail.y - board) * 0.5)
	_holes = []
	for row in grid:
		for col in grid:
			_holes.append(
				Rect2(
					origin + Vector2(col * cell, row * cell) + Vector2(cell * 0.08, cell * 0.08),
					Vector2.ONE * (cell * 0.84)
				)
			)
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_carrot_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 42.0)
		_hint_label.size = Vector2(340.0, 34.0)
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_carrot_label = Label.new()
	_carrot_label.theme_type_variation = &"CaptionLabel"
	add_child(_carrot_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.carrotGuard.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_pulse += delta
	_spawn_tick(delta)
	_mole_tick(delta)
	if CarrotGuardLogic.is_round_over(
		{"elapsed": elapsed, "carrots": carrots}, float(tune["DURATION_SEC"]), tune
	):
		_finish()
		return
	_update_labels()
	queue_redraw()


func _spawn_tick(delta: float) -> void:
	if not king.is_empty():
		return
	next_spawn -= delta
	if next_spawn > 0.0:
		return
	next_spawn = CarrotGuardLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	if CarrotGuardLogic.is_king_due(bonks, kings_spawned):
		_spawn_king()
		return
	var count := 1
	if rng.next() < CarrotGuardLogic.double_chance_at(elapsed, float(tune["DURATION_SEC"]), tune):
		count = 2
	for _i in count:
		var free_holes := _free_holes()
		if free_holes.is_empty():
			return
		var hole: int = free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))]
		(
			moles
			. append(
				{
					"hole": hole,
					"left": CarrotGuardLogic.up_time_at(elapsed, float(tune["DURATION_SEC"]), tune),
					"up": 0.0,
				}
			)
		)


func _spawn_king() -> void:
	kings_spawned += 1
	var free_holes := _free_holes()
	if free_holes.is_empty():
		return
	king = {
		"hole": free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))],
		"hp": int(CarrotGuardLogic.GUARD["KING_TAPS"]),
		"up": 0.0,
	}
	AudioDirector.try_play(self, "gvz_boss")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.8)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 110.0, view_size.y * 0.24),
			I18nService.t("mg.carrotGuard.king"),
			AcTokens.GOLD
		)


func _mole_tick(delta: float) -> void:
	if not king.is_empty():
		king["up"] = minf(1.0, float(king["up"]) + delta / float(tune["POP_SEC"]))
		return
	var kept: Array[Dictionary] = []
	for mole in moles:
		mole["up"] = minf(1.0, float(mole["up"]) + delta / float(tune["POP_SEC"]))
		mole["left"] = float(mole["left"]) - delta
		if float(mole["left"]) > 0.0:
			kept.append(mole)
			continue
		# Entwischt: eine Karotte weg, Kombo futsch.
		var escaped := CarrotGuardLogic.apply_escape({"carrots": carrots, "combo": combo})
		carrots = int(escaped["carrots"])
		combo = int(escaped["combo"])
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.28)
			ctx.juice.float_text(
				_holes[int(mole["hole"])].get_center(),
				I18nService.t("mg.carrotGuard.steal"),
				AcTokens.DANGER
			)
	moles = kept


func _free_holes() -> Array[int]:
	var used := {}
	for mole in moles:
		used[int(mole["hole"])] = true
	if not king.is_empty():
		used[int(king["hole"])] = true
	var out: Array[int] = []
	for i in _holes.size():
		if not used.has(i):
			out.append(i)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var since := elapsed - last_tap_at
	if not CarrotGuardLogic.accepts_tap_after(
		since, float(CarrotGuardLogic.GUARD["TAP_DEBOUNCE_SEC"])
	):
		return
	last_tap_at = elapsed
	var hole := _hole_at((event as InputEventScreenTouch).position)
	if hole < 0:
		return
	if not king.is_empty() and int(king["hole"]) == hole:
		_tap_king()
		return
	for i in moles.size():
		if int(moles[i]["hole"]) != hole:
			continue
		_bonk(i)
		return
	# Danebengehauen: kein Punktverlust, aber die Kombo ist weg.
	combo = int(CarrotGuardLogic.apply_whiff({"combo": combo})["combo"])
	AudioDirector.try_play(self, "mg_junk", 0.9)


func _bonk(index: int) -> void:
	var hole := int(moles[index]["hole"])
	moles.remove_at(index)
	var result := CarrotGuardLogic.apply_bonk({"score": score, "combo": combo})
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	var pos := _holes[hole].get_center()
	AudioDirector.try_play(self, "gvz_pop", 1.0 + 0.02 * minf(combo, 10.0))
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % delta, AcTokens.LEAF_DARK)
		ctx.juice.hit_freeze(45)
		if int(result["bonus"]) > 0:
			AudioDirector.try_play(self, "mg_combo")
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.float_text(
				pos - Vector2(0.0, 40.0), I18nService.t("mg.carrotGuard.combo"), AcTokens.PINK
			)
	ctx.report_score(score, delta)


func _tap_king() -> void:
	var result := CarrotGuardLogic.apply_king_tap(
		{"score": score, "combo": combo, "hp": int(king["hp"])}
	)
	var pos := _holes[int(king["hole"])].get_center()
	king["hp"] = int(result["hp"])
	AudioDirector.try_play(self, "gvz_boom")
	if not bool(result["complete"]):
		if ctx.juice != null:
			ctx.juice.shake(0.2)
			ctx.juice.float_text(pos, "×%d" % int(result["hp"]), AcTokens.GOLD)
		return
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	king = {}
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.slowmo(0.4, 260)
		ctx.juice.float_text(pos, I18nService.t("mg.carrotGuard.king_defeated"), AcTokens.GOLD)
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	if carrots <= 0 and ctx.juice != null:
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.4),
			I18nService.t("mg.carrotGuard.empty"),
			AcTokens.DANGER
		)
	ctx.report_end({"score": score, "carrots": carrots, "stolen": int(tune["CARROTS"]) - carrots})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.carrotGuard.stolen",
			{"n": int(tune["CARROTS"]) - carrots, "max": int(tune["ENDLESS_STOLEN"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_carrot_label.text = I18nService.t(
		"mg.carrotGuard.carrots", {"n": carrots, "max": int(tune["CARROTS"])}
	)


func _hole_at(screen: Vector2) -> int:
	for i in _holes.size():
		if _holes[i].has_point(screen):
			return i
	return -1


func _draw() -> void:
	_draw_meadow()
	for i in _holes.size():
		_draw_hole(i)
	for mole in moles:
		_draw_mole(int(mole["hole"]), float(mole["up"]), false)
	if not king.is_empty():
		_draw_mole(int(king["hole"]), float(king["up"]), true)
	_draw_carrot_bed()
	_draw_gooby()


## Wiese mit gemähten Bahnen, Hecke am Horizont und Streublümchen — sonst
## liest der Hintergrund als eine einzige grüne Fläche.
func _draw_meadow() -> void:
	var horizon := 76.0
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("BFE3A8"))
	draw_rect(Rect2(0.0, 0.0, view_size.x, horizon), Color("CFEAF7"))
	var stripe := maxf(48.0, view_size.y * 0.075)
	var row := 0
	var y := horizon
	while y < view_size.y:
		if row % 2 == 1:
			draw_rect(Rect2(0.0, y, view_size.x, stripe), Color("B4DC9B"))
		y += stripe
		row += 1
	# Hecke NACH den Mähbahnen, sonst frisst die erste Bahn ihre untere Hälfte.
	var bush := 30.0
	for i in int(view_size.x / bush) + 2:
		draw_circle(Vector2(float(i) * bush, horizon + 4.0), bush * 0.9, Color("74B060"))
	for i in int(view_size.x / bush) + 2:
		draw_arc(
			Vector2(float(i) * bush, horizon + 4.0), bush * 0.9, PI, TAU, 14, Color("5C9349"), 3.0
		)
	draw_line(Vector2(0.0, horizon), Vector2(view_size.x, horizon), AcTokens.INK, 3.0)
	_draw_daisies(horizon)


## Ein paar Gänseblümchen an den Rändern — nie unter den Hügeln, damit sie
## nicht als Bildrauschen zwischen den Löchern liegen.
func _draw_daisies(horizon: float) -> void:
	var band := maxf(80.0, view_size.y - horizon - 200.0)
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		var fx := view_size.x * 0.5 + side * (view_size.x * 0.42 - fmod(float(i) * 23.0, 26.0))
		var fy := horizon + 46.0 + fmod(float(i) * 173.0, band)
		draw_line(Vector2(fx, fy + 16.0), Vector2(fx, fy), Color("4E8F3C"), 3.0)
		for k in 5:
			var a := float(k) * TAU / 5.0
			draw_circle(Vector2(fx, fy) + Vector2(cos(a), sin(a)) * 6.0, 4.5, AcTokens.WHITE)
		draw_circle(Vector2(fx, fy), 4.0, AcTokens.YELLOW)


func _draw_hole(index: int) -> void:
	var rect := _holes[index]
	var center := rect.get_center()
	var r := rect.size.x * 0.46
	draw_circle(center + Vector2(0.0, r * 0.18), r, MOUND_DARK)
	draw_circle(center, r * 0.92, MOUND)
	draw_arc(center, r * 0.92, 0.0, TAU, 26, AcTokens.INK, 3.0)
	# Loch als flache Ellipse — dadurch liest der Hügel als Erdloch von schräg
	# oben und der Maulwurf kann sichtbar daraus auftauchen.
	var socket := _socket_of(index)
	draw_set_transform(socket.position, 0.0, Vector2(1.0, socket.size.y / socket.size.x))
	draw_circle(Vector2.ZERO, socket.size.x, Color("3A2A1E"))
	draw_arc(Vector2.ZERO, socket.size.x, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mittelpunkt (position) und Halbachsen (size) des Erdlochs.
func _socket_of(index: int) -> Rect2:
	var rect := _holes[index]
	var r := rect.size.x * 0.46
	return Rect2(rect.get_center() + Vector2(0.0, r * 0.06), Vector2(r * 0.68, r * 0.38))


func _draw_mole(hole: int, up: float, is_king: bool) -> void:
	var socket := _socket_of(hole)
	var sc := socket.position
	var r := socket.size.x * (0.74 if not is_king else 0.88)
	# Steigt aus dem Loch: bei up=0 komplett unter der Lochkante.
	var pos := Vector2(sc.x, lerpf(sc.y + r * 1.15, sc.y - r * 0.78, clampf(up, 0.0, 1.0)))
	var fur := MOLE if not is_king else Color("6A4E7A")
	var fur_dark := fur.darkened(0.22)
	# Ohren + Körper.
	draw_circle(pos + Vector2(-r * 0.72, -r * 0.6), r * 0.26, fur_dark)
	draw_circle(pos + Vector2(r * 0.72, -r * 0.6), r * 0.26, fur_dark)
	draw_circle(pos, r, fur)
	draw_arc(pos, r, 0.0, TAU, 24, AcTokens.INK, 3.0)
	# Schnauze mit Nase und Barthaaren.
	draw_circle(pos + Vector2(0.0, r * 0.3), r * 0.42, Color("D8B7A2"))
	draw_arc(pos + Vector2(0.0, r * 0.3), r * 0.42, 0.0, TAU, 18, AcTokens.INK, 2.0)
	draw_circle(pos + Vector2(0.0, r * 0.16), r * 0.15, Color("4A3B36"))
	for side in [-1.0, 1.0]:
		for k in 2:
			var from := pos + Vector2(side * r * 0.38, r * 0.26 + float(k) * r * 0.16)
			draw_line(from, from + Vector2(side * r * 0.5, -r * 0.06), AcTokens.INK, 1.6)
	draw_circle(pos + Vector2(-r * 0.34, -r * 0.2), r * 0.13, AcTokens.INK)
	draw_circle(pos + Vector2(r * 0.34, -r * 0.2), r * 0.13, AcTokens.INK)
	draw_circle(pos + Vector2(-r * 0.3, -r * 0.24), r * 0.05, AcTokens.WHITE)
	draw_circle(pos + Vector2(r * 0.38, -r * 0.24), r * 0.05, AcTokens.WHITE)
	if is_king:
		_draw_crown(pos, r)
	# Vordere Lochkante DECKT den Unterkörper ab — erst dadurch sieht es aus,
	# als käme der Maulwurf wirklich aus dem Loch.
	_draw_socket_front(socket)
	if not is_king:
		return
	for i in int(king.get("hp", 0)):
		var at := Vector2(
			sc.x - socket.size.x * 0.6 + float(i) * socket.size.x * 0.6, sc.y + socket.size.y + 14.0
		)
		draw_circle(at, 6.0, AcTokens.DANGER)
		draw_arc(at, 6.0, 0.0, TAU, 12, AcTokens.INK, 2.0)


func _draw_crown(pos: Vector2, r: float) -> void:
	var crown := pos + Vector2(0.0, -r * 1.05)
	var points := PackedVector2Array(
		[
			crown + Vector2(-r * 0.7, r * 0.3),
			crown + Vector2(-r * 0.42, -r * 0.35),
			crown + Vector2(0.0, r * 0.05),
			crown + Vector2(r * 0.42, -r * 0.35),
			crown + Vector2(r * 0.7, r * 0.3),
		]
	)
	draw_colored_polygon(points, AcTokens.GOLD)
	draw_polyline(points, AcTokens.INK, 2.5)


## Untere Hälfte der Loch-Ellipse als Erdlippe vor dem Maulwurf.
func _draw_socket_front(socket: Rect2) -> void:
	var points := PackedVector2Array()
	var steps := 22
	for i in steps + 1:
		var a := lerpf(0.0, PI, float(i) / float(steps))
		points.append(socket.position + Vector2(cos(a) * socket.size.x, sin(a) * socket.size.y))
	draw_colored_polygon(points, MOUND)
	draw_polyline(points, AcTokens.INK, 3.0)


## Karottenbeet: jede verbliebene Karotte ist eine gezeichnete Möhre.
func _draw_carrot_bed() -> void:
	var total := int(tune["CARROTS"])
	var strip_y := view_size.y - 84.0
	var strip_x := 24.0
	var strip_w := view_size.x - 48.0
	if landscape:
		strip_y = 96.0
		strip_x = view_size.x - view_size.x * 0.24
		strip_w = view_size.x * 0.2
	draw_rect(Rect2(strip_x - 8.0, strip_y - 26.0, strip_w + 16.0, 52.0), Color("9CCB7C"))
	draw_rect(Rect2(strip_x - 8.0, strip_y - 26.0, strip_w + 16.0, 52.0), AcTokens.INK, false, 3.0)
	for i in total:
		var t := (float(i) + 0.5) / float(total)
		var pos := Vector2(strip_x + strip_w * t, strip_y)
		if landscape:
			pos = Vector2(strip_x + strip_w * 0.5, strip_y - 18.0 + i * 5.0)
		var alive := i < carrots
		var body := Color("F2913D") if alive else Color(0.6, 0.55, 0.5, 0.35)
		draw_colored_polygon(
			PackedVector2Array(
				[pos + Vector2(-7.0, -8.0), pos + Vector2(7.0, -8.0), pos + Vector2(0.0, 14.0)]
			),
			body
		)
		if alive:
			draw_rect(Rect2(pos.x - 5.0, pos.y - 16.0, 4.0, 8.0), AcTokens.LEAF_DARK)
			draw_rect(Rect2(pos.x + 1.0, pos.y - 16.0, 4.0, 8.0), AcTokens.LEAF_DARK)


## Gooby-Cameo: hält Wache mit erhobenem Löffel.
func _draw_gooby() -> void:
	var base := Vector2(view_size.x - 54.0, 46.0)
	if landscape:
		base = Vector2(52.0, view_size.y - 54.0)
	var r := 21.0 + sin(_pulse * 3.0) * 1.5
	for side in [-1.0, 1.0]:
		var ear_root := base + Vector2(side * r * 0.42, -r * 0.72)
		var ear_tip := ear_root + Vector2(side * r * 0.34, -r * 0.85)
		draw_line(ear_root, ear_tip, Color(0.98, 0.88, 0.66), r * 0.32)
		draw_circle(ear_tip, r * 0.16, Color(0.98, 0.88, 0.66))
	draw_circle(base, r, Color(0.99, 0.91, 0.7))
	draw_arc(base, r, 0.0, TAU, 24, AcTokens.INK, 3.0)
	draw_circle(base + Vector2(-r * 0.32, -r * 0.14), r * 0.11, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.32, -r * 0.14), r * 0.11, AcTokens.INK)
	draw_arc(base + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 10, AcTokens.INK, 2.4)
