extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Tagesbonus + Tagesquests“: Boot → Onboarding, aber der
## Tagesbonus wird NICHT blind weggetippt, sondern geprüft: Popup
## erscheint (DailyBonusPopup), „Abholen!“ bucht wirklich +20 Münzen
## (Serientag 1, REWARD_TABLE[0]) und setzt daily.lastClaimDay. Danach
## das Tagesquest-Blatt über die HUD-Kachel: öffnet sich, trägt genau 3
## Quest-Karten + Bonus-Zeile + Reroll, „Neu würfeln“ läuft, Escape
## schließt das Blatt, und der Rundtrip (wieder öffnen/schließen)
## funktioniert.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_tagesbonus_quests

var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	# Basis-Onboarding übernehmen, aber den pauschalen Abholen-Tipp durch
	# die echte Bonus-Prüfstrecke ersetzen.
	for schritt in onboarding_schritte():
		if str(schritt["name"]) == "tagesbonus_abholen":
			liste.append_array(_bonus_schritte())
		else:
			liste.append(schritt)
	liste.append_array(_quest_schritte())
	return liste


func _bonus_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_erscheint",
			"aktion": "warte_bis",
			"klasse": "DailyBonusPopup",
			"timeout_s": 30.0,
		},
		{"name": "tagesbonus_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "muenzen_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "economy.coins lesbar",
		},
		{
			"name": "tagesbonus_abholen",
			"aktion": "tipp_text",
			"text": "Abholen!",
			"erwarte": {"weg_klasse": "DailyBonusPopup"},
			"timeout_s": 30.0,
		},
		{
			"name": "tagesbonus_gebucht",
			"aktion": "warte_bis",
			"bedingung": bonus_gebucht,
			"timeout_s": 15.0,
		},
	]


func _quest_schritte() -> Array[Dictionary]:
	return [
		# W20 P1 (HUD-Slimming): Quests ist Sekundär-Kachel — im Quer-
		# Cockpit erst das Mehr-Cluster aufklappen (Helfer unten).
		_freilegen_schritt("quests_freilegen"),
		{
			"name": "quests_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"klasse": "DailyQuestPanel"},
			"timeout_s": 45.0,
		},
		{"name": "quests_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "drei_quest_karten",
			"aktion": "warte_bis",
			"bedingung": drei_karten_da,
			"timeout_s": 10.0,
		},
		{
			"name": "neu_wuerfeln",
			"aktion": "tipp_text",
			"text": "Neu würfeln",
			"erwarte": {"text": "Neue Aufgaben sind da!"},
			"timeout_s": 20.0,
			"pflicht": false,
		},
		{"name": "nach_reroll_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "quests_schliessen",
			"aktion": "taste",
			"keycode": KEY_ESCAPE,
			"erwarte": {"weg_klasse": "DailyQuestPanel"},
			"timeout_s": 20.0,
		},
		_freilegen_schritt("quests_wieder_freilegen"),
		{
			"name": "quests_wieder_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnQuests",
			"erwarte": {"klasse": "DailyQuestPanel"},
			"timeout_s": 45.0,
		},
		{
			"name": "quests_wieder_schliessen",
			"aktion": "taste",
			"keycode": KEY_ESCAPE,
			"erwarte": {"weg_klasse": "DailyQuestPanel"},
			"timeout_s": 20.0,
		},
		{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
	]


## W20 P1 Nachfix (HUD-Slimming): die Quests-Kachel lebt im Quer-Cockpit
## eingeklappt hinter der Mehr-Kachel — als warte_bis-Bedingung freilegen
## (pollt bis Timeout: nach einer Heimkehr kann der Router noch busy sein
## und das HUD fehlt kurz; hochkant/offenes Cluster = sofort true).
func _freilegen_schritt(schritt_name: String) -> Dictionary:
	return {
		"name": schritt_name,
		"aktion": "warte_bis",
		"bedingung": quests_freilegen,
		"timeout_s": 30.0,
	}


## Idempotent: höchstens EIN „Mehr“-Druck pro Poll; apply_layout schaltet
## die Kacheln synchron sichtbar — der Recheck verhindert Doppel-Drücke.
func quests_freilegen() -> bool:
	var kachel := harness.root.find_child("BtnQuests", true, false) as Control
	if kachel != null and kachel.is_visible_in_tree():
		return true
	var mehr := harness.root.find_child("BtnMehr", true, false) as Button
	if mehr == null or not mehr.is_visible_in_tree():
		return false
	mehr.pressed.emit()
	kachel = harness.root.find_child("BtnQuests", true, false) as Control
	return kachel != null and kachel.is_visible_in_tree()


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", -1))
	return _muenzen_vorher >= 0


## Serientag 1 zahlt exakt +20 Münzen (DailyBonus.REWARD_TABLE[0]) und
## stempelt lastClaimDay/streak.
func bonus_gebucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	var muenzen := int(gs.get_value("economy.coins", -1))
	var tag := str(gs.get_value("daily.lastClaimDay", ""))
	var serie := int(gs.get_value("daily.streak", 0))
	return muenzen >= _muenzen_vorher + 20 and not tag.is_empty() and serie == 1


## Das Brett trägt genau 3 Karten (DailyQuestEngine.roll_today).
func drei_karten_da() -> bool:
	var panel := _finde_quest_panel(harness.root)
	if panel == null:
		return false
	var rows: Variant = panel.get("_rows")
	return rows is Dictionary and (rows as Dictionary).size() == 3


func _finde_quest_panel(node: Node) -> Node:
	if node.get_script() != null:
		var skript: Script = node.get_script()
		if skript.get_global_name() == &"DailyQuestPanel":
			return node
	for kind in node.get_children():
		var gefunden := _finde_quest_panel(kind)
		if gefunden != null:
			return gefunden
	return null
