extends SceneTree
## 3D-B-Hilfssonde (KEIN Test): meldet die Roh-AABBs der Kenney-Modelle, die
## die fünf 3D-Spiele benutzen. Damit lassen sich Einpass-Fehler (falsche
## Achse, falscher Ursprung) erkennen, ohne zu raten.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")

const PATHS: Array[String] = [
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-straight.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-corner-large.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-corner-small.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-looping.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/track-narrow-curve.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/gate-finish.glb",
	"res://assets/minigames/toy_racer/toy-car-kit/item-box.glb",
	"res://assets/minigames/toy_racer/car-kit/race.glb",
	"res://assets/minigames/toy_racer/car-kit/taxi.glb",
	"res://assets/minigames/harbor_hopper/watercraft-kit/boat-fishing-small.glb",
]


func _init() -> void:
	for path in PATHS:
		print("%s → %s" % [path.get_file(), Models.aabb(path)])
	quit(0)
