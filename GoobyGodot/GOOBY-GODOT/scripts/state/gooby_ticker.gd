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
			# W13B (Doc E §3.3): Erholungs-Boost auch offline — der wache
			# Anteil beginnt nach dem Aufwachen (sonst an der Basislinie).
			var awake_start := clampf(wake_at, last, float(now_ms)) if was_sleeping else last
			_erholungs_boost_offline(state, awake_start, awake_min, now_ms)
	# FERTIG-1 (EVAL Rang 12): Modifier-Scheduler holt Offline-Zeit nach
	# (ein verpasstes nextAt startet das Event JETZT — Web-§C-SYS4.1).
	events.append_array(_tick_modifiers(state, now_ms))
	return events


## Ein Live-Tick, solange die App offen ist: Schlaf tickt (inkl. Auto-Wecken
## mit Grants), sonst voller §C1-Verfall seit lastTickAt. Im Urlaub sind die
## Werte eingefroren; eine zurückgestellte Uhr setzt nur die Basislinie neu
## (nie negativer Verfall). Liefert Events (wokeUp/statLow:*).
## REST-3: Krankheit (Junk/Vernachlaessigung/Erschoepfung/Kaelte) und
## Gewichts-Drift ticken im selben Takt mit (becameQueasy/becameSick/
## recovered/tummyWarning-Events fuer die UI).
## FERTIG-1 (EVAL Rang 12): der Modifier-Scheduler tickt im selben Takt —
## auch waehrend Schlaf/Urlaub (der Kern hat Early-Returns, deshalb der
## Wrapper), damit ein faelliges Event nie am Zustand des Goobys haengt.
static func live_tick(state: Dictionary, now_ms: int) -> Array:
	var events := _live_tick_core(state, now_ms)
	events.append_array(_tick_modifiers(state, now_ms))
	return events


static func _live_tick_core(state: Dictionary, now_ms: int) -> Array:
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
	# W13B (Doc E §3.3): Erholungs-Boost — Energie sinkt 48 h nach der
	# Urlaubs-Abholung 20 % langsamer (Vacation.erholtBis, zeitinjiziert).
	var drain_faktor := Vacation.energie_drain_faktor(_dict(state.get("vacation")), now_ms)
	if drain_faktor < 1.0:
		var boost_stats: Dictionary = flat["stats"]
		var zurueck := absf(float(Stats.RATES_AWAKE["energy"])) * (1.0 - drain_faktor) * dt_min
		boost_stats["energy"] = Stats.clamp_stat(_num(boost_stats.get("energy")) + zurueck)
	flat["lastTickAt"] = now_ms
	write_back(state, flat)
	var events: Array = []
	for k in Stats.KEYS:
		var was := _num(before.get(k))
		if was >= Stats.LOW_STAT and float(flat["stats"][k]) < Stats.LOW_STAT:
			events.append("statLow:%s" % k)
	events.append_array(_advance_care(state, dt_min, 1.0, now_ms, false))
	return events


## FERTIG-1 (EVAL Rang 12): ein Modifier-Scheduler-Tick (Web §B4) — weist
## die Engine-Aenderungen dem Slice zu und meldet den Start als Eventstring
## "modifierStarted:<gameId>:<typ>" (RewardHub macht daraus den Toast).
static func _tick_modifiers(state: Dictionary, now_ms: int) -> Array:
	var res := ModifierEngine.tick(state, now_ms)
	if res["changes"] != null:
		state["modifiers"] = res["changes"]
	if str(res["event"]) == "started":
		var cur := _dict(_dict(state.get("modifiers")).get("current"))
		return ["modifierStarted:%s:%s" % [cur.get("gameId", ""), cur.get("type", "")]]
	return []


## W13B (Doc E §3.3): Erholungs-Boost im Offline-Fenster — gibt der Energie
## den zu viel verfallenen Anteil zurueck. Zaehlt NUR den Ueberlapp von
## Boost-Fenster [.., vacation.erholtBis] und wacher Offline-Zeit, gedeckelt
## auf die tatsaechlich simulierten Minuten (§E4-Cap), mit derselben
## ×0,3-Offline-Rate. Der golden-parity Port offline.gd bleibt bewusst
## unangetastet — die Verdrahtung lebt wie beim Live-Tick HIER im Adapter.
static func _erholungs_boost_offline(
	state: Dictionary, awake_start: float, awake_min: float, now_ms: int
) -> void:
	var erholt_bis := _num(_dict(state.get("vacation")).get("erholtBis"))
	var boost_min := minf((minf(float(now_ms), erholt_bis) - awake_start) / 60000.0, awake_min)
	if boost_min <= 0.0:
		return
	var stats := _dict(_dict(state.get("gooby")).get("stats"))
	var zurueck := (
		absf(float(Stats.RATES_AWAKE["energy"]))
		* (1.0 - Vacation.ERHOLUNGS_DRAIN_FAKTOR)
		* Offline.AWAKE_RATE_MULT
		* boost_min
	)
	stats["energy"] = Stats.clamp_stat(_num(stats.get("energy")) + zurueck)


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
	# LOKALER Kalendertag/Stunde wie RanchWetter.datum_heute() (Systemuhr) —
	# UTC verschob den SoulWetter-Tag z. B. für DE (UTC+1/+2) jeden Abend.
	var bias_min := int(Time.get_time_zone_from_system()["bias"])
	var date := local_datetime(now_ms, bias_min)
	var datum := "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]
	var wetter := SoulWetter.zustand(datum, float(date["hour"]))
	return bool(wetter.get("regen", false)) or bool(wetter.get("schnee", false))


## Kalender-Dict zum Unix-Zeitstempel in LOKALER Zeit (bias = Zeitzonen-
## Offset in Minuten wie Time.get_time_zone_from_system().bias) — pur,
## damit Tests den Offset injizieren können (AGENTS-Regel: Zeit injizieren).
static func local_datetime(now_ms: int, bias_min: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(now_ms / 1000.0) + bias_min * 60)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
