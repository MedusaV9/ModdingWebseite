class_name PowAngebote
extends RefCounted
## POW!-Tagesangebote + Kamera-Gate (Doc E §2.3, USER §E61) — PURE.
##
## 3 Angebots-Slots, deterministisch aus dem KALENDERTAG gezogen
## (mulberry32 = `GoobyRng`, Rezept aus der Web-Referenz postcards.js):
## derselbe Tag ⇒ dieselben drei Waren mit denselben Rabatten, auf jedem
## Gerät, ohne Server. Um Mitternacht wechselt das Angebot („Neu in 7 h!“).
##
## Die KAMERA ist keine Tagesware, sondern das Gate für den Fotomodus:
## einmal gekauft (inventory.items.kamera ≥ 1), danach als „hast du schon“
## ausgegraut. Die IGohbie-Kamera-App fragt genau das über `hat_kamera()` ab.

const SORTIMENT_PFAD := "res://scripts/city/data/pow_sortiment.json"
const KAMERA_ITEM := "kamera"
const SLOTS := 3


## Rohdaten des Sortiments ({} bei kaputter Datei).
static func daten(pfad := SORTIMENT_PFAD) -> Dictionary:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("POW!-Sortiment kaputt: %s" % pfad)
		return {}
	return json.data


static func kamera_ware(pfad := SORTIMENT_PFAD) -> Dictionary:
	var raw: Variant = daten(pfad).get("kamera", {})
	return raw if raw is Dictionary else {}


static func pool(pfad := SORTIMENT_PFAD) -> Array:
	var raw: Variant = daten(pfad).get("pool", [])
	return raw if raw is Array else []


## Tages-Seed aus einem Unix-Zeitstempel (LOKALE Kalenderzeit): YYYYMMDD.
static func tag_seed(unix_s: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(unix_s)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## Sekunden bis zum nächsten Angebots-Wechsel (Mitternacht lokal).
static func rest_s_bis_wechsel(unix_s: int) -> int:
	var d := Time.get_datetime_dict_from_unix_time(unix_s)
	var seit_mitternacht := int(d["hour"]) * 3600 + int(d["minute"]) * 60 + int(d["second"])
	return 86400 - seit_mitternacht


## Die 3 Tagesangebote zum Seed: [{id, name_de, preis, rabatt, preis_neu,
## inventar}] — Waren sind paarweise verschieden, Reihenfolge stabil.
static func angebote(seed_wert: int, pfad := SORTIMENT_PFAD) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var waren := pool(pfad)
	if waren.is_empty():
		return out
	var rabatte: Array = daten(pfad).get("rabatte", [20, 30, 50])
	var rng := GoobyRng.new(seed_wert)
	var uebrig: Array = waren.duplicate()
	for slot in mini(SLOTS, waren.size()):
		var index := int(rng.next() * float(uebrig.size()))
		index = clampi(index, 0, uebrig.size() - 1)
		var ware: Dictionary = uebrig[index]
		uebrig.remove_at(index)
		var rabatt := int(rabatte[slot % rabatte.size()])
		(
			out
			. append(
				{
					"id": str(ware.get("id", "")),
					"name_de": str(ware.get("name_de", "?")),
					"inventar": str(ware.get("inventar", ware.get("id", ""))),
					"preis": int(ware.get("preis", 0)),
					"rabatt": rabatt,
					"preis_neu": preis_mit_rabatt(int(ware.get("preis", 0)), rabatt),
				}
			)
		)
	return out


## Rabatt-Preis (kaufmännisch gerundet, mindestens 1 Münze).
static func preis_mit_rabatt(preis: int, rabatt_prozent: int) -> int:
	var neu := roundi(float(preis) * (1.0 - float(rabatt_prozent) / 100.0))
	return maxi(1, neu)


## Kamera schon gekauft? (Gate für Fotomodus + IGohbie-Kamera-App.)
static func hat_kamera(gs: Object) -> bool:
	if gs == null:
		return false
	return int(gs.get_value("inventory.items.%s" % KAMERA_ITEM, 0)) > 0
