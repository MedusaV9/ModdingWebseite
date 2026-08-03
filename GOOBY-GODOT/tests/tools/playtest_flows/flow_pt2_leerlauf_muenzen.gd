extends "res://tests/tools/playtest_flows/flow_pt2_basis.gd"
## PT-2 Mini-Flow „Leerlauf-Münzen“ (W18/R3 PT2-B13): Ledger-Wache über
## Economy.award_tap. Der Flow steht ~4,5 min still im Wohnzimmer (wie der
## Playtest-Befund „+5 ᴳ / 4 min, Quelle offen“) und zieht danach Bilanz:
## JEDE Buchung trägt den Seelen-Reason `soul_sofa_fund` (nichts bleibt
## unerklärt), der Konto-Zuwachs entspricht EXAKT der Buchungssumme und
## bleibt unter dem Tagesdeckel (Economy.SOUL_DAY_CAP). Danach wird ein
## Fund direkt am Runner erzwungen (Toast „… hat 1 ᴳ gefunden!“ wird
## sichtbar) und der Deckel bis zum Anschlag geprobt (Folgebuchung = 0).
## Aufruf: tools/ci/run_playtest.sh flow_pt2_leerlauf_muenzen

const Economy := preload("res://scripts/logic/economy.gd")

## ~4,5 min Leerlauf in Häppchen — jede Runde liefert einen Screenshot.
const LEERLAUF_RUNDEN := 5
const LEERLAUF_S := 55.0

var _buchungen: Array[Dictionary] = []


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "wache_starten",
					"aktion": "tue",
					"funktion": _wache_starten,
					"erwartung": "award_tap installiert, Kontostand gemerkt",
				},
			]
		)
	)
	for i in LEERLAUF_RUNDEN:
		(
			liste
			. append(
				{
					"name": "leerlauf_%d" % (i + 1),
					"aktion": "warte",
					"sekunden": LEERLAUF_S,
				}
			)
		)
	(
		liste
		. append_array(
			[
				{
					"name": "wache_bilanz",
					"aktion": "tue",
					"funktion": _wache_bilanz,
					"erwartung": "nur soul_sofa_fund-Buchungen, Delta == Summe ≤ Deckel",
				},
				{
					"name": "fund_erzwingen",
					"aktion": "tue",
					"funktion": _fund_erzwingen,
					"erwartung": "Runner bucht +1 soul_sofa_fund (Toast folgt)",
				},
				{
					"name": "fund_toast_da",
					"aktion": "warte_bis",
					"text": "ᴳ gefunden",
					"timeout_s": 6.0,
				},
				{
					"name": "deckel_probe",
					"aktion": "tue",
					"funktion": _deckel_probe,
					"erwartung": "Restplatz füllbar, dann bucht der Deckel 0",
				},
				{
					"name": "wache_stoppen",
					"aktion": "tue",
					"funktion": _wache_stoppen,
				},
				{"name": "abschluss", "aktion": "warte", "sekunden": 1.5},
			]
		)
	)
	return liste


## Tap installieren + Kontostand merken — ab jetzt wird JEDE Buchung
## (reason, angefragt, gewährt) mitgeschrieben.
func _wache_starten() -> bool:
	_buchungen.clear()
	Economy.award_tap = _notiere_buchung
	return merke_coins("leerlauf")


func _notiere_buchung(reason: String, angefragt: int, gewaehrt: int) -> void:
	_buchungen.append({"reason": reason, "angefragt": angefragt, "gewaehrt": gewaehrt})
	print("[PT2-B13] award: reason='%s' angefragt=%d gewaehrt=%d" % [reason, angefragt, gewaehrt])


## Bilanz nach dem Leerlauf: kein fremder Reason, Konto-Delta == Summe der
## gewährten Seelen-Funde, Summe unterm Tagesdeckel. (0 Buchungen sind ok —
## die Seelen-Bremse darf den Fund auch mal auslassen; entscheidend ist,
## dass NICHTS Unerklärtes bucht.)
func _wache_bilanz() -> bool:
	var summe := 0
	var fremd := 0
	for buchung: Dictionary in _buchungen:
		if str(buchung["reason"]) == "soul_sofa_fund":
			summe += int(buchung["gewaehrt"])
		else:
			fremd += 1
			print("[PT2-B13] UNERKLÄRTE Buchung: %s" % str(buchung))
	var delta := coins() - int(zettel.get("leerlauf", 0))
	print(
		(
			"[PT2-B13] Bilanz: %d Buchungen, Seelen-Summe %d, Konto-Delta %d, fremd %d"
			% [_buchungen.size(), summe, delta, fremd]
		)
	)
	return fremd == 0 and delta == summe and summe <= Economy.SOUL_DAY_CAP


## Einen Fund DIREKT am Runner auslösen (deterministisch statt auf die
## 90-s-Seelen-Bremse zu warten) — beweist Buchung + Toast im echten Spiel.
func _fund_erzwingen() -> bool:
	var runner := _finde_runner()
	if runner == null:
		print("[PT2-B13] kein GoobyReactions-Runner im Raum")
		return false
	var vorher := coins()
	var gewaehrt := int(runner.call("_grant_coins", 1))
	print("[PT2-B13] erzwungener Fund: gewährt %d (Konto %d → %d)" % [gewaehrt, vorher, coins()])
	return gewaehrt == 1 and coins() == vorher + 1


## Deckel-Probe: Restplatz in EINEM Schwung füllen, dann muss die nächste
## Buchung 0 gewähren (Tagesdeckel greift wirklich).
func _deckel_probe() -> bool:
	var gs := game_state()
	var runner := _finde_runner()
	if gs == null or runner == null:
		return false
	var tag := SoulTriggers.day_string(Time.get_datetime_dict_from_system())
	var rest := {"n": 0}
	gs.update(
		func(s: Dictionary) -> void:
			var econ: Dictionary = s["economy"]
			rest["n"] = Economy.award(econ, Economy.SOUL_DAY_CAP, "soul_sofa_fund", tag)
	)
	var voll := int(runner.call("_grant_coins", 1))
	var headroom := {"n": -1}
	gs.update(func(s: Dictionary) -> void: headroom["n"] = Economy.soul_headroom(s["economy"], tag))
	print(
		(
			"[PT2-B13] Deckel-Probe: Rest gefüllt %d, Folgebuchung %d, Headroom %d"
			% [int(rest["n"]), voll, int(headroom["n"])]
		)
	)
	return voll == 0 and int(headroom["n"]) == 0


func _wache_stoppen() -> bool:
	Economy.award_tap = Callable()
	print("[PT2-B13] award_tap wieder ausgehängt")
	return true


func _finde_runner() -> Node:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is GoobyReactions:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
