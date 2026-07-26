class_name RanchWetter
extends RefCounted
## Wetter der Ranch-Region (RW-1) — PURE + headless-testbar. Das Wetter ist
## offline-first: der komplette Tagesplan entsteht deterministisch aus
## **Datum + Seed** (kein Server, kein Echtzeit-Zufall) — gleiche Eingaben
## ⇒ exakt derselbe Wettertag auf jedem Gerät.
##
## `zustand(datum, stunde, seed)` liefert den Moment-Zustand mit weichen
## Übergängen (blend), Bodennässe (Pfützen nach Regen), Abend-Regenbogen
## und Licht-/Nebel-Faktoren. Der RanchWetterController verdrahtet das in
## die Szene und feuert `wetter_changed` für andere Systeme.

## Alle Wetterlagen (Reihenfolge = Anzeige-Reihenfolge).
const TYPEN: Array[String] = ["sonne", "wolken", "niesel", "regen", "gewitter", "nebel"]

## Regnende Typen (für Nässe/Pfützen/Ambience).
const REGEN_TYPEN: Array[String] = ["niesel", "regen", "gewitter"]

## Übergangsdauer zwischen zwei Segmenten in Stunden (10 min).
const UEBERGANG_H := 10.0 / 60.0

## Nässe braucht so lange zum Aufbauen (h) und trocknet so lange ab (h).
const NASS_AUFBAU_H := 0.33
const NASS_TROCKNEN_H := 2.0

## Auswahl-Gewichte je Typ (Summe egal — wird normalisiert).
const GEWICHTE := {
	"sonne": 32.0,
	"wolken": 24.0,
	"niesel": 10.0,
	"regen": 13.0,
	"gewitter": 7.0,
	"nebel": 14.0,
}

## Wolkendecke 0..1 je Typ.
const BEWOELKUNG := {
	"sonne": 0.12,
	"wolken": 0.62,
	"niesel": 0.78,
	"regen": 0.9,
	"gewitter": 1.0,
	"nebel": 0.7,
}

## Sonnenlicht-Faktor je Typ (Wetter dimmt die Tages-Lichtkurve).
const LICHT_FAKTOR := {
	"sonne": 1.0,
	"wolken": 0.78,
	"niesel": 0.58,
	"regen": 0.45,
	"gewitter": 0.3,
	"nebel": 0.55,
}


## Deterministischer Tagesplan: Segmentliste über 24 h.
## Segment: {typ, von, bis, intensitaet (0.5..1), wind (0..1)}.
static func tagesplan(datum: String, seed_wert: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = tages_seed(datum, seed_wert)
	var plan: Array[Dictionary] = []
	var stunde := 0.0
	var vorher := ""
	while stunde < 24.0:
		var dauer := rng.randf_range(2.5, 6.0)
		var typ := _wuerfle_typ(rng, stunde, vorher)
		var wind_min := 0.55 if typ == "gewitter" else 0.05
		(
			plan
			. append(
				{
					"typ": typ,
					"von": stunde,
					"bis": minf(stunde + dauer, 24.0),
					"intensitaet": rng.randf_range(0.5, 1.0),
					"wind": rng.randf_range(wind_min, 1.0 if typ != "sonne" else 0.5),
				}
			)
		)
		vorher = typ
		stunde += dauer
	return plan


## Moment-Zustand zu Datum + Uhrzeit (Stunden 0..24, Bruchteile ok).
## Ergebnis-Schlüssel: typ, vorher, blend (0..1, 1 = Ziel-Typ voll da),
## intensitaet, wind, bewoelkung, naesse, regenbogen, licht_faktor,
## nebel_dichte, name_key.
static func zustand(datum: String, stunde: float, seed_wert: int) -> Dictionary:
	var plan := tagesplan(datum, seed_wert)
	var h := fposmod(stunde, 24.0)
	var index := _segment_index(plan, h)
	var segment := plan[index]
	var vorher := plan[maxi(0, index - 1)]
	var blend := clampf((h - float(segment["von"])) / UEBERGANG_H, 0.0, 1.0)
	if index == 0:
		blend = 1.0
	var typ := str(segment["typ"])
	var typ_vorher := str(vorher["typ"])
	var naesse_wert := naesse(plan, h)
	return {
		"typ": typ,
		"vorher": typ_vorher,
		"blend": blend,
		"intensitaet": _mix(vorher, segment, "intensitaet", blend),
		"wind": _mix(vorher, segment, "wind", blend),
		"bewoelkung": lerpf(float(BEWOELKUNG[typ_vorher]), float(BEWOELKUNG[typ]), blend),
		"naesse": naesse_wert,
		"regenbogen": ist_regenbogen(typ, naesse_wert, h),
		"licht_faktor": lerpf(float(LICHT_FAKTOR[typ_vorher]), float(LICHT_FAKTOR[typ]), blend),
		"nebel_dichte": lerpf(_nebel(vorher), _nebel(segment), blend),
		"name_key": "rwelt.wetter.%s" % typ,
	}


## Bodennässe 0..1: baut sich im Regen auf und trocknet danach ~2 h ab —
## „nasser Boden/Pfützen“ und „Buddel-Glitzer nach Regen“ hängen hieran.
static func naesse(plan: Array[Dictionary], stunde: float) -> float:
	var wert := 0.0
	for segment: Dictionary in plan:
		var typ := str(segment["typ"])
		if not REGEN_TYPEN.has(typ):
			continue
		var staerke := float(segment["intensitaet"]) * (0.5 if typ == "niesel" else 1.0)
		var von := float(segment["von"])
		var bis := float(segment["bis"])
		if stunde < von:
			continue
		if stunde <= bis:
			wert = maxf(wert, staerke * clampf((stunde - von) / NASS_AUFBAU_H, 0.0, 1.0))
		else:
			var trocken := (stunde - bis) / NASS_TROCKNEN_H
			wert = maxf(wert, staerke * maxf(0.0, 1.0 - trocken))
	return clampf(wert, 0.0, 1.0)


## Abend-Regenbogen: klarer Himmel + noch nasser Boden + Abendstunde.
static func ist_regenbogen(typ: String, naesse_wert: float, stunde: float) -> bool:
	if typ != "sonne" and typ != "wolken":
		return false
	return naesse_wert > 0.15 and stunde >= 16.0 and stunde <= 20.5


## Kontinuierliche Wind-Böe 0..~1.3 für Shader/Partikel (zeit in s).
static func boe(zeit_s: float, wind: float) -> float:
	var puls := 0.72 + 0.2 * sin(zeit_s * 0.9) + 0.08 * sin(zeit_s * 2.7 + 1.3)
	return maxf(0.0, wind * puls)


## Stabiler Seed für einen Kalendertag ("YYYY-MM-DD") + Welt-Seed.
static func tages_seed(datum: String, seed_wert: int) -> int:
	return int(hash("%s|%d" % [datum, seed_wert])) & 0x7FFFFFFF


## Heutiges Datum als Plan-Schlüssel (Systemuhr, offline).
static func datum_heute() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## ------------------------------------------------------------------ intern


static func _wuerfle_typ(rng: RandomNumberGenerator, stunde: float, vorher: String) -> String:
	var summe := 0.0
	for typ: String in TYPEN:
		summe += _gewicht(typ, stunde, vorher)
	var wurf := rng.randf() * summe
	for typ: String in TYPEN:
		wurf -= _gewicht(typ, stunde, vorher)
		if wurf <= 0.0:
			return typ
	return "sonne"


## Tageszeit-gekoppelte Gewichte: Nebel morgens/spätabends, Gewitter nur
## nachmittags/abends; nie zweimal derselbe Typ hintereinander.
static func _gewicht(typ: String, stunde: float, vorher: String) -> float:
	if typ == vorher:
		return 0.0
	var gewicht := float(GEWICHTE[typ])
	if typ == "nebel":
		gewicht *= 2.2 if (stunde < 9.0 or stunde >= 21.0) else 0.35
	if typ == "gewitter":
		gewicht *= 1.8 if (stunde >= 13.0 and stunde < 22.0) else 0.0
	return gewicht


static func _segment_index(plan: Array[Dictionary], stunde: float) -> int:
	for i in plan.size():
		if stunde < float(plan[i]["bis"]):
			return i
	return plan.size() - 1


static func _mix(vorher: Dictionary, jetzt: Dictionary, key: String, blend: float) -> float:
	return lerpf(float(vorher[key]), float(jetzt[key]), blend)


static func _nebel(segment: Dictionary) -> float:
	var typ := str(segment["typ"])
	var staerke := float(segment["intensitaet"])
	match typ:
		"nebel":
			return 0.5 + 0.5 * staerke
		"regen":
			return 0.18
		"gewitter":
			return 0.26
		"niesel":
			return 0.12
		_:
			return 0.0
