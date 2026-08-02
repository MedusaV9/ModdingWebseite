class_name OrtBaumarkt
extends OrtScene
## Baumarkt „Bodo Balken“ (Doc D §5, Doc E §2.3): Regalgang mit Material und
## Bauplänen. Der Laden + der Katalog gehören ORTE, das Crafting der
## Werkstatt (Haus-Agent) — Contract: `BaumarktKatalog.freigeschaltete_rezepte`.
## G7-P55 „Läden lebendig“: zweiter „echter Ort“ neben REHWEI (IKEA ist nur
## ein Katalog-Screen) — browsende Kunden am Regalgang, Kassen-Verhalten,
## Glöckchen und Gemurmel.

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-1.4, 0.0, -1.2), 90.0, 0.95)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-5.0, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-2.6, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(2.6, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(5.0, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/crate.gltf" % INNEN, Vector3(3.6, 0.0, -0.6), 12.0, 0.75)
	_prop("%s/crate.gltf" % INNEN, Vector3(4.4, 0.0, 0.6), -20.0, 0.75)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(-4.2, 0.0, 0.4), 16.0, 1.5)
	_prop("%s/trashcan.glb" % MOEBEL, Vector3(5.9, 0.0, -1.8), 0.0, 1.0)
	_prop("%s/garten/fence_simple.glb" % MOEBEL, Vector3(-5.8, 0.0, 0.9), 90.0, 1.2)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/baumarkt.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F2A03D"), "emotion": "happy", "pos": Vector3(-1.4, 0.0, -2.3)}


## G7-P55: Ambient-Leben — 3 Kunden browsen den Regalgang entlang,
## Bodo Balken bekommt das Kassen-Verhalten, dazu Glöckchen + Gemurmel.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-5.0, 0.0, -2.2),
			Vector3(-2.6, 0.0, -2.0),
			Vector3(2.6, 0.0, -2.2),
			Vector3(5.0, 0.0, -1.9),
			Vector3(3.8, 0.0, 0.9),
		],
		"sprueche": "baumarkt",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
	}


## Baumarkt hat ein eigenes Händler-UI (Material + Baupläne).
func oeffne_laden() -> void:
	var inhalt := BaumarktSheet.new()
	inhalt.gs = game_state()
	inhalt.gekauft.connect(_on_gekauft)
	zeige_sheet(I18nService.t("city.baumarkt.sheet_titel"), inhalt)


func _on_gekauft(ware_id: String) -> void:
	if rig != null:
		rig.play_clip("wave")
	# G7-P55: Kauf piept an der Kasse (KassenNpc winkt gleich mit).
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()
	if ware_id.begins_with("bauplan_"):
		zeige_toast(I18nService.t("city.baumarkt.bauplan_toast"))
		return
	zeige_toast(I18nService.t("city.ort.item_erhalten"))
