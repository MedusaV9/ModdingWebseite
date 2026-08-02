extends TestCase
## A1 „Arcade-Sternenbuch“ (G8-IDEEN A1) — Wächter für die Meta-Progression
## der Arcade: (1) deterministische Stern-Ableitung aus minigames.plays +
## legacy.beaten (0..3), (2) Zähler-Mathe (gesamt/max über spielbare
## Spiele), (3) Bestwert fürs Kachel-Etikett (Zeit-Modi, ohne Endlos),
## (4) Meilenstein-Claims: Schwellen 10/25/50/80/114, IDEMPOTENT (kein
## Doppel-Reward), rückwirkendes Füllen, Münzen über Economy.award,
## (5) Arcade-Screen: Kacheln tragen Pips + Bestwert-Zeile, die Kopfzeilen-
## Kapsel zählt Spiele UND Sterne.

const ARCADE_SCENE := "res://scripts/minigames/arcade_screen.tscn"


## (1) Stern-Ableitung: gespielt → 1, Normal-Ziel → 2, Schwer-Ziel → 3.
func test_sterne_ableitung_deterministisch() -> void:
	var state := _state_mit({})
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 0, "unberührt = 0 ★")
	state = _state_mit({"plays": {"teaParty": 3}})
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 1, "gespielt = 1 ★")
	state = _state_mit({"plays": {"teaParty": 3}, "beaten": {"teaParty": {"normal": true}}})
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 2, "Normal-Ziel = 2 ★")
	state = _state_mit(
		{
			"plays": {"teaParty": 3},
			"beaten": {"teaParty": {"normal": true, "hard": true}},
		}
	)
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 3, "Schwer-Ziel = 3 ★")
	# Schwer ohne Normal zählt trotzdem 3 (höchste erreichte Stufe).
	state = _state_mit({"plays": {"teaParty": 1}, "beaten": {"teaParty": {"hard": true}}})
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 3, "hard schlägt alles")
	# Easy-Ziel bringt KEINEN Extra-Stern (Doc: ★★ ist explizit Normal).
	state = _state_mit({"plays": {"teaParty": 1}, "beaten": {"teaParty": {"easy": true}}})
	assert_eq(ArcadeSternenbuch.sterne_fuer(state, "teaParty"), 1, "easy = nur gespielt")


## (2) Zähler-Mathe: coming_soon-Spiele zählen weder Sterne noch Maximum.
func test_gesamt_und_max_sterne() -> void:
	var games: Array[Dictionary] = [{"id": "a"}, {"id": "b"}, {"id": "c", "coming_soon": true}]
	var state := _state_mit(
		{
			"plays": {"a": 2, "c": 9},
			"beaten": {"a": {"normal": true, "hard": true}, "c": {"hard": true}},
		}
	)
	assert_eq(ArcadeSternenbuch.max_sterne(games), 6, "2 spielbare × 3 = 6")
	assert_eq(ArcadeSternenbuch.gesamt_sterne(state, games), 3, "a=3, b=0 — coming_soon zählt nie")
	# Registry-Wirklichkeit: Maximum = 3 × spielbare Spiele (heute 38 → 114 ★)
	# — wächst automatisch mit neuen Manifest-Spielen mit.
	var registry_max := ArcadeSternenbuch.max_sterne(MinigameRegistry.all_games())
	assert_eq(
		registry_max,
		MinigameRegistry.playable().size() * ArcadeSternenbuch.STERNE_PRO_SPIEL,
		"Registry-Maximum folgt den spielbaren Spielen"
	)
	assert_true(registry_max >= 114, "38 Spiele im Bestand → mindestens 114 ★")


## (3) Kachel-Bestwert: Maximum über Normal/easy/hard — Endlos bleibt raus.
func test_bestwert_fuer_kachel() -> void:
	var state := _state_mit(
		{
			"best": {"teaParty": 50},
			"bestByDiff": {"teaParty": {"easy": 80, "hard": 30}},
			"endlessBest": {"teaParty": 999},
		}
	)
	assert_eq(ArcadeSternenbuch.bestwert_fuer(state, "teaParty"), 80, "Max der Zeit-Modi")
	assert_eq(ArcadeSternenbuch.bestwert_fuer(state, "gvz"), 0, "ohne Läufe: 0")


## (4a) Meilensteine: rückwirkend fällige Schwellen claimen + Münzen buchen.
func test_meilensteine_rueckwirkend_und_muenzen() -> void:
	var games := _fake_games(38)
	# 17 Spiele mit 3 ★ = 51 Sterne → Schwellen 10/25/50 sind fällig.
	var state := _state_mit_sternen(17, 3)
	var folge := ArcadeSternenbuch.claim_meilensteine(state, games, 1000)
	assert_eq(int(folge["sterne"]), 51, "17 × 3 = 51 ★")
	assert_eq(folge["neu"], [10, 25, 50] as Array[int], "drei Schwellen auf einmal (retro)")
	assert_eq(int(folge["coins"]), 40 + 80 + 120, "Münzen aller drei Meilensteine")
	assert_eq(int(state["economy"]["coins"]), 240, "Economy.award hat gebucht")
	assert_eq(int(state["economy"]["coinsEarned"]), 240, "…auch als earned")
	var claimed: Dictionary = state["minigames"]["sternenbuch"]["claimed"]
	assert_true(
		claimed.has("10") and claimed.has("25") and claimed.has("50"),
		"claimed merkt sich jede Schwelle"
	)
	assert_false(claimed.has("80"), "80 ★ noch offen")


## (4b) Idempotenz: der zweite Claim-Lauf zahlt NICHTS doppelt.
func test_meilensteine_idempotent_kein_doppel_reward() -> void:
	var games := _fake_games(38)
	var state := _state_mit_sternen(17, 3)
	ArcadeSternenbuch.claim_meilensteine(state, games, 1000)
	var coins_nach_erstem := int(state["economy"]["coins"])
	var zweiter := ArcadeSternenbuch.claim_meilensteine(state, games, 2000)
	assert_eq((zweiter["neu"] as Array).size(), 0, "zweiter Lauf: nichts Neues")
	assert_eq(int(zweiter["coins"]), 0, "zweiter Lauf: 0 Münzen")
	assert_eq(int(state["economy"]["coins"]), coins_nach_erstem, "Kontostand unverändert")
	# Wachstum claimt NUR die neue Schwelle (kein Nachzahlen alter).
	_setze_sterne(state, 27, 3)
	var dritter := ArcadeSternenbuch.claim_meilensteine(state, games, 3000)
	assert_eq(dritter["neu"], [80] as Array[int], "81 ★ → nur die 80er-Schwelle neu")
	assert_eq(int(dritter["coins"]), 200, "nur deren Münzen")


## (4c) Vollausbau: 114 ★ claimt auch die letzte Schwelle.
func test_meilenstein_vollausbau_114() -> void:
	var games := _fake_games(38)
	var state := _state_mit_sternen(38, 3)
	var folge := ArcadeSternenbuch.claim_meilensteine(state, games, 500)
	assert_eq(int(folge["sterne"]), 114, "Vollausbau")
	assert_eq(folge["neu"], [10, 25, 50, 80, 114] as Array[int], "alle fünf Schwellen fällig")
	assert_eq(int(folge["coins"]), 40 + 80 + 120 + 200 + 300, "Gesamt-Bonus 740")


## (5) Arcade-Screen: Pips + Bestwert-Zeile auf der Kachel, Sterne-Kapsel.
func test_arcade_screen_pips_und_zaehler() -> void:
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("update"):
		# Sichtbarer Stand für teaParty: gespielt + Normal-Ziel + Bestwert.
		gs.update(
			func(state: Dictionary) -> void:
				state["minigames"]["plays"]["teaParty"] = 2
				var legacy: Dictionary = state["minigames"]["legacy"]
				legacy["best"]["teaParty"] = 96
				if not (legacy["beaten"].get("teaParty") is Dictionary):
					legacy["beaten"]["teaParty"] = {}
				legacy["beaten"]["teaParty"]["normal"] = true
		)
	var screen: ArcadeScreen = (load(ARCADE_SCENE) as PackedScene).instantiate()
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(3)
	var kachel := screen.find_child("Tile_teaParty", true, false)
	assert_ne(kachel, null, "teaParty-Kachel im Grid")
	var pips := kachel.find_child("SternPips", true, false) if kachel != null else null
	assert_true(pips is ArcadeSternenbuch.SternPips, "Kachel trägt Sterne-Pips")
	if pips is ArcadeSternenbuch.SternPips and gs != null:
		assert_eq((pips as ArcadeSternenbuch.SternPips).earned, 2, "Pips zeigen 2 ★")
	var best_label := kachel.find_child("BestwertLabel", true, false) if kachel != null else null
	if gs != null:
		assert_ne(best_label, null, "Bestwert-Zeile auf der Kachel")
		if best_label != null:
			assert_true(str(best_label.get("text")).contains("96"), "…nennt den Bestwert")
			# Layout-Wache (Befund flow_arcade/017): Ellipsis-Trim + EXPAND-
			# Spacer quetschten das Label auf 0 px — es muss echte Breite haben.
			assert_true(
				(best_label as Control).size.x > 10.0, "Bestwert-Label hat sichtbare Breite"
			)
	var zaehler := screen.find_child("CountLabel", true, false) as Label
	assert_ne(zaehler, null, "Zähler-Kapsel vorhanden")
	if zaehler != null:
		var spielbar := MinigameRegistry.playable().size()
		assert_true(
			zaehler.text.contains(str(spielbar)), "Spielezahl bleibt (flow_pt3_rahmen-Wache)"
		)
		var max_text := "/%d ★" % ArcadeSternenbuch.max_sterne(MinigameRegistry.all_games())
		assert_true(zaehler.text.contains(max_text), "…plus Sammel-Zähler „n/114 ★“")
	screen.queue_free()
	await wait_frames(1)


## ── Helfer ───────────────────────────────────────────────────────────────


## Minimaler Save-Ausschnitt (nur die Sternenbuch-relevanten Äste).
func _state_mit(legacy_teile: Dictionary) -> Dictionary:
	return {
		"minigames":
		{
			"plays": legacy_teile.get("plays", {}),
			"legacy":
			{
				"best": legacy_teile.get("best", {}),
				"bestByDiff": legacy_teile.get("bestByDiff", {}),
				"endlessBest": legacy_teile.get("endlessBest", {}),
				"beaten": legacy_teile.get("beaten", {}),
				"lastPlayDay": {},
			},
		},
		"economy": {"coins": 0, "coinsEarned": 0},
	}


## Fake-Registry: n spielbare Spiele g0..g(n-1).
func _fake_games(n: int) -> Array[Dictionary]:
	var games: Array[Dictionary] = []
	for i in n:
		games.append({"id": "g%d" % i})
	return games


## Save, in dem die ersten `spiele` Fake-Spiele je `sterne` ★ tragen.
func _state_mit_sternen(spiele: int, sterne: int) -> Dictionary:
	var state := _state_mit({})
	_setze_sterne(state, spiele, sterne)
	return state


func _setze_sterne(state: Dictionary, spiele: int, sterne: int) -> void:
	var mg: Dictionary = state["minigames"]
	var legacy: Dictionary = mg["legacy"]
	for i in spiele:
		var id := "g%d" % i
		if sterne >= 1:
			mg["plays"][id] = 1
		if not (legacy["beaten"].get(id) is Dictionary):
			legacy["beaten"][id] = {}
		if sterne >= 2:
			legacy["beaten"][id]["normal"] = true
		if sterne >= 3:
			legacy["beaten"][id]["hard"] = true
