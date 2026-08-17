class_name OrtGouhbus
extends OrtScene
## Dr.Dr.Professor.Dr.Dr.GOOUHBUS — Arztpraxis (Doc E §2.4): Dialogbaum mit
## drei Brillen, Käsebrot von 1987 und Rezept-Ausstellung (city-Flag
## `rezept_tropfen`). Kein Laden — nur Dialog.
## J3 „Läden lebendig 2“: Wartezimmer-Leben (2 Patienten tigern herum) +
## CC0-Wartebänke und der Praxis-Laptop auf dem Counter.

const INNEN := "res://assets/city/innen"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_BANK := Vector2(0.4, 0.2)
const GRUND_LAPTOP := Vector2(0.264, 0.24)

## Wartebänke in Praxis-Creme (beruhigend wie das Käsebrot von 1987).
const TINT_BANK := Color("#EFE3C4")


func _baue_innenraum() -> void:
	# Basisgrößen: Tisch 3 m Ø, Counter 2 m — kleine Skalen (s. rehwei.gd).
	_prop("%s/table_round_A.gltf" % INNEN, Vector3(2.6, 0.0, -1.8), 0.0, 0.6)
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-3.6, 0.0, -3.0), 0.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-1.6, 0.0, -3.5), 0.0, 1.8)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.4, 0.9, -2.8), 0.0, 1.2)
	# J3/CC0: Wartebank-Paar an der rechten Wand (Blick in den Raum) +
	# Praxis-Laptop auf der Counter-Platte (~0,9 m, s. Glas darüber).
	for z: float in [-1.2, -2.4]:
		var bank := _cc0(
			"%s/bench_cushion.glb" % CC0_MOEBEL, Vector3(5.4, 0.0, z), 90.0, 2.0, GRUND_BANK
		)
		OrtRequisiten.tinte(bank, TINT_BANK, 0.4)
	_cc0("%s/laptop.glb" % CC0_MOEBEL, Vector3(-4.3, 0.9, -3.0), 20.0, 1.5, GRUND_LAPTOP)


## J3: Ambient-Leben — 2 Wartende (die Praxis hat keine Kasse, bezahlt
## wird im Dialog beim Herrn Professor).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(3.8, 0.0, 0.6),
			Vector3(1.4, 0.0, 1.4),
			Vector3(5.2, 0.0, 0.0),
			Vector3(-0.8, 0.0, 0.8),
		],
		"sprueche": "praxis",
		"blick": Vector3(0.4, 0.0, -4.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": false,
	}


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/gouhbus.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#EDE6D6"), "emotion": "neutral", "pos": Vector3(0.4, 0.0, -2.0)}
