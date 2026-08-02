class_name OrtPow
extends OrtScene
## POW! — Action-Laden (Doc E §2.3): Verkäufer „Bäm“ zwischen Regalen voller
## Dinge, die blinken oder umfallen. Verkauft die KAMERA (Gate für den
## Fotomodus, USER §E61) und 3 Tagesangebote (PowAngebote, deterministisch).
## G8-P1 „Jeder Ort lebt“ (PT2-B4): staunende Kundschaft vor den Regalen,
## Bäm tippt an der Kasse (KassenNpc) und die Momente machen dem Laden-
## Namen Ehre — Gadget-POW (Schreck-Hopser) und der klassische Umfaller.

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
	# G8-P1: Kassen-Piep + Winken übernimmt der KassenNpc (Muster rehwei).
	if kassen_npc != null:
		kassen_npc.kunde_zahlt()
	elif rig != null:
		rig.play_clip("wave")
	if ware_id == PowAngebote.KAMERA_ITEM:
		zeige_toast(I18nService.t("city.pow.kamera_gekauft"))
		return
	zeige_toast(I18nService.t("city.ort.item_erhalten"))


## G8-P1: Action-Laden-Leben — drei Staunende ziehen an Bären-Regal,
## Radio-Bord und Kisten-Ecke vorbei (Blick zur Regalwand). Momente:
## Gadget-POW (gvz_pop — irgendwas ist losgegangen, alle hüpfen) und der
## Umfaller (mg_junk tiefgestimmt — „Ich war das nicht!“).
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-4.2, 0.0, -1.6),
			Vector3(-2.2, 0.0, -1.8),
			Vector3(-0.6, 0.0, 0.9),
			Vector3(2.6, 0.0, 1.7),
		],
		"sprueche": "pow",
		"blick": Vector3(0.0, 0.0, -3.6),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
		"momente":
		[
			{
				"alle_s": 18.0,
				"versatz_s": 6.0,
				"sound": "gvz_pop",
				"pitch": 1.2,
				"clip": "hop",
				"sprueche": "pow_boom",
			},
			{
				"alle_s": 27.0,
				"versatz_s": 15.0,
				"sound": "mg_junk",
				"pitch": 0.9,
				"clip": "idle_lookaround",
				"sprueche": "pow_umfaller",
			},
		],
	}
