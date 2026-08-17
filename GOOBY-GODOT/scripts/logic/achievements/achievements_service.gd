class_name AchievementsService
extends Node
## Erfolgs-Unlock-Service (REST-1): signal-basierte Auswertung der 44
## Katalog-Erfolge gegen den W1d-GameState — exakt das StickerUnlocks-Muster
## (kein Polling; hört auf `slice_changed`/`stats_changed`/`level_changed`/
## `coins_changed` und re-evaluiert nur dann). Neu erfüllte Erfolge landen
## einmalig in `achievements.unlocked{id: ms}` (Web-verbatim, additiv — kein
## Version-Bump) und zahlen ihre Münz-Belohnung im SELBEN update() über den
## EINEN Geld-Pfad (Economy.award, reason "achievement") — danach feuert
## `achievement_unlocked(def)` pro Erfolg; der RewardHub feiert (Toast +
## Ton + Konfetti).
##
## neverSick-Buchführung: der Service latcht jede gesehene "sick"-Phase in
## counters.sickEver (Web: track('sickEver') beim Übergang) — so bleibt die
## Bedingung "Level 10 ohne je krank" semantisch korrekt.

signal achievement_unlocked(def: Dictionary)

const Economy := preload("res://scripts/logic/economy.gd")

var _gs: Object = null
var _catalog: Array = []
## Re-Entranz-Bremse: die Belohnung feuert coins_changed → nicht nochmal
## hineinevaluieren, die Schleife unten claimt ohnehin alles Fällige.
var _evaluating := false


## Service anbinden: initiale Auswertung + Signal-Abos. `catalog` leer =
## AchievementsCatalog.all() (Registry/Pack).
func attach(gs: Object, catalog: Array = []) -> void:
	_gs = gs
	_catalog = catalog if not catalog.is_empty() else AchievementsCatalog.all()
	if _gs is Node:
		var node := _gs as Node
		if node.has_signal("slice_changed"):
			node.slice_changed.connect(_on_slice_changed)
		if node.has_signal("stats_changed"):
			node.stats_changed.connect(func(_stats: Dictionary) -> void: evaluate_now())
		if node.has_signal("level_changed"):
			node.level_changed.connect(func(_level: int, _ratio: float) -> void: evaluate_now())
		if node.has_signal("coins_changed"):
			node.coins_changed.connect(func(_coins: int) -> void: evaluate_now())
	evaluate_now()


func catalog() -> Array:
	return _catalog


## Auswertung anstoßen (Signale rufen das; Tests dürfen direkt rufen).
func evaluate_now() -> void:
	if _gs == null or _evaluating:
		return
	_evaluating = true
	_latch_sick_ever()
	var fresh := AchievementsEngine.newly_met(_catalog, _gs.state())
	if not fresh.is_empty():
		var now_ms := _now_ms()
		_gs.update(
			func(state: Dictionary) -> void:
				if not (state.get("achievements") is Dictionary):
					state["achievements"] = {"unlocked": {}, "counters": {}}
				var slice: Dictionary = state["achievements"]
				if not (slice.get("unlocked") is Dictionary):
					slice["unlocked"] = {}
				for def: Dictionary in fresh:
					slice["unlocked"][str(def["id"])] = now_ms
					if state.get("economy") is Dictionary:
						Economy.award(state["economy"], int(def.get("coins", 0)), "achievement")
		)
		for def: Dictionary in fresh:
			achievement_unlocked.emit(def)
	_evaluating = false
	# Belohnungen können Folge-Erfolge erfüllen (z. B. coins1000) — einmal
	# nachfassen; ohne Neuzugang bricht die Rekursion sofort ab.
	if not fresh.is_empty():
		evaluate_now()


## Web track('sickEver'): einmalige Latch, sobald Gooby krank IST — ohne
## eigenes Verlaufs-Log genügt der beobachtete Zustand (jede sick-Phase
## läuft durch stats_changed/slice_changed hier vorbei).
func _latch_sick_ever() -> void:
	var health := str(_gs.get_value("gooby.health.state", "healthy"))
	if health != "sick":
		return
	if int(_gs.get_value("achievements.counters.sickEver", 0)) > 0:
		return
	_gs.update(
		func(state: Dictionary) -> void:
			if state.get("achievements") is Dictionary:
				var slice: Dictionary = state["achievements"]
				if not (slice.get("counters") is Dictionary):
					slice["counters"] = {}
				slice["counters"]["sickEver"] = 1
	)


func _on_slice_changed(_slice_id: String, _data: Variant) -> void:
	evaluate_now()


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
