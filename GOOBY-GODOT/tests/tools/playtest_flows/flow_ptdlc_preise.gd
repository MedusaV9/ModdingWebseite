extends "res://tests/tools/playtest_flows/flow_ptdlc_basis.gd"
## PT-DLC Flow (b) — GOOBYE PREIS-SCHIEBER (W18/R3, G8): zwei Markttage
## mit DEMSELBEN Seed 1, einziger Unterschied ist der Gemüse-Schieber.
## Tag 1 läuft mit Richtwert-Preisen, Tag 2 mit Gemüse +30 % (echter
## Slider-Drag im Preise-Sheet) — die Verkaufszahlen müssen PLAUSIBEL
## reagieren: weniger Möhren bei teurerem Gemüse (Monotonie-Beleg), und
## jede Möhren-Position kostet exakt MEINEN Schieber-Preis (5 × 1,3 → 7).
## Dazu: Trend-Banner im Sheet gegen den ECHTEN Tagestrend der Sim halten
## (gleicher Seed → gleiche Wahrheit) und Kundenlust-Worte an den Stufen.
##
## Goldwerte aus flow_ptdlc_seedsuche (ECHTE Spiel-Statics):
##   Seed 1 → Trend gemuese, 3 Kunden, Alwin-Menge 1.
##   Tag 1 (Regal apple 6 / carrot 8 / bread 5, alles Richtwert):
##     verkauft {carrot 3, bread 1, apple 2}, Umsatz 37.
##   Tag 2 (Rest-Regal apple 4 / carrot 5 / bread 4, gemuese 1,3):
##     verkauft {carrot 2, bread 1, apple 2}, Umsatz 36.

const MARKT_SEED := 1
const MARKT_TEMPO := 0.35
const TREND_GRUPPE := "gemuese"
const SCHIEBER_FAKTOR := 1.3

const GOLD_TAG1 := {"umsatz": 37, "kunden": 3, "verkauft": {"carrot": 3, "bread": 1, "apple": 2}}
const GOLD_TAG2 := {"umsatz": 36, "kunden": 3, "verkauft": {"carrot": 2, "bread": 1, "apple": 2}}

var _plan1: Dictionary = {}
var _plan2: Dictionary = {}


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(goobye_kauf_schritte())
	liste.append_array(_vorbereitung_schritte())
	liste.append_array(_sheet_tag1_schritte())
	liste.append_array(_tag1_schritte())
	liste.append_array(_sheet_tag2_schritte())
	liste.append_array(_tag2_schritte())
	return liste


## ------------------------------------------------ Regal für Tag 1 stellen


func _vorbereitung_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "seed_gesetzt",
			"aktion": "tue",
			"funktion": szene_prop.bind("seed_override", MARKT_SEED),
		},
		{
			"name": "tempo_gesetzt",
			"aktion": "tue",
			"funktion": szene_prop.bind("tempo", MARKT_TEMPO),
		},
		# NUR 3 Slots füllen (apple 6, carrot 8, bread 5) — exakt das Regal
		# der Goldwert-Rechnung; Slots 3/4 bleiben bewusst leer.
		{
			"name": "slot_0_apfel",
			"aktion": "tipp_name",
			"node": "Slot0",
			"erwarte": {"text": "×6"},
			"timeout_s": 20.0,
		},
		{
			"name": "slot_1_moehren",
			"aktion": "tipp_name",
			"node": "Slot1",
			"erwarte": {"text": "×8"},
			"timeout_s": 20.0,
		},
		{
			"name": "slot_2_brot",
			"aktion": "tipp_name",
			"node": "Slot2",
			"erwarte": {"text": "×5"},
			"timeout_s": 20.0,
		},
		{
			"name": "regal_tag1_gemerkt",
			"aktion": "tue",
			"funktion": _regal_merken.bind("regal1"),
			"erwartung": "19 Stück im Regal (6+8+5)",
		},
	]


## ------------------------------- Sheet-Blick Tag 1 (Richtwert + Banner)


func _sheet_tag1_schritte() -> Array[Dictionary]:
	return [
		{"name": "preise_geoeffnet", "aktion": "tipp_name", "node": "Preise", "timeout_s": 20.0},
		{
			"name": "preis_sheet_da",
			"aktion": "warte_bis",
			"text": "Preise am Regal",
			"timeout_s": 20.0,
		},
		{
			"name": "trend_banner_geprueft",
			"aktion": "tue",
			"funktion": _trend_banner_pruefen,
			"erwartung": "Banner nennt den echten Tagestrend (Gemüse ★)",
		},
		{
			"name": "lust_richtwert_hoch",
			"aktion": "tue",
			"funktion": _lust_ist.bind(TREND_GRUPPE, "lust_hoch"),
			"erwartung": "Richtwert-Stellung → „greifen ohne Zögern“",
		},
		# Backdrop-Tipp statt Runter-Wisch (Befund pt2_c4: Wische scrollen).
		{
			"name": "sheet_zu_tag1",
			"aktion": "tipp_pos",
			"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
			"pflicht": false,
		},
		{"name": "sheet_zu_warten_1", "aktion": "warte", "sekunden": 1.5},
	]


## ------------------------------------------- Tag 1: Richtwert-Markttag


func _tag1_schritte() -> Array[Dictionary]:
	return [
		{"name": "tag1_coins_gemerkt", "aktion": "tue", "funktion": merke_coins.bind("tag1")},
		{
			"name": "tag1_geoeffnet",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": _phase_ist.bind("offen")},
			"timeout_s": 20.0,
		},
		{
			"name": "tag1_plan_golden",
			"aktion": "tue",
			"funktion": _tag1_plan_geprueft,
			"erwartung": "Tag-1-Plan == Goldwert (37 ᴳ, carrot 3/bread 1/apple 2)",
		},
		{
			"name": "tag1_durch",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 300.0,
		},
		{
			"name": "tag1_karte_geprueft",
			"aktion": "tue",
			"funktion": _tag1_karte,
			"erwartung": "Kassensturz Tag 1 == Plan (Umsatz/Kunden/Artikel/Regal)",
		},
		{"name": "tag1_kasse_gemerkt", "aktion": "tue", "funktion": kassensturz_merken},
		{
			"name": "tag1_feierabend",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"weg_text": "Kassensturz!"},
			"timeout_s": 30.0,
		},
		{
			"name": "tag1_umsatz_gebucht",
			"aktion": "tue",
			"funktion": umsatz_gebucht,
			"erwartung": "Feierabend bucht exakt den Karten-Umsatz",
		},
		{
			"name": "tag1_golden_gebucht",
			"aktion": "tue",
			"funktion": pruefe_coins_delta.bind("tag1", GOLD_TAG1["umsatz"]),
			"erwartung": "Tag 1 bringt exakt +37 ᴳ",
		},
	]


## ----------------------------- Sheet Tag 2: Gemüse-Schieber auf +30 %


func _sheet_tag2_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "preise_geoeffnet_2",
			"aktion": "tipp_name",
			"node": "Preise",
			"timeout_s": 20.0,
		},
		{
			"name": "preis_sheet_da_2",
			"aktion": "warte_bis",
			"text": "Preise am Regal",
			"timeout_s": 20.0,
		},
		{
			"name": "schieber_ins_bild",
			"aktion": "tue",
			"funktion": rolle_zu.bind("Schieber_" + TREND_GRUPPE),
		},
		{"name": "schieber_pause", "aktion": "warte", "sekunden": 0.6},
		# Echter Drag: Griff in der Mitte (Richtwert) fassen, nach rechts
		# über den Rand ziehen — der Slider klemmt bei +30 %.
		{
			"name": "gemuese_hochgezogen",
			"aktion": "wisch",
			"von_funktion": schieber_punkt.bind(TREND_GRUPPE, 0.0),
			"nach_funktion": schieber_punkt.bind(TREND_GRUPPE, 0.55),
			"dauer_s": 0.8,
			"erwarte": {"bedingung": _faktor_ist.bind(TREND_GRUPPE, SCHIEBER_FAKTOR)},
			"timeout_s": 15.0,
		},
		{
			"name": "lust_mutig",
			"aktion": "tue",
			"funktion": _lust_ist.bind(TREND_GRUPPE, "lust_niedrig"),
			"erwartung": "+30 % → „Kunden lassen öfter liegen. Mutig!“",
		},
		{
			"name": "sheet_zu_tag2",
			"aktion": "tipp_pos",
			"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
			"pflicht": false,
		},
		{"name": "sheet_zu_warten_2", "aktion": "warte", "sekunden": 1.5},
	]


## ------------------------------- Tag 2: gleicher Seed, teureres Gemüse


func _tag2_schritte() -> Array[Dictionary]:
	return [
		# Kein Nachfüllen: das Rest-Regal (4/5/4) IST der Goldwert-Aufbau.
		{
			"name": "regal_tag2_gemerkt",
			"aktion": "tue",
			"funktion": _regal_merken.bind("regal2"),
			"erwartung": "13 Stück Rest im Regal (4+5+4)",
		},
		{"name": "tag2_coins_gemerkt", "aktion": "tue", "funktion": merke_coins.bind("tag2")},
		{
			"name": "tag2_geoeffnet",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": _phase_ist.bind("offen")},
			"timeout_s": 20.0,
		},
		{
			"name": "tag2_plan_golden",
			"aktion": "tue",
			"funktion": _tag2_plan_geprueft,
			"erwartung": "Tag-2-Plan == Goldwert + Möhre je 7 ᴳ + Monotonie",
		},
		{
			"name": "tag2_durch",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 300.0,
		},
		{
			"name": "tag2_karte_geprueft",
			"aktion": "tue",
			"funktion": _tag2_karte,
			"erwartung": "Kassensturz Tag 2 == Plan (Umsatz/Kunden/Artikel/Regal)",
		},
		{"name": "tag2_kasse_gemerkt", "aktion": "tue", "funktion": kassensturz_merken},
		{
			"name": "tag2_feierabend",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"weg_text": "Kassensturz!"},
			"timeout_s": 30.0,
		},
		{
			"name": "tag2_umsatz_gebucht",
			"aktion": "tue",
			"funktion": umsatz_gebucht,
			"erwartung": "Feierabend bucht exakt den Karten-Umsatz",
		},
		{
			"name": "tag2_golden_gebucht",
			"aktion": "tue",
			"funktion": pruefe_coins_delta.bind("tag2", GOLD_TAG2["umsatz"]),
			"erwartung": "Tag 2 bringt exakt +36 ᴳ",
		},
		{"name": "vergleich_fertig", "aktion": "warte", "sekunden": 2.0},
	]


## ---------------------------------------------------------------- Helfer


func _regal_merken(key: String) -> bool:
	var stand := _regal_stand()
	merke(key, stand)
	return stand > 0


## Trend-Banner im Sheet == ECHTER Sim-Trend (beide aus Seed 1).
func _trend_banner_pruefen() -> bool:
	var soll := I18nService.t(
		"dlc_goobye.preise.trend", {"gruppe": I18nService.t("dlc_goobye.gruppe." + TREND_GRUPPE)}
	)
	var ist := label_text("TrendBanner")
	var kopf := label_text("Kopf_" + TREND_GRUPPE)
	print("[PTDLC] TrendBanner '%s' (soll '%s'), Kopf '%s'" % [ist, soll, kopf])
	return ist == soll and kopf.ends_with("★")


func _lust_ist(gruppe_id: String, lust_key: String) -> bool:
	var soll := I18nService.t("dlc_goobye.preise." + lust_key)
	var ist := label_text("Lust_" + gruppe_id)
	print("[PTDLC] Lust %s: '%s' (soll '%s')" % [gruppe_id, ist, soll])
	return ist == soll


func _tag1_plan_geprueft() -> bool:
	_plan1 = _plan_kopie()
	return _plan_konsistent(_plan1) and _plan_wie_gold(_plan1, GOLD_TAG1)


func _tag1_karte() -> bool:
	return _kassenkarte_stimmt(_plan1, int(zettel.get("regal1", 0)))


## Tag 2: Goldwert + jede Möhren-Position kostet MEINEN Schieber-Preis
## (5 × 1,3 → 7) + Monotonie gegen Tag 1 (weniger Möhren bei +30 %).
func _tag2_plan_geprueft() -> bool:
	_plan2 = _plan_kopie()
	if not _plan_konsistent(_plan2) or not _plan_wie_gold(_plan2, GOLD_TAG2):
		return false
	var moehre_soll := mein_verkaufspreis(GoobyeKatalog.ware("carrot"), SCHIEBER_FAKTOR)
	for bon: Dictionary in _plan2.get("bons", []):
		for position: Dictionary in bon.get("positionen", []):
			if str(position.get("ware", "")) != "carrot":
				continue
			if int(position.get("preis", 0)) != moehre_soll:
				print(
					(
						"[PTDLC] Möhren-Preis falsch: %d statt %d"
						% [int(position.get("preis", 0)), moehre_soll]
					)
				)
				return false
	var tag1 := int((_plan1.get("verkauft", {}) as Dictionary).get("carrot", 0))
	var tag2 := int((_plan2.get("verkauft", {}) as Dictionary).get("carrot", 0))
	print("[PTDLC] Möhren-Monotonie: Tag 1 %d → Tag 2 %d bei +30 %%" % [tag1, tag2])
	return tag2 < tag1


func _tag2_karte() -> bool:
	return _kassenkarte_stimmt(_plan2, int(zettel.get("regal2", 0)))
