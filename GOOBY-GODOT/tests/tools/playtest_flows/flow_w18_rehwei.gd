extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18-Playtest (Asset-Integration F9) — Flow „REHWEI-Einkauf“: Reise in
## die Stadt, Auto an den REHWEI-Parkplatz stellen (Fahr-Skill ist nicht
## Testziel), „Betreten“, Innenraum mit den neuen CC0-Möbeln ansehen
## (Regal-Wand, Frischetheken mit Crop-Auslage, Kartons, Hirsch-Maskottchen
## statt Kisten-Primitives), über den Dialog „Einkaufen!“ das Händler-Sheet
## öffnen, EINE Ware kaufen (Kassen-Piep) und den Laden in Ruhe ablichten.
## Aufruf: tools/ci/run_playtest.sh flow_w18_rehwei

## Münzstand vor dem Kauf (merke_muenzen → kauf_verbucht).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_rehwei())
	return liste


func _schritte_rehwei() -> Array[Dictionary]:
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
		# Neue CC0-Einrichtung + Ambient-Kunden im Bild (W18-Umbau-Beleg).
		{"name": "laden_ansehen", "aktion": "warte", "sekunden": 4.0},
		# Begrüßungs-Bubble durchtippen (OrtDialogView-Typewriter): 1. Tap
		# zeigt die Zeile komplett, 2. Tap blättert weiter — erst DANACH
		# stehen die Options-Knöpfe. Der Fänger verschwindet mit der Bubble,
		# darum ist der zweite Tap „falls_da“ (Zeile kann schon fertig sein).
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
		# „Körbchen stehen links…“-Zeile durchtippen — der laden-Effekt
		# (HaendlerSheet öffnen) feuert erst, wenn die Bubble FERTIG ist.
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
		# Kauf per Positions-Tap auf den OBERSTEN sichtbaren Preis-Knopf
		# („5 ᴳ“ = Möhre): die Textsuche der Harness läuft von hinten und
		# fände zuerst die aus dem Sheet gescrollten Bücher-Knöpfe. Beweis
		# des Kaufs: der Münzstand sinkt (GameState economy.coins).
		{
			"name": "kasse_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "ware_kaufen",
			"aktion": "tipp_pos",
			"pos_funktion": kauf_knopf_pos,
			"erwarte": {"bedingung": kauf_verbucht},
			"timeout_s": 15.0,
		},
		{"name": "kassen_moment", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "sheet_schliessen",
			"aktion": "wisch",
			"von_rel": Vector2(0.5, 0.6),
			"nach_rel": Vector2(0.5, 0.97),
			"dauer_s": 0.4,
			"pflicht": false,
		},
		{"name": "abschluss_moebel", "aktion": "warte", "sekunden": 3.0},
	]


## Münzstand vor dem Kauf notieren (kauf_verbucht vergleicht dagegen).
func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


## Mitte des OBERSTEN sichtbaren, aktiven Preis-Knopfs ("{preis} ᴳ") im
## Händler-Sheet — Canvas-Koordinaten für tipp_pos.
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


## Kauf verbucht? Münzen müssen unter den notierten Stand gefallen sein.
func kauf_verbucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) < _muenzen_vorher


## Auto direkt an den REHWEI-Parkplatz stellen: das Ausparken abbrechen,
## teleportieren, Tempo nullen — der Betreten-Prompt kommt über
## CityScene._update_parkplatz von selbst.
func fahre_vor() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	stadt.auto.position = stadt.karte.parkplatz_welt("rehwei")
	stadt.auto.speed = 0.0
	return true
