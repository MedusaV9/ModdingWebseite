extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Flow (e) „McGooby-Probeschicht“ (Welle H): über Einstellungen →
## DLC-Hub die McGooby-Karte öffnen („Probeschicht starten!“ — Welle A ist
## ohne Kauf-Gate frei spielbar), Intro-Karte lesen, Schürze umbinden und
## ZWEI komplette Schichten am Grill spielen. Patty 1 wird EHRLICH in
## Echtzeit versucht (warte auf „JETZT wenden!“, dann Tap — bei llvmpipe-FPS
## ist das goldene 1,4-s-Fenster ein echter Härtetest, Ausgang offen);
## alle weiteren Pattys nutzen die Test-API der Szene (patty_zeit_setzen
## in die Fenster-Mitte + Knopfdruck) für deterministische „Perfekt!“-
## Wendungen inkl. Trinkgeld-Combo. Geprüft: Pause/Weiter, Kassensturz
## (muenzen == basis + trinkgeld, Münzen EXAKT gutgeschrieben, Schicht-
## Zähler), „Noch eine Schicht“ (Reset + neuer Seed) und „Feierabend
## machen“ (zurück in den DLC-Hub).
## Aufruf: tools/ci/run_playtest.sh flow_pt2_mcgooby

## Fester Seed → deterministische Bestell-Folge (Tages-Seed wäre datumsabhängig).
const SEED := 20260802
## Großzügig über dem Maximum (4 Bestellungen × 2 Pattys = 8).
const PATTY_RESERVE := 12


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
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
				# BUG-Umgehung (Befund pt2_d1): Settings-Overlay bleibt über
				# dem DLC-Hub offen — Zurück-Tipp legt den Hub frei (erst
				# Veil ausrollen lassen, sonst frisst der Vorhang den Tipp).
				{"name": "reise_ausrollen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "settings_overlay_schliessen",
					"aktion": "tipp_name",
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
		)
	)
	# Detail-Sheet: AktionKnopf unterm Falz — erst ins Bild rollen
	# (Befund pt2_d3 im Goobye-Flow, gleiches Sheet-Muster).
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
				{
					"name": "intro_karte",
					"aktion": "warte_bis",
					"text": "Die große Eröffnung",
					"timeout_s": 30.0,
				},
				{
					"name": "seed_pinnen",
					"aktion": "tue",
					"funktion": szene_prop.bind("seed_override", SEED),
				},
				{
					"name": "schicht_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("schicht1"),
				},
				{
					"name": "schuerze_umbinden",
					"aktion": "tipp_name",
					"node": "SchuerzeKnopf",
					"erwarte": {"weg_text": "Die große Eröffnung"},
					"timeout_s": 30.0,
				},
				{"name": "schicht_laeuft", "aktion": "tue", "funktion": _schicht_laeuft},
				# Pause sofort testen — pausiert brät der Patty NICHT weiter.
				{
					"name": "pause_oeffnen",
					"aktion": "tipp_name",
					"node": "Pause",
					"timeout_s": 20.0
				},
				{
					"name": "pause_modal_da",
					"aktion": "warte_bis",
					"bedingung": control_da.bind("ResumeButton"),
					"timeout_s": 20.0,
				},
				{
					"name": "weiter_braten",
					"aktion": "tipp_name",
					"node": "ResumeButton",
					"timeout_s": 20.0,
				},
				# Patty 1 EHRLICH: auf das goldene Fenster warten und real tippen.
				{
					"name": "goldbraun_abwarten",
					"aktion": "warte_bis",
					"text": "JETZT wenden!",
					"timeout_s": 90.0,
					"pflicht": false,
				},
				{
					"name": "patty_1_echt_wenden",
					"aktion": "tipp_name",
					"node": "PattyKnopf",
					"timeout_s": 20.0,
				},
				{"name": "echt_ergebnis", "aktion": "tue", "funktion": _echt_ergebnis_loggen},
			]
		)
	)
	liste.append_array(_patty_steps("s1", PATTY_RESERVE))
	(
		liste
		. append_array(
			[
				{
					"name": "feierabend_karte",
					"aktion": "warte_bis",
					"text": "Feierabend!",
					"timeout_s": 120.0,
				},
				{
					"name": "kassensturz_konsistent",
					"aktion": "tue",
					"funktion": _kasse_pruefen.bind("schicht1"),
					"erwartung": "muenzen == basis + trinkgeld UND exakt gutgeschrieben",
				},
				{
					"name": "trinkgeld_combo",
					"aktion": "tue",
					"funktion": _trinkgeld_da,
					"erwartung": "Trinkgeld > 0 (fehlerfreie Bestellungen in Folge)",
					"pflicht": false,
				},
				{
					"name": "schicht_verbucht",
					"aktion": "tue",
					"funktion": _schichten_gespielt.bind(1),
					"erwartung": "mcgooby.schichten.gespielt == 1",
				},
				{
					"name": "zweite_coins_merken",
					"aktion": "tue",
					"funktion": merke_coins.bind("schicht2"),
				},
				{
					"name": "noch_eine_schicht",
					"aktion": "tipp_name",
					"node": "Nochmal",
					"erwarte": {"weg_text": "Feierabend!"},
					"timeout_s": 30.0,
				},
				{
					"name": "zweite_schicht_frisch",
					"aktion": "tue",
					"funktion": _punkte_resettet,
					"erwartung": "Punkte wieder 0, Schicht läuft (neuer Seed = Runde+1)",
				},
			]
		)
	)
	liste.append_array(_patty_steps("s2", PATTY_RESERVE))
	(
		liste
		. append_array(
			[
				{
					"name": "feierabend_karte_2",
					"aktion": "warte_bis",
					"text": "Feierabend!",
					"timeout_s": 120.0,
				},
				{
					"name": "kassensturz_2_konsistent",
					"aktion": "tue",
					"funktion": _kasse_pruefen.bind("schicht2"),
					"erwartung": "auch Schicht 2 exakt verbucht",
				},
				{
					"name": "schicht_2_verbucht",
					"aktion": "tue",
					"funktion": _schichten_gespielt.bind(2),
					"erwartung": "mcgooby.schichten.gespielt == 2",
				},
				{
					"name": "feierabend_machen",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"erwarte": {"weg_klasse": "McGoobySchichtScene"},
					"timeout_s": 120.0,
				},
				{
					"name": "zurueck_im_hub",
					"aktion": "warte_bis",
					"klasse": "DlcScreen",
					"timeout_s": 30.0,
					"pflicht": false,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Reserve-Schritte: jeder wendet (falls die Schicht noch läuft) EINEN Patty
## deterministisch perfekt — überzählige Schritte melden nur „nichts zu tun“.
func _patty_steps(prefix: String, anzahl: int) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for i in range(anzahl):
		(
			steps
			. append(
				{
					"name": "%s_patty_%02d" % [prefix, i + 2],
					"aktion": "tue",
					"funktion": _patty_perfekt,
					"pflicht": false,
				}
			)
		)
	return steps


func _schicht_szene() -> Node:
	var szene := aktuelle_szene()
	return szene if szene is McGoobySchichtScene else null


func _schicht_laeuft() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var folge: Array = szene.get("_folge")
	print("[PT2] Schicht läuft: %d Bestellungen im Plan" % folge.size())
	for bestellung: Dictionary in folge:
		print(
			(
				"[PT2]   Bestellung %d: %s × %d Patty(s)"
				% [
					int(bestellung.get("nr", 0)),
					str(bestellung.get("rezept_id", "?")),
					int(bestellung.get("patties", 1)),
				]
			)
		)
	return bool(szene.call("ist_am_laufen"))


## Ausgang des ehrlichen Echtzeit-Taps festhalten (Perfekt/Röstaroma/roh).
func _echt_ergebnis_loggen() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	print(
		(
			"[PT2] Nach Echt-Tap: Punkte %d, Perfekt %d, Callout '%s'"
			% [
				int(szene.get("_punkte")),
				int(szene.get("_perfekt_gesamt")),
				szene.get("_callout").text
			]
		)
	)
	return true


## EIN Patty deterministisch perfekt wenden: Brat-Zeit in die Mitte des
## goldenen Fensters pinnen (Test-API der Szene), dann der Knopfdruck.
func _patty_perfekt() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	if bool(szene.call("ist_ende_offen")):
		print("[PT2] Schicht vorbei — nichts mehr zu braten")
		return true
	if not bool(szene.call("ist_am_laufen")):
		print("[PT2] Schicht läuft nicht (pausiert?)")
		return false
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.call("patty_zeit_setzen", mitte)
	var knopf: Button = szene.call("patty_knopf")
	if knopf == null:
		return false
	knopf.pressed.emit()
	print("[PT2] Patty gewendet bei %.2f s → Punkte %d" % [mitte, int(szene.get("_punkte"))])
	return true


## Kassensturz: Summe stimmig UND Münzen exakt aufs Konto (Delta seit Marke).
func _kasse_pruefen(marke: String) -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var kasse: Dictionary = szene.call("schicht_ergebnis")
	print("[PT2] Kasse: %s" % str(kasse))
	var basis := int(kasse.get("muenzen_basis", 0))
	var trinkgeld := int(kasse.get("trinkgeld", 0))
	var summe := int(kasse.get("muenzen", 0))
	if summe != basis + trinkgeld:
		print("[PT2] Kassensturz inkonsistent: %d != %d + %d" % [summe, basis, trinkgeld])
		return false
	return pruefe_coins_delta(marke, summe)


func _trinkgeld_da() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var trinkgeld := int(szene.call("schicht_ergebnis").get("trinkgeld", 0))
	print("[PT2] Trinkgeld: %d" % trinkgeld)
	return trinkgeld > 0


func _schichten_gespielt(soll: int) -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var gespielt := int(gs.get_value("mcgooby.schichten.gespielt", 0))
	var bestwert := int(gs.get_value("mcgooby.schichten.bestwert", 0))
	print("[PT2] Schichten gespielt: %d (soll %d), Bestwert %d" % [gespielt, soll, bestwert])
	return gespielt == soll


func _punkte_resettet() -> bool:
	var szene := _schicht_szene()
	if szene == null:
		return false
	var punkte := int(szene.get("_punkte"))
	print("[PT2] Punkte nach Nochmal: %d" % punkte)
	return punkte == 0 and bool(szene.call("ist_am_laufen"))
