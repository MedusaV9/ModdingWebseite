class_name MarktPreise
extends RefCounted
## Wochenmarkt-Preislogik (Doc D §6.3, USER §D51) — PURE.
##
## Der Markt zahlt den Kompost-Basispreis + 15 % Markt-Bonus. ABER: der Markt
## ist klein. Jede HEUTE schon verkaufte Einheit derselben Ware drückt den
## Preis um 5 % (Preis-Elastizität), bis zum Boden von 50 % des Marktpreises.
## Am nächsten Markttag zählt der Tages-Zähler wieder bei 0 los — deshalb
## steht im Save nur {tag, verkauft{}} und kein Verlaufs-Archiv.
##
## Alle Funktionen sind statisch und ohne GameState testbar; die Slice-Helfer
## unten sind der einzige Ort, der `gs` anfasst.

const Economy := preload("res://scripts/logic/economy.gd")

const PREIS_PFAD := "res://scripts/city/data/markt_preise.json"


static func daten(pfad := PREIS_PFAD) -> Dictionary:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("markt_preise.json kaputt: %s" % pfad)
		return {}
	return json.data


static func ernte_sorten(pfad := PREIS_PFAD) -> Array:
	var raw: Variant = daten(pfad).get("ernte", [])
	return raw if raw is Array else []


static func sorte(id: String, pfad := PREIS_PFAD) -> Dictionary:
	for eintrag: Dictionary in ernte_sorten(pfad):
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


## Voller Marktpreis EINER Einheit ohne Elastizität (Basis + Markt-Bonus).
static func marktpreis(id: String, pfad := PREIS_PFAD) -> int:
	var eintrag := sorte(id, pfad)
	if eintrag.is_empty():
		return 0
	var bonus := float(daten(pfad).get("markt_bonus", 0.15))
	return maxi(1, roundi(float(eintrag.get("basis", 0)) * (1.0 + bonus)))


## Preis der NÄCHSTEN Einheit, wenn heute schon `schon_verkauft` weg sind.
static func stueckpreis(id: String, schon_verkauft: int, pfad := PREIS_PFAD) -> int:
	var voll := marktpreis(id, pfad)
	if voll <= 0:
		return 0
	var d := daten(pfad)
	var elastizitaet := float(d.get("elastizitaet_pro_stueck", 0.05))
	var boden := float(d.get("preis_boden", 0.5))
	var faktor := maxf(boden, 1.0 - elastizitaet * float(maxi(0, schon_verkauft)))
	return maxi(1, roundi(float(voll) * faktor))


## Erlös für `menge` Einheiten am Stück (jede Einheit drückt den Preis weiter).
static func erloes(id: String, menge: int, schon_verkauft: int, pfad := PREIS_PFAD) -> int:
	var summe := 0
	for i in maxi(0, menge):
		summe += stueckpreis(id, schon_verkauft + i, pfad)
	return summe


## Tages-Key (lokal, YYYY-MM-DD) — Wechsel setzt die Elastizität zurück.
static func tages_key(unix_s: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_s)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## Markt-Slice des Tages ({tag, verkauft}) — an einem neuen Tag frisch.
static func slice_heute(gs: Object, unix_s: int) -> Dictionary:
	var heute := tages_key(unix_s)
	if gs == null:
		return {"tag": heute, "verkauft": {}}
	var roh: Variant = gs.get_value("city.markt", {})
	var slice: Dictionary = roh if roh is Dictionary else {}
	if str(slice.get("tag", "")) != heute or not (slice.get("verkauft") is Dictionary):
		return {"tag": heute, "verkauft": {}}
	return {"tag": heute, "verkauft": (slice["verkauft"] as Dictionary).duplicate()}


static func heute_verkauft(gs: Object, unix_s: int, id: String) -> int:
	return int(slice_heute(gs, unix_s).get("verkauft", {}).get(id, 0))


## Verkauf buchen: Ware aus inventory.food nehmen, Münzen gutschreiben,
## Tages-Zähler hochzählen. Rückgabe {ok, menge, erloes}.
static func verkaufen(gs: Object, unix_s: int, id: String, menge: int) -> Dictionary:
	var fehl := {"ok": false, "menge": 0, "erloes": 0}
	if gs == null or menge <= 0 or sorte(id).is_empty():
		return fehl
	var vorrat := int(gs.get_value("inventory.food.%s" % id, 0))
	var echte_menge := mini(menge, vorrat)
	if echte_menge <= 0:
		return fehl
	var slice := slice_heute(gs, unix_s)
	var schon := int(slice["verkauft"].get(id, 0))
	var summe := erloes(id, echte_menge, schon)
	var verkauft: Dictionary = slice["verkauft"]
	verkauft[id] = schon + echte_menge
	gs.update(
		func(state: Dictionary) -> void:
			var food: Dictionary = state["inventory"]["food"]
			food[id] = maxi(0, int(food.get(id, 0)) - echte_menge)
			Economy.award(state["economy"], summe, "wochenmarkt")
			var city: Dictionary = state.get(CityState.SLICE_ID, {})
			city["markt"] = {"tag": str(slice["tag"]), "verkauft": verkauft}
	)
	gs.notify_slice_changed(CityState.SLICE_ID)
	return {"ok": true, "menge": echte_menge, "erloes": summe}


## Verkaufbare Ernte im Inventar: [{id, name_de, vorrat, preis}].
static func angebot_des_spielers(gs: Object, unix_s: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if gs == null:
		return out
	for eintrag: Dictionary in ernte_sorten():
		var id := str(eintrag.get("id", ""))
		var vorrat := int(gs.get_value("inventory.food.%s" % id, 0))
		if vorrat <= 0:
			continue
		(
			out
			. append(
				{
					"id": id,
					"name_de": str(eintrag.get("name_de", id)),
					"vorrat": vorrat,
					"preis": stueckpreis(id, heute_verkauft(gs, unix_s, id)),
					"voll": marktpreis(id),
				}
			)
		)
	return out
