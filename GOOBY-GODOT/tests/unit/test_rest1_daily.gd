extends TestCase
## REST-1 Rang 8: Tagesbonus-Logik über Datumssprünge — Serie zählt hoch,
## EIN verpasster Tag ist Kulanz (Serie läuft weiter), zwei verpasste Tage
## brechen sie; Belohnungstabelle Web-verbatim (20..100, ab Tag 7 + Snack);
## Abholen ist einmalig pro Tag und läuft über den EINEN Geld-Pfad.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1_750_000_000_000


func _fresh_state() -> Dictionary:
	return SaveSchema.default_state(NOW_MS)


func test_prev_day_ueber_monats_und_jahresgrenzen() -> void:
	assert_eq(DailyBonus.prev_day("2026-07-27"), "2026-07-26", "normaler Tag")
	assert_eq(DailyBonus.prev_day("2026-03-01"), "2026-02-28", "Monatsgrenze")
	assert_eq(DailyBonus.prev_day("2024-03-01"), "2024-02-29", "Schaltjahr")
	assert_eq(DailyBonus.prev_day("2026-01-01"), "2025-12-31", "Jahresgrenze")
	assert_eq(DailyBonus.prev_day("kaputt"), "", "kaputter Input → leer")


func test_is_claimable_einmal_pro_tag() -> void:
	assert_true(DailyBonus.is_claimable({}, "2026-07-27"), "frisch abholbar")
	assert_true(DailyBonus.is_claimable({"lastClaimDay": "2026-07-26"}, "2026-07-27"), "neuer Tag")
	assert_false(
		DailyBonus.is_claimable({"lastClaimDay": "2026-07-27"}, "2026-07-27"), "heute schon"
	)


func test_next_streak_hochzaehlen_kulanz_und_bruch() -> void:
	var today := "2026-07-27"
	assert_eq(DailyBonus.next_streak({}, today), {"streak": 1, "grace": false}, "erster Tag")
	assert_eq(
		DailyBonus.next_streak({"lastClaimDay": "2026-07-26", "streak": 3}, today),
		{"streak": 4, "grace": false},
		"gestern geclaimt → +1"
	)
	assert_eq(
		DailyBonus.next_streak({"lastClaimDay": "2026-07-25", "streak": 3}, today),
		{"streak": 4, "grace": true},
		"EIN verpasster Tag → Kulanz, Serie läuft weiter"
	)
	assert_eq(
		DailyBonus.next_streak({"lastClaimDay": "2026-07-24", "streak": 9}, today),
		{"streak": 1, "grace": false},
		"zwei verpasste Tage → Serie bricht"
	)
	assert_eq(
		DailyBonus.next_streak({"lastClaimDay": "2026-07-26", "streak": 0}, today),
		{"streak": 1, "grace": false},
		"streak 0 → sauber bei 1 starten"
	)


func test_belohnungstabelle_web_verbatim() -> void:
	var expected := [20, 30, 40, 50, 60, 80, 100]
	for i in expected.size():
		var reward := DailyBonus.reward_for_streak(i + 1)
		assert_eq(int(reward["coins"]), expected[i], "Tag %d zahlt %d" % [i + 1, expected[i]])
		assert_eq(bool(reward["includes_food"]), i + 1 >= 7, "Snack ab Tag 7 (Tag %d)" % (i + 1))
	var day12 := DailyBonus.reward_for_streak(12)
	assert_eq(int(day12["coins"]), 100, "ab Tag 7 bleibt das Maximum")
	assert_true(bool(day12["includes_food"]), "und der Snack bleibt dabei")


func test_claim_ist_einmalig_pro_tag() -> void:
	var state := _fresh_state()
	var coins_start := int(state["economy"]["coins"])
	var res := DailyBonus.claim(state, "2026-07-27")
	assert_true(bool(res["ok"]), "erster Claim ok")
	assert_eq(int(res["streak_day"]), 1, "Tag 1")
	assert_eq(int(res["coins"]), 20, "Tag 1 zahlt 20")
	assert_eq(int(state["economy"]["coins"]), coins_start + 20, "Münzen über Economy.award")
	assert_eq(str(state["daily"]["lastClaimDay"]), "2026-07-27", "lastClaimDay gestempelt")
	var again := DailyBonus.claim(state, "2026-07-27")
	assert_false(bool(again["ok"]), "zweiter Claim am selben Tag ist no-op")
	assert_eq(int(state["economy"]["coins"]), coins_start + 20, "keine Doppel-Münzen")


func test_claim_ueber_datumsspruenge_mit_kulanz_und_bruch() -> void:
	var state := _fresh_state()
	assert_true(bool(DailyBonus.claim(state, "2026-07-20")["ok"]), "Tag 1")
	var day2 := DailyBonus.claim(state, "2026-07-21")
	assert_eq(int(day2["streak_day"]), 2, "Folgetag → Serie 2")
	assert_eq(int(day2["coins"]), 30, "Tag 2 zahlt 30")
	assert_false(bool(day2["grace"]), "keine Kulanz nötig")
	# 22.07. verpasst — der 23.07. zählt per Kulanz trotzdem weiter.
	var day3 := DailyBonus.claim(state, "2026-07-23")
	assert_eq(int(day3["streak_day"]), 3, "Kulanztag rettet die Serie")
	assert_true(bool(day3["grace"]), "Kulanz gemeldet (Popup-Hinweis)")
	# 24.+25.07. verpasst — am 26.07. beginnt die Serie neu.
	var reset := DailyBonus.claim(state, "2026-07-26")
	assert_eq(int(reset["streak_day"]), 1, "zwei verpasste Tage → Bruch")
	assert_false(bool(reset["grace"]), "Bruch ist keine Kulanz")


func test_claim_ab_tag7_gibt_snack_ins_inventar() -> void:
	var state := _fresh_state()
	state["daily"] = {"lastClaimDay": "2026-07-26", "streak": 6}
	var ids := FoodCatalog.FOODS.keys()
	ids.sort()
	var expected_food := str(ids[0])
	var before := int(state["inventory"]["food"].get(expected_food, 0))
	var res := DailyBonus.claim(state, "2026-07-27", 0.0)
	assert_eq(int(res["streak_day"]), 7, "Serie 7")
	assert_eq(int(res["coins"]), 100, "Tag 7 zahlt 100")
	assert_eq(str(res["food_id"]), expected_food, "rng 0.0 → erster sortierter Snack")
	assert_eq(
		int(state["inventory"]["food"].get(expected_food, 0)), before + 1, "Snack im Inventar"
	)


func test_pick_bonus_food_grenzen() -> void:
	var ids := FoodCatalog.FOODS.keys()
	ids.sort()
	assert_eq(DailyBonus.pick_bonus_food(0.0), str(ids[0]), "0.0 → erstes")
	assert_eq(DailyBonus.pick_bonus_food(0.999), str(ids[ids.size() - 1]), "0.999 → letztes")
	assert_eq(DailyBonus.pick_bonus_food(1.5), str(ids[ids.size() - 1]), "Overflow geklemmt")
