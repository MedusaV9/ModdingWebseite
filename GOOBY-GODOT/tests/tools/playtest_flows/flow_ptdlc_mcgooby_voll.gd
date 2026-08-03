extends "res://tests/tools/playtest_flows/flow_ptdlc_basis.gd"
## PT-DLC Flow (c) — MCGOOBY VOLL-MODUS (W18/R3, G8): der komplette
## Kauf-Weg als echter Spieler. Erst die freie Probeschicht (Level 10,
## 700 ᴳ — beide Gates ZU), dann die Ende-Karte „Schicht geschafft →
## Angebot“: Level-Gate-Zeile prüfen, Level 14 geben → Münz-Gate am
## „Kaufen“-Knopf (RESULT_BROKE, Klartext-Zeile, KEINE Abbuchung), dann
## 3456 ᴳ → Kauf klappt (−3000 exakt) und die VOLLE Schicht startet in
## place. Dort: Bühne 1× (Trinkgeld +6, zweiter Tipp wirkungslos),
## Grill-Tap, Fritteuse HALTEN mit Salz-Moment (Glitzersalz +4),
## Getränke-Zapfen mit Sprudel-Gag und einmal „zu früh losgelassen“
## (kein Fail, keine Wertung). Kassensturz wird mit der EIGENEN
## Doc-Mathe (meine_mc_abrechnung) nachgerechnet und exakt gegen die
## Münz-Gutschrift gehalten.
##
## Timing-Trick fürs llvmpipe-Tempo: jede Wertung passiert ATOMAR in
## EINEM tue-Schritt (unpausieren → Zeit per Test-API in die Fenster-
## Mitte pinnen → Knopf-Signal → wieder pausieren) — zwischen Schritten
## vergehen sonst Sekunden. Der Sprudel-Callout entsteht über den ECHTEN
## Frame-Pfad (_process_voll mit kontrolliertem delta), nie von Hand.
##
## Seed aus flow_ptdlc_seedsuche: 20260914 → Probeschicht gooby_mac ×2 +
## garten_gooby ×1 (3 Pattys); Voll-Plan 20260915 (_runde 1 nach Kauf) →
## kaese_knusperle (Grill-Tap), sprudelwasser_deluxe (Zapfen, mittel),
## moehren_pommes (Fritteuse+SALZ) + gooby_brause (Zapfen, gross).
## GOLDEN alles-perfekt + Bühne: 89 Punkte, Basis 22 + Trinkgeld 13 = 35 ᴳ.

const MC_SEED := 20260914

## Gate-Aufstellung: Level 10 < 14, 700 ᴳ < 3000; Kauf-Budget 3456.
const START_LEVEL := 10
const START_COINS := 700
const KAUF_BUDGET := 3456
const MC_LEVEL := 14
const MC_PREIS := 3000
const MC_BUEHNE_BONUS := 6
const MC_PUNKTE_PERFEKT := 10
const MC_PUNKTE_SALZ := 4
const MC_BONUS_BESTELLUNG := 15

## Reserve-Schritte des Aufgaben-Automaten (max 8 Aufgaben + Salz +
## Getränke-Zweiteiler + Puffer).
const AUFGABEN_RESERVE := 22

var _zu_frueh_gezeigt := false
var _meine_punkte := 0
var _meine_ergebnisse: Array[Dictionary] = []
var _bestellung_meine_punkte := 0
var _letzte_bestellung := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_hub_schritte())
	liste.append_array(_probeschicht_schritte())
	liste.append_array(_gate_schritte())
	liste.append_array(_kauf_schritte())
	liste.append_array(_voll_start_schritte())
	liste.append_array(_buehne_schritte())
	liste.append_array(_aufgaben_schritte())
	liste.append_array(_abrechnung_schritte())
	return liste


## ---------------------------------------- Weg zum Hub (Muster pt2_mcgooby)


func _hub_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{"name": "level_zehn", "aktion": "tue", "funktion": gib_level.bind(START_LEVEL)},
		{"name": "budget_klein", "aktion": "tue", "funktion": gib_coins.bind(START_COINS)},
		{
			"name": "einstellungen_oeffnen",
			"aktion": "tipp_name",
			"node": "SettingsButton",
			"erwarte": {"klasse": "SettingsScreen"},
			"timeout_s": 90.0,
		},
		{"name": "zu_dlc_rollen", "aktion": "tue", "funktion": rolle_zu.bind("DlcButton")},
		{
			"name": "alle_dlcs_ansehen",
			"aktion": "tipp_name",
			"node": "DlcButton",
			"erwarte": {"klasse": "DlcScreen"},
			"timeout_s": 90.0,
		},
		# Bekannte Umgehung (G8-PT2, Befund pt2_d1): Settings-Overlay
		# bleibt über dem DLC-Hub liegen — Zurück legt frei.
		{"name": "reise_ausrollen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "settings_overlay_schliessen",
			"aktion": "tipp_falls_da",
			"node": "BackButton",
			"erwarte": {"weg_klasse": "SettingsScreen"},
			"timeout_s": 30.0,
		},
		{
			"name": "zu_mcgooby_rollen",
			"aktion": "tue",
			"funktion": rolle_zu.bind("DlcKarte_mcgooby"),
		},
		{
			"name": "mcgooby_ansehen",
			"aktion": "tipp_pos",
			"pos_funktion": knopf_in.bind("DlcKarte_mcgooby"),
			"timeout_s": 20.0,
		},
		{
			"name": "detail_da",
			"aktion": "warte_bis",
			"text": "Probeschicht starten!",
			"timeout_s": 20.0,
		},
	]
	liste.append_array(rolle_schritte("Probeschicht starten!", "aktionknopf"))
	(
		liste
		. append_array(
			[
				{
					"name": "probeschicht_starten",
					"aktion": "tipp_name",
					"node": "AktionKnopf",
					"erwarte": {"klasse": "McGoobySchichtScene"},
					"timeout_s": 120.0,
				},
			]
		)
	)
	return liste


## --------------------------------------------- Probeschicht (Demo, Seed S)


func _probeschicht_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "intro_karte",
			"aktion": "warte_bis",
			"text": "Die große Eröffnung",
			"timeout_s": 30.0,
		},
		{
			"name": "seed_pinnen",
			"aktion": "tue",
			"funktion": szene_prop.bind("seed_override", MC_SEED)
		},
		{"name": "probe_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("probe")},
		{
			"name": "schuerze_umbinden",
			"aktion": "tipp_name",
			"node": "SchuerzeKnopf",
			"erwarte": {"weg_text": "Die große Eröffnung"},
			"timeout_s": 30.0,
		},
		{
			"name": "probe_plan_geprueft",
			"aktion": "tue",
			"funktion": _probe_plan_pruefen,
			"erwartung": "Demo-Plan: 2 Bestellungen, ≤ 3 Pattys (Seed-Vertrag)",
		},
	]
	for i in 4:
		(
			liste
			. append(
				{
					"name": "probe_patty_%d" % (i + 1),
					"aktion": "tue",
					"funktion": _probe_patty_perfekt,
					"pflicht": false,
				}
			)
		)
	(
		liste
		. append_array(
			[
				{
					"name": "probe_feierabend_karte",
					"aktion": "warte_bis",
					"text": "Feierabend!",
					"timeout_s": 60.0,
				},
				{
					"name": "probe_kasse_exakt",
					"aktion": "tue",
					"funktion": _probe_kasse_pruefen,
					"erwartung": "Demo-Kasse == meine Nachrechnung + Münzen exakt gebucht",
				},
				{
					"name": "angebot_block_da",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("AngebotAnsehen"),
					"timeout_s": 15.0,
				},
			]
		)
	)
	return liste


## --------------------------------------- Kauf-Gates (Level, dann Münzen)


func _gate_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "angebot_oeffnen_gate1",
			"aktion": "tipp_name",
			"node": "AngebotAnsehen",
			"erwarte": {"text": "Dein eigener Laden!"},
			"timeout_s": 30.0,
		},
		{
			"name": "level_gate_zeile",
			"aktion": "tue",
			"funktion": _level_gate_pruefen,
			"erwartung": "Kaufen disabled + Gate-Zeile „ab Level 14 … (aktuell 10)“",
		},
		{
			"name": "gate1_spaeter",
			"aktion": "tipp_name",
			"node": "Spaeter",
			"erwarte": {"weg_text": "Dein eigener Laden!"},
			"timeout_s": 30.0,
		},
		{"name": "level_vierzehn", "aktion": "tue", "funktion": gib_level.bind(MC_LEVEL)},
		{
			"name": "angebot_oeffnen_gate2",
			"aktion": "tipp_name",
			"node": "AngebotAnsehen",
			"erwarte": {"text": "Dein eigener Laden!"},
			"timeout_s": 30.0,
		},
		{
			"name": "kaufen_jetzt_frei",
			"aktion": "tue",
			"funktion": _kaufen_frei_pruefen,
			"erwartung": "Level 14 → Kaufen enabled, Hinweis = freundliche Frage",
		},
		{"name": "broke_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("broke")},
		{
			"name": "kauf_zu_arm",
			"aktion": "tipp_name",
			"node": "Kaufen",
			"erwarte": {"bedingung": _broke_zeile_da},
			"timeout_s": 30.0,
		},
		{
			"name": "broke_ohne_abbuchung",
			"aktion": "tue",
			"funktion": _broke_geprueft,
			"erwartung": "RESULT_BROKE: Münzen unverändert (719 nach Probe-Lohn), kein Kauf",
		},
		{
			"name": "gate2_spaeter",
			"aktion": "tipp_name",
			"node": "Spaeter",
			"erwarte": {"weg_text": "Dein eigener Laden!"},
			"timeout_s": 30.0,
		},
	]


## ----------------------------------------------- Kauf + Voll-Schicht-Start


func _kauf_schritte() -> Array[Dictionary]:
	return [
		{"name": "kauf_budget", "aktion": "tue", "funktion": gib_coins.bind(KAUF_BUDGET)},
		{"name": "kauf_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("kauf")},
		{
			"name": "angebot_oeffnen_kauf",
			"aktion": "tipp_name",
			"node": "AngebotAnsehen",
			"erwarte": {"text": "Dein eigener Laden!"},
			"timeout_s": 30.0,
		},
		# Kauf ATOMAR: pressed-Signal + sofort pausieren — sonst gart die
		# erste Voll-Aufgabe zwischen den Harness-Schritten unkontrolliert
		# (llvmpipe braucht pro Schritt Sekunden; Getränke-gar ist 2,25 s).
		{
			"name": "schluessel_kaufen",
			"aktion": "tue",
			"funktion": _kaufen_und_pausieren,
			"erwartung": "Kauf OK → volle Schicht startet in place, sofort pausiert",
		},
		{
			"name": "kauf_abgebucht",
			"aktion": "tue",
			"funktion": pruefe_coins_delta.bind("kauf", -MC_PREIS),
			"erwartung": "Münzen −3000 exakt nach dem Laden-Kauf",
		},
	]


func _voll_start_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "voll_modus_da",
			"aktion": "tue",
			"funktion": _voll_modus_pruefen,
			"erwartung": "ist_voll_modus + Stations-Pills + Bühnen-Knopf sichtbar",
		},
		{
			"name": "voll_plan_geprueft",
			"aktion": "tue",
			"funktion": _voll_plan_pruefen,
			"erwartung": "Voll-Plan (Seed+1): 3 Bestellungen, Grill+Fritteuse/Salz+Getränke",
		},
		{"name": "voll_coins_merken", "aktion": "tue", "funktion": merke_coins.bind("voll")},
	]


## --------------------------------------------------------- Bühne (1×)


func _buehne_schritte() -> Array[Dictionary]:
	return [
		# Auftritt starten: unpausieren → pressed → wieder pausieren (die
		# Bühnen-Tweens laufen weiter, die Gar-Zeit steht).
		{
			"name": "buehne_auftritt",
			"aktion": "tue",
			"funktion": _buehne_starten,
			"erwartung": "Bühnen-Auftritt läuft (McGoobyBuehne.laeuft)",
		},
		{
			"name": "buehne_fertig",
			"aktion": "warte_bis",
			"bedingung": _buehne_fertig,
			"timeout_s": 60.0,
		},
		{
			"name": "buehne_trinkgeld_callout",
			"aktion": "tue",
			"funktion": _buehne_bonus_pruefen,
			"erwartung": "Trinkgeld-Regen +6 als Callout, Knopf jetzt gesperrt",
		},
		{
			"name": "buehne_zweiter_tipp_wirkungslos",
			"aktion": "tue",
			"funktion": _buehne_nochmal_versuchen,
			"erwartung": "1×/Schicht: zweiter Versuch ändert NICHTS (Bonus bleibt 6)",
		},
	]


## ------------------------------------------- Aufgaben-Automat (generisch)


func _aufgaben_schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	for i in AUFGABEN_RESERVE:
		(
			liste
			. append(
				{
					"name": "voll_aufgabe_%02d" % (i + 1),
					"aktion": "tue",
					"funktion": _aufgabe_schritt,
					"pflicht": false,
				}
			)
		)
	return liste


func _abrechnung_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "voll_feierabend_karte",
			"aktion": "warte_bis",
			"text": "Feierabend!",
			"timeout_s": 60.0,
		},
		{
			"name": "voll_kasse_nachgerechnet",
			"aktion": "tue",
			"funktion": _voll_kasse_pruefen,
			"erwartung": "Kasse == MEINE Abrechnung (inkl. Bühnen-Bonus) + Münzen exakt",
		},
		{
			"name": "voll_ende_zeilen",
			"aktion": "tue",
			"funktion": _ende_zeilen_pruefen,
			"erwartung": "Ende-Karte: Salz-/Bühnen-Zeile da, Angebots-Block WEG",
		},
		{
			"name": "feierabend_machen",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"weg_klasse": "McGoobySchichtScene"},
			"timeout_s": 120.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


## ---------------------------------------------------------------- Helfer


func _voll_szene_ok() -> bool:
	return schicht_szene() != null


## Demo-Plan gegen den Seed-Vertrag halten (2 Bestellungen, ≤ 3 Pattys).
func _probe_plan_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	var folge: Array = szene.get("_folge")
	var patties := 0
	for bestellung: Dictionary in folge:
		patties += int(bestellung.get("patties", 1))
		print(
			(
				"[PTDLC] Probe-Bestellung %d: %s × %d"
				% [
					int(bestellung.get("nr", 0)),
					str(bestellung.get("rezept_id", "?")),
					int(bestellung.get("patties", 1)),
				]
			)
		)
	return folge.size() == 2 and patties <= 3 and bool(szene.call("ist_am_laufen"))


## EIN Demo-Patty deterministisch perfekt (Muster flow_pt2_mcgooby):
## Zeit in die Fenster-Mitte pinnen + pressed — und MEINE Punkte zählen.
func _probe_patty_perfekt() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	if bool(szene.call("ist_ende_offen")):
		print("[PTDLC] Probeschicht vorbei — nichts mehr zu braten")
		return true
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	_meine_bestellung_beobachten(szene)
	szene.call("patty_zeit_setzen", mitte)
	(szene.call("patty_knopf") as Button).pressed.emit()
	_meine_punkte_zaehlen(MC_PUNKTE_PERFEKT, szene)
	print("[PTDLC] Demo-Patty bei %.2f s → Punkte %d" % [mitte, int(szene.get("_punkte"))])
	return true


## Demo-Kasse: Spiel-Kasse == MEINE Abrechnung UND Münzen exakt gebucht.
func _probe_kasse_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	_meine_bestellung_abschliessen()
	var kasse: Dictionary = szene.call("schicht_ergebnis")
	var meine := meine_mc_abrechnung(_meine_ergebnisse, 0)
	print("[PTDLC] Demo-Kasse %s — meine %s" % [str(kasse), str(meine)])
	if int(kasse.get("punkte", -1)) != int(meine["punkte"]):
		return false
	if int(kasse.get("trinkgeld", -1)) != int(meine["trinkgeld"]):
		return false
	if int(kasse.get("muenzen_basis", -1)) != int(meine["muenzen_basis"]):
		return false
	var summe := int(meine["muenzen_basis"]) + int(meine["trinkgeld"])
	if int(kasse.get("muenzen", -1)) != summe:
		return false
	return pruefe_coins_delta("probe", summe)


## Level-Gate: Kaufen disabled + Klartext mit BEIDEN Zahlen (14 und 10).
func _level_gate_pruefen() -> bool:
	var kaufen := harness.root.find_child("Kaufen", true, false)
	if not (kaufen is BaseButton) or not (kaufen as BaseButton).is_visible_in_tree():
		print("[PTDLC] Kaufen-Knopf nicht sichtbar")
		return false
	var hinweis := label_text("KaufHinweis")
	var soll := I18nService.t(
		"dlc_mcgooby.angebot.gate", {"level": MC_LEVEL, "aktuell": START_LEVEL}
	)
	print(
		(
			"[PTDLC] Gate-Zeile: '%s' (soll '%s'), disabled=%s"
			% [hinweis, soll, str((kaufen as BaseButton).disabled)]
		)
	)
	return (kaufen as BaseButton).disabled and hinweis == soll


## Level 14 erreicht: Kaufen enabled, Hinweis = die freundliche Frage.
func _kaufen_frei_pruefen() -> bool:
	var kaufen := harness.root.find_child("Kaufen", true, false)
	if not (kaufen is BaseButton):
		return false
	var hinweis := label_text("KaufHinweis")
	var soll := I18nService.t("dlc_mcgooby.angebot.frage")
	print(
		"[PTDLC] Nach Level-Up: '%s', disabled=%s" % [hinweis, str((kaufen as BaseButton).disabled)]
	)
	return not (kaufen as BaseButton).disabled and hinweis == soll


func _broke_zeile_da() -> bool:
	return (
		label_text("KaufHinweis")
		== I18nService.t("dlc_mcgooby.angebot.zu_wenig", {"preis": MC_PREIS})
	)


## RESULT_BROKE lässt ALLES unangetastet: Münzen (Stand VOR dem Tipp —
## die Probeschicht hat +19 gezahlt, also 719), Kauf-Status, Demo-Modus.
func _broke_geprueft() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var gekauft := McGoobyState.ist_gekauft(gs)
	print("[PTDLC] Nach Broke-Kauf: %d ᴳ, gekauft=%s" % [coins(), str(gekauft)])
	return pruefe_coins_delta("broke", 0) and not gekauft


## Kauf + Sofort-Pause ATOMAR (kein Frame zwischen Schichtstart und Pause).
## Die eigene Punkte-Buchhaltung startet hier frisch für die volle Schicht.
func _kaufen_und_pausieren() -> bool:
	var szene := schicht_szene()
	var kaufen := harness.root.find_child("Kaufen", true, false)
	if szene == null or not (kaufen is BaseButton):
		return false
	(kaufen as BaseButton).pressed.emit()
	szene.set("_pausiert", true)
	_meine_punkte = 0
	_bestellung_meine_punkte = 0
	_meine_ergebnisse = []
	_letzte_bestellung = -1
	var voll := bool(szene.call("ist_voll_modus"))
	print("[PTDLC] Nach Kauf: voll=%s, pausiert, Runde %d" % [str(voll), int(szene.get("_runde"))])
	return voll


func _voll_modus_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null or not bool(szene.call("ist_voll_modus")):
		return false
	var pills: Array = szene.call("stationen_pills")
	var buehne := szene.call("buehne_knopf") as Button
	var block := harness.root.find_child("StationenBlock", true, false)
	var sichtbar := block is Control and (block as Control).is_visible_in_tree()
	print("[PTDLC] Voll-Modus: %d Pills, Block sichtbar=%s" % [pills.size(), str(sichtbar)])
	return pills.size() >= 3 and buehne != null and sichtbar


## Voll-Plan lesen: 3 Bestellungen, alle drei Stationen vertreten, und die
## Aufgaben-Liste fürs Protokoll ausdrucken (Zieh-Vertrag der Seedsuche).
func _voll_plan_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	var folge: Array = szene.get("_folge_voll")
	var grill := 0
	var fritteuse_salz := 0
	var getraenke := 0
	var gesamt := 0
	for bestellung: Dictionary in folge:
		var zeile := "[PTDLC] Voll-Bestellung %d:" % int(bestellung.get("nr", 0))
		for position: Dictionary in bestellung.get("positionen", []):
			zeile += " %s(" % str(position.get("rezept_id", "?"))
			for aufgabe: Dictionary in position.get("aufgaben", []):
				gesamt += 1
				var station := str(aufgabe.get("station", ""))
				zeile += (
					" %s/%s%s%s"
					% [
						station,
						str(aufgabe.get("art", "?")),
						"+SALZ" if bool(aufgabe.get("salz", false)) else "",
						(
							"+" + str(aufgabe.get("becher", ""))
							if str(aufgabe.get("becher", "")) != ""
							else ""
						),
					]
				)
				match station:
					"grill":
						grill += 1
					"fritteuse":
						if bool(aufgabe.get("salz", false)):
							fritteuse_salz += 1
					"getraenke":
						getraenke += 1
			zeile += " )"
		print(zeile)
	print(
		(
			"[PTDLC] Voll-Plan: %d Bestellungen, %d Aufgaben (%d Grill, %d Fritteuse+Salz, %d Getränke)"
			% [folge.size(), gesamt, grill, fritteuse_salz, getraenke]
		)
	)
	return folge.size() == 3 and grill >= 1 and fritteuse_salz >= 1 and getraenke >= 1


## Bühne starten: unpausieren → pressed → sofort wieder pausieren (der
## Auftritt tween-t in Echtzeit weiter, die Gar-Zeit friert).
func _buehne_starten() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	szene.set("_pausiert", false)
	(szene.call("buehne_knopf") as Button).pressed.emit()
	szene.set("_pausiert", true)
	var laeuft := bool((szene.call("buehne") as Node).call("laeuft"))
	print("[PTDLC] Bühne gestartet: laeuft=%s" % str(laeuft))
	return laeuft


func _buehne_fertig() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	var buehne: Node = szene.call("buehne")
	return bool(buehne.call("schon_aufgetreten")) and not bool(buehne.call("laeuft"))


func _buehne_bonus_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	var bonus := int(szene.get("_buehne_trinkgeld"))
	var callout := str((szene.get("_callout") as Label).text)
	var soll := I18nService.t("dlc_mcgooby.buehne.trinkgeld", {"betrag": MC_BUEHNE_BONUS})
	var gesperrt := (szene.call("buehne_knopf") as Button).disabled
	print(
		"[PTDLC] Bühnen-Bonus %d, Callout '%s', Knopf gesperrt=%s" % [bonus, callout, str(gesperrt)]
	)
	return bonus == MC_BUEHNE_BONUS and callout == soll and gesperrt


## Zweiter Auftritt darf NICHTS ändern (1×/Schicht-Vertrag).
func _buehne_nochmal_versuchen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	szene.set("_pausiert", false)
	(szene.call("buehne_knopf") as Button).pressed.emit()
	szene.set("_pausiert", true)
	var bonus := int(szene.get("_buehne_trinkgeld"))
	var laeuft := bool((szene.call("buehne") as Node).call("laeuft"))
	print("[PTDLC] Zweiter Bühnen-Tipp: Bonus %d, laeuft=%s" % [bonus, str(laeuft)])
	return bonus == MC_BUEHNE_BONUS and not laeuft


## EIN Automaten-Schritt der vollen Schicht: schaut auf den AKTUELLEN
## Zustand (Salz offen? Aufgabe TAP/HALTEN? schon am Halten?) und macht
## genau EINEN atomaren Zug — der Screenshot danach zeigt den Moment.
func _aufgabe_schritt() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	if bool(szene.call("ist_ende_offen")):
		print("[PTDLC] Schicht vorbei — Automat ruht")
		return true
	_meine_bestellung_beobachten(szene)
	if bool(szene.call("salz_ist_aktiv")):
		return _zug_salz(szene)
	var aufgabe: Dictionary = szene.call("aufgabe_aktuell")
	if aufgabe.is_empty():
		print("[PTDLC] Keine Aufgabe aktiv?!")
		return false
	return _zug_fuer(szene, aufgabe)


## Zug-Auswahl je Aufgaben-Art und Halte-Zustand (gdlint: max-returns).
func _zug_fuer(szene: Node, aufgabe: Dictionary) -> bool:
	if str(aufgabe.get("art", "")) == McGoobySchichtPlan.ART_TAP:
		return _zug_tap(szene)
	if bool(szene.get("_haelt")):
		return _zug_absetzen(szene)
	if not _zu_frueh_gezeigt:
		return _zug_zu_frueh(szene, aufgabe)
	return _zug_anfassen(szene, aufgabe)


## Grill-Tap: Zeit in die Fenster-Mitte, EIN Druck, Perfekt — atomar.
func _zug_tap(szene: Node) -> bool:
	var timing: Dictionary = szene.call("aufgabe_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.set("_pausiert", false)
	szene.call("patty_zeit_setzen", mitte)
	(szene.call("patty_knopf") as Button).button_down.emit()
	(szene.call("patty_knopf") as Button).button_up.emit()
	szene.set("_pausiert", true)
	_meine_punkte_zaehlen(MC_PUNKTE_PERFEKT, szene)
	print("[PTDLC] Grill-Tap bei %.2f s → Punkte %d" % [mitte, int(szene.get("_punkte"))])
	return true


## „Zu früh losgelassen“ EINMAL zeigen: Druck + Release bei 0,4 s → ROH,
## Callout (zu_blass/zu_leer), KEINE Wertung, Aufgabe läuft weiter.
func _zug_zu_frueh(szene: Node, aufgabe: Dictionary) -> bool:
	_zu_frueh_gezeigt = true
	var punkte_vorher := int(szene.get("_punkte"))
	szene.set("_pausiert", false)
	(szene.call("patty_knopf") as Button).button_down.emit()
	szene.call("patty_zeit_setzen", 0.4)
	(szene.call("patty_knopf") as Button).button_up.emit()
	szene.set("_pausiert", true)
	var callout := str((szene.get("_callout") as Label).text)
	var station := str(aufgabe.get("station", ""))
	var soll_key := "zu_leer" if station == "getraenke" else "zu_blass"
	var soll := I18nService.t("dlc_mcgooby.schicht." + soll_key)
	print(
		(
			"[PTDLC] Zu-früh-Release (%s): Callout '%s', Punkte %d (unverändert %d)"
			% [station, callout, int(szene.get("_punkte")), punkte_vorher]
		)
	)
	return callout == soll and int(szene.get("_punkte")) == punkte_vorher


## Halte-Aufgabe anfassen. Getränke bekommen den Sprudel-Gag über den
## ECHTEN Frame-Pfad: Zeit kurz vor goldbraun pinnen, dann _process_voll
## mit kontrolliertem delta — der Callout „sprudelt“ entsteht im Spiel-
## Code, der Screenshot nach dem Schritt zeigt ihn (Zeit steht pausiert).
func _zug_anfassen(szene: Node, aufgabe: Dictionary) -> bool:
	szene.set("_pausiert", false)
	(szene.call("patty_knopf") as Button).button_down.emit()
	szene.set("_pausiert", true)
	if not bool(szene.get("_haelt")):
		print("[PTDLC] Anfassen hat nicht gegriffen?!")
		return false
	if str(aufgabe.get("station", "")) != "getraenke":
		print("[PTDLC] %s angefasst — Zeit steht pausiert" % str(aufgabe.get("station", "")))
		return true
	var timing: Dictionary = szene.call("aufgabe_timing")
	szene.call("patty_zeit_setzen", float(timing.get("gar_sec", 3.0)) - 0.05)
	szene.call("_process_voll", 0.1)
	var callout := str((szene.get("_callout") as Label).text)
	var soll := I18nService.t("dlc_mcgooby.schicht.sprudelt")
	print(
		(
			"[PTDLC] Sprudel-Gag: Callout '%s' (Becher %s, gar %.2f s)"
			% [callout, str(aufgabe.get("becher", "?")), float(timing.get("gar_sec", 0.0))]
		)
	)
	return callout == soll


## Gehaltene Aufgabe im goldenen Fenster absetzen (Perfekt); Fritteusen
## mit Salz-Schritt öffnen synchron den Salz-Moment — der Screenshot
## nach dem Schritt zeigt Callout + Countdown-Balken (Zeit steht).
func _zug_absetzen(szene: Node) -> bool:
	var aufgabe: Dictionary = szene.call("aufgabe_aktuell")
	var timing: Dictionary = szene.call("aufgabe_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.2)) * 0.5
	szene.set("_pausiert", false)
	szene.call("patty_zeit_setzen", mitte)
	(szene.call("patty_knopf") as Button).button_up.emit()
	szene.set("_pausiert", true)
	_meine_punkte_zaehlen(MC_PUNKTE_PERFEKT, szene)
	var salz := bool(szene.call("salz_ist_aktiv"))
	print(
		(
			"[PTDLC] %s bei %.2f s abgesetzt → Punkte %d%s"
			% [
				str(aufgabe.get("station", "?")),
				mitte,
				int(szene.get("_punkte")),
				" — SALZ-MOMENT offen!" if salz else "",
			]
		)
	)
	if bool(aufgabe.get("salz", false)) and not salz:
		return false
	return true


## Salz-Tap im Fenster (0,3 s von 1,2 s): Glitzersalz-Bonus +4.
func _zug_salz(szene: Node) -> bool:
	szene.set("_pausiert", false)
	szene.call("salz_zeit_setzen", 0.3)
	(szene.call("patty_knopf") as Button).button_down.emit()
	szene.set("_pausiert", true)
	var callout := str((szene.get("_callout") as Label).text)
	var soll := I18nService.t("dlc_mcgooby.schicht.glitzersalz")
	_meine_punkte_zaehlen(MC_PUNKTE_SALZ, szene)
	print(
		(
			"[PTDLC] Salz-Tap: Callout '%s', Salz-Treffer %d"
			% [callout, int(szene.get("_salz_treffer"))]
		)
	)
	return callout == soll


## ------------------------------------------------ Eigene Punkte-Buchhaltung


## Bestellwechsel erkennen: abgeschlossene Bestellung in MEINE Ergebnis-
## Liste buchen (+15 Abschluss-Bonus, fehlerfrei — der Automat spielt
## alles perfekt; „zu früh“ wertet nie).
func _meine_bestellung_beobachten(szene: Node) -> void:
	var idx := int(szene.get("_bestellung_idx"))
	if _letzte_bestellung == -1:
		_letzte_bestellung = idx
		return
	if idx != _letzte_bestellung:
		_meine_bestellung_abschliessen()
		_letzte_bestellung = idx


func _meine_bestellung_abschliessen() -> void:
	if _letzte_bestellung < 0:
		return
	var punkte := _bestellung_meine_punkte + MC_BONUS_BESTELLUNG
	_meine_punkte += MC_BONUS_BESTELLUNG
	_meine_ergebnisse.append({"punkte": punkte, "fehlerfrei": true})
	_bestellung_meine_punkte = 0


func _meine_punkte_zaehlen(punkte: int, szene: Node) -> void:
	_meine_punkte += punkte
	_bestellung_meine_punkte += punkte
	# Bestellwechsel durch die Wertung selbst sofort mitnehmen.
	_meine_bestellung_beobachten(szene)


## Voll-Kasse: Spiel == MEINE Doc-Mathe (inkl. Bühnen-Bonus 6) UND die
## Münzen exakt aufs Konto (Delta seit Marke „voll“).
func _voll_kasse_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	_meine_bestellung_abschliessen()
	_letzte_bestellung = -1
	var kasse: Dictionary = szene.call("schicht_ergebnis")
	var meine := meine_mc_abrechnung(_meine_ergebnisse, MC_BUEHNE_BONUS)
	print("[PTDLC] Voll-Kasse %s" % str(kasse))
	print("[PTDLC] Meine Rechnung %s (Ergebnisse %s)" % [str(meine), str(_meine_ergebnisse)])
	var summe := int(meine["muenzen_basis"]) + int(meine["trinkgeld"])
	var stimmt := (
		int(kasse.get("punkte", -1)) == int(meine["punkte"])
		and int(kasse.get("trinkgeld", -1)) == int(meine["trinkgeld"])
		and int(kasse.get("muenzen_basis", -1)) == int(meine["muenzen_basis"])
		and int(kasse.get("buehne_trinkgeld", -1)) == MC_BUEHNE_BONUS
		and int(kasse.get("muenzen", -1)) == summe
	)
	if not stimmt:
		print("[PTDLC] Kasse weicht von meiner Rechnung ab!")
		return false
	return pruefe_coins_delta("voll", summe)


## Ende-Karte der vollen Schicht: Wert-Zeilen + Angebots-Block WEG.
func _ende_zeilen_pruefen() -> bool:
	var szene := schicht_szene()
	if szene == null:
		return false
	var kasse: Dictionary = szene.call("schicht_ergebnis")
	var block := harness.root.find_child("AngebotBlock", true, false)
	var block_weg := block == null or not (block as Control).is_visible_in_tree()
	var salz_zeile := label_text("Wert_salz")
	var buehne_zeile := label_text("Wert_buehne")
	var muenzen_zeile := label_text("Wert_muenzen")
	print(
		(
			"[PTDLC] Ende-Karte: salz '%s', buehne '%s', muenzen '%s', Angebot weg=%s"
			% [salz_zeile, buehne_zeile, muenzen_zeile, str(block_weg)]
		)
	)
	if salz_zeile != str(int(szene.get("_salz_treffer"))):
		return false
	if buehne_zeile != str(MC_BUEHNE_BONUS):
		return false
	if muenzen_zeile != str(int(kasse.get("muenzen", -1))):
		return false
	var gespielt := 0
	var gs := game_state()
	if gs != null:
		gespielt = int(gs.get_value("mcgooby.schichten.gespielt", 0))
	print("[PTDLC] Schichten gespielt: %d (soll 2)" % gespielt)
	return block_weg and gespielt == 2
