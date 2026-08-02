class_name OrtRehwei
extends OrtScene
## REHWEI — Lebensmittelladen (Doc E §2.3): Frau Rehwald an der Kasse,
## Obst-/Gemüse-Kisten (KayKit), Sortiment aus rehwei_sortiment.json.
## G7-P55 „Läden lebendig“: dazu Ambient-Kunden (OrtLeben), Kassen-
## Verhalten (KassenNpc, piept bei jedem Kauf), Tür-Glöckchen, leises
## Marktgemurmel und dichter gefüllte Regale.

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
	# G7-P55 Regal-Deko-Check: der Laden wirkte leer — Käse-Kiste, zweite
	# Kühltheke und Vorratsgläser AUF dem Tresen füllen die Lücken.
	_prop("%s/crate_cheese.gltf" % INNEN, Vector3(-3.7, 0.0, 1.8), 24.0, 0.65)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(3.2, 0.0, 1.9), -26.0, 0.65)
	_prop("%s/fridge_A.gltf" % INNEN, Vector3(-5.2, 0.0, -0.9), 0.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-0.2, 0.85, -0.6), 15.0, 0.5)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-0.15, 0.85, -1.8), -30.0, 0.5)


## W13B (Doc F §3.2): REHWEI führt neben den Lebensmitteln auch die
## Geschichten-Bücher — gleiche HaendlerSheet-UI, plus Bücher-Abschnitt
## (gekaufte Bücher stehen ausgegraut „im Regal“). W15/CROPS: dazu der
## Saatgut-Abschnitt für die vier neuen Garten-Crops (Muster Bücher).
func oeffne_laden() -> void:
	var inhalt := HaendlerSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = CitySortiment.laden(_sortiment_pfad())
	inhalt.saatgut = CitySortiment.saatgut(_sortiment_pfad())
	inhalt.buecher = CitySortiment.buecher(_sortiment_pfad())
	# G7-P55: jeder Kauf piept an der Kasse — Frau Rehwald kassiert sichtbar.
	inhalt.gekauft.connect(_on_kunde_zahlt)
	zeige_sheet(I18nService.t("city.laden.titel"), inhalt)


func _on_kunde_zahlt(_ware_id: String) -> void:
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/rehwei.json"


func _sortiment_pfad() -> String:
	return CitySortiment.REHWEI_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F2B5D4"), "emotion": "happy", "pos": Vector3(-0.2, 0.0, -2.2)}


## G7-P55: Ambient-Leben — 3 Kunden schlendern zwischen Kisten und
## Kühltheke, Frau Rehwald bekommt das Kassen-Verhalten, dazu Glöckchen
## beim Betreten und leises Marktgemurmel.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-3.4, 0.0, -0.6),
			Vector3(-1.6, 0.0, 1.2),
			Vector3(3.0, 0.0, -0.5),
			Vector3(1.4, 0.0, 1.6),
			Vector3(-4.8, 0.0, -2.0),
		],
		"sprueche": "laden",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
	}
