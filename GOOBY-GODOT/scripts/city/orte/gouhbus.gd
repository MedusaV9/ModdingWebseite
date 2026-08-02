class_name OrtGouhbus
extends OrtScene
## Dr.Dr.Professor.Dr.Dr.GOOUHBUS — Arztpraxis (Doc E §2.4): Dialogbaum mit
## drei Brillen, Käsebrot von 1987 und Rezept-Ausstellung (city-Flag
## `rezept_tropfen`). Kein Laden — nur Dialog.
## G8-P1 „Jeder Ort lebt“ (PT2-B4): Wartezimmer-Leben — zwei Patienten
## tigern durch die Praxis, einer sitzt schniefend am Boden (Taschentuch),
## dazu die Praxis-Momente Brillen-Suche und das legendäre Käsebrot.

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


## G8-P1: Praxis-Leben — zwei Patienten schlurfen ihre Warte-Runden, ein
## dritter sitzt schniefend am Boden (Muster Tierarzt-Patient). KEIN
## Gemurmel (Praxis-Stille), Glöckchen an der Tür. Momente: die Brillen-
## Suche (licht_schalter = Klick-Klick auf der Stirn) und das Käsebrot
## von 1987 (nom_nom TIEF + angewidertes Kopfschütteln).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-2.6, 0.0, -1.2),
			Vector3(-0.9, 0.0, 0.8),
			Vector3(1.4, 0.0, 1.5),
			Vector3(3.6, 0.0, 0.4),
		],
		"sprueche": "gouhbus",
		"blick": Vector3(0.4, 0.0, -2.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": false,
		"sitze":
		[
			{
				"pos": Vector3(-1.8, 0.0, -0.75),
				"requisit": "taschentuch",
				"blick": Vector3(0.4, 0.0, -2.0),
			},
		],
		"momente":
		[
			{
				"alle_s": 21.0,
				"versatz_s": 7.0,
				"sound": "licht_schalter",
				"pitch": 1.2,
				"clip": "idle_lookaround",
				"sprueche": "gouhbus_brille",
			},
			{
				"alle_s": 31.0,
				"versatz_s": 18.0,
				"sound": "nom_nom",
				"pitch": 0.8,
				"clip": "refuse",
				"sprueche": "gouhbus_kaesebrot",
			},
		],
	}
