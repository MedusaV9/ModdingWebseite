class_name OrtKatalog
extends RefCounted
## Ort-Registry (W3a/ORTE, Doc E §2.1): EINE Quelle der Wahrheit für alles,
## was die Stadt und die IGohbie-Apps über einen Ort wissen müssen —
## Szene, Name-Key, Energie-Kosten, Öffnungszeiten und Erst-Besuch.
## Datenbasis ist `city_map.json` (CityMap), damit Karte und Katalog nicht
## driften können (Doc E §8 Risiko 5 „Katalog-Drift“).
##
## Öffnungszeiten sind OPTIONAL: ohne `oeffnung`-Block ist ein Ort immer
## offen. Der Wochenmarkt hat `{"wochentage": [6], "von_stunde": 8,
## "bis_stunde": 14}` — Samstag 8–14 Uhr (Doc E §2.3, USER §D51).
## Wochentag-Zählung wie in Godots `Time`: 0 = Sonntag … 6 = Samstag.

const SAMSTAG := 6

## Erst-Besuche liegen im city-Slice unter `besucht` (additiv, CityState).
const BESUCHT_KEY := "city.besucht"


## Alle Ort-Einträge der Karte (Roh-Dictionaries aus city_map.json).
static func eintraege(karte: CityMap = null) -> Array:
	return _karte(karte).orte()


static func eintrag(ort_id: String, karte: CityMap = null) -> Dictionary:
	return _karte(karte).ort(ort_id)


## Ids aller BETRETBAREN Orte (mit hinterlegter Szene).
static func betretbare_ids(karte: CityMap = null) -> Array[String]:
	var out: Array[String] = []
	for eintrag_raw: Dictionary in eintraege(karte):
		if not str(eintrag_raw.get("szene", "")).is_empty():
			out.append(str(eintrag_raw.get("id", "")))
	return out


## Öffnungsregel eines Orts ({} = immer offen).
static func oeffnung(ort_id: String, karte: CityMap = null) -> Dictionary:
	var raw: Variant = eintrag(ort_id, karte).get("oeffnung", {})
	return raw if raw is Dictionary else {}


## Ist der Ort zum Zeitpunkt `unix_s` (lokale Zeit) geöffnet?
static func ist_offen(ort_id: String, unix_s: int, karte: CityMap = null) -> bool:
	var regel := oeffnung(ort_id, karte)
	if regel.is_empty():
		return true
	var zeit := Time.get_datetime_dict_from_unix_time(unix_s)
	return ist_offen_an(regel, int(zeit["weekday"]), float(zeit["hour"]))


## Öffnungstage einer Regel als echte Ints. JSON liefert Zahlen als Float —
## ohne diese Umwandlung findet `has(6)` die 6.0 nicht und der Markt hätte
## nie geöffnet.
static func wochentage(regel: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = regel.get("wochentage", [])
	if raw is Array:
		for tag: Variant in raw:
			out.append(int(tag))
	return out


## Pure Variante für Tests: Regel gegen Wochentag (0=So) + Stunde prüfen.
static func ist_offen_an(regel: Dictionary, wochentag: int, stunde: float) -> bool:
	if regel.is_empty():
		return true
	var tage := wochentage(regel)
	if not tage.is_empty() and not tage.has(wochentag):
		return false
	var von := float(regel.get("von_stunde", 0.0))
	var bis := float(regel.get("bis_stunde", 24.0))
	return stunde >= von and stunde < bis


## „Warum zu?“-Text-Key für den Prompt in der Stadt.
static func geschlossen_key(ort_id: String, karte: CityMap = null) -> String:
	if wochentage(oeffnung(ort_id, karte)).has(SAMSTAG):
		return "city.ort.nur_samstag"
	return "city.ort.geschlossen"


## Nächster Samstag-Öffnungstag als Anzahl Tage (0 = heute).
static func tage_bis_samstag(wochentag: int) -> int:
	return posmod(SAMSTAG - wochentag, 7)


## War der Ort schon mal betreten? (Erste-Male-Karte/Sticker-Trigger.)
static func schon_besucht(gs: Object, ort_id: String) -> bool:
	if gs == null:
		return false
	var besucht: Variant = gs.get_value(BESUCHT_KEY, {})
	return besucht is Dictionary and bool(besucht.get(ort_id, false))


## Besuch vermerken. Rückgabe true = das war der ERSTE Besuch.
static func besuch_merken(gs: Object, ort_id: String) -> bool:
	if gs == null or ort_id.is_empty():
		return false
	if schon_besucht(gs, ort_id):
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var city: Dictionary = state.get(CityState.SLICE_ID, {})
			var besucht: Dictionary = city.get("besucht", {})
			besucht[ort_id] = true
			city["besucht"] = besucht
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
	return true


static func _karte(karte: CityMap) -> CityMap:
	return karte if karte != null else CityMap.laden()
