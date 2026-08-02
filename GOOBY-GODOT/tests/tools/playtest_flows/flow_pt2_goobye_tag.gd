extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (d) „Goo und Bye — kompletter Tag-Loop“ (Welle H): Level 12 +
## 3000 ᴳ, über Einstellungen → DLC-Hub die Karte ansehen, das Angebot
## öffnen und den Schlüssel für 2500 ᴳ übernehmen (Geld exakt nachrechnen).
## Im Laden: Intro-Karte, drei Regal-Slots per ECHTEN Taps aus dem
## Startlager einräumen (B2-Fix-Beleg: vorher schluckte die Backen-Pill
## die Slot-Taps), eine Ofen-Charge backen und NACH dem Backen Slot 3
## tippen (Slot-Tap-nach-Backen-Probe), Preis-Sheet ansehen, Laden
## öffnen, den Kundenstrom (Alwin zuerst — jetzt MIT Sprechblase!) in
## Echtzeit anschauen, Kassensturz prüfen (Feierabend bucht EXAKT den
## Tagesumsatz) und danach am Großmarkt Nachschub kaufen (Hin- und
## Rückfahrt). Aufruf: tools/ci/run_playtest.sh flow_pt2_goobye_tag

const LEVEL := 12
const BUDGET := 3000
const DLC_PREIS := 2500
## Startlager: apple 6 + carrot 8 + bread 5 landen in Slot 0–2.
const REGAL_SOLL := 19
## … plus EINE Ofen-Charge (3 Brote) via Slot-3-Tap nach dem Backen.
const REGAL_MIT_BROT := REGAL_SOLL + GoobyeBackofen.BROT_JE_CHARGE


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{"name": "level_zwoelf", "aktion": "tue", "funktion": gib_level.bind(LEVEL)},
				{"name": "budget_setzen", "aktion": "tue", "funktion": gib_coins.bind(BUDGET)},
				{
					"name": "einstellungen_oeffnen",
					"aktion": "tipp_name",
					"node": "SettingsButton",
					"erwarte": {"klasse": "SettingsScreen"},
					"timeout_s": 90.0,
				},
				{
					"name": "zu_dlc_rollen",
					"aktion": "tue",
					"funktion": rolle_zu.bind("DlcButton"),
				},
				{
					"name": "alle_dlcs_ansehen",
					"aktion": "tipp_name",
					"node": "DlcButton",
					"erwarte": {"klasse": "DlcScreen"},
					"timeout_s": 90.0,
				},
				# BUG-Umgehung (Befund pt2_d1): die Reise zur Route `dlc`
				# schließt das Settings-Overlay NICHT — der Hub liegt unter
				# dem noch offenen Einstellungen-Screen (HomeEntry/UiLayer)
				# und bekommt keine Taps. Settings-Zurück legt ihn frei.
				# Erst den Reise-Veil ausrollen lassen (pt2_d2: Tipp bei
				# 0,4 s ging in den Vorhang), dann MUSS Settings weg sein.
				# tipp_falls_da statt tipp_name: falls ein B1-Fix das
				# Overlay schon selbst schließt, bleibt der Schritt grün
				# (BackButton existiert NUR im SettingsScreen).
				{"name": "reise_ausrollen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "settings_overlay_schliessen",
					"aktion": "tipp_falls_da",
					"node": "BackButton",
					"erwarte": {"weg_klasse": "SettingsScreen"},
					"timeout_s": 30.0,
				},
				{"name": "hub_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "zu_goobye_rollen",
					"aktion": "tue",
					"funktion": rolle_zu.bind("DlcKarte_goo_und_bye"),
				},
				{
					"name": "goobye_ansehen",
					"aktion": "tipp_pos",
					"pos_funktion": knopf_in.bind("DlcKarte_goo_und_bye"),
					"timeout_s": 20.0,
				},
				{
					"name": "detail_da",
					"aktion": "warte_bis",
					"text": "Schlüssel ansehen",
					"timeout_s": 20.0,
				},
			]
		)
	)
	# Detail-Sheet: der AktionKnopf steckt UNTER Cover+Teaser im
	# %SheetScroll — erst ins Bild rollen, sonst tippt der Tap unter das
	# Sheet-Fenster und verpufft (Befund pt2_d3, Schritt 023).
	liste.append_array(rolle_schritte("Schlüssel ansehen", "aktionknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "angebot_oeffnen",
					"aktion": "tipp_name",
					"node": "AktionKnopf",
					"erwarte": {"text": "Schlüssel übernehmen!"},
					"timeout_s": 30.0,
				},
				{
					"name": "kauf_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("kauf")
				},
			]
		)
	)
	# Angebots-Sheet: auch der Kaufen-Knopf kann unterm Falz liegen.
	liste.append_array(rolle_schritte("Schlüssel übernehmen!", "kaufknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "schluessel_uebernehmen",
					"aktion": "tipp_name",
					"node": "Kaufen",
					"erwarte": {"route": "dlc/goobye_laden"},
					"timeout_s": 120.0,
				},
				{
					"name": "dlc_preis_abgebucht",
					"aktion": "tue",
					"funktion": pruefe_coins_delta.bind("kauf", -DLC_PREIS),
					"erwartung": "Münzen −2500 nach Schlüssel-Kauf",
				},
				{
					"name": "intro_karte_lesen",
					"aktion": "warte_bis",
					"text": "Die Schlüsselübergabe",
					"timeout_s": 30.0,
				},
				{
					"name": "schluessel_nehmen",
					"aktion": "tipp_name",
					"node": "IntroWeiter",
					"timeout_s": 20.0,
				},
				{"name": "laden_umsehen", "aktion": "warte", "sekunden": 3.0},
				# B2-FIX-BELEG (Befund pt2_d4, G8-PT2): die Slots werden
				# jetzt WIRKLICH getippt — vorher lag die „Backen (9)“-Pill
				# quer über Slot 0–2 und schluckte die Taps (Umgehung war
				# slot_tippen() direkt). Die Knopf-Texte zählen als Beleg
				# mit: ×6 Äpfel, ×8 Möhren, ×5 Brote (Katalog-Reihenfolge).
				{
					"name": "slot_0_tippen",
					"aktion": "tipp_name",
					"node": "Slot0",
					"erwarte": {"text": "×6"},
					"timeout_s": 20.0,
				},
				{
					"name": "slot_1_tippen",
					"aktion": "tipp_name",
					"node": "Slot1",
					"erwarte": {"text": "×8"},
					"timeout_s": 20.0,
				},
				{
					"name": "slot_2_tippen",
					"aktion": "tipp_name",
					"node": "Slot2",
					"erwarte": {"text": "×5"},
					"timeout_s": 20.0,
				},
				{
					"name": "regal_bestueckt",
					"aktion": "tue",
					"funktion": _regal_stand.bind(REGAL_SOLL),
					"erwartung": "Startlager (19 Stück) liegt im Regal",
				},
				# Slot-Tap-NACH-Backen-Probe (B2): Backen wohnt jetzt in
				# der Bottom-Leiste — eine Charge backen (bucht GENAU die
				# Selbstkosten ab, legt 3 Brote ins Lager), danach muss der
				# Tap auf Slot 3 auf dem SLOT landen (Regal 19 → 22).
				{
					"name": "backen_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("backofen"),
				},
				{
					"name": "backen_tippen",
					"aktion": "tipp_name",
					"node": "Backen",
					"timeout_s": 20.0,
				},
				{
					"name": "backofen_bezahlt",
					"aktion": "tue",
					"funktion": _backofen_bezahlt,
					"erwartung": "GENAU eine Charge Selbstkosten abgebucht",
				},
				{
					"name": "slot_3_nach_backen",
					"aktion": "tipp_name",
					"node": "Slot3",
					"erwarte": {"text": "×3"},
					"timeout_s": 20.0,
				},
				{
					"name": "regal_nach_backen",
					"aktion": "tue",
					"funktion": _regal_stand.bind(REGAL_MIT_BROT),
					"erwartung": "Ofen-Charge (3 Brote) liegt in Slot 3",
				},
				{
					"name": "preise_ansehen",
					"aktion": "tipp_name",
					"node": "Preise",
					"timeout_s": 20.0
				},
				{
					"name": "preis_sheet_da",
					"aktion": "warte_bis",
					"text": "Preise am Regal",
					"timeout_s": 20.0,
				},
				# Backdrop-Tipp statt Runter-Wisch: ab Sheet-Mitte wischen
				# SCROLLT nur den Inhalt (Befund pt2_c4 am Wochenmarkt).
				{
					"name": "preis_sheet_zumachen",
					"aktion": "tipp_pos",
					"pos_funktion": canvas_punkt.bind(Vector2(0.9, 0.08)),
					"pflicht": false,
				},
				{"name": "sheet_zu_abwarten", "aktion": "warte", "sekunden": 1.5},
				{"name": "tag_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("tag")},
				{
					"name": "laden_oeffnen",
					"aktion": "tipp_name",
					"node": "LadenOeffnen",
					"timeout_s": 20.0,
				},
				# Kundenstrom in Echtzeit ansehen (Alwin ist immer Kunde 0).
				# Screenshot bei +3 s: Alwins Sprechblase (G8-PT2-Polish) lebt
				# ~4,8 s — hier ist sie gut gefüllt getippt UND Alwin im Bild.
				{"name": "alwin_blase_schauen", "aktion": "warte", "sekunden": 3.0},
				{"name": "kunden_schauen_1", "aktion": "warte", "sekunden": 5.0},
				{"name": "kunden_schauen_2", "aktion": "warte", "sekunden": 5.0},
				{
					"name": "kassensturz_karte",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("Feierabend"),
					"timeout_s": 240.0,
				},
				{
					"name": "alwin_bedient",
					"aktion": "tue",
					"funktion": _alwin_bedient,
					"erwartung": "Alwin hat seine Möhre bekommen (Streak gezählt)",
					"pflicht": false,
				},
				{
					"name": "kassensturz_merken",
					"aktion": "tue",
					"funktion": _kassensturz_merken,
					"erwartung": "Tagesumsatz + Kontostand notiert",
				},
				{
					"name": "feierabend_buchen",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"timeout_s": 20.0,
				},
				{"name": "buchung_abwarten", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "umsatz_exakt_gebucht",
					"aktion": "tue",
					"funktion": _umsatz_gebucht,
					"erwartung": "Feierabend bucht EXAKT den Tagesumsatz aufs Konto",
				},
				{
					"name": "grossmarkt_fahren",
					"aktion": "tipp_name",
					"node": "Grossmarkt",
					"erwarte": {"route": "dlc/goobye_grossmarkt"},
					"timeout_s": 120.0,
				},
				{
					"name": "rampe_erreicht",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("KaufenLosfahren"),
					"timeout_s": 90.0,
				},
				{
					"name": "zu_apfel_rollen",
					"aktion": "tue",
					"funktion": rolle_zu.bind("Palette_apple"),
				},
				{
					"name": "apfel_plus_1",
					"aktion": "tipp_name",
					"node": "Plus_apple",
					"timeout_s": 20.0
				},
				{
					"name": "apfel_plus_2",
					"aktion": "tipp_name",
					"node": "Plus_apple",
					"timeout_s": 20.0
				},
				{
					"name": "einkauf_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("einkauf"),
				},
				{
					"name": "kaufen_losfahren",
					"aktion": "tipp_name",
					"node": "KaufenLosfahren",
					"timeout_s": 20.0,
				},
				{
					"name": "ankunft_im_laden",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("ZurueckInDenLaden"),
					"timeout_s": 90.0,
				},
				{
					"name": "einkauf_bezahlt",
					"aktion": "tue",
					"funktion": _einkauf_bezahlt,
					"erwartung": "Münzen nach Großmarkt-Einkauf kleiner",
				},
				{
					"name": "zurueck_in_den_laden",
					"aktion": "tipp_name",
					"node": "ZurueckInDenLaden",
					"erwarte": {"route": "dlc/goobye_laden"},
					"timeout_s": 120.0,
				},
				{"name": "wieder_im_laden", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "laden_verlassen",
					"aktion": "tipp_name",
					"node": "Verlassen",
					"erwarte": {"weg_klasse": "GoobyeLadenScene"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


func _laden_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is GoobyeLadenScene else null


## Regal-Bestand gegen ein Soll prüfen (Slot-Taps laufen seit dem B2-Fix
## als ECHTE Taps über die Knöpfe — keine slot_tippen()-Umgehung mehr).
func _regal_stand(soll: int) -> bool:
	var szene := _laden_szene()
	if szene == null:
		return false
	var bestand := GoobyeRegal.gesamt_bestand(szene.get("_regal"))
	print("[PT2] Regal-Bestand: %d (soll %d)" % [bestand, soll])
	return bestand == soll


## Backen-Tap aus der Leiste: GENAU eine Charge Selbstkosten abgebucht.
func _backofen_bezahlt() -> bool:
	return pruefe_coins_delta("backofen", -GoobyeBackofen.kosten())


func _alwin_bedient() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var bedient := int(gs.get_value("dlc.goobye.alwin.bedientGesamt", 0))
	var streak := int(gs.get_value("dlc.goobye.alwin.streak", 0))
	print("[PT2] Alwin: bedientGesamt %d, Streak %d" % [bedient, streak])
	return bedient >= 1


## Tagesumsatz von der Kassensturz-Karte + Kontostand für den Exakt-Check.
func _kassensturz_merken() -> bool:
	var szene := _laden_szene()
	if szene == null:
		return false
	merke("umsatz", int(szene.get("umsatz_heute")))
	return merke_coins("feierabend")


func _umsatz_gebucht() -> bool:
	return pruefe_coins_delta("feierabend", int(zettel.get("umsatz", 0)))


func _einkauf_bezahlt() -> bool:
	var vorher := int(zettel.get("einkauf", 0))
	var ist := coins()
	print("[PT2] Großmarkt: Münzen %d → %d" % [vorher, ist])
	return ist < vorher
