class_name CouchLogic
extends RefCounted
## Besucher-Couch-Regel (W13B COUCH-COOP, User-Wunsch §C32 / P3-backend Punkt 11)
## — PURE. Wird es beim GASTGEBER Abend (ab 21 Uhr, Stunde reist im POS-Relay
## mit) und haben BEIDE Goobys kaum noch Energie (≤ 10), wandert der
## Besucher-Gooby zur Couch im Wohnzimmer und pennt ein. Diese Datei rechnet
## nur: Regel-Matrix, Couch-Suche im Haus-Snapshot und das NAP-Payload-Schema
## (generisches ROOM_MSG-Relay, kein Server-Hook nötig — rooms.js relayt
## unbekannte Kinds unverändert, geprüft W13B).

## Abend laut §C32: ab 21 Uhr Lokalzeit des Gastgebers.
const ABEND_STUNDE := 21
## „Keine Energie mehr“: Schwelle wie StatsLogic-Erschöpfung, aber bewusst
## eigene Konstante — die Regel gehört dem Besuch, nicht der Pflege.
const ENERGIE_SCHWELLE := 10.0
## Die Couch ist Pflichtmöbel im WOHNZIMMER (FurnitureCatalog pflicht="couch").
const WOHNZIMMER := "living"
const PFLICHT_SLOT_COUCH := "couch"


## Regel-Matrix (§C32): Abend beim Gastgeber UND beide Energien ≤ 10.
## Unbekannte Werte (−1 = noch kein Sync angekommen) schalten die Regel AUS —
## niemand soll wegen fehlender Daten einschlafen.
static func soll_schlafen(host_stunde: int, gast_energie: float, host_energie: float) -> bool:
	if host_stunde < 0 or gast_energie < 0.0 or host_energie < 0.0:
		return false
	if host_stunde < ABEND_STUNDE:
		return false
	return gast_energie <= ENERGIE_SCHWELLE and host_energie <= ENERGIE_SCHWELLE


## Couch im Wohnzimmer des Haus-Snapshots suchen (Grid-Position über die
## Save-Items, Welt-Mitte über den Katalog-Footprint). Kein Couch-Item im
## Snapshot (kaputter Alt-Save)? → {ok:false} — der Aufrufer macht das
## Boden-Nickerchen-Fallback.
static func couch_suchen(snapshot: Dictionary) -> Dictionary:
	var out := {"ok": false, "cell": Vector2i.ZERO, "pos": Vector3.ZERO, "item_id": ""}
	for entry: Variant in VisitSnapshot.room_items(snapshot, WOHNZIMMER):
		if not (entry is Dictionary):
			continue
		var item: Dictionary = entry
		if item.has("wall") or not (item.get("at") is Array):
			continue
		var def := FurnitureCatalog.def(str(item.get("item", "")))
		if str(def.get("pflicht", "")) != PFLICHT_SLOT_COUCH:
			continue
		var at_raw: Array = item["at"]
		if at_raw.size() < 2:
			continue
		var at := Vector2i(int(at_raw[0]), int(at_raw[1]))
		out["ok"] = true
		out["cell"] = at
		out["pos"] = GridData.world_center(at, def["footprint"], int(item.get("rot", 0)))
		out["item_id"] = str(def["id"])
		return out
	return out


## NAP-Body fürs generische Relay: {on, cell:[x,y], boden}. `boden` = Fallback
## ohne Couch (Boden-Nickerchen) — der Host zeigt dann die witzige Bubble.
static func nap_payload(an: bool, cell: Vector2i, boden: bool) -> Dictionary:
	return {"on": an, "cell": [cell.x, cell.y], "boden": boden}


## NAP-Body robust parsen (unbekannte Felder ignorieren, W2c §1).
static func parse_nap(body: Variant) -> Dictionary:
	var out := {"ok": false, "on": false, "cell": Vector2i.ZERO, "boden": false}
	if not (body is Dictionary):
		return out
	var data: Dictionary = body
	if not (data.get("on") is bool):
		return out
	out["ok"] = true
	out["on"] = bool(data["on"])
	out["boden"] = data.get("boden", false) is bool and bool(data.get("boden", false))
	var cell: Variant = data.get("cell")
	if cell is Array and (cell as Array).size() >= 2:
		out["cell"] = Vector2i(int(cell[0]), int(cell[1]))
	return out
