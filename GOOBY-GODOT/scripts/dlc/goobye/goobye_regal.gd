class_name GoobyeRegal
extends RefCounted
## Regal-Bestand und Nachfüllen des „Goo und Bye“ (G5/P24, Doc §4.3) —
## PURE + static über schlichten Dictionaries (headless golden-testbar,
## Save-tauglich). Welle A: EINE Regal-Reihe mit festen Slots; jeder Slot
## hält genau EINE Ware bis zum Slot-Deckel. Kein Verderb, nirgends —
## ein leeres Regal ist eine To-do-Notiz, keine Strafe (§1.4).

## Grundregal Welle A: 5 Slots (§3.2 Grundregal-Klasse), Deckel je Slot.
const SLOTS := 5
const MAX_JE_SLOT := 8


## Frisches Regal: [{ware: "", menge: 0}, …].
static func neues_regal(slots := SLOTS) -> Dictionary:
	var reihe: Array = []
	for _i in maxi(1, slots):
		reihe.append({"ware": "", "menge": 0})
	return {"slots": reihe}


## Self-Heal für Save-Daten (Typen reparieren, Deckel anwenden).
static func normalisieren(raw: Variant, slots := SLOTS) -> Dictionary:
	var regal := neues_regal(slots)
	if not (raw is Dictionary) or not ((raw as Dictionary).get("slots") is Array):
		return regal
	var quelle: Array = (raw as Dictionary)["slots"]
	for i in mini(quelle.size(), (regal["slots"] as Array).size()):
		if not (quelle[i] is Dictionary):
			continue
		var ware := str((quelle[i] as Dictionary).get("ware", ""))
		var menge := clampi(int((quelle[i] as Dictionary).get("menge", 0)), 0, MAX_JE_SLOT)
		if ware.is_empty() or menge <= 0:
			continue
		regal["slots"][i] = {"ware": ware, "menge": menge}
	return regal


## Einräumen (Tap aufs Regal): zieht bis zu `menge` Stück der Ware aus dem
## Lager in den Slot (leer oder gleiche Ware). Gibt die tatsächlich
## eingeräumte Stückzahl zurück (0 = nichts zu tun / Slot belegt).
static func einraeumen(
	regal: Dictionary, slot_idx: int, ware_id: String, menge: int, lager: Dictionary
) -> int:
	var slot := _slot(regal, slot_idx)
	if slot.is_empty() or ware_id.is_empty() or menge <= 0:
		return 0
	if not str(slot["ware"]).is_empty() and str(slot["ware"]) != ware_id:
		return 0
	var vorrat := maxi(0, int(lager.get(ware_id, 0)))
	var platz := MAX_JE_SLOT - int(slot["menge"])
	var bewegt := mini(menge, mini(vorrat, platz))
	if bewegt <= 0:
		return 0
	slot["ware"] = ware_id
	slot["menge"] = int(slot["menge"]) + bewegt
	lager[ware_id] = vorrat - bewegt
	if int(lager[ware_id]) <= 0:
		lager.erase(ware_id)
	return bewegt


## Entnahme (Kunde greift zu): nimmt bis zu `menge` Stück der Ware aus der
## Reihe, leert Slots sauber aus. Gibt die tatsächliche Stückzahl zurück.
static func entnehmen(regal: Dictionary, ware_id: String, menge := 1) -> int:
	var rest := maxi(0, menge)
	for slot: Dictionary in regal.get("slots", []):
		if rest <= 0:
			break
		if str(slot.get("ware", "")) != ware_id:
			continue
		var weg := mini(rest, int(slot.get("menge", 0)))
		slot["menge"] = int(slot["menge"]) - weg
		rest -= weg
		if int(slot["menge"]) <= 0:
			slot["ware"] = ""
			slot["menge"] = 0
	return menge - rest


## Bestand einer Ware über alle Slots.
static func bestand(regal: Dictionary, ware_id: String) -> int:
	var summe := 0
	for slot: Dictionary in regal.get("slots", []):
		if str(slot.get("ware", "")) == ware_id:
			summe += maxi(0, int(slot.get("menge", 0)))
	return summe


## Gesamtbestand der Reihe (0 = Laden kann nicht öffnen).
static func gesamt_bestand(regal: Dictionary) -> int:
	var summe := 0
	for slot: Dictionary in regal.get("slots", []):
		summe += maxi(0, int(slot.get("menge", 0)))
	return summe


## Sortiments-Zeilen fürs Markttag-Modul: [{id, bestand, faktor}] je
## bestückter Ware (Preis-Faktoren pro Ware aus `faktoren`, Default 1.0).
static func sortiment_von(regal: Dictionary, faktoren := {}) -> Array:
	var gesehen: Dictionary = {}
	var out: Array = []
	for slot: Dictionary in regal.get("slots", []):
		var ware := str(slot.get("ware", ""))
		if ware.is_empty() or int(slot.get("menge", 0)) <= 0 or gesehen.has(ware):
			continue
		gesehen[ware] = true
		(
			out
			. append(
				{
					"id": ware,
					"bestand": bestand(regal, ware),
					"faktor": float(faktoren.get(ware, 1.0)),
				}
			)
		)
	return out


## Nachfüll-Vorschlag („Das war schnell weg“, §2.5): Indizes leerer Slots,
## solange das Lager noch irgendetwas hergibt.
static func nachfuell_vorschlag(regal: Dictionary, lager: Dictionary) -> Array:
	var lager_leer := true
	for ware_id: Variant in lager:
		if int(lager[ware_id]) > 0:
			lager_leer = false
			break
	if lager_leer:
		return []
	var out: Array = []
	var slots: Array = regal.get("slots", [])
	for i in slots.size():
		if str((slots[i] as Dictionary).get("ware", "")).is_empty():
			out.append(i)
	return out


static func _slot(regal: Dictionary, slot_idx: int) -> Dictionary:
	var slots: Array = regal.get("slots", [])
	if slot_idx < 0 or slot_idx >= slots.size():
		return {}
	return slots[slot_idx]
