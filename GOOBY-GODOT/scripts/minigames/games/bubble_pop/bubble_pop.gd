extends MinigameBase
## Blasen-Platzer (bubblePop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## BubblePopLogic (zahlengleich zum Web, Bot-zertifiziert): Zielessen rotiert
## alle 12 s, Treffer +2, falsche Blase −2 + 0,5 s Stun, Stachelblasen platzen
## nie (Antippen −1), Steig- und Spawn-Kadenz rampen linear, drei gleiche
## Treffer in 2 s zünden eine Kettenreaktion über die Nachbarblasen.
## Optik: Pastell-Unterwasser mit dicken Outlines, farbenblind-sichere Symbole
## auf jeder Blase (Web-Tabelle), Gooby-Cameo taucht unten mit.

## Sichtbare Welt-Halbbreite in Logik-Einheiten (Web-Kamera ≈ 3.25 bei 390 px).
## Halbe sichtbare Welthöhe — im Web `tan(CAMERA_FOV/2) * 10` bei FOV 45°
## (bubblePop.js: `halfH = Math.tan(degToRad(camera.fov / 2)) * 10`,
## `halfW = halfH * (innerWidth / innerHeight)`). Der Blasenradius und die
## Steiggeschwindigkeit der Logik sind auf DIESEN Rahmen geeicht.
const WORLD_HALF_H := 4.142135623730951
## Blasenradius in Welteinheiten (Optik; getippt wird über touch_radius_for).
const BUBBLE_R := 0.42
const SPIKY_R := 0.5

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var streak := 0
var spiky_pops := 0
var stun_until := -1.0
var next_spawn := 0.0
var target_order: Array[String] = []
var chain: Dictionary = {}
var bubbles: Array[Dictionary] = []
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _streak_label: Label
var _hint_label: Label
var _banner_label: Label
var _bob := 0.0
var _hud_plate := _make_hud_plate()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BubblePopLogic.apply_difficulty(BubblePopLogic.BUBBLE, ctx.difficulty)
	rng = ctx.rng()
	chain = BubblePopLogic.create_pop_chain()
	# Genug Ziel-Slots für die ganze Runde (Endlos bekommt reichlich Vorrat).
	var slots := int(ceil(float(tune["DURATION_SEC"]) / float(tune["TARGET_ROTATE_SEC"]))) + 24
	target_order = BubblePopLogic.target_order(rng, slots)
	next_spawn = BubblePopLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
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
	if _time_label == null:
		return
	_time_label.position = Vector2(16.0, 10.0)
	_streak_label.position = Vector2(16.0, 48.0)
	var banner_w := minf(view_size.x - 32.0, 420.0)
	_banner_label.position = Vector2(
		(view_size.x - banner_w) * 0.5, 84.0 if not landscape else 12.0
	)
	_banner_label.size = Vector2(banner_w, 44.0)
	_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 46.0)
	_hint_label.size = Vector2(340.0, 36.0)
	queue_redraw()


## Aktives Zielessen zum Rundenzeitpunkt.
func target_food() -> String:
	if target_order.is_empty():
		return "carrot"
	var idx := BubblePopLogic.target_index_at(elapsed, tune)
	return target_order[idx % target_order.size()]


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	add_child(_streak_label)
	_banner_label = Label.new()
	_banner_label.theme_type_variation = &"TitleLabel"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_banner_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.bubblePop.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_bob += delta
	_spawn_tick(delta)
	_rise_tick(delta)
	if BubblePopLogic.endless_should_end(spiky_pops, tune):
		_finish()
		return
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_update_labels()
	queue_redraw()


func _spawn_tick(delta: float) -> void:
	next_spawn -= delta
	if next_spawn > 0.0:
		return
	next_spawn = BubblePopLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var rolled := BubblePopLogic.roll_bubble(rng, target_food(), tune)
	var half_w := _half_w()
	(
		bubbles
		. append(
			{
				"kind": rolled["kind"],
				"food": rolled["food"],
				"x": (rng.next() * 2.0 - 1.0) * maxf(0.2, half_w - 0.6),
				"y": -_half_h() - 0.6,
				"wobble": rng.next() * TAU,
				"active": true,
			}
		)
	)


func _rise_tick(delta: float) -> void:
	var speed := BubblePopLogic.rise_speed_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var top := _half_h() + 0.7
	var kept: Array[Dictionary] = []
	for bubble in bubbles:
		bubble["y"] = float(bubble["y"]) + speed * delta
		if float(bubble["y"]) <= top:
			kept.append(bubble)
	bubbles = kept


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	if elapsed < stun_until:
		return
	var world := _to_world((event as InputEventScreenTouch).position)
	var hit := _bubble_at(world)
	if hit < 0:
		return
	_pop(hit)


## Index der getroffenen Blase (nächste zuerst) oder −1.
func _bubble_at(world: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in bubbles.size():
		var bubble: Dictionary = bubbles[i]
		var radius := BubblePopLogic.touch_radius_for(str(bubble["kind"]))
		var d := Vector2(float(bubble["x"]) - world.x, float(bubble["y"]) - world.y).length()
		if d <= radius and d < best_d:
			best = i
			best_d = d
	return best


func _pop(index: int) -> void:
	var bubble: Dictionary = bubbles[index]
	var result := BubblePopLogic.pop_result(bubble, target_food())
	var delta := int(result["delta"])
	score = BubblePopLogic.apply_score(score, delta)
	var pos := _to_screen(Vector2(float(bubble["x"]), float(bubble["y"])))
	match str(result["result"]):
		"match":
			streak += 1
			_celebrate_match(bubble, pos, delta)
		"wrong":
			streak = 0
			stun_until = elapsed + float(result["stunSec"])
			AudioDirector.try_play(self, "mg_junk")
			if ctx.juice != null:
				ctx.juice.float_text(pos, I18nService.t("mg.bubblePop.wrong"), AcTokens.DANGER)
				ctx.juice.shake(0.35)
				ctx.juice.hit_freeze(80)
		_:
			streak = 0
			spiky_pops += 1
			AudioDirector.try_play(self, "mg_spill")
			if ctx.juice != null:
				ctx.juice.float_text(pos, I18nService.t("mg.bubblePop.spiky"), AcTokens.DANGER)
				ctx.juice.shake(0.3)
	if bool(result["pops"]):
		bubbles.remove_at(index)
	ctx.report_score(score, delta)


func _celebrate_match(bubble: Dictionary, pos: Vector2, delta: int) -> void:
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.02 * minf(streak, 12.0))
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % delta, AcTokens.LEAF_DARK)
	var style := str(bubble["food"])
	var fired: Dictionary = BubblePopLogic.record_pop_chain(chain, style, elapsed)
	if bool(fired["triggered"]):
		_chain_burst(style, float(bubble["x"]), float(bubble["y"]), pos)
	if BubblePopLogic.match_streak_milestone(streak):
		AudioDirector.try_play(self, "mg_combo", 1.0 + 0.03 * minf(streak, 20.0))
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.float_text(
				pos - Vector2(0.0, 42.0),
				I18nService.t("mg.game.streak", {"n": streak}),
				AcTokens.PINK
			)


## Kettenreaktion: alle gleichfarbigen Nachbarn im Radius platzen mit.
func _chain_burst(style: String, x: float, y: float, pos: Vector2) -> void:
	var neighbours := BubblePopLogic.chain_neighbor_indices(
		bubbles, style, x, y, float(BubblePopLogic.BUBBLE["CHAIN_RADIUS"])
	)
	neighbours.reverse()
	var gained := 0
	for i in neighbours:
		gained += int(BubblePopLogic.BUBBLE["MATCH_PTS"])
		bubbles.remove_at(i)
	if gained > 0:
		score = BubblePopLogic.apply_score(score, gained)
		ctx.report_score(score, gained)
	AudioDirector.try_play(self, "mg_golden")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.slowmo(0.4, 260)
		ctx.juice.float_text(
			pos - Vector2(0.0, 20.0), I18nService.t("mg.bubblePop.chain"), AcTokens.GOLD
		)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "spikyPops": spiky_pops, "elapsed": elapsed})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.bubblePop.spikes", {"n": spiky_pops, "max": int(tune["ENDLESS_SPIKY_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_streak_label.text = (I18nService.t("mg.game.streak", {"n": streak}) if streak > 1 else "")
	var food := target_food()
	_banner_label.text = I18nService.t(
		"mg.bubblePop.target", {"food": I18nService.t("mg.bubblePop.food_%s" % _food_key(food))}
	)


func _food_key(food: String) -> String:
	return "donut" if food == "donut-sprinkles" else food


## Pixel pro Welteinheit — Hochkant an der Breite, Quer an der Höhe.
func _ppu() -> float:
	# Immer an der HÖHE geeicht (wie die vertikale Kamera-FOV im Web) — die
	# frühere Fassung mass im Hochformat an der Breite und machte die Welt
	# dadurch rund 70 % zu hoch, die Blasen entsprechend zu klein.
	return view_size.y / (WORLD_HALF_H * 2.0)


func _half_w() -> float:
	return view_size.x * 0.5 / _ppu()


func _half_h() -> float:
	return view_size.y * 0.5 / _ppu()


func _to_screen(world: Vector2) -> Vector2:
	var ppu := _ppu()
	return Vector2(view_size.x * 0.5 + world.x * ppu, view_size.y * 0.5 - world.y * ppu)


func _to_world(screen: Vector2) -> Vector2:
	var ppu := _ppu()
	return Vector2((screen.x - view_size.x * 0.5) / ppu, (view_size.y * 0.5 - screen.y) / ppu)


func _draw() -> void:
	_draw_water()
	for bubble in bubbles:
		_draw_bubble(bubble)
	# Nach den Blasen: der Cameo sass sonst regelmässig hinter einer Blase.
	_draw_gooby()
	_draw_hud_backing()
	if elapsed < stun_until:
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.9, 0.4, 0.4, 0.16))


## Milchglas hinter Zeit und Serie. Die Labels sind Kinder und landen dadurch
## obenauf; im Querformat reicht das Wasser bis an die Oberkante und aufsteigende
## Blasen zogen sonst direkt durch die Ziffern.
static func _make_hud_plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.99, 0.94, 0.72)
	box.set_corner_radius_all(16)
	return box


func _draw_hud_backing() -> void:
	if _time_label == null:
		return
	var top_left := _time_label.position - Vector2(12.0, 6.0)
	var bottom_right := (
		_streak_label.position
		+ Vector2(maxf(_time_label.size.x, _streak_label.size.x), _streak_label.size.y)
		+ Vector2(12.0, 6.0)
	)
	draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))


func _draw_water() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), AcTokens.SKY_SOFT)
	# Sanfte Lichtbahnen von oben + heller Wasserspiegel.
	for i in 6:
		var x := view_size.x * (0.08 + i * 0.17)
		var top := Vector2(x, 0.0)
		var bottom := Vector2(x + view_size.x * 0.06, view_size.y)
		draw_line(top, bottom, Color(1.0, 1.0, 1.0, 0.10), 26.0)
	draw_rect(Rect2(0.0, 0.0, view_size.x, 6.0), Color(1.0, 1.0, 1.0, 0.55))
	draw_rect(Rect2(0.0, view_size.y - 52.0, view_size.x, 52.0), Color(0.58, 0.79, 0.62))
	for i in 9:
		var wx := view_size.x * (0.05 + i * 0.11)
		var sway := sin(_bob * 1.4 + float(i)) * 7.0
		draw_line(
			Vector2(wx, view_size.y - 46.0),
			Vector2(wx + sway, view_size.y - 96.0),
			Color(0.42, 0.66, 0.44),
			7.0
		)


func _draw_bubble(bubble: Dictionary) -> void:
	var wobble := sin(_bob * 2.2 + float(bubble["wobble"])) * 0.06
	var pos := _to_screen(Vector2(float(bubble["x"]) + wobble, float(bubble["y"])))
	var ppu := _ppu()
	if str(bubble["kind"]) == "spiky":
		# Stachelblase bleibt bewusst matt und kühl: sie ist die Gefahr, darf
		# aber die bunten Ess-Blasen optisch nicht erschlagen.
		var r := SPIKY_R * ppu
		for i in 10:
			var a := TAU * i / 10.0 + _bob * 0.4
			draw_line(
				pos + Vector2(cos(a), sin(a)) * r * 0.74,
				pos + Vector2(cos(a), sin(a)) * r * 1.16,
				Color(0.46, 0.42, 0.52, 0.75),
				3.0
			)
		draw_circle(pos, r * 0.78, Color(0.58, 0.56, 0.66, 0.5))
		draw_arc(pos, r * 0.78, 0.0, TAU, 24, Color(0.32, 0.28, 0.36, 0.8), 3.0)
		draw_circle(pos + Vector2(-r * 0.26, -r * 0.28), r * 0.14, Color(1, 1, 1, 0.45))
		return
	var food := str(bubble["food"])
	var tint := Mg1FoodArt.tint_of(food)
	var r := BUBBLE_R * ppu
	var wanted := food == target_food()
	# Gesuchte Sorte pulsiert leicht und trägt einen Zielring — das ist die
	# einzige Information, die der Spieler in der Sekunde wirklich braucht.
	if wanted:
		var halo := r * (1.24 + sin(_bob * 4.0) * 0.05)
		draw_circle(pos, halo, Color(tint.r, tint.g, tint.b, 0.2))
		draw_arc(pos, halo, 0.0, TAU, 30, Color(1.0, 1.0, 1.0, 0.75), 4.0)
	draw_circle(pos, r, Color(tint.r, tint.g, tint.b, 0.3))
	draw_circle(pos, r, Color(1.0, 1.0, 1.0, 0.28))
	Mg1FoodArt.draw(self, food, pos, r * 0.7)
	draw_arc(pos, r, 0.0, TAU, 28, AcTokens.INK, 3.0)
	# Glanzlicht und Seifenschimmer auf der Blasenhaut.
	draw_arc(pos, r * 0.82, PI * 1.05, PI * 1.5, 12, Color(1, 1, 1, 0.8), 5.0)
	draw_circle(pos + Vector2(r * 0.42, r * 0.34), r * 0.1, Color(1, 1, 1, 0.5))


## Gooby taucht unten mit und schaut den Blasen hinterher.
func _draw_gooby() -> void:
	var r := clampf(view_size.y * 0.042, 26.0, 52.0)
	# Immer vollständig über der Wasserpflanzen-Kante und nie angeschnitten.
	var base := Vector2(
		maxf(r * 1.8, view_size.x * 0.16), view_size.y - 108.0 - r + sin(_bob * 1.6) * 5.0
	)
	var fur := Color(0.99, 0.91, 0.7)
	# Taucherblasen steigen aus dem Cameo auf.
	for i in 3:
		var phase := fmod(_bob * 0.5 + float(i) * 0.33, 1.0)
		draw_circle(
			base + Vector2(r * 0.9 + float(i) * 5.0, -r - phase * r * 2.4),
			r * (0.1 + phase * 0.06),
			Color(1, 1, 1, 0.5 * (1.0 - phase))
		)
	# Ohren wachsen AUS dem Kopf (frei schwebende Kreise sahen abgetrennt aus).
	for side in [-1.0, 1.0]:
		var ear_root := base + Vector2(side * r * 0.42, -r * 0.72)
		var ear_tip := ear_root + Vector2(side * r * 0.34, -r * 0.85)
		draw_line(ear_root, ear_tip, Color(0.98, 0.88, 0.66), r * 0.32)
		draw_circle(ear_tip, r * 0.16, Color(0.98, 0.88, 0.66))
	draw_circle(base, r, fur)
	draw_arc(base, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_circle(base + Vector2(-r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(-r * 0.62, r * 0.22), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	draw_circle(base + Vector2(r * 0.62, r * 0.22), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	draw_arc(base + Vector2(0.0, r * 0.16), r * 0.32, 0.3, PI - 0.3, 12, AcTokens.INK, 2.5)
