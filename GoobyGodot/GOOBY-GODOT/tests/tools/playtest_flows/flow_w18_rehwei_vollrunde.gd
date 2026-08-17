extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Welle 3, Stadt-Agent) — Flow „REHWEI-Vollrunde“: geht über
## flow_w18_rehwei hinaus und prüft den W18-CC0-Umbau INHALTLICH: stehen
## die 4 getinteten Regal-Wände, die 2 Frischetheken und die 3 Kartons
## wirklich im Raum? Steht der Hirsch (Maskottchen) AUF dem Boden statt zu
## schweben? Schlendern Ambient-Kunden (OrtLeben) durch den Laden? Danach
## der Kauf-LOOP: ZWEI Käufe nacheinander (Kassen-Piep, Münzstand sinkt
## zweimal), Sheet zu, Laden verlassen.
## Aufruf: tools/ci/run_playtest.sh flow_w18_rehwei_vollrunde

## Hirsch-Toleranz: stag.glb wird bei y=0 gestellt — mehr als 5 cm Luft
## unterm Huf wäre ein Schwebe-Befund.
const HIRSCH_BODEN_TOLERANZ := 0.05

## Münzstand vor dem jeweiligen Kauf (merke_muenzen → kauf_verbucht).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_ritual_puffer())
	liste.append_array(_schritte_anfahrt())
	liste.append_array(_schritte_inventur())
	liste.append_array(_schritte_kauf_loop())
	return liste


## ------------------------------------------------------------------ Anfahrt


func _schritte_anfahrt() -> Array[Dictionary]:
	return [
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vorfahren",
			"aktion": "tue",
			"funktion": fahre_vor,
			"erwartung": "Auto steht am REHWEI-Parkplatz",
		},
		{
			"name": "rehwei_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/rehwei"},
			"timeout_s": 120.0,
		},
		{"name": "laden_ansehen", "aktion": "warte", "sekunden": 4.0},
	]


## ------------------------------------------- W18-Inventur (Möbel + Leben)


func _schritte_inventur() -> Array[Dictionary]:
	return [
		{
			"name": "regalwand_check",
			"aktion": "tue",
			"funktion": regalwand_da,
			"erwartung": "4 bookcase_closed-Regale stehen im Raum",
		},
		{
			"name": "frischetheken_check",
			"aktion": "tue",
			"funktion": frischetheken_da,
			"erwartung": "2 stall-Frischetheken stehen im Raum",
		},
		{
			"name": "kartonecke_check",
			"aktion": "tue",
			"funktion": kartonecke_da,
			"erwartung": "3 cardboard_box-Kartons stehen im Raum",
		},
		{
			"name": "hirsch_check",
			"aktion": "tue",
			"funktion": hirsch_am_boden,
			"erwartung": "stag.glb existiert und steht AUF dem Boden (y≈0)",
		},
		{
			"name": "kunden_check",
			"aktion": "tue",
			"funktion": kunden_da,
			"erwartung": "OrtLeben hat mindestens 1 Ambient-Besucher gespawnt",
		},
		# Kunden ein paar Sekunden schlendern lassen (Screenshot-Beleg,
		# dass sie sich bewegen und nicht in Möbeln stecken).
		{"name": "kunden_beobachten", "aktion": "warte", "sekunden": 5.0},
	]


## ---------------------------------------------------------------- Kauf-Loop


func _schritte_kauf_loop() -> Array[Dictionary]:
	return [
		{
			"name": "bubble_zeile_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "einkaufen_waehlen",
			"aktion": "tipp_text",
			"text": "Einkaufen!",
			"timeout_s": 60.0,
		},
		{"name": "laden_zeile_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "laden_zeile_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "laden_zeile_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "laden_zeile_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
		},
		{
			"name": "haendler_sheet_offen",
			"aktion": "warte_bis",
			"klasse": "HaendlerSheet",
			"timeout_s": 20.0,
		},
		{"name": "sortiment_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "kasse_merken_1",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "ware_kaufen_1",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 15.0,
		},
		{"name": "kassen_moment_1", "aktion": "warte", "sekunden": 1.5},
		# Kauf-LOOP: direkt der zweite Kauf im selben Sheet — der Münzstand
		# muss ERNEUT sinken (Kassen-Piep Nr. 2).
		{
			"name": "kasse_merken_2",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand erneut notiert",
		},
		{
			"name": "ware_kaufen_2",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 15.0,
		},
		{"name": "kassen_moment_2", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "sheet_schliessen",
			"aktion": "tipp_pos",
			"pos_rel": Vector2(0.5, 0.06),
			"pflicht": false,
		},
		{
			"name": "sheet_weg",
			"aktion": "warte_bis",
			"weg_klasse": "HaendlerSheet",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "laden_abschied", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "rehwei_verlassen",
			"aktion": "tipp_text",
			"text": "Raus",
			"erwarte": {"route": "city"},
			"timeout_s": 120.0,
		},
		{"name": "abschluss_strasse", "aktion": "warte", "sekunden": 3.0},
	]


## ---------------------------------------------------------------- Bausteine


## Auto direkt an den REHWEI-Parkplatz stellen (Muster flow_w18_rehwei).
func fahre_vor() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	var park: Vector3 = stadt.karte.parkplatz_welt("rehwei")
	stadt.auto.teleport(park.x, park.z)
	# Auto-Runner: ohne gehaltene Bremse rollt das Auto sofort aus dem
	# 7-m-Parkradius (Lauf-1-Lehre aus flow_w18_stadt_tour).
	stadt.auto.set_brake(true)
	return true


func regalwand_da() -> bool:
	return _zaehle_node3d("bookcase") >= 4


func frischetheken_da() -> bool:
	return _zaehle_node3d("stall") >= 2


func kartonecke_da() -> bool:
	# GLB-Innenknoten heißen camelCase („cardboardBoxClosed(Clone)“) —
	# Lauf-1-Lehre: NICHT nach snake_case-Dateinamen suchen.
	return _zaehle_node3d("cardboardbox") >= 3


## Hirsch existiert und steht am Boden (kein Schwebe-Asset).
func hirsch_am_boden() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var hirsch := _finde_node3d_mit_namen(szene, "stag")
	if hirsch == null:
		return false
	return absf(hirsch.position.y) <= HIRSCH_BODEN_TOLERANZ


## OrtLeben existiert und hat sichtbare Besucher gespawnt.
func kunden_da() -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		return false
	var leben := szene.find_child("OrtLeben", true, false)
	if leben == null or not leben.has_method("besucher_nodes"):
		return false
	return leben.besucher_nodes().size() >= 1


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


## Mitte des OBERSTEN sichtbaren, aktiven Preis-Knopfs ("{preis} ᴳ") im
## Händler-Sheet (Muster flow_w18_rehwei.kauf_knopf_pos).
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


## Node3D mit Namensteil zählen (GLB-Wurzeln heißen wie die Datei).
func _zaehle_node3d(teil: String) -> int:
	var szene := aktuelle_szene()
	if szene == null:
		return 0
	var nadel := teil.to_lower()
	var anzahl := 0
	var stapel: Array[Node] = [szene]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Node3D and String(aktuell.name).to_lower().contains(nadel):
			anzahl += 1
		for kind in aktuell.get_children():
			stapel.append(kind)
	return anzahl


func _finde_node3d_mit_namen(wurzel: Node, teil: String) -> Node3D:
	var nadel := teil.to_lower()
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Node3D and String(aktuell.name).to_lower().contains(nadel):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


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
