class_name OrtGoobytheke
extends OrtScene
## GOOBYTHEKE — Apotheke (Doc E §2.3/§2.4): Hilde am Tresen, Gläser-Regal.
## Gooby-Tropfen NUR mit Rezept-Flag (der Dialog löst das Rezept ein, das
## Laden-Sortiment verlangt es für den Direktkauf).
## G8-P1 „Jeder Ort lebt“ (PT2-B4): Wartebank mit Taschentuch-Gästen,
## stöbernde Kunden, Hilde bekommt das Tresen-Verhalten (KassenNpc) und
## der Ort seine Momente — Niesen samt „Gute Besserung!“ und Tiegel-Plopp.

const INNEN := "res://assets/city/innen"

## Wartebank-Kiste (Muster Tierarzt-Bänkchen): 2 m Basis × 0,55 = 1,1 m
## breit, Deckel bei 0,8 × 0,55 = 0,44 m — darauf sitzen die Gäste.
const WARTEBANK_POS := Vector3(4.4, 0.0, 0.2)
const WARTEBANK_SITZ_Y := 0.44


func _baue_innenraum() -> void:
	# Basisgrößen: Counter 2 m, Gläser 0,5×0,75 m — Skalen klein (s. rehwei.gd).
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(0.0, 0.0, -1.2), 90.0, 0.9)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-3.2, 0.0, -3.2), 0.0, 1.6)
	_prop("%s/jar_A_large.gltf" % INNEN, Vector3(-2.2, 0.0, -3.4), 12.0, 1.3)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(3.4, 0.0, -3.0), 0.0, 0.9)
	_prop("%s/menu.gltf" % INNEN, Vector3(-4.8, 0.0, -2.6), 25.0, 1.6)
	# G8-P1 Wartebank rechts an der Wand — die OrtLeben-Sitzer nehmen
	# darauf Platz (Sitzhöhe = Kistendeckel, s. Konstanten).
	_prop("%s/crate.gltf" % INNEN, WARTEBANK_POS, 8.0, 0.55)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/goobytheke.json"


func _sortiment_pfad() -> String:
	return CitySortiment.GOOBYTHEKE_PFAD


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "neutral", "pos": Vector3(0.0, 0.0, -2.2)}


## G8-P1: Standard-Laden-Sheet, aber jeder Kauf piept an Hildes Tresen
## (Muster orte/rehwei.gd::_on_kunde_zahlt).
func oeffne_laden() -> void:
	var inhalt := HaendlerSheet.new()
	inhalt.gs = game_state()
	inhalt.waren = CitySortiment.laden(_sortiment_pfad())
	inhalt.gekauft.connect(_on_kunde_zahlt)
	zeige_sheet(I18nService.t("city.laden.titel"), inhalt)


func _on_kunde_zahlt(_ware_id: String) -> void:
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()


## G8-P1: Apotheken-Leben — zwei stöbernde Kunden zwischen Tiegeln und
## Regal, zwei Wartebank-Gäste (einer mit Taschentuch), Hilde tippt am
## Tresen. Momente: Niesen + „Gute Besserung!“ (pet_squish@1,55 = das
## Tierarzt-Nies-Geräusch) und klimpernde Salben-Tiegel. Gemurmel bleibt
## aus — eine Apotheke ist leise, die Momente tragen den Klang.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 2,
		"punkte":
		[
			Vector3(-3.2, 0.0, -2.0),
			Vector3(-1.8, 0.0, 1.0),
			Vector3(2.2, 0.0, -2.2),
			Vector3(2.6, 0.0, 0.9),
		],
		"sprueche": "goobytheke",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": false,
		"tuer_glocke": true,
		"kasse": true,
		"sitze":
		[
			{
				"pos": Vector3(4.15, WARTEBANK_SITZ_Y, 0.4),
				"requisit": "taschentuch",
				"blick": Vector3(0.0, 0.0, -1.2),
			},
			{"pos": Vector3(4.7, WARTEBANK_SITZ_Y, 0.05), "blick": Vector3(0.0, 0.0, -1.2)},
		],
		"momente":
		[
			{
				"alle_s": 19.0,
				"versatz_s": 6.0,
				"sound": "pet_squish",
				"pitch": 1.55,
				"clip": "hop",
				"sprueche": "goobytheke_niesen",
			},
			{
				"alle_s": 27.0,
				"versatz_s": 16.0,
				"sound": "tuer_plopp",
				"pitch": 1.35,
				"clip": "idle_lookaround",
				"sprueche": "goobytheke_tiegel",
			},
		],
	}
