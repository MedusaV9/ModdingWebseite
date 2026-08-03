extends "res://tests/tools/playtest_flows/flow_ptdlc_basis.gd"
## PT-DLC Flow (a) — GOOBYE GROSSMARKT komplett (W18/R3, G8): Laden →
## „Zum Großmarkt“ → Rampe (Staffel-Rabatt ab 10, Rampen-Tagesangebot,
## Kofferraum-Deckel, Budget-Klemme) → Kauf → Rückfahrt → Einräumen →
## Markttag mit der neuen Ware → Kassensturz → Feierabend.
##
## Geld und Lager rechnet der Flow mit der EIGENEN Doc-Mathe der Basis
## nach (mein_*-Familie) — weicht das Spiel ab, wird der Schritt rot.
##
## Das Rampen-Tagesangebot hängt am ECHTEN Datum (die Route entsteht im
## Router, seed_override greift dort nicht): der Flow LIEST die Gruppe
## zur Laufzeit, wählt seine Angebots-Ware danach und rechnet mit ihr.

## Markttag-Seed (flow_ptdlc_seedsuche: FLOW-A Seed=7 → 3 Kunden inkl.
## Hamster-Gooby, Alwin-Menge 1) + Choreo-Raffer für llvmpipe.
const MARKT_SEED := 7
const MARKT_TEMPO := 0.35

## Staffel-Palette: 10× Brot (EK 6 = vk 10 × 60 %), Kofferraum-Probe Apfel.
const STAFFEL_WARE := "bread"
const STAFFEL_MENGE := 10
const ANGEBOT_MENGE := 2
const TRUNK_WARE := "apple"

## Startlager 32 Stück (goobye_sortiment.json `start`: 6+8+5+5+4+4);
## nach dem 12-Kisten-Einkauf sind es 44.
const LAGER_START := 32
const LAGER_NACH_KAUF := LAGER_START + STAFFEL_MENGE + ANGEBOT_MENGE

var _angebot := ""
var _angebots_ware := ""
var _trunk_extra := 0
var _summe_soll := 0
var _plan: Dictionary = {}


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(goobye_kauf_schritte())
	liste.append_array(_anfahrt_schritte())
	liste.append_array(_staffel_schritte())
	liste.append_array(_angebot_schritte())
	liste.append_array(_kofferraum_schritte())
	liste.append_array(_budget_schritte())
	liste.append_array(_einkauf_schritte())
	liste.append_array(_markttag_schritte())
	return liste


## ------------------------------------------------------------ Anfahrt


func _anfahrt_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "startlager_da",
			"aktion": "warte_bis",
			"text": "Lager: %d Stück" % LAGER_START,
			"timeout_s": 20.0,
		},
		{
			"name": "zum_grossmarkt",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"route": "dlc/goobye_grossmarkt"},
			"timeout_s": 90.0,
		},
		{
			"name": "rampe_erreicht",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("KaufenLosfahren"),
			"timeout_s": 60.0,
		},
		{
			"name": "angebot_gelesen",
			"aktion": "tue",
			"funktion": _angebot_lesen,
			"erwartung": "AngebotBanner nennt die Tagesgruppe der Rampe",
		},
		{
			"name": "kasse_zeile_stimmt",
			"aktion": "tue",
			"funktion": _kasse_zeile_stimmt,
			"erwartung": "BudgetZeile zeigt exakt den echten Kontostand",
		},
	]


## --------------------------------------------------- Staffel-Rabatt (10×)


func _staffel_schritte() -> Array[Dictionary]:
	return [
		{"name": "brot_rollen", "aktion": "tue", "funktion": rolle_zu.bind("Plus_" + STAFFEL_WARE)},
		{"name": "brot_roll_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "brot_plus_erster",
			"aktion": "tipp_name",
			"node": "Plus_" + STAFFEL_WARE,
			"erwarte": {"bedingung": _anzahl_ist.bind(STAFFEL_WARE, 1)},
			"timeout_s": 15.0,
		},
		{
			"name": "brot_auf_neun",
			"aktion": "tue",
			"funktion": _plus_emitten.bind(STAFFEL_WARE, 8),
			"erwartung": "8 weitere Brot-Paletten im Korb",
		},
		{
			"name": "brot_plus_zehnter",
			"aktion": "tipp_name",
			"node": "Plus_" + STAFFEL_WARE,
			"erwarte": {"bedingung": _anzahl_ist.bind(STAFFEL_WARE, STAFFEL_MENGE)},
			"timeout_s": 15.0,
		},
		{"name": "staffel_tag_da", "aktion": "warte_bis", "text": "Staffel!", "timeout_s": 10.0},
		{
			"name": "staffel_nachgerechnet",
			"aktion": "tue",
			"funktion": _summe_pruefen,
			"erwartung": "SummeZeile == eigene Staffel-Mathe (−5 % ab 10)",
		},
	]


## ------------------------------------------- Rampen-Tagesangebot (−15 %)


func _angebot_schritte() -> Array[Dictionary]:
	return [
		{"name": "angebot_rollen", "aktion": "tue", "funktion": _angebot_rollen},
		{"name": "angebot_roll_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "angebot_stern_da",
			"aktion": "warte_bis",
			"text": "Heute im Rampen-Angebot!",
			"timeout_s": 10.0,
		},
		{
			"name": "angebot_plus_1",
			"aktion": "tipp_pos",
			"pos_funktion": _angebot_plus_mitte,
			"erwarte": {"bedingung": _angebot_anzahl.bind(1)},
			"timeout_s": 15.0,
		},
		{
			"name": "angebot_plus_2",
			"aktion": "tipp_pos",
			"pos_funktion": _angebot_plus_mitte,
			"erwarte": {"bedingung": _angebot_anzahl.bind(ANGEBOT_MENGE)},
			"timeout_s": 15.0,
		},
		{
			"name": "angebot_nachgerechnet",
			"aktion": "tue",
			"funktion": _summe_pruefen,
			"erwartung": "SummeZeile == eigene Mathe inkl. −15 % Angebot",
		},
	]


## -------------------------------------------- Kofferraum-Deckel (24 Kisten)


func _kofferraum_schritte() -> Array[Dictionary]:
	return [
		{"name": "trunk_geld", "aktion": "tue", "funktion": gib_coins.bind(9999)},
		{
			"name": "trunk_fuellen",
			"aktion": "tue",
			"funktion": _trunk_fuellen,
			"erwartung": "Korb per Stepper auf 24/24 Kisten aufgefüllt",
		},
		{
			"name": "trunk_zeile_da",
			"aktion": "warte_bis",
			"text": "Kofferraum: %d/%d" % [KOFFERRAUM_MAX, KOFFERRAUM_MAX],
			"timeout_s": 10.0,
		},
		{"name": "trunk_rollen", "aktion": "tue", "funktion": rolle_zu.bind("Plus_" + TRUNK_WARE)},
		{"name": "trunk_roll_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "trunk_deckel_toast",
			"aktion": "tipp_name",
			"node": "Plus_" + TRUNK_WARE,
			"erwarte": {"text": "Mehr passt nicht in den Kofferraum!"},
			"timeout_s": 15.0,
		},
		{
			"name": "trunk_geleert",
			"aktion": "tue",
			"funktion": _trunk_leeren,
			"erwartung": "Probe-Äpfel wieder raus, Budget zurück auf 500",
		},
	]


## ----------------------------------------------------- Budget-Klemme


func _budget_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "budget_geklemmt",
			"aktion": "tue",
			"funktion": _budget_klemmen,
			"erwartung": "Münzen exakt auf meine Korbsumme geklemmt",
		},
		{
			"name": "brot_rollen_2",
			"aktion": "tue",
			"funktion": rolle_zu.bind("Plus_" + STAFFEL_WARE),
		},
		{"name": "brot_roll_pause_2", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "budget_toast",
			"aktion": "tipp_name",
			"node": "Plus_" + STAFFEL_WARE,
			"erwarte": {"text": "Dafür reichen die Münzen gerade nicht."},
			"timeout_s": 15.0,
		},
		{
			"name": "budget_unveraendert",
			"aktion": "tue",
			"funktion": _anzahl_ist.bind(STAFFEL_WARE, STAFFEL_MENGE),
			"erwartung": "Brot-Zeile bleibt trotz Tipp bei 10",
		},
		{"name": "budget_zurueck", "aktion": "tue", "funktion": gib_coins.bind(500)},
	]


## ------------------------------------------------- Kauf + Rückfahrt


func _einkauf_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "vor_kauf_gemerkt",
			"aktion": "tue",
			"funktion": _vor_kauf_merken,
			"erwartung": "Korb, Lager und Kontostand notiert",
		},
		{
			"name": "kaufen_losfahren",
			"aktion": "tipp_name",
			"node": "KaufenLosfahren",
			"erwarte": {"bedingung": control_da.bind("ZurueckInDenLaden")},
			"timeout_s": 60.0,
		},
		{
			"name": "kauf_nachgerechnet",
			"aktion": "tue",
			"funktion": _kauf_geprueft,
			"erwartung": "Münzen −Summe, Lager +Paletten, Ankunftszeile exakt",
		},
		{
			"name": "zurueck_in_den_laden",
			"aktion": "tipp_name",
			"node": "ZurueckInDenLaden",
			"erwarte": {"route": "dlc/goobye_laden"},
			"timeout_s": 90.0,
		},
		{
			"name": "einraeum_toast",
			"aktion": "warte_bis",
			"text": "Kisten eingeräumt",
			"timeout_s": 15.0,
			"pflicht": false,
		},
	]


## ------------------------------------- Einräumen + Markttag mit neuer Ware


func _markttag_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
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
		{
			"name": "lager_nach_kauf_da",
			"aktion": "warte_bis",
			"text": "Lager: %d Stück" % LAGER_NACH_KAUF,
			"timeout_s": 15.0,
		},
		{"name": "lager_gemerkt", "aktion": "tue", "funktion": _lager_merken},
	]
	for i in 5:
		liste.append({"name": "slot_%d_fuellen" % i, "aktion": "tipp_name", "node": "Slot%d" % i})
	(
		liste
		. append_array(
			[
				{
					"name": "regal_nachgerechnet",
					"aktion": "tue",
					"funktion": _regal_geprueft,
					"erwartung": "Regal == eigene Slot-Simulation aus dem Lager",
				},
				{
					"name": "laden_geoeffnet",
					"aktion": "tipp_name",
					"node": "LadenOeffnen",
					"erwarte": {"bedingung": _phase_ist.bind("offen")},
					"timeout_s": 20.0,
				},
				{
					"name": "plan_gelesen",
					"aktion": "tue",
					"funktion": _plan_lesen,
					"erwartung": "Tagesplan in sich stimmig (Bons == Umsatz)",
				},
				{
					"name": "markttag_durch",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("Feierabend"),
					"timeout_s": 300.0,
				},
				{
					"name": "kassensturz_nachgerechnet",
					"aktion": "tue",
					"funktion": _abschluss_geprueft,
					"erwartung": "Karte == Plan (Umsatz, Kunden, Artikel, Regal)",
				},
				{"name": "kassensturz_gemerkt", "aktion": "tue", "funktion": kassensturz_merken},
				{
					"name": "feierabend",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"erwarte": {"weg_text": "Kassensturz!"},
					"timeout_s": 30.0,
				},
				{
					"name": "umsatz_gebucht",
					"aktion": "tue",
					"funktion": umsatz_gebucht,
					"erwartung": "Feierabend bucht exakt den Karten-Umsatz",
				},
				{"name": "tag_fertig", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ---------------------------------------------------------------- Helfer


## Angebotsgruppe der Rampe zur Laufzeit lesen und die Angebots-Ware
## wählen (erste Katalog-Ware der Gruppe; Brot wäre doppelt → Croissant).
func _angebot_lesen() -> bool:
	var szene := grossmarkt_szene()
	if szene == null:
		return false
	_angebot = str(szene.get("_angebot_gruppe"))
	if _angebot.is_empty():
		print("[PTDLC] Rampe ohne Angebotsgruppe?!")
		return false
	_angebots_ware = _erste_ware_der_gruppe(_angebot)
	if _angebots_ware == STAFFEL_WARE:
		_angebots_ware = "croissant"
	var banner := label_text("AngebotBanner")
	var gruppen_name := I18nService.t("dlc_goobye.gruppe." + _angebot)
	print(
		(
			"[PTDLC] Rampen-Angebot: %s (%s) — Banner '%s', Angebots-Ware %s"
			% [_angebot, gruppen_name, banner, _angebots_ware]
		)
	)
	return banner.contains(gruppen_name)


## Kassen-Zeile der Rampe gegen den ECHTEN Kontostand halten (nicht gegen
## eine feste Zahl: das coins1000-Achievement schenkt nach dem Münz-Cheat
## +50, also stehen hier legitim 550 statt 500 — Lauf ptdlc_a1).
func _kasse_zeile_stimmt() -> bool:
	var soll := I18nService.t("dlc_goobye.grossmarkt.budget", {"betrag": coins()})
	var ist := label_text("BudgetZeile")
	print("[PTDLC] Kasse-Zeile: '%s' (soll '%s')" % [ist, soll])
	return ist == soll


func _erste_ware_der_gruppe(gruppe_id: String) -> String:
	for ware: Dictionary in GoobyeKatalog.waren():
		if str(ware.get("gruppe", "")) == gruppe_id:
			return str(ware["id"])
	return ""


func _anzahl_ist(ware_id: String, soll: int) -> bool:
	return label_text("Anzahl_" + ware_id) == str(soll)


## Stepper-Taps in Serie über das ECHTE pressed-Signal (der erste und der
## Schwellen-Tap sind echte Bildschirm-Tipps — hier zählt nur die Menge).
func _plus_emitten(ware_id: String, mal: int) -> bool:
	var knopf := harness.root.find_child("Plus_" + ware_id, true, false)
	if not (knopf is BaseButton):
		print("[PTDLC] Plus_%s nicht gefunden" % ware_id)
		return false
	for _i in mal:
		(knopf as BaseButton).pressed.emit()
	return true


func _minus_emitten(ware_id: String, mal: int) -> bool:
	var knopf := harness.root.find_child("Minus_" + ware_id, true, false)
	if not (knopf is BaseButton):
		print("[PTDLC] Minus_%s nicht gefunden" % ware_id)
		return false
	for _i in mal:
		(knopf as BaseButton).pressed.emit()
	return true


func _angebot_rollen() -> bool:
	return rolle_zu("Plus_" + _angebots_ware)


func _angebot_plus_mitte() -> Vector2:
	return control_mitte("Plus_" + _angebots_ware)


func _angebot_anzahl(soll: int) -> bool:
	return _anzahl_ist(_angebots_ware, soll)


func _korb_kopie() -> Dictionary:
	var szene := grossmarkt_szene()
	if szene == null:
		return {}
	var korb: Variant = szene.get("_korb")
	return (korb as Dictionary).duplicate(true) if korb is Dictionary else {}


func _kisten_zahl(korb: Dictionary) -> int:
	var summe := 0
	for id: Variant in korb:
		summe += int(korb[id])
	return summe


## SummeZeile gegen die EIGENE Rabatt-Mathe halten (exakter String).
func _summe_pruefen() -> bool:
	var korb := _korb_kopie()
	if korb.is_empty():
		return false
	_summe_soll = mein_korb_preis(korb, _angebot)
	var soll_text := I18nService.t("dlc_goobye.grossmarkt.summe", {"betrag": _summe_soll})
	var ist_text := label_text("SummeZeile")
	print("[PTDLC] Korb %s → meine Summe %d ('%s')" % [str(korb), _summe_soll, ist_text])
	return ist_text == soll_text


## Kofferraum-Probe: mit Stepper-Signalen bis 24/24 auffüllen.
func _trunk_fuellen() -> bool:
	_trunk_extra = KOFFERRAUM_MAX - _kisten_zahl(_korb_kopie())
	if _trunk_extra <= 0:
		return false
	if not _plus_emitten(TRUNK_WARE, _trunk_extra):
		return false
	return _kisten_zahl(_korb_kopie()) == KOFFERRAUM_MAX


func _trunk_leeren() -> bool:
	if not _minus_emitten(TRUNK_WARE, _trunk_extra):
		return false
	var kisten := _kisten_zahl(_korb_kopie())
	gib_coins(500)
	return kisten == STAFFEL_MENGE + ANGEBOT_MENGE


## Budget exakt auf MEINE Korbsumme klemmen: rechnet das Spiel anders,
## würde der folgende Plus-Tipp durchgehen und der Check danach fällt um.
func _budget_klemmen() -> bool:
	var korb := _korb_kopie()
	if korb.is_empty():
		return false
	_summe_soll = mein_korb_preis(korb, _angebot)
	return gib_coins(_summe_soll)


func _vor_kauf_merken() -> bool:
	var korb := _korb_kopie()
	if korb.is_empty():
		return false
	zettel["korb"] = korb
	zettel["lager_vor"] = gs_lager()
	_summe_soll = mein_korb_preis(korb, _angebot)
	merke("kauf_summe", _summe_soll)
	return merke_coins("einkauf")


## Nach dem Kauf: Münz-Delta, Lager-Zuwachs und Ankunftszeile exakt.
func _kauf_geprueft() -> bool:
	if not pruefe_coins_delta("einkauf", -_summe_soll):
		return false
	var korb: Dictionary = zettel.get("korb", {})
	var vorher: Dictionary = zettel.get("lager_vor", {})
	var nachher := gs_lager()
	for id: Variant in korb:
		var soll := int(vorher.get(id, 0)) + int(korb[id])
		if int(nachher.get(id, 0)) != soll:
			print("[PTDLC] Lager %s: ist %d, soll %d" % [str(id), int(nachher.get(id, 0)), soll])
			return false
	var soll_zeile := I18nService.t(
		"dlc_goobye.grossmarkt.einraeumen_zeile",
		{"kisten": _kisten_zahl(korb), "betrag": _summe_soll}
	)
	var ist_zeile := label_text("AnkunftZeile")
	print("[PTDLC] Ankunft: '%s'" % ist_zeile)
	return ist_zeile == soll_zeile


func _lager_merken() -> bool:
	var szene := laden_szene()
	if szene == null:
		return false
	var lager: Variant = szene.get("_lager")
	zettel["lager_regal"] = (lager as Dictionary).duplicate(true) if lager is Dictionary else {}
	return not (zettel["lager_regal"] as Dictionary).is_empty()


## Regal nach 5 Slot-Taps gegen die eigene Slot-Simulation halten.
func _regal_geprueft() -> bool:
	var ist := _regal_stand()
	var soll := erwarteter_regal_stand(zettel.get("lager_regal", {}))
	zettel["regal_stand"] = ist
	print("[PTDLC] Regal nach Einräumen: %d Stück (meine Simulation: %d)" % [ist, soll])
	return ist == soll and ist > 0


## Tagesplan lesen und in sich prüfen (Bon-Summen == Plan-Umsatz).
func _plan_lesen() -> bool:
	_plan = _plan_kopie()
	return not _plan.is_empty() and _plan_konsistent(_plan)


func _abschluss_geprueft() -> bool:
	return _kassenkarte_stimmt(_plan, int(zettel.get("regal_stand", 0)))
