extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Flow „GOOBY-FREE hochkant“: der
## Duty-Free-Stand am Flughafen in BEIDEN Zuständen, im HOCHFORMAT
## (1320x2868): (1) OHNE Abflug-Buchung ist der Knopf ausgegraut + die
## „öffnet nur vor dem Abflug“-Zeile sichtbar (geschlossen-Zustand),
## (2) nach Taxi-Buchung (Glitzermeer, Dev-Key debug.taxi_warte_s hoch,
## damit das Taxi während des Bummelns NICHT wegfährt) öffnet der Shop,
## ein exklusives gfree-Möbel wird gekauft (Münzstand sinkt, Ware landet
## im Lager), (3) nach STORNO ist der Knopf wieder zu (Runde komplett).
## Aufruf: tools/ci/run_playtest.sh flow_w18_gfree_hochkant 1320x2868
##
## Staging (KEINE Spielmechanik-Änderung): Münzen auf 600 (Reise 190 +
## teuerstes gfree-Möbel 149), debug.taxi_warte_s = 300 (Taxi soll
## WARTEN, nicht abfahren — wir fliegen hier bewusst nie ab).

const STAGING_MUENZEN := 600
const TAXI_WARTE_S := 300

var _muenzen_vorher := -1
## Lagerbestand vor dem gfree-Kauf (Möbel landen in home.storage).
var _lager_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_zu_zustand())
	liste.append_array(_schritte_buchen_und_bummeln())
	liste.append_array(_schritte_storno_runde())
	return liste


## -------------------------------------------- Zustand 1: „geschlossen“


func _schritte_zu_zustand() -> Array[Dictionary]:
	return [
		{
			"name": "staging_kasse",
			"aktion": "tue",
			"funktion": staging_kasse,
			"erwartung": "Münzen aufgestockt + Taxi-Wartezeit gesetzt",
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
		{"name": "terminal_hochkant_ansehen", "aktion": "warte", "sekunden": 4.0},
		# GESCHLOSSEN-Zustand: Knopf disabled + Hinweis-Zeile sichtbar.
		{
			"name": "gfree_zu_check",
			"aktion": "tue",
			"funktion": gfree_ist_zu,
			"erwartung": "GOOBY-FREE-Knopf disabled + „öffnet nur…“-Hinweis sichtbar",
		},
	]


## ------------------------- Zustand 2: Buchung → Shop offen → Kauf


func _schritte_buchen_und_bummeln() -> Array[Dictionary]:
	return [
		{
			"name": "reise_schalter_oeffnen",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"klasse": "FlapBoard"},
			"timeout_s": 60.0,
		},
		{"name": "tafel_hochkant_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "ziel_glitzermeer",
			"aktion": "tipp_text",
			"text": "Glitzermeer",
			"erwarte": {"text": "Buchen"},
			"timeout_s": 30.0,
		},
		{
			"name": "kasse_merken_reise",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "reise_buchen",
			"aktion": "tipp_text",
			"text": "Buchen",
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 20.0,
		},
		{"name": "taxi_gerufen_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "reise_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "reise_sheet_zu",
			"aktion": "warte_bis",
			"weg_klasse": "ReiseApp",
			"timeout_s": 20.0,
		},
		# OFFEN-Zustand: mit gerufenem Taxi ist der Duty-Free freigeschaltet.
		{
			"name": "gfree_offen_check",
			"aktion": "tue",
			"funktion": gfree_ist_offen,
			"erwartung": "GOOBY-FREE-Knopf aktiv + Hinweis-Zeile weg",
		},
		{
			"name": "gfree_oeffnen",
			"aktion": "tipp_name",
			"node": "GoobyFree",
			"erwarte": {"text": "Flughafenpreise"},
			"timeout_s": 60.0,
		},
		{"name": "sortiment_hochkant_ansehen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "kasse_und_lager_merken",
			"aktion": "tue",
			"funktion": merke_kasse_und_lager,
			"erwartung": "Münzstand + Lagerbestand notiert",
		},
		{
			"name": "gfree_moebel_kaufen",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": gfree_kauf_verbucht},
			"timeout_s": 20.0,
		},
		{"name": "einpack_moment", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "gfree_sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{"name": "gfree_zu_moment", "aktion": "warte", "sekunden": 1.5},
	]


## --------------------------- Zustand 3: Storno → wieder „geschlossen“


func _schritte_storno_runde() -> Array[Dictionary]:
	return [
		{
			"name": "reise_schalter_wieder",
			"aktion": "tipp_name",
			"node": "Reise",
			"erwarte": {"text": "Stornieren"},
			"timeout_s": 60.0,
		},
		{"name": "countdown_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "taxi_stornieren",
			"aktion": "tipp_text",
			"text": "Stornieren",
			"erwarte": {"text": "Wohin soll Gooby fliegen?"},
			"timeout_s": 30.0,
		},
		{"name": "storno_moment", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "reise_sheet_schliessen_2",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "reise_sheet_zu_2",
			"aktion": "warte_bis",
			"weg_klasse": "ReiseApp",
			"timeout_s": 20.0,
		},
		# Runde komplett: ohne Buchung ist der Duty-Free WIEDER zu.
		{
			"name": "gfree_wieder_zu_check",
			"aktion": "tue",
			"funktion": gfree_ist_zu,
			"erwartung": "GOOBY-FREE nach Storno wieder disabled + Hinweis da",
		},
		{
			"name": "flughafen_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "abschluss_strasse", "aktion": "warte", "sekunden": 3.0},
	]


## ---------------------------------------------------------------- Bausteine


func staging_kasse() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", STAGING_MUENZEN)
	var settings := harness.root.get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("set_setting"):
		return false
	settings.set_setting("debug.taxi_warte_s", TAXI_WARTE_S)
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


## „Geschlossen“-Vertrag: Knopf disabled UND die Hinweis-Zeile sichtbar.
func gfree_ist_zu() -> bool:
	var knopf := harness.root.find_child("GoobyFree", true, false)
	if not (knopf is Button):
		return false
	var hinweis := harness.root.find_child("GoobyFreeHinweis", true, false)
	if not (hinweis is Label):
		return false
	return (knopf as Button).disabled and (hinweis as Label).is_visible_in_tree()


## „Offen“-Vertrag: Knopf aktiv UND die Hinweis-Zeile ausgeblendet.
func gfree_ist_offen() -> bool:
	var knopf := harness.root.find_child("GoobyFree", true, false)
	if not (knopf is Button):
		return false
	var hinweis := harness.root.find_child("GoobyFreeHinweis", true, false)
	if not (hinweis is Label):
		return false
	return not (knopf as Button).disabled and not (hinweis as Label).is_visible_in_tree()


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


func merke_kasse_und_lager() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	_lager_vorher = _lager_groesse()
	return true


## gfree-Kauf verbucht: Münzen runter UND ein Möbel mehr im Lager.
func gfree_kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0 or _lager_vorher < 0:
		return false
	if int(gs.get_value("economy.coins", 0)) >= _muenzen_vorher:
		return false
	return _lager_groesse() > _lager_vorher


func _lager_groesse() -> int:
	var gs := game_state()
	if gs == null:
		return -1
	var lager: Variant = gs.get_value("home.storage", [])
	return (lager as Array).size() if lager is Array else -1


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
