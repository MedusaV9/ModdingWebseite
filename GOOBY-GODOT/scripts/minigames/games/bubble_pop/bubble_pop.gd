extends MinigameBase
## Blasen-Platzer (bubblePop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## BubblePopLogic (zahlengleich zum Web, Bot-zertifiziert): Zielessen rotiert
## alle 12 s, Treffer +2, falsche Blase −2 + 0,5 s Stun, Stachelblasen platzen
## nie (Antippen −1), Steig- und Spawn-Kadenz rampen linear, drei gleiche
## Treffer in 2 s zünden eine Kettenreaktion über die Nachbarblasen.
## ECHTES 3D-UNTERWASSER (FB-4, BubblePopStage3D): Kenney-Food-Modelle schweben
## in Glasblasen durch ein Pastell-Aquarium, die Zielsorte trägt einen
## pulsierenden Leuchtring, Gooby taucht als echtes Rig mit. Die Kamera rahmt
## die Aufstiegsebene EXAKT wie die 2D-Rechnung (set_half_height) — Spawn-,
## Steig- und Trefferzahlen bleiben unangetastet. Nur HUD-Milchglas und der
## Stun-Rotschleier bleiben als 2D-Overlay.
##
## W17/G4-Politur (NUR Präsentation): Intro-Beat 1,5 s mit Kamerafahrt vom
## Riff hoch zum Ziel-Abzeichen samt Ziel-Banner (die Sim wartet, M1),
## _ui-Skalierung des HUD und Hinweis-/Banner-Breite aus vp.x statt fixer
## 340 px (M9 — behebt das belegte Hint-Clipping), Konturen auf Zeit/Serie
## (M7) und Endton mg_win/mg_lose (M8).

const Stage := preload("res://scripts/minigames/games/bubble_pop/bubble_pop_stage3d.gd")

## Sichtbare Welt-Halbbreite in Logik-Einheiten (Web-Kamera ≈ 3.25 bei 390 px).
## Halbe sichtbare Welthöhe — im Web `tan(CAMERA_FOV/2) * 10` bei FOV 45°
## (bubblePop.js: `halfH = Math.tan(degToRad(camera.fov / 2)) * 10`,
## `halfW = halfH * (innerWidth / innerHeight)`). Der Blasenradius und die
## Steiggeschwindigkeit der Logik sind auf DIESEN Rahmen geeicht.
const WORLD_HALF_H := 4.142135623730951
## Blasenradius in Welteinheiten (Optik; getippt wird über touch_radius_for).
const BUBBLE_R := 0.42
const SPIKY_R := 0.5
## W17 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (hide_seek-Muster).
const DESIGN_SHORT := 390.0
## W17 M1: Intro-Beat (s) — Kamerafahrt Riff→Ziel-Abzeichen, die Sim wartet.
const INTRO_S := 1.5
## Warm-weiße Kontur der HUD-Labels (M7): hebt Ziffern vom Wasser ab.
const OUTLINE_RIM := Color(1.0, 0.99, 0.94, 0.9)

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
var _stage: Node3D
var _bob := 0.0
var _hud_plate := _make_hud_plate()
var _banner_plate := _make_hud_plate()
var _hint_plate := _make_hud_plate()
var _ui := 1.0
var _intro_left := 0.0
var _banner_text := ""
var _banner_t := 0.0
var _intro_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BubblePopLogic.apply_difficulty(BubblePopLogic.BUBBLE, ctx.difficulty)
	rng = ctx.rng()
	chain = BubblePopLogic.create_pop_chain()
	# Genug Ziel-Slots für die ganze Runde (Endlos bekommt reichlich Vorrat).
	var slots := int(ceil(float(tune["DURATION_SEC"]) / float(tune["TARGET_ROTATE_SEC"]))) + 24
	target_order = BubblePopLogic.target_order(rng, slots)
	next_spawn = BubblePopLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_stage = Stage.new()
	_stage.name = "Aquarium3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fit_viewport()
	_intro_plate.set_corner_radius_all(12)
	# W17 M1: Intro-Beat — Kamerafahrt vom Riff hoch zum Ziel-Abzeichen; die
	# Sim (elapsed/Spawn-Uhr) wartet, der Lauf bleibt danach zahlengleich.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.bubblePop.intro"), INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## W17 M9: der _ui-Faktor (Kurzkante/390, 0.75..3.0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.frame(view_size)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W17 M9: alle Pixelmaße skalieren mit _ui; Hinweis- und Banner-Breite
## hängen an vp.x statt an Fix-340/420-px (das Hint-Clipping des Audits),
## dazu Konturen auf Zeit/Serie (M7).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0) * _ui
	_time_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_time_label.add_theme_constant_override("outline_size", int(6.0 * _ui))
	_streak_label.position = Vector2(16.0, 48.0) * _ui
	_streak_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_streak_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var banner_w := minf(vp.x - 32.0 * _ui, 420.0 * _ui)
	_banner_label.add_theme_font_size_override("font_size", int(28.0 * _ui))
	_banner_label.add_theme_constant_override("outline_size", int(6.0 * _ui))
	_banner_label.position = Vector2(
		(vp.x - banner_w) * 0.5, (84.0 if not landscape else 12.0) * _ui
	)
	_banner_label.size = Vector2(banner_w, 44.0 * _ui)
	_layout_hint(vp, 10.0)
	# 3D-Zielabzeichen direkt unter das Banner hängen (zeigt das Ziel-Essen).
	if _stage != null:
		_stage.set_badge_anchor(
			Vector2(vp.x * 0.5, _banner_label.position.y + _banner_label.size.y + 44.0 * _ui)
		)


## M9: Hinweis unten mittig — Breite folgt vp.x/_ui, Höhe dem umbrochenen
## Text (lange Übersetzungen liefen vorher aus dem Fix-340-px-Kasten).
func _layout_hint(vp: Vector2, bottom_pad: float) -> void:
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	var font_size := int(20.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", font_size)
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var font := _hint_label.get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		_hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, hint_w, font_size
	)
	var box := Vector2(hint_w, text_size.y + 6.0 * _ui)
	_hint_label.position = Vector2((vp.x - box.x) * 0.5, vp.y - box.y - bottom_pad * _ui)
	_hint_label.size = box


## Aktives Zielessen zum Rundenzeitpunkt.
func target_food() -> String:
	if target_order.is_empty():
		return "carrot"
	var idx := BubblePopLogic.target_index_at(elapsed, tune)
	return target_order[idx % target_order.size()]


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	_streak_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_streak_label)
	_banner_label = Label.new()
	_banner_label.theme_type_variation = &"TitleLabel"
	_banner_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_banner_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.bubblePop.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_color_override("font_outline_color", Color(OUTLINE_RIM, 0.6))
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_bob += delta
	# W17 M1: Intro-Beat — die Kamera fährt vom Riff hoch zum Ziel-Abzeichen,
	# das Ziel steht als Banner; elapsed und Spawn-Uhr warten, der Lauf bleibt
	# zahlengleich (Crosscheck-Vertrag unberührt). Reduced Motion überspringt
	# die Fahrt (Call-Site-Gate) und hält nur den Banner-Beat.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_stage.sync(bubbles, target_food(), _bob, delta)
		_update_labels()
		queue_redraw()
		return
	_banner_t = maxf(0.0, _banner_t - delta)
	elapsed += delta
	_spawn_tick(delta)
	_rise_tick(delta)
	if BubblePopLogic.endless_should_end(spiky_pops, tune):
		_finish()
		return
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_stage.sync(bubbles, target_food(), _bob, delta)
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
	if not is_active() or finished or _intro_left > 0.0:
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
	# Erst entfernen, DANN feiern — wie die Web-Vorlage (despawn vor dem
	# Ketten-Check). Sonst zählt die Kette die getroffene Blase doppelt und
	# remove_at greift nach der Kettenräumung ins Leere.
	if bool(result["pops"]):
		bubbles.remove_at(index)
	match str(result["result"]):
		"match":
			streak += 1
			_stage.pop_fx(float(bubble["x"]), float(bubble["y"]), true)
			_celebrate_match(bubble, pos, delta)
		"wrong":
			streak = 0
			stun_until = elapsed + float(result["stunSec"])
			AudioDirector.try_play(self, "mg_junk")
			_stage.pop_fx(float(bubble["x"]), float(bubble["y"]), false)
			if ctx.juice != null:
				ctx.juice.float_text(pos, I18nService.t("mg.bubblePop.wrong"), AcTokens.DANGER)
				ctx.juice.shake(0.35)
				ctx.juice.hit_freeze(80)
				ctx.juice.hit_flash(Color(0.9, 0.35, 0.3, 0.14))
		_:
			streak = 0
			spiky_pops += 1
			AudioDirector.try_play(self, "mg_spill")
			_stage.pop_fx(float(bubble["x"]), float(bubble["y"]), false)
			if ctx.juice != null:
				ctx.juice.float_text(pos, I18nService.t("mg.bubblePop.spiky"), AcTokens.DANGER)
				ctx.juice.shake(0.3)
	ctx.report_score(score, delta)


func _celebrate_match(bubble: Dictionary, pos: Vector2, delta: int) -> void:
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.02 * minf(streak, 12.0))
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % delta, AcTokens.LEAF_DARK)
		ctx.juice.overlay_ring(pos, Color(0.65, 0.95, 1.0, 0.85), 56.0)
		# Serien-Ton steigt pro Treffer um einen Halbton — DER Dopamin-Hebel.
		if streak >= 2:
			ctx.juice.combo_tone(streak)
	var style := str(bubble["food"])
	var fired: Dictionary = BubblePopLogic.record_pop_chain(chain, style, elapsed)
	if bool(fired["triggered"]):
		_chain_burst(style, float(bubble["x"]), float(bubble["y"]), pos)
	if BubblePopLogic.match_streak_milestone(streak):
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
	_stage.chain_fx(x, y)
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
	# W17 M8: hörbarer Schlusspunkt — der Zeitmodus endet als geschaffte
	# Runde (mg_win), Endlos endet immer über die dritte Stachelblase (mg_lose).
	AudioDirector.try_play(self, "mg_lose" if bool(tune["ENDLESS"]) else "mg_win")
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
	_hint_label.modulate.a = _hint_alpha()


## Der Hinweis blendet nach ein paar Sekunden aus — das Wasser gehört dann
## ganz den Blasen.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 5.0) / 1.5, 0.0, 1.0)


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


## Nur noch HUD-Overlay: Milchglas hinter den Labels + Stun-Rotschleier.
func _draw() -> void:
	_draw_hud_backing()
	_draw_intro_banner()
	if elapsed < stun_until:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.9, 0.4, 0.4, 0.16))


func _set_banner(text: String, sec := 1.4) -> void:
	_banner_text = text
	_banner_t = sec


## Intro-Banner mittig mit Milchglas-Plate und Kontur (M7, carrot_guard-
## Muster); lange Übersetzungen brechen um.
func _draw_intro_banner() -> void:
	if _banner_t <= 0.0 or _banner_text.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var font_size := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := vp.y * 0.3
	var pad := Vector2(18.0 * _ui, 10.0 * _ui)
	_intro_plate.set_corner_radius_all(int(12.0 * _ui))
	_intro_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_intro_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.32, 0.24, 0.28, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(
		font, at, _banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink
	)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


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
	var pad := Vector2(12.0, 6.0) * _ui
	var top_left := _time_label.position - pad
	var bottom_right := (
		_streak_label.position
		+ Vector2(maxf(_time_label.size.x, _streak_label.size.x), _streak_label.size.y)
		+ pad
	)
	draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))
	# Auch das Ziel-Banner bekommt Milchglas — Blasen zogen sonst durch den
	# Text und das Ziel war im Gewusel kaum zu lesen.
	var banner_size := _banner_label.get_minimum_size() + Vector2(36.0, 10.0) * _ui
	var banner_at := Vector2(
		_banner_label.position.x + (_banner_label.size.x - banner_size.x) * 0.5,
		_banner_label.position.y + (_banner_label.size.y - banner_size.y) * 0.5
	)
	draw_style_box(_banner_plate, Rect2(banner_at, banner_size))
	# Der Hinweis blendet nach ein paar Sekunden aus.
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)
