class_name WhatsNextAdvisor
extends RefCounted
## „Was nun?“-Berater (REST-2, roter Faden): schlägt aus Spielstand + Quest-
## Brett den EINEN nächsten sinnvollen Schritt vor. PURE Static — Tests
## reichen State/Brett/Kontext direkt herein.
##
## Prioritäten (erste Übereinstimmung gewinnt):
##   1 abholbereite Quest-Belohnung
##   2 offene Tagesquest (die mit dem meisten Fortschritt zuerst)
##   3 dringende Pflege (Stat unter der Alarm-Schwelle)
##   4 Ranch freigeschaltet (Level >= Freischalt-Level)
##   5 Level-Ziel (nächstes Level als Fernziel, Arcade als Weg)
##   6 sanfter Default (Arcade-Einladung)
##
## Ergebnis: {"id", "text_key", "args", "aktion"} — aktion "quests" öffnet
## das Quest-Panel, "" ist nur Text. {} = kein Vorschlag (Stille ist okay).

## Unter diesem Stat-Wert wird Pflege vorgeschlagen (HUD-Alarm ist 25 —
## der Hinweis kommt bewusst etwas früher, bevor die Kapsel pulsiert).
const PFLEGE_SCHWELLE := 35.0


static func suggest(state: Dictionary, board: Array, ctx: Dictionary) -> Dictionary:
	if int(ctx.get("claimable", 0)) > 0:
		return {
			"id": "abholen",
			"text_key": "quests.wasnun.abholen",
			"args": {},
			"aktion": "quests",
		}
	var open_quest := _best_open_quest(board)
	if not open_quest.is_empty():
		return {
			"id": "quest_%s" % str(open_quest.get("id", "")),
			"text_key": "quests.wasnun.quest",
			"args": {"titel_key": DailyQuestCatalog.title_key(open_quest)},
			"aktion": "quests",
		}
	var pflege := _pflege_vorschlag(state)
	if not pflege.is_empty():
		return pflege
	var level := _level_of(state)
	var ranch_level := maxi(1, int(ctx.get("ranch_level", 20)))
	if level >= ranch_level:
		return {"id": "ranch", "text_key": "quests.wasnun.ranch", "args": {}, "aktion": ""}
	if bool(ctx.get("all_claimed", false)):
		return {
			"id": "level",
			"text_key": "quests.wasnun.level",
			"args": {"level": level + 1},
			"aktion": "",
		}
	return {"id": "arcade", "text_key": "quests.wasnun.arcade", "args": {}, "aktion": ""}


## Offene (unclaimed, unfertige) Quest mit dem meisten relativen Fortschritt —
## „fast geschafft“ motiviert mehr als „fang neu an“.
static func _best_open_quest(board: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := -1.0
	for row: Variant in board:
		if not (row is Dictionary):
			continue
		if bool(row.get("claimed", false)) or bool(row.get("complete", false)):
			continue
		var target := maxi(1, int(row.get("target", 1)))
		var ratio := float(int(row.get("progress", 0))) / float(target)
		if ratio > best_ratio:
			best_ratio = ratio
			best = row.get("def", {})
	return best


static func _pflege_vorschlag(state: Dictionary) -> Dictionary:
	var stats: Variant = state.get("gooby", {}).get("stats", {})
	if not (stats is Dictionary):
		return {}
	var checks := [
		["hunger", "quests.wasnun.pflege_hunger"],
		["hygiene", "quests.wasnun.pflege_hygiene"],
		["energy", "quests.wasnun.pflege_energie"],
	]
	var worst_key := ""
	var worst_text := ""
	var worst := PFLEGE_SCHWELLE
	for check: Array in checks:
		var value := float(stats.get(check[0], 100.0))
		if value < worst:
			worst = value
			worst_key = str(check[0])
			worst_text = str(check[1])
	if worst_key.is_empty():
		return {}
	return {"id": "pflege_%s" % worst_key, "text_key": worst_text, "args": {}, "aktion": ""}


static func _level_of(state: Dictionary) -> int:
	var prog: Variant = state.get("progression", {})
	if not (prog is Dictionary):
		return 1
	return maxi(1, int(float(prog.get("level", 1))))
