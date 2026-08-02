extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (b) „REHWEI + IKEA Kauf-Flow“ (Welle H): in der Stadt bei
## REHWEI vorfahren, Frau Rehwalds Dialog wie ein Spieler durchtippen
## („Einkaufen!“), im HaendlerSheet ZWEI Käufe tätigen (Möhre 5 ᴳ, Apfel
## 6 ᴳ — Kauf-Knöpfe tragen nur den Preis, darum Knopf-neben-Label-Sucher)
## und Geld/Inventar exakt nachrechnen. Danach zurück nach Hause und im
## IKEA (HUD-Knopf) ein Möbel in den Lagerraum kaufen (Katalog: Zeile →
## Detail → BuyButton). Aufruf: tools/ci/run_playtest.sh flow_pt2_rehwei_ikea

const MOEHRE_PREIS := 5
const APFEL_PREIS := 6
## IKEA-Budget: Startgeld (100) reicht für kein Sofa — Aufstockung nötig.
const IKEA_BUDGET := 800


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "in_die_stadt",
					"aktion": "tipp_name",
					"node": "BtnReise",
					"erwarte": {"route": "city"},
					"timeout_s": 120.0,
				},
				{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "vorfahrt_rehwei",
					"aktion": "tue",
					"funktion": fahre_zu.bind("rehwei"),
					"erwartung": "Auto steht am REHWEI-Parkplatz",
				},
				{
					"name": "rehwei_betreten",
					"aktion": "tipp_text",
					"text": "Betreten",
					"erwarte": {"klasse": "OrtRehwei"},
					"timeout_s": 120.0,
				},
				{"name": "laden_ansehen", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	# Dialog: Begrüßung durchtippen, dann die Option wählen, dann die
	# Laden-Zeile durchtippen — am Bubble-Ende feuert der laden-Effekt.
	liste.append_array(dialog_taps(2, "gruss"))
	(
		liste
		. append_array(
			[
				{
					"name": "option_einkaufen",
					"aktion": "tipp_text",
					"text": "Einkaufen!",
					"timeout_s": 30.0,
				},
			]
		)
	)
	liste.append_array(dialog_taps(3, "laden"))
	(
		liste
		. append_array(
			[
				{
					"name": "sheet_wartet",
					"aktion": "warte_bis",
					"text": "Du hast",
					"timeout_s": 30.0,
				},
				{
					"name": "coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("rehwei_start"),
				},
				{
					"name": "moehren_bestand_merken",
					"aktion": "tue",
					"funktion": _merke_moehren,
				},
				{
					"name": "moehre_kaufen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_neben_label.bind("Möhre"),
					"timeout_s": 20.0,
				},
				{"name": "kauf_piep_abwarten", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "moehre_geld_geprueft",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("rehwei_start", -MOEHRE_PREIS),
					"erwartung": "Münzen −5 nach Möhren-Kauf",
				},
				{
					"name": "moehre_im_inventar",
					"aktion": "tue",
					"funktion": _pruefe_moehre_plus_eins,
					"erwartung": "inventory.food.carrot +1",
				},
				{
					"name": "apfel_kaufen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_neben_label.bind("Apfel"),
					"timeout_s": 20.0,
				},
				{"name": "kauf_piep_2", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "apfel_geld_geprueft",
					"aktion": "tue",
					"funktion":
					pruefe_coins_delta.bind("rehwei_start", -MOEHRE_PREIS - APFEL_PREIS),
					"erwartung": "Münzen −11 nach Möhre+Apfel",
				},
				# Sheet per Griff-Wisch schließen (PanelSheet-Geste, kein X).
				{
					"name": "sheet_zuwischen",
					"aktion": "wisch",
					"von_funktion": canvas_punkt.bind(Vector2(0.5, 0.42)),
					"nach_funktion": canvas_punkt.bind(Vector2(0.5, 0.95)),
					"dauer_s": 0.4,
				},
				{"name": "sheet_zu_abwarten", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "rehwei_verlassen",
					"aktion": "tipp_name",
					"node": "Verlassen",
					"erwarte": {"route": "city"},
					"timeout_s": 120.0,
				},
				{
					"name": "heim_fuer_ikea",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{"name": "wohnzimmer_kurz", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "ikea_budget",
					"aktion": "tue",
					"funktion": gib_coins.bind(IKEA_BUDGET),
				},
				{
					"name": "ikea_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnIkea",
					"erwarte": {"klasse": "IkeaScreen"},
					"timeout_s": 90.0,
				},
				{"name": "katalog_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "ikea_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("ikea_start"),
				},
				{
					"name": "ikea_lager_merken",
					"aktion": "tue",
					"funktion": _merke_lager,
				},
				{
					"name": "erste_zeile_waehlen",
					"aktion": "tipp_pos",
					"pos_funktion": _erste_katalog_zeile,
					"timeout_s": 20.0,
				},
				{"name": "detail_ansehen", "aktion": "warte", "sekunden": 2.0},
				# Kaufen-Zeile liegt im Landscape UNTER dem Fold des
				# DetailScroll (Lauf pt2_b1: Tap traf geclippten Knopf,
				# Kauf blieb aus) — erst sichtbar rollen, dann tippen.
				{
					"name": "zum_kaufknopf_rollen",
					"aktion": "tue",
					"funktion": rolle_zu.bind("BuyButton"),
				},
				{"name": "roll_abwarten", "aktion": "warte", "sekunden": 0.8},
				{
					"name": "moebel_kaufen",
					"aktion": "tipp_name",
					"node": "BuyButton",
					"timeout_s": 20.0,
				},
				{"name": "kauf_abwarten", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lager_plus_eins",
					"aktion": "tue",
					"funktion": _pruefe_lager_plus_eins,
					"erwartung": "home.storage +1 nach IKEA-Kauf",
				},
				{
					"name": "geld_abgezogen",
					"aktion": "tue",
					"funktion": _pruefe_ikea_geld,
					"erwartung": "Münzen nach IKEA-Kauf kleiner",
				},
				{
					"name": "ikea_zurueck",
					"aktion": "tipp_name",
					"node": "BackButton",
					"erwarte": {"route": "home/living"},
					"timeout_s": 90.0,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


func _merke_moehren() -> bool:
	return merke("moehren", essen_bestand("carrot"))


func _pruefe_moehre_plus_eins() -> bool:
	var vorher := int(zettel.get("moehren", 0))
	var ist := essen_bestand("carrot")
	print("[PT2] Möhren im Inventar: %d → %d" % [vorher, ist])
	return ist == vorher + 1


func _lager_anzahl() -> int:
	var gs := game_state()
	if gs == null:
		return 0
	var lager: Variant = gs.get_value("home.storage", [])
	return (lager as Array).size() if lager is Array else 0


func _merke_lager() -> bool:
	return merke("ikea_lager", _lager_anzahl())


func _pruefe_lager_plus_eins() -> bool:
	var vorher := int(zettel.get("ikea_lager", 0))
	var ist := _lager_anzahl()
	print("[PT2] IKEA-Lager: %d → %d Stück" % [vorher, ist])
	return ist == vorher + 1


func _pruefe_ikea_geld() -> bool:
	var vorher := int(zettel.get("ikea_start", 0))
	var ist := coins()
	print("[PT2] IKEA-Münzen: %d → %d" % [vorher, ist])
	return ist < vorher


## Erste Katalog-Zeile („Row_<id>“) im Item-Scroll finden und antippen.
func _erste_katalog_zeile() -> Vector2:
	var liste := harness.root.find_child("ItemList", true, false)
	if liste == null:
		print("[PT2] ItemList nicht gefunden")
		return Vector2.ZERO
	for kind in liste.get_children():
		if kind is Control and String(kind.name).begins_with("Row_"):
			if (kind as Control).is_visible_in_tree():
				print("[PT2] Wähle Katalog-Zeile %s" % kind.name)
				return (kind as Control).get_global_rect().get_center()
	print("[PT2] Keine sichtbare Row_ im Katalog")
	return Vector2.ZERO
