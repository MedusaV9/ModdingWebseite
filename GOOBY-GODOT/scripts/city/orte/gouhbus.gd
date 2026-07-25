class_name OrtGouhbus
extends OrtScene
## Dr.Dr.Professor.Dr.Dr.GOOUHBUS — Arztpraxis (Doc E §2.4): Dialogbaum mit
## drei Brillen, Käsebrot von 1987 und Rezept-Ausstellung (city-Flag
## `rezept_tropfen`). Kein Laden — nur Dialog.

const INNEN := "res://assets/city/innen"


func _baue_innenraum() -> void:
	# Basisgrößen: Tisch 3 m Ø, Counter 2 m — kleine Skalen (s. rehwei.gd).
	_prop("%s/table_round_A.gltf" % INNEN, Vector3(2.6, 0.0, -1.8), 0.0, 0.6)
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-3.6, 0.0, -3.0), 0.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-1.6, 0.0, -3.5), 0.0, 1.8)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.4, 0.9, -2.8), 0.0, 1.2)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/gouhbus.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#EDE6D6"), "emotion": "neutral", "pos": Vector3(0.4, 0.0, -2.0)}
