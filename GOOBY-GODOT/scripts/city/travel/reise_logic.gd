class_name ReiseLogic
extends RefCounted
## Reise-Bestätigungs- und Rückkehr-Logik (W3a CITY, Doc E §3): PURE Helfer
## über dem W1d-vacation-Slice (scripts/logic/vacation.gd — Katalogpreise
## VERBATIM). Der Bestätigungs-Dialog zeigt Ziel/Preis/Dauer + WARNUNG
## („Gooby ist dann 3 Tage weg!“) + NUTZEN („Er bringt Souvenirs &
## Postkarten mit!“); bei Abholung fließen souvenirCoins + Postkarten-Flag.

const Vacation := preload("res://scripts/logic/vacation.gd")

## Ziel-Reihenfolge fürs Flughafen-UI (Katalog: Vacation.CATALOG).
const ZIELE: Array[String] = [
	"beach",
	"harbor",
	"meadowTrip",
	"spookGarden",
	"bakery",
	"bigCity",
	"nightSky",
	"toyRoom",
	"space",
]


## Infos für den Bestätigungs-Dialog. Rückgabe {} bei unbekanntem Ziel, sonst
## {ziel_id, preis, tage, souvenir_coins, kann_zahlen, name_key}.
static func bestaetigung(ziel_id: String, coins: int) -> Dictionary:
	var eintrag: Dictionary = Vacation.CATALOG.get(ziel_id, {})
	if eintrag.is_empty():
		return {}
	return {
		"ziel_id": ziel_id,
		"preis": int(eintrag["price"]),
		"tage": int(eintrag["days"]),
		"souvenir_coins": int(eintrag["souvenirCoins"]),
		"kann_zahlen": coins >= int(eintrag["price"]),
		"name_key": "travel.ziel.%s" % ziel_id,
	}


## Buchen: baut den neuen vacation-Slice (phase=away, Timestamps) auf Basis
## des BESTEHENDEN Slices (trips/archive/visited bleiben erhalten). Geld
## zieht der Aufrufer ab (kosten in der Rückgabe). ok=false wenn schon weg
## oder Ziel unbekannt.
static func buchen(vacation_slice: Dictionary, ziel_id: String, now_ms: int) -> Dictionary:
	var eintrag: Dictionary = Vacation.CATALOG.get(ziel_id, {})
	var v := Vacation.slice_of({"vacation": vacation_slice})
	if eintrag.is_empty() or str(v["phase"]) != Vacation.PHASE_NONE:
		return {"ok": false, "vacation": v, "kosten": 0}
	var return_at := now_ms + int(eintrag["days"]) * Vacation.MS_PER_DAY
	v["phase"] = Vacation.PHASE_AWAY
	v["destId"] = ziel_id
	v["bookedAt"] = now_ms
	v["returnAt"] = return_at
	v["pickupBy"] = return_at + Vacation.PICKUP_WINDOW_MS
	v["postcards"] = 0
	return {"ok": true, "vacation": v, "kosten": int(eintrag["price"])}


## Abholung/Rückkehr: souvenirCoins gutschreiben (Aufrufer), Postkarten als
## Flag/Archiv-Zähler, Ziel im Sammelpass, trips+1 → phase none.
## W13B (Doc E §3.3): dazu stempelt JEDE Abholung den Erholungs-Boost
## (`erholtBis` = now + 48 h) und latcht beim 9/9-Sammelpass den
## Weltengooby-Titel (`weltengoobyAt`, einmalig — nie zurückgesetzt).
## Rückgabe {ok, vacation, souvenir_coins, postkarten, ziel_id,
## weltengooby_neu}.
static func abholen(vacation_slice: Dictionary, now_ms: int) -> Dictionary:
	var v := Vacation.slice_of({"vacation": vacation_slice})
	var phase := Vacation.phase_at(v, now_ms)
	if phase != Vacation.PHASE_RETURN_READY and phase != Vacation.PHASE_OVERDUE:
		return {
			"ok": false,
			"vacation": v,
			"souvenir_coins": 0,
			"postkarten": 0,
			"ziel_id": "",
			"weltengooby_neu": false,
		}
	var ziel_id := str(v["destId"])
	var eintrag: Dictionary = Vacation.CATALOG.get(ziel_id, {})
	var postkarten := Vacation.postcards_due(v, now_ms)
	var visited: Dictionary = v["visited"]
	visited[ziel_id] = true
	# W19/MITBRINGSEL: Heimkehr-Latches VOR dem Nullen stempeln — Ziel +
	# Abflug-Timestamp sind der deterministische Mitbringsel-Seed, der
	# Abhol-Zeitpunkt öffnet das 24-h-GOOBY-FREE-Fenster (HeimkehrLogik).
	v["heimkehrZiel"] = ziel_id
	v["heimkehrAbflug"] = int(v["bookedAt"])
	v["heimkehrAt"] = now_ms
	v["heimkehrGefeiert"] = false
	v["phase"] = Vacation.PHASE_NONE
	v["destId"] = ""
	v["bookedAt"] = 0
	v["returnAt"] = 0
	v["pickupBy"] = 0
	v["postcards"] = 0
	v["trips"] = int(v["trips"]) + 1
	v["erholtBis"] = now_ms + Vacation.ERHOLUNGS_BOOST_MS
	var weltengooby_neu := false
	if int(v["weltengoobyAt"]) == 0 and Vacation.alle_ziele_besucht(v):
		v["weltengoobyAt"] = now_ms
		weltengooby_neu = true
	return {
		"ok": true,
		"vacation": v,
		"souvenir_coins": int(eintrag.get("souvenirCoins", 0)),
		"postkarten": postkarten,
		"ziel_id": ziel_id,
		"weltengooby_neu": weltengooby_neu,
	}
