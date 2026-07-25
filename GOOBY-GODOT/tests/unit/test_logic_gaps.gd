extends TestCase
## W4-P5 (INFRA) — restliche Logic-Lücken aus dem Coverage-Sweep (Plan §2.4-13):
## economy.norm_award/norm_cost/can_afford, stats.clamp_stats, clock.unpin
## und die Framework-Policy-Helfer js_round/normalize_difficulty/
## difficulty_enabled (Coin-Formel-Fundament, §G5).

const Economy := preload("res://scripts/logic/economy.gd")
const Stats := preload("res://scripts/logic/stats.gd")
const Clock := preload("res://scripts/logic/clock.gd")
const FrameworkLogic := preload("res://scripts/minigames/framework_logic.gd")


func test_norm_award_rundet_gegen_den_spieler() -> void:
	assert_eq(Economy.norm_award(7.9), 7, "Award floort")
	assert_eq(Economy.norm_award(7), 7)
	assert_eq(Economy.norm_award(-3), 0, "nie negativ")
	assert_eq(Economy.norm_award(-0.5), 0)
	assert_eq(Economy.norm_award("junk"), 0, "Nicht-Zahl → 0")
	assert_eq(Economy.norm_award(null), 0)


func test_norm_cost_rundet_auf() -> void:
	assert_eq(Economy.norm_cost(7.1), 8, "Kosten ceilen")
	assert_eq(Economy.norm_cost(7), 7)
	assert_eq(Economy.norm_cost(-3), 0, "nie negativ")
	assert_eq(Economy.norm_cost(true), 0, "Bool ist keine Zahl")


func test_can_afford_grenzfaelle() -> void:
	var econ := Economy.default_slice()
	econ["coins"] = 100
	assert_true(Economy.can_afford(econ, 100), "exakt reicht")
	assert_false(Economy.can_afford(econ, 101))
	assert_true(Economy.can_afford(econ, 99.5), "99.5 → ceil 100 → reicht exakt")
	assert_false(Economy.can_afford(econ, 100.5), "100.5 → ceil 101 → zu teuer")
	assert_true(Economy.can_afford(econ, 0), "0 geht immer")
	assert_false(Economy.can_afford({}, 1), "leerer Slice → 0 Coins")


func test_clamp_stats_haertet_junk() -> void:
	var out := Stats.clamp_stats({"hunger": 150.0, "energy": -20.0, "hygiene": "kaputt"})
	assert_almost(out["hunger"], 100.0, 1e-9, "über MAX → 100")
	assert_almost(out["energy"], 0.0, 1e-9, "unter MIN → 0")
	assert_almost(out["hygiene"], 0.0, 1e-9, "Junk → 0")
	assert_almost(out["fun"], 0.0, 1e-9, "fehlender Key → 0")
	assert_eq(out.keys().size(), 4, "genau die 4 Stat-Keys")
	var inf_out := Stats.clamp_stats({"hunger": INF, "energy": -INF, "hygiene": NAN, "fun": 5.0})
	assert_almost(inf_out["hunger"], 0.0, 1e-9, "INF → MIN (NaN-Poisoning-Guard)")
	assert_almost(inf_out["energy"], 0.0, 1e-9)
	assert_almost(inf_out["hygiene"], 0.0, 1e-9)
	assert_almost(inf_out["fun"], 5.0, 1e-9)


func test_clock_unpin_kehrt_zur_systemuhr_zurueck() -> void:
	var clock := Clock.new()
	clock.pin(1234)
	assert_eq(clock.now_ms(), 1234, "gepinnt")
	clock.advance(6)
	assert_eq(clock.now_ms(), 1240, "advance auf gepinnter Uhr")
	clock.unpin()
	var sys_now := int(Time.get_unix_time_from_system() * 1000.0)
	assert_true(absi(clock.now_ms() - sys_now) < 5000, "entpinnt → Systemzeit")
	clock.advance(999999)
	assert_true(absi(clock.now_ms() - sys_now) < 5000, "advance ist entpinnt ein No-op")


func test_js_round_halbe_richtung_plus_unendlich() -> void:
	assert_eq(FrameworkLogic.js_round(0.5), 1, "JS Math.round(.5) → aufwärts")
	assert_eq(FrameworkLogic.js_round(1.5), 2)
	assert_eq(FrameworkLogic.js_round(2.5), 3, "kein Banker's Rounding")
	assert_eq(FrameworkLogic.js_round(2.4), 2)
	assert_eq(FrameworkLogic.js_round(2.6), 3)
	assert_eq(FrameworkLogic.js_round(0.0), 0)


func test_normalize_difficulty_whitelist() -> void:
	for mode in ["easy", "normal", "hard", "endless"]:
		assert_eq(FrameworkLogic.normalize_difficulty(mode), mode, mode + " bleibt")
	assert_eq(FrameworkLogic.normalize_difficulty("EASY"), "normal", "case-strikt")
	assert_eq(FrameworkLogic.normalize_difficulty("quatsch"), "normal")
	assert_eq(FrameworkLogic.normalize_difficulty(null), "normal")
	assert_eq(FrameworkLogic.normalize_difficulty(3), "normal", "Nicht-String → normal")


func test_difficulty_enabled_ausnahmen() -> void:
	assert_true(FrameworkLogic.difficulty_enabled("teaParty"))
	assert_false(FrameworkLogic.difficulty_enabled("cityDrive"), "Trip-Semantik → aus")
	assert_false(FrameworkLogic.difficulty_enabled("goobyWelt"), "Chill-Special → aus")
	assert_false(FrameworkLogic.difficulty_enabled("teaParty", {"dev": true}), "dev-Meta → aus")
	assert_true(FrameworkLogic.difficulty_enabled("teaParty", {"dev": false}))
