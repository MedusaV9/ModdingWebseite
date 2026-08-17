extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Einkaufsfahrt“ (cityDrive, Hochkant-3D-Stadt, 90-s-Runde):
## Arcade (Wisch-Scrollen) → Pregame → Countdown → ~20 s lenken (Finger
## links/rechts halten = Touch-Lenkung) → Pause/Weiter (3-2-1) → Runde
## läuft aus (Timer oder 3-Crash-Teleport-Cutscene, beides reguläre
## Enden) → Results → „Nochmal“ (Quick-GO) → kurz fahren → Pause/
## „Beenden“ → Arcade → „Zurück“ = Wohnzimmer (Router-Fix-Wache).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_city_drive


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("cityDrive", 1))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "intro_abwarten", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lenken_rechts",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.78, 0.7)),
					"dauer_s": 2.0,
				},
				{"name": "fahren_1", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lenken_links",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.22, 0.7)),
					"dauer_s": 2.0,
				},
				{"name": "fahren_2", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lenken_leicht_rechts",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.62, 0.7)),
					"dauer_s": 2.5,
				},
				{"name": "fahren_3", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	liste.append_array(pause_und_weiter())
	(
		liste
		. append_array(
			[
				{
					"name": "lenken_nach_pause",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.35, 0.7)),
					"dauer_s": 2.0,
				},
				runde_zu_ende(220.0),
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
					"name": "runde2_lenken",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.7, 0.7)),
					"dauer_s": 2.0,
				},
				{"name": "runde2_fahren", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	liste.append_array(beenden_und_heim())
	return liste
