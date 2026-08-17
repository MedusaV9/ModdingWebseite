extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W19-Playtest — Flow „Goo und Bye Welle C: Lieferwagen-Story + REHWEI-Rampe“
## (Doc §7.1 + §4.2), kompletter Spieler-Weg: Level/Münzen stagen + Uhr
## pinnen (Determinismus), DLC im Hub ECHT kaufen, GATE-PROBE im Bestell-Sheet
## (Laden-Level 1: ehrlicher Hinweis, KEIN Kauf-Knopf), Laden-Level ehrlich
## auf 5 stagen (Umsatz-Zettel = Zustands-Prüfung), Firmenwagen kaufen
## (Münz-Gegenprobe 1500), Übergabe-Karte + Van-Vorfahrt, Kofferraum 0/48,
## kleine Bestellung startet eine Fahrt (die gepinnte Uhr hält sie ehrlich
## „unterwegs“), dann Heimweg + Stadtreise zu REHWEI: die Händler-Rampe
## zeigt Lieferwagen + Kisten GENAU WEIL die Fahrt läuft.
## Aufruf: tools/ci/run_playtest.sh flow_w19_goobye_lieferwagen

const START_MUENZEN := 6000

## Münzstand für die Gegenproben (DLC-Kauf / Lieferwagen-Kauf).
var _muenzen_vorher := -1


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
	liste.append_array(_schritte_dlc_kauf())
	liste.append_array(_schritte_gate_probe())
	liste.append_array(_schritte_lieferwagen_kauf())
	liste.append_array(_schritte_fahrt_starten())
	liste.append_array(_schritte_rehwei_rampe())
	return liste


## Staging (dokumentierter Test-Griff, Muster flow_w19_goobye_grossmarkt):
## Level/Münzen setzen und die Uhr auf JETZT pinnen — die spätere Fahrt
## bleibt dadurch deterministisch „unterwegs“, egal wie lange die
## Stadt-Reise zur Rampe dauert.
func stage_und_uhr_pinnen() -> bool:
	if not stage_level_muenzen(12, START_MUENZEN):
		return false
	var gs := game_state()
	gs.clock.pin(int(gs.clock.now_ms()))
	return true


## Echter DLC-Kauf über das Angebot-Sheet (Muster flow_w19_goobye_grossmarkt).
func _schritte_dlc_kauf() -> Array[Dictionary]:
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


## Gate-Probe (§7.1): auf Laden-Level 1 zeigt das Bestell-Sheet den
## EHRLICHEN Hinweis mit dem aktuellen Level — und keinen Kauf-Knopf.
func _schritte_gate_probe() -> Array[Dictionary]:
	return [
		{
			"name": "sheet_fuer_gate_probe",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"text": "Großmarkt-Bestellung"},
			"timeout_s": 30.0,
		},
		{
			"name": "gate_hinweis_level1",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _label_enthaelt("LieferwagenGate", "Level 1"),
			"timeout_s": 10.0,
		},
		{
			"name": "kein_kauf_knopf_unter_level5",
			"aktion": "tue",
			"funktion": func() -> bool: return _finde("LieferwagenKaufen") == null,
			"erwartung": "Unter Level 5 gibt es KEINEN Lieferwagen-Kauf-Knopf",
		},
		schritt_sheet_schliessen("gate_sheet_zu"),
		{
			"name": "staging_laden_level5",
			"aktion": "tue",
			"funktion": stage_laden_level5,
			"erwartung": "Umsatz-Zettel auf Level-5-Schwellen gestellt (Zustands-Prüfung)",
		},
	]


## Kauf + Story-Beat: Münz-Gegenprobe, Übergabe-Karte, Van-Vorfahrt.
func _schritte_lieferwagen_kauf() -> Array[Dictionary]:
	return [
		{
			"name": "sheet_fuer_kauf",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"text": "Großmarkt-Bestellung"},
			"timeout_s": 30.0,
		},
		{
			"name": "kauf_knopf_ab_level5",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _finde("LieferwagenKaufen") != null,
			"timeout_s": 10.0,
		},
		{
			"name": "lieferwagen_muenzen_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand vor dem Lieferwagen-Kauf notiert",
		},
		{
			"name": "lieferwagen_kaufen",
			"aktion": "tipp_name",
			"node": "LieferwagenKaufen",
			"erwarte": {"text": "Der Firmenwagen!"},
			"timeout_s": 30.0,
		},
		{
			"name": "lieferwagen_preis_abgebucht",
			"aktion": "tue",
			"funktion": func() -> bool: return abgebucht(GoobyeTransport.LIEFERWAGEN_PREIS),
			"erwartung": "Genau der Lieferwagen-Preis (1500) wurde abgebucht",
		},
		{
			"name": "van_faehrt_vor",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _finde("GoobyeLieferwagen") != null,
			"timeout_s": 10.0,
		},
		{"name": "uebergabe_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "uebergabe_danke",
			"aktion": "tipp_name",
			"node": "UebergabeWeiter",
			"erwarte": {"weg_text": "Der Firmenwagen!"},
			"timeout_s": 30.0,
		},
	]


## Kleine Bestellung: der 48er-Kofferraum steht im Sheet, 2 Kisten reichen —
## die gepinnte Uhr hält die Fahrt für den Rampen-Beweis „unterwegs“.
func _schritte_fahrt_starten() -> Array[Dictionary]:
	return [
		{
			"name": "sheet_fuer_bestellung",
			"aktion": "tipp_name",
			"node": "Grossmarkt",
			"erwarte": {"text": "Großmarkt-Bestellung"},
			"timeout_s": 30.0,
		},
		{
			"name": "kofferraum_48",
			"aktion": "warte_bis",
			"bedingung": func() -> bool: return _label_enthaelt("KofferraumZeile", "0/48"),
			"timeout_s": 10.0,
		},
		{
			"name": "apfel_einblenden",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("Plus_apple"),
			"erwartung": "Apfel-Zeile liegt im Bestell-Sheet sichtbar",
		},
		{
			"name": "apfel_plus_1",
			"aktion": "tipp_name",
			"node": "Plus_apple",
			"erwarte": {"bedingung": korb_hat.bind("apple", 1)},
			"timeout_s": 20.0,
		},
		{
			"name": "apfel_plus_2",
			"aktion": "tipp_name",
			"node": "Plus_apple",
			"erwarte": {"bedingung": korb_hat.bind("apple", 2)},
			"timeout_s": 20.0,
		},
		{
			"name": "losfahren",
			"aktion": "tipp_name",
			"node": "Losfahren",
			"erwarte": {"bedingung": fahrt_unterwegs},
			"timeout_s": 30.0,
		},
	]


## Heimweg + Stadtreise: die REHWEI-Rampe zeigt Lieferwagen + Kisten,
## WEIL die Fahrt läuft (reine Funktion des Save-Stands).
func _schritte_rehwei_rampe() -> Array[Dictionary]:
	return [
		# WICHTIG: auf die ANKUNFT in der Bibliothek warten (route wartet
		# auch auf "Router nicht busy") — ein weg_text wäre schon WÄHREND
		# des Reise-Veils wahr und der nächste Tap fiele in den _busy-Guard
		# von SceneRouter.handle_back_request (Tap verpufft, Befund W19-C).
		{
			"name": "laden_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"route": "dlc"},
			"timeout_s": 90.0,
		},
		{
			"name": "bibliothek_zurueck",
			"aktion": "tipp_name",
			"node": "Zurueck",
			"erwarte": {"route": "home/living"},
			"timeout_s": 90.0,
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren",
			"aktion": "tue",
			"funktion": fahre_vor,
			"erwartung": "Auto steht am REHWEI-Parkplatz",
		},
		{
			"name": "rehwei_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/rehwei"},
			"timeout_s": 120.0,
		},
		{"name": "laden_ankommen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "fahrt_laeuft_noch",
			"aktion": "tue",
			"funktion": fahrt_unterwegs,
			"erwartung": "Die Großmarkt-Fahrt läuft weiter (gepinnte Uhr)",
		},
		{
			"name": "rampe_zeigt_lieferwagen",
			"aktion": "warte_bis",
			"bedingung": rampe_sichtbar,
			"timeout_s": 15.0,
		},
		{
			"name": "rolltor_ecke_steht",
			"aktion": "tue",
			"funktion": func() -> bool: return _finde("RampenTor") != null,
			"erwartung": "Die Rolltor-Ecke steht als baulicher Anker",
		},
		# Begrüßungs-Bubble durchtippen (Muster flow_w18_rehwei), damit der
		# Beleg-Screenshot freie Sicht auf Rampe + Lieferwagen hat.
		{
			"name": "bubble_zeile_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{"name": "rampe_ansehen", "aktion": "warte", "sekunden": 3.0},
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


## Laden-Level ehrlich auf 5 stellen: der Umsatz-Zettel bekommt GENAU die
## GoobyeLevel-Schwellen (Zustands-Prüfung §7.1 — kein Extra-Schalter).
func stage_laden_level5() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("dlc.goobye.umsatz", {"tage": 14, "gestern": 0, "gesamt": 800})
	return GoobyeLevel.level_fuer(gs) == 5


func _grossmarkt_glue() -> GoobyeLadenGrossmarkt:
	var szene := aktuelle_szene()
	return szene.get("grossmarkt") if szene != null else null


func korb_hat(ware_id: String, menge: int) -> bool:
	var glue := _grossmarkt_glue()
	return glue != null and int(glue.korb.get(ware_id, 0)) == menge


func fahrt_unterwegs() -> bool:
	return not GoobyeTransport.unterwegs_von(game_state()).is_empty()


## Rampen-Beweis: der Fahrt-Container der REHWEI-Szene ist sichtbar.
func rampe_sichtbar() -> bool:
	var szene := aktuelle_szene()
	if not (szene is OrtRehwei):
		return false
	var fahrt: Node3D = (szene as OrtRehwei).rampen_fahrt
	return fahrt != null and fahrt.visible


## Auto an den REHWEI-Parkplatz stellen (Fahr-Skill ist nicht Testziel —
## Muster flow_w18_rehwei.fahre_vor).
func fahre_vor() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	stadt.auto.position = stadt.karte.parkplatz_welt("rehwei")
	stadt.auto.speed = 0.0
	return true


func _finde(node_name: String) -> Node:
	return harness.root.find_child(node_name, true, false)


func _label_enthaelt(node_name: String, teil: String) -> bool:
	var label := _finde(node_name)
	return label is Label and (label as Label).text.contains(teil)
