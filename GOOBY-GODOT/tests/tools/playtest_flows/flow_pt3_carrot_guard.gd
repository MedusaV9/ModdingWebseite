extends "res://tests/tools/playtest_flows/flow_pt3_basis.gd"
## PT-3 Flow (b2) „Karottenwache KOMPLETT“ (Welle H): Onboarding → Arcade →
## Kachel carrotGuard → Pregame (Normal) → komplette 45-s-Runde SPIELEN:
## der Flow haut wie ein Spieler auf den frischesten Maulwurf (bzw. den
## Karottenkönig, der mehrere Treffer braucht) — Loch-Rechtecke kommen aus
## dem Spiel selbst, der Tap läuft als echtes Touch-Event durchs Spielfeld
## → Results abwarten → Award-Nachrechnung (Münz-Delta == Results-Zeile,
## Tagesbonus ×2 beim Erstlauf) → „Nach Hause“ direkt ins Wohnzimmer
## (dritter Rahmen-Knopf, G7-P56).
## Aufruf: tools/ci/run_playtest.sh flow_pt3_carrot_guard

## Hau-Schritte: 45-s-Runde / ~1,5 s je Schritt + Reserve.
const HAU_SCHRITTE := 34


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(arcade_pregame_schritte("carrotGuard"))
	(
		liste
		. append_array(
			[
				{
					"name": "breakdown_fangen",
					"aktion": "tue",
					"funktion": breakdown_fangen,
					"erwartung": "round_finished-Lauscher hängt am Host",
				},
				{"name": "intro_beat_ansehen", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	for i in HAU_SCHRITTE:
		(
			liste
			. append(
				{
					"name": "maulwurf_hauen_%02d" % (i + 1),
					"aktion": "tipp_pos",
					"pos_funktion": maulwurf_punkt,
					"pflicht": false,
				}
			)
		)
		liste.append({"name": "lauern_%02d" % (i + 1), "aktion": "warte", "sekunden": 0.4})
	(
		liste
		. append_array(
			[
				{
					"name": "runde_zu_ende",
					"aktion": "warte_bis",
					"bedingung": rundenende_da,
					"timeout_s": 150.0,
				},
				{"name": "results_zaehlen_lassen", "aktion": "warte", "sekunden": 4.0},
				{
					"name": "score_und_bonks_loggen",
					"aktion": "tue",
					"funktion": ausbeute_loggen,
				},
				{
					"name": "award_nachgerechnet",
					"aktion": "tue",
					"funktion": award_nachrechnen,
					"erwartung": "Münz-Delta == Results-Zeile (+Tagesbonus ×2)",
				},
				{
					"name": "tagesbonus_da",
					"aktion": "warte_bis",
					"text": "Tagesbonus",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{
					"name": "nach_hause",
					"aktion": "tipp_text",
					"text": "Nach Hause",
					"erwarte": {"route": "home/living"},
					"timeout_s": 120.0,
				},
				{
					"name": "history_sauber_daheim",
					"aktion": "tue",
					"funktion": history_sauber,
					"erwartung": "mg_host/mg_pregame NICHT in der History",
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## Wie ein Spieler: König zuerst (braucht mehrere Treffer), sonst der
## Maulwurf mit der meisten Rest-Zeit (den treffen wir sicher). Kein Ziel
## → Vector2.ZERO (Tap verpufft, keine Whiff-Kombo-Strafe im Loch).
func maulwurf_punkt() -> Vector2:
	var g := spiel()
	if g == null or not bool(g.get("running")) or bool(g.get("finished")):
		return Vector2.ZERO
	if float(g.get("_intro_left")) > 0.0:
		return Vector2.ZERO
	var loecher: Array = g.get("_holes")
	var ziel := -1
	var koenig: Dictionary = g.get("king")
	if not koenig.is_empty():
		ziel = int(koenig.get("hole", -1))
	else:
		var beste_rest := 0.35
		var maulwuerfe: Array = g.get("moles")
		for maulwurf: Dictionary in maulwuerfe:
			var rest := float(maulwurf.get("left", 0.0))
			if rest > beste_rest:
				beste_rest = rest
				ziel = int(maulwurf.get("hole", -1))
	if ziel < 0 or ziel >= loecher.size():
		return Vector2.ZERO
	var rect: Rect2 = loecher[ziel]
	return spiel_punkt(rect.get_center())


## Ausbeute der Runde in den Log (Score, Bonks, Combo, geklaut).
func ausbeute_loggen() -> bool:
	var g := spiel()
	if g == null:
		print("[PT3] Ausbeute: Spiel schon abgeräumt")
		return true
	print(
		(
			"[PT3] Ausbeute: Score %d, Bonks %d, Karotten übrig %d, Könige %d"
			% [
				int(g.get("score")),
				int(g.get("bonks")),
				int(g.get("carrots")),
				int(g.get("kings_spawned")),
			]
		)
	)
	return true


## round_finished-Breakdown des Hosts einfangen (der exakte Award-Beleg —
## die Results-UI zeigt nur die Münz-Zeile, Level-Up-Coins kämen obendrauf).
func breakdown_fangen() -> bool:
	var h := host()
	if h == null:
		return false
	h.connect("round_finished", _merke_breakdown)
	return true


## Award exakt nachrechnen: Konto-Delta seit Pregame == breakdown.coins +
## Level-Up-Coins; Erstlauf des Tages (frisches Save) → firstToday + die
## §G5.2-Coin-Row (score/3, 4..25) ×2 Tagesbonus.
func award_nachrechnen() -> bool:
	var breakdown: Dictionary = zettel.get("breakdown", {})
	if breakdown.is_empty():
		print("[PT3] Award: kein Breakdown gefangen!")
		return false
	var score := int(breakdown.get("score", -1))
	var paid := int(breakdown.get("coins", 0))
	var level_coins := int(breakdown.get("coinsFromLevels", 0))
	var vorher := int(zettel.get("start_coins", 0))
	var delta := coins() - vorher
	var basis := clampi(int(floor(score / 3.0)), 4, 25)
	print(
		(
			(
				"[PT3] Award: Score %d, coins %d (Erwartung Row %d ×2 = %d), "
				+ "Level-Up-Coins %d, firstToday %s, Konto-Delta %+d"
			)
			% [
				score,
				paid,
				basis,
				basis * 2,
				level_coins,
				str(breakdown.get("firstToday")),
				delta,
			]
		)
	)
	var ok := delta == paid + level_coins
	if score > 0:
		ok = ok and paid == basis * 2 and bool(breakdown.get("firstToday"))
	return ok


func _merke_breakdown(breakdown: Dictionary) -> void:
	zettel["breakdown"] = breakdown
	print("[PT3] round_finished: %s" % str(breakdown))
