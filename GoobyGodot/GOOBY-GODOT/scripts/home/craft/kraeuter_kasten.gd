class_name KraeuterKasten
extends RefCounted
## W15/MARKT — Wochenertrag des Kräuterkastens (Craft-Rezept
## r_kraeuterkasten, Markt-Synergie): jeder Kasten im Besitz (Lager ODER
## im Raum platziert) produziert wöchentlich 1 Kräuterbund (`kraeuter`,
## inventory.items) — DIE Craft-Ware des eigenen Marktstands
## (markt_waren.json). PURE + zeitinjiziert: alle Funktionen nehmen
## `unix_s`, nichts liest die Systemuhr.
##
## Save (home-Slice, additiv — HomeState.normalize_slice erhält fremde
## Keys VERBATIM): home.kraeuterkasten = {"letzteErnteUnix": int}.
## Der Zyklus ankert beim ERSTEN schoepfe() nach Besitz (Ertrag 0) und
## rückt danach nur um GANZE Wochen vor — Teilwochen verfallen nie.

const ITEM_ID := "kraeuterkasten"
const WARE_ID := "kraeuter"
const WOCHE_S := 7 * 86400
## Länger nicht vorbeigeschaut? Mehr als 2 Wochen Rückstand sammelt ein
## Kasten nicht an (freundlicher Deckel statt Kräuter-Lawine).
const MAX_WOCHEN := 2


## Kästen im Besitz: im Möbellager + in Räumen platziert.
static func anzahl(gs: Object) -> int:
	if gs == null:
		return 0
	var storage: Variant = gs.get_value("home.storage", [])
	var summe := StorageLogic.count_of(storage if storage is Array else [], ITEM_ID)
	var rooms: Variant = gs.get_value("home.rooms", {})
	if rooms is Dictionary:
		for room_id: Variant in rooms:
			var raum: Variant = rooms[room_id]
			if not (raum is Dictionary):
				continue
			var items: Variant = (raum as Dictionary).get("items", [])
			if not (items is Array):
				continue
			for eintrag: Variant in items:
				if eintrag is Dictionary and str(eintrag.get("item", "")) == ITEM_ID:
					summe += 1
	return summe


## Anker des Wochen-Zyklus (0 = noch nie geschöpft).
static func letzte_ernte_unix(gs: Object) -> int:
	if gs == null:
		return 0
	var raw: Variant = gs.get_value("home.kraeuterkasten", {})
	if raw is Dictionary:
		return maxi(0, int((raw as Dictionary).get("letzteErnteUnix", 0)))
	return 0


## Volle Wochen seit dem Anker (gedeckelt) — PURE Kernrechnung für Tests.
static func wochen_seit(letzte_unix: int, unix_s: int) -> int:
	if letzte_unix <= 0 or unix_s <= letzte_unix:
		return 0
	return clampi((unix_s - letzte_unix) / WOCHE_S, 0, MAX_WOCHEN)


## Abholbereite Kräuterbünde zum Zeitpunkt `unix_s` (reine Sicht).
static func faellig(gs: Object, unix_s: int) -> int:
	var kaesten := anzahl(gs)
	if kaesten <= 0:
		return 0
	return wochen_seit(letzte_ernte_unix(gs), unix_s) * kaesten


## Ertrag buchen: fällige Kräuterbünde in inventory.items legen und den
## Anker um GANZE Wochen vorrücken (Rest der Woche läuft weiter). Beim
## ersten Ruf nach Besitz wird nur der Anker gesetzt (Ertrag 0).
## Rückgabe = gutgeschriebene Bünde.
static func schoepfe(gs: Object, unix_s: int) -> int:
	if gs == null or anzahl(gs) <= 0:
		return 0
	var letzte := letzte_ernte_unix(gs)
	var wochen := wochen_seit(letzte, unix_s)
	var ertrag := wochen * anzahl(gs)
	if letzte > 0 and wochen <= 0:
		return 0
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("home") is Dictionary):
				state["home"] = {}
			var home: Dictionary = state["home"]
			home["kraeuterkasten"] = {
				"letzteErnteUnix": unix_s if letzte <= 0 else letzte + wochen * WOCHE_S,
			}
			if ertrag <= 0:
				return
			if not (state.get("inventory") is Dictionary):
				state["inventory"] = {}
			var inventory: Dictionary = state["inventory"]
			if not (inventory.get("items") is Dictionary):
				inventory["items"] = {}
			var items: Dictionary = inventory["items"]
			items[WARE_ID] = maxi(0, int(items.get(WARE_ID, 0))) + ertrag
	)
	gs.notify_slice_changed("home")
	return ertrag
