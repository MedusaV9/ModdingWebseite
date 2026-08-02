extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Flow (e) „Quest-Loop": die deterministische Wirtschafts-Quest
## „Einkaufsbummel" (einkauf1: 1 Münze ausgeben; im Fresh-Save-Kontext für
## Anfang August gerollt — der Flow loggt die echten Ids als Beleg) durch
## einen ECHTEN Garderoben-Kauf (Beanie, 100 Münzen) erfüllen → Tagesquest-
## Blatt öffnen (ERSTES Öffnen! Wegen des G8-Befunds „Wieder-Öffnen bringt
## leeres Blatt" — s. flow_pt4_sheets — wird das Blatt hier ERST NACH dem
## Kauf geöffnet, damit „Abholen" im funktionierenden Erst-Öffnen liegt) →
## Belohnung abholen („Quest geschafft! +… Münzen, +… XP", Häkchen
## „Erledigt!") → der Erfolg „Macher" (erste Tagesquest, +10 Münzen)
## PLOPPT als Toast → Münzstand steigt (Progressions-Beleg) → Blatt per
## Runterwischen zu → Wieder-Öffnen-Probe (G8-Regression, pflicht=false).
## Tagesbonus (Onboarding-Kette) steckt in onboarding_schritte().
## Aufruf: tools/ci/run_playtest.sh flow_pt4_quests


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{"name": "quests_loggen", "aktion": "tue", "funktion": quests_loggen},
				{
					"name": "einkauf_quest_gerollt",
					"aktion": "warte_bis",
					"bedingung": einkauf_quest_da,
					"timeout_s": 8.0,
					"pflicht": false,
				},
				# ── Quest erfüllen: Einkauf in der Garderobe (Beanie, 100).
				{
					"name": "garderobe_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnWardrobe",
					"erwarte": {"route": "wardrobe"},
					"timeout_s": 60.0,
				},
				{"name": "garderobe_ansehen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "beanie_kaufen_fuer_quest",
					"aktion": "tipp_name",
					"node": "Item_beanie",
					"erwarte": {"bedingung": muenzen_ausgegeben},
					"timeout_s": 20.0,
				},
				{
					"name": "zurueck_ins_wohnzimmer",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 60.0,
				},
				{"name": "wohnzimmer_kurz", "aktion": "warte", "sekunden": 2.0},
				{"name": "muenzen_vor_belohnung", "aktion": "tue", "funktion": merke_muenzen},
				# ── Belohnung abholen + Erfolg (ERSTES Blatt-Öffnen, s. Kopf).
				{
					"name": "quests_blatt_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnQuests",
					"erwarte": {"text": "Abholen"},
					"timeout_s": 45.0,
				},
				{"name": "abholen_knopf_ansehen", "aktion": "warte", "sekunden": 1.5},
				# GEZIELT den Einkaufsbummel-Knopf (ClaimEinkauf1) tippen:
				# tipp_text „Abholen" fand in Lauf 1 den Knopf der DRITTEN
				# Quest — der liegt unterm Sichtfalz des Blatts, der Tap
				# landete auf dem Backdrop-Dim und SCHLOSS das Blatt.
				{
					"name": "belohnung_abholen",
					"aktion": "tipp_name",
					"node": "ClaimEinkauf1",
					"erwarte": {"text": "Quest geschafft!"},
					"timeout_s": 20.0,
				},
				{
					"name": "erfolg_macher_ploppt",
					"aktion": "warte_bis",
					"text": "Erfolg: Macher",
					"timeout_s": 20.0,
				},
				{
					"name": "muenzen_belohnung_gebucht",
					"aktion": "warte_bis",
					"bedingung": muenzen_gestiegen,
					"timeout_s": 15.0,
				},
				{
					"name": "haekchen_erledigt",
					"aktion": "warte_bis",
					"text": "Erledigt!",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{"name": "erfolg_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "blatt_zu_per_wisch",
					"aktion": "wisch",
					"von_funktion": blatt_griff_pos,
					"nach_funktion": blatt_wisch_ziel,
					"dauer_s": 0.45,
					"erwarte": {"weg_klasse": "DailyQuestPanel"},
					"timeout_s": 20.0,
				},
				# ── G8-Regressions-Probe (s. flow_pt4_sheets): zweites Öffnen.
				{
					"name": "wieder_oeffnen_regression",
					"aktion": "tipp_name",
					"node": "BtnQuests",
					"erwarte": {"klasse": "DailyQuestPanel"},
					"timeout_s": 20.0,
					"pflicht": false,
				},
				{"name": "blatt_zustand_loggen", "aktion": "tue", "funktion": blatt_zustand_loggen},
				{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Gerollte Tagesquests als Beleg in den Lauf-Log schreiben (immer ok).
func quests_loggen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var active: Variant = gs.get_value("quests.active", [])
	var ids: Array[String] = []
	if active is Array:
		for entry: Variant in active:
			if entry is Dictionary:
				ids.append(str((entry as Dictionary).get("id", "?")))
	print("[PT4] Gerollte Tagesquests: %s" % str(ids))
	return true


func einkauf_quest_da() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var active: Variant = gs.get_value("quests.active", [])
	if not (active is Array):
		return false
	for entry: Variant in active:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == "einkauf1":
			return true
	return false


## Quest-Metrik „muenzen_ausgegeben": nach dem Beanie-Kauf > 0.
func muenzen_ausgegeben() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return int(gs.get_value("economy.coinsSpent", 0)) > 0


func muenzen_gestiegen() -> bool:
	if muenzen_merker < 0:
		return false
	return muenzen() > muenzen_merker
