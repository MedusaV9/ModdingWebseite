class_name TaxiLogic
extends RefCounted
## Taxi-Warte-Loop-Statemaschine (W3a CITY, Doc E §4 + User-Wunsch): PURE,
## Zeit als TIMESTAMPS im Save (nie Countdown-Reste) — App-Kill/Neustart ist
## selbstheilend (Muster vacation.js sliceOf). Geld bewegt der AUFRUFER über
## die zurückgegebenen kosten/erstattung-Werte (Economy, W1d).
##
## IDLE ─rufen()→ GERUFEN (warte 300–600 s real, Dev-Key verkürzbar)
## GERUFEN ─tick(now≥ankunft)→ WARTET (60-s-Fenster)
## WARTET ─einsteigen()→ FAHRT (Cutscene; Aufrufer setzt danach abgeschlossen())
## WARTET ─tick(now>ankunft+60 s)→ VERPASST-Event → IDLE (5 von 10 Münzen weg)
## GERUFEN ─storno()→ IDLE (2 Münzen Gebühr, 8 zurück)

## Wartezeit-Spanne in REAL-Sekunden (Doc E §4: rand(300..600 s)).
const WARTE_MIN_S := 300
const WARTE_MAX_S := 600
## Einstiegsfenster nach Taxi-Ankunft (s).
const FENSTER_S := 60
## Kosten: 10 Münzen beim Rufen; verpasst = 5 zurück (5 Gebühr);
## Storno in GERUFEN = 8 zurück (2 Gebühr).
const KOSTEN := 10
const ERSTATTUNG_VERPASST := 5
const ERSTATTUNG_STORNO := 8
## Notification-Vorlauf „gleich da“ (s vor Ankunft).
const VORLAUF_S := 15
## Notification-Ids (NotificationService; storniere_gruppe("taxi.")).
const NOTIF_GLEICH_DA := "taxi.gleich_da"
const NOTIF_DA := "taxi.da"
const NOTIF_WEG := "taxi.weg"

const STATE_IDLE := "idle"
const STATE_GERUFEN := "gerufen"
const STATE_WARTET := "wartet"
const STATE_FAHRT := "fahrt"
const STATES: Array[String] = [STATE_IDLE, STATE_GERUFEN, STATE_WARTET, STATE_FAHRT]


static func default_slice() -> Dictionary:
	return {
		"state": STATE_IDLE,
		"gerufenAt": 0,
		"ankunftAt": 0,
		"zielId": "",
	}


static func normalize_slice(raw: Variant) -> Dictionary:
	var d := default_slice()
	if not (raw is Dictionary):
		return d
	var state := str(raw.get("state", STATE_IDLE))
	return {
		"state": state if state in STATES else STATE_IDLE,
		"gerufenAt": maxi(0, int(raw.get("gerufenAt", 0))),
		"ankunftAt": maxi(0, int(raw.get("ankunftAt", 0))),
		"zielId": str(raw.get("zielId", "")),
	}


static func kann_rufen(slice: Dictionary) -> bool:
	return str(slice.get("state", STATE_IDLE)) == STATE_IDLE


## Taxi rufen: warte_s kommt vom Aufrufer (rand 300–600 s bzw. Debug-Key
## `debug.taxi_warte_s` aus AppSettings — Dev-Harness). Rückgabe:
## {ok, slice, kosten, notifications:[{id, text_key, at_ms}]}.
static func rufen(
	slice: Dictionary, now_ms: int, warte_s: int, ziel_id := "flughafen"
) -> Dictionary:
	if not kann_rufen(slice):
		return {"ok": false, "slice": slice, "kosten": 0, "notifications": []}
	var ankunft := now_ms + maxi(1, warte_s) * 1000
	var neu := {
		"state": STATE_GERUFEN,
		"gerufenAt": now_ms,
		"ankunftAt": ankunft,
		"zielId": ziel_id,
	}
	var notifications := [
		{
			"id": NOTIF_GLEICH_DA,
			"text_key": "travel.taxi.notif_gleich_da",
			"at_ms": ankunft - VORLAUF_S * 1000
		},
		{"id": NOTIF_DA, "text_key": "travel.taxi.notif_da", "at_ms": ankunft},
		{"id": NOTIF_WEG, "text_key": "travel.taxi.notif_weg", "at_ms": ankunft + FENSTER_S * 1000},
	]
	return {"ok": true, "slice": neu, "kosten": KOSTEN, "notifications": notifications}


## Zeit-Tick (auch App-Start-Recovery: übersprungene Phasen werden still
## abgewickelt). Rückgabe {slice, events:[{typ:"wartet"|"verpasst", ...}]}.
static func tick(slice: Dictionary, now_ms: int) -> Dictionary:
	var s := normalize_slice(slice)
	var events: Array = []
	var state := str(s["state"])
	var ankunft := int(s["ankunftAt"])
	if state == STATE_GERUFEN and now_ms >= ankunft:
		s["state"] = STATE_WARTET
		state = STATE_WARTET
		events.append({"typ": "wartet"})
	if state == STATE_WARTET and now_ms > ankunft + FENSTER_S * 1000:
		s = default_slice()
		events.append({"typ": "verpasst", "erstattung": ERSTATTUNG_VERPASST})
	return {"slice": s, "events": events}


## Einsteigen — nur in WARTET innerhalb des Fensters gültig → FAHRT.
static func einsteigen(slice: Dictionary, now_ms: int) -> Dictionary:
	var s := normalize_slice(slice)
	var im_fenster := now_ms <= int(s["ankunftAt"]) + FENSTER_S * 1000
	if str(s["state"]) != STATE_WARTET or not im_fenster:
		return {"ok": false, "slice": s}
	s["state"] = STATE_FAHRT
	return {"ok": true, "slice": s}


## Storno — nur in GERUFEN. Rückgabe enthält die Erstattung (8 von 10).
static func storno(slice: Dictionary) -> Dictionary:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_GERUFEN:
		return {"ok": false, "slice": s, "erstattung": 0}
	return {"ok": true, "slice": default_slice(), "erstattung": ERSTATTUNG_STORNO}


## Fahrt beendet (Cutscene vorbei) → IDLE.
static func abgeschlossen(slice: Dictionary) -> Dictionary:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_FAHRT:
		return s
	return default_slice()


## Rest-Wartezeit bis Taxi-Ankunft (s, 0 wenn nicht GERUFEN).
static func warte_rest_s(slice: Dictionary, now_ms: int) -> int:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_GERUFEN:
		return 0
	return maxi(0, ceili(float(int(s["ankunftAt"]) - now_ms) / 1000.0))


## Rest des 60-s-Einstiegsfensters (s, 0 wenn nicht WARTET).
static func fenster_rest_s(slice: Dictionary, now_ms: int) -> int:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_WARTET:
		return 0
	return maxi(0, ceili(float(int(s["ankunftAt"]) + FENSTER_S * 1000 - now_ms) / 1000.0))
