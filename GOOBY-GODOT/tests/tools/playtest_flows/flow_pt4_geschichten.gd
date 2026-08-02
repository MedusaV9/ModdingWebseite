extends "res://tests/tools/playtest_flows/flow_pt4_basis.gd"
## PT-4 Regressions-Flow „Geschichten" (G8-BLOCKER B1, GEFIXT): Das Öffnen
## eines Buchs im Gute-Nacht-Bücherregal crashte das Spiel hart (Signal
## 11) — story_time._setze_inhalt gab die Bibliotheks-Ansicht IM
## pressed-Signal des Buch-Knopfs mit einem harten free() frei, mitsamt
## dem noch emittierenden Knopf. Seit dem Fix (remove_child + queue_free,
## s. scripts/events/story_time.gd) erwartet der Flow den ERFOLG: Buch
## antippen → Lückentext-Seite steht → drei Wort-Chips setzen → Gooby
## schläft ein („Mmmh… schöne Geschichte…"), das Blatt schließt sich.
## Der Buch-Tap läuft über echte Eingabe-Events — exakt der Pfad, der
## vor dem Fix segfaultete. Beide free()-Pfade (Buchwahl UND Seiten-
## wechsel über Wort-Chips) deckt zusätzlich der Unit-Test
## tests/unit/test_g8_story_crash.gd headless ab.
## Weg: frisches Onboarding → Bett-Bauquest erfüllen (das Bett liegt im
## Start-Lager) → Bett antippen → „Gute-Nacht-Geschichte" → Startbuch
## „Goobys Möhrenmond-Fibel" antippen → erste Seite durchspielen.
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
			# ── G8-B1-REGRESSION: dieser Tap riss den Godot-Prozess vor
			# dem Fix mit Signal 11 ab — jetzt muss die Buchseite stehen.
			{
				"name": "startbuch_oeffnen",
				"aktion": "tipp_name",
				"node": "Buch_buch_moehrenmond",
				"erwarte": {"text": "Tippe ein Wort"},
				"timeout_s": 20.0,
			},
			{
				"name": "bibliothek_abgeloest",
				"aktion": "warte_bis",
				"weg_text": "Welches Buch lesen wir heute?",
				"timeout_s": 10.0,
			},
			{"name": "buchseite_ansehen", "aktion": "warte", "sekunden": 1.0},
			# Erste Seite spielen: der jeweils ERSTE freie Chip ist in
			# allen drei Fibel-Geschichten die richtige Antwort der
			# nächsten Lücke (Pool-Reihenfolge = Lücken-Reihenfolge).
			{"name": "wort_1_setzen", "aktion": "tipp_pos", "pos_funktion": wort_chip_pos},
			{"name": "wort_1_wirkt", "aktion": "warte", "sekunden": 0.6},
			{"name": "wort_2_setzen", "aktion": "tipp_pos", "pos_funktion": wort_chip_pos},
			{"name": "wort_2_wirkt", "aktion": "warte", "sekunden": 0.6},
			# Das frische Startbuch braucht genau 3 Wörter — der dritte
			# Chip beendet die Vorlese-Session, Gooby schläft ein.
			{
				"name": "wort_3_gooby_schlaeft",
				"aktion": "tipp_pos",
				"pos_funktion": wort_chip_pos,
				"erwarte": {"text": "schöne Geschichte"},
				"timeout_s": 20.0,
			},
			{
				"name": "blatt_schliesst_von_selbst",
				"aktion": "warte_bis",
				"bedingung": kein_blatt_offen,
				"timeout_s": 20.0,
			},
			{"name": "gute_nacht_ansehen", "aktion": "warte", "sekunden": 2.0},
		]
	)
	return liste


## Mitte des ersten tippbaren Wort-Chips der offenen Buchseite (die
## Seiten sind gemischt — der Chip-NAME variiert, die Grid-Lage nicht).
func wort_chip_pos() -> Vector2:
	var grid := harness.root.find_child("WortGrid", true, false)
	if grid != null:
		for kind in grid.get_children():
			var chip := kind as Button
			if chip != null and not chip.disabled and chip.is_visible_in_tree():
				return chip.get_global_rect().get_center()
	# Kein freier Chip (mehr) — neutral in die Canvas-Mitte tippen; die
	# folgenden Erwartungen decken den Fehlschlag dann auf.
	return harness.root.get_visible_rect().size * 0.5
