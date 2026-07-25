extends SceneTree

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Bot := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_bot.gd")


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for mode: String in ["easy", "normal", "hard", "endless"]:
		var out := PackedInt32Array()
		for s in range(1, 6):
			out.append(int(Bot.simulate_autoplay(mode, s)["score"]))
		print(mode, " ", out)
	print("ms=", Time.get_ticks_msec() - t0)
	var r: Dictionary = Bot.simulate_autoplay("normal", 3)
	print("n3 ", r)
	var rng := GoobyRng.new(5)
	var layout: Dictionary = Logic.create_layout(func() -> float: return rng.next())
	for p: Dictionary in layout["platforms"]:
		print("plat %.9f %.9f" % [p["x"], p["y"]])
	for p: Dictionary in layout["fuelPickups"]:
		print("fuel %.9f %.9f" % [p["x"], p["y"]])
	quit()
