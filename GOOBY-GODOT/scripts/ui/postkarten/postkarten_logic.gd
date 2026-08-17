class_name PostkartenLogic
extends RefCounted
## Postkarten-Archiv-Engine (REST-4, EVAL Rang 15 + P1 „Bald“) — PURER Port
## von GOOBY/src/systems/postcards.js: eine Karte pro VOLLEM Reisetag
## (feste TRIP-ms, nie Kalendertage), deterministische Text-Varianten-Wahl
## (mulberry32, Seed aus destId+bookedAt — Replays erzeugen byte-gleiche
## Archive) und ein FIFO-Archiv mit MAX_ARCHIVE-Deckel. Die Generierung
## läuft aus Vacation.tick() — Live-Ticker und Offline-Catch-up teilen
## sich DIESEN Prozessor (idempotent, rückwärts-uhr-sicher).
##
## Dazu (Godot-additiv, Web-Regal-Parität): Souvenir-Sicht auf
## `vacation.visited` und der Set-Bonus für viele besuchte Ziele
## (Claims persistieren additiv in `vacation.setBonusClaimed`).
##
## WICHTIG (Zyklus-Freiheit wie im Web): dieses Modul lädt vacation.gd
## NICHT — vacation.gd lädt UNS. Die Ziel-Liste ist deshalb dupliziert
## (Test CatalogSync wacht über die Gleichheit mit Vacation.CATALOG).

## Ein Reisetag in festen REAL-ms (== Vacation.MS_PER_DAY, Test-gepinnt).
const MS_PER_DAY := 86400000
## Archiv-Deckel (PLAN6 §5): älteste Karten fliegen zuerst (FIFO).
const MAX_ARCHIVE := 36
## Text-Pool je Ziel (Keys `postkarten.text.<destId>.1..N`).
const VARIANTS := 5

## Bekannte Ziel-Ids (== Vacation.CATALOG.keys(), dupliziert — s. Header).
const DEST_IDS: Array[String] = [
	"beach",
	"meadowTrip",
	"bigCity",
	"space",
	"harbor",
	"spookGarden",
	"bakery",
	"nightSky",
	"toyRoom",
]

## Set-Bonus-Stufen: n besuchte Ziele → Münzen (einmalig je Stufe).
const SET_STUFEN: Array[Dictionary] = [
	{"n": 3, "coins": 150},
	{"n": 6, "coins": 300},
	{"n": 9, "coins": 600},
]

## ---------------------------------------------------------- Deterministik


## FNV-1a-Hash → uint32 (Web hashStr, verbatim).
static func hash_str(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = h ^ text.unicode_at(i)
		h = _imul(h, 16777619)
	return h & 0xFFFFFFFF


## Trip-Seed: destId + Buchungszeit (Web tripSeed).
static func trip_seed(dest_id: String, booked_at: int) -> int:
	var at := int(floor(_num(booked_at)))
	return (hash_str(dest_id) ^ (at & 0xFFFFFFFF)) & 0xFFFFFFFF


## Deterministische Text-Variante für Reisetag k (1..VARIANTS, Web variantOf).
static func variant_of(dest_id: String, booked_at: int, day_index: int) -> int:
	var k := maxi(1, int(floor(_num(day_index))))
	var seed := (trip_seed(dest_id, booked_at) ^ _imul(k, 0x9e3779b1)) & 0xFFFFFFFF
	var rnd := _mulberry32(seed)
	return 1 + (int(floor(rnd * float(VARIANTS))) % VARIANTS)


## Ein mulberry32-Schritt (Web-Rezept, uint32-treu) → 0..1.
static func _mulberry32(seed: int) -> float:
	var a := (seed + 0x6D2B79F5) & 0xFFFFFFFF
	var t := _imul(a ^ (a >> 15), (1 | a) & 0xFFFFFFFF)
	t = ((t + _imul(t ^ (t >> 7), (61 | t) & 0xFFFFFFFF)) & 0xFFFFFFFF) ^ t
	t = t & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


## Math.imul: 32-Bit-Multiplikation mit Wrap, Ergebnis als uint32.
static func _imul(a: int, b: int) -> int:
	return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF


## ---------------------------------------------------------- Archiv-Sicht


## I18n-Key der handgeschriebenen Zeile einer Karte (Junk klemmt in den Pool).
static func text_key(entry: Dictionary) -> String:
	var dest_id := str(entry.get("destId", ""))
	var variant := clampi(int(floor(_num(entry.get("variant", 1)))), 1, VARIANTS)
	return "postkarten.text.%s.%d" % [dest_id, maxi(1, variant)]


## EINEN rohen Archiv-Eintrag normalisieren (Junk → {}).
static func normalize_entry(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var e := raw as Dictionary
	var dest_id := str(e.get("destId", "")) if e.get("destId") is String else ""
	if dest_id.is_empty() or not DEST_IDS.has(dest_id):
		return {}
	var day_f := _num_nan(e.get("dayIndex"))
	var var_f := _num_nan(e.get("variant"))
	var at_ms := _num_nan(e.get("atMs"))
	if is_nan(day_f) or is_nan(var_f) or is_nan(at_ms):
		return {}
	var day_index := int(floor(day_f))
	var variant := int(floor(var_f))
	if day_index < 1 or variant < 1 or at_ms < 0.0:
		return {}
	return {"destId": dest_id, "dayIndex": day_index, "variant": variant, "atMs": int(at_ms)}


## Rohes Archiv normalisieren: Junk raus, Duplikate kollabieren,
## chronologisch sortieren, FIFO-Deckel (die NEUSTEN bleiben).
static func normalize_archive(raw: Variant) -> Array:
	if not (raw is Array):
		return []
	var clean: Array = []
	var seen := {}
	for item: Variant in raw:
		var entry := normalize_entry(item)
		if entry.is_empty():
			continue
		var key := "%s|%d|%d" % [entry["destId"], int(entry["atMs"]), int(entry["dayIndex"])]
		if seen.has(key):
			continue
		seen[key] = true
		clean.append(entry)
	clean.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["atMs"]) < int(b["atMs"])
	)
	if clean.size() > MAX_ARCHIVE:
		return clean.slice(clean.size() - MAX_ARCHIVE)
	return clean


## DER geteilte pure Prozessor (Web processPostcardsUpTo): Archiv eines
## Vacation-Slices bis now_ms aufholen. Karten tragen ihre feste
## Ankunftszeit (bookedAt + k·Tag), nie die Beobachtungs-Uhr.
static func process_postcards_up_to(v: Dictionary, now_ms: int) -> Dictionary:
	var archive := normalize_archive(v.get("archive"))
	var last := maxi(0, int(floor(_num(v.get("lastPostcardDayProcessed")))))
	var dest_id := str(v.get("destId", "")) if v.get("destId") is String else ""
	var booked_at := _num(v.get("bookedAt"))
	var return_at := _num(v.get("returnAt"))
	if dest_id.is_empty() or not DEST_IDS.has(dest_id):
		return {"archive": archive, "lastPostcardDayProcessed": last, "added": 0}
	if not (booked_at > 0.0) or not (return_at > booked_at):
		return {"archive": archive, "lastPostcardDayProcessed": last, "added": 0}
	var total_days := int(round((return_at - booked_at) / MS_PER_DAY))
	var max_cards := maxi(0, total_days - 1)
	var full_days := int(floor((minf(float(now_ms), return_at) - booked_at) / MS_PER_DAY))
	var due := maxi(0, mini(full_days, max_cards))
	var added := 0
	for k in range(last + 1, due + 1):
		(
			archive
			. append(
				{
					"destId": dest_id,
					"dayIndex": k,
					"variant": variant_of(dest_id, int(booked_at), k),
					"atMs": int(booked_at) + k * MS_PER_DAY,
				}
			)
		)
		added += 1
	if archive.size() > MAX_ARCHIVE:
		archive = archive.slice(archive.size() - MAX_ARCHIVE)
	return {"archive": archive, "lastPostcardDayProcessed": maxi(last, due), "added": added}


## Archiv eines Save-States, normalisiert (stabile Lese-API der UI).
static func archive_of(state: Dictionary) -> Array:
	var v: Variant = state.get("vacation")
	if not (v is Dictionary):
		return []
	return normalize_archive((v as Dictionary).get("archive"))


## ---------------------------------------------------------- Souvenirregal


## Besuchte Ziele (nur strikte true-Werte bekannter Ids), Katalog-Reihenfolge.
static func souvenirs_von(state: Dictionary) -> Array:
	var v: Variant = state.get("vacation")
	if not (v is Dictionary):
		return []
	var visited: Variant = (v as Dictionary).get("visited")
	if not (visited is Dictionary):
		return []
	var out: Array = []
	for id: String in DEST_IDS:
		var wert: Variant = (visited as Dictionary).get(id)
		if wert is bool and wert:
			out.append(id)
	return out


static func besucht_anzahl(state: Dictionary) -> int:
	return souvenirs_von(state).size()


## ---------------------------------------------------------- Set-Bonus


## Stufen-Zeilen fürs UI: {n, coins, erreicht, abgeholt}.
static func set_stufen(state: Dictionary) -> Array:
	var besucht := besucht_anzahl(state)
	var claimed := _claimed(state)
	var out: Array = []
	for stufe: Dictionary in SET_STUFEN:
		(
			out
			. append(
				{
					"n": int(stufe["n"]),
					"coins": int(stufe["coins"]),
					"erreicht": besucht >= int(stufe["n"]),
					"abgeholt": claimed.has(str(int(stufe["n"]))),
				}
			)
		)
	return out


## Stufen-Claim (mutiert den Save-Draft): Münzen zahlt der AUFRUFER über
## Economy.award — hier wird nur der Latch gesetzt. 0 = nichts zu holen.
static func claim_set_bonus(state: Dictionary, n: int, now_ms: int) -> int:
	var besucht := besucht_anzahl(state)
	var claimed := _claimed(state)
	for stufe: Dictionary in SET_STUFEN:
		if int(stufe["n"]) != n:
			continue
		if besucht < n or claimed.has(str(n)):
			return 0
		if not (state.get("vacation") is Dictionary):
			return 0
		var v: Dictionary = state["vacation"]
		if not (v.get("setBonusClaimed") is Dictionary):
			v["setBonusClaimed"] = {}
		v["setBonusClaimed"][str(n)] = now_ms
		return int(stufe["coins"])
	return 0


static func _claimed(state: Dictionary) -> Dictionary:
	var v: Variant = state.get("vacation")
	if not (v is Dictionary):
		return {}
	var raw: Variant = (v as Dictionary).get("setBonusClaimed")
	return raw if raw is Dictionary else {}


## ---------------------------------------------------------- Helfer


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0


static func _num_nan(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return NAN
