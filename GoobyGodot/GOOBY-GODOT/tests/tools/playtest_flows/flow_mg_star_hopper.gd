extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Sternenhüpfer“ (starHopper, Hochkant-Spiel letterboxt, Kachel
## weiter unten im Grid): Arcade-Scrollen per Wisch, Pregame → Countdown
## → Bahnwechsel per Tipp (1 Bahn) und Wisch (2 Bahnen). EIN Meteor-
## Treffer beendet die Runde — Pause/Weiter ist deshalb pflicht=false
## (Runde kann schon vorbei sein), das Runden-Ende kommt so oder so
## (Treffer oder 75-s-Uhr). Danach Results → „Nochmal“ (Quick-GO) →
## zweite Runde bis zum Ende → „Nach Hause“ (Results-Home-Ausgang des
## G7-Rahmens).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_star_hopper


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("starHopper", 2))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "intro_abwarten", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "bahn_rechts_tipp",
					"aktion": "tipp_pos",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.72, 0.55)),
				},
				{"name": "fliegen_1", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "bahn_links_tipp",
					"aktion": "tipp_pos",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.28, 0.55)),
				},
				{"name": "fliegen_2", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "bahn_wisch_rechts",
					"aktion": "wisch",
					"von_funktion": spielfeld_pos.bind(Vector2(0.3, 0.6)),
					"nach_funktion": spielfeld_pos.bind(Vector2(0.75, 0.6)),
					"dauer_s": 0.4,
				},
				{"name": "fliegen_3", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	liste.append_array(pause_und_weiter(false))
	(
		liste
		. append_array(
			[
				{
					"name": "bahn_links_tipp_2",
					"aktion": "tipp_pos",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.3, 0.55)),
					"pflicht": false,
				},
				runde_zu_ende(160.0),
				{"name": "results_ansehen", "aktion": "warte", "sekunden": 4.0},
			]
		)
	)
	liste.append_array(nochmal_und_los())
	(
		liste
		. append_array(
			[
				{
					"name": "runde2_tipp",
					"aktion": "tipp_pos",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.7, 0.55)),
					"pflicht": false,
				},
				{
					"name": "runde2_zu_ende",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 160.0,
				},
				{
					"name": "results_nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 90.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste
