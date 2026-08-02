extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Repro-Flow „Geschichten-Crash" (G8-BLOCKER): das Öffnen eines
## Buchs im Gute-Nacht-Geschichten-Regal CRASHT das Spiel hart (Signal
## 11). Kette: story_time._on_book_chosen läuft IM pressed-Signal des
## Buch-Knopfs → _open_page → _setze_inhalt → `_inhalt.free()` gibt die
## Bibliotheks-Ansicht SOFORT frei — mitsamt dem Knopf, der gerade noch
## sein Signal emittiert → Godot: „Object was freed or unreferenced while
## a signal is being emitted" → Segfault. (Dasselbe Muster droht beim
## Seiten-Wechsel über die Wort-Chips, _on_word_tapped.)
## Weg zum Crash: frisches Onboarding → Bett-Bauquest erfüllen (das Bett
## liegt im Start-Lager) → Bett antippen → „Gute-Nacht-Geschichte" →
## Startbuch „Goobys Möhrenmond-Fibel" antippen → CRASH. Der Lauf bricht
## beim letzten Schritt ab; lauf.log hält Fehlertext + Backtrace fest.
## Aufruf: tools/ci/run_playtest.sh flow_pt4_geschichten


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "baumodus_fuer_bett",
					"aktion": "tipp_name",
					"node": "BtnBau",
					"erwarte": {"text": "Fertig"},
					"timeout_s": 60.0,
				},
			]
		)
	)
	liste.append_array(bett_platzieren_schritte())
	liste.append_array(
		[
			{"name": "bett_steht", "aktion": "warte", "sekunden": 1.5},
			{
				"name": "bett_antippen",
				"aktion": "tipp_3d",
				"finder": func() -> Node3D: return finde_moebel("bedSingle"),
				"offset": Vector3(0.0, 0.3, 0.0),
				"erwarte": {"text": "Bettzeit"},
				"timeout_s": 30.0,
			},
			{
				"name": "geschichte_waehlen",
				"aktion": "tipp_text",
				"text": "Gute-Nacht-Geschichte",
				"erwarte": {"text": "Bücherregal"},
				"timeout_s": 20.0,
			},
			{"name": "bibliothek_ansehen", "aktion": "warte", "sekunden": 1.5},
			# ── AB HIER CRASHT DAS SPIEL (Erwartung: dieser Schritt reisst
			# den Godot-Prozess mit Signal 11 ab — s. Kopf-Doku).
			{
				"name": "startbuch_oeffnen_CRASH",
				"aktion": "tipp_name",
				"node": "Buch_buch_moehrenmond",
				"erwarte": {"weg_text": "Welches Buch lesen wir heute?"},
				"timeout_s": 20.0,
			},
			{"name": "nach_buch_tap", "aktion": "warte", "sekunden": 2.0},
		]
	)
	return liste
