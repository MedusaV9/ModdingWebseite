class_name OrtBaumarkt
extends OrtScene
## Baumarkt „Bodo Balken“ (Doc D §5, Doc E §2.3): Regalgang mit Material und
## Bauplänen. Der Laden + der Katalog gehören ORTE, das Crafting der
## Werkstatt (Haus-Agent) — Contract: `BaumarktKatalog.freigeschaltete_rezepte`.
## G7-P55 „Läden lebendig“: zweiter „echter Ort“ neben REHWEI (IKEA ist nur
## ein Katalog-Screen) — browsende Kunden am Regalgang, Kassen-Verhalten,
## Glöckchen und Gemurmel. W18 CC0: Regal-Lücke an der Rückwand gefüllt,
## Kisten-Provisorien → Kartons, Werkbank-Ecke (Kenney furniture).

const INNEN := "res://assets/city/innen"
const MOEBEL := "res://assets/furniture"
const CC0_MOEBEL := "res://assets/models/cc0/kenney_furniture_extra"

## Rohe Footprints (Breite, Tiefe) der Ecke-Ursprung-Möbel laut GLB-AABB.
const GRUND_REGAL := Vector2(0.4, 0.25)
const GRUND_KARTON := Vector2(0.212, 0.212)
const GRUND_WERKBANK := Vector2(0.734, 0.392)

## Baumarkt-Pastell: warmes Orange (Bodo-Balken-Branding, s. _npc_konfig).
const TINT_HOLZ := Color("#F2C089")


func _baue_innenraum() -> void:
	_prop("%s/kitchencounter_straight.gltf" % INNEN, Vector3(-1.4, 0.0, -1.2), 90.0, 0.95)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-5.0, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(-2.6, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(2.6, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/bookcaseOpen.glb" % MOEBEL, Vector3(5.0, 0.0, -3.6), 0.0, 1.4)
	_prop("%s/deko/box_B.gltf" % MOEBEL, Vector3(-4.2, 0.0, 0.4), 16.0, 1.5)
	_prop("%s/trashcan.glb" % MOEBEL, Vector3(5.9, 0.0, -1.8), 0.0, 1.0)
	_prop("%s/garten/fence_simple.glb" % MOEBEL, Vector3(-5.8, 0.0, 0.9), 90.0, 1.2)
	# W18: geschlossene Sortiment-Regale füllen die Rückwand-Lücke.
	for x: float in [-1.1, -0.3]:
		var regal := _cc0(
			"%s/bookcase_closed.glb" % CC0_MOEBEL, Vector3(x, 0.0, -3.6), 0.0, 1.4, GRUND_REGAL
		)
		OrtRequisiten.tinte(regal, TINT_HOLZ, 0.4)
	# W18: Kisten-Provisorien → Karton-Stapel am Regalgang (Wegpunkt bei
	# (3.8, 0.9) bleibt frei, s. _leben_konfig).
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL, Vector3(3.6, 0.0, -0.6), 12.0, 2.0, GRUND_KARTON
	)
	_cc0(
		"%s/cardboard_box_closed.glb" % CC0_MOEBEL,
		Vector3(3.65, 0.562, -0.55),
		40.0,
		2.0,
		GRUND_KARTON
	)
	_cc0("%s/cardboard_box_open.glb" % CC0_MOEBEL, Vector3(4.4, 0.0, 0.5), -20.0, 2.0, GRUND_KARTON)
	# W18: Werkbank-Ecke links vorn — Schreibtisch als Werkbank (getintet),
	# Hocker + offener Karton auf der Platte (Desk-Oberkante 0.73).
	var werkbank := _cc0(
		"%s/desk.glb" % CC0_MOEBEL, Vector3(-3.6, 0.0, 1.3), 0.0, 1.9, GRUND_WERKBANK
	)
	if werkbank != null:
		werkbank.name = "Werkbank"
	OrtRequisiten.tinte(werkbank, TINT_HOLZ, 0.4)
	var hocker := _prop("%s/stool_bar_square.glb" % CC0_MOEBEL, Vector3(-2.7, 0.0, 1.0), -40.0, 1.6)
	OrtRequisiten.tinte(hocker, TINT_HOLZ, 0.4)
	_cc0(
		"%s/cardboard_box_open.glb" % CC0_MOEBEL,
		Vector3(-3.75, 0.73, 1.25),
		30.0,
		1.2,
		GRUND_KARTON
	)


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
