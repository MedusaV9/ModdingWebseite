extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Morgen-Ritual + Overlay-Dirigent“ (W18/J1, Playtest-Befund E4
## „Overlay-Stau“): Boot → Onboarding, dann wird der inszenierte Tagesstart
## Schritt für Schritt BELEGT statt blind weggetippt:
## 1. Direkt beim Ankommen ist KEIN Tagesbonus-Schleier da (Begrüßungs-
##    Fenster — die Bühne gehört Gooby).
## 2. DANN gleitet das Tagesbonus-Blatt rein — und zwar ALLEIN (Guide-Karte
##    geduckt, Coachmark geparkt: nie zwei Willkommens-Schichten).
## 3. „Abholen!“ bucht wirklich +20 Münzen (Serientag 1) und stempelt
##    daily.lastClaimDay.
## 4. DANN ist der Coachmark dran — wieder allein.
## 5. DANN kehrt die Guide-/Tour-Karte von selbst zurück (X beendet sie).
## 6. Gegenprobe „keine toten Tap-Zonen“: die Küchentür ist nach dem
##    Sequenz-Ende sofort tippbar (Tür-Dialog „Los!“ → Raumwechsel).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_morgen_ritual

var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	# Onboarding-Karten wie ein Spieler — aber NUR bis zur Ankunft: die
	# pauschalen Wegtipp-Schritte ersetzt hier die echte Ritual-Prüfstrecke.
	for schritt in onboarding_schritte():
		liste.append(schritt)
		if str(schritt["name"]) == "onboarding_fertig":
			break
	liste.append_array(_ritual_schritte())
	liste.append_array(_tuer_gegenprobe())
	return liste


func _ritual_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "gruss_fenster_ohne_popup",
			"aktion": "tue",
			"funktion": kein_tagesbonus_da,
			"erwartung": "beim Ankommen erst Gooby-Gruß, KEIN Tagesbonus-Schleier",
		},
		{
			"name": "tagesbonus_gleitet_rein",
			"aktion": "warte_bis",
			"klasse": "DailyBonusPopup",
			"timeout_s": 30.0,
		},
		{
			"name": "bonus_allein_kein_stau",
			"aktion": "tue",
			"funktion": bonus_allein,
			"erwartung": "Blatt allein: Guide-Karte geduckt, Coachmark geparkt",
		},
		{"name": "tagesbonus_ansehen", "aktion": "warte", "sekunden": 1.5},
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
		{
			"name": "coachmark_kommt_dran",
			"aktion": "warte_bis",
			"text": "Alles klar!",
			"timeout_s": 15.0,
		},
		{
			"name": "coachmark_allein_kein_stau",
			"aktion": "tue",
			"funktion": coachmark_allein,
			"erwartung": "Coachmark allein: Bonus weg, Guide-Karte noch geduckt",
		},
		{
			"name": "coachmark_wegtippen",
			"aktion": "tipp_text",
			"text": "Alles klar!",
			"erwarte": {"weg_text": "Alles klar!"},
			"timeout_s": 15.0,
		},
		{
			"name": "guide_kehrt_zurueck",
			"aktion": "warte_bis",
			"bedingung": guide_karte_sichtbar,
			"timeout_s": 15.0,
		},
		{
			"name": "guide_tour_beenden",
			"aktion": "tipp_name",
			"node": "GuideBeenden",
			"timeout_s": 20.0,
		},
		{
			"name": "guide_karte_weg",
			"aktion": "warte_bis",
			"bedingung": guide_karte_weg,
			"timeout_s": 15.0,
		},
	]


## Gegenprobe „keine toten Tap-Zonen“ (Muster flow_home_tuer_gegenprobe):
## nach dem Sequenz-Ende muss die Küchentür sofort tippbar sein.
func _tuer_gegenprobe() -> Array[Dictionary]:
	return [
		{
			"name": "was_nun_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 8.0,
			"pflicht": false,
		},
		{
			"name": "tuer_zur_kueche_tippen",
			"aktion": "tipp_3d",
			"finder": finde_tuer.bind("kitchen"),
			"offset": Vector3(0.0, 1.0, 0.0),
			"erwarte": {"text": "Los!"},
			"timeout_s": 45.0,
		},
		{
			"name": "tuer_bestaetigen",
			"aktion": "tipp_text",
			"text": "Los!",
			"erwarte": {"route": "home/kitchen"},
			"timeout_s": 120.0,
			"nebenbei_tipp_klasse": "TapMashOverlay",
		},
		{"name": "kueche_ankommen", "aktion": "warte", "sekunden": 2.0},
	]


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


func kein_tagesbonus_da() -> bool:
	return _finde_sichtbare_klasse(harness.root, "DailyBonusPopup") == null


## Während das Blatt offen ist: Guide-Karte geduckt, Coachmark geparkt.
func bonus_allein() -> bool:
	if _finde_sichtbare_klasse(harness.root, "DailyBonusPopup") == null:
		return false
	return not _name_sichtbar("GuideKarte") and not _name_sichtbar("HudCoachmark")


## Während der Coachmark dran ist: Bonus weg, Guide-Karte noch geduckt.
func coachmark_allein() -> bool:
	if not _name_sichtbar("HudCoachmark"):
		return false
	if _finde_sichtbare_klasse(harness.root, "DailyBonusPopup") != null:
		return false
	return not _name_sichtbar("GuideKarte")


func guide_karte_sichtbar() -> bool:
	return _name_sichtbar("GuideKarte")


func guide_karte_weg() -> bool:
	return not _name_sichtbar("GuideKarte")


func _name_sichtbar(node_name: String) -> bool:
	var node := harness.root.find_child(node_name, true, false)
	if node == null:
		return false
	if node is Control:
		return (node as Control).is_visible_in_tree()
	return true


func _finde_sichtbare_klasse(node: Node, klasse: String) -> Node:
	if node.get_script() != null:
		var skript: Script = node.get_script()
		if skript.get_global_name() == StringName(klasse):
			if not (node is Control) or (node as Control).is_visible_in_tree():
				return node
	for kind in node.get_children():
		var gefunden := _finde_sichtbare_klasse(kind, klasse)
		if gefunden != null:
			return gefunden
	return null
