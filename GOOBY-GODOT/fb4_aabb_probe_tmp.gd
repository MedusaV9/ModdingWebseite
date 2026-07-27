extends SceneTree
## Wegwerf-Probe (FB4): Roh-AABBs der Fahrzeug-/Requisiten-GLBs ausgeben.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")

const PATHS: Array[String] = [
	"res://assets/minigames/toy_racer/car-kit/race.glb",
	"res://assets/minigames/toy_racer/car-kit/taxi.glb",
	"res://assets/minigames/toy_racer/car-kit/police.glb",
	"res://assets/minigames/toy_racer/car-kit/hatchback-sports.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/gate-finish.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/gate.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/item-cone.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/item-banana.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/item-box.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-straight.glb",
	"res://assets/city/autos/sedan.glb",
	"res://assets/city/autos/taxi.glb",
	"res://assets/city/autos/suv.glb",
	"res://assets/city/autos/van.glb",
	"res://assets/city/strassen/road-straight.glb",
	"res://assets/city/strassen/tile-low.glb",
	"res://assets/city/autos/delivery.glb",
	"res://assets/city/autos/truck.glb",
	"res://assets/city/autos/race.glb",
	"res://assets/city/autos/garbage-truck.glb",
	"res://assets/city/autos/firetruck.glb",
	"res://assets/city/autos/police.glb",
	"res://assets/city/autos/ambulance.glb",
	"res://assets/city/autos/hatchback-sports.glb",
	"res://assets/city/autos/race-future.glb",
	"res://assets/city/autos/tractor.glb",
	"res://assets/city/autos/sedan-sports.glb",
]


func _initialize() -> void:
	for path in PATHS:
		if not ResourceLoader.exists(path):
			print("FEHLT  %s" % path)
			continue
		var box: AABB = Models.aabb(path)
		print(
			(
				"%s  min_y=%.4f  size=%.3f/%.3f/%.3f"
				% [path.get_file(), box.position.y, box.size.x, box.size.y, box.size.z]
			)
		)
	quit(0)
