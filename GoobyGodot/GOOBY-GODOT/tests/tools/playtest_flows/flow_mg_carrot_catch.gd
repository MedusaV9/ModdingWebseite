extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Möhrenfang“ (carrotCatch, Hochkant-Spiel letterboxt): Boot/
## Onboarding → Arcade → Kachel → Pregame → „Spielen!“ (mit Wipe-Probe-
## Screenshot) → Countdown → ~20 s Korb ziehen (Halten/Wischen im
## letterboxten Spielfeld) → Pause/Weiter (3-2-1) → Runde läuft aus (60 s)
## → Results (Zähl-Animation, Konfetti, Rekord-Banner) → „Nochmal“
## (Quick-GO) → kurz spielen → Pause/„Beenden“ → Arcade → „Zurück“ =
## Wohnzimmer (Router-Fix-Wache).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_carrot_catch


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("carrotCatch", 0))
	liste.append_array(spiel_starten(true))
	(
		liste
		. append_array(
			[
				{
					"name": "korb_links",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.2, 0.75)),
					"dauer_s": 1.5,
				},
				{"name": "fangen_1", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "korb_rechts",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.8, 0.75)),
					"dauer_s": 1.5,
				},
				{"name": "fangen_2", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "korb_ziehen",
					"aktion": "wisch",
					"von_funktion": spielfeld_pos.bind(Vector2(0.8, 0.7)),
					"nach_funktion": spielfeld_pos.bind(Vector2(0.2, 0.7)),
					"dauer_s": 1.2,
				},
				{"name": "fangen_3", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "korb_mitte",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.5, 0.75)),
					"dauer_s": 1.2,
				},
				{"name": "fangen_4", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	liste.append_array(pause_und_weiter())
	(
		liste
		. append_array(
			[
				{
					"name": "korb_nach_pause",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.35, 0.75)),
					"dauer_s": 1.5,
				},
				runde_zu_ende(180.0),
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
					"name": "runde2_korb",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.6, 0.75)),
					"dauer_s": 1.5,
				},
				{"name": "runde2_fangen", "aktion": "warte", "sekunden": 3.0},
			]
		)
	)
	liste.append_array(beenden_und_heim())
	return liste
