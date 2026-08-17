class_name PostLogic
extends RefCounted
## FERTIG-1 (Platzhalter „Versand an Freunde kommt bald“ → ersetzt):
## das TAGESPAKET. Frau Zettel legt pro Lokaltag genau EIN Paket für
## Gooby zurück — 15–40 Münzen, deterministisch über den Tages-String
## geseedet (kein Farm-Reroll durch Neu-Öffnen). Der alte Brief-Schalter
## (Multiplayer-Versand ohne Netzcode) ist ersatzlos gestrichen; ein
## künftiger Netz-Versand bekommt wieder einen eigenen, echten Schalter.
##
## Save: ADDITIVER city-Schlüssel `city.postPaket = {"tag": "YYYY-MM-DD"}`
## (letzter Abhol-Tag; normalize in city_state.gd — KEIN Version-Bump).

const Economy := preload("res://scripts/logic/economy.gd")

const COINS_MIN := 15
const COINS_MAX := 40


## Liegt heute noch ein Paket bereit?
static func verfuegbar(state: Dictionary, tag: String) -> bool:
	return _paket_slice(state).get("tag", "") != tag


## Tages-Inhalt: uniform 15–40 Münzen, geseedet über den Tages-String
## (FNV-1a → mulberry32) — jeder sieht am selben Tag dasselbe Paket.
static func coins_fuer(tag: String) -> int:
	var h := 2166136261
	for i in tag.length():
		h = (h ^ tag.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	var rng := GoobyRng.new(h)
	return COINS_MIN + int(floor(rng.next() * float(COINS_MAX - COINS_MIN + 1)))


## Paket abholen (mutiert `state` — innerhalb von GameState.update rufen).
## Liefert {ok, coins}; ok=false wenn heute schon abgeholt.
static func hole_paket(state: Dictionary, tag: String) -> Dictionary:
	if not verfuegbar(state, tag):
		return {"ok": false, "coins": 0}
	var coins := coins_fuer(tag)
	if state.get("economy") is Dictionary:
		Economy.award(state["economy"], coins, "postPaket", tag)
	var city: Dictionary = state.get("city") if state.get("city") is Dictionary else {}
	city["postPaket"] = {"tag": tag}
	state["city"] = city
	return {"ok": true, "coins": coins}


static func _paket_slice(state: Dictionary) -> Dictionary:
	var city: Variant = state.get("city")
	if not (city is Dictionary):
		return {}
	var paket: Variant = (city as Dictionary).get("postPaket")
	return paket if paket is Dictionary else {}
