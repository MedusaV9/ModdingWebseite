extends "res://tools/capture/clips/_mg_base.gd"
## Clip: GvZ (Tower-Defense) — Level 5 (5 Bahnen, 5 Turmarten). Für einen
## actionreichen 12-s-Ausschnitt wird die Verteidigung direkt über die
## Spiel-Logik aufgebaut, die erste Welle vorgezogen und der Spawn-Plan
## verdichtet; Nutella-Drops sammelt der Treiber wie ein Spieler per Tap.

var _next_act := 0.0


func _setup() -> void:
	game_id = "gvz"
	duration = 12.0
	seed_value = 2024
	super._setup()


func _on_play_start() -> void:
	var g := game()
	if str(g.phase) == "select":
		g.open_level(5)
	var state: Dictionary = g.state
	if state.is_empty():
		return
	state["nutella"] = 5000
	var aufstellung: Array = [
		["nutella_sammler", 0],
		["moehrenschuetze", 1],
		["moehrenschuetze", 2],
		["dicker_bert", 3],
	]
	for lane: Variant in state["lanes"]:
		for setup: Array in aufstellung:
			GvzLogic.place_tower(state, str(setup[0]), int(lane), int(setup[1]))
			state["cooldowns"] = {}
	state["nutella"] = 350
	# Welle vorziehen (2 s statt 32 s) und verdichten (Zombie ~alle 2-3 s).
	var plan: Array = state["spawn_plan"]
	if not plan.is_empty():
		var erster := int(plan[0]["tick"])
		for entry: Dictionary in plan:
			entry["tick"] = erster + int((int(entry["tick"]) - erster) * 0.35)
		state["tick"] = maxi(int(state["tick"]), erster - 40)


func _drive(_delta: float) -> void:
	var g := game()
	if g == null or str(g.phase) != "battle" or g.state.is_empty() or t < _next_act:
		return
	var drops: Array = g.state.get("drops", [])
	if not drops.is_empty():
		var d: Dictionary = drops[0]
		tap(to_window(g._cell_center(int(d["lane"]), int(d["col"]))))
		_next_act = t + 0.5
