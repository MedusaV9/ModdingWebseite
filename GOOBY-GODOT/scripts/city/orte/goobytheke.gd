class_name OrtGoobytheke
extends OrtScene
## GOOBYTHEKE — Apotheke (Doc E §2.3/§2.4): Hilde am Tresen, Gläser-Regal.
## Gooby-Tropfen NUR mit Rezept-Flag (der Dialog löst das Rezept ein, das
## Laden-Sortiment verlangt es für den Direktkauf).
## J3 „Läden lebendig 2“: Ambient-Kundschaft (OrtLeben) + Kassen-Verhalten
## für Hilde, dazu CC0-Medizinschränke und eine Wartebank; Opa Hatschi
## (Stammkunde, 9–11 Uhr) holt seine Kräuterbonbons.

const INNEN := "res://assets/city/innen"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_SCHRANK := Vector2(0.4, 0.25)
const GRUND_BANK := Vector2(0.4, 0.2)

## Apotheken-Palette: Schränke mint, Wartebank warm-creme.
const TINT_SCHRANK := Color("#B7E0CE")
const TINT_BANK := Color("#EFD9A8")


func _baue_innenraum() -> void:
	# Basisgrößen: Counter 2 m, Gläser 0,5×0,75 m — Skalen klein (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.2, 0.0, -3.2), 0.0, 1.6)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-2.2, 0.0, -3.4), 12.0, 1.3)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(3.4, 0.0, -3.0), 0.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-4.8, 0.0, -2.6), 25.0, 1.6)
	# J3/CC0: Medizinschrank-Paar hinter Hilde (Türen zu — Rezeptpflicht!)
	# und eine Wartebank an der linken Seite (Blick in den Raum).
	for x: float in [1.2, 1.95]:
		var schrank := _cc0(
			"%s/bookcase_closed_doors.glb" % CC0_MOEBEL,
			Vector3(x, 0.0, -3.6),
			0.0,
			1.7,
			GRUND_SCHRANK
		)
		OrtRequisiten.tinte(schrank, TINT_SCHRANK, 0.45)
	var bank := _cc0(
		"%s/bench_cushion.glb" % CC0_MOEBEL, Vector3(-5.2, 0.0, -0.9), -90.0, 2.0, GRUND_BANK
	)
	OrtRequisiten.tinte(bank, TINT_BANK, 0.4)


## J3: Ambient-Leben — 2 Kunden schlendern zwischen Tresen und Regalen,
## Hilde bekommt das Kassen-Verhalten (Käufe piepen via OrtScene-Hook).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-3.6, 0.0, -0.6),
			Vector3(-1.4, 0.0, 1.0),
			Vector3(2.4, 0.0, -0.6),
			Vector3(0.6, 0.0, 1.6),
		],
		"sprueche": "apotheke",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": true,
	}


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/goobytheke.json"


func _sortiment_pfad() -> String:
	return CitySortiment.GOOBYTHEKE_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "neutral", "pos": Vector3(0.0, 0.0, -2.2)}
