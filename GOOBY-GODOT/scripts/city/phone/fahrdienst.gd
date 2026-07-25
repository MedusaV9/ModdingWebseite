class_name Fahrdienst
extends RefCounted
## Taxi vs. Guber (Doc E §4 + USER): BEIDE fahren auf derselben
## TaxiLogic-Statemaschine — sie unterscheiden sich nur in Wartezeit, Preis
## und Ton. Guber ist teuer und schnell und der Fahrer spricht, als hätte er
## Manschettenknöpfe. PURE: kein Node, kein UI.
##
## Weil es nur EINE Maschine gibt, kann auch nur EIN Wagen unterwegs sein.
## Welcher Dienst gerade fährt, steht additiv im city-Slice unter
## `fahrdienst` ("" = keiner) — deshalb sieht die Taxi-App eine Guber-Fahrt
## als „ein anderer Wagen ist schon unterwegs“ und umgekehrt.

const TAXI := "taxi"
const GUBER := "guber"
const SLICE_KEY := "city.fahrdienst"
## Gebühren, die bei Storno bzw. verpasstem Wagen einbehalten werden.
## Beim Taxi ergibt das exakt TaxiLogic.ERSTATTUNG_STORNO/_VERPASST.
const GEBUEHR_STORNO := 2
const GEBUEHR_VERPASST := 5
## Unter dieser Energie ist das Taxi der Rettungsweg (Doc E §4) und die
## Kachel im App-Grid wird hervorgehoben.
const RETTUNG_ENERGIE := 1.0

const DIENSTE := {
	TAXI:
	{
		"kosten": TaxiLogic.KOSTEN,
		"warte_min_s": TaxiLogic.WARTE_MIN_S,
		"warte_max_s": TaxiLogic.WARTE_MAX_S,
		"debug_key": "debug.taxi_warte_s",
	},
	GUBER:
	{
		"kosten": 25,
		"warte_min_s": 30,
		"warte_max_s": 90,
		"debug_key": "debug.guber_warte_s",
	},
}


static func def(dienst: String) -> Dictionary:
	var raw: Variant = DIENSTE.get(dienst, {})
	return (raw as Dictionary).duplicate() if raw is Dictionary else {}


static func kosten(dienst: String) -> int:
	return int(def(dienst).get("kosten", 0))


## Erstattung bei Storno (in GERUFEN) bzw. bei verpasstem Einstiegsfenster.
static func erstattung(dienst: String, verpasst: bool) -> int:
	var gebuehr := GEBUEHR_VERPASST if verpasst else GEBUEHR_STORNO
	return maxi(0, kosten(dienst) - gebuehr)


## Ist Gooby zu platt zum Fahren? Dann ist das Taxi der Rettungsweg.
static func ist_rettungsweg(gs: Object) -> bool:
	if gs == null:
		return false
	return float(gs.get_value("gooby.stats.energy", 100.0)) < RETTUNG_ENERGIE


## Welcher Dienst fährt gerade? ("" = keiner unterwegs.)
static func aktiver(gs: Object) -> String:
	if gs == null:
		return ""
	var slice := CityState.taxi_slice(gs)
	if str(slice["state"]) == TaxiLogic.STATE_IDLE:
		return ""
	var dienst := str(gs.get_value(SLICE_KEY, ""))
	return dienst if DIENSTE.has(dienst) else TAXI


## Blockiert ein ANDERER Dienst gerade die Maschine?
static func blockiert_durch(gs: Object, dienst: String) -> String:
	var laeuft := aktiver(gs)
	return laeuft if not laeuft.is_empty() and laeuft != dienst else ""


static func merke_dienst(gs: Object, dienst: String) -> void:
	if gs == null:
		return
	gs.set_value(SLICE_KEY, dienst)
	gs.notify_slice_changed(CityState.SLICE_ID)


## Wartezeit würfeln (Dev-Harness: `debug.<dienst>_warte_s` überschreibt).
static func warte_s(dienst: String, debug_wert: int, roll: float) -> int:
	if debug_wert > 0:
		return debug_wert
	var d := def(dienst)
	var min_s := int(d.get("warte_min_s", TaxiLogic.WARTE_MIN_S))
	var max_s := int(d.get("warte_max_s", TaxiLogic.WARTE_MAX_S))
	return min_s + int(clampf(roll, 0.0, 1.0) * float(maxi(0, max_s - min_s)))
