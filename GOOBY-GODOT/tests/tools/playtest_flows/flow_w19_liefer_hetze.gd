extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Liefer-Hetze" (deliveryRush, 3D-Verfolgerkamera durch die Abendstadt) —
## dauerhafter Wächter der W19-Politur (Live-Demo-Befunde: Kulissen-Klemme der
## Kamera, Milchglas-Plate unterm Steuer-Hinweis, Erste-Lieferung-Beat):
## Arcade → Pregame → Countdown → Intro-Beat ansehen (Stadt-Totale +
## Ziel-Banner, danach der Erste-Lieferung-Beat) → ~20 s echt lenken
## (Halte-Eingaben links/rechts wie ein Finger, quer durch Kurven — genau da
## schwenkte der Kamera-Boom früher in die Häuserblocks) → Pause/Weiter →
## weiterfahren → Pause/„Beenden" → Arcade → „Zurück" = Wohnzimmer.
## Format: quer 2868x1320 (Leitformat, Default); hochkant 1320x2868 läuft
## über den zweiten Aufruf.
## Aufruf: tools/ci/run_playtest.sh flow_w19_liefer_hetze


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("deliveryRush", 1))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				# Intro-Beat: Stadt-Totale + „Bring die Pakete…"-Banner (2,2 s).
				{"name": "intro_banner_ansehen", "aktion": "warte", "sekunden": 1.2},
				# Danach steht der Erste-Lieferung-Beat (benennt das erste Ziel,
				# 4,5 s) — die Anfahrt zum ersten Ring ist damit ERKLÄRT.
				{"name": "erste_lieferung_beat", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lenken_rechts",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.78, 0.7)),
					"dauer_s": 2.5,
				},
				{"name": "fahren_1", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "lenken_links",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.22, 0.7)),
					"dauer_s": 2.5,
				},
				{"name": "fahren_2", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "kurve_eng_rechts",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.9, 0.7)),
					"dauer_s": 3.0,
				},
				{"name": "fahren_3", "aktion": "warte", "sekunden": 2.5},
				{
					"name": "spurwechsel_links",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.3, 0.7)),
					"dauer_s": 2.0,
				},
				{"name": "fahren_4", "aktion": "warte", "sekunden": 2.5},
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
					"pos_funktion": spielfeld_pos.bind(Vector2(0.65, 0.7)),
					"dauer_s": 2.0,
				},
				{"name": "fahren_5", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	liste.append_array(beenden_und_heim())
	return liste
