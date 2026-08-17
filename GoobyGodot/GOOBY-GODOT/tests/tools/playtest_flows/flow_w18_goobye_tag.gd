extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W18/3-Playtest (Agent 5) — Flow „Goo und Bye: Kauf + kompletter
## Tag-Loop“: Level/Münzen stagen, DLC im Hub ECHT kaufen (Schlüssel
## übernehmen → Münzabbuchung prüfen), Erstbesuch-Story-Karte, Nachschub
## kaufen (inkl. Möhre für Onkel Alwins 9-Uhr-Möhre), Regal-Slots
## einräumen (neue CC0-Regale/Slot-Anker im Bild), Laden öffnen, den
## Kundenstrom (Alwin zuerst!) begleiten, Kassensturz-Karte + Feierabend
## mit Münz-Gegenprobe, Regal-Reste-Tag-2-Start und „‹ Raus“.
## Aufruf: tools/ci/run_playtest.sh flow_w18_goobye_tag

const START_MUENZEN := 6000

## Münzstände für die Gegenproben (Kauf / Kassensturz).
var _muenzen_vor_kauf := -1
var _muenzen_vor_feierabend := -1
var _umsatz_heute := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "staging_level12_reich",
				"aktion": "tue",
				"funktion": stage_level_muenzen.bind(12, START_MUENZEN),
				"erwartung": "Level 12 + %d Münzen gesetzt (Staging)" % START_MUENZEN,
			}
		)
	)
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(_schritte_kauf())
	liste.append_array(_schritte_intro_und_nachschub())
	liste.append_array(_schritte_einraeumen())
	liste.append_array(_schritte_markttag())
	liste.append_array(_schritte_feierabend())
	return liste


## Echter Kauf über das Angebot-Sheet — danach reist der Laden selbst an.
func _schritte_kauf() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("goo_und_bye", "Schlüssel ansehen"))
	(
		liste
		. append_array(
			[
				{
					"name": "kauf_muenzen_merken",
					"aktion": "tue",
					"funktion": merke_muenzen_vor_kauf,
					"erwartung": "Münzstand vor dem Kauf notiert",
				},
				{
					"name": "angebot_oeffnen",
					"aktion": "tipp_text",
					"text": "Schlüssel ansehen",
					"erwarte": {"text": "Schlüssel übernehmen"},
					"timeout_s": 30.0,
				},
				{"name": "angebot_ansehen", "aktion": "warte", "sekunden": 1.5},
				# BEFUND B4 GEFIXT (W18/4): der Kauf-Knopf sitzt gepinnt im
				# Blatt-Fuß — der frühere Scroll-Workaround ist RAUS, der
				# direkte Tipp beweist den echten Weg.
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
					"funktion": kaufpreis_verbucht,
					"erwartung": "Genau der DLC-Preis wurde abgebucht (2500)",
				},
			]
		)
	)
	return liste


func _schritte_intro_und_nachschub() -> Array[Dictionary]:
	return [
		{
			"name": "erstbesuch_karte",
			"aktion": "warte_bis",
			"text": "Schlüssel nehmen",
			"timeout_s": 60.0,
		},
		{"name": "erstbesuch_lesen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "erstbesuch_weiter",
			"aktion": "tipp_name",
			"node": "IntroWeiter",
			"erwarte": {"weg_text": "Schlüssel nehmen"},
			"timeout_s": 30.0,
		},
		{"name": "laden_leer_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "nachschub_oeffnen",
			"aktion": "tipp_name",
			"node": "Nachschub",
			"erwarte": {"text": "Nachschub bestellen"},
			"timeout_s": 30.0,
		},
		{
			"name": "moehre_einblenden",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("Nachschub_carrot"),
			"erwartung": "Möhren-Zeile liegt im Nachschub-Sheet sichtbar",
		},
		{"name": "nachschub_ruhe", "aktion": "warte", "sekunden": 1.0},
		# Startlager (Katalog `start`): apple 6 · carrot 8 · bread 5 ·
		# cookie 5 · cheese 4 · gb_hoppel_pops 4 — die Käufe prüfen darum
		# ABSOLUTE Stände (8→9→10 bzw. 6→7→8), nicht bloß „existiert“.
		{
			"name": "moehre_kaufen_1",
			"aktion": "tipp_name",
			"node": "Nachschub_carrot",
			"erwarte": {"bedingung": lager_hat.bind("carrot", 9)},
			"timeout_s": 20.0,
		},
		{
			"name": "moehre_kaufen_2",
			"aktion": "tipp_name",
			"node": "Nachschub_carrot",
			"erwarte": {"bedingung": lager_hat.bind("carrot", 10)},
			"timeout_s": 20.0,
		},
		{
			"name": "apfel_einblenden",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("Nachschub_apple"),
			"erwartung": "Apfel-Zeile liegt im Nachschub-Sheet sichtbar",
		},
		{
			"name": "apfel_kaufen_1",
			"aktion": "tipp_name",
			"node": "Nachschub_apple",
			"erwarte": {"bedingung": lager_hat.bind("apple", 7)},
			"timeout_s": 20.0,
		},
		{
			"name": "apfel_kaufen_2",
			"aktion": "tipp_name",
			"node": "Nachschub_apple",
			"erwarte": {"bedingung": lager_hat.bind("apple", 8)},
			"timeout_s": 20.0,
		},
		schritt_sheet_schliessen("nachschub_sheet_zu"),
		{"name": "nachschub_zu_ruhe", "aktion": "warte", "sekunden": 1.0},
	]


## Slots von links füllen (erste Lager-Ware in Katalog-Reihenfolge, je
## Slot max. 8): Slot0 zieht die 8 Äpfel leer, Slot1 nimmt 8 der 10
## Möhren, Slot2 die 2 REST-Möhren (Katalog-Reihenfolge zieht die Ware
## leer, bevor die nächste dran ist — Lauf w18a5_goobye2, Screenshot 048).
func _schritte_einraeumen() -> Array[Dictionary]:
	return [
		{
			"name": "slot0_fuellen",
			"aktion": "tipp_name",
			"node": "Slot0",
			"erwarte": {"bedingung": regal_hat.bind("apple")},
			"timeout_s": 20.0,
		},
		{
			"name": "slot1_fuellen",
			"aktion": "tipp_name",
			"node": "Slot1",
			"erwarte": {"bedingung": regal_hat.bind("carrot")},
			"timeout_s": 20.0,
		},
		{
			"name": "slot2_fuellen_rest",
			"aktion": "tipp_name",
			"node": "Slot2",
			"erwarte": {"bedingung": slot_belegt.bind(2)},
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{"name": "regal_ansehen", "aktion": "warte", "sekunden": 2.0},
	]


func _schritte_markttag() -> Array[Dictionary]:
	return [
		{
			"name": "laden_oeffnen",
			"aktion": "tipp_name",
			"node": "LadenOeffnen",
			"erwarte": {"bedingung": laden_ist_offen},
			"timeout_s": 30.0,
		},
		{
			"name": "alwin_ist_erster_kunde",
			"aktion": "tue",
			"funktion": alwin_zuerst_mit_moehre,
			"erwartung": "Bon 1 = Onkel Alwin (9-Uhr-Möhre, ware carrot)",
		},
		{"name": "kunde_alwin_laeuft", "aktion": "warte", "sekunden": 4.0},
		{"name": "kunde_alwin_kasse", "aktion": "warte", "sekunden": 4.0},
		{"name": "kundenstrom_mitte", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "kassensturz_karte",
			"aktion": "warte_bis",
			"text": "Feierabend",
			"timeout_s": 180.0,
		},
		{"name": "kassensturz_zaehlt_hoch", "aktion": "warte", "sekunden": 2.5},
	]


func _schritte_feierabend() -> Array[Dictionary]:
	return [
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
		{"name": "tag2_einraeumen_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "laden_verlassen",
			"aktion": "tipp_name",
			"node": "Verlassen",
			"erwarte": {"weg_text": "Nachschub"},
			"timeout_s": 90.0,
		},
		{"name": "abschluss_ruhe", "aktion": "warte", "sekunden": 2.0},
	]


func merke_muenzen_vor_kauf() -> bool:
	_muenzen_vor_kauf = muenzstand()
	return _muenzen_vor_kauf >= 0


## Progression-Wache: exakt der Katalog-Preis (2500) ging vom Konto.
func kaufpreis_verbucht() -> bool:
	if _muenzen_vor_kauf < 0:
		return false
	return muenzstand() == _muenzen_vor_kauf - GoobyeKatalog.preis()


## Lager-Bestand einer Ware im Save (Nachschub-Gegenprobe).
func lager_hat(ware_id: String, mindestens: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var lager: Variant = gs.get_value("dlc.goobye.lager", {})
	return lager is Dictionary and int((lager as Dictionary).get(ware_id, 0)) >= mindestens


## Regal-Gegenprobe direkt an der Szene (private Sicht — Test-Staging).
func regal_hat(ware_id: String) -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var regal: Variant = szene.get("_regal")
	if not (regal is Dictionary):
		return false
	for slot: Variant in (regal as Dictionary).get("slots", []):
		if slot is Dictionary and str((slot as Dictionary).get("ware", "")) == ware_id:
			return int((slot as Dictionary).get("menge", 0)) > 0
	return false


## Regal-Slot <index> hält irgendeine Ware (Menge > 0).
func slot_belegt(index: int) -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var regal: Variant = szene.get("_regal")
	if not (regal is Dictionary):
		return false
	var slots: Array = (regal as Dictionary).get("slots", [])
	if index >= slots.size():
		return false
	var slot: Variant = slots[index]
	return slot is Dictionary and int((slot as Dictionary).get("menge", 0)) > 0


func laden_ist_offen() -> bool:
	var szene := aktuelle_szene()
	return szene != null and str(szene.get("phase")) == "offen"


## Der Alwin-Moment ist deterministisch geplant: Bon 1 gehört dem
## Archetyp „alwin“ und enthält genau die Möhre.
func alwin_zuerst_mit_moehre() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var plan: Variant = szene.get("_tagesplan")
	if not (plan is Dictionary):
		return false
	var bons: Array = (plan as Dictionary).get("bons", [])
	if bons.is_empty():
		return false
	var bon: Dictionary = bons[0]
	if str(bon.get("archetyp", "")) != "alwin":
		return false
	for position: Variant in bon.get("positionen", []):
		if position is Dictionary and str((position as Dictionary).get("ware", "")) == "carrot":
			return true
	return false


func merke_vor_feierabend() -> bool:
	_muenzen_vor_feierabend = muenzstand()
	var szene := aktuelle_szene()
	if szene == null:
		return false
	_umsatz_heute = int(szene.get("umsatz_heute"))
	return _muenzen_vor_feierabend >= 0 and _umsatz_heute >= 0


## Kassensturz-Gegenprobe: Münzen steigen um GENAU den Tagesumsatz.
func umsatz_gutgeschrieben() -> bool:
	if _muenzen_vor_feierabend < 0 or _umsatz_heute < 0:
		return false
	return muenzstand() == _muenzen_vor_feierabend + _umsatz_heute
