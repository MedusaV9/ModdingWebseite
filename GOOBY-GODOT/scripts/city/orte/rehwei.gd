class_name OrtRehwei
extends OrtScene
## REHWEI — Lebensmittelladen (Doc E §2.3): Frau Rehwald an der Kasse,
## Obst-/Gemüse-Kisten (KayKit), Sortiment aus rehwei_sortiment.json.

const INNEN := "res://assets/city/innen"


func _baue_innenraum() -> void:
	# KayKit-Basisgrößen: Counter/Kisten ~2 m, Kühlschrank 2×2,5 m — Skalen
	# klein halten, sonst füllt eine Kiste den halben Raum.
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-0.2, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(-3.6, 0.0, -1.6), 12.0, 0.65)
	_prop("%s/crate_tomatoes.gltf" % INNEN, Vector3(-3.4, 0.0, 0.2), -8.0, 0.65)
	_prop("%s/crate_buns.gltf" % INNEN, Vector3(3.4, 0.0, -1.4), 20.0, 0.65)
	_prop("%s/crate.gltf" % INNEN, Vector3(3.6, 0.0, 0.4), -14.0, 0.65)
	_prop("%s/menu.gltf" % INNEN, Vector3(2.2, 0.0, -3.4), 0.0, 1.6)
	_prop("%s/fridge_A.gltf" % INNEN, Vector3(-5.2, 0.0, -3.2), 0.0, 0.9)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/rehwei.json"


func _sortiment_pfad() -> String:
	return CitySortiment.REHWEI_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F2B5D4"), "emotion": "happy", "pos": Vector3(-0.2, 0.0, -2.2)}
