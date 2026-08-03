extends "res://tests/tools/playtest_flows/flow_ptdlc_basis.gd"
## PT-DLC Flow (d) — GOOBYE BACKSTATION + ALWIN-STREAK über 3 Markttage
## (W18/R3, G8). Tag 1: 2 Ofen-Chargen (je −9 ᴳ = 50 % EK × 3 Brote,
## MEINE Doc-Mathe), Duft an, Markttag mit Alwin-Möhre → Streak 1.
## Tag 2: 3. Charge + TAGESDECKEL-Probe (4. Versuch: Toast, KEINE
## Abbuchung), Backwaren-Schieber auf +30 % (echter Drag), Sonderwunsch-
## Tag (Alwin will ZWEI Möhren) → Streak 2 — und die DUFT-MESSUNG: der
## Flow plant den Tag mit den ECHTEN Statics einmal MIT und einmal OHNE
## duft_gruppe nach; die Szene muss dem MIT-Plan gleichen und der
## Umsatz-Abstand belegt den messbaren Duft-Bonus. Tag 3: Streak 3 →
## Alwin steckt 12 ᴳ zu (Ganztages-Münzcheck: Umsatz + 12 exakt).
##
## Der Ofen-Tagesdeckel klebt am ECHTEN Datum (gs.clock), nicht am
## Feierabend — alle 3 Chargen zählen im selben Lauf auf EINEN Tag,
## deshalb backt Tag 1 zwei und Tag 2 die letzte (Seedsuche-Plan).
##
## Seeds aus flow_ptdlc_seedsuche (alwin_menge 1/2/1, Duft messbar,
## Möhren reichen): A=4 (31 ᴳ, carrot 3/bread 1/apple 1), B=75
## (Sonderwunsch, 34 ᴳ MIT Duft vs 21 OHNE — messbar!), C=3 (29 ᴳ,
## Streak-Belohnung). Alle Soll-Werte entstehen zur LAUFZEIT aus den
## echten Statics — keine abgeschriebenen Goldzahlen.

const SEED_A := 4
const SEED_B := 75
const SEED_C := 3

const MARKT_TEMPO := 0.35
const CHARGEN_TAG1 := 2
const BROT_START := 5
const DUFT_GRUPPE := "backwaren"
const SCHIEBER_FAKTOR := 1.3
const ALWIN_BELOHNUNG := 12

var _zeilen_heute: Array = []
var _plan_heute: Dictionary = {}
var _regal_vor_tag := 0
var _tag3_umsatz := 0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(goobye_kauf_schritte())
	liste.append_array(_tag1_backen_schritte())
	liste.append_array(_tag1_markt_schritte())
	liste.append_array(_tag2_ofen_schritte())
	liste.append_array(_tag2_preis_schritte())
	liste.append_array(_tag2_markt_schritte())
	liste.append_array(_tag3_schritte())
	return liste


## ------------------------------------------------ Tag 1: Ofen anwerfen


func _tag1_backen_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "backen_knopf_preis",
			"aktion": "tue",
			"funktion": _backen_knopf_pruefen,
			"erwartung": "Backen-Knopf nennt MEINE Selbstkosten (9 ᴳ)",
		},
	]
	for i in CHARGEN_TAG1:
		var nr := i + 1
		(
			liste
			. append_array(
				[
					{
						"name": "charge_%d_coins" % nr,
						"aktion": "tue",
						"funktion": merke_coins.bind("charge%d" % nr),
					},
					{
						"name": "charge_%d_backen" % nr,
						"aktion": "tipp_name",
						"node": "Backen",
						"erwarte": {"text": "frisches Brot aus dem Ofen"},
						"timeout_s": 20.0,
					},
					{
						"name": "charge_%d_bezahlt" % nr,
						"aktion": "tue",
						"funktion": _charge_bezahlt.bind("charge%d" % nr, nr),
						"erwartung": "−9 ᴳ exakt, Lager +3 Brot, Chargen-Zähler stimmt",
					},
				]
			)
		)
	(
		liste
		. append(
			{
				"name": "duft_aktiv",
				"aktion": "tue",
				"funktion": _duft_aktiv_pruefen,
				"erwartung": "GoobyeBackofen.duft_aktiv == true nach der 1. Charge",
			}
		)
	)
	return liste


func _tag1_markt_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "slot_0_apfel",
			"aktion": "tipp_name",
			"node": "Slot0",
			"erwarte": {"bedingung": _slot_zeigt.bind(0, 6)},
			"timeout_s": 20.0,
		},
		{
			"name": "slot_1_moehren",
			"aktion": "tipp_name",
			"node": "Slot1",
			"erwarte": {"bedingung": _slot_zeigt.bind(1, 8)},
			"timeout_s": 20.0,
		},
		# Brot-Lager 5 + 6 = 11 → Slot-Deckel 8 greift (Rest 3 im Lager).
		{
			"name": "slot_2_brot",
			"aktion": "tipp_name",
			"node": "Slot2",
			"erwarte": {"bedingung": _slot_zeigt.bind(2, 8)},
			"timeout_s": 20.0,
		},
		{"name": "seed_a", "aktion": "tue", "funktion": szene_prop.bind("seed_override", SEED_A)},
		{"name": "tag1_sortiment", "aktion": "tue", "funktion": _sortiment_merken},
		{"name": "tag1_coins", "aktion": "tue", "funktion": merke_coins.bind("tag1")},
		{
			"name": "tag1_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": _phase_ist.bind("offen")},
			"timeout_s": 20.0,
		},
		{
			"name": "tag1_alwin_spruch",
			"aktion": "warte_bis",
			"text": "Onkel Alwin",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "tag1_tempo", "aktion": "tue", "funktion": szene_prop.bind("tempo", MARKT_TEMPO)},
		{
			"name": "tag1_plan_wie_statics",
			"aktion": "tue",
			"funktion": _plan_gegen_statics.bind(SEED_A, false),
			"erwartung": "Szene-Plan == echtes tag_planen MIT Duft (Verdrahtungs-Beweis)",
		},
		{
			"name": "tag1_durch",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 300.0,
		},
		{
			"name": "tag1_karte",
			"aktion": "tue",
			"funktion": _karte_stimmt,
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
			"name": "tag1_streak_1",
			"aktion": "tue",
			"funktion": _streak_ist.bind(1, 1),
			"erwartung": "Alwin-Streak 1 nach Tag 1 (Möhre bekommen)",
		},
	]


## ------------------------------ Tag 2: letzte Charge + Tagesdeckel-Probe


func _tag2_ofen_schritte() -> Array[Dictionary]:
	return [
		{"name": "charge_3_coins", "aktion": "tue", "funktion": merke_coins.bind("charge3")},
		{
			"name": "charge_3_backen",
			"aktion": "tipp_name",
			"node": "Backen",
			"erwarte": {"text": "frisches Brot aus dem Ofen"},
			"timeout_s": 20.0,
		},
		{
			"name": "charge_3_bezahlt",
			"aktion": "tue",
			"funktion": _charge_bezahlt.bind("charge3", 3),
			"erwartung": "Auch Charge 3: −9 ᴳ exakt, Lager +3",
		},
		{"name": "deckel_coins", "aktion": "tue", "funktion": merke_coins.bind("deckel")},
		{"name": "deckel_lager", "aktion": "tue", "funktion": _lager_merken_deckel},
		# Tagesdeckel: die 4. Charge MUSS freundlich abblitzen (kein Kauf).
		{
			"name": "deckel_vierte_charge",
			"aktion": "tipp_name",
			"node": "Backen",
			"erwarte": {"text": "Der Ofen hat für heute Feierabend"},
			"timeout_s": 20.0,
		},
		{
			"name": "deckel_nichts_passiert",
			"aktion": "tue",
			"funktion": _deckel_geprueft,
			"erwartung": "4. Charge: 0 ᴳ abgebucht, Lager unverändert, Chargen bleiben 3",
		},
	]


func _tag2_preis_schritte() -> Array[Dictionary]:
	return [
		{"name": "preise_oeffnen", "aktion": "tipp_name", "node": "Preise", "timeout_s": 20.0},
		{
			"name": "preis_sheet_da",
			"aktion": "warte_bis",
			"text": "Preise am Regal",
			"timeout_s": 20.0,
		},
		{
			"name": "schieber_ins_bild",
			"aktion": "tue",
			"funktion": rolle_zu.bind("Schieber_" + DUFT_GRUPPE),
		},
		{"name": "schieber_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "backwaren_hochgezogen",
			"aktion": "wisch",
			"von_funktion": schieber_punkt.bind(DUFT_GRUPPE, 0.0),
			"nach_funktion": schieber_punkt.bind(DUFT_GRUPPE, 0.55),
			"dauer_s": 0.8,
			"erwarte": {"bedingung": _faktor_ist.bind(DUFT_GRUPPE, SCHIEBER_FAKTOR)},
			"timeout_s": 15.0,
		},
		# Backdrop-Tipp statt Runter-Wisch (Befund pt2_c4: Wische scrollen).
		{
			"name": "sheet_zu",
			"aktion": "tipp_pos",
			"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
			"pflicht": false,
		},
		{"name": "sheet_zu_warten", "aktion": "warte", "sekunden": 1.5},
	]


func _tag2_markt_schritte() -> Array[Dictionary]:
	return [
		# Nur Slot 2 (Brot) auf 8 nachfüllen — Äpfel/Möhren bleiben auf
		# Rest (exakt das Regal der Seed-Suche für Tag B).
		{
			"name": "slot_2_nachgefuellt",
			"aktion": "tipp_name",
			"node": "Slot2",
			"erwarte": {"bedingung": _slot_zeigt.bind(2, 8)},
			"timeout_s": 20.0,
		},
		{"name": "seed_b", "aktion": "tue", "funktion": szene_prop.bind("seed_override", SEED_B)},
		{"name": "tag2_tempo_normal", "aktion": "tue", "funktion": szene_prop.bind("tempo", 1.0)},
		{"name": "tag2_sortiment", "aktion": "tue", "funktion": _sortiment_merken},
		{"name": "tag2_coins", "aktion": "tue", "funktion": merke_coins.bind("tag2")},
		{
			"name": "tag2_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": _phase_ist.bind("offen")},
			"timeout_s": 20.0,
		},
		# Sonderwunsch-Gag sichtbar? (Blase steht 5 s bei tempo 1.0.)
		{
			"name": "tag2_zwei_moehren_blase",
			"aktion": "warte_bis",
			"text": "ZWEI Möhren",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "tag2_tempo", "aktion": "tue", "funktion": szene_prop.bind("tempo", MARKT_TEMPO)},
		{
			"name": "tag2_duft_messung",
			"aktion": "tue",
			"funktion": _plan_gegen_statics.bind(SEED_B, true),
			"erwartung": "Szene == MIT-Duft-Plan UND Umsatz MIT > OHNE (messbar!)",
		},
		{
			"name": "tag2_sonderwunsch_bon",
			"aktion": "tue",
			"funktion": _sonderwunsch_geprueft,
			"erwartung": "Alwin-Bon trägt 2 Möhren-Positionen (alwin_menge == 2)",
		},
		{
			"name": "tag2_durch",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 300.0,
		},
		{
			"name": "tag2_karte",
			"aktion": "tue",
			"funktion": _karte_stimmt,
			"erwartung": "Kassensturz Tag 2 == Plan",
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
			"name": "tag2_streak_2",
			"aktion": "tue",
			"funktion": _streak_ist.bind(2, 2),
			"erwartung": "Alwin-Streak 2 nach dem Sonderwunsch-Tag",
		},
	]


## ---------------------------------- Tag 3: Streak-Belohnung (+12 exakt)


func _tag3_schritte() -> Array[Dictionary]:
	return [
		{"name": "seed_c", "aktion": "tue", "funktion": szene_prop.bind("seed_override", SEED_C)},
		{"name": "tag3_tempo_normal", "aktion": "tue", "funktion": szene_prop.bind("tempo", 1.0)},
		{"name": "tag3_sortiment", "aktion": "tue", "funktion": _sortiment_merken},
		{"name": "tag3_coins", "aktion": "tue", "funktion": merke_coins.bind("tag3")},
		{
			"name": "tag3_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": _phase_ist.bind("offen")},
			"timeout_s": 20.0,
		},
		# Belohnungs-Toast beim Alwin-Kassenmoment (streak 3 → 12 ᴳ).
		{
			"name": "tag3_belohnung_toast",
			"aktion": "warte_bis",
			"text": "Alwin-Streak 3",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{"name": "tag3_tempo", "aktion": "tue", "funktion": szene_prop.bind("tempo", MARKT_TEMPO)},
		{
			"name": "tag3_plan_wie_statics",
			"aktion": "tue",
			"funktion": _plan_gegen_statics.bind(SEED_C, false),
			"erwartung": "Auch Tag 3 plant exakt wie die echten Statics (Duft an)",
		},
		{
			"name": "tag3_durch",
			"aktion": "warte_bis",
			"bedingung": control_da.bind("Feierabend"),
			"timeout_s": 300.0,
		},
		{
			"name": "tag3_karte",
			"aktion": "tue",
			"funktion": _karte_stimmt,
			"erwartung": "Kassensturz Tag 3 == Plan",
		},
		{"name": "tag3_umsatz_notiert", "aktion": "tue", "funktion": _tag3_umsatz_merken},
		{
			"name": "tag3_feierabend",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"weg_text": "Kassensturz!"},
			"timeout_s": 30.0,
		},
		{
			"name": "tag3_streak_3_belohnt",
			"aktion": "tue",
			"funktion": _streak_ist.bind(3, 3),
			"erwartung": "Alwin-Streak 3 (Belohnungs-Tag) im Save",
		},
		{
			"name": "tag3_muenzen_mit_trinkgeld",
			"aktion": "tue",
			"funktion": _tag3_gebucht,
			"erwartung": "Ganztages-Delta == Umsatz + 12 ᴳ Alwin-Trinkgeld EXAKT",
		},
		{"name": "streak_fertig", "aktion": "warte", "sekunden": 2.0},
	]


## ---------------------------------------------------------------- Helfer


## Backen-Knopf-Beschriftung gegen MEINE Selbstkosten-Mathe halten.
func _backen_knopf_pruefen() -> bool:
	var soll := I18nService.t("dlc_goobye.laden.backen", {"preis": mein_backen_kosten()})
	var ist := label_text("Backen")
	print(
		(
			"[PTDLC] Backen-Knopf: '%s' (soll '%s', meine Kosten %d)"
			% [ist, soll, mein_backen_kosten()]
		)
	)
	return ist == soll


## Nach einer Charge: Münzen −Kosten, Lager-Brot +3, Chargen-Zähler == nr.
func _charge_bezahlt(marke: String, nr: int) -> bool:
	if not pruefe_coins_delta(marke, -mein_backen_kosten()):
		return false
	var brot_soll := BROT_START + nr * BROT_JE_CHARGE
	var brot_ist := int(gs_lager().get("bread", 0))
	var chargen := _chargen_heute()
	print(
		(
			"[PTDLC] Charge %d: Lager-Brot %d (soll %d), Chargen heute %d"
			% [nr, brot_ist, brot_soll, chargen]
		)
	)
	return brot_ist == brot_soll and chargen == nr


func _chargen_heute() -> int:
	var szene := laden_szene()
	var gs := game_state()
	if szene == null or gs == null:
		return -1
	return GoobyeBackofen.chargen_heute(gs, str(szene.call("_tag_key")))


func _duft_aktiv_pruefen() -> bool:
	var szene := laden_szene()
	var gs := game_state()
	if szene == null or gs == null:
		return false
	var duft := GoobyeBackofen.duft_aktiv(gs, str(szene.call("_tag_key")))
	print("[PTDLC] Duft aktiv: %s" % str(duft))
	return duft


func _slot_zeigt(idx: int, menge: int) -> bool:
	return label_text("Slot%d" % idx) == "×%d" % menge


## Regal-Zeilen + Faktoren VOR der Öffnung einfrieren (exakt der
## Szenen-Codepfad: GoobyeRegal.sortiment_von + GoobyePreis.ware_faktoren).
func _sortiment_merken() -> bool:
	var szene := laden_szene()
	var gs := game_state()
	if szene == null or gs == null:
		return false
	var regal: Dictionary = szene.get("_regal")
	var faktoren := GoobyePreis.ware_faktoren(GoobyeState.preise_von(gs))
	_zeilen_heute = GoobyeRegal.sortiment_von(regal, faktoren)
	_regal_vor_tag = _regal_stand()
	print(
		"[PTDLC] Sortiment vor Öffnung: %s (Regal %d Stück)" % [str(_zeilen_heute), _regal_vor_tag]
	)
	return not _zeilen_heute.is_empty()


## Szene-Plan gegen die ECHTEN Statics: MIT Duft muss er GLEICH sein;
## bei streng == true muss der OHNE-Duft-Umsatz strikt kleiner sein
## (der messbare Duft-Bonus der Backstation).
func _plan_gegen_statics(seed_wert: int, streng: bool) -> bool:
	_plan_heute = _plan_kopie()
	if not _plan_konsistent(_plan_heute):
		return false
	var basis := {
		"kunden_min": 2,
		"kunden_max": 3,
		"trend_gruppe": GoobyeMarkttag.tagestrend(seed_wert),
		"alwin_menge": GoobyeMarkttag.alwin_menge(seed_wert),
	}
	var mit_opt := basis.duplicate(true)
	mit_opt["duft_gruppe"] = DUFT_GRUPPE
	var ohne_opt := basis.duplicate(true)
	ohne_opt["duft_gruppe"] = ""
	var mit := GoobyeMarkttag.tag_planen(seed_wert, _zeilen_heute, mit_opt)
	var ohne := GoobyeMarkttag.tag_planen(seed_wert, _zeilen_heute, ohne_opt)
	print(
		(
			"[PTDLC] Duft-Messung Seed %d: MIT %d ᴳ %s vs OHNE %d ᴳ %s"
			% [
				seed_wert,
				int(mit.get("umsatz", 0)),
				str(mit.get("verkauft", {})),
				int(ohne.get("umsatz", 0)),
				str(ohne.get("verkauft", {})),
			]
		)
	)
	var gleich := (
		int(_plan_heute.get("umsatz", -1)) == int(mit.get("umsatz", -2))
		and int(_plan_heute.get("kundenzahl", -1)) == int(mit.get("kundenzahl", -2))
		and (
			(_plan_heute.get("verkauft", {}) as Dictionary)
			== (mit.get("verkauft", {}) as Dictionary)
		)
	)
	if not gleich:
		print("[PTDLC] Szene-Plan weicht vom MIT-Duft-Plan ab!")
		return false
	if streng and int(mit.get("umsatz", 0)) <= int(ohne.get("umsatz", 0)):
		print("[PTDLC] Duft-Bonus NICHT messbar (mit <= ohne)!")
		return false
	return true


## Alwins Bon am Sonderwunsch-Tag: GENAU 2 Möhren-Positionen.
func _sonderwunsch_geprueft() -> bool:
	var bons: Array = _plan_heute.get("bons", [])
	if bons.is_empty():
		return false
	var alwin: Dictionary = bons[0]
	if str(alwin.get("archetyp", "")) != GoobyeMarkttag.ARCHETYP_ALWIN:
		print("[PTDLC] Kunde 0 ist nicht Alwin?!")
		return false
	var moehren := 0
	for position: Dictionary in alwin.get("positionen", []):
		if str(position.get("ware", "")) == "carrot":
			moehren += 1
	print("[PTDLC] Alwin-Bon Tag 2: %d Möhren-Positionen" % moehren)
	return moehren == 2


func _karte_stimmt() -> bool:
	return _kassenkarte_stimmt(_plan_heute, _regal_vor_tag)


func _streak_ist(streak: int, bedient: int) -> bool:
	var stand := _alwin_stand()
	print("[PTDLC] Alwin-Stand: %s (soll streak %d, bedient %d)" % [str(stand), streak, bedient])
	return int(stand.get("streak", -1)) == streak and int(stand.get("bedientGesamt", -1)) == bedient


func _lager_merken_deckel() -> bool:
	zettel["deckel_brot"] = int(gs_lager().get("bread", 0))
	return true


## Tagesdeckel-Probe: 4. Charge bucht NICHTS (Münzen, Lager, Zähler).
func _deckel_geprueft() -> bool:
	if not pruefe_coins_delta("deckel", 0):
		return false
	var brot := int(gs_lager().get("bread", 0))
	var chargen := _chargen_heute()
	print(
		(
			"[PTDLC] Nach Deckel-Versuch: Brot %d (soll %d), Chargen %d (soll 3)"
			% [brot, int(zettel.get("deckel_brot", -1)), chargen]
		)
	)
	return brot == int(zettel.get("deckel_brot", -1)) and chargen == 3


func _tag3_umsatz_merken() -> bool:
	var szene := laden_szene()
	if szene == null:
		return false
	_tag3_umsatz = int(szene.get("umsatz_heute"))
	print("[PTDLC] Tag-3-Umsatz auf der Karte: %d" % _tag3_umsatz)
	return _tag3_umsatz >= 0


## Ganztages-Delta Tag 3 == Umsatz + 12 (Belohnung wird beim KASSIEREN
## gebucht, der Umsatz erst beim Feierabend — beides zusammen exakt).
func _tag3_gebucht() -> bool:
	return pruefe_coins_delta("tag3", _tag3_umsatz + ALWIN_BELOHNUNG)
