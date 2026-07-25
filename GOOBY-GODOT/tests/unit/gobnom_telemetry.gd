extends SceneTree
## GOB-NOM-Lösbarkeits-Telemetrie (KEIN Test — kein test_-Präfix): führt den
## Auto-Solver (GobnomSolver) über alle 15 Kampagnen- + 10 Coop-Level und
## druckt die Beweis-Tabelle (Sieg, Gläser, Ticks, Seitenwechsel, verweigerte
## Aktionen). Grundlage jedes Level-Tuning-Passes (Doc G §5.3/§5.4). Aufruf:
##   godot --headless --path . --script res://tests/unit/gobnom_telemetry.gd
## Env-Schalter:
##   GOBNOM_ONLY  ("campaign:3,coop:5" = nur diese Level)
##   GOBNOM_TRACE ("campaign:3" = Trajektorie + Events des Levels dumpen)
##   GOBNOM_SEED  (Default 1)

const TRACE_EVERY_TICKS := 6


func _init() -> void:
	var seed_value := 1
	var env_seed := OS.get_environment("GOBNOM_SEED")
	if env_seed.is_valid_int():
		seed_value = int(env_seed)
	var only := _parse_filter(OS.get_environment("GOBNOM_ONLY"))
	var trace := _parse_filter(OS.get_environment("GOBNOM_TRACE"))
	_run(seed_value, only, trace)
	quit(0)


func _run(seed_value: int, only: Array, trace: Array) -> void:
	var balance := GobnomData.load_balance(null)
	var tracks := {"campaign": GobnomData.load_campaign(), "coop": GobnomData.load_coop()}
	print("GOB-NOM-Solver-Report (Seed %d)" % seed_value)
	print("| Level | Sieg | Gläser | Ticks | Seitenwechsel | verweigert |")
	print("|---|---|---|---|---|---|")
	var wins := 0
	var total := 0
	for track: String in ["campaign", "coop"]:
		for level: Dictionary in tracks[track]:
			var id := int(level["id"])
			if not only.is_empty() and not only.has([track, id]):
				continue
			total += 1
			if trace.has([track, id]):
				_trace_level(level, balance, seed_value)
			var result := GobnomSolver.run_solution(level, balance, seed_value)
			if bool(result["won"]):
				wins += 1
			var tag := "L%02d" % id if track == "campaign" else "CN%d" % id
			print(
				(
					"| %s | %s | %d/3 | %d | %d | %d |"
					% [
						tag,
						"JA" if result["won"] else "NEIN (%s)" % result["outcome"],
						int(result["jars"]),
						int(result["ticks"]),
						int(result["side_changes"]),
						int(result["denied"]),
					]
				)
			)
	print("Lösbar: %d/%d" % [wins, total])


## Trajektorie eines Levels dumpen (fürs Platzieren von Gläsern/Elementen).
func _trace_level(level: Dictionary, balance: Dictionary, seed_value: int) -> void:
	var state := GobnomLogic.new_run(level, balance, seed_value)
	var actions: Array = (level.get("solution", {}).get("actions", []) as Array).duplicate(true)
	actions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"])
	)
	var next_action := 0
	print("-- TRACE %s L%d --" % [str(level.get("kind", "?")), int(level["id"])])
	var max_ticks := int(40.0 * GobnomLogic.TPS)
	while int(state["tick"]) < max_ticks and not GobnomLogic.is_over(state):
		var now := float(state["tick"]) / float(GobnomLogic.TPS)
		while next_action < actions.size() and float(actions[next_action]["t"]) <= now:
			var action: Dictionary = actions[next_action]
			var player := str(action.get("player", "solo"))
			var result: Dictionary = {}
			match str(action.get("do", "")):
				"cut":
					result = GobnomLogic.cut_rope(state, int(action.get("rope", 0)), player)
				"pop":
					result = GobnomLogic.pop_bubble(state, int(action.get("bubble", 0)), player)
				"puff":
					result = GobnomLogic.puff_cushion(state, int(action.get("cushion", 0)), player)
				"fan":
					result = GobnomLogic.toggle_fan(state, int(action.get("fan", 0)), player)
				"slide":
					result = GobnomLogic.move_anchor(
						state, int(action.get("rope", 0)), float(action.get("to", 0.0)), player
					)
			print("  t=%.2f AKTION %s → %s" % [now, str(action), str(result)])
			next_action += 1
		var events := GobnomLogic.step(state)
		for event: Dictionary in events:
			print("  t=%.2f EVENT %s" % [now, str(event)])
		if int(state["tick"]) % TRACE_EVERY_TICKS == 0:
			var pos := GobnomLogic.candy_pos(state)
			var vel := GobnomLogic.candy_velocity(state)
			print(
				(
					"  t=%.2f pos=(%.0f,%.0f) vel=(%.0f,%.0f)%s"
					% [
						now,
						pos.x,
						pos.y,
						vel.x,
						vel.y,
						" [Blase]" if bool(state["in_bubble"]) else "",
					]
				)
			)
	print("-- ENDE outcome=%s Gläser=%d --" % [str(state["outcome"]), int(state["jars_taken"])])


## "campaign:3,coop:5" → [["campaign",3],["coop",5]].
func _parse_filter(raw: String) -> Array:
	var out: Array = []
	for part in raw.split(",", false):
		var bits := part.strip_edges().split(":")
		if bits.size() == 2 and bits[1].is_valid_int():
			out.append([bits[0], int(bits[1])])
	return out
