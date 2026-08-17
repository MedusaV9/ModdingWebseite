extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Flow „Raumstation GOOB-1“: Shuttle
## am Flughafen (erst nach space-Urlaub sichtbar → Staging latcht
## vacation.visited.space), Station ansehen, LOW-GRAVITY-Beleg (der
## Stations-Gooby schwebt per Hop ×2,2 höher — wir warten live auf y>0,3),
## beide SPIEL-TERMINALS im Bestand prüfen, Astro-Snack kaufen, dann am
## Sternenhüpfer-Terminal SPIELEN: Runde 1 → Results → „Nochmal“ → Runde 2
## → Results — inkl. der Alt-Befund-Sonde „Results-Streifen im Querformat“
## (Karte muss KOMPLETT im Bild liegen). „Zur Arcade“ muss dank der
## Rückweg-Umleitung wieder in der STATION landen, „Raus“ im Flughafen.
## Aufruf: tools/ci/run_playtest.sh flow_w18_raumstation
##
## Staging (KEINE Spielmechanik-Änderung): vacation.visited.space = true —
## exakt der Latch, den ein echter space-Urlaub setzt (Shuttle-Gate).

## Der Low-G-Hop hebt den Rig auf 0,22·2,2 ≈ 0,48 m — über 0,3 m ist
## eindeutig „schwebt“, ein Boden-Hop (0,22) käme da nie hin.
const SCHWEBE_MIN_Y := 0.3
## Results-Karte muss mindestens so hoch sein (Streifen-Sonde).
const RESULTS_MIN_HOEHE := 200.0

var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_anreise())
	liste.append_array(_schritte_station())
	liste.append_array(_schritte_arcade())
	return liste


## ---------------------------------------------------- Anreise (Shuttle)


func _schritte_anreise() -> Array[Dictionary]:
	return [
		{
			"name": "staging_space_latch",
			"aktion": "tue",
			"funktion": staging_space,
			"erwartung": "vacation.visited.space gelatcht (Shuttle-Gate)",
		},
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren_flughafen",
			"aktion": "tue",
			"funktion": fahre_vor_flughafen,
			"erwartung": "Auto steht am Flughafen-Parkplatz",
		},
		# BLOCKER-Umgehung (Report B7): der Parkplatz-Trigger des Flughafens
		# liegt IM Gebäude (city_map.json tiles[0]=[0,2], strasse=[0,4] —
		# 2 Tiles Abstand), der Betreten-Prompt ist per Auto unerreichbar.
		# Kurze Sonde dokumentiert das, dann Force-Enter über die
		# CityScene-Prompt-Aktion.
		{
			"name": "flughafen_betreten_prompt_sonde",
			"aktion": "tipp_falls_da",
			"text": "Betreten",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "flughafen_betreten_force",
			"aktion": "tue",
			"funktion": betrete_flughafen_direkt,
			"erwartung": "Force-Enter Flughafen (B7-Umgehung)",
		},
		{
			"name": "flughafen_betreten",
			"aktion": "warte_bis",
			"route": "city/ort/flughafen",
			"timeout_s": 60.0,
		},
		{
			"name": "shuttle_knopf_check",
			"aktion": "tue",
			"funktion": shuttle_knopf_da,
			"erwartung": "GOOB-1-Shuttle-Knopf ist nach dem Latch sichtbar",
		},
		{
			"name": "shuttle_nehmen",
			"aktion": "tipp_name",
			"node": "Shuttle",
			"erwarte": {"route": "city/ort/raumstation"},
			"timeout_s": 120.0,
		},
		{"name": "station_ankommen", "aktion": "warte", "sekunden": 4.0},
	]


## ------------------------------------- Station (Low-G, Terminals, Snack)


func _schritte_station() -> Array[Dictionary]:
	return [
		# Begrüßungs-Bubble durchtippen (Station hat eine Dialog-Datei).
		{
			"name": "bubble_zeigen",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 10.0,
		},
		{"name": "bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		# LOW-GRAVITY-Beleg: der Schwebe-Hop muss den Rig live über 0,3 m
		# heben (Boden-Hops schaffen nur 0,22 m).
		{
			"name": "low_g_schwebe_check",
			"aktion": "warte_bis",
			"bedingung": gooby_schwebt,
			"timeout_s": 30.0,
		},
		{
			"name": "terminals_check",
			"aktion": "tue",
			"funktion": terminals_da,
			"erwartung": "beide Spiel-Terminals (rocketRescue+starHopper) stehen",
		},
		{"name": "station_panorama", "aktion": "warte", "sekunden": 3.0},
		# Astro-Snack-Automat: Weltraum-Möhre kaufen (Münzstand sinkt).
		{
			"name": "automat_oeffnen",
			"aktion": "tipp_text",
			"text": "Astro-Snacks",
			"erwarte": {"klasse": "HaendlerSheet"},
			"timeout_s": 60.0,
		},
		{"name": "automat_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "kasse_merken_snack",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "moehre_kaufen",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 15.0,
		},
		{"name": "snack_moment", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "automat_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "automat_weg",
			"aktion": "warte_bis",
			"weg_klasse": "HaendlerSheet",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "automat_zu_moment", "aktion": "warte", "sekunden": 1.5},
	]


## -------------------------- Terminal-Arcade (inkl. Results-Streifen-Sonde)


func _schritte_arcade() -> Array[Dictionary]:
	var liste: Array[Dictionary] = [
		{
			"name": "terminal_sternenhuepfer",
			"aktion": "tipp_name",
			"node": "TerminalStar",
			"erwarte": {"text": "Spielen!"},
			"timeout_s": 90.0,
		},
		{"name": "pregame_ansehen", "aktion": "warte", "sekunden": 2.0},
	]
	liste.append_array(spiel_starten(false))
	(
		liste
		. append_array(
			[
				{"name": "runde1_fliegen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "runde1_beenden",
					"aktion": "tue",
					"funktion": runde_beenden.bind(3),
					"erwartung": "report_end({score: 3}) über den Spiel-Kontext",
				},
				{
					"name": "results1_da",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 30.0,
				},
				{"name": "results1_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "results1_im_bild",
					"aktion": "tue",
					"funktion": results_im_bild,
					"erwartung": "Results-Karte 1 liegt komplett im Bild",
					"pflicht": false,
				},
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
				{"name": "runde2_fliegen", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "runde2_beenden",
					"aktion": "tue",
					"funktion": runde_beenden.bind(4),
					"erwartung": "report_end({score: 4}) über den Spiel-Kontext",
				},
				{
					"name": "results2_da",
					"aktion": "warte_bis",
					"text": "Runde vorbei!",
					"timeout_s": 30.0,
				},
				{"name": "results2_ansehen", "aktion": "warte", "sekunden": 2.0},
				# ALT-BEFUND-SONDE „Teestube-Streifen im Querformat“: die
				# ZWEITE Results-Karte war früher ein Streifen am unteren
				# Rand mit unerreichbaren Knöpfen. pflicht=false — ein FAIL
				# ist ein Report-Befund, kein Flow-Abbruch.
				{
					"name": "results2_streifen_sonde",
					"aktion": "tue",
					"funktion": results_im_bild,
					"erwartung": "Results-Karte 2 liegt komplett im Bild (kein Streifen)",
					"pflicht": false,
				},
				# Rückweg-Umleitung: „Zur Arcade“ muss in der STATION landen
				# (die &arcade-Route zeigt beim Terminal-Start auf GOOB-1).
				{
					"name": "zur_arcade_zurueck",
					"aktion": "tipp_text",
					"text": "Zur Arcade",
					"erwarte": {"klasse": "OrtRaumstation"},
					"timeout_s": 120.0,
				},
				{"name": "wieder_in_der_station", "aktion": "warte", "sekunden": 3.0},
				{
					"name": "station_verlassen",
					"aktion": "tipp_text",
					"text": "Raus",
					"erwarte": {"route": "city/ort/flughafen"},
					"timeout_s": 120.0,
				},
				{"name": "abschluss_flughafen", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## ---------------------------------------------------------------- Bausteine


## space-Besuchs-Latch setzen — exakt das Flag, das OrtRaumstation.
## freigeschaltet() prüft (und das ein echter space-Urlaub latcht).
func staging_space() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var roh: Variant = gs.get_value("vacation", {})
	var v: Dictionary = roh if roh is Dictionary else {}
	var besucht_roh: Variant = v.get("visited", {})
	var besucht: Dictionary = besucht_roh if besucht_roh is Dictionary else {}
	besucht["space"] = true
	v["visited"] = besucht
	gs.set_value("vacation", v)
	return true


func fahre_vor_flughafen() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt("flughafen")
	stadt.auto.teleport(park.x, park.z)
	# Auto-Runner: ohne gehaltene Bremse rollt das Auto sofort aus dem
	# 7-m-Parkradius (Lauf-1-Lehre aus flow_w18_stadt_tour).
	stadt.auto.set_brake(true)
	return true


func shuttle_knopf_da() -> bool:
	var knopf := harness.root.find_child("Shuttle", true, false)
	return knopf is Button and (knopf as Button).is_visible_in_tree()


## Live-Beleg für Low-G: der Stations-Gooby hebt beim Schwebe-Hop über
## SCHWEBE_MIN_Y ab (Bedingung wird pro Frame gepollt).
func gooby_schwebt() -> bool:
	var szene := aktuelle_szene()
	if not (szene is OrtRaumstation):
		return false
	var rig: Variant = szene.get("rig")
	if not (rig is Node3D):
		return false
	return (rig as Node3D).position.y > SCHWEBE_MIN_Y


func terminals_da() -> bool:
	var szene := aktuelle_szene()
	if not (szene is OrtRaumstation):
		return false
	var station: OrtRaumstation = szene
	return (
		station.terminals.has(OrtRaumstation.SPIEL_ROCKET)
		and station.terminals.has(OrtRaumstation.SPIEL_STAR)
	)


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


func kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) < _muenzen_vorher


## Mitte des obersten sichtbaren Preis-Knopfs ("{preis} ᴳ") im Sheet.
func kauf_knopf_pos() -> Vector2:
	var sicht := harness.root.get_visible_rect()
	var beste := Vector2.ZERO
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		for kind in aktuell.get_children():
			stapel.append(kind)
		if not (aktuell is Button):
			continue
		var knopf := aktuell as Button
		if knopf.disabled or not knopf.is_visible_in_tree() or not knopf.text.contains("ᴳ"):
			continue
		var mitte := knopf.get_global_rect().get_center()
		if sicht.has_point(mitte) and (beste == Vector2.ZERO or mitte.y < beste.y):
			beste = mitte
	return beste


## Runde über den Spiel-Kontext beenden (FB3-Audit-Muster).
func runde_beenden(score: int) -> bool:
	var spiel := spiel_node()
	if spiel == null or spiel.get("ctx") == null:
		return false
	spiel.ctx.report_end({"score": score})
	return true


## Streifen-Sonde: die Results-Karte (_panel) liegt KOMPLETT im sichtbaren
## Canvas und ist kein zusammengestauchter Streifen.
func results_im_bild() -> bool:
	var host := host_node()
	if host == null:
		return false
	var results: Variant = host.get("_results")
	if not (results is Control):
		return false
	var panel: Variant = (results as Control).get("_panel")
	if not (panel is Control):
		return false
	var rect := (panel as Control).get_global_rect()
	var sicht := harness.root.get_visible_rect()
	print("[PROBE] results panel rect=%s canvas=%s" % [str(rect), str(sicht)])
	return sicht.encloses(rect) and rect.size.y > RESULTS_MIN_HOEHE


## Nachzügler-Wache: die Erste-Viertelstunde-Tour-Karte (OnboardingGuide)
## kehrt NACH der Morgen-Ritual-Sequenz zurück und blockiert mit ihrem
## Scrim alle HUD-Taps — erst ausklingen lassen, dann (falls da) das X.
func _schritte_ritual_puffer() -> Array[Dictionary]:
	return [
		{
			"name": "tagesbonus_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{"name": "bonus_zu_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "coachmark_nachzuegler",
			"aktion": "tipp_falls_da",
			"text": "Alles klar!",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "guide_nachzuegler_wegtippen",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{"name": "hud_frei_moment", "aktion": "warte", "sekunden": 2.0},
	]


## BLOCKER-B7-Umgehung: ruft die Prompt-Aktion der CityScene direkt auf —
## exakt der Codepfad, den der (unerreichbare) Betreten-Knopf ausloest.
func betrete_flughafen_direkt() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	(szene as CityScene)._on_betreten("flughafen")
	return true
