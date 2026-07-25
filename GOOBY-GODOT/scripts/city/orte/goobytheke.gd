class_name OrtGoobytheke
extends OrtScene
## GOOBYTHEKE — Apotheke (Doc E §2.3/§2.4): Hilde am Tresen, Gläser-Regal.
## Gooby-Tropfen NUR mit Rezept-Flag (der Dialog löst das Rezept ein, das
## Laden-Sortiment verlangt es für den Direktkauf).

const INNEN := "res://assets/city/innen"


func _baue_innenraum() -> void:
	# Basisgrößen: Counter 2 m, Gläser 0,5×0,75 m — Skalen klein (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.2, 0.0, -3.2), 0.0, 1.6)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-2.2, 0.0, -3.4), 12.0, 1.3)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(3.4, 0.0, -3.0), 0.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-4.8, 0.0, -2.6), 25.0, 1.6)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/goobytheke.json"


func _sortiment_pfad() -> String:
	return CitySortiment.GOOBYTHEKE_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "neutral", "pos": Vector3(0.0, 0.0, -2.2)}
