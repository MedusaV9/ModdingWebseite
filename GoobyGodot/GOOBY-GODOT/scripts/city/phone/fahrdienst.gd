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
## Tatsächlich bezahlter Preis der laufenden Fahrt (W13B): zu Stoßzeiten
## kostet Guber mehr — Storno/Verpasst erstatten vom BEZAHLTEN Preis.
const PREIS_KEY := "city.fahrdienstPreis"
## Gebühren, die bei Storno bzw. verpasstem Wagen einbehalten werden.
## Beim Taxi ergibt das exakt TaxiLogic.ERSTATTUNG_STORNO/_VERPASST.
const GEBUEHR_STORNO := 2
const GEBUEHR_VERPASST := 5
## Unter dieser Energie ist das Taxi der Rettungsweg (Doc E §4) und die
## Kachel im App-Grid wird hervorgehoben.
const RETTUNG_ENERGIE := 1.0
## Guber-Surge-Gag (W13B, Doc E §4): zu Stoßzeiten 18–20 Uhr Lokalzeit
## kostet der Wagen 45 statt 30 — mit vornehm-entschuldigendem Spruch.
const GUBER_SURGE_VON_H := 18.0
const GUBER_SURGE_BIS_H := 20.0
const GUBER_SURGE_KOSTEN := 45

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
		# Doc E §4: Guber kostet 30 Münzen (W13B: 25 → 30, Doc-Parität).
		"kosten": 30,
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


## Stoßzeit für den Guber-Surge (18–20 Uhr Lokalzeit, Zeit injizierbar).
static func ist_stosszeit(stunde: float) -> bool:
	return stunde >= GUBER_SURGE_VON_H and stunde < GUBER_SURGE_BIS_H


## Preis zur Stunde: nur Guber kennt den Surge — das Taxi bleibt ehrlich.
static func kosten_zur_stunde(dienst: String, stunde: float) -> int:
	if dienst == GUBER and ist_stosszeit(stunde):
		return GUBER_SURGE_KOSTEN
	return kosten(dienst)


## Erstattung bei Storno (in GERUFEN) bzw. bei verpasstem Einstiegsfenster.
static func erstattung(dienst: String, verpasst: bool) -> int:
	return erstattung_fuer(kosten(dienst), verpasst)


## Erstattung vom TATSÄCHLICH bezahlten Preis (W13B: Surge-Fahrten
## erstatten 45−Gebühr, nicht 30−Gebühr).
static func erstattung_fuer(preis: int, verpasst: bool) -> int:
	var gebuehr := GEBUEHR_VERPASST if verpasst else GEBUEHR_STORNO
	return maxi(0, preis - gebuehr)


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
	if dienst.is_empty():
		gs.set_value(PREIS_KEY, 0)
	gs.notify_slice_changed(CityState.SLICE_ID)


## Bezahlten Preis der laufenden Fahrt merken (beim Rufen).
static func merke_preis(gs: Object, preis: int) -> void:
	if gs == null:
		return
	gs.set_value(PREIS_KEY, preis)
	gs.notify_slice_changed(CityState.SLICE_ID)


## Tatsächlich bezahlter Preis der laufenden Fahrt (Fallback: Basispreis —
## Alt-Saves ohne PREIS_KEY erstatten wie bisher).
static func bezahlter_preis(gs: Object, dienst: String) -> int:
	if gs == null:
		return kosten(dienst)
	var preis := int(gs.get_value(PREIS_KEY, 0))
	return preis if preis > 0 else kosten(dienst)


## Wartezeit würfeln (Dev-Harness: `debug.<dienst>_warte_s` überschreibt).
static func warte_s(dienst: String, debug_wert: int, roll: float) -> int:
	if debug_wert > 0:
		return debug_wert
	var d := def(dienst)
	var min_s := int(d.get("warte_min_s", TaxiLogic.WARTE_MIN_S))
	var max_s := int(d.get("warte_max_s", TaxiLogic.WARTE_MAX_S))
	return min_s + int(clampf(roll, 0.0, 1.0) * float(maxi(0, max_s - min_s)))
