extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W19-Playtest — Flow „Goo und Bye Welle B: Großmarkt-Fahrt + Tagesangebot
## + Kühl-Kapazität“ (Doc §4.2–§4.4), kompletter Spieler-Weg:
## Level/Münzen stagen + Uhr pinnen (Determinismus), DLC im Hub ECHT kaufen,
## Erstbesuch-Karte, Bestell-Sheet mit ±-Steppern (Kofferraum-Deckel-Probe
## am 12/12-Rand), atomare Bestellung mit Münz-Gegenprobe, Fahrt-Phasen über
## die gepinnte Uhr vorspulen, „Alles ausladen!“, Tagesangebot wählen
## (Kritzel-Schild + Eine-Gruppe-pro-Tag-Block), Regal einräumen bis an die
## KÜHL-GRENZE (8 Stück = 1 Modul), Kühlmodul-Nachkauf (8/16), Markttag MIT
## Angebot (Alwins 9-Uhr-Möhre kostet den −15-%-Angebotspreis), Kassensturz.
## Aufruf: tools/ci/run_playtest.sh flow_w19_goobye_grossmarkt

const START_MUENZEN := 6000
## Bestellung: exakt Kofferraum-Kapazität des Start-Autos (12 Kisten Käse —
## Kühlware, damit die Kühl-Grenze beim Einräumen wirklich erreicht wird).
const KISTEN_BESTELLUNG := 12

## Münzstände für die Gegenproben (Kauf / Bestellung / Modul / Feierabend).
var _muenzen_vorher := -1
var _muenzen_vor_feierabend := -1
var _umsatz_heute := -1
## Korb-Kopie beim Losfahren (Kosten-Gegenprobe rechnet die PURE-Seite nach).
var _korb_kopie: Dictionary = {}


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "staging_level12_uhr_gepinnt",
				"aktion": "tue",
				"funktion": stage_und_uhr_pinnen,
				"erwartung": "Level 12 + %d Münzen gesetzt, Uhr gepinnt" % START_MUENZEN,
			}
		)
	)
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(_schritte_kauf())
	liste.append_array(_schritte_bestellung())
	liste.append_array(_schritte_fahrt_und_ausladen())
	liste.append_array(_schritte_tagesangebot())
	liste.append_array(_schritte_kuehl_grenze())
	liste.append_array(_schritte_markttag_mit_angebot())
	return liste


## Staging (dokumentierter Test-Griff): Level/Münzen setzen und die Uhr auf
## JETZT pinnen — die Fahrt wird später per clock.advance vorgespult, ohne
## dass der Kalendertag kippt (Tagesangebot/Markttag bleiben „heute“).
func stage_und_uhr_pinnen() -> bool:
	if not stage_level_muenzen(12, START_MUENZEN):
		return false
	var gs := game_state()
	gs.clock.pin(int(gs.clock.now_ms()))
	return true


## Echter Kauf über das Angebot-Sheet (Muster flow_w18_goobye_tag).
func _schritte_kauf() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("goo_und_bye", "Schlüssel ansehen"))
	liste.append_array(
		[
			{
				"name": "kauf_muenzen_merken",
				"aktion": "tue",
				"funktion": merke_muenzen,
				"erwartung": "Münzstand vor dem Kauf notiert",
			},
			{
				"name": "angebot_oeffnen",
				"aktion": "tipp_text",
				"text": "Schlüssel ansehen",
				"erwarte": {"text": "Schlüssel übernehmen"},
				"timeout_s": 30.0,
			},
			{
				"name": "schluessel_uebernehmen",
				"aktion": "tipp_text",
				"text": "Schlüssel übernehmen",
				"erwarte": {"route": "dlc/goobye_laden"},
				"timeout_s": 180.0,
			},
			{
				"name": "kaufpreis_abgebucht",
				"aktion": "tue",
				"funktion": func() -> bool: return abgebucht(GoobyeKatalog.preis()),
				"erwartung": "Genau der DLC-Preis (2500) wurde abgebucht",
			},
			{
				"name": "erstbesuch_karte",
				"aktion": "warte_bis",
				"text": "Schlüssel nehmen",
				"timeout_s": 60.0,
			},
			{
				"name": "erstbesuch_weiter",
				"aktion": "tipp_name",
				"node": "IntroWeiter",
				"erwarte": {"weg_text": "Schlüssel nehmen"},
				"timeout_s": 30.0,
			},
		]
	)
	return liste


## Bestell-Sheet (§4.2): Stepper bis an den Kofferraum-Deckel, dann die
## atomare Bestellung mit Münz-Gegenprobe.
func _schritte_bestellung() -> Array[Dictionary]:
	return [
		{
			"name": "grossmarkt_sheet_oeffnen",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"text": "Großmarkt-Bestellung"},
			"timeout_s": 30.0,
		},
		{
			"name": "kofferraum_zeile_leer",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _label_enthaelt("KofferraumZeile", "0/12"),
			"timeout_s": 10.0,
		},
		{
			"name": "kuehl_zeile_start",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _label_enthaelt("KuehlZeile", "0/8"),
			"timeout_s": 10.0,
		},
		{
			"name": "kaese_einblenden",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("Plus_cheese"),
			"erwartung": "Käse-Zeile liegt im Bestell-Sheet sichtbar",
		},
		# Zwei ECHTE Stepper-Taps (Plus), dann ein echter Minus-Tap als
		# Gegenprobe — der Rest läuft über das pressed-Signal derselben
		# Knöpfe (identischer Code-Pfad, spart llvmpipe-Frames).
		{
			"name": "kaese_plus_1",
			"aktion": "tipp_name",
			"node": "Plus_cheese",
			"erwarte": {"bedingung": korb_hat.bind("cheese", 1)},
			"timeout_s": 20.0,
		},
		{
			"name": "kaese_plus_2",
			"aktion": "tipp_name",
			"node": "Plus_cheese",
			"erwarte": {"bedingung": korb_hat.bind("cheese", 2)},
			"timeout_s": 20.0,
		},
		{
			"name": "kaese_minus_1",
			"aktion": "tipp_name",
			"node": "Minus_cheese",
			"erwarte": {"bedingung": korb_hat.bind("cheese", 1)},
			"timeout_s": 20.0,
		},
		{
			"name": "kaese_auf_kapazitaet",
			"aktion": "tue",
			"funktion": stepper_bis.bind("cheese", KISTEN_BESTELLUNG),
			"erwartung": "Korb per Plus-Signal auf 12/12 Kisten Käse gefüllt",
		},
		# Kofferraum-Deckel (§4.2): der 13. Plus-Tap blockt EHRLICH — Toast
		# statt Kiste, der Korb bleibt bei 12.
		{
			"name": "kofferraum_deckel_tap",
			"aktion": "tipp_name",
			"node": "Plus_cheese",
			"erwarte": {"text": "Mehr passt nicht in den Kofferraum"},
			"timeout_s": 15.0,
		},
		{
			"name": "kofferraum_deckel_haelt",
			"aktion": "tue",
			"funktion": korb_hat.bind("cheese", KISTEN_BESTELLUNG),
			"erwartung": "Korb bleibt trotz Deckel-Tap bei 12 Kisten",
		},
		{
			"name": "bestellung_muenzen_merken",
			"aktion": "tue",
			"funktion": merke_muenzen_und_korb,
			"erwartung": "Münzstand + Korb-Kopie vor dem Losfahren notiert",
		},
		{
			"name": "losfahren",
			"aktion": "tipp_name",
			"node": "Losfahren",
			"erwarte": {"bedingung": fahrt_unterwegs},
			"timeout_s": 30.0,
		},
		{
			"name": "bestellkosten_abgebucht",
			"aktion": "tue",
			"funktion": func() -> bool: return abgebucht(GoobyeTransport.kosten(_korb_kopie)),
			"erwartung": "Genau die Bestellkosten (Einkaufspreis × Kisten) sind weg",
		},
	]


## Fahrt-Phasen (fahrer_sim-Zeitmodell) über die gepinnte Uhr vorspulen.
func _schritte_fahrt_und_ausladen() -> Array[Dictionary]:
	return [
		{
			"name": "fahrt_status_hinfahrt",
			"aktion": "warte_bis",
			"text": "Hinfahrt zur Rampe",
			"timeout_s": 20.0,
		},
		{
			"name": "uhr_in_beladen_phase",
			"aktion": "tue",
			"funktion": uhr_vorspulen.bind(GoobyeTransport.HIN_MS + 2_000),
			"erwartung": "Uhr hinter das Hinfahrt-Ende gestellt",
		},
		{
			"name": "fahrt_status_beladen",
			"aktion": "warte_bis",
			"text": "Beladen an der Rampe",
			"timeout_s": 20.0,
		},
		{
			"name": "uhr_hinter_ankunft",
			"aktion": "tue",
			"funktion": uhr_vorspulen.bind(GoobyeTransport.fahrzeit_ms(KISTEN_BESTELLUNG)),
			"erwartung": "Uhr hinter die Ankunft gestellt",
		},
		{
			"name": "ausladen_knopf_da",
			"aktion": "warte_bis",
			"text": "Alles ausladen",
			"timeout_s": 20.0,
		},
		{
			"name": "alles_ausladen",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"bedingung": lager_hat.bind("cheese", 16)},
			"timeout_s": 30.0,
		},
		{
			"name": "fahrt_abgeraeumt",
			"aktion": "tue",
			"funktion": func() -> bool: return not fahrt_unterwegs(),
			"erwartung": "Die Fahrt ist nach dem Ausladen aus dem Save geräumt",
		},
	]


## Tagesangebot (§4.4): Gemüse wählen (Alwins Möhre!), Kritzel-Schild hängt,
## eine ZWEITE Gruppe am selben Tag blockt ehrlich.
func _schritte_tagesangebot() -> Array[Dictionary]:
	return [
		{
			"name": "tagesangebot_sheet",
			"aktion": "tipp_name",
			"node": "Tagesangebot",
			"erwarte": {"text": "Tagesangebot wählen"},
			"timeout_s": 30.0,
		},
		{
			"name": "gemuese_anbieten",
			"aktion": "tipp_name",
			"node": "Angebot_gemuese",
			"erwarte": {"bedingung": angebot_aktiv.bind("gemuese")},
			"timeout_s": 20.0,
		},
		{
			"name": "kritzel_schild_haengt",
			"aktion": "warte_bis",
			"bedingung": schild_haengt,
			"timeout_s": 15.0,
		},
		{
			"name": "tagesangebot_sheet_erneut",
			"aktion": "tipp_name",
			"node": "Tagesangebot",
			"erwarte": {"text": "Heute im Angebot"},
			"timeout_s": 30.0,
		},
		{
			"name": "zweite_gruppe_blockt",
			"aktion": "tipp_name",
			"node": "Angebot_obst",
			"erwarte": {"text": "schon ein Angebot gewählt"},
			"timeout_s": 15.0,
		},
		{
			"name": "angebot_bleibt_gemuese",
			"aktion": "tue",
			"funktion": angebot_aktiv.bind("gemuese"),
			"erwartung": "Die Zweitwahl hat das Tagesangebot NICHT überschrieben",
		},
		schritt_sheet_schliessen("tagesangebot_sheet_zu"),
	]


## Regal füllen bis an die Kühl-Grenze (§4.3): Slot4 bekommt 8 Käse
## (= 1 Modul), der nächste Kühl-Tap blockt, das Nachkauf-Modul hebt die
## Kapazität sichtbar auf 8/16.
func _schritte_kuehl_grenze() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	for i in 4:
		(
			liste
			. append(
				{
					"name": "slot%d_fuellen" % i,
					"aktion": "tipp_name",
					"node": "Slot%d" % i,
					"erwarte": {"bedingung": slot_belegt.bind(i)},
					"timeout_s": 20.0,
				}
			)
		)
	liste.append_array(
		[
			{
				"name": "slot4_kaese_bis_kuehlgrenze",
				"aktion": "tipp_name",
				"node": "Slot4",
				"erwarte": {"bedingung": regal_kuehl_stueck.bind(8)},
				"timeout_s": 20.0,
			},
			{
				"name": "kuehl_grenze_blockt",
				"aktion": "tipp_name",
				"node": "Slot4",
				"erwarte": {"text": "Nicht genug Kühlplatz"},
				"timeout_s": 15.0,
			},
			{
				"name": "kuehl_bleibt_acht",
				"aktion": "tue",
				"funktion": regal_kuehl_stueck.bind(8),
				"erwartung": "Der Grenz-Tap hat KEIN 9. Kühl-Stück eingeräumt",
			},
			{
				"name": "modul_muenzen_merken",
				"aktion": "tue",
				"funktion": merke_muenzen,
				"erwartung": "Münzstand vor dem Modul-Kauf notiert",
			},
			{
				"name": "grossmarkt_sheet_fuer_modul",
				"aktion": "tipp_name",
				"node": "Grossmarkt",
				"erwarte": {"text": "Kühlmodul kaufen"},
				"timeout_s": 30.0,
			},
			{
				"name": "kuehlmodul_kaufen",
				"aktion": "tipp_name",
				"node": "KuehlmodulKaufen",
				"erwarte": {"bedingung": kuehl_module.bind(2)},
				"timeout_s": 20.0,
			},
			{
				"name": "modulpreis_abgebucht",
				"aktion": "tue",
				"funktion": func() -> bool: return abgebucht(GoobyeKuehl.MODUL_PREIS),
				"erwartung": "Genau der Modul-Preis (150) wurde abgebucht",
			},
			{
				"name": "kuehl_zeile_acht_sechzehn",
				"aktion": "warte_bis",
				"bedingung": func() -> bool: return _label_enthaelt("KuehlZeile", "8/16"),
				"timeout_s": 10.0,
			},
			schritt_sheet_schliessen("modul_sheet_zu"),
		]
	)
	return liste


## Markttag MIT Angebot: Alwin (Bon 1) zahlt für die 9-Uhr-Möhre den
## −15-%-Angebotspreis — der deterministische Beweis, dass das Tagesangebot
## im Kundenstrom wirkt. Danach Kassensturz + Feierabend + Raus.
func _schritte_markttag_mit_angebot() -> Array[Dictionary]:
	return [
		{
			"name": "laden_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": laden_ist_offen},
			"timeout_s": 30.0,
		},
		{
			"name": "alwin_moehre_zum_angebotspreis",
			"aktion": "tue",
			"funktion": alwin_zahlt_angebotspreis,
			"erwartung": "Bon 1 = Alwin, Möhre zum Angebotspreis (−15 %)",
		},
		{"name": "kundenstrom_ansehen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "kassensturz_karte",
			"aktion": "warte_bis",
			"text": "Feierabend",
			"timeout_s": 180.0,
		},
		{
			"name": "feierabend_muenzen_merken",
			"aktion": "tue",
			"funktion": merke_vor_feierabend,
			"erwartung": "Münzstand + Tagesumsatz notiert",
		},
		{
			"name": "feierabend_tippen",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"bedingung": umsatz_gutgeschrieben},
			"timeout_s": 30.0,
		},
		{
			"name": "laden_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"weg_text": "Nachschub"},
			"timeout_s": 90.0,
		},
		{"name": "abschluss_ruhe", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------ Helfer


func merke_muenzen() -> bool:
	_muenzen_vorher = muenzstand()
	return _muenzen_vorher >= 0


## Gegenprobe: seit merke_muenzen ging GENAU `betrag` vom Konto.
func abgebucht(betrag: int) -> bool:
	if _muenzen_vorher < 0:
		return false
	var ok := muenzstand() == _muenzen_vorher - betrag
	_muenzen_vorher = -1
	return ok


func merke_muenzen_und_korb() -> bool:
	_korb_kopie = _grossmarkt_glue().korb.duplicate(true)
	return merke_muenzen() and not _korb_kopie.is_empty()


func _grossmarkt_glue() -> GoobyeLadenGrossmarkt:
	var szene := aktuelle_szene()
	return szene.get("grossmarkt") if szene != null else null


func korb_hat(ware_id: String, menge: int) -> bool:
	var glue := _grossmarkt_glue()
	return glue != null and int(glue.korb.get(ware_id, 0)) == menge


## Restliche Plus-Taps über das pressed-Signal DESSELBEN Knopfs (identischer
## Handler-Pfad wie ein Tap; llvmpipe-Frames sind teuer).
func stepper_bis(ware_id: String, ziel: int) -> bool:
	var plus := harness.root.find_child("Plus_" + ware_id, true, false)
	if not (plus is Button):
		return false
	for _i in 32:
		if korb_hat(ware_id, ziel):
			return true
		(plus as Button).pressed.emit()
	return korb_hat(ware_id, ziel)


func fahrt_unterwegs() -> bool:
	return not GoobyeTransport.unterwegs_von(game_state()).is_empty()


## Uhr vorspulen: relativ zur BESTELLZEIT (deterministisch, egal wie lange
## Taps/Screenshots gedauert haben). Ohne Fahrt: einfach ab jetzt.
func uhr_vorspulen(ms_nach_bestellung: int) -> bool:
	var gs := game_state()
	var fahrt := GoobyeTransport.unterwegs_von(gs)
	var basis := int(fahrt.get("bestelltAt", gs.clock.now_ms()))
	gs.clock.pin(basis + ms_nach_bestellung)
	return true


func lager_hat(ware_id: String, mindestens: int) -> bool:
	var lager: Variant = game_state().get_value("dlc.goobye.lager", {})
	return lager is Dictionary and int((lager as Dictionary).get(ware_id, 0)) >= mindestens


func angebot_aktiv(gruppe_id: String) -> bool:
	return GoobyeAngebot.aktive_gruppe_von(game_state()) == gruppe_id


func schild_haengt() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var glue: Variant = szene.get("angebot")
	return glue != null and (glue as GoobyeLadenAngebot).schild != null


func slot_belegt(index: int) -> bool:
	var regal: Variant = aktuelle_szene().get("_regal")
	if not (regal is Dictionary):
		return false
	var slots: Array = (regal as Dictionary).get("slots", [])
	if index >= slots.size():
		return false
	return int((slots[index] as Dictionary).get("menge", 0)) > 0


func regal_kuehl_stueck(erwartet: int) -> bool:
	var regal: Variant = aktuelle_szene().get("_regal")
	return regal is Dictionary and GoobyeKuehl.kuehl_stueck(regal) == erwartet


func kuehl_module(erwartet: int) -> bool:
	return GoobyeKuehl.module_von(game_state()) == erwartet


func laden_ist_offen() -> bool:
	var szene := aktuelle_szene()
	return szene != null and str(szene.get("phase")) == "offen"


## Bon 1 gehört Alwin; seine Möhre kostet GENAU den Angebotspreis (−15 %,
## Gemüse ist Tagesangebot) — und der liegt unter dem Normalpreis.
func alwin_zahlt_angebotspreis() -> bool:
	var plan: Variant = aktuelle_szene().get("_tagesplan")
	if not (plan is Dictionary):
		return false
	var bons: Array = (plan as Dictionary).get("bons", [])
	if bons.is_empty():
		return false
	var bon: Dictionary = bons[0]
	if str(bon.get("archetyp", "")) != "alwin":
		return false
	var moehre := GoobyeKatalog.ware("carrot")
	var angebots_preis := GoobyeAngebot.angebots_preis(moehre)
	if angebots_preis >= GoobyePreis.verkaufspreis(moehre):
		return false
	for position: Variant in bon.get("positionen", []):
		if position is Dictionary and str((position as Dictionary).get("ware", "")) == "carrot":
			return int((position as Dictionary).get("preis", -1)) == angebots_preis
	return false


func merke_vor_feierabend() -> bool:
	_muenzen_vor_feierabend = muenzstand()
	_umsatz_heute = int(aktuelle_szene().get("umsatz_heute"))
	return _muenzen_vor_feierabend >= 0 and _umsatz_heute >= 0


func umsatz_gutgeschrieben() -> bool:
	if _muenzen_vor_feierabend < 0 or _umsatz_heute < 0:
		return false
	return muenzstand() == _muenzen_vor_feierabend + _umsatz_heute


func _label_enthaelt(node_name: String, teil: String) -> bool:
	var label := harness.root.find_child(node_name, true, false)
	return label is Label and (label as Label).text.contains(teil)
