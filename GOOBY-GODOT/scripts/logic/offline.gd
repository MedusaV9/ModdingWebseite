extends RefCounted
## Offline catch-up simulation — port of GOOBY/src/systems/offline.js (§E4).
##
## Ported core paths (binding algorithm, numbers identical to the web):
##   - sleeping: asleep rates for min(elapsed, wakeAt - lastTickAt); complete
##     the wake if due ('wokeUp' + §C1.4 grants); the remaining elapsed time
##     decays awake at x0.3, capped at 480 sim-minutes.
##   - awake: the whole elapsed time decays at x0.3, capped at 480 sim-min.
##   - 'statLow:<stat>' for every stat that CROSSED below 25 during the sim
##     (already-low stats are silent), in KEYS order after 'wokeUp'.
##   - V5/VACATION: while away the stats are FROZEN; the vacation phase
##     machine catches up at the end (postcard/returnReady/overdue events).
##
## W2 HOOKS (deliberately NOT ported in W1d — the web advances these engines
## in the same sim): health/weight (same 0.3x/480-min awake window) and
## garden (FULL elapsed rate, uncapped, + offline rain blocks). When W2 ports
## systems/health|weight|garden.js, their catch-up slots in RIGHT HERE
## between the statLow loop and the vacation tick (web order: health events
## first, then 'cropsReady', then vacation events).
##
## Parity proven against golden_values.json offline.cases (all 6).

const Stats := preload("res://scripts/logic/stats.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")

## Awake decay runs at 0.3x the awake rates while the app is closed.
const AWAKE_RATE_MULT := 0.3
## Cap of simulated awake-decay minutes (8 h). Sleep progress is uncapped.
const AWAKE_CAP_MIN := 480.0


## Simulate the time the app was closed. Pure — returns
## {"state": Dictionary (new), "events": Array[String]}.
static func simulate_offline(state: Dictionary, now_ms: int) -> Dictionary:
	var events: Array = []
	var last := _num(state.get("lastTickAt"))
	if last == 0.0:
		last = float(now_ms)
	var elapsed_ms := float(now_ms) - last
	if elapsed_ms <= 0.0:
		var unchanged := state.duplicate(true)
		unchanged["lastTickAt"] = now_ms
		return {"state": unchanged, "events": events}

	var stats_before: Dictionary = state.get("stats", {}).duplicate()
	var s := state.duplicate(true)
	var awake_ms := elapsed_ms

	# V5/VACATION: while Gooby was away the whole absence, his stats are
	# FROZEN (the resort cares for him; the reunion refills stats anyway).
	var vac_away := Vacation.is_away(s)
	if vac_away:
		awake_ms = 0.0

	if not vac_away and Sleep.is_sleeping(s):
		# Also the recovery path for a sleep that completed while the app was
		# hidden and then killed (web F2/E4 note): grants apply exactly once.
		var wake_at := _num(s["sleep"].get("wakeAt"))
		var asleep_ms := maxf(0.0, minf(elapsed_ms, wake_at - last))
		s["stats"] = Stats.apply_tick(s["stats"], asleep_ms / 60000.0, {"asleep": true})
		if float(now_ms) >= wake_at:
			var woken := Sleep.wake_up(s, int(wake_at), {"early": false})
			s = woken["state"]
			events.append_array(woken["events"])
			awake_ms = elapsed_ms - asleep_ms
		else:
			awake_ms = 0.0

	var awake_min := minf(awake_ms / 60000.0, AWAKE_CAP_MIN)
	if awake_min > 0.0:
		s["stats"] = Stats.apply_tick(s["stats"], awake_min, {"rateMult": AWAKE_RATE_MULT})
	s["lastTickAt"] = now_ms

	for k in Stats.KEYS:
		var before := _num(stats_before.get(k))
		if before >= Stats.LOW_STAT and float(s["stats"][k]) < Stats.LOW_STAT:
			events.append("statLow:%s" % k)

	# (W2 hook: health/weight/garden offline advance lands here — see header.)

	# V5/VACATION phase catch-up: one pure tick walks every stage the absence
	# crossed and appends the welcome-back string events in transition order.
	var r := Vacation.tick(s, now_ms)
	if r["changes"] != null:
		s["vacation"] = r["changes"]
	for ev: Dictionary in r["events"]:
		match ev.get("type"):
			"postcard":
				events.append("vacationPostcard")
			"returnReady":
				events.append("vacationReturnReady")
			"overdue":
				events.append("vacationOverdue")

	return {"state": s, "events": events}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
