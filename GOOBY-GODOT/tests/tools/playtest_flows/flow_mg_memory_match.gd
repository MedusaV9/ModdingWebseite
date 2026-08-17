extends "res://tests/tools/playtest_flows/flow_mg_basis.gd"
## Flow „Memory“ (memoryMatch, Hochkant-Spiel letterboxt): Arcade (mit
## Wisch-Scrollen) → Pregame → Countdown → Merk-Fenster abwarten → wie
## ein Spieler mit PERFEKTEM Gedächtnis Paare tippen (der Flow liest die
## Kartengesichter aus der laufenden Spiel-Instanz und tippt die echten
## Kartenmitten über die reguläre Eingabe-Pipeline) — nur so endet die
## getaktete Runde deterministisch (Brett geschafft). Zwischen Paar 2 und
## 3: Pause/Weiter (3-2-1). Danach Results → „Nochmal“ → 2 Paare in
## Runde 2 → Pause/„Beenden“ → Arcade → „Zurück“ = Wohnzimmer
## (Router-Fix-Wache).
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_mg_memory_match


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_bis_pregame("memoryMatch", 1))
	liste.append_array(spiel_starten(false))
	liste.append({"name": "merkfenster_ansehen", "aktion": "warte", "sekunden": 2.0})
	for nr in [1, 2]:
		liste.append_array(paar_schritte(nr, true))
	liste.append_array(pause_und_weiter())
	for nr in [3, 4, 5, 6, 7, 8]:
		liste.append_array(paar_schritte(nr, true))
	for nr in [9, 10, 11]:
		liste.append_array(paar_schritte(nr, false))
	(
		liste
		. append_array(
			[
				runde_zu_ende(120.0),
				{"name": "results_ansehen", "aktion": "warte", "sekunden": 4.0},
			]
		)
	)
	liste.append_array(nochmal_und_los())
	liste.append({"name": "runde2_merkfenster", "aktion": "warte", "sekunden": 2.0})
	for nr in [12, 13]:
		liste.append_array(paar_schritte(nr, false))
	liste.append_array(beenden_und_heim())
	return liste


## Ein Paar-Zyklus: warten bis Karten tippbar sind, Karte A, kurz warten,
## Partner-Karte B, Auflösung abwarten (Screenshot nach jedem Schritt).
func paar_schritte(nr: int, pflicht: bool) -> Array[Dictionary]:
	return [
		{
			"name": "paar_%02d_bereit" % nr,
			"aktion": "warte_bis",
			"bedingung": karten_bereit,
			"timeout_s": 25.0,
			"pflicht": pflicht,
		},
		{
			"name": "paar_%02d_karte_a" % nr,
			"aktion": "tipp_pos",
			"pos_funktion": naechste_karte_pos,
			"pflicht": pflicht,
		},
		{"name": "paar_%02d_kurz" % nr, "aktion": "warte", "sekunden": 0.8},
		{
			"name": "paar_%02d_karte_b" % nr,
			"aktion": "tipp_pos",
			"pos_funktion": naechste_karte_pos,
			"pflicht": pflicht,
		},
		{"name": "paar_%02d_aufloesen" % nr, "aktion": "warte", "sekunden": 1.4},
	]


## Eingabe-Fenster offen? (Intro/Merk-/Spick-Fenster/Auflösung vorbei und
## keine halboffene Wahl.) Nach dem Brett-Ende immer true, damit die
## Reserve-Zyklen nicht in Timeouts laufen.
func karten_bereit() -> bool:
	var spiel := spiel_node()
	if spiel == null:
		return false
	if bool(spiel.get("finished")):
		return true
	var laeuft := bool(spiel.get("running")) and not bool(spiel.get("game_paused"))
	var fenster_zu := (
		float(spiel.get("_intro_left")) <= 0.0
		and float(spiel.get("reveal_left")) <= 0.0
		and float(spiel.get("peek_left")) <= 0.0
		and float(spiel.get("resolve_left")) <= 0.0
	)
	return laeuft and fenster_zu and (spiel.get("picked") as Array).is_empty()


## Mitte der nächsten sinnvollen Karte (Canvas-Koordinaten): liegt schon
## eine Karte offen, deren Partner (gleiches Gesicht, verdeckt), sonst die
## erste verdeckte Karte. Brett fertig → neutrale Ecke (kein Fehl-Tap auf
## Results-Knöpfe).
func naechste_karte_pos() -> Vector2:
	var spiel := spiel_node()
	if spiel == null or bool(spiel.get("finished")):
		return Vector2(8.0, 8.0)
	var karten: Array = spiel.get("cards")
	var picked: Array = spiel.get("picked")
	var ziel := -1
	if picked.size() == 1:
		var offen: Dictionary = karten[picked[0]]
		for i in karten.size():
			if i == int(picked[0]):
				continue
			var karte: Dictionary = karten[i]
			if str(karte["state"]) == "down" and int(karte["face"]) == int(offen["face"]):
				ziel = i
				break
	if ziel < 0:
		for i in karten.size():
			if str((karten[i] as Dictionary)["state"]) == "down":
				ziel = i
				break
	if ziel < 0:
		return Vector2(8.0, 8.0)
	return spielfeld_punkt(spiel.call("_card_center", ziel))
