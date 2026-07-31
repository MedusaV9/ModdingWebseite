extends RefCounted
## Vacation/airport phase machine — port of GOOBY/src/systems/vacation.js
## (V5/VACATION, core paths). Pure slice math; used by offline.gd catch-up
## and by migration_v4.gd (interrupted-trip handling).
##
## REST-4 (EVAL Rang 15): the postcard ARCHIVE generator (web
## systems/postcards.js) is ported in scripts/ui/postkarten/
## postkarten_logic.gd (pure, cycle-free — it does NOT load this file);
## tick() now also brings the archive current (one shared processor for
## the live ticker and the offline catch-up, idempotent).

const PHASE_NONE := "none"
const PHASE_AWAY := "away"
const PHASE_RETURN_READY := "returnReady"
const PHASE_OVERDUE := "overdue"
const PHASES: Array[String] = [PHASE_NONE, PHASE_AWAY, PHASE_RETURN_READY, PHASE_OVERDUE]

## One vacation "day" in REAL ms.
const MS_PER_DAY := 86400000
## Pickup window after returnAt before the taxi is needed (24 h).
const PICKUP_WINDOW_MS := 86400000
## Taxi fee for an overdue pickup.
const TAXI_FEE := 60
## All four stats fill to this on the reunion.
const PICKUP_STAT_FILL := 100.0

## W13B/RAUMSTATION (Doc E §3.3): Erholungs-Boost — nach JEDER Abholung
## sinkt die Energie 48 REAL-Stunden lang 20 % langsamer (×0,8). Die
## Zahlen frieren HIER (Owning-Module, Doc E §3.3 „Zahlen im Owning-Module
## frieren“); reise_logic.abholen stempelt `erholtBis`, der Ticker liest
## `energie_drain_faktor()` (Verdrahtung: Request an den Ticker-Owner).
const ERHOLUNGS_BOOST_MS := 48 * 3_600_000
const ERHOLUNGS_DRAIN_FAKTOR := 0.8

## Catalog ids + prices (web data/vacations.js, frozen §E0.1-2 numbers).
## Prices are needed by migration_v4.gd (interrupted-trip refund).
const CATALOG := {
	"beach": {"price": 180, "days": 3, "souvenirCoins": 30},
	"meadowTrip": {"price": 220, "days": 3, "souvenirCoins": 40},
	"bigCity": {"price": 280, "days": 4, "souvenirCoins": 55},
	"space": {"price": 350, "days": 4, "souvenirCoins": 70},
	"harbor": {"price": 200, "days": 3, "souvenirCoins": 35},
	"spookGarden": {"price": 240, "days": 3, "souvenirCoins": 45},
	"bakery": {"price": 260, "days": 3, "souvenirCoins": 50},
	"nightSky": {"price": 300, "days": 4, "souvenirCoins": 60},
	"toyRoom": {"price": 320, "days": 4, "souvenirCoins": 65},
}


## The vacation save slice at its defaults (defensive factory).
static func default_slice() -> Dictionary:
	return {
		"phase": PHASE_NONE,
		"destId": "",
		"bookedAt": 0,
		"returnAt": 0,
		"pickupBy": 0,
		"postcards": 0,
		"trips": 0,
		"archive": [],
		"lastPostcardDayProcessed": 0,
		"visited": {},
		"erholtBis": 0,
		"weltengoobyAt": 0,
		"weltengoobyGefeiert": false,
	}


## Read the vacation slice off a save state, normalized through the factory
## (never mutates `state`; junk leaves fall back to the defaults).
static func slice_of(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("vacation")
	var d := default_slice()
	if not (raw is Dictionary):
		return d
	# `is String` zuerst: PHASES ist ein Array[String] — ein Nicht-String (z. B.
	# fehlendes phase → null) loggt sonst einen Engine-Error (typed-array find).
	var phase: Variant = raw.get("phase")
	return {
		"phase": phase if phase is String and phase in PHASES else d["phase"],
		"destId": raw.get("destId") if raw.get("destId") is String else "",
		"bookedAt": _num(raw.get("bookedAt")),
		"returnAt": _num(raw.get("returnAt")),
		"pickupBy": _num(raw.get("pickupBy")),
		"postcards": maxi(0, int(floor(_num(raw.get("postcards"))))),
		"trips": maxi(0, int(floor(_num(raw.get("trips"))))),
		"archive": raw.get("archive").duplicate(true) if raw.get("archive") is Array else [],
		"lastPostcardDayProcessed": maxi(0, int(floor(_num(raw.get("lastPostcardDayProcessed"))))),
		"visited": _normalize_visited(raw.get("visited")),
		# W13B: Urlaubs-Nutzen-Latches (additiv) — MÜSSEN hier durch die
		# Normalisierung, sonst würde die nächste Abholung sie wegwerfen.
		"erholtBis": maxi(0, int(_num(raw.get("erholtBis")))),
		"weltengoobyAt": maxi(0, int(_num(raw.get("weltengoobyAt")))),
		"weltengoobyGefeiert":
		raw.get("weltengoobyGefeiert") is bool and raw.get("weltengoobyGefeiert"),
	}


## Is Gooby physically NOT home right now (any active phase)?
static func is_away(state: Dictionary) -> bool:
	return slice_of(state)["phase"] != PHASE_NONE


## Derive the phase a booked slice SHOULD be in at now_ms (pure timestamp math).
static func phase_at(v: Dictionary, now_ms: int) -> String:
	if v.is_empty() or v.get("phase") == PHASE_NONE or not (_num(v.get("returnAt")) > 0.0):
		return PHASE_NONE
	if float(now_ms) < _num(v.get("returnAt")):
		return PHASE_AWAY
	if float(now_ms) < _num(v.get("pickupBy")):
		return PHASE_RETURN_READY
	return PHASE_OVERDUE


## Postcards due by now_ms: one per FULL day away, capped at days - 1 (the
## last day Gooby travels home instead of writing).
static func postcards_due(v: Dictionary, now_ms: int) -> int:
	var booked := _num(v.get("bookedAt"))
	var return_at := _num(v.get("returnAt"))
	if v.get("phase") == PHASE_NONE or not (booked > 0.0) or not (return_at > booked):
		return 0
	var total_days := int(round((return_at - booked) / MS_PER_DAY))
	var max_cards := maxi(0, total_days - 1)
	var full_days := int(floor((minf(float(now_ms), return_at) - booked) / MS_PER_DAY))
	return maxi(0, mini(full_days, max_cards))


## Countdown ms until the next milestone — away → returnAt, returnReady →
## pickupBy, overdue/none → 0.
static func remaining_ms(state: Dictionary, now_ms: int) -> int:
	var v := slice_of(state)
	if v["phase"] == PHASE_AWAY:
		return maxi(0, int(_num(v["returnAt"])) - now_ms)
	if v["phase"] == PHASE_RETURN_READY:
		return maxi(0, int(_num(v["pickupBy"])) - now_ms)
	return 0


## The pure engine tick (web tick() contract): returns
## {"changes": Dictionary|null, "events": Array} — changes only when something
## changed; idempotent across any gap (offline catch-up calls it once).
## Event dicts: {type:'postcard',destId,n} / {type:'returnReady',destId} /
## {type:'overdue',destId}. (Archive generation: W2 — see header.)
static func tick(state: Dictionary, now_ms: int) -> Dictionary:
	var base_present: bool = state.get("vacation") is Dictionary
	var v := slice_of(state)
	var events: Array = []
	var changed := not base_present
	if v["phase"] == PHASE_NONE:
		return {"changes": v if changed else null, "events": events}
	var due := postcards_due(v, now_ms)
	if due > int(v["postcards"]):
		for n in range(int(v["postcards"]) + 1, due + 1):
			events.append({"type": "postcard", "destId": v["destId"], "n": n})
		v["postcards"] = due
		changed = true
	# REST-4: Archiv-Karten nachziehen (postkarten_logic.gd, Web postcards.js).
	var karten := PostkartenLogic.process_postcards_up_to(v, now_ms)
	if (
		int(karten["added"]) > 0
		or int(karten["lastPostcardDayProcessed"]) != int(v["lastPostcardDayProcessed"])
	):
		v["archive"] = karten["archive"]
		v["lastPostcardDayProcessed"] = karten["lastPostcardDayProcessed"]
		changed = true
	var phase := phase_at(v, now_ms)
	if phase != v["phase"]:
		# Walk skipped stages so offline gaps still announce the airport wait
		# before the taxi call (event order: returnReady → overdue).
		if v["phase"] == PHASE_AWAY and phase != PHASE_AWAY:
			events.append({"type": "returnReady", "destId": v["destId"]})
		if phase == PHASE_OVERDUE:
			events.append({"type": "overdue", "destId": v["destId"]})
		v["phase"] = phase
		changed = true
	return {"changes": v if changed else null, "events": events}


## ------------------------------------------------- W13B Urlaubs-Nutzen


## Läuft der Erholungs-Boost (48 h nach Abholung) zum Zeitpunkt now_ms?
## Nimmt einen (normalisierten oder rohen) vacation-Slice.
static func erholungs_boost_aktiv(v: Dictionary, now_ms: int) -> bool:
	return _num(v.get("erholtBis")) > float(now_ms)


## Energie-Drain-Faktor fürs Stats-System: ×0,8 solange der Boost läuft,
## sonst 1,0 (Muster: gooberando_state.energie_drain_faktor). Zeit injiziert.
static func energie_drain_faktor(v: Dictionary, now_ms: int) -> float:
	return ERHOLUNGS_DRAIN_FAKTOR if erholungs_boost_aktiv(v, now_ms) else 1.0


## Hat der Spieler ALLE Katalog-Ziele besucht? (9/9 → Weltengooby-Titel.)
static func alle_ziele_besucht(v: Dictionary) -> bool:
	return _normalize_visited(v.get("visited")).size() >= CATALOG.size()


## Trägt der Spieler den Weltengooby-Titel? (Latch aus reise_logic.abholen.)
static func weltengooby(v: Dictionary) -> bool:
	return _num(v.get("weltengoobyAt")) > 0.0


## Whitelist-normalize a raw `visited` map: known catalog ids with a value of
## strictly true only (junk drops silently; naturally capped at 9 keys).
## `is bool` zuerst — `"ja" == true` ist in GDScript ein LAUFZEITFEHLER
## (E2-P0-Crash-Klasse; Web nutzt `=== true`).
static func _normalize_visited(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var out := {}
	for id: String in CATALOG.keys():
		var v: Variant = raw.get(id)
		if v is bool and v:
			out[id] = true
	return out


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
