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
static func catch_up(state: Dictionary, now_ms: int) -> Array:
	var res := Offline.simulate_offline(flat_view(state), now_ms)
	write_back(state, res["state"])
	return res["events"]


## Ein Live-Tick, solange die App offen ist: Schlaf tickt (inkl. Auto-Wecken
## mit Grants), sonst voller §C1-Verfall seit lastTickAt. Im Urlaub sind die
## Werte eingefroren; eine zurückgestellte Uhr setzt nur die Basislinie neu
## (nie negativer Verfall). Liefert Events (wokeUp/statLow:*).
static func live_tick(state: Dictionary, now_ms: int) -> Array:
	var flat := flat_view(state)
	if Vacation.is_away(flat):
		flat["lastTickAt"] = now_ms
		write_back(state, flat)
		return []
	if Sleep.is_sleeping(flat):
		var res := Sleep.tick_sleep(flat, now_ms)
		write_back(state, res["state"])
		return res["events"]
	var last := _num(flat.get("lastTickAt"))
	if last <= 0.0 or float(now_ms) <= last:
		flat["lastTickAt"] = now_ms
		write_back(state, flat)
		return []
	var dt_min := (float(now_ms) - last) / 60000.0
	var before: Dictionary = _dict(flat.get("stats")).duplicate()
	flat["stats"] = Stats.apply_tick(before, dt_min)
	flat["lastTickAt"] = now_ms
	write_back(state, flat)
	var events: Array = []
	for k in Stats.KEYS:
		var was := _num(before.get(k))
		if was >= Stats.LOW_STAT and float(flat["stats"][k]) < Stats.LOW_STAT:
			events.append("statLow:%s" % k)
	return events


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
