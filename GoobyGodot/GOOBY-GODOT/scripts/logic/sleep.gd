extends RefCounted
## Sleep state machine — 1:1 port of GOOBY/src/systems/sleep.js (§C1.4).
##
## Operates on a state dict with the web-verbatim slice keys (see
## save_schema.gd `gooby` slice): stats{...}, sleep{sleeping,startedAt,wakeAt},
## grumpyUntil, lastTickAt, xp, level, coins, achievements.counters.sleeps.
## All transforms are PURE: they deep-duplicate and return new dicts.
## Parity proven against golden_values.json sleep.*.

const Stats := preload("res://scripts/logic/stats.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

## Lamp switch starts sleep only when energy < 70.
const START_BELOW_ENERGY := 70.0
## sleepDurationMin = ceil(30 * (100 - energy) / 100), minimum 10.
const DURATION_BASE_MIN := 30.0
const DURATION_MIN_MIN := 10
## Early manual wake allowed after this many minutes (0 = sofort kündbar).
const EARLY_WAKE_AFTER_MIN := 0
## Early wake grumpy debuff: mood -15 for 10 minutes.
const EARLY_WAKE_MOOD_DEBUFF := 15.0
const EARLY_WAKE_DEBUFF_MIN := 10
## REST-3 (additiv): Mittagsschlaf — kurzes festes Nickerchen, schon erlaubt,
## wenn Gooby nur ein bisschen muede ist (energy < 90). Die Web-Parity-
## Funktionen oben bleiben unveraendert.
const NAP_BELOW_ENERGY := 90.0
const NAP_MIN := 20
## REST-3: unterhalb dieser Energie wird Gooby SICHTBAR muede (Gaehnen,
## Augenringe, langsamerer Gang) — rein kosmetisch, nie eine Strafe.
const TIRED_VISIBLE_BELOW := 45.0


## Sleep duration in minutes for a given energy level (§C1.4).
static func sleep_duration_min(energy: float) -> int:
	var e := minf(Stats.MAX, maxf(Stats.MIN, energy))
	var raw := int(ceil(DURATION_BASE_MIN * (Stats.MAX - e) / Stats.MAX))
	return maxi(DURATION_MIN_MIN, raw)


## True while Gooby is asleep. Strict-bool read (schema `_is_true`-Semantik):
## Junk wie {"sleeping": 1} zaehlt als false — ein nackter `== true`-Vergleich
## loggt bei int/bool sonst einen Engine-SCRIPT-ERROR (BUGHUNT-Fund).
static func is_sleeping(state: Dictionary) -> bool:
	var sleep_slice: Variant = state.get("sleep")
	if sleep_slice is Dictionary:
		var sleeping: Variant = sleep_slice.get("sleeping", false)
		return sleeping is bool and sleeping
	return false


## Can Gooby fall asleep (§C1.4)? Only when awake and energy < 70.
static func can_sleep(state: Dictionary) -> bool:
	if is_sleeping(state):
		return false
	var stats: Variant = state.get("stats")
	if not (stats is Dictionary):
		return false
	return float(stats.get("energy", 0.0)) < START_BELOW_ENERGY


## Start a sleep: wakeAt = now + duration. Pure — returns a new state.
## Callers must check can_sleep() first (this does not).
static func start_sleep(state: Dictionary, now_ms: int) -> Dictionary:
	var dur_min := sleep_duration_min(float(state["stats"].get("energy", 0.0)))
	var s := state.duplicate(true)
	s["sleep"] = {"sleeping": true, "startedAt": now_ms, "wakeAt": now_ms + dur_min * 60000}
	return s


## REST-3: Ist ein Nickerchen erlaubt? Wach und nicht schon putzmunter.
static func can_nap(state: Dictionary) -> bool:
	if is_sleeping(state):
		return false
	var stats: Variant = state.get("stats")
	if not (stats is Dictionary):
		return false
	return float(stats.get("energy", 0.0)) < NAP_BELOW_ENERGY


## REST-3: Nickerchen starten — fester Kurzschlaf (hoechstens NAP_MIN, nie
## laenger als der volle Schlaf dauern wuerde). Pure — neuer State.
## Aufrufer pruefen can_nap() vorher (wie bei start_sleep/can_sleep).
static func start_nap(state: Dictionary, now_ms: int) -> Dictionary:
	var full := sleep_duration_min(float(state["stats"].get("energy", 0.0)))
	var dur_min := mini(NAP_MIN, full)
	var s := state.duplicate(true)
	s["sleep"] = {"sleeping": true, "startedAt": now_ms, "wakeAt": now_ms + dur_min * 60000}
	return s


## Is an early manual wake allowed? Nach EARLY_WAKE_AFTER_MIN Minuten Schlaf
## (0 = sofort, Grumpy-Debuff bleibt beim early-Pfad).
static func can_wake_early(state: Dictionary, now_ms: int) -> bool:
	if not is_sleeping(state):
		return false
	return now_ms - int(state["sleep"].get("startedAt", 0)) >= EARLY_WAKE_AFTER_MIN * 60000


## Milliseconds of sleep remaining (HUD countdown chip); 0 when awake.
static func sleep_remaining_ms(state: Dictionary, now_ms: int) -> int:
	if not is_sleeping(state):
		return 0
	return maxi(0, int(state["sleep"].get("wakeAt", 0)) - now_ms)


## Grants for a COMPLETED sleep (§C1.5): XP +10 (with level-up handling) and
## achievements.counters.sleeps += 1. Pure — returns a new state.
static func apply_completed_sleep_grants(state: Dictionary) -> Dictionary:
	var progress := Leveling.apply_xp(
		{"xp": state.get("xp", 0), "level": state.get("level", 1)}, Leveling.XP_COMPLETED_SLEEP
	)
	var s := state.duplicate(true)
	s["xp"] = progress["xp"]
	s["level"] = progress["level"]
	s["coins"] = int(_num(s.get("coins"))) + int(progress["coinsAwarded"])
	var achievements: Dictionary = s.get("achievements", {})
	var counters: Dictionary = achievements.get("counters", {})
	counters["sleeps"] = int(_num(counters.get("sleeps"))) + 1
	achievements["counters"] = counters
	s["achievements"] = achievements
	return s


## Wake Gooby up (§C1.4). Pure — returns {"state", "events"}.
## opts.early: grumpy debuff (grumpyUntil = now + 10 min), event 'wokeEarly'.
## Completed (default): XP +10 + sleeps counter, event 'wokeUp'.
static func wake_up(state: Dictionary, now_ms: int, opts: Dictionary = {}) -> Dictionary:
	var s := state.duplicate(true)
	s["sleep"] = {"sleeping": false, "startedAt": 0, "wakeAt": 0}
	if opts.get("early", false):
		s["grumpyUntil"] = now_ms + EARLY_WAKE_DEBUFF_MIN * 60000
		return {"state": s, "events": ["wokeEarly"]}
	s = apply_completed_sleep_grants(s)
	return {"state": s, "events": ["wokeUp"]}


## Pure asleep tick (§C1.4/§E4): asleep rates from lastTickAt for
## min(now, wakeAt), updates lastTickAt, auto-wakes (completed, with grants)
## at energy >= 100 or wakeAt. No-op when not sleeping.
static func tick_sleep(state: Dictionary, now_ms: int) -> Dictionary:
	if not is_sleeping(state):
		return {"state": state, "events": []}
	var from := _num(state.get("lastTickAt"))
	if from == 0.0:
		from = float(now_ms)
	var wake_at := _num(state["sleep"].get("wakeAt"))
	var until := minf(float(now_ms), wake_at)
	var dt_min := maxf(0.0, (until - from) / 60000.0)
	var s := state.duplicate(true)
	s["stats"] = Stats.apply_tick(state["stats"], dt_min, {"asleep": true})
	s["lastTickAt"] = now_ms
	if float(now_ms) >= wake_at or float(s["stats"]["energy"]) >= Stats.MAX:
		return wake_up(s, now_ms, {"early": false})
	return {"state": s, "events": []}


## Active grumpy mood debuff (§C1.4): 15 while now < grumpyUntil, else 0.
static func grumpy_debuff(state: Dictionary, now_ms: int) -> float:
	var until := _num(state.get("grumpyUntil"))
	return EARLY_WAKE_MOOD_DEBUFF if float(now_ms) < until else 0.0


## Canonical mood reader (§C1 + §C1.4): mood with the early-wake debuff.
static func current_mood(state: Dictionary, now_ms: int) -> float:
	return Stats.mood(state["stats"], {"debuff": grumpy_debuff(state, now_ms)})


# ── REST-3: v5-State-Helfer (fuers Bett-Interactable + Tests) ─────────────────


## Stufenlose Muedigkeit fuers Modell: 0.0 ab energy >= 45, 1.0 bei energy 0.
static func tiredness01(stats: Variant) -> float:
	if not (stats is Dictionary):
		return 0.0
	var energy := _num((stats as Dictionary).get("energy"))
	return clampf((TIRED_VISIBLE_BELOW - energy) / TIRED_VISIBLE_BELOW, 0.0, 1.0)


## Flache Web-Sicht auf den v5-gooby-Slice (Referenzen, nur zum LESEN der
## can_*-Prüfungen — Schreiber duplizieren über start_sleep/start_nap selbst).
static func flat_of(state: Dictionary) -> Dictionary:
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return {"stats": {}, "sleep": {}, "grumpyUntil": 0}
	return {
		"stats": gooby.get("stats", {}),
		"sleep": gooby.get("sleep", {}),
		"grumpyUntil": gooby.get("grumpyUntil", 0),
	}


## Schlaf (nap=false) oder Nickerchen (nap=true) direkt im v5-Save starten.
## Mutiert `state` in place (im gs.update laufen lassen); false, wenn die
## can_sleep-/can_nap-Regel es nicht erlaubt.
static func start_sleep_state(state: Dictionary, now_ms: int, nap := false) -> bool:
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return false
	var flat := flat_of(state)
	if not (flat["stats"] is Dictionary) or (flat["stats"] as Dictionary).is_empty():
		return false
	if nap:
		if not can_nap(flat):
			return false
		gooby["sleep"] = start_nap(flat, now_ms)["sleep"]
	else:
		if not can_sleep(flat):
			return false
		gooby["sleep"] = start_sleep(flat, now_ms)["sleep"]
	return true


## Fruehes (manuelles) Wecken im v5-Save: erlaubt nach EARLY_WAKE_AFTER_MIN
## (0 = sofort); setzt den Grumpy-Debuff (KEINE Grants — die gibt es nur
## fuer vollen Schlaf ueber den Ticker). Rueckgabe die Events ([] = nichts).
static func wake_early_state(state: Dictionary, now_ms: int) -> Array:
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return []
	var flat := flat_of(state)
	if not is_sleeping(flat) or not can_wake_early(flat, now_ms):
		return []
	var res := wake_up(flat, now_ms, {"early": true})
	gooby["sleep"] = res["state"]["sleep"]
	gooby["grumpyUntil"] = res["state"]["grumpyUntil"]
	return res["events"]


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
