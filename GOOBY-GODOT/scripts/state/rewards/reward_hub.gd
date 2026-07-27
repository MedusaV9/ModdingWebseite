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

signal sticker_celebrated(def: Dictionary)

## Serialisierung der Feiern — nie zwei Konfetti-Bursts übereinander.
const FEIER_ABSTAND_S := 2.6
const KONFETTI_TEILE := 40
const SET_REWARD_COINS := 120
const GROUP := &"reward_hub"

const Economy := preload("res://scripts/logic/economy.gd")

var unlocks: StickerUnlocks

var _gs: Object = null
var _layer: CanvasLayer
var _toasts: ToastLayer
var _queue: Array[Dictionary] = []
var _draining := false


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
	if _gs != null:
		unlocks.attach(_gs)


## Feiert das Album gerade selbst mit? Nein — das Album zeigt nur noch den
## Grid-Refresh, die Feier (Toast+Ton+Konfetti) kommt IMMER von hier.
func _on_sticker_unlocked(def: Dictionary) -> void:
	_queue.append(def)
	if not _draining:
		_drain_queue()


func _drain_queue() -> void:
	_draining = true
	while not _queue.is_empty():
		var def: Dictionary = _queue.pop_front()
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
