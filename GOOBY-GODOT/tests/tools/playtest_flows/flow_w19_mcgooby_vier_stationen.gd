extends "res://tests/tools/playtest_flows/flow_w18_dlc5_basis.gd"
## W19-Playtest — Flow „McGooby Welle C: vier Stationen + Laden-Rang“
## (Doc §2.2 #3/#4, §6.1), Spieler-Weg NACH dem Kauf in EINEM Save:
## 1) Staging: Level 14 + Münzen + mcgooby.gekauft (der ehrliche Kauf-Weg
##    ist bereits vom Welle-B-Wächter flow_w19_mcgooby_kauf_belegen
##    abgedeckt — dieser Flow prüft den AUSBAU dahinter).
## 2) Hub → „Schicht starten!“ → Intro → Schichten spielen, bis Fritteuse
##    UND Shake-Bar real dran waren (bestell_folge zieht seit Welle C aus
##    ALLEN Rezepten; Bestellung 2 kommt garantiert vom neuen Tresen).
##    Pro Phase wird geprüft, dass der Stations-Tab der Arbeit folgt;
##    Timing-Runden werden im goldenen Fenster der JEWEILIGEN Station
##    gespielt (Zeit gepinnt — llvmpipe-Frames machen Echtzeit-Fenster
##    unspielbar, W18-Muster).
## 3) Ende-Karte zeigt den Laden-Rang (Sterne-Band, Welle C §6.1) und der
##    DLC-Hub zeigt dieselbe Rang-Zeile ehrlich im Detail-Sheet.
## Aufruf: tools/ci/run_playtest.sh flow_w19_mcgooby_vier_stationen

const STAGE_MUENZEN := 5000
## Sicherheitsdeckel: so viele Schichten dürfen maximal laufen, bis beide
## neuen Stationen dran waren (praktisch reichen 1–3).
const MAX_SCHICHTEN := 12

## Welche Stations-Phasen der Bot wirklich gespielt hat.
var _gesehen: Dictionary = {}


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append(
			{
				"name": "staging_gekauft",
				"aktion": "tue",
				"funktion": _stage_gekauft,
				"erwartung": "Level 14 + %d Münzen + mcgooby.gekauft (Staging)" % STAGE_MUENZEN,
			}
		)
	)
	liste.append_array(schritte_zur_bibliothek())
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Schicht starten"))
	(
		liste
		. append_array(
			[
				{
					"name": "schicht_starten",
					"aktion": "tipp_text",
					"text": "Schicht starten",
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
					"name": "schuerze_umbinden",
					"aktion": "tipp_name",
					"node": "SchuerzeKnopf",
					"erwarte": {"bedingung": schicht_laeuft},
					"timeout_s": 30.0,
				},
				{
					"name": "vier_stationen_erspielen",
					"aktion": "tue",
					"funktion": vier_stationen_erspielen,
					"erwartung": "Fritteuse UND Shake-Bar real gespielt — Tabs folgten der Arbeit",
				},
				{
					"name": "ende_karte_da",
					"aktion": "warte_bis",
					"text": "Feierabend!",
					"timeout_s": 60.0,
				},
				{
					"name": "ende_zeigt_rang",
					"aktion": "tue",
					"funktion": ende_zeigt_rang,
					"erwartung": "Ende-Karte zeigt den Laden-Rang (Sterne-Band + Ziel)",
				},
				{"name": "ende_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "feierabend_machen",
					"aktion": "tipp_name",
					"node": "Feierabend",
					"erwarte": {"route": "dlc"},
					"timeout_s": 90.0,
				},
			]
		)
	)
	liste.append_array(schritte_detail_oeffnen("mcgooby", "Schicht starten"))
	(
		liste
		. append_array(
			[
				{
					"name": "hub_zeigt_rang",
					"aktion": "tue",
					"funktion": hub_zeigt_rang,
					"erwartung": "DLC-Hub-Detail zeigt dieselbe Rang-Zeile (ehrlich)",
				},
				# Sheet vor dem Abschluss schließen: bleibt es beim Quit
				# offen, feuert sein tree_exiting ins HUD (hud_sichtbarkeit)
				# und der Teardown loggt einen get_node-ERROR (Log-Befund).
				schritt_sheet_schliessen("detail_mcgooby_schliessen"),
				{"name": "abschluss_ruhe", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ------------------------------------------------------------ Staging


func _stage_gekauft() -> bool:
	if not stage_level_muenzen(14, STAGE_MUENZEN):
		return false
	# Kauf-Weg ist vom Welle-B-Flow gewacht — hier zählt der Zustand DANACH.
	game_state().set_value("mcgooby.gekauft", true)
	return bool(game_state().get_value("mcgooby.gekauft", false))


## ------------------------------------------------------ Schicht-Griffe


func schicht_laeuft() -> bool:
	var szene := aktuelle_szene()
	return szene != null and szene.has_method("ist_am_laufen") and bool(szene.ist_am_laufen())


## Schichten spielen (max. MAX_SCHICHTEN), bis Fritteuse UND Shake-Bar
## wirklich dran waren — nach dem Kauf startet „Noch eine Schicht“ die
## nächste Runde (neuer Seed = neuer Kundenstrom).
func vier_stationen_erspielen() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	_gesehen = {}
	for _schicht in MAX_SCHICHTEN:
		if not _schicht_durchspielen(szene):
			return false
		if _gesehen.has("fritteuse") and _gesehen.has("shake"):
			return true
		var nochmal := harness.root.find_child("Nochmal", true, false)
		if not (nochmal is Button) or not (nochmal as Button).is_visible_in_tree():
			return false
		(nochmal as Button).pressed.emit()
	return false


## EINE Schicht synchron durchspielen (Signale wie echte Taps): Zutaten in
## Ticket-Reihenfolge, Timing-Runden im goldenen Fenster der aktiven
## Station; nebenbei sammeln, welche Stationen dran waren, und prüfen,
## dass der Stations-Tab der Arbeit folgt (wechsle_station beim
## Phasen-Start — der Bot wechselt selbst NIE).
func _schicht_durchspielen(szene: Node) -> bool:
	for _i in 400:
		if bool(szene.ist_ende_offen()):
			return true
		var phase := str(szene.phase_aktuell())
		_gesehen[phase] = true
		if str(szene.station_aktiv()) != phase:
			return false
		if phase == "belegen":
			if not _zutat_richtig_druecken(szene):
				return false
		elif not _runde_perfekt(szene):
			return false
	return bool(szene.ist_ende_offen())


## EINE Timing-Runde perfekt (Zeit in die Fenster-Mitte der AKTIVEN
## Station pinnen + Knopf-Signal im selben Frame — deterministisch).
func _runde_perfekt(szene: Node) -> bool:
	if not bool(szene.get("_patty_aktiv")):
		return false
	var timing: Dictionary = szene.get("_patty_timing")
	var mitte := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4)) * 0.5
	szene.patty_zeit_setzen(mitte)
	(szene.patty_knopf() as Button).pressed.emit()
	return true


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


## ------------------------------------------------------------ Rang-Wachen


func ende_zeigt_rang() -> bool:
	var rang := harness.root.find_child("Wert_rang", true, false)
	if not (rang is Label) or not (rang as Label).is_visible_in_tree():
		return false
	if not (rang as Label).text.contains("★"):
		return false
	var ziel := harness.root.find_child("RangZiel", true, false)
	return ziel is Label and (ziel as Label).is_visible_in_tree()


func hub_zeigt_rang() -> bool:
	var rang := harness.root.find_child("McGoobyRang", true, false)
	if not (rang is Label) or not (rang as Label).is_visible_in_tree():
		return false
	return (rang as Label).text.contains("★")
