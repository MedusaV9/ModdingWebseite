extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W19-Playtest — Flow „McGooby Welle B: Kauf-Gate + Belegstation“
## (Doc §2.2 #2/§6.2), kompletter Spieler-Weg in EINEM Save:
## 1) DEMO-PFAD: frischer Save auf Level 14 OHNE Kauf — Detail-Sheet zeigt
##    „Angebot ansehen“ + Demo-Zweitknopf, die Tages-Probeschicht läuft
##    komplett (Grill + Belegstation), die Ende-Karte ist die ehrliche
##    Demo-Variante (kein „Noch eine Schicht“), und der ZWEITE Versuch am
##    selben Tag ist im Hub ehrlich gesperrt (Knopf disabled + Hinweis,
##    Tap reist nicht).
## 2) KAUF-PFAD: Münzen stagen, Angebot-Sheet, „Laden kaufen!“ mit exakter
##    3000er-Abbuchung, direkte Anreise in die erste eigene Schicht.
## 3) BELEGSTATION: Früh-Tap-Probe (straffrei), Perfekt-Wendungen, ECHTER
##    Tab-Wechsel unten, ECHTE Zutaten-Taps in Ticket-Reihenfolge, die
##    PERFEKT-KETTE über Stationen hinweg im Callout, eine absichtlich
##    FALSCHE Zutat (Malus + Kette reißt, Turm bleibt stehen), Kassensturz
##    mit Trinkgeld-Combo und exakter Münz-Gegenprobe.
## Aufruf: tools/ci/run_playtest.sh flow_w19_mcgooby_kauf_belegen

## Demo-Pfad: Münzen bewusst UNTER dem Kaufpreis (3000) halten.
const DEMO_MUENZEN := 500
const KAUF_MUENZEN := 5000

## Münzstände für die Gegenproben (Demo-Schicht / Kauf / Kauf-Schicht).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "staging_level14_arm",
				"aktion": "tue",
				"funktion": stage_level_muenzen.bind(14, DEMO_MUENZEN),
				"erwartung": "Level 14 + %d Münzen gesetzt (Staging)" % DEMO_MUENZEN,
			}
		)
	)
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(_schritte_demo_schicht())
	liste.append_array(_schritte_demo_gesperrt())
	liste.append_array(_schritte_kauf())
	liste.append_array(_schritte_belegstation_showcase())
	liste.append_array(_schritte_kassensturz())
	return liste


## Demo-Pfad: Zweitknopf im Detail-Sheet → Probeschicht komplett spielen →
## Demo-Variante der Ende-Karte.
func _schritte_demo_schicht() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Angebot ansehen"))
	(
		liste
		. append_array(
			[
				{
					"name": "demo_knopf_frei",
					"aktion": "tue",
					"funktion": demo_knopf_frei,
					"erwartung": "Demo-Zweitknopf „Probeschicht starten!“ ist aktiv",
				},
				{
					"name": "probeschicht_starten",
					"aktion": "tipp_text",
					"text": "Probeschicht starten",
					"erwarte": {"route": "mcgooby_schicht"},
					"timeout_s": 180.0,
				},
				{
					"name": "intro_karte_da",
					"aktion": "warte_bis",
					"text": "Schürze umbinden",
					"timeout_s": 60.0,
				},
				{
					"name": "demo_muenzen_merken",
					"aktion": "tue",
					"funktion": _merke_muenzen,
					"erwartung": "Münzstand vor der Probeschicht notiert",
				},
				{
					"name": "schuerze_umbinden",
					"aktion": "tipp_name",
					"node": "SchuerzeKnopf",
					"erwarte": {"bedingung": schicht_laeuft},
					"timeout_s": 30.0,
				},
				{
					"name": "demo_stempel_gesetzt",
					"aktion": "tue",
					"funktion": demo_stempel_heute,
					"erwartung": "mcgooby.demoTag trägt den heutigen Tag",
				},
				{
					"name": "demo_schicht_durchspielen",
					"aktion": "tue",
					"funktion": schicht_fertig_spielen,
					"erwartung": "Probeschicht fehlerfrei bis zur Ende-Karte gespielt",
				},
				{
					"name": "ende_demo_variante",
					"aktion": "tue",
					"funktion": ende_ist_demo_variante,
					"erwartung": "Demo-Ende: kein „Noch eine Schicht“, Hinweis + Angebots-Knopf",
				},
				{
					"name": "demo_muenzen_gutgeschrieben",
					"aktion": "tue",
					"funktion": _kasse_exakt_gutgeschrieben,
					"erwartung": "GENAU kasse.muenzen der Demo-Schicht kamen aufs Konto",
				},
				{"name": "demo_ende_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "demo_feierabend",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"erwarte": {"route": "dlc"},
					"timeout_s": 90.0,
				},
			]
		)
	)
	return liste


## Der ZWEITE Demo-Versuch am selben Tag: ehrlich gesperrt im Hub —
## Knopf disabled, Klartext-Hinweis, ein Tap reist NICHT.
func _schritte_demo_gesperrt() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Angebot ansehen"))
	(
		liste
		. append_array(
			[
				{
					"name": "demo_hinweis_verbraucht",
					"aktion": "warte_bis",
					"text": "Heute schon probiert",
					"timeout_s": 15.0,
				},
				{
					"name": "demo_knopf_disabled",
					"aktion": "tue",
					"funktion": demo_knopf_gesperrt,
					"erwartung": "Demo-Knopf ist nach der Tages-Demo disabled",
				},
				{
					"name": "demo_sperr_tap_probe",
					"aktion": "tipp_name",
					"node": "DemoKnopf",
					"pflicht": false,
				},
				{
					"name": "demo_sperr_tap_reist_nicht",
					"aktion": "tue",
					"funktion": route_bleibt_dlc,
					"erwartung": "Der Tap auf den gesperrten Demo-Knopf startet KEINE Reise",
				},
			]
		)
	)
	return liste


## Kauf-Pfad: Münzen stagen, Angebot-Sheet, atomarer Kauf (exakt 3000),
## direkte Anreise in die erste eigene Schicht.
func _schritte_kauf() -> Array[Dictionary]:
	return [
		{
			"name": "staging_muenzen_reich",
			"aktion": "tue",
			"funktion": stage_level_muenzen.bind(14, KAUF_MUENZEN),
			"erwartung": "Münzstand auf %d gehoben (Staging)" % KAUF_MUENZEN,
		},
		{
			"name": "kauf_angebot_oeffnen",
			"aktion": "tipp_text",
			"text": "Angebot ansehen",
			"erwarte": {"text": "Laden kaufen"},
			"timeout_s": 30.0,
		},
		{
			"name": "kauf_knopf_aktiv",
			"aktion": "tue",
			"funktion": kauf_knopf_aktiv,
			"erwartung": "„Laden kaufen!“ ist mit vollem Säckel NICHT ausgegraut",
		},
		{
			"name": "kauf_muenzen_merken",
			"aktion": "tue",
			"funktion": _merke_muenzen,
			"erwartung": "Münzstand vor dem Kauf notiert",
		},
		{
			"name": "laden_kaufen",
			"aktion": "tipp_text",
			"text": "Laden kaufen",
			"erwarte": {"route": "mcgooby_schicht"},
			"timeout_s": 180.0,
		},
		{
			"name": "kaufpreis_abgebucht",
			"aktion": "tue",
			"funktion": kaufpreis_verbucht,
			"erwartung": "Genau der Kaufpreis (3000) ist weg UND mcgooby.gekauft steht",
		},
		{
			"name": "schicht_startet_direkt",
			"aktion": "warte_bis",
			"bedingung": schicht_laeuft,
			"timeout_s": 60.0,
		},
		{
			"name": "schicht_muenzen_merken",
			"aktion": "tue",
			"funktion": _merke_muenzen,
			"erwartung": "Münzstand vor der ersten eigenen Schicht notiert",
		},
	]


## Belegstation-Showcase (Doc §2.2 #2): Früh-Tap-Probe, Perfekt-Wendungen,
## ECHTER Tab-Wechsel, ECHTE Zutaten-Taps (richtig → Kette, falsch → Malus).
func _schritte_belegstation_showcase() -> Array[Dictionary]:
	return [
		{
			"name": "patty_zeit_null",
			"aktion": "tue",
			"funktion": patty_zeit_zuruecksetzen,
			"erwartung": "Brat-Zeit auf 0 gepinnt (sicher roh)",
		},
		{
			"name": "patty_tap_zu_frueh",
			"aktion": "tipp_name",
			"node": "PattyKnopf",
			"pflicht": false,
		},
		{
			"name": "roh_callout_da",
			"aktion": "warte_bis",
			"bedingung": roh_callout_sichtbar,
			"timeout_s": 5.0,
			"pflicht": false,
		},
		{
			"name": "grill_perfekt_bis_belegen",
			"aktion": "tue",
			"funktion": grill_bis_belegen,
			"erwartung": "Alle Pattys der Bestellung perfekt — Phase wechselt auf Belegen",
		},
		{
			"name": "belegen_tab_tippen",
			"aktion": "tipp_name",
			"node": "Tab_belegen",
			"erwarte": {"bedingung": belegen_station_sichtbar},
			"timeout_s": 20.0,
		},
		{"name": "ticket_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "zutat_richtig_kette",
			"aktion": "tipp_pos",
			"pos_funktion": naechste_zutat_pos,
			"erwarte": {"text": "Perfekt-Kette"},
			"timeout_s": 20.0,
		},
		{
			"name": "turm_waechst",
			"aktion": "tue",
			"funktion": func() -> bool: return belegen_platziert() == 1,
			"erwartung": "Die richtige Zutat sitzt auf dem Turm (1 platziert)",
		},
		{
			"name": "zutat_falsch_probe",
			"aktion": "tipp_pos",
			"pos_funktion": falsche_zutat_pos,
			"erwarte": {"text": "falsche Zutat"},
			"timeout_s": 20.0,
		},
		{
			"name": "falsche_zutat_ehrlich",
			"aktion": "tue",
			"funktion": falsche_zutat_folgen,
			"erwartung": "Falsche Zutat: Turm bleibt bei 1, die Perfekt-Kette ist gerissen",
		},
		{
			"name": "zutat_richtig_weiter",
			"aktion": "tipp_pos",
			"pos_funktion": naechste_zutat_pos,
			"erwarte": {"bedingung": func() -> bool: return belegen_platziert() == 2},
			"timeout_s": 20.0,
		},
		{
			"name": "rest_der_schicht",
			"aktion": "tue",
			"funktion": schicht_fertig_spielen,
			"erwartung": "Restliche Zutaten/Bestellungen fehlerfrei, Schicht endet",
		},
	]


func _schritte_kassensturz() -> Array[Dictionary]:
	return [
		{
			"name": "kassensturz_karte",
			"aktion": "warte_bis",
			"text": "Feierabend!",
			"timeout_s": 60.0,
		},
		{
			"name": "kassensturz_gepruft",
			"aktion": "tue",
			"funktion": kassensturz_ok,
			"erwartung": "Trinkgeld > 0, Combo > ×1,0, Münzen exakt gutgeschrieben",
		},
		{
			"name": "nochmal_knopf_zurueck",
			"aktion": "tue",
			"funktion": nochmal_knopf_sichtbar,
			"erwartung": "Nach dem Kauf zeigt die Ende-Karte wieder „Noch eine Schicht“",
		},
		{"name": "kassensturz_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "feierabend_machen",
			"aktion": "tipp_name",
			"node": "Feierabend",
			"erwarte": {"route": "dlc"},
			"timeout_s": 90.0,
		},
		{"name": "abschluss_ruhe", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------ Gegenproben


func _merke_muenzen() -> bool:
	_muenzen_vorher = muenzstand()
	return _muenzen_vorher >= 0


func demo_knopf_frei() -> bool:
	var knopf := harness.root.find_child("DemoKnopf", true, false)
	return knopf is Button and not (knopf as Button).disabled


func demo_knopf_gesperrt() -> bool:
	var knopf := harness.root.find_child("DemoKnopf", true, false)
	return knopf is Button and (knopf as Button).disabled


func demo_stempel_heute() -> bool:
	var gs := game_state()
	var tag := McGoobyState.heute_tag(gs)
	return not tag.is_empty() and str(gs.get_value("mcgooby.demoTag", "")) == tag


func route_bleibt_dlc() -> bool:
	var router := harness.root.get_node_or_null("/root/SceneRouter")
	return router != null and str(router.get_current_target()) == "dlc" and not router.is_busy()


func kauf_knopf_aktiv() -> bool:
	var knopf := harness.root.find_child("Kaufen", true, false)
	return knopf is Button and not (knopf as Button).disabled


## Progression-Wache: exakt der Katalog-Preis (3000) ging vom Konto und
## der Besitz steht im Save.
func kaufpreis_verbucht() -> bool:
	if _muenzen_vorher < 0:
		return false
	if muenzstand() != _muenzen_vorher - McGoobyKatalog.preis():
		return false
	return bool(game_state().get_value("mcgooby.gekauft", false))


## ------------------------------------------------------------ Schicht-Griffe


func schicht_laeuft() -> bool:
	var szene := aktuelle_szene()
	return szene != null and szene.has_method("ist_am_laufen") and bool(szene.ist_am_laufen())


func belegen_platziert() -> int:
	var szene := aktuelle_szene()
	return int(szene.belegen_platziert()) if szene != null else -1


func belegen_station_sichtbar() -> bool:
	var szene := aktuelle_szene()
	if szene == null or str(szene.station_aktiv()) != "belegen":
		return false
	var box := harness.root.find_child("BelegenBox", true, false)
	return box is Control and (box as Control).is_visible_in_tree()


## Brat-Zeit auf 0 pinnen (sicher roh für den Früh-Tap — echte Frames
## kosten unter llvmpipe je ~0,3–0,5 s, das Fenster wäre sonst Glückssache).
func patty_zeit_zuruecksetzen() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("patty_zeit_setzen"):
		return false
	szene.patty_zeit_setzen(0.0)
	return true


func roh_callout_sichtbar() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var callout: Variant = szene.get("_callout")
	return callout is Label and (callout as Label).text == I18nService.t("dlc_mcgooby.schicht.roh")


## EINE Perfekt-Wendung: Zeit in die Fenster-Mitte pinnen + Knopf-Signal im
## SELBEN Frame (deterministisch, W18-Muster — llvmpipe-Frames machen das
## Echtzeit-Fenster unspielbar).
func _patty_perfekt() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("patty_zeit_setzen"):
		return false
	if not bool(szene.get("_patty_aktiv")):
		return false
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.patty_zeit_setzen(mitte)
	(szene.patty_knopf() as Button).pressed.emit()
	return true


## Alle Pattys der AKTUELLEN Bestellung perfekt wenden, bis die Belegstation
## dran ist (alle Grill-Rezepte der Welle B haben einen Belegen-Schritt).
func grill_bis_belegen() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	for _i in 20:
		if str(szene.phase_aktuell()) == "belegen":
			return true
		if not _patty_perfekt():
			return false
	return str(szene.phase_aktuell()) == "belegen"


## Mitte des Zutaten-Knopfs, den das Ticket als NÄCHSTES verlangt.
func naechste_zutat_pos() -> Vector2:
	var szene := aktuelle_szene()
	if szene == null:
		return Vector2.ZERO
	var ticket: Array = szene.belegen_ticket()
	var idx := int(szene.belegen_platziert())
	if idx >= ticket.size():
		return Vector2.ZERO
	return _zutat_knopf_pos(str(ticket[idx]))


## Mitte eines Zutaten-Knopfs, der NICHT als Nächstes dran ist (jedes
## Welle-B-Ticket hat ≥ 2 verschiedene Zutaten).
func falsche_zutat_pos() -> Vector2:
	var szene := aktuelle_szene()
	if szene == null:
		return Vector2.ZERO
	var ticket: Array = szene.belegen_ticket()
	var idx := int(szene.belegen_platziert())
	var richtig := str(ticket[idx]) if idx < ticket.size() else ""
	for knopf: Button in szene.zutaten_knoepfe():
		var zutat := String(knopf.name).trim_prefix("Zutat_")
		if zutat != richtig:
			return knopf.get_global_rect().get_center()
	return Vector2.ZERO


func _zutat_knopf_pos(zutat_id: String) -> Vector2:
	var knopf := harness.root.find_child("Zutat_" + zutat_id, true, false)
	if not (knopf is Control):
		return Vector2.ZERO
	return (knopf as Control).get_global_rect().get_center()


## Nach der falschen Zutat: Turm unverändert (1 platziert), Kette gerissen.
func falsche_zutat_folgen() -> bool:
	var szene := aktuelle_szene()
	return szene != null and belegen_platziert() == 1 and int(szene.get("_kette")) == 0


## Die komplette (Rest-)Schicht fehlerfrei durchspielen — synchron über
## dieselben Signale, die auch echte Taps feuern: Grill-Wendungen im
## goldenen Fenster, Zutaten in Ticket-Reihenfolge. Schleife hart begrenzt.
func schicht_fertig_spielen() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	for _i in 300:
		if bool(szene.ist_ende_offen()):
			return true
		if str(szene.phase_aktuell()) == "belegen":
			if not _zutat_richtig_druecken(szene):
				return false
		elif not _patty_perfekt():
			return false
	return bool(szene.ist_ende_offen())


func _zutat_richtig_druecken(szene: Node) -> bool:
	var ticket: Array = szene.belegen_ticket()
	var idx := int(szene.belegen_platziert())
	if idx >= ticket.size():
		return false
	var knopf := harness.root.find_child("Zutat_" + str(ticket[idx]), true, false)
	if not (knopf is Button):
		return false
	(knopf as Button).pressed.emit()
	return true


## ------------------------------------------------------------ Ende-Karte


func ende_ist_demo_variante() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not bool(szene.ist_ende_offen()):
		return false
	var nochmal := harness.root.find_child("Nochmal", true, false)
	var hinweis := harness.root.find_child("DemoHinweis", true, false)
	var angebot := harness.root.find_child("EndeAngebot", true, false)
	if not (nochmal is Control and hinweis is Control and angebot is Control):
		return false
	return (
		not (nochmal as Control).visible
		and (hinweis as Control).visible
		and (angebot as Control).visible
	)


func nochmal_knopf_sichtbar() -> bool:
	var nochmal := harness.root.find_child("Nochmal", true, false)
	return nochmal is Control and (nochmal as Control).is_visible_in_tree()


## GENAU kasse.muenzen kamen seit _merke_muenzen aufs Konto.
func _kasse_exakt_gutgeschrieben() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("schicht_ergebnis") or _muenzen_vorher < 0:
		return false
	var kasse: Dictionary = szene.schicht_ergebnis()
	return muenzstand() == _muenzen_vorher + int(kasse.get("muenzen", 0))


## Kassensturz-Gegenprobe der Kauf-Schicht: die falsche Zutat traf nur
## Bestellung 1 — ab Bestellung 2 ist alles fehlerfrei, die Combo zieht
## (> ×1,0), Trinkgeld > 0, und GENAU kasse.muenzen kamen aufs Konto.
func kassensturz_ok() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("schicht_ergebnis"):
		return false
	var kasse: Dictionary = szene.schicht_ergebnis()
	if int(kasse.get("trinkgeld", -1)) <= 0:
		return false
	if float(kasse.get("combo_max_mult", 0.0)) <= 1.0:
		return false
	return _kasse_exakt_gutgeschrieben()
