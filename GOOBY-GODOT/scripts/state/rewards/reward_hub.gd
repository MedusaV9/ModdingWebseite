class_name RewardHub
extends Node
## Globale Belohnungs-Zentrale (EF-1, EVAL-1 D2): wertet die 141 Sticker-
## Freischaltbedingungen NACH JEDER relevanten Handlung aus (signalbasiert
## über StickerUnlocks am GameState) und feiert jeden neuen Sticker sofort —
## Toast + `ui_sticker`-Pluck + Konfetti-Burst auf einer eigenen, obersten
## CanvasLayer, egal welcher Screen gerade offen ist. Vorher feuerten
## Sticker nur bei offenem Album (album_screen.gd) — das Album hängt sich
## jetzt an DIESEN Hub (kein Doppel-Service, keine Doppel-Feier).
##
## Frequenzbremse: Feiern werden in einer Queue serialisiert (eine Feier
## alle FEIER_ABSTAND_S), Toasts stapeln nie (ToastQueue). Set-komplett-
## Belohnungen werden zusätzlich hier geclaimt (additiv in
## stickers.setRewards — identisch idempotent zum Album-Pfad).
##
## REST-1: derselbe Hub feiert jetzt auch die 44 ERFOLGE (AchievementsService
## hängt hier, kein zweites System) und bietet beim ersten Start des Tages
## den TAGESBONUS an (DailyBonusPopup auf der Hub-Layer) — beide teilen die
## Feier-Queue/Toasts/Konfetti mit den Stickern.

signal sticker_celebrated(def: Dictionary)
signal achievement_celebrated(def: Dictionary)
signal daily_bonus_claimed(reward: Dictionary)

## Serialisierung der Feiern — nie zwei Konfetti-Bursts übereinander.
const FEIER_ABSTAND_S := 2.6
const KONFETTI_TEILE := 40
const SET_REWARD_COINS := 120
const GROUP := &"reward_hub"

const Economy := preload("res://scripts/logic/economy.gd")

var unlocks: StickerUnlocks
## REST-1: Erfolgs-Auswertung — gleiches Muster wie `unlocks`.
var achievements: AchievementsService

var _gs: Object = null
var _layer: CanvasLayer
var _toasts: ToastLayer
## Feier-Queue: [{kind: "sticker"|"erfolg", def: {...}}].
var _queue: Array[Dictionary] = []
var _draining := false
var _daily_popup: Control = null
## Einmal pro Session beim ersten travel_finished anbieten (s. _wire_daily_bonus).
var _daily_offer_done := false


## Hub erzeugen und an den Home-Entry hängen (idempotent, Gruppe reward_hub).
static func attach_to(parent: Node, gs: Object) -> RewardHub:
	var tree := parent.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is RewardHub:
			return existing
	var hub := RewardHub.new()
	hub.name = "RewardHub"
	hub._gs = gs
	parent.add_child(hub)
	return hub


## Aktiver Hub im Baum ({null} ohne Home-Entry, z. B. nackte Tests).
static func find(node: Node) -> RewardHub:
	if node == null or not node.is_inside_tree():
		return null
	var found := node.get_tree().get_first_node_in_group(GROUP)
	return found if found is RewardHub else null


## Nach Counter-Bumps (feeds/washes/pets/...) die Auswertung anstoßen —
## Counter-Mutationen emittieren sonst KEIN Signal (game_state.update
## beobachtet nur coins/stats/level/xp).
static func note_action(gs: Object) -> void:
	if gs != null and gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("achievements")


func _ready() -> void:
	add_to_group(GROUP)
	_layer = CanvasLayer.new()
	_layer.name = "RewardLayer"
	_layer.layer = 90
	add_child(_layer)
	_toasts = ToastLayer.new()
	_toasts.name = "RewardToasts"
	_toasts.theme = ThemeService.theme()
	_toasts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_toasts)
	unlocks = StickerUnlocks.new()
	unlocks.name = "GlobalStickerUnlocks"
	add_child(unlocks)
	unlocks.sticker_unlocked.connect(_on_sticker_unlocked)
	achievements = AchievementsService.new()
	achievements.name = "GlobalAchievements"
	add_child(achievements)
	achievements.achievement_unlocked.connect(_on_achievement_unlocked)
	if _gs != null:
		unlocks.attach(_gs)
		achievements.attach(_gs)
		_wire_daily_bonus()


## REST-1: Tagesbonus beim ersten Start des Tages anbieten. Mit Router
## wartet das Angebot auf die ERSTE Ankunft im Raum (travel_finished) und
## jede weitere Reise schließt ein offenes Popup („Später“-Semantik — der
## Bonus bleibt bis Mitternacht abholbar). Ohne Router (nackte Tests) kommt
## das Angebot deferred direkt. App-Resume prüft erneut (Datumswechsel).
func _wire_daily_bonus() -> void:
	if _gs is Node and (_gs as Node).has_signal("slice_changed"):
		(_gs as Node).slice_changed.connect(_on_gs_slice_changed)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)
		router.travel_started.connect(_on_travel_started)
	else:
		_maybe_offer_daily_bonus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_maybe_offer_daily_bonus()


## Erste Raum-Ankunft der Session → Tagesbonus anbieten (einmalig; Resume
## und Onboarding-Abschluss prüfen separat erneut).
func _on_travel_finished(_target: Variant = null) -> void:
	if _daily_offer_done:
		return
	_daily_offer_done = true
	_maybe_offer_daily_bonus()


## Reiseantritt mit offenem Popup = „Später“: schließen, nicht claimen.
func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	if _daily_popup != null and is_instance_valid(_daily_popup):
		_daily_popup.queue_free()
	_daily_popup = null


## Feiert das Album gerade selbst mit? Nein — das Album zeigt nur noch den
## Grid-Refresh, die Feier (Toast+Ton+Konfetti) kommt IMMER von hier.
func _on_sticker_unlocked(def: Dictionary) -> void:
	_queue.append({"kind": "sticker", "def": def})
	if not _draining:
		_drain_queue()


func _on_achievement_unlocked(def: Dictionary) -> void:
	_queue.append({"kind": "erfolg", "def": def})
	if not _draining:
		_drain_queue()


func _drain_queue() -> void:
	_draining = true
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		var def: Dictionary = entry.get("def", {})
		if str(entry.get("kind", "sticker")) == "erfolg":
			_celebrate_achievement(def)
		else:
			_celebrate(def)
		var tree := get_tree()
		if tree == null:
			break
		await tree.create_timer(FEIER_ABSTAND_S).timeout
	_draining = false


func _celebrate(def: Dictionary) -> void:
	var sticker_name := str(def.get("name_de", def.get("id", "")))
	_toasts.show_toast(I18nService.t("album.unlock_toast", {"name": sticker_name}))
	AudioDirector.try_play(self, "ui_sticker")
	var breite := 640.0
	var viewport := get_viewport()
	if viewport != null:
		breite = viewport.get_visible_rect().size.x
	RewardFx.konfetti_2d(_toasts, KONFETTI_TEILE, breite)
	_maybe_claim_set_reward(str(def.get("page", "")))
	sticker_celebrated.emit(def)


## REST-1: Erfolgs-Feier — Toast (Name + Münzen aus dem Katalog), Ton und
## Konfetti auf derselben obersten Layer wie die Sticker.
func _celebrate_achievement(def: Dictionary) -> void:
	var id := str(def.get("id", ""))
	var ach_name := I18nService.t("achievements.defs.%s.name" % id)
	_toasts.show_toast(
		I18nService.t(
			"achievements.unlock_toast", {"name": ach_name, "coins": int(def.get("coins", 0))}
		)
	)
	AudioDirector.try_play(self, "ui_sticker")
	var breite := 640.0
	var viewport := get_viewport()
	if viewport != null:
		breite = viewport.get_visible_rect().size.x
	RewardFx.konfetti_2d(_toasts, KONFETTI_TEILE, breite)
	achievement_celebrated.emit(def)


## REST-1: Tagesbonus-Popup anbieten, wenn heute noch nichts abgeholt wurde
## (should_offer prüft Onboarding + lastClaimDay). Idempotent — nie zwei
## Popups; „Später“ lässt den Bonus bis Mitternacht abholbar.
func _maybe_offer_daily_bonus() -> void:
	if _gs == null or _layer == null:
		return
	if _daily_popup != null and is_instance_valid(_daily_popup):
		return
	if not DailyBonusPopup.should_offer(_gs, _local_day()):
		return
	var popup := DailyBonusPopup.new()
	popup.name = "DailyBonusPopup"
	popup.theme = ThemeService.theme()
	popup.setup(_gs)
	popup.claimed.connect(_on_daily_bonus_claimed)
	_layer.add_child(popup)
	_daily_popup = popup


## Onboarding fertig → der erste Tagesbonus darf sofort kommen (Web-Fluss).
func _on_gs_slice_changed(slice_id: String, _data: Variant) -> void:
	if slice_id == "onboarding":
		_maybe_offer_daily_bonus()


func _on_daily_bonus_claimed(reward: Dictionary) -> void:
	var coins := int(reward.get("coins", 0))
	var food_id := str(reward.get("food_id", ""))
	if food_id.is_empty():
		_toasts.show_toast(I18nService.t("daily.claimed_toast", {"coins": coins}))
	else:
		var snack := I18nService.t("rewards.food.%s" % food_id)
		_toasts.show_toast(
			I18nService.t("daily.claimed_snack_toast", {"coins": coins, "snack": snack})
		)
	var breite := 640.0
	var viewport := get_viewport()
	if viewport != null:
		breite = viewport.get_visible_rect().size.x
	RewardFx.konfetti_2d(_toasts, KONFETTI_TEILE, breite)
	daily_bonus_claimed.emit(reward)


func _local_day() -> String:
	if _gs != null and "clock" in _gs:
		return str(_gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Set-komplett-Belohnung auch außerhalb des Albums claimen (additiv,
## idempotent — der Album-Pfad prüft dieselbe setRewards-Map).
func _maybe_claim_set_reward(page_id: String) -> void:
	if _gs == null or page_id.is_empty() or _set_reward_claimed(page_id):
		return
	var progress := StickerUnlocks.page_progress(_gs.state(), StickerCatalog.all(), page_id)
	if int(progress["total"]) <= 0 or int(progress["unlocked"]) < int(progress["total"]):
		return
	var now_ms := _now_ms()
	_gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("stickers") is Dictionary):
				state["stickers"] = {"unlocked": {}, "seen": {}}
			var stickers: Dictionary = state["stickers"]
			if not (stickers.get("setRewards") is Dictionary):
				stickers["setRewards"] = {}
			stickers["setRewards"][page_id] = now_ms
			if state.get("economy") is Dictionary:
				Economy.award(state["economy"], SET_REWARD_COINS, "stickerSet")
	)
	_gs.notify_slice_changed("stickers")
	var title := page_id
	for page: Variant in StickerCatalog.pages():
		if page is Dictionary and str(page.get("id", "")) == page_id:
			title = str(page.get("title_de", page_id))
			break
	_toasts.show_toast(
		I18nService.t("album.set_belohnung", {"title": title, "coins": SET_REWARD_COINS})
	)


func _set_reward_claimed(page_id: String) -> bool:
	var rewards: Variant = _gs.get_value("stickers.setRewards", {})
	return rewards is Dictionary and (rewards as Dictionary).has(page_id)


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
