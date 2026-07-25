extends MinigameBase
## Gooby Einkaufs-Surf (shoppingSurf) — Spiel-Szene. Die GESAMTE Mechanik
## läuft über ShoppingSurfRun.step_run(), also bit-genau die Web-Simulation:
## 3 Spuren à 1,6 m, Tempo 8 → 16 m/s, Wagen/Kisten/Passanten/Markisen/
## Pfützen/Bordsteinlücken, Münzen ×2 mit Power-up, Beinahe-Treffer +2,
## 3 Crashes = Aus. Der View füttert nur Eingaben hinein und spielt die
## zurückgelieferten Ereignisse als Klang, Juice und Banner ab.
##
## 2D statt 3D (Web war three.js): der Korridor ist eine reine Tiefenachse
## und die Kollisionen laufen ohnehin in Weltmetern in der reinen Logik. Eine
## perspektivische Sticker-Projektion (project()) hält JEDE Zahl exakt, kostet
## kein 3D-Kit (das Godot-Projekt hat keins) und liest sich auf dem Handy
## deutlich sauberer als ein Mini-3D-Nachbau.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `cart_skin` /
## `speed_bonus` bleiben leer, bis das Autohaus Fahrzeuge liefert.

const Logic := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_logic.gd")
const Run := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_run.gd")
const Street := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_street.gd")

## Kamera-/Zeichenzahlen der Darstellung (KEINE Spiel-Mathe).
const CAM_BEHIND := 6.6
## Halbe Fahrbahnbreite (m): Spuren ±1,6 m plus Randstreifen.
const ROAD_HALF := 2.6
## Sichtweite (m) und Nahgrenze hinter der Kamera.
const DRAW_Z := -62.0
const DRAW_NEAR_Z := 1.4
## Läden verschwinden früher als die Straße — sonst kleben angeschnittene
## Fassaden-Klötze am Bildrand.
const SHOP_NEAR_Z := -9.0
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

## Autohaus-Haken: später vom Host befüllbar.
var cart_skin := ""
var speed_bonus := 0.0

## Für Screenshot-/Zertifizierungsläufe: der §C8.7-Bot übernimmt.
var autoplay := false

var tune: Dictionary = {}
var run: Dictionary = {}
var score := 0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _shops: Array[Vector3] = []
var _focal_px := 400.0
var _cam_y := 1.7
var _horizon_px := 200.0
var _ui := 1.0
var _swipe_from := Vector2.ZERO
var _swipe_live := false
var _held: Dictionary = {}
var _banner := ""
var _banner_t := 0.0
var _flash_t := 0.0
var _score_label: Label
var _stat_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SURF, ctx.difficulty)
	run = Run.create_run(ctx.rng(), "arcade", tune)
	var deco := ctx.rng(ctx.run_seed ^ 0x51F5)
	for i in 22:
		# x-Seite (±1), z-Tiefe, Laden-Variante 0..1.
		_shops.append(Vector3(-1.0 if i % 2 == 0 else 1.0, -i * 5.5 - 4.0, deco.next()))
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


## Welt (x, y, z) → Bildschirmpixel; z < 0 = vor Gooby.
func project(wx: float, wy: float, wz: float) -> Vector2:
	var s := scale_at(wz)
	return Vector2(view_size.x * 0.5 + wx * s, _horizon_px + (_cam_y - wy) * s)


## Pixel pro Meter in dieser Tiefe (für Größen).
func scale_at(wz: float) -> float:
	return _focal_px / maxf(0.4, CAM_BEHIND - wz)


## Kamera aus dem Layout ableiten: die Straße füllt einen festen Anteil der
## Breite, die Füße stehen auf einem festen Anteil der Höhe. Damit sitzt
## Gooby in BEIDEN Orientierungen richtig (feste Werte kippten ihn hochkant
## aus dem Bild — dieselbe Falle wie beim Renner).
func _recompute_camera() -> void:
	var road_fill := 0.46 if landscape else 0.82
	var horizon_frac := 0.34 if landscape else 0.32
	var feet_frac := 0.8 if landscape else 0.74
	_focal_px = road_fill * view_size.x * CAM_BEHIND / (2.0 * ROAD_HALF)
	_horizon_px = view_size.y * horizon_frac
	_cam_y = (view_size.y * feet_frac - _horizon_px) * CAM_BEHIND / _focal_px


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	add_child(_score_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.shoppingSurf.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	_update_labels()


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
			AudioDirector.try_play(self, "mg_spill", 0.9)
			_set_banner(I18nService.t("mg.shoppingSurf.puddle"))
		"shieldPop":
			_on_shield_pop()
		"crash":
			_on_crash(int(e["crashes"]))
		"telegraph":
			AudioDirector.try_play(self, "ui_tick", 1.1)
		_:
			pass


func _on_coin(e: Dictionary) -> void:
	AudioDirector.try_play(self, "mg_good")
	if ctx.juice == null:
		return
	var pos := project(float(e["x"]), float(e["y"]) + 0.4, float(e["z"]))
	ctx.juice.float_text(pos, "+%d" % int(e["value"]), Color(1.0, 0.84, 0.42))


func _on_near_miss(e: Dictionary) -> void:
	var streak := int(e["streak"])
	AudioDirector.try_play(self, "mg_combo" if streak > 1 else "mg_perfect", 1.1)
	_set_banner(I18nService.t("mg.shoppingSurf.near", {"streak": streak}))
	if ctx.juice == null:
		return
	ctx.juice.float_text(
		Vector2(view_size.x * 0.5 - 60.0 * _ui, view_size.y * 0.44),
		I18nService.t("mg.shoppingSurf.near_pop"),
		Color(0.72, 1.0, 0.86)
	)
	if streak >= 3:
		ctx.juice.bloom_pulse(0.8)


func _on_powerup(kind: String) -> void:
	AudioDirector.try_play(self, "mg_golden")
	_set_banner(I18nService.t("mg.shoppingSurf.%s" % kind))
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		if kind == "turbo":
			ctx.juice.slowmo(0.55, 220)


func _on_shield_pop() -> void:
	AudioDirector.try_play(self, "mg_junk")
	_set_banner(I18nService.t("mg.shoppingSurf.shield_pop"))
	_flash_t = 0.35
	if ctx.juice != null:
		ctx.juice.shake(0.28)
		ctx.juice.bloom_pulse(0.7)


func _on_crash(crashes: int) -> void:
	AudioDirector.try_play(self, "mg_spill")
	_flash_t = 0.45
	var left := maxi(0, int(tune["ARCADE_MAX_CRASHES"]) - crashes)
	if left > 0:
		_set_banner(I18nService.t("mg.shoppingSurf.crash", {"left": left}))
	if ctx.juice == null:
		return
	ctx.juice.shake(0.45 if left == 0 else 0.32)
	ctx.juice.hit_freeze(110)


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


# ── Zeichnen ──────────────────────────────────────────────────────────────


func _draw() -> void:
	var project_fn := Callable(self, "project")
	Street.draw_ground(
		self,
		view_size,
		_horizon_px,
		project_fn,
		ROAD_HALF,
		DRAW_NEAR_Z,
		DRAW_Z,
		float(run["distanceM"])
	)
	_draw_shops()
	# Alles Bewegliche von HINTEN nach VORNE (Maler-Algorithmus).
	var items: Array[Dictionary] = []
	for ob: Dictionary in run["obstacles"]:
		items.append({"z": float(ob["z"]), "kind": "ob", "data": ob})
	for c: Dictionary in run["coinItems"]:
		items.append({"z": float(c["z"]), "kind": "coin", "data": c})
	for p: Dictionary in run["powerupItems"]:
		items.append({"z": float(p["z"]), "kind": "pu", "data": p})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["z"] < b["z"])
	for item: Dictionary in items:
		if float(item["z"]) < DRAW_Z or float(item["z"]) > DRAW_NEAR_Z:
			continue
		_draw_item(item)
	_draw_gooby()
	_draw_powerup_bar()
	_draw_banner()
	_draw_flash()


func _draw_item(item: Dictionary) -> void:
	var data: Dictionary = item["data"]
	var z := float(item["z"])
	var sc := scale_at(z)
	match str(item["kind"]):
		"coin":
			Street.draw_coin(
				self,
				project(float(data["x"]), float(data["y"]), z),
				sc,
				float(run["elapsed"]) * 4.0 + z * 0.3
			)
		"pu":
			Street.draw_powerup(
				self,
				project(float(data["x"]), 0.0, z),
				sc,
				str(data["kind"]),
				float(run["elapsed"]) + z * 0.2
			)
		_:
			_draw_obstacle(data, z, sc)


func _draw_obstacle(ob: Dictionary, z: float, sc: float) -> void:
	var kind := str(ob["kind"])
	var at := project(float(ob["x"]), 0.0, z)
	match kind:
		"cart":
			Street.draw_cart(self, at, sc, bool(ob["telegraphed"]))
		"crate":
			Street.draw_crate(self, at, sc)
		"npc":
			_draw_npc_with_trail(ob, z, sc, at)
		"awning":
			Street.draw_awning(
				self,
				at,
				sc,
				float(ob["halfW"]),
				float((tune["OBSTACLES"] as Dictionary)["awning"]["gapY"])
			)
		"puddle":
			Street.draw_puddle(self, at, sc, bool(ob["hit"]))
		_:
			Street.draw_gap(
				self,
				Callable(self, "project"),
				z,
				float((tune["OBSTACLES"] as Dictionary)["gap"]["halfDepth"]),
				ROAD_HALF
			)


## Passant + gepunktete Bahn (§C8.3 „gestrichelte Linie kündigt ihn an").
func _draw_npc_with_trail(ob: Dictionary, z: float, sc: float, at: Vector2) -> void:
	var x := float(ob["x"])
	var dots := 8
	for i in dots:
		var tx := x + (ROAD_HALF + 1.0 - x) * float(i + 1) / dots
		draw_circle(project(tx, 0.03, z), maxf(1.0, sc * 0.05), Color(1, 1, 1, 0.55))
	Street.draw_npc(self, at, sc, float(run["elapsed"]))


func _draw_shops() -> void:
	var sorted := _shops.duplicate()
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var offset := fposmod(float(run["distanceM"]), 121.0)
	for s: Vector3 in sorted:
		var z := s.y + offset
		if z > SHOP_NEAR_Z:
			z -= 121.0
		# Nahe Läden würden nur als angeschnittene Klötze am Bildrand kleben.
		if z < DRAW_Z or z > SHOP_NEAR_Z:
			continue
		Street.draw_shop(self, Callable(self, "project"), s.x, z, s.z, ROAD_HALF)


func _draw_gooby() -> void:
	var sc := scale_at(0.0)
	var px := Run.player_x(run)
	var py := Run.player_y(run)
	var sliding := float(run["slideT"]) >= 0.0
	var squash := float(tune["SLIDE_HEIGHT"]) / float(tune["STAND_HEIGHT"]) if sliding else 1.0
	var base := project(px, py, 0.0)
	var invuln := float(run["invulnT"])
	var alpha := 1.0 if invuln <= 0.0 else (0.4 + 0.6 * absf(sin(invuln * 22.0)))
	var body_h := sc * float(tune["STAND_HEIGHT"]) * squash * float(tune["RENDER_SCALE_MULT"])
	var body_w := sc * 0.46 * (1.0 + (1.0 - squash) * 0.6)
	_draw_ellipse(
		project(px, 0.0, 0.0),
		body_w * maxf(0.35, 0.78 - py * 0.2),
		body_w * maxf(0.12, 0.26 - py * 0.07),
		Color(0.35, 0.24, 0.28, 0.2 * alpha)
	)
	_draw_gooby_auras(base, body_h, body_w, alpha)
	var fur := Color(0.99, 0.9, 0.66, alpha)
	var ink := Color(0.32, 0.22, 0.18, alpha)
	var head := base + Vector2(0.0, -body_h * 0.68)
	var r := body_h * 0.3
	if not sliding:
		var step := sin(float(run["elapsed"]) * 16.0) * body_h * 0.1
		for side in [-1.0, 1.0]:
			draw_line(
				base + Vector2(side * body_w * 0.34, -body_h * 0.3),
				base + Vector2(side * body_w * 0.34, step * side),
				Color(0.86, 0.72, 0.5, alpha),
				maxf(3.0, body_w * 0.24)
			)
	_draw_ellipse(base + Vector2(0.0, -body_h * 0.42), body_w * 0.8, body_h * 0.29, fur)
	# Einkaufstasche in der Pfote — das Thema der Kachel.
	draw_rect(
		Rect2(base + Vector2(body_w * 0.5, -body_h * 0.46), Vector2(body_w * 0.62, body_h * 0.34)),
		Color(1.0, 0.66, 0.74, alpha)
	)
	draw_arc(
		base + Vector2(body_w * 0.81, -body_h * 0.46),
		body_w * 0.2,
		PI,
		TAU,
		10,
		Color(0.85, 0.5, 0.6, alpha),
		maxf(1.5, body_w * 0.06)
	)
	for side in [-1.0, 1.0]:
		draw_circle(head + Vector2(side * r * 0.62, -r * 0.82), r * 0.34, fur)
	draw_circle(head, r, fur)
	var eye := r * 0.13
	draw_circle(head + Vector2(-r * 0.34, -r * 0.1), eye, ink)
	draw_circle(head + Vector2(r * 0.34, -r * 0.1), eye, ink)
	draw_arc(head + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 12, ink, maxf(2.0, r * 0.1))
	draw_circle(head + Vector2(0.0, r * 0.12), r * 0.1, Color(0.95, 0.6, 0.62, alpha))


func _draw_gooby_auras(base: Vector2, body_h: float, body_w: float, alpha: float) -> void:
	var pu: Dictionary = run["pu"]
	var center := base + Vector2(0.0, -body_h * 0.5)
	if float(pu["magnetT"]) > 0.0:
		draw_arc(center, body_w * 2.8, 0.0, TAU, 34, Color(0.55, 0.85, 1.0, 0.5 * alpha), 3.0)
	if bool(pu["shield"]):
		draw_arc(center, body_w * 2.0, 0.0, TAU, 34, Color(0.4, 0.72, 0.98, 0.85 * alpha), 4.0)
	if float(pu["turboT"]) > 0.0:
		for i in 5:
			var f := float(i) / 4.0
			draw_line(
				base + Vector2(-body_w * (1.2 + f * 1.6), -body_h * (0.2 + f * 0.5)),
				base + Vector2(-body_w * (2.0 + f * 1.6), -body_h * (0.2 + f * 0.5)),
				Color(1.0, 0.62, 0.3, (0.8 - f * 0.5) * alpha),
				maxf(2.0, body_w * 0.12)
			)


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


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 26:
		var a := TAU * i / 26.0
		pts.append(center + Vector2(cos(a) * maxf(1.0, rx), sin(a) * maxf(1.0, ry)))
	draw_colored_polygon(pts, color)
