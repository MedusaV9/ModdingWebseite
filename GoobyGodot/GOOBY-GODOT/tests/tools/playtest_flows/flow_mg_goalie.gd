extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Torwart-Gooby“ (goalieGooby, QUER-Spiel): Arcade (Wisch-
## Scrollen) → Pregame → Countdown → hechten per Wisch / Mitte per Tipp →
## FRÜH Pause (3 Gegentore beenden die Runde vorzeitig) → im Pause-Modal
## „Neustart“ (Quick-GO-Retry-Pfad aus der Pause) → weiterspielen bis zum
## Runden-Ende (60-s-Uhr oder 3 Gegentore) → Results → „Zur Arcade“
## (dritter Rahmen-Ausgang) → „Zurück“ = Wohnzimmer (Router-Fix-Wache).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_goalie


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("goalieGooby", 1))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "intro_abwarten", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "hechten_links",
					"aktion": "wisch",
					"von_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
					"nach_funktion": spielfeld_pos.bind(Vector2(0.25, 0.6)),
					"dauer_s": 0.3,
				},
				{"name": "parade_1", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "hechten_rechts",
					"aktion": "wisch",
					"von_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
					"nach_funktion": spielfeld_pos.bind(Vector2(0.78, 0.6)),
					"dauer_s": 0.3,
				},
			]
		)
	)
	(
		liste
		. append_array(
			[
				{
					"name": "pause_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{"name": "pause_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "neustart_tippen",
					"aktion": "tipp_text",
					"text": "Neustart",
					"erwarte": {"weg_text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "neustart_quick_go",
					"aktion": "warte_bis",
					"bedingung": countdown_fertig,
					"timeout_s": 30.0,
				},
				{"name": "neustart_intro", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "hechten_mitte_tipp",
					"aktion": "tipp_pos",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
					"pflicht": false,
				},
				{"name": "parade_2", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "hechten_links_2",
					"aktion": "wisch",
					"von_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
					"nach_funktion": spielfeld_pos.bind(Vector2(0.22, 0.6)),
					"dauer_s": 0.3,
					"pflicht": false,
				},
				runde_zu_ende(150.0),
				{"name": "results_ansehen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "results_zur_arcade",
					"aktion": "tipp_text",
					"text": "Zur Arcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				{
					"name": "zurueck_nach_hause",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 90.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste
