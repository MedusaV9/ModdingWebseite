class_name GoobyTicker
extends RefCounted
## BUGHUNT-P1-Fix: Verdrahtung der puren Gooby-Lebenslogik in das v5-Schema.
##
## VORHER existierten `Offline.simulate_offline` (§E4), `Stats.apply_tick`
## (§C1) und `Sleep.tick_sleep` (§C1.4) nur als getestete, aber NIRGENDS
## aufgerufene Pur-Funktionen — sichtbare Folgen im Spiel: Hunger/Spaß/
## Hygiene sanken NIE (Tamagotchi-Kernloop tot), nach App-Neustart holte
## nichts die Offline-Zeit nach, und ein schlafender Gooby (importierter
## Save) schlief für immer weiter.
##
## Diese Klasse ist der EINE Adapter zwischen dem v5-Schema (gooby.stats /
## progression.xp / economy.coins / vacation) und der flachen Web-State-Form
## (stats/sleep/xp/level/coins auf oberster Ebene), auf der die Logik-Ports
## arbeiten. GameState ruft:
## - `catch_up()` beim Laden + bei NOTIFICATION_APPLICATION_RESUMED,
## - `live_tick()` alle paar Sekunden, solange die App offen ist.
## Beide mutieren `state` in place (innerhalb von GameState laufen lassen)
## und liefern die Web-Eventstrings ("wokeUp", "statLow:<stat>", ...).

const Offline := preload("res://scripts/logic/offline.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")
const Stats := preload("res://scripts/logic/stats.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const Health := preload("res://scripts/logic/health.gd")
const Weight := preload("res://scripts/logic/weight.gd")

## REST-3: Kaelte-Ausloeser (§Krankheit) — Gooby friert, wenn es draussen
## nass/schneit UND die Hygiene so niedrig ist, dass er klamm ist.
const CHILL_HYGIENE_BELOW := 40.0


## v5 → flache Web-Form (Referenzen; die Logik-Ports duplizieren selbst).
static func flat_view(state: Dictionary) -> Dictionary:
	var gooby := _dict(state.get("gooby"))
	var prog := _dict(state.get("progression"))
	var econ := _dict(state.get("economy"))
	return {
		"stats": _dict(gooby.get("stats")),
		"sleep": _dict(gooby.get("sleep")),
		"grumpyUntil": gooby.get("grumpyUntil", 0),
		"lastTickAt": gooby.get("lastTickAt", 0),
		"xp": prog.get("xp", 0),
		"level": prog.get("level", 1),
		"coins": econ.get("coins", 0),
		"vacation": _dict(state.get("vacation")),
		"achievements": _dict(state.get("achievements")),
	}


## Ergebnis der flachen Form zurück ins v5-Schema schreiben (in place).
static func write_back(state: Dictionary, flat: Dictionary) -> void:
	var gooby := _dict(state.get("gooby"))
	gooby["stats"] = _dict(flat.get("stats"))
	gooby["sleep"] = _dict(flat.get("sleep"))
	gooby["grumpyUntil"] = flat.get("grumpyUntil", 0)
	gooby["lastTickAt"] = flat.get("lastTickAt", 0)
	state["gooby"] = gooby
	var prog := _dict(state.get("progression"))
	prog["xp"] = flat.get("xp", 0)
	prog["level"] = flat.get("level", 1)
	state["progression"] = prog
	var econ := _dict(state.get("economy"))
	econ["coins"] = flat.get("coins", 0)
	state["economy"] = econ
	state["vacation"] = _dict(flat.get("vacation"))
	state["achievements"] = _dict(flat.get("achievements"))


## Offline-Zeit nachholen (§E4): Schlaf zu Ende schlafen (Grants genau
## einmal), wache Zeit mit 0,3× (Cap 480 min) verfallen, Urlaubs-Phasen
## aufholen. Liefert die Web-Events (wokeUp/statLow:*/vacation*).
## REST-3: danach ruecken Krankheit + Gewicht ueber dasselbe §E4-Fenster vor
## (0,3×, Cap 480 wache Minuten — der W2-Hook aus offline.gd, s. dort).
static func catch_up(state: Dictionary, now_ms: int) -> Array:
	var flat := flat_view(state)
	var last := _num(flat.get("lastTickAt"))
	var was_sleeping := Sleep.is_sleeping(flat)
	var wake_at := _num(_dict(flat.get("sleep")).get("wakeAt")) if was_sleeping else 0.0
	var was_away := Vacation.is_away(flat)
	var res := Offline.simulate_offline(flat, now_ms)
	write_back(state, res["state"])
	var events: Array = res["events"]
	if not was_away and last > 0.0 and float(now_ms) > last:
		var elapsed_ms := float(now_ms) - last
		var awake_ms := elapsed_ms
		if was_sleeping:
			awake_ms = elapsed_ms - maxf(0.0, minf(elapsed_ms, wake_at - last))
		var awake_min := minf(maxf(0.0, awake_ms) / 60000.0, Offline.AWAKE_CAP_MIN)
		if awake_min > 0.0:
			events.append_array(
				_advance_care(state, awake_min, Offline.AWAKE_RATE_MULT, now_ms, false)
			)
	return events


## Ein Live-Tick, solange die App offen ist: Schlaf tickt (inkl. Auto-Wecken
## mit Grants), sonst voller §C1-Verfall seit lastTickAt. Im Urlaub sind die
## Werte eingefroren; eine zurückgestellte Uhr setzt nur die Basislinie neu
## (nie negativer Verfall). Liefert Events (wokeUp/statLow:*).
## REST-3: Krankheit (Junk/Vernachlaessigung/Erschoepfung/Kaelte) und
## Gewichts-Drift ticken im selben Takt mit (becameQueasy/becameSick/
## recovered/tummyWarning-Events fuer die UI).
static func live_tick(state: Dictionary, now_ms: int) -> Array:
	var flat := flat_view(state)
	if Vacation.is_away(flat):
		flat["lastTickAt"] = now_ms
		write_back(state, flat)
		return []
	var last := _num(flat.get("lastTickAt"))
	var dt_min := maxf(0.0, (float(now_ms) - last) / 60000.0) if last > 0.0 else 0.0
	if Sleep.is_sleeping(flat):
		var res := Sleep.tick_sleep(flat, now_ms)
		write_back(state, res["state"])
		var sleep_events: Array = res["events"]
		if dt_min > 0.0:
			sleep_events.append_array(_advance_care(state, dt_min, 1.0, now_ms, true))
		return sleep_events
	if last <= 0.0 or float(now_ms) <= last:
		flat["lastTickAt"] = now_ms
		write_back(state, flat)
		return []
	var before: Dictionary = _dict(flat.get("stats")).duplicate()
	flat["stats"] = Stats.apply_tick(before, dt_min)
	# §C3.3: kraenklich verfaellt der Spass x1.25 (der Extra-Anteil hier).
	if Health.grade(_dict(state.get("gooby")).get("health")) > 0:
		var stats: Dictionary = flat["stats"]
		var extra := absf(float(Stats.RATES_AWAKE["fun"])) * (Health.QUEASY_FUN_DECAY_MULT - 1.0)
		stats["fun"] = Stats.clamp_stat(_num(stats.get("fun")) - extra * dt_min)
	flat["lastTickAt"] = now_ms
	write_back(state, flat)
	var events: Array = []
	for k in Stats.KEYS:
		var was := _num(before.get(k))
		if was >= Stats.LOW_STAT and float(flat["stats"][k]) < Stats.LOW_STAT:
			events.append("statLow:%s" % k)
	events.append_array(_advance_care(state, dt_min, 1.0, now_ms, false))
	return events


## REST-3: Krankheit + Gewicht um dt_min vorruecken (mult = Offline-Faktor).
## Mutiert state.gooby in place und liefert die Health-Eventstrings.
static func _advance_care(
	state: Dictionary, dt_min: float, mult: float, now_ms: int, asleep: bool
) -> Array:
	var gooby := _dict(state.get("gooby"))
	var stats := _dict(gooby.get("stats"))
	var opts := {
		"mult": mult,
		"now_ms": now_ms,
		"exhausted": not asleep and Stats.is_exhausted(stats),
		"chill": not asleep and _chill_active(stats, now_ms),
	}
	var res := Health.tick(gooby.get("health"), dt_min, Health.low_stat_count(stats), opts)
	gooby["health"] = res["h"]
	gooby["weight"] = Weight.tick(gooby.get("weight", Weight.DEFAULT), dt_min, mult)
	state["gooby"] = gooby
	return res["events"]


## Friert Gooby? Deterministisch pro Tag (SoulWetter): Regen/Schnee draussen
## UND klamme Hygiene. Nie eine Strafe — ein Bad macht den Druck sofort weg.
static func _chill_active(stats: Dictionary, now_ms: int) -> bool:
	if _num(stats.get("hygiene")) >= CHILL_HYGIENE_BELOW:
		return false
	var date := Time.get_datetime_dict_from_unix_time(int(now_ms / 1000.0))
	var datum := "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]
	var wetter := SoulWetter.zustand(datum, float(date["hour"]))
	return bool(wetter.get("regen", false)) or bool(wetter.get("schnee", false))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
