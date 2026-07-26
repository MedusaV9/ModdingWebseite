class_name RecapService
extends Node
## Recap-Service (FIX-4) — der pendingLevel-Handshake aus dem Web (§B5.2):
## Level-Änderungen queuen den NIEDRIGSTEN offenen Meilenstein in
## recap.pendingLevel (additiver Key im bestehenden Slice, KEIN Version-
## Bump); das Kino spielt beim nächsten Zuhause-Ankommen. Nur der
## Abspiel-Abschluss (RecapScene → complete_recap) löscht pendingLevel.
##
## Als Autoload "Recap" gedacht (Request in handoffs/project-godot-
## requests.md); alle Kern-APIs sind static und funktionieren ohne Autoload:
##   RecapService.queue_if_milestone(gs, prev, next)
##   RecapService.pending_level(gs)
##   RecapService.open_recap(parent, gs)             # spielt sofort
##   RecapService.replay(parent, gs, history_row)    # §C-SYS2.8 Replay

signal recap_started(level: int)
signal recap_finished(level: int, skipped: bool)

var _last_level := 0
var _active: Node


func _ready() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("level_changed"):
		gs.level_changed.connect(_on_level_changed)
		if gs.has_method("get_value"):
			_last_level = int(gs.get_value("progression.level", 1))
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


# ── Statische Kern-API (headless testbar) ────────────────────────────────────


## Meilenstein-Queue: prev→next überquert einen offenen 5er-Meilenstein →
## pendingLevel setzen (bereits gequeuete NIEDRIGERE bleiben). Gibt den
## gequeueten Meilenstein zurück (0 = nichts fällig).
static func queue_if_milestone(gs: Object, prev_level: int, new_level: int) -> int:
	if gs == null or not gs.has_method("update"):
		return 0
	var slice := RecapEngine.slice_of(_state_of(gs))
	var milestone := RecapEngine.milestone_crossed(
		prev_level, new_level, int(slice["lastRecapLevel"])
	)
	if milestone <= 0:
		return 0
	var pending := int(slice["pendingLevel"])
	var queued := mini(pending, milestone) if pending > 0 else milestone
	gs.update(
		func(s: Dictionary) -> void:
			var recap := RecapEngine.slice_of(s)
			recap["pendingLevel"] = queued
			s["recap"] = recap
	)
	return queued


## Der gequeuete Meilenstein (0 = keiner).
static func pending_level(gs: Object) -> int:
	return int(RecapEngine.slice_of(_state_of(gs))["pendingLevel"])


## Recap-Kino sofort öffnen (level 0 = pending/aktueller Meilenstein).
static func open_recap(parent: Node, gs: Object, level := 0) -> Node:
	var scene := RecapScene.build(gs, level)
	parent.add_child(scene)
	return scene


## History-Zeile erneut ansehen (§C-SYS2.8 — rendert aus row.stats,
## schreibt NICHTS zurück).
static func replay(parent: Node, gs: Object, history_row: Dictionary) -> Node:
	var scene := RecapScene.build(gs, 0, history_row)
	parent.add_child(scene)
	return scene


## History-Zeilen (neueste zuerst) fürs Album/Telefon-UI.
static func history(gs: Object) -> Array:
	var rows: Array = (RecapEngine.slice_of(_state_of(gs))["history"] as Array).duplicate()
	rows.reverse()
	return rows


# ── Autoload-Verhalten ────────────────────────────────────────────────────────


func _on_level_changed(level: int, _xp_ratio: float) -> void:
	var gs := get_node_or_null("/root/GameState")
	var prev := _last_level if _last_level > 0 else maxi(1, level - 1)
	_last_level = level
	queue_if_milestone(gs, prev, level)


func _on_travel_finished(target: StringName) -> void:
	if not String(target).begins_with("home"):
		return
	if _active != null and is_instance_valid(_active):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or pending_level(gs) <= 0:
		return
	_play_pending(gs)


func _play_pending(gs: Object) -> void:
	var level := pending_level(gs)
	var layer := CanvasLayer.new()
	layer.layer = 95
	get_tree().root.add_child(layer)
	var scene: Node = open_recap(layer, gs)
	_active = scene
	recap_started.emit(level)
	scene.finished.connect(
		func(skipped: bool) -> void:
			_active = null
			layer.queue_free()
			recap_finished.emit(level, skipped)
	)


static func _state_of(gs: Object) -> Dictionary:
	if gs != null and gs.has_method("state"):
		var state: Variant = gs.state()
		if state is Dictionary:
			return state
	return {}
