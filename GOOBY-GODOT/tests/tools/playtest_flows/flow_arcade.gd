extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow (c) „Arcade“: Boot → Onboarding → Arcade über den HUD-Knopf →
## Teestube-Kachel → Pregame → „Spielen!“ → Countdown abwarten → wie ein
## Spieler gießen (Halten/Loslassen) → Pause → Weiter → nochmal gießen →
## Pause → „Beenden“ zurück zur Arcade → „Zurück“ nach Hause (Bug-Wächter,
## s. Befund unten) → notfalls über das Runden-Ende-Modal nach Hause.
## A1 STERNENBUCH-PROBE (G8-IDEEN A1): vor dem Öffnen werden 5 Spiele mit
## Schwer-Ziel gesät (15 ★) — das Buch füllt sich RÜCKWIRKEND beim ersten
## Öffnen: Meilenstein-Toast („Sternenbuch: 10 ★ …“) ploppt, der Claim
## ist idempotent gebucht, die Kacheln tragen Pips + Bestwert-Zeile, die
## Kopfzeilen-Kapsel zählt „38 Spiele · 15/114 ★“. Die Kachel MIT Pips
## bleibt tappbar (der Teestube-Tap direkt danach beweist es).
## Aufruf: tools/ci/run_playtest.sh flow_arcade

## A1-Saat: diese Spiele gelten als „Schwer-Ziel geschlagen“ (je 3 ★).
const SAAT_SPIELE: Array[String] = ["gvz", "gobnom", "carrotCatch", "bunnyHop", "teaParty"]
const SAAT_BESTWERT := 111


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "sternenbuch_saeen",
					"aktion": "tue",
					"funktion": sternenbuch_saeen,
					"erwartung": "5 Spiele mit 3 ★ im Save (15 ★ — Meilenstein 10 fällig)",
				},
				{
					"name": "arcade_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnArcade",
					"erwarte": {"route": "arcade"},
					"timeout_s": 60.0,
				},
				# A1: das Buch füllt sich rückwirkend beim ERSTEN Öffnen —
				# der Meilenstein-Toast ist der Screenshot-Beleg der Feier.
				{
					"name": "meilenstein_toast_ploppt",
					"aktion": "warte_bis",
					"bedingung": meilenstein_toast_da,
					"timeout_s": 30.0,
				},
				{
					"name": "meilenstein_claim_gebucht",
					"aktion": "tue",
					"funktion": meilenstein_claim_pruefen,
					"erwartung": "minigames.sternenbuch.claimed enthält die 10er-Schwelle",
				},
				{"name": "arcade_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "sternenbuch_kacheln_pruefen",
					"aktion": "tue",
					"funktion": sternenbuch_pruefen,
					"erwartung": "Kacheln mit Pips + Bestwert-Zeile, Kapsel zählt „… ★“",
				},
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


## A1-Saat: 5 Spiele mit Schwer-Ziel + Bestwert in den Save schreiben —
## das Sternenbuch soll sich RÜCKWIRKEND füllen (Boards gibt es seit W1d).
func sternenbuch_saeen() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("update"):
		print("[ARCADE] Sternenbuch-Saat: kein GameState")
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var mg: Dictionary = state["minigames"]
			var legacy: Dictionary = mg["legacy"]
			for id: String in SAAT_SPIELE:
				mg["plays"][id] = 1
				if not (legacy["beaten"].get(id) is Dictionary):
					legacy["beaten"][id] = {}
				legacy["beaten"][id]["normal"] = true
				legacy["beaten"][id]["hard"] = true
				legacy["best"][id] = SAAT_BESTWERT
	)
	print("[ARCADE] Sternenbuch-Saat: %d Spiele mit 3 ★" % SAAT_SPIELE.size())
	return true


## A1: irgendwo ist gerade ein Toast mit „Sternenbuch“ sichtbar (die Feier
## läuft über die RewardHub-ToastLayer — Meilenstein 10 ★ ist fällig).
func meilenstein_toast_da() -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Label and (aktuell as Control).is_visible_in_tree():
			if str((aktuell as Label).text).contains("Sternenbuch"):
				return true
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false


## A1: der Meilenstein-Claim liegt idempotent im Save (kein Doppel-Reward —
## die 10er-Schwelle ist gebucht, bevor die Arcade wieder verlassen wird).
func meilenstein_claim_pruefen() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("get_value"):
		return false
	var claimed: Variant = gs.get_value("minigames.sternenbuch.claimed", {})
	var ok := claimed is Dictionary and (claimed as Dictionary).has("10")
	print("[ARCADE] Meilenstein-Claims: %s" % [claimed])
	return ok


## A1: gesäte Kachel trägt 3 volle Pips + Bestwert-Zeile; die Kapsel zählt
## Spiele UND Sterne („38 Spiele · 15/114 ★“).
func sternenbuch_pruefen() -> bool:
	var kachel := harness.root.find_child("Tile_teaParty", true, false)
	if kachel == null:
		print("[ARCADE] Sternenbuch: Tile_teaParty fehlt")
		return false
	var pips := kachel.find_child("SternPips", true, false)
	var sterne := int(pips.get("earned")) if pips != null else -1
	var best_label := kachel.find_child("BestwertLabel", true, false) as Label
	var best_text := best_label.text if best_label != null else "FEHLT"
	var zaehler := harness.root.find_child("CountLabel", true, false) as Label
	var kapsel := zaehler.text if zaehler != null else "?"
	print(
		(
			"[ARCADE] Sternenbuch: teaParty %d ★, Bestwert-Zeile '%s', Kapsel '%s'"
			% [sterne, best_text, kapsel]
		)
	)
	if sterne != 3:
		return false
	if best_label == null or not best_text.contains(str(SAAT_BESTWERT)):
		return false
	return zaehler != null and kapsel.contains("★")
