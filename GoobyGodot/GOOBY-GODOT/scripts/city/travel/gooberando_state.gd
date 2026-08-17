class_name GooberandoLogic
extends RefCounted
## GOOBERANDO-Liefer-Statemaschine (W3a CITY, Doc E §5, M1-Kern): PURE,
## Timestamps im Save (App-Neustart-fest). Geld/Inventar bewegt der AUFRUFER
## über die Rückgabewerte (Economy/Inventory, W1d).
##
## IDLE ─bestellen()→ BESTELLT (prep 120–300 s real, Dev-Key verkürzbar)
## BESTELLT ─tick(now≥fertig)→ VOR_DER_TUER (Klingel! Geduld 5 min)
## VOR_DER_TUER ─uebergabe()→ TRINKGELD (Essen ins Inventar, Prompt)
## VOR_DER_TUER ─tick(now>fertig+5 min)→ ABGESTELLT-Event → IDLE
##               (Tüte vor der Tür, voller Effekt, kein Trinkgeld-Moment)
## TRINKGELD ─trinkgeld(geben)→ IDLE (30 % Chance 2-h-Energie-Buff ×0,75)

## Liefergebühr auf den Gericht-Preis (Doc E §5.1).
const LIEFERGEBUEHR := 3
## Trinkgeld-Betrag (M1: fix 5 Münzen).
const TRINKGELD := 5
## Buff „Extra-Grinsen“: 30 % Chance, 2 h, Energie-Drain ×0,75.
const BUFF_CHANCE := 0.3
const BUFF_DAUER_MS := 2 * 3600 * 1000
const BUFF_DRAIN_FAKTOR := 0.75
## Zubereitung+Fahrt in REAL-Sekunden (Doc E §5.2: rand(120..300 s)).
const PREP_MIN_S := 120
const PREP_MAX_S := 300
## Geduld des Liefer-Goobys vor der Tür (s).
const GEDULD_S := 300
## „Trinkgeld schadet nie ;)“-Hinweis nach 3 Lieferungen ohne Trinkgeld.
const HINWEIS_NACH_OHNE := 3
## Notification-Id (NotificationService).
const NOTIF_DA := "gooberando.da"

const STATE_IDLE := "idle"
const STATE_BESTELLT := "bestellt"
const STATE_VOR_DER_TUER := "vorDerTuer"
const STATE_TRINKGELD := "trinkgeld"
const STATES: Array[String] = [STATE_IDLE, STATE_BESTELLT, STATE_VOR_DER_TUER, STATE_TRINKGELD]


static func default_slice() -> Dictionary:
	return {
		"state": STATE_IDLE,
		"bestelltAt": 0,
		"fertigAt": 0,
		"gerichtId": "",
		"gerichte": [],
		"restaurantId": "",
		"lieferungen": 0,
		"trinkgelder": 0,
		"ohneTrinkgeldFolge": 0,
		"hinweisGezeigt": false,
		"buffBis": 0,
	}


static func normalize_slice(raw: Variant) -> Dictionary:
	var d := default_slice()
	if not (raw is Dictionary):
		return d
	var state := str(raw.get("state", STATE_IDLE))
	return {
		"state": state if state in STATES else STATE_IDLE,
		"bestelltAt": maxi(0, int(raw.get("bestelltAt", 0))),
		"fertigAt": maxi(0, int(raw.get("fertigAt", 0))),
		"gerichtId": str(raw.get("gerichtId", "")),
		"gerichte": _gericht_ids(raw),
		"restaurantId": str(raw.get("restaurantId", "")),
		"lieferungen": maxi(0, int(raw.get("lieferungen", 0))),
		"trinkgelder": maxi(0, int(raw.get("trinkgelder", 0))),
		"ohneTrinkgeldFolge": maxi(0, int(raw.get("ohneTrinkgeldFolge", 0))),
		"hinweisGezeigt": bool(raw.get("hinweisGezeigt", false)),
		"buffBis": maxi(0, int(raw.get("buffBis", 0))),
	}


## Warenkorb-Ids aus rohen Save-Daten (W13B): Alt-Saves kennen nur
## `gerichtId` — dann wird daraus ein Ein-Gericht-Korb.
static func _gericht_ids(raw: Dictionary) -> Array:
	var ids: Array = []
	var roh: Variant = raw.get("gerichte", [])
	if roh is Array:
		for id: Variant in roh:
			if not str(id).is_empty():
				ids.append(str(id))
	if ids.is_empty() and not str(raw.get("gerichtId", "")).is_empty():
		ids.append(str(raw.get("gerichtId", "")))
	return ids


static func kann_bestellen(slice: Dictionary) -> bool:
	return str(slice.get("state", STATE_IDLE)) == STATE_IDLE


## Bestellen (Einzelgericht, W3a-Signatur): delegiert an den Warenkorb.
static func bestellen(
	slice: Dictionary, now_ms: int, prep_s: int, gericht: Dictionary, restaurant_id := ""
) -> Dictionary:
	return bestellen_korb(slice, now_ms, prep_s, [gericht], restaurant_id)


## Warenkorb bestellen (W13B, Doc E §5.1): gerichte = [{id, preis}, …],
## kosten = Summe der Preise + Liefergebühr 3. prep_s vom Aufrufer
## (Restaurant-Wartezeit + Fahrzeit bzw. Debug-Key `debug.gooberando_prep_s`).
static func bestellen_korb(
	slice: Dictionary, now_ms: int, prep_s: int, gerichte: Array, restaurant_id := ""
) -> Dictionary:
	if not kann_bestellen(slice) or gerichte.is_empty():
		return {"ok": false, "slice": slice, "kosten": 0, "notifications": []}
	var s := normalize_slice(slice)
	var fertig := now_ms + maxi(1, prep_s) * 1000
	var ids: Array = []
	var kosten := LIEFERGEBUEHR
	for gericht: Dictionary in gerichte:
		ids.append(str(gericht.get("id", "")))
		kosten += int(gericht.get("preis", 0))
	s["state"] = STATE_BESTELLT
	s["bestelltAt"] = now_ms
	s["fertigAt"] = fertig
	s["gerichtId"] = str(ids[0])
	s["gerichte"] = ids
	s["restaurantId"] = restaurant_id
	var notifications := [
		{"id": NOTIF_DA, "text_key": "travel.gooberando.notif_da", "at_ms": fertig}
	]
	return {"ok": true, "slice": s, "kosten": kosten, "notifications": notifications}


## Zeit-Tick (auch Recovery über App-Neustarts hinweg). Events:
## {typ:"vor_der_tuer"} / {typ:"abgestellt", gerichtId} — bei „abgestellt“
## landet das Essen TROTZDEM im Inventar (wir sind freundlich, Doc E §5.2).
static func tick(slice: Dictionary, now_ms: int) -> Dictionary:
	var s := normalize_slice(slice)
	var events: Array = []
	var fertig := int(s["fertigAt"])
	if str(s["state"]) == STATE_BESTELLT and now_ms >= fertig:
		s["state"] = STATE_VOR_DER_TUER
		events.append({"typ": "vor_der_tuer"})
	if str(s["state"]) == STATE_VOR_DER_TUER and now_ms > fertig + GEDULD_S * 1000:
		var gericht_id := str(s["gerichtId"])
		var ids: Array = (s["gerichte"] as Array).duplicate()
		s = _nach_lieferung(s, 0)
		events.append({"typ": "abgestellt", "gerichtId": gericht_id, "gerichte": ids})
	return {"slice": s, "events": events}


## Tür geöffnet → Übergabe: Essen ins Inventar (gerichtId/gerichte in der
## Rückgabe), danach wartet der TRINKGELD-Prompt.
static func uebergabe(slice: Dictionary, now_ms: int) -> Dictionary:
	var s: Dictionary = tick(slice, now_ms)["slice"]
	if str(s["state"]) != STATE_VOR_DER_TUER:
		return {"ok": false, "slice": s, "gerichtId": "", "gerichte": []}
	s["state"] = STATE_TRINKGELD
	return {
		"ok": true,
		"slice": s,
		"gerichtId": str(s["gerichtId"]),
		"gerichte": (s["gerichte"] as Array).duplicate(),
	}


## Trinkgeld-Entscheidung (roll 0..1 injizierbar für Tests). Rückgabe:
## {slice, kosten (5|0), buff (bool), hinweis (bool — „Trinkgeld schadet nie ;)“)}.
static func trinkgeld(slice: Dictionary, now_ms: int, geben: bool, roll: float) -> Dictionary:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_TRINKGELD:
		return {"slice": s, "kosten": 0, "buff": false, "hinweis": false}
	var buff := false
	if geben:
		s["trinkgelder"] = int(s["trinkgelder"]) + 1
		if roll < BUFF_CHANCE:
			buff = true
			s["buffBis"] = now_ms + BUFF_DAUER_MS
	var hinweis := false
	s = _nach_lieferung(s, -1 if geben else 1)
	var folge := int(s["ohneTrinkgeldFolge"])
	if not geben and folge >= HINWEIS_NACH_OHNE and not bool(s["hinweisGezeigt"]):
		s["hinweisGezeigt"] = true
		hinweis = true
	return {"slice": s, "kosten": TRINKGELD if geben else 0, "buff": buff, "hinweis": hinweis}


static func buff_aktiv(slice: Dictionary, now_ms: int) -> bool:
	return now_ms < int(normalize_slice(slice).get("buffBis", 0))


## Energie-Drain-Faktor fürs Stats-System: ×0,75 solange der Buff läuft.
static func energie_drain_faktor(slice: Dictionary, now_ms: int) -> float:
	return BUFF_DRAIN_FAKTOR if buff_aktiv(slice, now_ms) else 1.0


## Rest-Lieferzeit (s, 0 wenn nicht BESTELLT).
static func liefer_rest_s(slice: Dictionary, now_ms: int) -> int:
	var s := normalize_slice(slice)
	if str(s["state"]) != STATE_BESTELLT:
		return 0
	return maxi(0, ceili(float(int(s["fertigAt"]) - now_ms) / 1000.0))


## Lieferung abschließen: Zähler buchen, Bestellfelder räumen → IDLE.
## folge_delta: −1 = Trinkgeld gegeben (Folge-Zähler reset), +1 = bewusst
## keins, 0 = abgestellt (kein Trinkgeld-MOMENT — zählt nicht als „keins“).
static func _nach_lieferung(s: Dictionary, folge_delta: int) -> Dictionary:
	s["lieferungen"] = int(s["lieferungen"]) + 1
	if folge_delta < 0:
		s["ohneTrinkgeldFolge"] = 0
	elif folge_delta > 0:
		s["ohneTrinkgeldFolge"] = int(s["ohneTrinkgeldFolge"]) + 1
	s["state"] = STATE_IDLE
	s["bestelltAt"] = 0
	s["fertigAt"] = 0
	s["gerichtId"] = ""
	s["gerichte"] = []
	s["restaurantId"] = ""
	return s
