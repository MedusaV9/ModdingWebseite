extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Basisklasse der Minispiel-Flows (Arcade/G7-Rahmen) — KEIN eigenständig
## startbarer Flow: gemeinsame Bausteine — Arcade öffnen, Kachel auch
## außerhalb des Sichtfensters ansteuern (Spieler-Wische + deterministische
## Sichtbarkeit), Pregame → „Spielen!“ → Countdown, Pause/Weiter, Nochmal
## (Quick-GO), Beenden-und-Heim mit Router-Fix-Wache sowie Positions-Helfer
## ins letterboxte Spielfeld des MinigameHost. KEIN Test (kein
## test_-Präfix), reines Playtest-Werkzeug wie flow_basis.gd.


## MinigameHost der laufenden Runde (null, wenn keiner gemountet ist).
func host_node() -> Node:
	return harness._finde_klasse(harness.root, "MinigameHost")


## Laufende Spiel-Instanz (MinigameBase) unter dem Host.
func spiel_node() -> Node:
	var host := host_node()
	return host.get("_game") if host != null else null


## Countdown vorbei = Pause-Knopf freigeschaltet (Host-Vertrag: disabled
## bis „Los!“, auch während des 3-2-1-Weiterspiel-Countdowns).
func countdown_fertig() -> bool:
	var host := host_node()
	if host == null:
		return false
	var knopf: Variant = host.get("_pause_button")
	return knopf is Button and not (knopf as Button).disabled


## Canvas-Rechteck des letterboxten Spielfelds (SubViewportContainer).
func spielfeld_rect() -> Rect2:
	var host := host_node()
	if host != null:
		var container: Variant = host.get("_viewport_container")
		if container is Control:
			return (container as Control).get_global_rect()
	return harness.root.get_visible_rect()


## Canvas-Position eines RELATIVEN Punkts (0..1) im Spielfeld — für
## Portrait-Spiele im Querformat-Fenster landen Taps sonst in der Pillarbox.
func spielfeld_pos(rel: Vector2) -> Vector2:
	var rect := spielfeld_rect()
	return rect.position + rel * rect.size


## Canvas-Position eines Punkts im SPIEL-Viewport-Pixelraum (view_size des
## Spiels) — für exakte Ziele wie Memory-Kartenmitten.
func spielfeld_punkt(punkt: Vector2) -> Vector2:
	var host := host_node()
	if host == null:
		return harness.root.get_visible_rect().size * 0.5
	var container: Variant = host.get("_viewport_container")
	if not (container is SubViewportContainer):
		return harness.root.get_visible_rect().size * 0.5
	var rect := (container as SubViewportContainer).get_global_rect()
	var viewport := (container as SubViewportContainer).get_child(0) as SubViewport
	if viewport == null or viewport.size.x == 0 or viewport.size.y == 0:
		return rect.position + punkt
	var faktor := rect.size / Vector2(viewport.size)
	return rect.position + punkt * faktor


## Kachel ins Scroll-Fenster holen (deterministisch, nach den Spieler-
## Wischen): ScrollContainer-Vorfahr + ensure_control_visible.
func kachel_einblenden(tile_name: String) -> bool:
	var tile := harness.root.find_child(tile_name, true, false)
	if not (tile is Control):
		return false
	var knoten: Node = tile
	while knoten != null and not (knoten is ScrollContainer):
		knoten = knoten.get_parent()
	if knoten == null:
		return false
	(knoten as ScrollContainer).ensure_control_visible(tile as Control)
	return true


## Schritte: HUD-Arcade-Knopf → Grid ansehen → optional per Wisch scrollen
## (testet Touch-Scrolling) → Kachel sichtbar machen → Kachel tippen →
## Pregame steht („Spielen!“ sichtbar).
func arcade_bis_pregame(game_id: String, wisch_anzahl: int) -> Array[Dictionary]:
	var tile := "Tile_%s" % game_id
	var liste: Array[Dictionary] = [
		{
			"name": "arcade_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnArcade",
			"erwarte": {"route": "arcade"},
			"timeout_s": 60.0,
		},
		{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
	]
	for i in wisch_anzahl:
		(
			liste
			. append(
				{
					"name": "arcade_scrollen_%d" % (i + 1),
					"aktion": "wisch",
					"von_rel": Vector2(0.5, 0.75),
					"nach_rel": Vector2(0.5, 0.3),
					"dauer_s": 0.6,
				}
			)
		)
	(
		liste
		. append_array(
			[
				{
					"name": "kachel_sichtbar_machen",
					"aktion": "tue",
					"funktion": kachel_einblenden.bind(tile),
					"erwartung": "Kachel %s existiert und liegt im Scroll-Fenster" % tile,
				},
				{"name": "kachel_ruhe", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "kachel_tippen",
					"aktion": "tipp_name",
					"node": tile,
					"erwarte": {"text": "Spielen!"},
					"timeout_s": 60.0,
				},
				{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Schritte: „Spielen!“ → (optional Wipe-Probe-Screenshot mitten im
## Übergang) → Host erreicht → 3-2-1-Countdown fertig („Los!“).
func spiel_starten(wipe_probe: bool) -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	if wipe_probe:
		(
			liste
			. append_array(
				[
					{"name": "spiel_starten_tipp", "aktion": "tipp_text", "text": "Spielen!"},
					{"name": "wipe_beobachten", "aktion": "warte", "sekunden": 0.4},
					{
						"name": "host_erreicht",
						"aktion": "warte_bis",
						"klasse": "MinigameHost",
						"timeout_s": 90.0,
					},
				]
			)
		)
	else:
		(
			liste
			. append(
				{
					"name": "spiel_starten",
					"aktion": "tipp_text",
					"text": "Spielen!",
					"erwarte": {"klasse": "MinigameHost"},
					"timeout_s": 90.0,
				}
			)
		)
	(
		liste
		. append(
			{
				"name": "countdown_abwarten",
				"aktion": "warte_bis",
				"bedingung": countdown_fertig,
				"timeout_s": 45.0,
			}
		)
	)
	return liste


## Schritte: Pause öffnen (Modal mit Beenden sichtbar) → ansehen →
## „Weiter“ → 3-2-1-Weiterspiel-Countdown bis das Spiel wieder läuft.
func pause_und_weiter(pflicht: bool = true) -> Array[Dictionary]:
	return [
		{
			"name": "pause_oeffnen",
			"aktion": "tipp_text",
			"text": "Pause",
			"erwarte": {"text": "Beenden"},
			"timeout_s": 30.0,
			"pflicht": pflicht,
		},
		{"name": "pause_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "weiter_tippen",
			"aktion": "tipp_text",
			"text": "Weiter",
			"erwarte": {"weg_text": "Beenden"},
			"timeout_s": 30.0,
			"pflicht": pflicht,
		},
		{
			"name": "resume_countdown",
			"aktion": "warte_bis",
			"bedingung": countdown_fertig,
			"timeout_s": 30.0,
			"pflicht": pflicht,
		},
	]


## Schritt: aufs Runden-Ende warten (Results-Titel „Runde vorbei!“).
func runde_zu_ende(timeout_s: float) -> Dictionary:
	return {
		"name": "runde_zu_ende",
		"aktion": "warte_bis",
		"text": "Runde vorbei!",
		"timeout_s": timeout_s,
	}


## Schritte: Results „Nochmal“ (Quick-GO ohne 3-2-1) bis die frische Runde
## läuft — deckt den G7-Rahmen-Retry-Pfad ab.
func nochmal_und_los() -> Array[Dictionary]:
	return [
		{
			"name": "nochmal_tippen",
			"aktion": "tipp_text",
			"text": "Nochmal",
			"erwarte": {"weg_text": "Runde vorbei!"},
			"timeout_s": 30.0,
		},
		{
			"name": "quick_go_abwarten",
			"aktion": "warte_bis",
			"bedingung": countdown_fertig,
			"timeout_s": 30.0,
		},
	]


## Schritte: Pause → „Beenden“ → Arcade → „Zurück“ → Wohnzimmer. Der
## Zurück-Schritt ist die Wache für den G7-Router-Fix (flüchtige Ziele:
## back() darf NIE wieder eine frische Runde starten).
func beenden_und_heim() -> Array[Dictionary]:
	return [
		{
			"name": "pause_fuer_beenden",
			"aktion": "tipp_text",
			"text": "Pause",
			"erwarte": {"text": "Beenden"},
			"timeout_s": 30.0,
		},
		{
			"name": "runde_beenden",
			"aktion": "tipp_text",
			"text": "Beenden",
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
