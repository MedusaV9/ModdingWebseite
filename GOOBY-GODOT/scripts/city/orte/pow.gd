class_name OrtPow
extends OrtScene
## POW! — Action-Laden (Doc E §2.3): Verkäufer „Bäm“ zwischen Regalen voller
## Dinge, die blinken oder umfallen. Verkauft die KAMERA (Gate für den
## Fotomodus, USER §E61) und 3 Tagesangebote (PowAngebote, deterministisch).

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(1.6, 0.0, -1.4), 90.0, 0.9)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-4.6, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseOpenLow.glb" % MOEBEL, Vector3(-2.2, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(4.8, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bear.glb" % MOEBEL, Vector3(-4.4, 1.05, -3.4), 200.0, 1.1)
	_prop("%s/radio.glb" % MOEBEL, Vector3(-2.2, 0.72, -3.5), 165.0, 1.1)
	_prop("%s/speaker.glb" % MOEBEL, Vector3(4.9, 0.0, -2.4), 150.0, 1.0)
	_prop("%s/lampRoundFloor.glb" % MOEBEL, Vector3(-5.8, 0.0, -1.0), 0.0, 1.1)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(3.4, 0.0, 0.6), 22.0, 1.4)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(-3.4, 0.0, 0.8), -18.0, 1.4)


func _dialog_pfad() -> String:
	return "res://scripts/city/data/dialoge/pow.json"


func _npc_konfig() -> Dictionary:
	return {"tint": Color("#F2C14E"), "emotion": "happy", "pos": Vector3(1.4, 0.0, -2.4)}


## POW! hat ein eigenes Händler-UI (Kamera-Gate + Tagesangebote).
func oeffne_laden() -> void:
	var inhalt := PowSheet.new()
	inhalt.gs = game_state()
	inhalt.gekauft.connect(_on_gekauft)
	zeige_sheet(I18nService.t("city.pow.sheet_titel"), inhalt)


func _on_gekauft(ware_id: String) -> void:
	if rig != null:
		rig.play_clip("wave")
	if ware_id == PowAngebote.KAMERA_ITEM:
		zeige_toast(I18nService.t("city.pow.kamera_gekauft"))
		return
	zeige_toast(I18nService.t("city.ort.item_erhalten"))
