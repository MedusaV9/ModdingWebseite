extends "res://tests/tools/playtest_flows/flow_pt1_helfer.gd"
## Flow IDEA-WOCHE „Wochen-Vorhaben“ (G8 Progression-Top-1): das Tagesquests-
## Blatt zeigt oben den „Diese Woche“-Abschnitt mit dem deterministisch
## gerollten Bogen der echten Kalenderwoche (Id wird als Beleg geloggt).
## Für den schnell erspielbaren Pfad wird danach der Wellness-Bogen gestellt
## (Debug-Stellung, im Auftrag vorgesehen): Schritt 1 „einmal kitzeln“ wird
## über ECHTE Taps auf Gooby erfüllt (Area3D-Tap + handle_tap-Burst, Muster
## flow_pt1_zuwendung — der dritte Tap in Folge ist die Kitzlig-Stufe), das
## Blatt hakt den Schritt ab und zeigt Goobys Zwischentext von Schritt 2.
## Die Restschritte kommen als Zähler-Stellung über den EINEN Meldepfad
## (gs.update + RewardHub.note_action — exakt der _count_tickle-Weg), das
## OFFENE Blatt zieht live nach („Feiern!“ erscheint ohne Neu-Öffnen), der
## Feiern-Tap zahlt +60/+30 über _pay aus (Toast + Konfetti), danach steht
## der Geschafft-Zustand samt „Nächste Woche“-Zeile und ein zweites
## vorhaben_feiern() bleibt ok=false (Idempotenz im echten Spiel).
## Aufruf: tools/ci/run_playtest.sh flow_woche

## Schnell erspielbarer Bogen für den Flow (Schritt 1: 1× kitzeln).
const BOGEN_ID := "wellness"


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "events_stilllegen",
			"aktion": "tue",
			"funktion": _events_stilllegen,
			"erwartung": "Random-Events liegen für den Lauf auf Cooldown",
		},
	]
	liste.append_array(onboarding_schritte())
	liste.append_array(_angebot_schritte())
	liste.append_array(_kitzel_schritte())
	liste.append_array(_finale_schritte())
	return liste


# ---------------------------------------------------------------- Abschnitte


## Angebot der echten Woche: Bogen läuft nach dem Home-Entry, das Blatt
## zeigt die Sektion mit Titel, Schrittzeilen und Goobys Zwischentext.
func _angebot_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "vorhaben_gerollt",
			"aktion": "warte_bis",
			"bedingung": _vorhaben_aktiv,
			"timeout_s": 30.0,
			"erwartung": "ensure_vorhaben startet den Wochen-Bogen beim Home-Entry",
		},
		{
			"name": "angebot_loggen",
			"aktion": "tue",
			"funktion": _angebot_loggen,
			"erwartung": "quests.vorhaben.woche = ISO-Woche von heute (Wochen-Seed)",
		},
		{
			"name": "blatt_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"text": "Diese Woche"},
			"timeout_s": 45.0,
			"erwartung": "Tagesquests-Blatt öffnet mit dem „Diese Woche“-Abschnitt oben",
		},
		{"name": "angebot_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "sektion_geprueft",
			"aktion": "tue",
			"funktion": _sektion_geprueft,
			"erwartung": "Sektion + Schrittzeile 0 + Zwischentext + Bogen-Titel sichtbar",
		},
		{
			"name": "blatt_zu",
			"aktion": "taste",
			"keycode": KEY_ESCAPE,
			"erwarte": {"weg_klasse": "DailyQuestPanel"},
			"timeout_s": 15.0,
		},
	]


## Wellness stellen und Schritt 1 (1× kitzeln) über echte Taps erfüllen.
func _kitzel_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "wellness_stellen",
			"aktion": "tue",
			"funktion": _wellness_stellen,
			"erwartung": "Debug-Stellung: Wellness-Bogen (Schritt 1: 1× kitzeln) läuft",
		},
		{"name": "kitzel_stand_merken", "aktion": "tue", "funktion": _kitzel_merken},
		# Die Tour-Karte („Schritt 1/9“) kann noch offen sein: beim ersten
		# X-Tap der Basis lag der Sticker-Toast ÜBER dem Schließknopf (Lauf
		# flow_woche_232933) — die Karte deckt Gooby ab und frisst den Tap.
		{
			"name": "tour_x_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 4.0,
			"pflicht": false,
		},
		{
			"name": "tour_ablehnen",
			"aktion": "tipp_falls_da",
			"text": "Lieber nicht",
			"timeout_s": 3.0,
			"pflicht": false,
		},
		{
			"name": "coachmark_wegtippen_zwei",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 3.0,
			"pflicht": false,
		},
		{"name": "overlay_ruhe", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "gooby_echt_antippen",
			"aktion": "tipp_3d",
			"finder": gooby_node,
			"offset": Vector3(0.0, 0.35, 0.0),
			"erwarte": {"bedingung": _pets_gestiegen},
			"timeout_s": 8.0,
			"pflicht": false,
			"erwartung": "Tap auf die GoobyTapArea bucht petsToday +1 (echte Aktion)",
		},
		{
			"name": "tour_x_nachfassen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 2.0,
			"pflicht": false,
		},
		{
			"name": "gooby_zweitversuch",
			"aktion": "tipp_3d",
			"finder": gooby_node,
			"offset": Vector3(0.0, 0.35, 0.0),
			"erwarte": {"bedingung": _pets_gestiegen},
			"timeout_s": 20.0,
			"erwartung": "Zweitversuch nach Overlay-Räumung: petsToday steigt",
		},
		{
			"name": "kitzlig_machen",
			"aktion": "tue",
			"funktion": _kitzel_burst,
			"erwarte": {"bedingung": _schritt_eins_da},
			"timeout_s": 10.0,
			"erwartung": "Kitzlig-Stufe bucht tickles+1 → Vorhaben-Schritt 1 abgehakt",
		},
		{
			"name": "blatt_mit_haekchen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"text": "Blubberblasen"},
			"timeout_s": 45.0,
			"erwartung": "Blatt zeigt Goobys Zwischentext von Schritt 2 (Bad) — 1 abgehakt",
		},
		{"name": "haekchen_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "haekchen_geprueft",
			"aktion": "tue",
			"funktion": _haekchen_geprueft,
			"erwartung": "schritt=1, GENAU +1 tickle, Fortschritts-Label am aktiven Schritt",
		},
	]


## Restschritte über den Meldepfad, Finale feiern, Idempotenz-Probe.
func _finale_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "rest_erspielen",
			"aktion": "tue",
			"funktion": _rest_erspielen,
			"erwarte": {"text": "Feiern!"},
			"timeout_s": 10.0,
			"erwartung": "Bad/Zähne/Futter gebucht → OFFENES Blatt zeigt live Feiern!",
		},
		{"name": "muenzen_vor_feier", "aktion": "tue", "funktion": _muenzen_merken},
		{
			"name": "feiern_tippen",
			"aktion": "tipp_name",
			"node": "VorhabenFeiern",
			"erwarte": {"text": "Vorhaben geschafft"},
			"timeout_s": 20.0,
			"erwartung": "Finale: Toast + Konfetti, Blatt wechselt in den Geschafft-Zustand",
		},
		{"name": "feier_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "feier_geprueft",
			"aktion": "tue",
			"funktion": _feier_geprueft,
			"erwartung": "+60 Münzen gebucht, Slice geleert, letzteId/fertigWoche gestempelt",
		},
		{
			"name": "doppel_feiern_probe",
			"aktion": "tue",
			"funktion": _doppel_feiern_probe,
			"erwartung": "Zweites vorhaben_feiern() bleibt ok=false — kein Doppel-Payout",
		},
		{
			"name": "naechste_woche_zeile",
			"aktion": "warte_bis",
			"text": "Nächste Woche wartet",
			"timeout_s": 10.0,
			"erwartung": "Geschafft-Karte zeigt die „Nächste Woche“-Vorfreude",
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


# ---------------------------------------------------------------- Bausteine


func _heute() -> String:
	var gs := game_state()
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _vorhaben_aktiv() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return not str(gs.get_value("quests.vorhaben.id", "")).is_empty()


## Gerollten Wochen-Bogen als Beleg loggen + Woche-Stempel prüfen.
func _angebot_loggen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var id := str(gs.get_value("quests.vorhaben.id", ""))
	var woche := str(gs.get_value("quests.vorhaben.woche", ""))
	var soll := WochenVorhaben.woche_von(_heute())
	print("[WOCHE] Angebot der Woche %s: Bogen '%s' (Soll-Woche %s)" % [woche, id, soll])
	return merke("angebot_id", id) and woche == soll and not id.is_empty()


## Sichtprüfung der „Diese Woche“-Karte mit dem NATÜRLICH gerollten Bogen.
func _sektion_geprueft() -> bool:
	var def := WochenVorhabenKatalog.def_by_id(str(wert("angebot_id", "")))
	var titel := I18nService.t(WochenVorhabenKatalog.title_key(def))
	var karte := control_da("VorhabenSektion")
	var zeile := control_da("VorhabenSchritt0")
	var zwischen := control_da("VorhabenZwischen")
	var titel_da := text_da(titel)
	print(
		(
			"[WOCHE] Sektion: karte=%s zeile0=%s zwischen=%s titel('%s')=%s"
			% [karte, zeile, zwischen, titel, titel_da]
		)
	)
	return karte and zeile and zwischen and titel_da


## Debug-Stellung: Wellness-Bogen der aktuellen Woche starten (Engine-
## Static, exakt der ensure_aktiv-Unterbau — nur mit fester Bogen-Wahl).
func _wellness_stellen() -> bool:
	var gs := game_state()
	var def := WochenVorhabenKatalog.def_by_id(BOGEN_ID)
	if gs == null or def.is_empty():
		print("[WOCHE] wellness_stellen: GameState/Def fehlt")
		return false
	var woche := WochenVorhaben.woche_von(_heute())
	var ok := {"v": false}
	gs.update(
		func(s: Dictionary) -> void:
			if not (s.get("quests") is Dictionary):
				s["quests"] = {}
			ok["v"] = WochenVorhaben.starte_bogen(s["quests"], def, woche, s)
	)
	gs.notify_slice_changed("quests")
	print("[WOCHE] Wellness gestellt (Woche %s): %s" % [woche, str(ok["v"])])
	return bool(ok["v"])


func _kitzel_merken() -> bool:
	var pets := zahl("achievements.counters.petsToday", 0.0)
	var tickles := zahl("achievements.counters.tickles", 0.0)
	return merke("pets_vorher", pets) and merke("tickles_vorher", tickles)


func _pets_gestiegen() -> bool:
	return zahl("achievements.counters.petsToday", -1.0) > float(wert("pets_vorher", 999.0))


## Kitzlig-Burst: drei schnelle Taps über den ECHTEN Tap-Handler — die
## Stufe „tipp_kitzlig“ (3. Tap in Folge) bucht tickles+1, egal ob der
## Area3D-Tap davor noch im 4-s-Fenster liegt (dann zählt Tap 3 von 4).
func _kitzel_burst() -> bool:
	var runner := gooby_runner()
	if runner == null or not runner.has_method("handle_tap"):
		print("[WOCHE] kitzel_burst: kein GoobyReactions-Runner")
		return false
	for i in 3:
		runner.handle_tap()
	return true


func _schritt_eins_da() -> bool:
	var schritt := zahl("quests.vorhaben.schritt", -1.0)
	var tickles := zahl("achievements.counters.tickles", -1.0)
	print("[WOCHE] Kitzel-Stand: tickles=%s schritt=%s" % [tickles, schritt])
	return schritt >= 1.0


## Häkchen-Beweis: Schritt 1 abgehakt, GENAU ein tickle gebucht (kein
## Doppelzählen im Burst), Fortschritts-Label am aktiven Schritt 2.
func _haekchen_geprueft() -> bool:
	var schritt := zahl("quests.vorhaben.schritt", -1.0)
	var tickles := zahl("achievements.counters.tickles", -1.0)
	var genau_eins := tickles == float(wert("tickles_vorher", -99.0)) + 1.0
	var stand := control_da("VorhabenStand")
	var titel := text_da("Wellness für Weltmeister")
	print(
		(
			"[WOCHE] Häkchen: schritt=%s tickles=%s(+1?=%s) stand=%s titel=%s"
			% [schritt, tickles, genau_eins, stand, titel]
		)
	)
	return schritt == 1.0 and genau_eins and stand and titel


## Bad/Zähne/Futter nacheinander über den EINEN Meldepfad buchen — nach
## jeder Buchung schaltet der Dienst weiter und friert die Baseline des
## Folgeschritts ein; das offene Blatt zieht bei jedem Schritt live nach.
func _rest_erspielen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_zaehler_bump(gs, "washes", 1)
	_zaehler_bump(gs, "teeth_brushed", 1)
	_zaehler_bump(gs, "feeds", 2)
	var schritt := zahl("quests.vorhaben.schritt", -1.0)
	print("[WOCHE] Rest erspielt: schritt=%s (Soll 4)" % schritt)
	return schritt >= 4.0


## Zähler-Buchung wie im Spielcode (Muster gooby_reactions._count_tickle):
## Zähler hoch, dann RewardHub.note_action → slice_changed("achievements").
func _zaehler_bump(gs: Node, key: String, n: int) -> void:
	gs.update(
		func(s: Dictionary) -> void:
			var counters: Dictionary = s.get("achievements", {}).get("counters", {})
			counters[key] = int(counters.get(key, 0)) + n
	)
	RewardHub.note_action(gs)


func _muenzen_merken() -> bool:
	var coins := zahl("economy.coins", -1.0)
	return merke("muenzen_vorher", coins) and coins >= 0.0


## Feier-Beweis: +60 Münzen über _pay, Slice geleert und gestempelt.
func _feier_geprueft() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var coins := zahl("economy.coins", -1.0)
	var vorher := float(wert("muenzen_vorher", -1.0))
	var id := str(gs.get_value("quests.vorhaben.id", "?"))
	var letzte := str(gs.get_value("quests.vorhaben.letzteId", ""))
	var fertig_woche := str(gs.get_value("quests.vorhaben.fertigWoche", ""))
	var woche := WochenVorhaben.woche_von(_heute())
	print(
		(
			"[WOCHE] Feier: coins %s→%s (Soll >= +60) slice id='%s' letzte=%s"
			% [vorher, coins, id, letzte]
		)
	)
	print(
		(
			"[WOCHE] Feier: fertigWoche=%s (Soll %s) xp=%s"
			% [fertig_woche, woche, zahl("progression.xp", -1.0)]
		)
	)
	return coins >= vorher + 60.0 and id.is_empty() and letzte == BOGEN_ID and fertig_woche == woche


## Idempotenz im echten Spiel: ein zweiter Feiern-Aufruf bleibt ok=false
## und zahlt keine 60 Münzen mehr aus (kleine Toleranz für Idle-Münzen).
func _doppel_feiern_probe() -> bool:
	var dienst := DailyQuestService.find_service()
	if dienst == null:
		print("[WOCHE] doppel_feiern: kein DailyQuestService")
		return false
	var vorher := zahl("economy.coins", -1.0)
	var result: Dictionary = dienst.vorhaben_feiern()
	var nachher := zahl("economy.coins", -2.0)
	print("[WOCHE] Doppel-Feiern: ok=%s coins %s→%s" % [str(result.get("ok")), vorher, nachher])
	return not bool(result.get("ok", true)) and nachher < vorher + 60.0
