extends MinigameBase
## Burger-Bau (burgerBuild) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## BurgerBuildLogic (zahlengleich zum Web): 4–7-Lagen-Ticket, Zutaten regnen in
## 3 Spalten, richtige Lage +5 (Rush ×1.5), falsche −2, fertiger Burger +15,
## Fallspeed +8 % je Burger. 75 s (Endlos: bis 3 abgelaufene Bestellungen).
##
## ECHTE 3D-DINERBÜHNE (BurgerBuildStage3D): Gooby steht als KOCH hinter der
## Theke, aus drei Schächten regnen echte Food-Kit-Zutaten auf einen Teller,
## der auf der Theke mitfährt. Die 3D-Kamera ist deckungsgleich mit
## `project(wx, wy)` gerahmt, PLATE_HALF_WIDTH und Spaltenmitten gelten also
## unverändert. In 2D bleiben nur Bestellzettel und Meldung (das ist UI).

const Logic := preload("res://scripts/minigames/games/burger_build/burger_build_logic.gd")
const Stage := preload("res://scripts/minigames/games/burger_build/burger_build_stage3d.gd")

## Sichtbare Welt-Halbbreite (Web-Kamera in Hochkant) — Basis der Projektion.
const HALF_W := 3.4
const HALF_H := 5.2
## Teller-Höhe in Weltmetern (Web: plateY).
const PLATE_Y := -3.4
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## G5 M1: Intro-Beat (s) — Küchen-Totale + Ziel-Banner, Sim/Eingabe warten.
const INTRO_S := 1.5
## G5 M6: nach so vielen Sekunden SIM-Zeit blendet der Hinweis aus.
const HINT_FADE_SEC := 6.0
## G5 M4: unter dieser Bestell-Restzeit pulsiert der Zettel rot und tickt.
const URGENT_UNDER_S := 5.0

const LAYER_COLORS := {
	"bun": Color(0.91, 0.68, 0.36),
	"patty": Color(0.55, 0.33, 0.2),
	"cheese": Color(1.0, 0.79, 0.28),
	"tomato": Color(0.9, 0.31, 0.28),
	"salad": Color(0.5, 0.79, 0.38),
	"onion": Color(0.93, 0.85, 0.93),
}

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0.0
var ticket: Array[String] = []
var placed := 0
var completed := 0
var expired := 0
var order_number := 1
var rush := false
var elapsed := 0.0
var order_left := 30.0
var since_needed := 0.0
var spawn_left := 0.0
var bite_left := 0.0
var plate_x := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

## Aktive Regen-Teile: {"id", "x", "y", "col"}
var _items: Array[Dictionary] = []
var _stage: Node3D
var _flash := 0.0
var _flash_text := ""
var _flash_good := true
var _ui := 1.0
var _time_label: Label
var _order_label: Label
var _hint_label: Label
var _intro_left := 0.0
var _flash_plate := StyleBoxFlat.new()
var _last_tick_sec := -1


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.BURGER, ctx.difficulty)
	rng = ctx.rng()
	_build_stage()
	_build_hud()
	_new_order()
	_fit_viewport()
	# G5 M1: Intro-Beat — Ziel-Banner + Küchen-Totale; Sim-Uhr, Spawns und
	# Eingabe warten, der Lauf bleibt danach zahlengleich (Crosscheck-Vertrag).
	_intro_left = INTRO_S
	_flash_text = I18nService.t("mg.burgerBuild.intro")
	_flash_good = true
	_flash = INTRO_S + 0.7
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## 3D-Bühne unter die Node2D-Wurzel hängen (Godot rendert 3D hinter 2D).
func _build_stage() -> void:
	_stage = Stage.new()
	_stage.name = "Stage3D"
	add_child(_stage)
	_stage.setup_stage(Logic.column_centers(HALF_W))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.world_env


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.frame(view_size.y * 0.5 / _world_scale())
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_order_label.position = Vector2(pad, 44.0 * _ui)
	_order_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 46.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	# G5 M1: im Intro-Beat schwebt die Kamera aus der Küchen-Totale in die
	# Spielpose (Reduced Motion springt direkt); Sim-Uhr/Spawns warten.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_flash = maxf(0.0, _flash - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_sync_stage(delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	_flash = maxf(0.0, _flash - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if bite_left > 0.0:
		bite_left -= delta
		if bite_left <= 0.0:
			_new_order()
		_update_labels()
		queue_redraw()
		return
	order_left -= delta
	if order_left <= 0.0:
		_expire_order()
		_update_labels()
		queue_redraw()
		return
	since_needed += delta
	spawn_left -= delta
	if spawn_left <= 0.0:
		_spawn_item()
		spawn_left = float(tune["SPAWN_SEC"])
	_step_items(delta)
	_tick_urgency()
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## G5 M4 (Audit A §2.4): unter 5 s Bestell-Restzeit tickt einmal je
## Restsekunde ein ui_tick mit steigendem Pitch (carrot_guard-Muster, kein
## neues Audio-Asset) — die rote Puls-Kante dazu malt _draw_ticket.
func _tick_urgency() -> void:
	if order_left > URGENT_UNDER_S or order_left <= 0.0:
		_last_tick_sec = -1
		return
	var sec := int(ceil(order_left))
	if sec != _last_tick_sec:
		_last_tick_sec = sec
		AudioDirector.try_play(self, "ui_tick", 0.9 + 0.5 * (1.0 - order_left / URGENT_UNDER_S))


## Die 3D-Bühne bekommt EINEN Zustandsschnappschuss — sie rechnet nur Optik.
func _sync_stage(delta: float) -> void:
	_stage.tick(delta)
	_stage.sync(
		_items, plate_x, ticket, placed, Logic.next_needed(ticket, placed), _reduced_motion()
	)
	_stage.feel(_mood())


## Gooby-Laune aus dem Bestellzustand (Reihenfolge = Dringlichkeit).
func _mood() -> String:
	if bite_left > 0.0:
		return "ecstatic"
	if order_left <= 5.0:
		return "scared"
	if _flash > 0.0 and not _flash_good:
		return "sad"
	if rush:
		return "angry"
	return "happy"


func _unhandled_input(event: InputEvent) -> void:
	# G5 M1: im Intro-Beat wartet auch die Eingabe (kein Frühstart-Teller).
	if not is_active() or finished or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch and event.pressed:
		plate_x = _to_world_x(event.position.x)
	elif event is InputEventScreenDrag:
		plate_x = _to_world_x(event.position.x)


## Weltmeter → Bildschirmpixel.
func project(wx: float, wy: float) -> Vector2:
	var scale := _world_scale()
	return Vector2(view_size.x * 0.5 + wx * scale, view_size.y * 0.5 - wy * scale)


func _world_scale() -> float:
	return minf(view_size.x / (HALF_W * 2.0), view_size.y / (HALF_H * 2.0))


func _to_world_x(px: float) -> float:
	var scale := _world_scale()
	return clampf((px - view_size.x * 0.5) / scale, -HALF_W + 0.4, HALF_W - 0.4)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_order_label = Label.new()
	_order_label.theme_type_variation = &"CaptionLabel"
	add_child(_order_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.burgerBuild.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf dem roten Schachbrettboden — heller Text mit Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.32, 0.14, 0.12, 0.5))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _new_order() -> void:
	ticket = Logic.make_ticket(rng)
	placed = 0
	rush = Logic.is_rush_order(order_number)
	order_left = Logic.order_timer_sec(rush, tune)
	since_needed = 0.0
	spawn_left = 0.0
	_items.clear()
	if rush:
		AudioDirector.try_play(self, "mg_golden")


func _spawn_item() -> void:
	var needed := Logic.next_needed(ticket, placed)
	var id := Logic.roll_spawn(rng, needed, since_needed, tune)
	if id == needed:
		since_needed = 0.0
	var cols := Logic.column_centers(HALF_W)
	var col := mini(cols.size() - 1, int(floor(rng.next() * cols.size())))
	_items.append({"id": id, "x": float(cols[col]), "y": HALF_H + 0.6, "col": col})


func _step_items(delta: float) -> void:
	var speed := Logic.fall_speed_at(completed, tune)
	var catch_y := PLATE_Y + _stack_top() + 0.12
	var half := float(tune["PLATE_HALF_WIDTH"])
	var keep: Array[Dictionary] = []
	for item in _items:
		var prev_y := float(item["y"])
		item["y"] = prev_y - speed * delta
		var y := float(item["y"])
		if prev_y > catch_y and y <= catch_y and absf(float(item["x"]) - plate_x) <= half:
			_catch_item(item)
			continue
		if y < -HALF_H - 0.8:
			continue
		keep.append(item)
	_items = keep


func _stack_top() -> float:
	return 0.18 + placed * 0.22


func _catch_item(item: Dictionary) -> void:
	var needed := Logic.next_needed(ticket, placed)
	var correct := str(item["id"]) == needed and not needed.is_empty()
	var prev := score
	score = Logic.apply_catch(score, correct, rush, tune)
	var delta := score - prev
	var pos := project(plate_x, PLATE_Y + _stack_top())
	if correct:
		placed += 1
		# W14 Quick-Win: steigende Combo-Tonleiter je Lage (+1 Halbton) statt
		# flachem mg_good — der Stapel wird hörbar höher (Audit d=3, nur Ton).
		if ctx.juice != null:
			ctx.juice.combo_tone(placed)
		else:
			AudioDirector.try_play(self, "mg_good", 1.0 + 0.03 * placed)
		_flash_text = "+%s" % _fmt(delta)
		_flash_good = true
		# Funkenwölkchen in der Farbe der gefangenen Lage — der Treffer
		# passiert AM Teller, also antwortet auch der Teller.
		# (Q2: Partikel-Burst nur ohne Reduced Motion; Ton/Float-Text bleiben.)
		if not _reduced_motion():
			_stage.poof(LAYER_COLORS.get(str(item["id"]), Color(1.0, 0.9, 0.6)))
		if ctx.juice != null:
			ctx.juice.float_text(pos, _flash_text, Color(0.2, 0.6, 0.34))
			ctx.juice.hit_freeze(35)
	else:
		AudioDirector.try_play(self, "mg_spill")
		_flash_text = I18nService.t("mg.burgerBuild.wrong")
		_flash_good = false
		if not _reduced_motion():
			_stage.poof(Color(0.55, 0.5, 0.48))
		if ctx.juice != null:
			ctx.juice.float_text(pos, "%s" % _fmt(delta), Color(0.82, 0.32, 0.3))
			ctx.juice.shake(0.2)
	_flash = 0.7
	ctx.report_score(int(floor(score)), int(floor(score)) - int(floor(prev)))
	if Logic.is_complete(ticket, placed):
		_complete_order()


func _complete_order() -> void:
	var prev := score
	score += Logic.order_points(float(tune["COMPLETE_PTS"]), rush)
	completed += 1
	ctx.report_score(int(floor(score)), int(floor(score)) - int(floor(prev)))
	AudioDirector.try_play(self, "mg_perfect")
	_flash_text = I18nService.t("mg.burgerBuild.done", {"n": _fmt(score - prev)})
	_flash_good = true
	_flash = 1.2
	# Belohnungsmoment: der Koch jubelt, über dem fertigen Burger goldene
	# Funken, die Bühne blitzt warm auf — und die Gäste feiern mit (G5 M2).
	_stage.cheer("celebrate")
	_stage.guests_cheer(_reduced_motion())
	if not _reduced_motion():
		_stage.poof(Color(1.0, 0.85, 0.4))
	_stage.pulse_glow(0.9)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.shake(0.14)
		ctx.juice.confetti(45)  # W14 Quick-Win: fertiger Burger = kleiner Regen
	order_number += 1
	bite_left = float(tune["BITE_SEC"])
	_items.clear()


func _expire_order() -> void:
	expired += 1
	AudioDirector.try_play(self, "mg_junk")
	_flash_text = I18nService.t("mg.burgerBuild.expired")
	_flash_good = false
	_flash = 1.2
	if ctx.juice != null:
		ctx.juice.shake(0.32)
	order_number += 1
	if Logic.endless_should_end(expired, tune):
		_finish()
		return
	_new_order()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": int(floor(score)), "completed": completed, "expired": expired})


func _fmt(value: float) -> String:
	if absf(value - roundf(value)) < 0.001:
		return "%d" % int(roundf(value))
	return "%.1f" % value


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.burgerBuild.expired_count", {"n": expired, "max": int(tune["ENDLESS_EXPIRES"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	var key := "mg.burgerBuild.order_rush" if rush else "mg.burgerBuild.order"
	var left_sec := int(ceil(maxf(0.0, order_left)))
	_order_label.text = I18nService.t(key, {"n": order_number, "sec": left_sec})
	# G5 M6: der Hinweis blendet nach 6 s SIM-Zeit aus (im Intro steht die
	# Uhr, der Hinweis bleibt dort also voll lesbar — rocket-Muster).
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


## Die WELT lebt in der 3D-Bühne — 2D bleibt nur der Bestellzettel (UI) und
## die Meldung.
func _draw() -> void:
	_draw_ticket()
	_draw_flash()


## Bestellzettel an der Wand: Klemme oben, Lagen von OBEN nach UNTEN, der
## Marker links zeigt auf die als Nächstes gesuchte Lage.
func _draw_ticket() -> void:
	var scale := _world_scale()
	var w := 1.05 * scale
	var h := 0.36 * scale
	var pad := 12.0 * _ui
	var head := 26.0 * _ui
	var origin := Vector2(view_size.x - w - pad * 2.2, view_size.y * 0.13 + head)
	var bg := Rect2(
		origin - Vector2(pad, pad + head),
		Vector2(w + pad * 2.0, h * ticket.size() + pad * 2.0 + head)
	)
	var frame := Color(0.9, 0.5, 0.35) if rush else Color(0.7, 0.6, 0.52)
	# G5 M4 (Audit A §2.4): unter 5 s Restzeit pulsiert die Zettel-Kante rot
	# (Reduced Motion: statisch rot) — die HUD-Dringlichkeit zur Gooby-Mimik.
	var urgent := bite_left <= 0.0 and order_left > 0.0 and order_left <= URGENT_UNDER_S
	if urgent:
		var pulse := 1.0 if _reduced_motion() else 0.55 + 0.45 * sin(elapsed * 9.0)
		frame = frame.lerp(Color(0.88, 0.2, 0.16), pulse)
	draw_rect(bg.grow(3.0 * _ui), Color(0.0, 0.0, 0.0, 0.1))
	draw_rect(bg, Color(1.0, 1.0, 1.0, 0.95))
	draw_rect(bg, frame, false, maxf(2.0, (4.0 if urgent else 3.0) * _ui))
	draw_rect(
		Rect2(bg.position.x, bg.position.y, bg.size.x, head * 0.8), frame.lerp(Color.WHITE, 0.72)
	)
	# Klemme, die den Zettel an die Wand heftet.
	var clip := Rect2(
		bg.position.x + bg.size.x * 0.5 - 14.0 * _ui,
		bg.position.y - 12.0 * _ui,
		28.0 * _ui,
		18.0 * _ui
	)
	draw_rect(clip, Color(0.72, 0.74, 0.79))
	draw_rect(clip, Color(0.5, 0.52, 0.57), false, maxf(1.5, 2.0 * _ui))
	for i in ticket.size():
		var layer_index := ticket.size() - 1 - i
		var rect := Rect2(origin + Vector2(0.0, h * i), Vector2(w, h - 5.0 * _ui))
		var col: Color = LAYER_COLORS.get(ticket[layer_index], Color.GRAY)
		if layer_index >= placed:
			col = col.lerp(Color(1.0, 1.0, 1.0), 0.6)
		draw_rect(rect, col)
		draw_rect(rect, Color(0.4, 0.3, 0.25, 0.45), false, maxf(1.5, 2.0 * _ui))
		if layer_index < placed:
			var tick := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
			draw_line(
				tick + Vector2(-rect.size.x * 0.12, 0.0),
				tick + Vector2(-rect.size.x * 0.02, rect.size.y * 0.22),
				Color(0.2, 0.45, 0.28),
				maxf(2.0, 3.0 * _ui)
			)
			draw_line(
				tick + Vector2(-rect.size.x * 0.02, rect.size.y * 0.22),
				tick + Vector2(rect.size.x * 0.16, -rect.size.y * 0.26),
				Color(0.2, 0.45, 0.28),
				maxf(2.0, 3.0 * _ui)
			)
	if placed < ticket.size():
		var mark := Rect2(
			origin + Vector2(-14.0 * _ui, h * (ticket.size() - 1 - placed)),
			Vector2(9.0 * _ui, h - 5.0 * _ui)
		)
		draw_rect(mark, Color(0.95, 0.45, 0.66))


## G5 M7 (Audit A §2.4): Meldung auf Milchglas-Plate mit Kontur und Umbruch
## (rocket-Muster) — vorher kollidierte die nackte Schrift bei y·0,3 optisch
## mit den Deckenlampen; jetzt sitzt sie UNTER den Lampen auf einer Plate.
func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_flash * 1.4, 0.0, 1.0)
	var font_size := maxi(18, int(26.0 * _ui))
	var w := minf(view_size.x - 24.0, 400.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_flash_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := view_size.y * 0.4
	var pad := Vector2(18.0, 10.0) * _ui
	_flash_plate.set_corner_radius_all(int(12.0 * _ui))
	_flash_plate.bg_color = Color(1.0, 0.99, 0.94, 0.78 * alpha)
	var plate_pos := Vector2((view_size.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_flash_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.16, 0.45, 0.26, alpha) if _flash_good else Color(0.72, 0.2, 0.16, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((view_size.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _flash_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(font, at, _flash_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)
