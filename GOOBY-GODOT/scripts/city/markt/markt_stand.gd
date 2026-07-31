class_name MarktStand
extends RefCounted
## W15/MARKT — Zustand des EIGENEN Marktstands (Doc D §6.3): Bestücken vor
## Marktbeginn, Preis-Slider je Ware (±50 % um den Basiswert), fester
## Markttag, Abrechnung. Alle Funktionen static; `gs` = Duck-Typing wie
## überall (GameState oder Test-Fake).
##
## Save (city-Slice, additiv — CityState.normalize_slice erhält fremde Keys
## VERBATIM, dieser Helfer heilt seinen Unterbaum selbst):
##   city.marktstand = {"tag": "YYYY-MM-DD", "slots": [{ware, menge, faktor}]}
##
## Lebenszyklus: LEER → (bestuecke bindet den nächsten Markttag) WARTET →
## LAEUFT (Samstag im Marktfenster) → FERTIG. `abholen()` bucht Erlös +
## Rückläufer und leert den Stand; Zuschauen ist nur ein Replay derselben
## deterministischen Sim (MarktSim) und ändert NICHTS am Ergebnis.

const SLICE_KEY := "city.marktstand"
const SLOT_MAX := 8
const FAKTOR_MIN := 0.5
const FAKTOR_MAX := 1.5
const SAMSTAG := 6

const Economy := preload("res://scripts/logic/economy.gd")

## Stand-Zustände (stabile Strings für UI/Tests).
const STATUS_LEER := "leer"
const STATUS_WARTET := "wartet"
const STATUS_LAEUFT := "laeuft"
const STATUS_FERTIG := "fertig"


## Marktfenster {von, bis} aus der Öffnungsregel der Karte (Quelle der
## Wahrheit: city_map.json via OrtKatalog) — Fallback Samstag 8–14 Uhr.
static func marktfenster() -> Dictionary:
	var regel := OrtKatalog.oeffnung("wochenmarkt")
	return {
		"von": int(regel.get("von_stunde", 8)),
		"bis": int(regel.get("bis_stunde", 14)),
	}


## Geheilter Stand-Slice ({tag, slots}) — nie null, nie falsche Typen.
static func slice_von(gs: Object) -> Dictionary:
	if gs == null:
		return {"tag": "", "slots": []}
	var raw: Variant = gs.get_value(SLICE_KEY, {})
	var slice: Dictionary = raw if raw is Dictionary else {}
	var slots: Array = []
	var raw_slots: Variant = slice.get("slots", [])
	if raw_slots is Array:
		for row: Variant in raw_slots:
			if not (row is Dictionary):
				continue
			var ware := str((row as Dictionary).get("ware", ""))
			var menge := int((row as Dictionary).get("menge", 0))
			if ware.is_empty() or menge <= 0:
				continue
			(
				slots
				. append(
					{
						"ware": ware,
						"menge": menge,
						"faktor": clamp_faktor(float((row as Dictionary).get("faktor", 1.0))),
					}
				)
			)
	return {"tag": str(slice.get("tag", "")), "slots": slots}


static func clamp_faktor(faktor: float) -> float:
	return snappedf(clampf(faktor, FAKTOR_MIN, FAKTOR_MAX), 0.05)


## Nächster verkaufbarer Markttag als Tages-Key: Samstag vor Marktende =
## heute, sonst der kommende Samstag.
static func naechster_markt_tag(unix_s: int) -> String:
	var zeit := Time.get_datetime_dict_from_unix_time(unix_s)
	var fenster := marktfenster()
	var tage := posmod(SAMSTAG - int(zeit["weekday"]), 7)
	if tage == 0 and int(zeit["hour"]) >= int(fenster["bis"]):
		tage = 7
	return MarktPreise.tages_key(unix_s + tage * 86400)


## Stand-Zustand zum Zeitpunkt `unix_s` (s. Lebenszyklus im Kopf).
static func status(gs: Object, unix_s: int) -> String:
	var slice := slice_von(gs)
	if (slice["slots"] as Array).is_empty():
		return STATUS_LEER
	var tag := str(slice["tag"])
	var heute := MarktPreise.tages_key(unix_s)
	if tag > heute:
		return STATUS_WARTET
	if tag < heute:
		return STATUS_FERTIG
	var stunde := int(Time.get_datetime_dict_from_unix_time(unix_s)["hour"])
	var fenster := marktfenster()
	if stunde < int(fenster["von"]):
		return STATUS_WARTET
	if stunde < int(fenster["bis"]):
		return STATUS_LAEUFT
	return STATUS_FERTIG


## Ware auf den Stand legen (nur solange der Markttag noch nicht läuft).
## Nimmt höchstens den Lager-Vorrat; gleiche Ware landet im selben Slot.
## Rückgabe {ok, menge}.
static func bestuecke(
	gs: Object, unix_s: int, ware_id: String, menge: int, faktor := 1.0
) -> Dictionary:
	var fehl := {"ok": false, "menge": 0}
	if gs == null or menge <= 0 or MarktWaren.ware(ware_id).is_empty():
		return fehl
	var stand := status(gs, unix_s)
	if stand != STATUS_LEER and stand != STATUS_WARTET:
		return fehl
	var slice := slice_von(gs)
	var slots: Array = slice["slots"]
	var slot_index := _slot_index(slots, ware_id)
	if slot_index < 0 and slots.size() >= SLOT_MAX:
		return fehl
	var tag := str(slice["tag"])
	if stand == STATUS_LEER:
		tag = naechster_markt_tag(unix_s)
	var genommen := {"n": 0}
	gs.update(
		func(state: Dictionary) -> void:
			genommen["n"] = MarktWaren.nimm(state, ware_id, menge)
			if int(genommen["n"]) <= 0:
				return
			if slot_index >= 0:
				var slot: Dictionary = slots[slot_index]
				slot["menge"] = int(slot["menge"]) + int(genommen["n"])
				slot["faktor"] = clamp_faktor(faktor)
			else:
				(
					slots
					. append(
						{
							"ware": ware_id,
							"menge": int(genommen["n"]),
							"faktor": clamp_faktor(faktor),
						}
					)
				)
			_schreibe(state, tag, slots)
	)
	if int(genommen["n"]) <= 0:
		return fehl
	gs.notify_slice_changed(CityState.SLICE_ID)
	return {"ok": true, "menge": int(genommen["n"])}


## Ware wieder herunternehmen (nur vor Marktbeginn) — verlustfrei zurück
## ins Lager. Rückgabe = zurückgelegte Menge.
static func entnehme(gs: Object, unix_s: int, ware_id: String, menge: int) -> int:
	if gs == null or menge <= 0:
		return 0
	var stand := status(gs, unix_s)
	if stand != STATUS_WARTET:
		return 0
	var slice := slice_von(gs)
	var slots: Array = slice["slots"]
	var slot_index := _slot_index(slots, ware_id)
	if slot_index < 0:
		return 0
	var slot: Dictionary = slots[slot_index]
	var weg := mini(menge, int(slot["menge"]))
	gs.update(
		func(state: Dictionary) -> void:
			MarktWaren.zurueck(state, ware_id, weg)
			slot["menge"] = int(slot["menge"]) - weg
			if int(slot["menge"]) <= 0:
				slots.remove_at(slot_index)
			_schreibe(state, "" if slots.is_empty() else str(slice["tag"]), slots)
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
	return weg


## Preis-Slider einer bestückten Ware stellen (nur vor Marktbeginn).
static func set_faktor(gs: Object, unix_s: int, ware_id: String, faktor: float) -> bool:
	if gs == null or status(gs, unix_s) != STATUS_WARTET:
		return false
	var slice := slice_von(gs)
	var slots: Array = slice["slots"]
	var slot_index := _slot_index(slots, ware_id)
	if slot_index < 0:
		return false
	gs.update(
		func(state: Dictionary) -> void:
			(slots[slot_index] as Dictionary)["faktor"] = clamp_faktor(faktor)
			_schreibe(state, str(slice["tag"]), slots)
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
	return true


## Das deterministische Tagesergebnis des gebundenen Markttags (PURE Sicht,
## bucht nichts). {} solange der Stand leer ist.
static func ergebnis(gs: Object) -> Dictionary:
	var slice := slice_von(gs)
	var slots: Array = slice["slots"]
	if slots.is_empty():
		return {}
	var fenster := marktfenster()
	return MarktSim.simulate(
		slots, MarktSim.tages_seed(str(slice["tag"])), int(fenster["von"]), int(fenster["bis"])
	)


## Abrechnung buchen (läuft der Markt oder ist er vorbei): Erlös aufs Konto,
## Unverkauftes verlustfrei zurück ins Lager, Verkaufs-Zähler (`sells`,
## speist den marketDay-Sticker) hochzählen, Stand leeren.
## Rückgabe = Abrechnungs-Karte (MarktSim.abrechnung) oder {} wenn nichts
## abzuholen ist.
static func abholen(gs: Object, unix_s: int) -> Dictionary:
	var stand := status(gs, unix_s)
	if stand != STATUS_LAEUFT and stand != STATUS_FERTIG:
		return {}
	var slice := slice_von(gs)
	var slots: Array = slice["slots"]
	var sim := ergebnis(gs)
	var karte := MarktSim.abrechnung(slots, sim)
	gs.update(
		func(state: Dictionary) -> void:
			for zeile: Dictionary in karte["zeilen"]:
				MarktWaren.zurueck(state, str(zeile["ware"]), int(zeile["uebrig"]))
			var summe := int(karte["erloes"])
			if summe > 0:
				Economy.award(state["economy"], summe, "marktstand")
			_zaehle_verkaeufe(state, karte)
			_schreibe(state, "", [])
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
	RewardHub.note_action(gs)
	return karte


static func _slot_index(slots: Array, ware_id: String) -> int:
	for i in slots.size():
		if str((slots[i] as Dictionary).get("ware", "")) == ware_id:
			return i
	return -1


static func _schreibe(state: Dictionary, tag: String, slots: Array) -> void:
	if not (state.get(CityState.SLICE_ID) is Dictionary):
		state[CityState.SLICE_ID] = {}
	var city: Dictionary = state[CityState.SLICE_ID]
	city["marktstand"] = {"tag": tag, "slots": slots}


## `sells`-Zähler (achievements.counters) um die verkaufte Stückzahl erhöhen
## — dieselbe Zählung wie der Markt-Ankauf (MarktPreise.verkaufen).
static func _zaehle_verkaeufe(state: Dictionary, karte: Dictionary) -> void:
	var stueck := 0
	for zeile: Dictionary in karte["zeilen"]:
		stueck += int(zeile["verkauft"])
	if stueck <= 0:
		return
	if not (state.get("achievements") is Dictionary):
		state["achievements"] = {}
	var achievements: Dictionary = state["achievements"]
	if not (achievements.get("counters") is Dictionary):
		achievements["counters"] = {}
	var counters: Dictionary = achievements["counters"]
	counters["sells"] = int(counters.get("sells", 0)) + stueck
