class_name GobnomSolver
extends RefCounted
## Auto-Solver/Bot für GOB NOM: führt den datengetriebenen Lösungs-Plan
## eines Levels (level.solution.actions, Zeiten in Sekunden) AUSSCHLIESSLICH
## über die öffentliche Aktions-API der puren Sim aus — inkl. der
## player-Angaben, sodass der Lauf auch die Coop-Ownership-Gates beweist
## (verweigerte Aktionen werden gezählt und sind in Tests = 0).
## Jeder grüne Lauf ist damit der maschinelle Lösbarkeits-Beweis des Levels
## (Doc G §5: "Skip-sicher getestet"). Für Ein-Seil-Level existiert
## zusätzlich ein winziger Greedy-Fallback (Seil kappen, sobald das Bonbon
## über dem Mund hängt) — der beweist, dass auch OHNE Plan gelöst wird.

## Sicherheitsdeckel, falls ein Plan nie terminiert (Sekunden Sim-Zeit).
const DEFAULT_TIMEOUT_SEC := 40.0


## Lösungs-Plan des Levels ausführen. Liefert
## {won, outcome, jars, stars, ticks, side_changes, denied, actions_run}.
static func run_solution(level: Dictionary, balance: Dictionary, seed_value := 1) -> Dictionary:
	var state := GobnomLogic.new_run(level, balance, seed_value)
	var actions := _sorted_actions(level)
	var timeout := float(balance.get("limits", {}).get("solver_timeout_sec", DEFAULT_TIMEOUT_SEC))
	var max_ticks := int(timeout * GobnomLogic.TPS)
	var denied := 0
	var actions_run := 0
	var next_action := 0
	while int(state["tick"]) < max_ticks and not GobnomLogic.is_over(state):
		var now := float(state["tick"]) / float(GobnomLogic.TPS)
		while next_action < actions.size() and float(actions[next_action]["t"]) <= now:
			var result := _execute(state, actions[next_action])
			actions_run += 1
			if not bool(result.get("ok", false)):
				denied += 1
			next_action += 1
		GobnomLogic.step(state)
	return _report(state, denied, actions_run)


## Greedy-Fallback ohne Plan: schneidet ALLE Seile, sobald das Bonbon
## (fast) über dem Mund hängt — löst die Gerade-runter-Level beweisbar.
static func run_greedy(level: Dictionary, balance: Dictionary, seed_value := 1) -> Dictionary:
	var state := GobnomLogic.new_run(level, balance, seed_value)
	var max_ticks := int(DEFAULT_TIMEOUT_SEC * GobnomLogic.TPS)
	var mouth := Vector2((state["mouth"] as Dictionary)["pos"])
	while int(state["tick"]) < max_ticks and not GobnomLogic.is_over(state):
		var pos := GobnomLogic.candy_pos(state)
		if absf(pos.x - mouth.x) < 20.0 and pos.y < mouth.y:
			for rope: Dictionary in state["ropes"]:
				if not bool(rope["cut"]):
					GobnomLogic.cut_rope(state, int(rope["id"]))
		GobnomLogic.step(state)
	return _report(state, 0, 0)


static func _sorted_actions(level: Dictionary) -> Array:
	var solution: Dictionary = level.get("solution", {})
	var actions: Array = (solution.get("actions", []) as Array).duplicate(true)
	actions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"])
	)
	return actions


## Eine Plan-Aktion über die öffentliche Sim-API ausführen.
static func _execute(state: Dictionary, action: Dictionary) -> Dictionary:
	var player := str(action.get("player", GobnomLogic.PLAYER_SOLO))
	match str(action.get("do", "")):
		"cut":
			return GobnomLogic.cut_rope(state, int(action.get("rope", 0)), player)
		"pop":
			return GobnomLogic.pop_bubble(state, int(action.get("bubble", 0)), player)
		"puff":
			return GobnomLogic.puff_cushion(state, int(action.get("cushion", 0)), player)
		"fan":
			return GobnomLogic.toggle_fan(state, int(action.get("fan", 0)), player)
		"slide":
			return GobnomLogic.move_anchor(
				state, int(action.get("rope", 0)), float(action.get("to", 0.0)), player
			)
		_:
			return {"ok": false, "reason": "unknown_action"}


static func _report(state: Dictionary, denied: int, actions_run: int) -> Dictionary:
	var jars := int(state["jars_taken"])
	return {
		"won": str(state["outcome"]) == "won",
		"outcome": str(state["outcome"]),
		"jars": jars,
		"stars": GobnomLogic.stars_for(jars),
		"ticks": int(state["tick"]),
		"side_changes": int(state["side_changes"]),
		"denied": denied,
		"actions_run": actions_run,
	}
