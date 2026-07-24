extends TestCase
## W1d — Goldwert-Parity der Pure-Logik-Ports gegen das echte Web-Verhalten.
## tests/fixtures/golden_values.json wird von tools/fixtures/make_v4_fixtures.mjs
## DIREKT aus dem Web-Code (GOOBY/src) erzeugt (Uhr gepinnt, TZ=UTC) —
## jede Assertion hier ist damit ein Beweis der Zahlengleichheit.

const Stats := preload("res://scripts/logic/stats.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")
const Economy := preload("res://scripts/logic/economy.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Offline := preload("res://scripts/logic/offline.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const Clock := preload("res://scripts/logic/clock.gd")

const GOLDEN_PATH := "res://tests/fixtures/golden_values.json"
## localDay(NOW) bei TZ=UTC (NOW = 2026-01-15T12:00:00Z, siehe Fixture-Gen).
const GOLDEN_DAY := "2026-01-15"

var _golden: Dictionary = {}


func _load_golden() -> Dictionary:
	if _golden.is_empty():
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(GOLDEN_PATH))
		assert_eq(err, OK, "golden_values.json muss parsen")
		_golden = json.data
	return _golden


func test_leveling_xp_curve() -> void:
	var g: Dictionary = _load_golden()["leveling"]
	assert_eq(Leveling.MAX_LEVEL, int(g["maxLevel"]))
	for level_key: String in g["xpToNext"].keys():
		assert_eq(
			Leveling.xp_to_next(int(level_key)),
			int(g["xpToNext"][level_key]),
			"xpToNext(%s)" % level_key
		)
	assert_eq(Leveling.cumulative_xp_to_level(40), int(g["cumulativeXpTo40"]))
	assert_eq(Leveling.cumulative_xp_to_level(10), int(g["cumulativeXpTo10"]))


func test_leveling_apply_xp_golden_cases() -> void:
	var cases: Array = _load_golden()["leveling"]["applyXpCases"]
	for c: Dictionary in cases:
		var got := Leveling.apply_xp(c["progress"], float(c["amount"]))
		var want: Dictionary = c["result"]
		var label := "applyXp(%s, %s)" % [str(c["progress"]), str(c["amount"])]
		assert_eq(got["xp"], want["xp"], label + " xp")
		assert_eq(got["level"], want["level"], label + " level")
		assert_eq(got["levelsGained"], want["levelsGained"], label + " levelsGained")
		assert_eq(got["coinsAwarded"], want["coinsAwarded"], label + " coinsAwarded")


func test_leveling_minigame_xp() -> void:
	var table: Dictionary = _load_golden()["leveling"]["minigameXp"]
	for coins_key: String in table.keys():
		assert_eq(
			Leveling.minigame_xp(float(coins_key)),
			int(table[coins_key]),
			"minigameXp(%s)" % coins_key
		)


func test_stats_rates_match_web() -> void:
	var g: Dictionary = _load_golden()["stats"]
	for k: String in Stats.KEYS:
		assert_eq(float(Stats.RATES_AWAKE[k]), float(g["ratesAwake"][k]), "awake " + k)
		assert_eq(float(Stats.RATES_ASLEEP[k]), float(g["ratesAsleep"][k]), "asleep " + k)


func test_stats_apply_tick_golden_cases() -> void:
	var cases: Array = _load_golden()["stats"]["applyTickCases"]
	for c: Dictionary in cases:
		var got := Stats.apply_tick(c["stats"], float(c["dtMin"]), c["opts"])
		for k: String in Stats.KEYS:
			assert_eq(
				got[k],
				c["result"][k],
				(
					"applyTick(%s, dt=%s, %s).%s"
					% [str(c["stats"]), str(c["dtMin"]), str(c["opts"]), k]
				)
			)


func test_stats_mood_golden_cases() -> void:
	var cases: Array = _load_golden()["stats"]["moodCases"]
	for c: Dictionary in cases:
		var got := Stats.mood(c["stats"], c["opts"])
		assert_eq(got, c["result"], "mood(%s, %s)" % [str(c["stats"]), str(c["opts"])])
		assert_eq(Stats.mood_band(got), c["band"], "moodBand(%s)" % str(got))


func test_stats_clamp_and_flags() -> void:
	assert_eq(Stats.clamp_stat(150.0), 100.0)
	assert_eq(Stats.clamp_stat(-3.0), 0.0)
	assert_eq(Stats.clamp_stat(NAN), 0.0, "NaN-Poisoning-Guard (web V2/FIX-A)")
	assert_eq(Stats.clamp_stat(INF), 0.0)
	assert_true(Stats.is_low(24.9))
	assert_false(Stats.is_low(25.0))
	assert_true(Stats.is_critical(9.9))
	assert_false(Stats.is_critical(10.0))
	assert_true(Stats.is_exhausted({"energy": 15.0}))
	assert_false(Stats.is_exhausted({"energy": 15.1}))
	var deltas := Stats.apply_deltas(
		{"hunger": 90.0, "energy": 5.0, "hygiene": 50.0, "fun": 50.0},
		{"hunger": 20.0, "energy": -10.0}
	)
	assert_eq(deltas["hunger"], 100.0)
	assert_eq(deltas["energy"], 0.0)
	assert_eq(deltas["hygiene"], 50.0)


func test_economy_golden_step_sequence() -> void:
	var g: Dictionary = _load_golden()["economy"]
	assert_eq(Economy.STARTING_COINS, int(g["startingCoins"]))
	assert_eq(Economy.DAY_COIN_CAP, int(g["dayCoinCap"]))
	var econ := Economy.default_slice()
	for step: Dictionary in g["steps"]:
		var label := "step %s %s" % [step["kind"], str(step["args"])]
		match step["kind"]:
			"start":
				pass
			"award":
				var got := Economy.award(econ, step["args"][0], step["args"][1], GOLDEN_DAY)
				assert_eq(got, int(step["ret"]), label + " ret")
			"spend":
				var ok := Economy.spend(econ, step["args"][0], step["args"][1])
				assert_eq(ok, step["ret"], label + " ret")
		assert_eq(econ["coins"], step["coins"], label + " coins")
		assert_eq(econ["coinsEarned"], step["coinsEarned"], label + " coinsEarned")
		assert_eq(econ["coinsSpent"], step["coinsSpent"], label + " coinsSpent")
		assert_eq(econ["dayCoins"], step["dayCoins"], label + " dayCoins")
		assert_eq(econ["endlessCoins"], step["endlessCoins"], label + " endlessCoins")


func test_economy_quick_prices() -> void:
	var prices: Dictionary = _load_golden()["economy"]["quickPrices"]
	for base_key: String in prices.keys():
		assert_eq(
			Economy.quick_price(float(base_key)), int(prices[base_key]), "quickPrice(%s)" % base_key
		)


func test_economy_day_ledger_rolls_over() -> void:
	var econ := Economy.default_slice()
	assert_eq(Economy.award(econ, 150, "glueckspilz", "2026-01-15"), 150)
	assert_eq(Economy.award(econ, 10, "modifier", "2026-01-15"), 0, "Tages-Cap erreicht")
	assert_eq(Economy.award(econ, 10, "modifier", "2026-01-16"), 10, "neuer Tag = neues Budget")


func test_sleep_durations_and_gates() -> void:
	var g: Dictionary = _load_golden()["sleep"]
	for energy_key: String in g["durations"].keys():
		assert_eq(
			Sleep.sleep_duration_min(float(energy_key)),
			int(g["durations"][energy_key]),
			"sleepDurationMin(%s)" % energy_key
		)
	for c: Dictionary in g["canSleepCases"]:
		var state := {
			"stats": {"energy": float(c["energy"])},
			"sleep": {"sleeping": c["sleeping"]},
		}
		assert_eq(Sleep.can_sleep(state), c["result"], "canSleep(%s)" % str(c))


func test_sleep_completed_grants_golden() -> void:
	var g: Dictionary = _load_golden()["sleep"]["completedGrants"]
	var input: Dictionary = g["input"]
	var state := {
		"xp": input["xp"],
		"level": input["level"],
		"coins": input["coins"],
		"achievements": {"counters": {"sleeps": input["sleeps"]}},
	}
	var out := Sleep.apply_completed_sleep_grants(state)
	assert_eq(out["xp"], g["output"]["xp"])
	assert_eq(out["level"], g["output"]["level"])
	assert_eq(out["coins"], g["output"]["coins"])
	assert_eq(
		out["achievements"]["counters"]["sleeps"], g["output"]["achievements"]["counters"]["sleeps"]
	)


func test_sleep_tick_auto_wake_golden() -> void:
	var g: Dictionary = _load_golden()["sleep"]["tickSleepCase"]
	var now_ms := int(_load_golden()["vacation"]["nowMs"])
	var state := {
		"stats": {"hunger": 60.0, "energy": 40.0, "hygiene": 60.0, "fun": 60.0},
		"sleep": {},
		"xp": 0,
		"level": 1,
		"coins": 0,
		"lastTickAt": now_ms,
		"achievements": {"counters": {"sleeps": 0}},
	}
	var started := Sleep.start_sleep(state, now_ms)
	assert_eq(started["sleep"]["sleeping"], g["started"]["sleeping"])
	assert_eq(started["sleep"]["startedAt"], g["started"]["startedAt"])
	assert_eq(started["sleep"]["wakeAt"], g["started"]["wakeAt"])
	var res := Sleep.tick_sleep(started, now_ms + 20 * 60000)
	var want: Dictionary = g["result"]["state"]
	for k: String in Stats.KEYS:
		assert_eq(res["state"]["stats"][k], want["stats"][k], "tickSleep stat " + k)
	assert_eq(res["state"]["sleep"]["sleeping"], want["sleep"]["sleeping"])
	assert_eq(res["state"]["xp"], want["xp"])
	assert_eq(res["state"]["level"], want["level"])
	assert_eq(res["state"]["coins"], want["coins"])
	assert_eq(res["state"]["lastTickAt"], want["lastTickAt"])
	assert_eq(
		res["state"]["achievements"]["counters"]["sleeps"],
		want["achievements"]["counters"]["sleeps"]
	)
	assert_eq(res["events"], Array(g["result"]["events"]))


func test_offline_golden_cases() -> void:
	var g: Dictionary = _load_golden()["offline"]
	assert_eq(Offline.AWAKE_RATE_MULT, float(g["awakeRateMult"]))
	assert_eq(Offline.AWAKE_CAP_MIN, float(g["awakeCapMin"]))
	var now_ms := int(_load_golden()["vacation"]["nowMs"])
	for c: Dictionary in g["cases"]:
		var label: String = c["label"]
		var state: Dictionary = c["input"].duplicate(true)
		if state.get("vacation") == null:
			state.erase("vacation")
		state["achievements"] = {"counters": {"sleeps": 0}}
		var sim := Offline.simulate_offline(state, now_ms)
		var want: Dictionary = c["result"]
		for k: String in Stats.KEYS:
			# double-Parity bis auf Summationsreihenfolge (Chunk-Schleife) —
			# 1e-9 absolut auf einer 0..100-Skala == wertgleich.
			assert_almost(
				float(sim["state"]["stats"][k]),
				float(want["stats"][k]),
				1e-9,
				"%s stat %s" % [label, k]
			)
		assert_eq(sim["state"]["lastTickAt"], want["lastTickAt"], label + " lastTickAt")
		assert_eq(sim["state"]["sleep"]["sleeping"], want["sleep"]["sleeping"], label + " sleeping")
		assert_eq(sim["state"]["xp"], want["xp"], label + " xp")
		assert_eq(sim["state"]["level"], want["level"], label + " level")
		assert_eq(sim["state"]["coins"], want["coins"], label + " coins")
		var vac := Vacation.slice_of(sim["state"])
		assert_eq(vac["phase"], want["vacationPhase"], label + " vacationPhase")
		assert_eq(vac["postcards"], want["vacationPostcards"], label + " postcards")
		assert_eq(sim["events"], Array(want["events"]), label + " events")


func test_vacation_catalog_matches_web() -> void:
	var g: Dictionary = _load_golden()["vacation"]
	assert_eq(Vacation.CATALOG.keys(), Array(g["ids"]), "9 Katalog-IDs, Reihenfolge web")
	assert_eq(Vacation.MS_PER_DAY, int(g["msPerDay"]))
	assert_eq(Vacation.PICKUP_WINDOW_MS, int(g["pickupWindowMs"]))


func test_clock_pin_and_local_day() -> void:
	var clock := Clock.new()
	clock.pin(int(_load_golden()["vacation"]["nowMs"]))
	clock.set_utc_offset_minutes(0)
	assert_eq(clock.now_ms(), 1768478400000)
	assert_eq(clock.local_day(), GOLDEN_DAY, "NOW = 2026-01-15T12:00Z")
	clock.advance(13 * 3600000)
	assert_eq(clock.local_day(), "2026-01-16", "13 h spaeter = naechster UTC-Tag")
	clock.set_utc_offset_minutes(-120)
	assert_eq(clock.local_day(), "2026-01-15", "UTC-2 ist noch am 15.")
