class_name DailyQuestService
extends Node
## Tagesquest-Dienst (REST-2): das Bindeglied zwischen der puren
## DailyQuestEngine und dem laufenden Spiel. Häng-Punkt ist der Home-Entry
## (eine Zeile, Muster RewardHub.attach_to). Verantwortungen:
##  - beim Start + bei Tageswechsel das heutige Brett würfeln (deterministisch,
##    DailyQuestEngine.roll_today — Slice additiv im bestehenden `quests`-Dict),
##  - Fortschritt beobachten (GameState-Signale; Zähler-Bumps melden sich über
##    RewardHub.note_action → slice_changed("achievements")),
##  - Claims auszahlen über die VORHANDENEN Pfade (Economy.award + Leveling.
##    apply_xp — kein zweites Belohnungssystem; Sticker feiert der RewardHub
##    selbst, weil questsDone ein normaler Achievements-Zähler ist),
##  - Abschluss-Bonus zahlen, wenn alle drei geclaimt sind,
##  - das Quest-Panel (HUD-Knopf `quests`) und den „Was nun?“-Hinweis zeigen.
##
## Alles abschaltbar/dezent: der Hinweis respektiert AppSettings
## `hints.whats_next_enabled`, ist pro Vorschlag+Tag nur 1× sichtbar und
## verschwindet, solange der Onboarding-Guide läuft.

signal quests_changed

const GROUP := &"daily_quest_service"
const SHEET_SCENE := "res://scripts/ui/panel_sheet.tscn"
## Tageswechsel-/Aufräum-Puls (Sekunden) — billig, nur ein Datumsvergleich.
const TICK_S := 30.0
const HINT_SETTING := "hints.whats_next_enabled"

const Economy := preload("res://scripts/logic/economy.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

var _gs: Object = null
var _layer: CanvasLayer
var _toasts: ToastLayer
var _sheet: PanelSheet
var _panel: DailyQuestPanel
var _hint: WhatsNextHint
var _timer: Timer
## Pro Sitzung weggedrückte Hinweise: "vorschlag_id:tag" → true.
var _hint_dismissed: Dictionary = {}


## Dienst erzeugen und an den Home-Entry hängen (idempotent, Gruppe).
static func attach_to(parent: Node, gs: Object) -> DailyQuestService:
	var tree := parent.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is DailyQuestService:
			return existing
	var service := DailyQuestService.new()
	service.name = "DailyQuestService"
	service._gs = gs
	parent.add_child(service)
	return service


static func find_service() -> DailyQuestService:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var found := (loop as SceneTree).get_first_node_in_group(GROUP)
	return found if found is DailyQuestService else null


## EIN Verdrahtungspunkt für den HUD-Quests-Knopf (home_entry-Dispatch):
## konsumiert die Action und öffnet das Panel.
static func handle_hud_action(action: StringName) -> bool:
	if action != &"quests":
		return false
	var service := find_service()
	if service != null:
		service.open_panel()
	return true


func _ready() -> void:
	add_to_group(GROUP)
	_layer = CanvasLayer.new()
	_layer.name = "QuestLayer"
	_layer.layer = 60
	add_child(_layer)
	_toasts = ToastLayer.new()
	_toasts.name = "QuestToasts"
	_toasts.theme = ThemeService.theme()
	_toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_toasts)
	_timer = Timer.new()
	_timer.wait_time = TICK_S
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()
	if _gs != null:
		if _gs.has_signal("slice_changed"):
			_gs.slice_changed.connect(_on_slice_changed)
		if _gs.has_signal("coins_changed"):
			_gs.coins_changed.connect(func(_coins: int) -> void: _on_progress_maybe_changed())
		if _gs.has_signal("stats_changed"):
			_gs.stats_changed.connect(func(_stats: Dictionary) -> void: refresh_hint())
	ensure_roll()
	_wire_router()
	refresh_hint()


## --- Brett / Fortschritt -----------------------------------------------------


func today() -> String:
	if _gs != null and "clock" in _gs:
		return str(_gs.clock.local_day())
	var date := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


func pool() -> Array:
	return DailyQuestCatalog.pool()


## Kontext für `braucht`-Filter: Level, freigeschaltete Spiele, Garten.
func ctx() -> Dictionary:
	var games: Array[String] = []
	for meta in MinigameRegistry.playable():
		games.append(str(meta["id"]))
	return {
		"level": int(_gs.get_value("progression.level", 1)) if _gs != null else 1,
		"minigames": games,
		"garden": true,
	}


## Heutiges Brett sicherstellen (No-op, wenn schon gerollt).
func ensure_roll() -> void:
	if _gs == null:
		return
	var day := today()
	var quest_pool := pool()
	var quest_ctx := ctx()
	var rolled := false
	_gs.update(
		func(state: Dictionary) -> void:
			rolled = DailyQuestEngine.roll_today(
				_slice_of(state), day, quest_pool, quest_ctx, state
			)
	)
	if rolled:
		_gs.notify_slice_changed("quests")
		quests_changed.emit()


## Anzeigefertiges Brett: [{def, entry, progress, target, complete, claimed}].
func board() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _gs == null:
		return out
	var state: Dictionary = _gs.state()
	var by_id := DailyQuestEngine.pool_by_id(pool())
	var slice: Variant = state.get("quests", {})
	if not (slice is Dictionary) or not (slice.get("active") is Array):
		return out
	for entry: Variant in slice["active"]:
		if not (entry is Dictionary):
			continue
		var def: Dictionary = by_id.get(str(entry.get("id", "")), {})
		if def.is_empty():
			continue
		var target := DailyQuestEngine.target_of(def)
		var progress := DailyQuestEngine.progress_of(entry, def, state)
		(
			out
			. append(
				{
					"def": def,
					"entry": entry,
					"progress": progress,
					"target": target,
					"complete": progress >= target,
					"claimed": bool(entry.get("claimed", false)),
				}
			)
		)
	return out


func claimable_count() -> int:
	if _gs == null:
		return 0
	var state: Dictionary = _gs.state()
	return DailyQuestEngine.claimable_count(
		_slice_of(state), DailyQuestEngine.pool_by_id(pool()), state
	)


func all_claimed() -> bool:
	return _gs != null and DailyQuestEngine.all_claimed(_slice_of(_gs.state()))


func reroll_available() -> bool:
	if _gs == null:
		return false
	return str(_slice_of(_gs.state()).get("rerolledDay", "")) != today()


## --- Claim / Bonus / Reroll --------------------------------------------------


## Quest abholen: Engine-Claim + Auszahlung über die EINEN Geld/XP-Pfade.
## Liefert {"ok", "muenzen", "xp", "bonus": {..}|{}} — UI feiert damit.
func claim(id: String) -> Dictionary:
	if _gs == null:
		return {"ok": false, "muenzen": 0, "xp": 0, "bonus": {}}
	var day := today()
	var def: Dictionary = DailyQuestEngine.pool_by_id(pool()).get(id, {})
	var result := {"ok": false, "muenzen": 0, "xp": 0}
	_gs.update(
		func(state: Dictionary) -> void:
			result = DailyQuestEngine.claim(_slice_of(state), id, def, state)
			if not bool(result["ok"]):
				return
			_pay(state, int(result["muenzen"]), int(result["xp"]), day, "quest")
			var counters: Dictionary = state.get("achievements", {}).get("counters", {})
			counters["questsDone"] = int(counters.get("questsDone", 0)) + 1
	)
	result["bonus"] = {}
	if not bool(result["ok"]):
		return result
	_gs.notify_slice_changed("quests")
	RewardHub.note_action(_gs)
	result["bonus"] = _maybe_pay_bonus(day)
	quests_changed.emit()
	refresh_hint()
	return result


## Abschluss-Bonus zahlen, wenn fällig ({} sonst).
func _maybe_pay_bonus(day: String) -> Dictionary:
	var due := false
	_gs.update(
		func(state: Dictionary) -> void:
			var slice := _slice_of(state)
			due = DailyQuestEngine.bonus_due(slice, day)
			if not due:
				return
			DailyQuestEngine.mark_bonus_paid(slice, day)
			_pay(state, DailyQuestEngine.BONUS_COINS, DailyQuestEngine.BONUS_XP, day, "questBonus")
	)
	if not due:
		return {}
	_gs.notify_slice_changed("quests")
	_toasts.show_toast(
		I18nService.t("quests.bonus_toast", {"muenzen": DailyQuestEngine.BONUS_COINS})
	)
	return {"muenzen": DailyQuestEngine.BONUS_COINS, "xp": DailyQuestEngine.BONUS_XP}


## 1× täglicher Reroll unangefangener Quests.
func reroll() -> bool:
	if _gs == null:
		return false
	var day := today()
	var quest_pool := pool()
	var quest_ctx := ctx()
	var done := false
	_gs.update(
		func(state: Dictionary) -> void:
			done = DailyQuestEngine.reroll_today(
				_slice_of(state), day, quest_pool, quest_ctx, state
			)
	)
	if done:
		_gs.notify_slice_changed("quests")
		_toasts.show_toast(I18nService.t("quests.reroll_toast"))
		quests_changed.emit()
	return done


## Münzen + XP über die vorhandenen Pfade buchen (Level-Up-Coins inklusive).
func _pay(state: Dictionary, coins: int, xp: int, day: String, reason: String) -> void:
	var econ: Dictionary = state.get("economy", {})
	if coins > 0:
		Economy.award(econ, coins, reason, day)
	if xp <= 0:
		return
	var prog: Dictionary = state.get("progression", {})
	var res := Leveling.apply_xp(
		{"xp": float(prog.get("xp", 0.0)), "level": int(prog.get("level", 1))}, float(xp)
	)
	prog["xp"] = res["xp"]
	prog["level"] = res["level"]
	if int(res["coinsAwarded"]) > 0:
		Economy.award(econ, res["coinsAwarded"], "levelUp", day)


## --- Panel -------------------------------------------------------------------


func open_panel() -> void:
	if _sheet == null or not is_instance_valid(_sheet):
		_sheet = (load(SHEET_SCENE) as PackedScene).instantiate()
		_layer.add_child(_sheet)
		# Nach dem Zuklappen darf der „Was nun?“-Hinweis wieder übernehmen.
		_sheet.closed.connect(refresh_hint)
		_panel = DailyQuestPanel.new()
		_panel.claim_pressed.connect(_on_panel_claim)
		_panel.reroll_pressed.connect(_on_panel_reroll)
	ensure_roll()
	_sheet.set_title(I18nService.t("quests.titel"))
	_refresh_panel()
	_sheet.add_content(_panel)
	_sheet.open()
	# Ein evtl. sichtbarer „Was nun?“-Hinweis verschwindet, solange das
	# Panel offen ist (das Sheet-Gate in _hint_allowed blendet ihn aus).
	refresh_hint()


func _refresh_panel() -> void:
	if _panel == null:
		return
	var f := UiScale.for_viewport(get_viewport())
	_panel.rebuild(board(), _bonus_info(), reroll_available(), f)


func _bonus_info() -> Dictionary:
	var paid := (
		_gs != null and str(_slice_of(_gs.state()).get("bonusDay", "")) == today() and all_claimed()
	)
	return {
		"muenzen": DailyQuestEngine.BONUS_COINS,
		"xp": DailyQuestEngine.BONUS_XP,
		"paid": paid,
	}


func _on_panel_claim(id: String) -> void:
	var result := claim(id)
	if not bool(result["ok"]):
		_refresh_panel()
		return
	AudioDirector.try_play(self, "ui_sticker")
	_toasts.show_toast(
		I18nService.t(
			"quests.claim_toast", {"muenzen": int(result["muenzen"]), "xp": int(result["xp"])}
		)
	)
	if _panel != null:
		_panel.mark_claimed(id, _bonus_info())
	var bonus: Dictionary = result.get("bonus", {})
	if not bonus.is_empty() and _panel != null:
		AudioDirector.try_play(self, "mg_win")
		var breite := 640.0
		var viewport := get_viewport()
		if viewport != null:
			breite = viewport.get_visible_rect().size.x
		RewardFx.konfetti_2d(_toasts, 40, breite)


func _on_panel_reroll() -> void:
	reroll()
	_refresh_panel()


## --- „Was nun?“-Hinweis ------------------------------------------------------


func refresh_hint() -> void:
	if _gs == null or _layer == null:
		return
	if not _hint_allowed():
		_set_hint({})
		return
	var suggestion := WhatsNextAdvisor.suggest(_gs.state(), board(), _advisor_ctx())
	if suggestion.is_empty():
		_set_hint({})
		return
	var gate := "%s:%s" % [str(suggestion.get("id", "")), today()]
	if _hint_dismissed.has(gate):
		_set_hint({})
		return
	_set_hint(suggestion)


func _hint_allowed() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if (
		settings != null
		and settings.has_method("get_setting")
		and not bool(settings.get_setting(HINT_SETTING, true))
	):
		return false
	# Solange der Guide läuft, hält der Hinweis den Mund (nichts darf nerven).
	if get_tree().get_first_node_in_group(OnboardingGuide.GROUP) != null:
		return false
	# Bei offenem Quest-Panel wäre „schau in deine Quests“ nur Rauschen.
	if _sheet != null and is_instance_valid(_sheet) and _sheet.is_open():
		return false
	if not bool(_gs.get_value("onboarding.done", false)):
		return false
	return _in_room()


func _in_room() -> bool:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return true
	return router.get_current_scene() is RoomBase


func _advisor_ctx() -> Dictionary:
	return {
		"ranch_level": RanchKatalog.freischalt_level(),
		"claimable": claimable_count(),
		"all_claimed": all_claimed(),
	}


func _set_hint(suggestion: Dictionary) -> void:
	if suggestion.is_empty():
		if _hint != null and is_instance_valid(_hint):
			_hint.hide_hint()
		return
	if _hint == null or not is_instance_valid(_hint):
		_hint = WhatsNextHint.new()
		_hint.tapped.connect(_on_hint_tapped)
		_hint.dismissed.connect(_on_hint_dismissed)
		_layer.add_child(_hint)
	_hint.show_suggestion(suggestion)


func _on_hint_tapped(suggestion: Dictionary) -> void:
	if str(suggestion.get("aktion", "")) == "quests":
		open_panel()
	_on_hint_dismissed(suggestion)


func _on_hint_dismissed(suggestion: Dictionary) -> void:
	_hint_dismissed["%s:%s" % [str(suggestion.get("id", "")), today()]] = true
	if _hint != null and is_instance_valid(_hint):
		_hint.hide_hint()


## --- intern ------------------------------------------------------------------


func _wire_router() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)
	if router.has_signal("travel_started"):
		router.travel_started.connect(_on_travel_started)


func _on_travel_finished(_target: Variant = null) -> void:
	refresh_hint()


func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	_set_hint({})


func _on_slice_changed(slice_id: String, _data: Variant) -> void:
	if slice_id in ["achievements", "home", "stickers", "onboarding"]:
		_on_progress_maybe_changed()


func _on_progress_maybe_changed() -> void:
	if _sheet != null and is_instance_valid(_sheet) and _sheet.is_open():
		_refresh_panel()
	refresh_hint()


func _on_tick() -> void:
	ensure_roll()
	refresh_hint()


func _slice_of(state: Dictionary) -> Dictionary:
	if not (state.get("quests") is Dictionary):
		state["quests"] = {"completedTotal": 0}
	return state["quests"]
