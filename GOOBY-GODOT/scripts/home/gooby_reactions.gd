class_name GoobyReactions
extends Node
## Seelen-Runner im Raum (FB-6/SEELE): macht Gooby lebendig, ohne je
## aufdringlich zu sein. Wird wie InteractablesHost/EventRunner pro Raum
## angehängt (home_entry._on_travel_finished → GoobyReactions.attach_to).
##
## Was hier lebt (Logik-Kern ist PURE in scripts/soul/ — dieser Node ist nur
## Glue + Visuals):
##  - Betreten-Moment (max. EINER): Ritual > Begrüßung > Wetter > Erinnerung
##    (SoulService.decide_enter, Frequenzbremse in SoulTriggers).
##  - Antippen: Kichern → Kitzlig (hüpft, zählt tickles) → Schwindelig.
##  - Idle-Leben: räumt auf, schaut fern, döst, schaut aus dem Fenster,
##    tanzt zur Radiomusik, besucht seinen Lieblingsplatz.
##  - Überraschungen: Münzfund unterm Sofa (echte Coins!), lautes Träumen,
##    Kissenturm, Winken in die Kamera — selten, mit langen Cooldowns.
##  - Kommentare: Neuanschaffungen („Der Sessel ist bequem!“),
##    Danke für Essen + Lieblingsessen (aus echten Fütterungen),
##    traurige Blicke bei Vernachlässigung (NIE Strafen), Zähneputzen
##    nach dem Aufwachen, Gute-Nacht-Gähnen.
##  - Geburtstags-Frage: kleines wegklickbares Panel, Datum wird gemerkt
##    und jedes Jahr gefeiert.

const Economy := preload("res://scripts/logic/economy.gd")

const EMOTION_REVERT_S := 4.0
const IDLE_MIN_S := 18.0
const IDLE_MAX_S := 35.0
const SURPRISE_CHECK_S := 60.0
const PRESENCE_STAMP_S := 60.0
const TAP_WINDOW_S := 4.0
const IDLE_ACT_COOLDOWN_MS := 180_000
const BUBBLE_MIN_GAP_S := 12.0
const NEGLECT_STAT_THRESHOLD := 20.0
const FAV_FOOD_MIN := 3
const SOFA_FUND_COINS := 3
## EF-1/EVAL-1 D4: Idle-Handlungen sind meist kommentiert (vorher 45 %) …
const IDLE_TEXT_QUOTE := 0.7
## … und etwa alle 90 s gibt es einen Mini-Fund (+1 Münze, Funken). Die
## Frequenz läuft über die VORHANDENE Seelen-Bremse (ambient_allowed).
const FUND_INTERVAL_S := 90.0
const MINI_FUND_COINS := 1
const FUND_KEYS: Array[String] = ["rewards.fund.a", "rewards.fund.b", "rewards.fund.c"]
## EF-1/EVAL-1 D5 Streichel-Treppe: Tonhöhe steigt je Streichler, jeder
## zehnte Streichler des Tages gibt einen kleinen Münz-Bonus.
const PET_BONUS_JEDER := 10
const PET_PITCH_SCHRITT := 0.04
const PET_BONUS_COINS := 1

var room: Node = null
var gs: Object = null
var gooby: Node3D = null
## Tests: Zeit/Zufall injizierbar (AGENTS.md-Regel: nie OS-Uhr im Kern).
var now_ms_override := -1
var rng := RandomNumberGenerator.new()
## Tests: Visuals (Partikel/Laufwege) abschaltbar — Logik läuft trotzdem.
var visuals_enabled := true

var _defs: Array = []
var _idle_timer := 0.0
var _surprise_timer := 0.0
var _fund_timer := FUND_INTERVAL_S
var _presence_timer := 0.0
var _idle_cooldowns: Dictionary = {}
var _tap_count := 0
var _tap_last_s := 0.0
var _last_bubble_s := -1000.0
var _food_snapshot: Dictionary = {}
var _sad := false
var _tap_area: Area3D = null
var _emotion_revert: SceneTreeTimer = null


## Runner erzeugen und an einen RoomBase hängen (idempotent pro Raum).
static func attach_to(target_room: Node) -> GoobyReactions:
	var existing := target_room.get_node_or_null("GoobyReactions")
	if existing is GoobyReactions:
		return existing
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	target_room.add_child(runner)
	runner.setup(target_room)
	return runner


## Kicher-Stufe je Tipp-Zähler (PURE, testbar): 1 = kichern, 3 = kitzlig,
## 6 = schwindelig (und der Zähler startet neu), sonst "".
static func tap_stage(count: int) -> String:
	if count == 1:
		return "tipp_kicher"
	if count == 3:
		return "tipp_kitzlig"
	if count >= 6:
		return "tipp_schwindelig"
	return ""


## Streichel-Tonhöhe (PURE, EVAL-1 D5): steigt Stufe um Stufe zur
## Bonus-Marke hin, nach jedem zehnten Streichler startet die Treppe neu.
static func pet_pitch(pets_today: int) -> float:
	return 1.0 + PET_PITCH_SCHRITT * float(maxi(pets_today - 1, 0) % PET_BONUS_JEDER)


## Ist dieser Streichler die Bonus-Stufe (jeder zehnte des Tages)?
static func pet_bonus_due(pets_today: int) -> bool:
	return pets_today > 0 and pets_today % PET_BONUS_JEDER == 0


func setup(target_room: Node) -> void:
	room = target_room
	SoulState.register_slice()
	gs = room.game_state() if room.has_method("game_state") else null
	gooby = room.gooby() if room.has_method("gooby") else null
	if gs == null:
		return
	rng.randomize()
	_defs = SoulService.defs_from_registry()
	_idle_timer = rng.randf_range(IDLE_MIN_S, IDLE_MAX_S)
	_surprise_timer = SURPRISE_CHECK_S
	_food_snapshot = _food_now()
	if gs.has_signal("stats_changed"):
		gs.stats_changed.connect(_on_stats_changed)
	if gs.has_signal("gooby_events"):
		gs.gooby_events.connect(_on_gooby_events)
	if room.has_signal("build_mode_toggled"):
		room.build_mode_toggled.connect(_on_build_mode_toggled)
	_setup_tap_area()
	_pick_favorite_if_needed()
	_run_enter()


func _process(delta: float) -> void:
	if gs == null:
		return
	if _tap_area != null and gooby != null:
		_tap_area.global_position = gooby.global_position + Vector3(0.0, 0.35, 0.0)
	_presence_timer += delta
	if _presence_timer >= PRESENCE_STAMP_S:
		_presence_timer = 0.0
		SoulState.mutate(gs, func(s: Dictionary) -> void: s["lastVisitAt"] = _now_ms())
	if _busy():
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = rng.randf_range(IDLE_MIN_S, IDLE_MAX_S)
		_run_idle()
	_surprise_timer -= delta
	if _surprise_timer <= 0.0:
		_surprise_timer = SURPRISE_CHECK_S
		_run_surprise()
	_fund_timer -= delta
	if _fund_timer <= 0.0:
		_fund_timer = FUND_INTERVAL_S
		_run_mini_fund()


# ── Betreten-Moment ───────────────────────────────────────────────────────────


func _run_enter() -> void:
	var gap := SoulState.touch_visit(gs, _now_ms())
	var ctx := _ctx(gap)
	var slice := SoulState.slice_of(gs)
	var moment := SoulService.decide_enter(gs.state(), slice, _defs, ctx, rng.randf())
	if moment.is_empty():
		_maybe_habit(ctx)
		_maybe_ask_birthday(ctx)
		return
	SoulState.mutate(gs, func(s: Dictionary) -> void: SoulService.book_enter(s, moment, ctx))
	_show_moment(moment)


## Alltags-Rituale abseits des Enter-Moments: Gute-Nacht-Gähnen ab 21 Uhr
## (Zähneputzen triggert über das wokeUp-Event, s. _on_gooby_events).
func _maybe_habit(ctx: Dictionary) -> void:
	if int(ctx["hour"]) < 21:
		return
	_habit("alltag_gutenacht", ctx)


func _habit(habit_id: String, ctx: Dictionary) -> void:
	var slice := SoulState.slice_of(gs)
	var today := SoulTriggers.day_string(ctx["date"])
	if SoulTriggers.celebrated_today(slice["celebrated"], habit_id, today):
		return
	if not SoulTriggers.ambient_allowed(slice["ambient"], int(ctx["now_ms"]), today):
		return
	var def := SoulService.def_by_id(_defs, habit_id)
	if def.is_empty():
		return
	var moment := _moment_of(def, ctx)
	moment["gate_key"] = habit_id
	moment["gate_stamp"] = today
	SoulState.mutate(gs, func(s: Dictionary) -> void: SoulService.book_enter(s, moment, ctx))
	_show_moment(moment)


# ── Antippen / Kitzeln ────────────────────────────────────────────────────────


func _setup_tap_area() -> void:
	if gooby == null or room == null:
		return
	_tap_area = Area3D.new()
	_tap_area.name = "GoobyTapArea"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	_tap_area.add_child(shape)
	add_child(_tap_area)
	_tap_area.input_event.connect(_on_tap_input)


func _on_tap_input(
	_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int
) -> void:
	if event is InputEventMouseButton and event.pressed:
		handle_tap()


## Öffentlich (Tests/Screenshots rufen direkt): ein Antippen verarbeiten.
func handle_tap() -> void:
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if now_s - _tap_last_s > TAP_WINDOW_S:
		_tap_count = 0
	_tap_last_s = now_s
	_tap_count += 1
	_pet_feedback(_count_pet())
	var stage := tap_stage(_tap_count)
	if stage.is_empty():
		return
	if stage == "tipp_schwindelig":
		_tap_count = 0
	if stage == "tipp_kitzlig":
		_count_tickle()
	var def := SoulService.def_by_id(_defs, stage)
	if def.is_empty():
		return
	_show_moment(_moment_of(def, _ctx(0)), true)


## Zählt den Streichler und liefert den neuen Tagesstand (EVAL-1 D5).
func _count_pet() -> int:
	var today := SoulTriggers.day_string(_date_now())
	gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s.get("achievements", {}).get("counters", {})
			if str(counters.get("petsDay", "")) != today:
				counters["petsDay"] = today
				counters["petsToday"] = 0
			counters["petsToday"] = int(counters.get("petsToday", 0)) + 1
	)
	RewardHub.note_action(gs)
	return int(gs.get_value("achievements.counters.petsToday", 0))


## Streichel-Treppe (EVAL-1 D5): jeder Streichler klingt (steigende
## Tonhöhe) mit Herzchen, jeder zehnte gibt +1 Münze mit Gold-Float —
## vorher war Streicheln komplett belohnungsfrei.
func _pet_feedback(pets_today: int) -> void:
	AudioDirector.try_play(self, "ui_tick", pet_pitch(pets_today))
	var pos := _gooby_pos()
	if visuals_enabled and room != null and gooby != null:
		RewardFx.herz_burst(room, pos, 4)
	if not pet_bonus_due(pets_today):
		return
	_grant_coins(PET_BONUS_COINS)
	AudioDirector.try_play(self, "ui_coins")
	if visuals_enabled and room != null and gooby != null:
		RewardFx.float_text(room, pos, "+%d" % PET_BONUS_COINS, RewardFx.GOLD)
		RewardFx.herz_burst(room, pos, 14)


func _count_tickle() -> void:
	gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s.get("achievements", {}).get("counters", {})
			counters["tickles"] = int(counters.get("tickles", 0)) + 1
	)
	RewardHub.note_action(gs)


# ── Idle-Leben (Hintergrund) ──────────────────────────────────────────────────


func _run_idle() -> void:
	var ctx := _ctx(0)
	ctx["hat_tv"] = not _find_items_by_prefix("television").is_empty()
	ctx["radio_an"] = (
		bool(gs.get_value("radio.owned", false)) and bool(gs.get_value("radio.playing", false))
	)
	var slice := SoulState.slice_of(gs)
	var fav := str(slice["favFurniture"])
	ctx["hat_fav"] = not fav.is_empty() and not _find_items_by_id(fav).is_empty()
	var act := SoulService.pick_idle(_defs, ctx, _idle_cooldowns, rng.randf())
	if act.is_empty():
		return
	_idle_cooldowns[str(act["id"])] = _now_ms() + IDLE_ACT_COOLDOWN_MS
	_perform_idle(act, ctx)


func _perform_idle(act: Dictionary, ctx: Dictionary) -> void:
	var moment := _moment_of(act, ctx)
	# Idle-Texte nur manchmal (nie zutexten) — die Handlung spricht selbst.
	# EVAL-1 D4: Quote auf 70 % angehoben und jede Handlung leise vertont,
	# vorher blieben 75 s Leerlauf komplett stumm (0 Bubbles/0 SFX).
	if rng.randf() > IDLE_TEXT_QUOTE:
		moment["text_key"] = ""
	if str(moment.get("sfx", "")).is_empty():
		moment["sfx"] = "ui_tick"
	_idle_sparkle()
	match str(act.get("aktion", "")):
		"moebel":
			_walk_to_random_furniture()
		"tv":
			_walk_to_item_prefix("television")
		"fenster":
			_walk_to_window()
		"fav":
			var fav_id := str(SoulState.slice_of(gs)["favFurniture"])
			moment["args"]["moebel"] = _item_name(fav_id)
			_walk_to_item_id(fav_id)
		_:
			pass
	_show_moment(moment, true)


# ── Überraschungen ────────────────────────────────────────────────────────────


func _run_surprise() -> void:
	var ctx := _ctx(0)
	var slice := SoulState.slice_of(gs)
	var moment := SoulService.pick_surprise(slice, _defs, ctx, rng.randf(), rng.randf())
	if moment.is_empty():
		return
	SoulState.mutate(
		gs, func(s: Dictionary) -> void: SoulService.book_surprise(s, moment, _now_ms())
	)
	match str(moment.get("aktion", "")):
		"muenze":
			_grant_coins(SOFA_FUND_COINS)
		"turm":
			_build_tower()
		_:
			pass
	_show_moment(moment)


func _grant_coins(amount: int) -> void:
	gs.update(
		func(s: Dictionary) -> void:
			var econ: Dictionary = s.get("economy", {})
			Economy.award(econ, amount, "soul_sofa_fund")
	)


## Mini-Fund (EF-1, EVAL-1 D4): etwa alle FUND_INTERVAL_S ein kleiner
## Moment — Gooby findet eine Münze (Funken + „+1“-Float + Münz-Ton +
## Zeile). Die Frequenz läuft über die VORHANDENE Seelen-Bremse
## (ambient_allowed: 90-s-Mindestabstand + Tagesdeckel) — kein zweites
## Bremssystem, nichts darf nerven.
func _run_mini_fund() -> void:
	var ctx := _ctx(0)
	if not _ambient_ok():
		return
	_book_ambient(ctx)
	_grant_coins(MINI_FUND_COINS)
	AudioDirector.try_play(self, "ui_coins")
	if visuals_enabled and gooby != null and room != null:
		var pos := _gooby_pos()
		RewardFx.float_text(room, pos, "+%d" % MINI_FUND_COINS, RewardFx.GOLD)
		RewardFx.funken_burst(room, pos + Vector3(0.0, -0.25, 0.0))
	var key: String = FUND_KEYS[rng.randi_range(0, FUND_KEYS.size() - 1)]
	_say(I18nService.t(key, {"gooby": str(gs.get_value("meta.goobyNickname", "Gooby"))}))


## Kleiner Idle-Funkel (EVAL-1 D4): macht die Handlung sichtbar, ohne zu
## schreien — ein paar Glitzerteilchen am Gooby.
func _idle_sparkle() -> void:
	if not visuals_enabled or gooby == null or room == null:
		return
	RewardFx.glitzer_burst(room, gooby.global_position + Vector3(0.0, 0.7, 0.0), 6)


func _gooby_pos() -> Vector3:
	if gooby != null:
		return gooby.global_position + Vector3(0.0, 0.8, 0.0)
	return Vector3.ZERO


# ── Kommentare: Möbel, Essen, Vernachlässigung, Rituale ───────────────────────


## Nach dem Baumodus: neue Items gegen knownItems diffen → Kommentar.
func _on_build_mode_toggled(active: bool) -> void:
	if active or room.grid == null:
		return
	var slice := SoulState.slice_of(gs)
	var known: Dictionary = slice["knownItems"]
	var fresh: Array[String] = []
	var current := {}
	for entry: Dictionary in room.grid.to_items_array():
		var item_id := str(entry["item"])
		current[item_id] = true
		if not known.has(item_id):
			fresh.append(item_id)
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["knownItems"] = current)
	if fresh.is_empty() or not _ambient_ok():
		return
	var def := SoulService.def_by_id(_defs, "kommentar_moebel_neu")
	if def.is_empty():
		return
	var ctx := _ctx(0)
	var moment := _moment_of(def, ctx)
	moment["args"]["moebel"] = _item_name(fresh[0])
	_book_ambient(ctx)
	_show_moment(moment)


## Fütterungen aus echten Daten: inventory.food-Abnahmen zählen. Ab
## FAV_FOOD_MIN Fütterungen wird das meistgegebene Essen zum Lieblingsessen.
func _on_stats_changed(stats: Dictionary) -> void:
	_check_food_given()
	_check_neglect(stats)


func _check_food_given() -> void:
	var now_food := _food_now()
	var given := ""
	for food_id: String in _food_snapshot:
		if int(now_food.get(food_id, 0)) < int(_food_snapshot[food_id]):
			given = food_id
			break
	_food_snapshot = now_food
	if given.is_empty():
		return
	var counted := 0
	SoulState.mutate(
		gs,
		func(s: Dictionary) -> void: s["foodGiven"][given] = int(s["foodGiven"].get(given, 0)) + 1
	)
	counted = int(SoulState.slice_of(gs)["foodGiven"].get(given, 0))
	_comment_food(given, counted)


func _comment_food(food_id: String, count: int) -> void:
	if not _ambient_ok():
		return
	var ctx := _ctx(0)
	var slice := SoulState.slice_of(gs)
	var today := SoulTriggers.day_string(ctx["date"])
	var is_favorite := count >= FAV_FOOD_MIN and count >= _max_food_given(slice)
	var def_id := "kommentar_lieblingsessen" if is_favorite else "kommentar_geschenk"
	var gate := "essen_" + def_id
	if SoulTriggers.celebrated_today(slice["celebrated"], gate, today):
		return
	var def := SoulService.def_by_id(_defs, def_id)
	if def.is_empty():
		return
	var moment := _moment_of(def, ctx)
	moment["args"]["essen"] = _food_name(food_id)
	moment["gate_key"] = gate
	moment["gate_stamp"] = today
	SoulState.mutate(gs, func(s: Dictionary) -> void: SoulService.book_enter(s, moment, ctx))
	_show_moment(moment)


func _max_food_given(slice: Dictionary) -> int:
	var top := 0
	for food_id: String in slice["foodGiven"]:
		top = maxi(top, int(slice["foodGiven"][food_id]))
	return top


## Vernachlässigung = traurige Blicke (NIE Strafen): sad-Emotion + seltener,
## sanfter Kommentar. Erholt sich sofort, wenn die Werte wieder gut sind.
func _check_neglect(stats: Dictionary) -> void:
	var lowest := 100.0
	for key: String in stats:
		lowest = minf(lowest, float(stats[key]))
	if lowest >= NEGLECT_STAT_THRESHOLD:
		if _sad:
			_sad = false
			_set_emotion("happy")
		return
	if _sad:
		return
	_sad = true
	_set_emotion("sad")
	if not _ambient_ok():
		return
	var ctx := _ctx(0)
	var slice := SoulState.slice_of(gs)
	var today := SoulTriggers.day_string(ctx["date"])
	if SoulTriggers.celebrated_today(slice["celebrated"], "traurig", today):
		return
	var def := SoulService.def_by_id(_defs, "kommentar_traurig")
	if def.is_empty():
		return
	var moment := _moment_of(def, ctx)
	moment["emotion"] = ""
	moment["gate_key"] = "traurig"
	moment["gate_stamp"] = today
	SoulState.mutate(gs, func(s: Dictionary) -> void: SoulService.book_enter(s, moment, ctx))
	_show_moment(moment)


## Ticker-Events: nach dem Aufwachen (wokeUp) morgens ans Zähneputzen denken.
func _on_gooby_events(events: Array) -> void:
	if not events.has("wokeUp"):
		return
	var ctx := _ctx(0)
	var hour := int(ctx["hour"])
	if hour >= 5 and hour <= 11:
		_habit("alltag_zaehne", ctx)


# ── Geburtstags-Frage (kleines, wegklickbares Panel) ──────────────────────────


func _maybe_ask_birthday(ctx: Dictionary) -> void:
	var slice := SoulState.slice_of(gs)
	if not SoulService.should_ask_birthday(slice, ctx):
		return
	var def := SoulService.def_by_id(_defs, "frage_geburtstag")
	if def.is_empty():
		return
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["askedBirthdayAt"] = int(ctx["now_ms"]))
	_book_ambient(ctx)
	_show_moment(_moment_of(def, ctx))
	_open_birthday_panel()


func _open_birthday_panel() -> void:
	if not room.has_method("ui_layer"):
		return
	var panel := PanelContainer.new()
	panel.name = "SoulBirthdayPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = I18nService.t("soul.geburtstag_panel.titel")
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var month := SpinBox.new()
	month.min_value = 1
	month.max_value = 12
	month.prefix = I18nService.t("soul.geburtstag_panel.monat")
	row.add_child(month)
	var day := SpinBox.new()
	day.min_value = 1
	day.max_value = 31
	day.prefix = I18nService.t("soul.geburtstag_panel.tag")
	row.add_child(day)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var save := Button.new()
	save.text = I18nService.t("soul.geburtstag_panel.speichern")
	save.custom_minimum_size = Vector2(0, 44)
	buttons.add_child(save)
	var cancel := Button.new()
	cancel.text = I18nService.t("soul.geburtstag_panel.abbrechen")
	cancel.custom_minimum_size = Vector2(0, 44)
	buttons.add_child(cancel)
	room.ui_layer().add_child(panel)
	save.pressed.connect(_on_birthday_saved.bind(month, day, panel))
	cancel.pressed.connect(func() -> void: panel.queue_free())


func _on_birthday_saved(month: SpinBox, day: SpinBox, panel: Control) -> void:
	var m := int(month.value)
	var d := int(day.value)
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["playerBirthday"] = {"month": m, "day": d})
	panel.queue_free()
	_say(I18nService.t("soul.geburtstag_panel.danke", {"tag": d, "monat": m}))
	AudioDirector.try_play(self, "ui_confirm")


# ── Anzeige / Visuals ─────────────────────────────────────────────────────────


func _show_moment(moment: Dictionary, quiet_ok := false) -> void:
	if moment.is_empty():
		return
	var text_key := str(moment.get("text_key", ""))
	if not text_key.is_empty():
		var now_s := float(Time.get_ticks_msec()) / 1000.0
		if quiet_ok and now_s - _last_bubble_s < BUBBLE_MIN_GAP_S:
			text_key = ""
		else:
			_last_bubble_s = now_s
			_say(I18nService.t(text_key, moment.get("args", {})))
	var emotion := str(moment.get("emotion", ""))
	if not emotion.is_empty():
		_set_emotion(emotion, true)
	var clip := str(moment.get("clip", ""))
	if not clip.is_empty() and gooby != null and gooby.get("rig") != null:
		gooby.rig.play_clip(clip)
	var sfx := str(moment.get("sfx", ""))
	if not sfx.is_empty():
		AudioDirector.try_play(self, sfx)
	match str(moment.get("aktion", "")):
		"konfetti":
			_confetti()
		"fenster":
			_walk_to_window()
		"winken":
			pass
		_:
			pass


func _say(text: String) -> void:
	if room != null and room.has_method("say") and not text.is_empty():
		room.say(text)


func _set_emotion(emotion: String, revert := false) -> void:
	if gooby == null or gooby.get("rig") == null:
		return
	gooby.rig.set_emotion(emotion)
	if not revert or emotion == "happy" or emotion == "neutral":
		return
	_emotion_revert = get_tree().create_timer(EMOTION_REVERT_S)
	# Methoden-Callable statt Lambda (REST5, B2): stirbt dieser Node vor dem
	# Timeout, trennt Godot die Verbindung automatisch.
	_emotion_revert.timeout.connect(_revert_emotion)


func _revert_emotion() -> void:
	if not _sad and gooby != null and is_instance_valid(gooby):
		gooby.rig.set_emotion("happy")


## Konfetti-Regen (Geburtstage/Jubiläen) — reine CPU-Partikel, kein Asset.
func _confetti() -> void:
	if not visuals_enabled or gooby == null:
		return
	var particles := CPUParticles3D.new()
	particles.amount = 96
	particles.lifetime = 2.2
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.direction = Vector3.UP
	particles.initial_velocity_min = 1.6
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -2.6, 0.0)
	particles.spread = 75.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	# Ohne vertex_color_use_as_albedo rendert der Gradient NICHT (grau).
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	particles.mesh = mesh
	particles.color_ramp = _confetti_gradient()
	particles.position = gooby.global_position + Vector3(0.0, 0.9, 0.0)
	room.add_child(particles)
	particles.emitting = true
	# Methoden-Callable statt Lambda (B2): stirbt der Raum vor dem Timeout,
	# räumt Godot die Verbindung ab — kein "Lambda capture ... was freed".
	get_tree().create_timer(2.5).timeout.connect(particles.queue_free)


static func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color("#FF7BA9"))
	gradient.set_color(1, Color("#59C9B9"))
	gradient.add_point(0.5, Color("#FFD166"))
	return gradient


## Kissenturm-Gag: drei gestapelte, weiche Boxen neben Gooby (kurzlebig).
func _build_tower() -> void:
	if not visuals_enabled or gooby == null:
		return
	var tower := Node3D.new()
	tower.name = "SoulTower"
	var colors := [Color("#F4BFCD"), Color("#59C9B9"), Color("#FFD166")]
	for i in 3:
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4 - 0.06 * i, 0.22, 0.4 - 0.06 * i)
		block.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[i]
		block.material_override = material
		block.position = Vector3(0.0, 0.11 + 0.23 * i, 0.0)
		tower.add_child(block)
	tower.position = gooby.global_position + Vector3(0.6, 0.0, 0.2)
	room.add_child(tower)
	# Methoden-Callable statt Lambda (B2) — s. Konfetti oben.
	get_tree().create_timer(10.0).timeout.connect(tower.queue_free)


# ── Laufwege ─────────────────────────────────────────────────────────────────


func _walk_to_window() -> void:
	if not visuals_enabled or gooby == null or room.grid == null:
		return
	# Ans nördliche Raum-Ende (Außenwand mit Fenster-Diorama) schlendern.
	var cells: Array[Vector2i] = room.grid.free_cells()
	var best := Vector2i(-1, -1)
	for cell: Vector2i in cells:
		if best.x < 0 or cell.y < best.y:
			best = cell
	if best.x >= 0:
		gooby.walk_to(GridData.world_center(best, Vector2i.ONE, 0), 5.0)


func _walk_to_random_furniture() -> void:
	if not visuals_enabled or gooby == null or room.grid == null:
		return
	var items: Array = room.grid.to_items_array()
	if items.is_empty():
		return
	var entry: Dictionary = items[rng.randi_range(0, items.size() - 1)]
	_walk_near_cell(Vector2i(int(entry["at"][0]), int(entry["at"][1])))


func _walk_to_item_prefix(prefix: String) -> void:
	var found := _find_items_by_prefix(prefix)
	if not found.is_empty():
		_walk_near_cell(found[0])


func _walk_to_item_id(item_id: String) -> void:
	var found := _find_items_by_id(item_id)
	if not found.is_empty():
		_walk_near_cell(found[0])


func _walk_near_cell(cell: Vector2i) -> void:
	if not visuals_enabled or gooby == null or room.grid == null:
		return
	for step: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = cell + step
		if room.grid.walkable(neighbor):
			gooby.walk_to(GridData.world_center(neighbor, Vector2i.ONE, 0), 5.0)
			return


func _find_items_by_prefix(prefix: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if room.grid == null:
		return out
	for entry: Dictionary in room.grid.to_items_array():
		if str(entry["item"]).begins_with(prefix):
			out.append(Vector2i(int(entry["at"][0]), int(entry["at"][1])))
	return out


func _find_items_by_id(item_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if item_id.is_empty() or room.grid == null:
		return out
	for entry: Dictionary in room.grid.to_items_array():
		if str(entry["item"]) == item_id:
			out.append(Vector2i(int(entry["at"][0]), int(entry["at"][1])))
	return out


## Lieblingsmöbel einmalig deterministisch wählen (Hash aus firstMetAt) —
## bleibt für immer, außer das Möbel verschwindet aus dem Zuhause.
func _pick_favorite_if_needed() -> void:
	if room.grid == null:
		return
	var slice := SoulState.slice_of(gs)
	if not str(slice["favFurniture"]).is_empty():
		return
	var ids: Array[String] = []
	for entry: Dictionary in room.grid.to_items_array():
		var item_id := str(entry["item"])
		if not ids.has(item_id):
			ids.append(item_id)
	if ids.is_empty():
		return
	ids.sort()
	var pick: String = ids[int(slice["firstMetAt"]) % ids.size()]
	SoulState.mutate(gs, func(s: Dictionary) -> void: s["favFurniture"] = pick)


# ── Kontext / Helfer ─────────────────────────────────────────────────────────


func _ctx(gap_ms: int) -> Dictionary:
	var date := _date_now()
	var datum := SoulTriggers.day_string(date)
	return {
		"now_ms": _now_ms(),
		"date": date,
		"hour": int(date.get("hour", 12)),
		"gap_ms": gap_ms,
		"wetter": SoulWetter.zustand(datum, float(date.get("hour", 12))),
		"player_name": str(gs.get_value("meta.playerName", "")),
		"nickname": str(gs.get_value("meta.goobyNickname", "Gooby")),
	}


func _now_ms() -> int:
	if now_ms_override >= 0:
		return now_ms_override
	return int(Time.get_unix_time_from_system() * 1000.0)


func _date_now() -> Dictionary:
	if now_ms_override >= 0:
		return Time.get_datetime_dict_from_unix_time(int(now_ms_override / 1000.0))
	return Time.get_datetime_dict_from_system()


func _busy() -> bool:
	if room == null or gs == null:
		return true
	if room.has_method("is_build_mode_active") and room.is_build_mode_active():
		return true
	return false


func _ambient_ok() -> bool:
	var slice := SoulState.slice_of(gs)
	return SoulTriggers.ambient_allowed(
		slice["ambient"], _now_ms(), SoulTriggers.day_string(_date_now())
	)


func _book_ambient(ctx: Dictionary) -> void:
	SoulState.mutate(
		gs,
		func(s: Dictionary) -> void:
			s["ambient"] = SoulTriggers.note_ambient(
				s["ambient"], int(ctx["now_ms"]), SoulTriggers.day_string(ctx["date"])
			)
	)


## Snapshot der Futter-Bestände (inventory.food) — Abnahme = Fütterung.
func _food_now() -> Dictionary:
	var food: Variant = gs.get_value("inventory.food", {})
	if food is Dictionary:
		return (food as Dictionary).duplicate(true)
	return {}


func _item_name(item_id: String) -> String:
	var def := FurnitureCatalog.def(item_id)
	if def.is_empty():
		return item_id
	return FurnitureCatalog.display_name(def, I18nService.get_locale())


func _food_name(food_id: String) -> String:
	var key := "soul.essen." + food_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	# EF-1: neue Speisen heißen im rewards-Katalog (Kühlschrank/REHWEI/Garten).
	return FoodCatalog.display_name(food_id)


func _moment_of(def: Dictionary, ctx: Dictionary) -> Dictionary:
	var slice := SoulState.slice_of(gs)
	var args := {
		"name": str(ctx.get("player_name", "")),
		"gooby": str(ctx.get("nickname", "Gooby")),
		"tage": SoulTriggers.days_known(int(slice["firstMetAt"]), int(ctx["now_ms"])),
	}
	var player_name := str(ctx.get("player_name", ""))
	args["namek"] = (", " + player_name) if not player_name.is_empty() else ""
	var keys: Array = def.get("text_keys", [])
	var text_key := ""
	if not keys.is_empty():
		text_key = str(keys[rng.randi_range(0, keys.size() - 1)])
	return {
		"id": str(def.get("id", "")),
		"kind": str(def.get("kind", "kommentar")),
		"text_key": text_key,
		"args": args,
		"emotion": str(def.get("emotion", "happy")),
		"clip": str(def.get("clip", "")),
		"sfx": str(def.get("sfx", "")),
		"aktion": str(def.get("aktion", "")),
	}
