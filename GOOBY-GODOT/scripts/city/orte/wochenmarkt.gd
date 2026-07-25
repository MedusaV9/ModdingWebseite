class_name OrtWochenmarkt
extends OrtScene
## Wochenmarkt (Doc D §6.3, USER §D51): samstags 8–14 Uhr (Öffnungsregel in
## city_map.json, geprüft von OrtKatalog). Kein Innenraum, sondern ein Platz
## unter freiem Himmel — Stände, Kisten, Info-Schild. Verkauft wird die eigene
## ERNTE mit Preis-Elastizität (MarktPreise): jede heute verkaufte Einheit
## drückt den Preis, am nächsten Markttag ist er wieder voll.

const INNEN := "res://assets/city/innen"
const ESSEN := "res://assets/city/essen"
const MOEBEL := "res://assets/furniture"


## Marktplatz statt Ladenraum: keine Rückwand, Wiese, heller Himmel.
func _ist_draussen() -> bool:
	return true


func _baue_innenraum() -> void:
	_prop("%s/table.glb" % MOEBEL, Vector3(-3.4, 0.0, -1.8), 0.0, 1.2)
	_prop("%s/table.glb" % MOEBEL, Vector3(3.4, 0.0, -1.8), 0.0, 1.2)
	_prop("%s/crate_carrots.gltf" % INNEN, Vector3(-4.2, 0.0, -0.4), 14.0, 0.7)
	_prop("%s/crate_tomatoes.gltf" % INNEN, Vector3(-2.6, 0.0, -0.4), -10.0, 0.7)
	_prop("%s/crate_buns.gltf" % INNEN, Vector3(2.6, 0.0, -0.4), 8.0, 0.7)
	_prop("%s/crate.gltf" % INNEN, Vector3(4.2, 0.0, -0.4), -16.0, 0.7)
	_prop("%s/menu.gltf" % INNEN, Vector3(0.0, 0.0, -3.6), 0.0, 1.8)
	_prop("%s/garten/bench.glb" % MOEBEL, Vector3(5.6, 0.0, 1.2), -100.0, 1.1)
	_prop("%s/garten/tree_fat.glb" % MOEBEL, Vector3(-6.4, 0.0, -3.4), 0.0, 2.4)
	_baue_auslage()


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/wochenmarkt.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#4FBF8B"), "emotion": "happy", "pos": Vector3(0.0, 0.0, -2.4)}


## Wochenmarkt VERKAUFT nicht, er KAUFT — eigenes Sheet mit Erlös-Rechnung.
func oeffne_laden() -> void:
	var inhalt := MarktSheet.new()
	inhalt.gs = game_state()
	inhalt.erstes_mal = ist_erstbesuch
	inhalt.verkauft.connect(_on_verkauft)
	zeige_sheet(I18nService.t("city.markt.sheet_titel"), inhalt)


## Gemüse auf den Tischen (reine Deko, ohne Bezug zum Inventar).
func _baue_auslage() -> void:
	var auslage := {
		"carrot.glb": Vector3(-3.9, 0.78, -1.7),
		"tomato.glb": Vector3(-3.2, 0.78, -1.9),
		"salad.glb": Vector3(-2.7, 0.78, -1.6),
		"corn.glb": Vector3(2.8, 0.78, -1.7),
		"watermelon.glb": Vector3(3.5, 0.78, -1.9),
		"broccoli.glb": Vector3(4.1, 0.78, -1.6),
	}
	for datei: String in auslage:
		_prop("%s/%s" % [ESSEN, datei], auslage[datei], randf() * 40.0 - 20.0, 1.1)


func _on_verkauft(_ernte_id: String, _menge: int) -> void:
	if rig != null:
		rig.play_clip("wave")
