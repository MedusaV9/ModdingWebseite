extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Gooby vs. Zombies“ (gvz, Querformat-Spiel) — W21 „ACNH-UI“
## In-Game-HUD-Erkundung: Arcade → Kachel → Pregame → Countdown →
## Level-Auswahl (Kachel 1 über den ECHTEN Button-Anker im SubViewport,
## Muster flow_w18_ranch_spiele/spiel_text_pos) → Gefecht: Karten antippen
## und auf Zellen setzen (Tap-Tap-Pfad aus gvz_game._touch_down), zwischen
## den Zügen Nutella ansparen lassen, ~30 s echtes Gefecht mit Wellen-
## Banner/HP-Balken/Zähler-Chip im Bild, Pause/Weiter-Probe, dann Beenden →
## Arcade → Wohnzimmer. Screenshots pro Schritt = HUD-Belege im Gameplay.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_w21_gvz


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("gvz", 1))
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{
					"name": "levelwahl_da",
					"aktion": "warte_bis",
					"bedingung": levelwahl_da,
					"timeout_s": 60.0,
				},
				{"name": "levelwahl_ansehen", "aktion": "warte", "sekunden": 1.5},
				{
					"name": "level1_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": level1_pos,
					"erwarte": {"bedingung": gefecht_laeuft},
					"timeout_s": 30.0,
				},
				{"name": "intro_banner_ansehen", "aktion": "warte", "sekunden": 2.5},
			]
		)
	)
	# 3 Setz-Züge: Karte 1 antippen, dann eine Zelle — dazwischen Nutella
	# ansparen (Zeile mittig, Spalten von links nach rechts).
	for zug in [[2, 1], [1, 2], [3, 2]]:
		(
			liste
			. append_array(
				[
					{"name": "nutella_sparen_%d_%d" % zug, "aktion": "warte", "sekunden": 6.0},
					{
						"name": "karte_waehlen_%d_%d" % zug,
						"aktion": "tipp_pos",
						"pos_funktion": karte_pos.bind(0),
						"pflicht": false,
					},
					{
						"name": "turm_setzen_%d_%d" % zug,
						"aktion": "tipp_pos",
						"pos_funktion": zelle_pos.bind(zug[0], zug[1]),
						"pflicht": false,
					},
				]
			)
		)
	(
		liste
		. append_array(
			[
				{"name": "gefecht_beobachten", "aktion": "warte", "sekunden": 8.0},
				{
					"name": "welle_beobachten",
					"aktion": "warte",
					"sekunden": 6.0,
				},
			]
		)
	)
	liste.append_array(pause_und_weiter())
	liste.append({"name": "spaetes_gefecht_ansehen", "aktion": "warte", "sekunden": 4.0})
	liste.append_array(beenden_und_heim())
	return liste


## Level-Auswahl steht (Spiel gemountet + Select-Phase aktiv).
func levelwahl_da() -> bool:
	var spiel := spiel_node()
	return spiel != null and str(spiel.get("phase")) == "select"


## Gefecht läuft (Level 1 geöffnet).
func gefecht_laeuft() -> bool:
	var spiel := spiel_node()
	return spiel != null and str(spiel.get("phase")) == "battle"


## Canvas-Punkt der Level-1-Kachel: der ECHTE Button-Anker im letterboxten
## SubViewport (spielfeld_punkt rechnet Spiel-Pixel → Canvas; Harness-Falle
## aus w18a5_spiele/1: nackte tipp_text-Koordinaten treffen daneben).
func level1_pos() -> Vector2:
	var select: Node = harness._finde_klasse(harness.root, "GvzLevelSelect")
	if select == null:
		return spielfeld_pos(Vector2(0.5, 0.5))
	var buttons: Variant = select.get("_buttons")
	if not (buttons is Dictionary) or not (buttons as Dictionary).has(1):
		return spielfeld_pos(Vector2(0.5, 0.5))
	var knopf: Button = (buttons as Dictionary)[1]
	return spielfeld_punkt(knopf.get_global_rect().get_center())


## Canvas-Punkt einer Karte in der Kartenleiste (Index in _card_list).
func karte_pos(index: int) -> Vector2:
	var spiel := spiel_node()
	if spiel == null:
		return spielfeld_pos(Vector2(0.1, 0.95))
	var rect: Rect2 = spiel._card_rect(index)
	return spielfeld_punkt(rect.get_center())


## Canvas-Punkt einer Feld-Zelle (lane 0–4, col 0–8).
func zelle_pos(lane: int, col: int) -> Vector2:
	var spiel := spiel_node()
	if spiel == null:
		return spielfeld_pos(Vector2(0.4, 0.5))
	var center: Vector2 = spiel._cell_center(lane, col)
	return spielfeld_punkt(center)
