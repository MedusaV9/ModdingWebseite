class_name OrtPost
extends OrtScene
## Post (Doc E §2.3, Doc C §3.7): Schalter-Halle mit Frau Zettel hinter der
## Scheibe, Paketberg im Hintergrund. FERTIG-1: statt des gestrichenen
## Multiplayer-Versand-Hooks gibt es hier das echte TAGESPAKET (PostLogic).

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-0.4, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/kitchencounter_sink.gltf" % INNEN, Vector3(1.6, 0.0, -1.3), 90.0, 0.95)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(-4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseClosedWide.glb" % MOEBEL, Vector3(4.4, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(3.2, 0.0, -0.4), 14.0, 1.5)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(3.6, 0.0, 0.9), -9.0, 1.5)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(-3.5, 0.0, 0.7), 27.0, 1.5)
	_prop("%s/coatRackStanding.glb" % MOEBEL, Vector3(-5.6, 0.0, -0.6), 0.0, 1.1)
	_prop("%s/pottedPlant.glb" % MOEBEL, Vector3(5.6, 0.0, -0.4), 0.0, 1.1)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/post.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#FFD166"), "emotion": "happy", "pos": Vector3(-0.4, 0.0, -2.4)}


## Post hat ein eigenes Schalter-UI (Tagespaket + Postkarten-Archiv).
func oeffne_laden() -> void:
	var inhalt := PostSheet.new()
	inhalt.gs = game_state()
	inhalt.schalter_gewaehlt.connect(_on_schalter)
	zeige_sheet(I18nService.t("city.post.sheet_titel"), inhalt)


func _on_schalter(_schalter: String) -> void:
	if rig != null:
		rig.play_clip("wave")
