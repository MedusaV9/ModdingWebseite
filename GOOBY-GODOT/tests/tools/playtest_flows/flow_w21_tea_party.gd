extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Teestube“ (teaParty, Hochkant-Spiel letterboxt) — W21 „ACNH-UI“
## In-Game-HUD-Erkundung: Arcade → Kachel → Pregame → Countdown → mehrere
## ECHTE Gieß-Züge (Halten füllt mit FILL_RATE 0,5/s, Band-Mitte liegt je
## Tasse bei ~0,55–0,8 ⇒ gestaffelte Haltezeiten treffen Perfect/Good/Spill
## quer durch die Feedback-Palette), Pause/Weiter-Probe mitten im Spiel,
## dann Beenden → Arcade → Wohnzimmer. Die Schritt-Screenshots dokumentieren
## HUD-Plate, Füllmeter, Banner-Momente und den Hinweis-Fade im Gameplay.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_w21_tea_party


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("teaParty", 0))
	liste.append_array(spiel_starten(false))
	liste.append({"name": "intro_abwarten", "aktion": "warte", "sekunden": 2.2})
	# Gestaffelte Haltezeiten: kurz (Spill/daneben), mittel (Good/Perfect),
	# lang (Überlauf) — so tauchen alle Banner-/Float-Text-Momente auf.
	var haltezeiten: Array[float] = [1.3, 1.5, 0.4, 1.4, 2.3, 1.5]
	for i in haltezeiten.size():
		(
			liste
			. append_array(
				[
					{
						"name": "giessen_%d" % (i + 1),
						"aktion": "halte",
						"pos_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
						"dauer_s": haltezeiten[i],
					},
					{"name": "wertung_%d_ansehen" % (i + 1), "aktion": "warte", "sekunden": 1.2},
				]
			)
		)
	liste.append_array(pause_und_weiter())
	(
		liste
		. append_array(
			[
				{
					"name": "giessen_nach_pause",
					"aktion": "halte",
					"pos_funktion": spielfeld_pos.bind(Vector2(0.5, 0.6)),
					"dauer_s": 1.4,
				},
				{"name": "spaete_runde_ansehen", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	liste.append_array(beenden_und_heim())
	return liste
