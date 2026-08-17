class_name ParkState
extends RefCounted
## Funkelpark-Slice-Helfer (REST-4) — Port der puren Übergänge aus
## GOOBY/src/systems/themePark.js (recordVisit/recordNight/recordRide/
## recordCandy/recordHandsUp). Die NORMALISIERUNG des Slices besitzt
## save_schema.gd (`_clamp_park`, web sliceOf) — hier leben nur die
## Übergänge plus die GameState-Schreibhelfer (ein `gs.update` pro Buchung,
## danach `notify_slice_changed("park")`, damit die Sticker-Auswertung des
## RewardHub die Funkelpark-Seite sieht).

## Bekannte Fahrgeschäfte mit Zähler im Save (web PARK_RIDE_IDS verbatim).
const RIDE_IDS: Array[String] = ["coaster", "wheel"]
const MAX_COUNT := 99999

## Preise in Münzen (Godot-additiv: Web-Fahrten liefen über den Tagesausflug,
## hier zahlt man pro Fahrt an der Kasse — Kosten-Teil der Anforderung).
const PREIS := {"coaster": 15, "wheel": 10, "karussell": 5}
## Naschgassen-Stände (web parkDressing.PARK_STALLS + data/foods.js Preise).
const STALLS := [
	{"id": "cottonCandy", "preis": 12, "tint": Color("#F781B0")},
	{"id": "softServe", "preis": 18, "tint": Color("#9BD7E8")},
	{"id": "waffle", "preis": 20, "tint": Color("#F5C518")},
]
## Nacht-Band des Parks (Lichter an + nightVisit-Latch): ab 19 Uhr bis 6 Uhr.
const NACHT_AB := 19.0
const NACHT_BIS := 6.0


## Normalisierter Park-Slice (web sliceOf — Zähler geklemmt, Rides whitelisted).
static func slice_of(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("park")
	var d := {"visits": 0, "nightVisit": false, "rides": {}, "handsUp": 0, "candyBought": 0}
	for id in RIDE_IDS:
		d["rides"][id] = 0
	if not (raw is Dictionary):
		return d
	d["visits"] = _clamp_count(raw.get("visits"))
	d["nightVisit"] = raw.get("nightVisit") is bool and raw.get("nightVisit")
	var raw_rides: Dictionary = raw.get("rides") if raw.get("rides") is Dictionary else {}
	for id in RIDE_IDS:
		d["rides"][id] = _clamp_count(raw_rides.get(id))
	d["handsUp"] = _clamp_count(raw.get("handsUp"))
	d["candyBought"] = _clamp_count(raw.get("candyBought"))
	return d


## Ein Plaza-Besuch (web recordVisit): visits+1, night latcht nightVisit.
static func record_visit(slice: Variant, night := false) -> Dictionary:
	var s := slice_of({"park": slice})
	s["visits"] = _clamp_count(int(s["visits"]) + 1)
	if night:
		s["nightVisit"] = true
	return s


## nightVisit-Latch ohne neuen Besuch (Band kippt WÄHREND Gooby da steht).
static func record_night(slice: Variant) -> Dictionary:
	var s := slice_of({"park": slice})
	s["nightVisit"] = true
	return s


## Eine gefahrene Runde (web recordRide) — unbekannte Ids buchen nichts.
static func record_ride(slice: Variant, ride_id: String) -> Dictionary:
	var s := slice_of({"park": slice})
	if RIDE_IDS.has(ride_id):
		s["rides"][ride_id] = _clamp_count(int(s["rides"][ride_id]) + 1)
	return s


## Ein Naschgassen-Kauf (web recordCandy).
static func record_candy(slice: Variant) -> Dictionary:
	var s := slice_of({"park": slice})
	s["candyBought"] = _clamp_count(int(s["candyBought"]) + 1)
	return s


## Ein Hände-hoch-Moment aus der Achterbahn (web recordHandsUp).
static func record_hands_up(slice: Variant) -> Dictionary:
	var s := slice_of({"park": slice})
	s["handsUp"] = _clamp_count(int(s["handsUp"]) + 1)
	return s


## Liegt `stunde` (0..24) im Nacht-Band des Parks?
static func ist_nacht(stunde: float) -> bool:
	return stunde >= NACHT_AB or stunde < NACHT_BIS


## Übergang in den Spielstand schreiben (ein update + Slice-Notify).
## `transition` bekommt den aktuellen Slice und liefert den neuen.
static func schreibe(gs: Object, transition: Callable) -> void:
	if gs == null:
		return
	gs.update(func(state: Dictionary) -> void: state["park"] = transition.call(state.get("park")))
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("park")


static func _clamp_count(value: Variant) -> int:
	var n: float = 0.0
	if value is int or value is float:
		n = float(value)
	if is_nan(n) or is_inf(n):
		return 0
	return clampi(int(floor(n)), 0, MAX_COUNT)
