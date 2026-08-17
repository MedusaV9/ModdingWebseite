class_name OrtPow
extends OrtScene
## POW! — Action-Laden (Doc E §2.3): Verkäufer „Bäm“ zwischen Regalen voller
## Dinge, die blinken oder umfallen. Verkauft die KAMERA (Gate für den
## Fotomodus, USER §E61) und 3 Tagesangebote (PowAngebote, deterministisch).
## J3 „Läden lebendig 2“: Ambient-Kundschaft + Kassen-Verhalten, dazu
## CC0-Deko (Kassen-Bildschirm, Spielzeugeisenbahn auf dem Boden).

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"
const CC0_HOLIDAY := "res://assets/models/cc0/kenney_holiday"

## Roher Footprint (Breite, Tiefe) des Ecke-Ursprung-Bildschirms (GLB-AABB).
const GRUND_SCREEN := Vector2(0.393, 0.104)

## Kassen-Tech in kühlem Grau-Blau (Muster GooUndBye-Kasse).
const TINT_TECH := Color("#9FB4C7")


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(1.6, 0.0, -1.4), 90.0, 0.9)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-4.6, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseOpenLow.glb" % MOEBEL, Vector3(-2.2, 0.0, -3.6), 0.0, 1.3)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(4.8, 0.0, -3.6), 0.0, 1.3)
	# W18/Audit: Teddy SITZT auf dem Regal (bookcaseOpen bei x=-4.6, Footprint
	# x∈[-4.60,-4.08], z∈[-3.925,-3.60], Oberkante 1.144) — vorher schwebte er
	# 1.05 m in der Luft, 0.2 m VOR dem Regal. Achtung: der bear.glb-Origin
	# liegt nicht im AABB-Zentrum (Yaw 200° schiebt die Box um ~(-0.15, +0.20)
	# in XZ) — dieser Origin zentriert das Mesh auf der Regal-Oberkante.
	_prop("%s/bear.glb" % MOEBEL, Vector3(-4.19, 1.14, -3.96), 200.0, 1.1)
	_prop("%s/radio.glb" % MOEBEL, Vector3(-2.2, 0.72, -3.5), 165.0, 1.1)
	_prop("%s/speaker.glb" % MOEBEL, Vector3(4.9, 0.0, -2.4), 150.0, 1.0)
	_prop("%s/lampRoundFloor.glb" % MOEBEL, Vector3(-5.8, 0.0, -1.0), 0.0, 1.1)
	_prop("%s/deko/box_A.gltf" % MOEBEL, Vector3(3.4, 0.0, 0.6), 22.0, 1.4)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(-3.4, 0.0, 0.8), -18.0, 1.4)
	# J3/CC0: Kassen-Bildschirm auf dem Counter (Counter-Platte ~0,85 m,
	# s. rehwei-Gläser) + Spielzeugeisenbahn als Boden-Vorführstrecke.
	var screen := _cc0(
		"%s/computer_screen.glb" % CC0_MOEBEL, Vector3(1.7, 0.85, -1.6), 180.0, 1.25, GRUND_SCREEN
	)
	OrtRequisiten.tinte(screen, TINT_TECH, 0.4)
	_prop("%s/train_locomotive.glb" % CC0_HOLIDAY, Vector3(-0.9, 0.0, -3.2), -70.0, 1.0)
	_prop("%s/train_wagon.glb" % CC0_HOLIDAY, Vector3(-0.25, 0.0, -3.0), -75.0, 1.0)


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
	# J3: Kassen-Piep + Winken über das Kassen-Verhalten von Bäm.
	if kassen_npc != null:
		_on_leben_kunde_zahlt(ware_id)
	elif rig != null:
		rig.play_clip("wave")
	if ware_id == PowAngebote.KAMERA_ITEM:
		zeige_toast(I18nService.t("city.pow.kamera_gekauft"))
		return
	zeige_toast(I18nService.t("city.ort.item_erhalten"))


## J3: Ambient-Leben — 3 Kunden staunen zwischen den Action-Regalen,
## Bäm bekommt das Kassen-Verhalten.
func _leben_konfig() -> Dictionary:
	return {
		"besucher": 3,
		"punkte":
		[
			Vector3(-3.8, 0.0, -1.6),
			Vector3(-1.8, 0.0, 0.9),
			Vector3(2.4, 0.0, 1.2),
			Vector3(0.8, 0.0, -0.3),
			Vector3(4.6, 0.0, -1.2),
		],
		"sprueche": "pow",
		"blick": Vector3(0.0, 0.0, -4.0),
		"gemurmel": true,
		"tuer_glocke": true,
		"kasse": true,
	}
