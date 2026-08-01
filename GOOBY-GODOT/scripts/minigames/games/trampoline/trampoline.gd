extends MinigameBase
## Trampolin-Tricks (trampoline) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## TrampolineLogic (zahlengleich zum Web, Bot-zertifiziert): Tippen im
## schrumpfenden Landefenster gibt Boost, Wischen in der Luft macht
## Salto/Drehung/Schraube (Punkte × Höhenfaktor 1–3), Fenster verpasst =
## Po-Landung und die Höhe fällt auf BASE_VY zurück. Alle drei Trickarten in
## EINEM Flug zahlen +12. 60 s; Endlos endet nach drei Bruchlandungen.
##
## ECHTE 3D-TURNHALLE (FB-4, TrampolineStage3D): Gooby springt als echtes Rig
## metergenau über einem Sprungtuch mit Federn, Tricks drehen ihn im Raum,
## die Höhenmarken ×2/×3 leuchten beim Erreichen. Nur das Landefenster bleibt
## als 2D-Ring-Overlay über der Figur (Skill-Check-Lesbarkeit). Die 3D-Welt
## hängt unter der Node2D-Wurzel, der MinigameBase-Vertrag bleibt unberührt.

const Stage := preload("res://scripts/minigames/games/trampoline/trampoline_stage3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")

## Mindest-Wischlänge in Pixeln, damit eine Geste als Trick zählt.
const SWIPE_MIN_PX := 44.0
## W16 Intro-Beat (s): Kamera-Totale auf die Halle + Ziel-Banner, die SIM
## wartet komplett (M1-Muster star_hopper.gd — der Lauf bleibt zahlengleich).
const INTRO_S := 1.5
## Entwurfs-Kurzkante — HUD-Pixelmaße skalieren mit `_ui` (M9-Muster hide_seek).
const DESIGN_SHORT := 390.0
## Reihenfolge der Trick-Chips im HUD (Dreierpack-Fortschritt je Flug).
const CHIP_KINDS: Array[String] = ["flip", "spin", "twist"]
## Konturfarbe für Banner/Chip-Icons (gleiche Tinte wie die Bühne).
const INK := Color(0.24, 0.19, 0.17)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var height := 0.0
var vy := 0.0
var apex := 0.0
var airborne := true
var failures := 0
var stagger_left := 0.0
var armed := ""
var trick_chain: Dictionary = {}
var tricking := 0.0
var trick_spin := 0.0
var last_trick := ""
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _trick_label: Label
var _hint_label: Label
var _stage: Node3D
var _swipe_from := Vector2.ZERO
var _swiping := false
var _pulse := 0.0
var _shock := 0.0
var _ui := 1.0
var _intro_left := 0.0
var _banner_text := ""
var _banner_t := 0.0
## Höhenstufe (×1/×2/×3) des letzten Flugs — Durchbrüche feiern (Befund 5).
var _tier_prev := 1
## Gold-Blitz der Chips nach dem Dreierpack + Pop je frisch gefülltem Chip.
var _chip_flash := 0.0
var _chip_pop: Dictionary = {}
var _hud_plate := Kit.hud_plate()
var _hint_plate := Kit.hud_plate()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = TrampolineLogic.apply_difficulty(TrampolineLogic.TRAMP, ctx.difficulty)
	rng = ctx.rng()
	vy = float(tune["BASE_VY"])
	apex = TrampolineLogic.apex_for(vy, float(tune["GRAVITY"]))
	trick_chain = TrampolineLogic.create_trick_chain()
	_stage = Stage.new()
	_stage.name = "Halle3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_tier_prev = TrampolineLogic.height_multiplier(apex)
	_build_hud()
	_fit_viewport()
	_intro_left = INTRO_S
	_banner_text = I18nService.t("mg.trampoline.intro")
	_banner_t = INTRO_S + 0.8
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
		_stage.apply_size(view_size)
	_layout_hud()
	_update_labels()
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_trick_label = Label.new()
	_trick_label.theme_type_variation = &"CaptionLabel"
	add_child(_trick_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.trampoline.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_layout_hud()
	_update_labels()


## HUD in Entwurfspixeln, mit `_ui` skaliert (M9) — vorher fixe Pixel, auf
## iPad wirkten die Labels verloren. IMMER aus dem Viewport-Rect stellen.
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	var pad := 16.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_trick_label.position = Vector2(pad, 46.0 * _ui)
	_trick_label.add_theme_font_size_override("font_size", int(16.0 * _ui))
	var hint_w := minf(vp.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - 46.0 * _ui)
	_hint_label.size = Vector2(hint_w, 36.0 * _ui)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_pulse += delta
	_shock = maxf(0.0, _shock - delta * 2.2)
	_banner_t = maxf(0.0, _banner_t - delta)
	_chip_flash = maxf(0.0, _chip_flash - delta * 1.4)
	for kind: String in _chip_pop:
		_chip_pop[kind] = maxf(0.0, float(_chip_pop[kind]) - delta)
	# Intro-Beat (M1): Kamera schwebt aus der Hallen-Totale in die Spielpose,
	# das Ziel-Banner steht — die SIM (elapsed/Flug) wartet komplett, danach
	# läuft der zertifizierte Lauf zahlengleich weiter.
	if _intro_left > 0.0:
		_intro_left = maxf(_intro_left - delta, 0.0)
		_stage.establish(1.0 - _intro_left / INTRO_S)
		_stage.sync(0.0, 0.0, 0.0, 0.0, 0.0, "", apex, 0.0, _pulse, delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	tricking = maxf(0.0, tricking - delta)
	if tricking > 0.0:
		trick_spin += delta * 9.0
	if stagger_left > 0.0:
		stagger_left = maxf(0.0, stagger_left - delta)
		if stagger_left <= 0.0:
			_launch(float(tune["BASE_VY"]))
	else:
		_flight_tick(delta)
	if TrampolineLogic.endless_should_end(failures, tune):
		_finish()
		return
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_stage.sync(
		height, vy, stagger_left, tricking, trick_spin, last_trick, apex, _shock, _pulse, delta
	)
	_update_labels()
	queue_redraw()


func _flight_tick(delta: float) -> void:
	var g := float(tune["GRAVITY"])
	var previous := height
	vy -= g * delta
	height += vy * delta
	if not TrampolineLogic.crossed_mat(previous, height, vy):
		return
	# Mattenkontakt: die scharfgestellte Aktion genau einmal verbrauchen.
	var consumed := TrampolineLogic.consume_landing_action(armed)
	armed = str(consumed["armed"])
	var action := str(consumed["action"])
	height = 0.0
	_shock = 1.0
	if action == "butt":
		_butt_landing()
		return
	var next_vy := TrampolineLogic.next_bounce_vy(
		TrampolineLogic.apex_for(vy, g) * 0.0 + absf(vy), action, tune
	)
	# JEDE Landung wirft Staub auf und dippt das Tuch (reine Optik).
	_stage.land_fx(clampf(absf(vy) / float(tune["MAX_VY"]), 0.3, 1.0))
	if action == "boost":
		AudioDirector.try_play(self, "mg_perfect")
		_stage.boost_fx()
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.6)
			ctx.juice.float_text(
				_gooby_screen() - Vector2(0.0, 40.0),
				I18nService.t("mg.trampoline.boost"),
				AcTokens.TEAL_DARK
			)
	else:
		# Eigener Feder-„Boing" statt geliehenem gvz_place (Befund 4): die
		# Tonhöhe sinkt mit der Aufprallwucht — hohe Sprünge federn satt,
		# kleine Hopser blubbern hell (kein neues Audio-Asset, nur Pitch).
		var thump := clampf(absf(vy) / float(tune["MAX_VY"]), 0.0, 1.0)
		AudioDirector.try_play(self, "mg_good", 1.15 - 0.4 * thump)
	_launch(next_vy)


func _butt_landing() -> void:
	failures += 1
	stagger_left = float(tune["BUTT_STAGGER_SEC"])
	airborne = false
	vy = 0.0
	AudioDirector.try_play(self, "mg_spill")
	_stage.butt_fx()
	if ctx.juice != null:
		ctx.juice.shake(0.45)
		ctx.juice.hit_freeze(90)
		ctx.juice.float_text(_gooby_screen(), I18nService.t("mg.trampoline.butt"), AcTokens.DANGER)


func _launch(next_vy: float) -> void:
	vy = next_vy
	height = 0.0
	airborne = true
	apex = TrampolineLogic.apex_for(vy, float(tune["GRAVITY"]))
	armed = ""
	trick_chain = TrampolineLogic.create_trick_chain()
	trick_spin = 0.0
	_tier_check()


## Befund 5: Der Tier-Durchbruch war stumm — steigt der kommende Apex in eine
## neue ×2/×3-Stufe, pingt mg_combo (Pitch je Stufe), das Höhenband blitzt in
## 3D, ein Popup feiert die Stufe und bei ×3 jubelt das Publikum.
func _tier_check() -> void:
	var mult := TrampolineLogic.height_multiplier(apex)
	if mult > _tier_prev:
		AudioDirector.try_play(self, "mg_combo", 1.0 + 0.18 * float(mult - 1))
		_stage.tier_flash(mult - 2)
		if mult >= 3:
			_stage.crowd_cheer(1.0)
		if ctx.juice != null:
			ctx.juice.float_text(
				_gooby_screen() - Vector2(0.0, 64.0),
				I18nService.t("mg.trampoline.tier", {"n": mult}),
				AcTokens.GOLD if mult >= 3 else AcTokens.TEAL_DARK
			)
	_tier_prev = mult


func _time_to_impact() -> float:
	if not airborne:
		return INF
	# `vy` geht VORZEICHENBEHAFTET hinein (Web: `timeToImpact(this.h, this.vy)`).
	# Mit dem gedrehten Vorzeichen kam immer rund 1 s heraus, wodurch
	# `classify_landing_tap` ausnahmslos "ignore" lieferte — der Boost war
	# schlicht nicht erreichbar.
	return TrampolineLogic.time_to_impact(height, vy, float(tune["GRAVITY"]))


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or stagger_left > 0.0 or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_swiping = true
			_swipe_from = touch.position
			_tap_landing()
		elif _swiping:
			_swiping = false
			_resolve_swipe(touch.position - _swipe_from)
	elif event is InputEventScreenDrag and _swiping:
		var drag := event as InputEventScreenDrag
		if (drag.position - _swipe_from).length() >= SWIPE_MIN_PX:
			_swiping = false
			_resolve_swipe(drag.position - _swipe_from)


## Tippen im Fallen: im Fenster Boost, in der Urteilszone Po-Landung.
func _tap_landing() -> void:
	if vy > 0.0:
		return
	var verdict := TrampolineLogic.classify_landing_tap(_time_to_impact(), apex, tune)
	if verdict == "ignore":
		return
	armed = verdict
	AudioDirector.try_play(self, "ui_tick", 1.2 if verdict == "boost" else 0.85)


func _resolve_swipe(delta: Vector2) -> void:
	if delta.length() < SWIPE_MIN_PX:
		return
	if not TrampolineLogic.can_trick(airborne, _time_to_impact(), tricking > 0.0, tune):
		return
	var kind := "twist"
	if absf(delta.x) > absf(delta.y):
		kind = "flip" if delta.x < 0.0 else "spin"
	var mult := TrampolineLogic.height_multiplier(apex)
	var points := TrampolineLogic.trick_points(kind, mult)
	score += points
	tricking = 0.3
	last_trick = kind
	_stage.trick_fx()
	AudioDirector.try_play(self, "mg_combo", 0.95 + 0.06 * float(mult))
	if ctx.juice != null:
		ctx.juice.float_text(
			_gooby_screen() - Vector2(0.0, 46.0),
			"%s +%d" % [I18nService.t("mg.trampoline.%s" % kind), points],
			AcTokens.PINK if mult < 3 else AcTokens.GOLD
		)
	var was_seen: bool = (trick_chain["seen"] as Array).has(kind)
	var chained := TrampolineLogic.record_trick(trick_chain, kind)
	if not was_seen:
		# Frisch gefüllter Trick-Chip poppt kurz auf (Befund 3).
		_chip_pop[kind] = 0.3
	if bool(chained["triggered"]):
		var bonus := int(chained["bonus"])
		score += bonus
		_chip_flash = 1.0
		_stage.crowd_cheer(1.0)
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.slowmo(0.35, 280)
			ctx.juice.float_text(
				_gooby_screen() - Vector2(0.0, 84.0),
				I18nService.t("mg.trampoline.combo"),
				AcTokens.GOLD
			)
		points += bonus
	ctx.report_score(score, points)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "failures": failures, "elapsed": elapsed})


func _update_labels() -> void:
	if _time_label == null:
		return
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.trampoline.fails", {"n": failures, "max": int(tune["ENDLESS_FAILURE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	# Vorher kryptisch nur „×2" — jetzt benannt als Höhenfaktor (Befund 3).
	_trick_label.text = I18nService.t(
		"mg.trampoline.mult", {"n": TrampolineLogic.height_multiplier(apex)}
	)
	_hint_label.modulate.a = _hint_alpha()


## Der Hinweis blendet nach ein paar Sekunden Spielzeit aus (M6-Muster
## carrot_guard) — die Bühne gehört dann ganz Gooby; im Intro voll lesbar.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 6.0) / 1.5, 0.0, 1.0)


## Gooby skaliert mit dem Viewport, sonst ist er auf großen Schirmen verloren.
func _gooby_radius() -> float:
	return clampf(maxf(view_size.x, view_size.y) * 0.05, 26.0, 62.0)


func _gooby_screen() -> Vector2:
	return _stage.gooby_screen()


## Nur noch HUD-Overlay: Milchglas-Plates, Trick-Chips, Banner und das
## Landefenster als Ring um die 3D-Figur — der Skill-Check bleibt damit
## pixelscharf lesbar, egal wie die Kamera steht.
func _draw() -> void:
	_draw_hud_plates()
	_draw_trick_chips()
	_draw_window_gauge()
	_draw_banner()


## Milchglas hinter Zeit/Höhenfaktor/Chips und dem Hinweis (M6): die helle
## Halle zog sonst direkt durch die Ziffern.
func _draw_hud_plates() -> void:
	if _time_label == null:
		return
	var top_left := _time_label.position - Vector2(12.0, 6.0) * _ui
	var width := maxf(_time_label.size.x, _trick_label.size.x)
	width = maxf(width, _chip_center(CHIP_KINDS.size() - 1).x + _chip_radius() - top_left.x)
	var bottom := _chip_center(0).y + _chip_radius() + 10.0 * _ui
	draw_style_box(_hud_plate, Rect2(top_left, Vector2(width + 24.0 * _ui, bottom - top_left.y)))
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)


func _chip_center(i: int) -> Vector2:
	return Vector2(16.0 * _ui + 15.0 * _ui + float(i) * 38.0 * _ui, 90.0 * _ui)


func _chip_radius() -> float:
	return 13.0 * _ui


## Befund 3: Der Dreierpack-Fortschritt (alle 3 Trickarten in EINEM Flug =
## +12) war unsichtbar — drei Icon-Chips (Salto/Drehung/Schraube) füllen sich
## pro Flug, poppen beim Füllen und blitzen gold, wenn die Kette komplett ist.
func _draw_trick_chips() -> void:
	if finished:
		return
	var seen: Array = trick_chain["seen"]
	var tints: Array[Color] = [AcTokens.PINK, AcTokens.TEAL_DARK, AcTokens.YELLOW_DARK]
	for i in CHIP_KINDS.size():
		var kind := CHIP_KINDS[i]
		var at := _chip_center(i)
		var r := _chip_radius() + float(_chip_pop.get(kind, 0.0)) * 14.0 * _ui
		var filled: bool = seen.has(kind)
		if _chip_flash > 0.0:
			# Dreierpack komplett: alle Chips glühen gold auf.
			draw_circle(at, r + 3.0 * _ui, Color(AcTokens.GOLD, 0.55 * _chip_flash))
		if filled:
			draw_circle(at, r, tints[i])
		else:
			draw_circle(at, r, Color(1.0, 0.99, 0.94, 0.6))
			draw_arc(at, r, 0.0, TAU, 26, Color(INK, 0.35), 1.5 * _ui)
		var icon := Color(1.0, 0.99, 0.96) if filled else Color(INK, 0.5)
		_draw_chip_icon(kind, at, _chip_radius(), icon)


## Mini-Glyphen je Trickart: Salto = senkrechter Bogen mit Pfeilspitze,
## Drehung = flache Ellipse (Hochachse), Schraube = Wellenlinie.
func _draw_chip_icon(kind: String, at: Vector2, r: float, color: Color) -> void:
	var w := 2.2 * _ui
	if kind == "flip":
		draw_arc(at, r * 0.55, -PI * 0.2, PI * 1.3, 18, color, w)
		var tip := at + Vector2(cos(-PI * 0.2), sin(-PI * 0.2)) * r * 0.55
		draw_line(tip, tip + Vector2(-0.5, -4.0) * _ui, color, w)
		draw_line(tip, tip + Vector2(-4.0, 1.5) * _ui, color, w)
	elif kind == "spin":
		var points := PackedVector2Array()
		for step in 19:
			var a := TAU * float(step) / 18.0
			points.append(at + Vector2(cos(a) * r * 0.62, sin(a) * r * 0.26))
		draw_polyline(points, color, w)
		draw_line(at + Vector2(0.0, -r * 0.62), at + Vector2(0.0, r * 0.62), Color(color, 0.6), w)
	else:
		var wave := PackedVector2Array()
		for step in 13:
			var t := float(step) / 12.0
			wave.append(at + Vector2(sin(t * TAU * 1.5) * r * 0.38, (t - 0.5) * r * 1.15))
		draw_polyline(wave, color, w)


## Intro-/Ziel-Banner mittig MIT Kontur (M7-Muster star_hopper) — Creme-Text
## ohne Outline ging vor der hellen Halle unter.
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner_text.is_empty():
		return
	var alpha := clampf(_banner_t / 0.4, 0.0, 1.0)
	var font := ThemeService.font(800)
	var size := int(26.0 * _ui)
	var at := Vector2(0.0, view_size.y * 0.3)
	draw_string_outline(
		font,
		at,
		_banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		size,
		int(6.0 * _ui),
		Color(INK, 0.85 * alpha)
	)
	draw_string(
		font,
		at,
		_banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		size,
		Color(1.0, 0.98, 0.94, alpha)
	)


## Landefenster als Ring um Gooby, sobald er fällt — das ist der Skill-Check.
## Lesehilfe: das GRÜNE Segment am Ende der Skala IST das Fenster; der Zeiger
## füllt die Skala, und sobald er im Grün steht, pulsiert der Ring — tippen!
func _draw_window_gauge() -> void:
	if not airborne or vy > 0.0 or finished:
		return
	var tti := _time_to_impact()
	var window := TrampolineLogic.window_sec_for(apex, tune)
	var zone := float(tune["JUDGE_ZONE_SEC"])
	if tti > zone * 1.6:
		return
	var pos := _gooby_screen()
	var ring := _gooby_radius() * 1.7
	var ratio := clampf(1.0 - tti / maxf(0.05, zone), 0.0, 1.0)
	var inside := tti <= window
	# Leise Laufbahn + grünes Fenster-Segment (Ziel sichtbar VOR dem Zeiger).
	# Strichstärken skalieren mit `_ui`, sonst wird der Ring auf iPad dünn.
	draw_arc(pos, ring, 0.0, TAU, 40, Color(0.4, 0.32, 0.28, 0.2), 4.0 * _ui)
	var window_from := clampf(1.0 - window / maxf(0.05, zone), 0.0, 1.0)
	draw_arc(
		pos,
		ring,
		-PI * 0.5 + TAU * window_from,
		-PI * 0.5 + TAU,
		24,
		Color(AcTokens.LEAF.r, AcTokens.LEAF.g, AcTokens.LEAF.b, 0.4),
		10.0 * _ui
	)
	var tint := AcTokens.LEAF if inside else AcTokens.YELLOW
	draw_arc(pos, ring, -PI * 0.5, -PI * 0.5 + TAU * ratio, 30, tint, 7.0 * _ui)
	if inside:
		# Jetzt-tippen-Puls: der ganze Ring atmet grün auf.
		var flash := 0.45 + 0.35 * sin(_pulse * 16.0)
		draw_arc(
			pos,
			ring + 8.0 * _ui,
			0.0,
			TAU,
			40,
			Color(AcTokens.LEAF.r, AcTokens.LEAF.g, AcTokens.LEAF.b, flash),
			3.5 * _ui
		)
