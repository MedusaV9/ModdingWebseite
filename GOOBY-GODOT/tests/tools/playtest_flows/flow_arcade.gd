extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow (c) „Arcade“: Boot → Onboarding → Arcade über den HUD-Knopf →
## Teestube-Kachel → Pregame → „Spielen!“ → Countdown abwarten → wie ein
## Spieler gießen (Halten/Loslassen) → Pause → Weiter → nochmal gießen →
## Pause → „Beenden“ zurück zur Arcade → „Zurück“ nach Hause (Bug-Wächter,
## s. Befund unten) → notfalls über das Runden-Ende-Modal nach Hause.
## Aufruf: tools/ci/run_playtest.sh flow_arcade


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "arcade_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnArcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 60.0,
				},
				{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "teestube_waehlen",
					"aktion": "tipp_name",
					"node": "Tile_teaParty",
					"erwarte": {"text": "Spielen!"},
					"timeout_s": 60.0,
				},
				{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "spiel_starten",
					"aktion": "tipp_text",
					"text": "Spielen!",
					"erwarte": {"klasse": "MinigameHost"},
					"timeout_s": 90.0,
				},
				{"name": "countdown_abwarten", "aktion": "warte", "sekunden": 6.0},
				{
					"name": "giessen_1",
					"aktion": "halte",
					"pos_rel": Vector2(0.5, 0.6),
					"dauer_s": 1.2,
				},
				{
					"name": "giessen_2",
					"aktion": "halte",
					"pos_rel": Vector2(0.5, 0.6),
					"dauer_s": 0.7,
				},
				{
					"name": "pause_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "weiter_spielen",
					"aktion": "tipp_text",
					"text": "Weiter",
					"erwarte": {"weg_text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "giessen_3",
					"aktion": "halte",
					"pos_rel": Vector2(0.5, 0.6),
					"dauer_s": 1.0,
				},
				{
					"name": "pause_wieder_oeffnen",
					"aktion": "tipp_text",
					"text": "Pause",
					"erwarte": {"text": "Beenden"},
					"timeout_s": 30.0,
				},
				{
					"name": "spiel_beenden",
					"aktion": "tipp_text",
					"text": "Beenden",
					"erwarte": {"route": "arcade"},
					"timeout_s": 90.0,
				},
				# BEFUND Pionier-Lauf 1: „Zurück“ nutzt die Router-History —
				# nach Pause→„Beenden“ (goto arcade) liegt mg_host oben, der
				# Knopf startet also eine NEUE Runde statt nach Hause zu
				# führen. Schritt bleibt als Bug-Wächter drin (pflicht=false),
				# danach rettet sich der Flow wie ein Spieler über das
				# Runden-Ende-Modal.
				{
					"name": "zurueck_nach_hause",
					"aktion": "tipp_text",
					"text": "Zurück",
					"erwarte": {"route": "home/living"},
					"timeout_s": 90.0,
					"pflicht": false,
				},
				{
					"name": "runde_vorbei_nach_hause",
					"aktion": "tipp_falls_da",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
					"pflicht": false,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste
