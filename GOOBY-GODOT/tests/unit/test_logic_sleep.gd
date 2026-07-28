extends TestCase
## W4-P5 (INFRA) — Lücken-Tests für scripts/logic/sleep.gd: die bislang
## ungetesteten public funcs is_sleeping / can_wake_early / sleep_remaining_ms
## / wake_up / grumpy_debuff / current_mood (Coverage-Sweep Plan §2.4-13).

const Sleep := preload("res://scripts/logic/sleep.gd")
const Stats := preload("res://scripts/logic/stats.gd")

const NOW_MS := 1768478400000
const MIN_MS := 60000


func _awake_state(energy := 50.0) -> Dictionary:
	return {
		"stats": {"hunger": 80.0, "energy": energy, "hygiene": 85.0, "fun": 70.0},
		"sleep": {"sleeping": false, "startedAt": 0, "wakeAt": 0},
		"grumpyUntil": 0,
		"lastTickAt": NOW_MS,
		"xp": 0,
		"level": 1,
		"coins": 100,
		"achievements": {"counters": {"sleeps": 0}},
	}


func test_is_sleeping_liest_slice_defensiv() -> void:
	assert_false(Sleep.is_sleeping(_awake_state()), "wach → false")
	assert_false(Sleep.is_sleeping({}), "fehlender sleep-Slice → false, kein Crash")
	assert_false(Sleep.is_sleeping({"sleep": "kaputt"}), "Junk-Slice → false")
	assert_false(Sleep.is_sleeping({"sleep": {"sleeping": 1}}), "nur strikt true zählt")
	var asleep := Sleep.start_sleep(_awake_state(30.0), NOW_MS)
	assert_true(Sleep.is_sleeping(asleep), "nach start_sleep → true")


func test_can_wake_early_sofort_erlaubt() -> void:
	assert_false(Sleep.can_wake_early(_awake_state(), NOW_MS), "wach → nie")
	var asleep := Sleep.start_sleep(_awake_state(30.0), NOW_MS)
	assert_true(Sleep.can_wake_early(asleep, NOW_MS), "Minute 0 → ja (EARLY_WAKE_AFTER_MIN=0)")
	assert_true(Sleep.can_wake_early(asleep, NOW_MS + 1), "sofort danach → ja")
	assert_eq(Sleep.EARLY_WAKE_AFTER_MIN, 0, "Gate offen ab 0 min")


func test_sleep_remaining_ms_countdown_und_clamp() -> void:
	assert_eq(Sleep.sleep_remaining_ms(_awake_state(), NOW_MS), 0, "wach → 0")
	# Energie 30 → ceil(30*(100-30)/100) = 21 min Schlafdauer.
	var asleep := Sleep.start_sleep(_awake_state(30.0), NOW_MS)
	assert_eq(int(asleep["sleep"]["wakeAt"]) - NOW_MS, 21 * MIN_MS, "Dauer 21 min")
	assert_eq(Sleep.sleep_remaining_ms(asleep, NOW_MS), 21 * MIN_MS)
	assert_eq(Sleep.sleep_remaining_ms(asleep, NOW_MS + 20 * MIN_MS), 1 * MIN_MS)
	assert_eq(Sleep.sleep_remaining_ms(asleep, NOW_MS + 60 * MIN_MS), 0, "nie negativ")


func test_wake_up_early_setzt_grumpy_debuff() -> void:
	var asleep := Sleep.start_sleep(_awake_state(30.0), NOW_MS)
	var at := NOW_MS + 6 * MIN_MS
	var res := Sleep.wake_up(asleep, at, {"early": true})
	var s: Dictionary = res["state"]
	assert_eq(res["events"], ["wokeEarly"])
	assert_false(Sleep.is_sleeping(s), "wach nach wake_up")
	assert_eq(int(s["grumpyUntil"]), at + 10 * MIN_MS, "grumpy 10 min")
	assert_eq(int(s["xp"]), 0, "früh geweckt → keine XP")
	assert_eq(int(s["achievements"]["counters"]["sleeps"]), 0, "kein sleeps-Zähler")
	# Original bleibt unangetastet (pure).
	assert_true(Sleep.is_sleeping(asleep), "Input-State unverändert")


func test_wake_up_completed_gibt_xp_und_zaehler() -> void:
	var asleep := Sleep.start_sleep(_awake_state(30.0), NOW_MS)
	var res := Sleep.wake_up(asleep, NOW_MS + 21 * MIN_MS, {})
	var s: Dictionary = res["state"]
	assert_eq(res["events"], ["wokeUp"])
	assert_eq(int(s["grumpyUntil"]), 0, "kein Debuff")
	assert_eq(int(s["xp"]), 10, "XP_COMPLETED_SLEEP = 10")
	assert_eq(int(s["achievements"]["counters"]["sleeps"]), 1, "sleeps-Zähler +1")


func test_grumpy_debuff_laeuft_ab() -> void:
	var s := _awake_state()
	s["grumpyUntil"] = NOW_MS + 10 * MIN_MS
	assert_almost(Sleep.grumpy_debuff(s, NOW_MS), 15.0, 1e-9, "aktiv → 15")
	assert_almost(Sleep.grumpy_debuff(s, NOW_MS + 10 * MIN_MS), 0.0, 1e-9, "abgelaufen → 0")
	assert_almost(Sleep.grumpy_debuff({}, NOW_MS), 0.0, 1e-9, "fehlendes Feld → 0")


func test_current_mood_zieht_debuff_ab() -> void:
	var s := _awake_state()
	var base := Stats.mood(s["stats"])
	s["grumpyUntil"] = NOW_MS + MIN_MS
	assert_almost(Sleep.current_mood(s, NOW_MS), base - 15.0, 1e-9, "Debuff aktiv")
	assert_almost(Sleep.current_mood(s, NOW_MS + 2 * MIN_MS), base, 1e-9, "danach normal")
