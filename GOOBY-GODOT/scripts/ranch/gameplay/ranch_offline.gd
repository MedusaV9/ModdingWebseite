class_name RanchOffline
extends RefCounted
## Tagesrhythmus + Offline-Verfall der Ranch-Pferde (RANCH-2) — PURE,
## nach dem Vorbild von scripts/logic/offline.gd (§E4): Weide-Verfall läuft
## offline mit 0.3× und ist auf 480 Sim-Minuten gedeckelt, Stall-Nächte
## laufen voll durch (wie der Web-Schlaf). Nichts hier doppelt das
## Gooby-Offline-System — es simuliert NUR den `ranch.tiere`-Unterschlüssel.
##
## Tagesrhythmus: Pferde schlafen 21–7 Uhr im Stall, tagsüber Weide.
## RANCH-1s Welt fragt wohin(stunde) für die Aufstellung.

const Care := preload("res://scripts/ranch/gameplay/horse_care.gd")

## Nacht = Stallzeit [NACHT_AB, 24) ∪ [0, MORGEN_AB).
const NACHT_AB := 21
const MORGEN_AB := 7

## Offline-Weide-Verfall: 0.3× der Wach-Raten, gedeckelt auf 8 h Sim-Zeit.
const WEIDE_RATE_MULT := 0.3
const WEIDE_CAP_MIN := 480.0
## Simulationsfenster: älter als 7 Tage wird nicht weiter gerechnet.
const ELAPSED_CAP_MS := 7 * 86400000


## True in der Stall-/Schlafenszeit (Stunde 0..24, Bruchteile erlaubt).
static func ist_nacht(stunde: float) -> bool:
	var h := fposmod(stunde, 24.0)
	return h >= float(NACHT_AB) or h < float(MORGEN_AB)


## Aufstellungs-Hinweis für die Welt: "stall" nachts, sonst "weide".
static func wohin(stunde: float) -> String:
	return "stall" if ist_nacht(stunde) else "weide"


## Lokale Stunde (0..24, float) zu einem Epoch-ms-Stempel.
## offset_min = UTC-Offset in Minuten (Tests pinnen 0, Muster clock.gd).
static func stunde_lokal(ms: int, offset_min: int = 0) -> float:
	var local_secs := int(floor(ms / 1000.0)) + offset_min * 60
	var day_secs := posmod(local_secs, 86400)
	return float(day_secs) / 3600.0


## Millisekunden bis zum nächsten Phasenwechsel (7:00 oder 21:00).
static func ms_bis_phasenwechsel(ms: int, offset_min: int = 0) -> int:
	var h := stunde_lokal(ms, offset_min)
	var ziel := float(MORGEN_AB) if ist_nacht(h) else float(NACHT_AB)
	var delta_h := fposmod(ziel - h, 24.0)
	if delta_h <= 0.0:
		delta_h = 24.0
	return int(ceil(delta_h * 3600000.0))


## Die Zeit simulieren, in der die App zu war. Pure — liefert
## {"tiere": Dictionary (neu), "events": Array[String]}.
## opts: {"offsetMin": int, "sauberkeitMult": float (Weidezaun)}.
static func simulate_offline(tiere: Dictionary, now_ms: int, opts: Dictionary = {}) -> Dictionary:
	var events: Array = []
	var t := tiere.duplicate(true)
	var last := int(_num(t.get("lastTickAt"), 0.0))
	if last <= 0:
		t["lastTickAt"] = now_ms
		return {"tiere": t, "events": events}
	var elapsed := now_ms - last
	if elapsed <= 0:
		t["lastTickAt"] = now_ms
		return {"tiere": t, "events": events}
	elapsed = mini(elapsed, ELAPSED_CAP_MS)
	var start := now_ms - elapsed

	var offset_min := int(_num(opts.get("offsetMin"), 0.0))
	var weide_mult := _num(opts.get("sauberkeitMult"), 1.0)
	var pferde: Dictionary = t.get("pferde") if t.get("pferde") is Dictionary else {}
	var vorher := {}
	for id: Variant in pferde.keys():
		vorher[id] = (pferde[id]["werte"] as Dictionary).duplicate()
	var stall_vorher := _num(t["stall"].get("sauberkeit"), 100.0)

	var cursor := start
	var weide_budget_min := WEIDE_CAP_MIN
	var guard := 0
	while cursor < now_ms and guard < 64:
		guard += 1
		var segment_ende := mini(now_ms, cursor + ms_bis_phasenwechsel(cursor, offset_min))
		var seg_min := float(segment_ende - cursor) / 60000.0
		var nachts := ist_nacht(stunde_lokal(cursor, offset_min))
		if nachts:
			_tick_nacht(t, pferde, seg_min)
		else:
			var sim_min := minf(seg_min, weide_budget_min)
			weide_budget_min -= sim_min
			if sim_min > 0.0:
				_tick_weide(pferde, sim_min, weide_mult)
		cursor = segment_ende

	_bond_verfall(pferde, start, now_ms)
	t["lastTickAt"] = now_ms

	_append_wert_events(events, vorher, pferde)
	if stall_vorher >= Care.STALL_DRECKIG_UNTER:
		if _num(t["stall"].get("sauberkeit"), 100.0) < Care.STALL_DRECKIG_UNTER:
			events.append("stallDreckig")
	return {"tiere": t, "events": events}


static func _tick_nacht(t: Dictionary, pferde: Dictionary, seg_min: float) -> void:
	var stall := _num(t["stall"].get("sauberkeit"), 100.0)
	for id: Variant in pferde.keys():
		pferde[id]["werte"] = Care.tick(
			pferde[id]["werte"], seg_min, {"schlaeft": true, "stallSauberkeit": stall}
		)
	t["stall"]["sauberkeit"] = Care.stall_tick(stall, seg_min, pferde.size())


static func _tick_weide(pferde: Dictionary, sim_min: float, weide_mult: float) -> void:
	for id: Variant in pferde.keys():
		pferde[id]["werte"] = Care.tick(
			pferde[id]["werte"],
			sim_min,
			{"rateMult": WEIDE_RATE_MULT, "sauberkeitMult": weide_mult}
		)


static func _bond_verfall(pferde: Dictionary, start: int, now_ms: int) -> void:
	var dt_min := float(now_ms - start) / 60000.0
	for id: Variant in pferde.keys():
		var pflege_at := int(_num(pferde[id].get("letztePflegeAt"), 0.0))
		var seit_min := 0.0
		if pflege_at > 0:
			seit_min = maxf(0.0, float(start - pflege_at) / 60000.0)
		pferde[id]["bindung"] = Care.bond_verfall(
			_num(pferde[id].get("bindung"), 0.0), seit_min, dt_min
		)


## "hungrig:<id>"/"durstig:<id>"/"stinkig:<id>" für jeden Wert, der WÄHREND
## der Simulation unter 25 gerutscht ist (schon niedrige bleiben still) —
## deterministische Reihenfolge: Wert-Reihenfolge, dann Pferd-Id sortiert.
static func _append_wert_events(events: Array, vorher: Dictionary, pferde: Dictionary) -> void:
	var namen := {"hunger": "hungrig", "durst": "durstig", "sauberkeit": "stinkig"}
	var ids := pferde.keys()
	ids.sort()
	for k: String in Care.KEYS:
		for id: Variant in ids:
			var davor := _num((vorher[id] as Dictionary).get(k), 0.0)
			var danach := _num((pferde[id]["werte"] as Dictionary).get(k), 0.0)
			if davor >= Care.NIEDRIG and danach < Care.NIEDRIG:
				events.append("%s:%s" % [namen[k], id])


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
