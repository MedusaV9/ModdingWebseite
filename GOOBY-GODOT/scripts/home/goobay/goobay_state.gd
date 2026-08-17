class_name GoobayState
extends RefCounted
## Goobay — Save-Anbindung & Angebotsliste (Doc D §5.4). Additiv im
## `home`-Slice unter `home.goobay`:
##   {"nachfrage": {kategorie: faktor}, "nachfrageTag": "YYYY-MM-DD",
##    "gesperrt": {itemId: tag}}   (Abbruch → erst morgen wieder listbar)
##
## PFLICHTMÖBEL-REGEL (Doc D §2.4, hier WIEDERVERWENDET): Das letzte Bett /
## die letzte Couch / der letzte Kühlschrank taucht in Goobay gar nicht erst
## auf — gezählt wird über PLATZIERTE Items (alle Räume) UND das Lager.

const Economy := preload("res://scripts/logic/economy.gd")


static func default_goobay() -> Dictionary:
	return {"nachfrage": {}, "nachfrageTag": "", "gesperrt": {}}


static func normalize(raw: Variant) -> Dictionary:
	var goobay: Dictionary = raw if raw is Dictionary else default_goobay()
	if not (goobay.get("nachfrage") is Dictionary):
		goobay["nachfrage"] = {}
	if not (goobay.get("gesperrt") is Dictionary):
		goobay["gesperrt"] = {}
	goobay["nachfrageTag"] = str(goobay.get("nachfrageTag", ""))
	return goobay


static func slice(gs: Object) -> Dictionary:
	var raw: Variant = gs.get_value("home.goobay", {})
	return raw if raw is Dictionary else default_goobay()


## Alle platzierten Items aller Räume (für die Pflichtmöbel-Zählung).
static func placed_items(gs: Object) -> Array:
	var out: Array = []
	var rooms: Variant = gs.get_value("home.rooms", {})
	if not (rooms is Dictionary):
		return out
	for room_id: String in rooms:
		var items: Variant = rooms[room_id].get("items", [])
		if items is Array:
			out.append_array(items)
	return out


## Wie viele Exemplare eines Pflicht-Slots besitzt der Spieler insgesamt
## (platziert + eingelagert)?
static func slot_bestand(slot: String, placed: Array, storage: Array) -> int:
	if slot == "":
		return 0
	var total := int(FurnitureCatalog.mandatory_counts(placed).get(slot, 0))
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		if str(FurnitureCatalog.def(str(entry.get("item", ""))).get("pflicht", "")) == slot:
			total += maxi(0, int(entry.get("count", 0)))
	return total


## Doc D §2.4/§5.4: unverkäuflich, solange es das LETZTE Exemplar seines
## Pflicht-Slots ist.
static func ist_pflicht_gesperrt(item_id: String, placed: Array, storage: Array) -> bool:
	var slot := str(FurnitureCatalog.def(item_id).get("pflicht", ""))
	if slot == "":
		return false
	return slot_bestand(slot, placed, storage) <= 1


## Verkaufsliste: Lager-Einträge, die Goobay zeigen darf.
## Liefert [{item, count, name, wert, kategorie, gesperrt_bis}].
static func angebote(gs: Object, heute := "") -> Array:
	var storage := HomeState.storage(gs)
	var placed := placed_items(gs)
	var gesperrt: Dictionary = slice(gs).get("gesperrt", {})
	var out: Array = []
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		var item_id := str(entry.get("item", ""))
		var def := FurnitureCatalog.def(item_id)
		if def.is_empty() or ist_pflicht_gesperrt(item_id, placed, storage):
			continue
		if heute != "" and str(gesperrt.get(item_id, "")) == heute:
			continue
		(
			out
			. append(
				{
					"item": item_id,
					"count": maxi(1, int(entry.get("count", 1))),
					"name": FurnitureCatalog.display_name(def, I18nService.get_locale()),
					"wert": verkaufswert(def),
					"kategorie": str(def.get("kategorie", "deko")),
				}
			)
		)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["item"] < b["item"])
	return out


## Basis-Verkaufswert eines Möbels (Doc D §1.3 `sellBase`; ohne eigenen
## Eintrag sind es 35 % des Kaufpreises).
static func verkaufswert(def: Dictionary) -> int:
	if def.has("verkaufswert") and int(def["verkaufswert"]) > 0:
		return int(def["verkaufswert"])
	return maxi(1, int(round(int(def.get("preis", 0)) * 0.35)))


## Tagesnachfrage einer Kategorie (einmal pro Tag gewürfelt, dann stabil).
static func nachfrage(
	gs: Object, kategorie: String, tag: String, rng: RandomNumberGenerator
) -> float:
	var goobay := slice(gs)
	var tabelle: Dictionary = goobay.get("nachfrage", {})
	if str(goobay.get("nachfrageTag", "")) == tag and tabelle.has(kategorie):
		return float(tabelle[kategorie])
	var wert := GoobayLogic.tages_nachfrage(rng)
	gs.update(
		func(state: Dictionary) -> void:
			var slot: Dictionary = state["home"]["goobay"]
			if str(slot.get("nachfrageTag", "")) != tag:
				slot["nachfrage"] = {}
				slot["nachfrageTag"] = tag
			slot["nachfrage"][kategorie] = wert
	)
	gs.notify_slice_changed("home")
	return wert


## Deal abschließen: Möbel aus dem Lager nehmen, Münzen gutschreiben.
## `versand` = zur Post bringen (+10 %, Doc D §5.4).
static func deal_abschliessen(gs: Object, item_id: String, erloes: int, versand := false) -> int:
	if StorageLogic.count_of(HomeState.storage(gs), item_id) <= 0:
		return 0
	var betrag := GoobayLogic.post_bonus(erloes) if versand else erloes
	gs.update(
		func(state: Dictionary) -> void:
			if StorageLogic.take(state["home"]["storage"], item_id):
				Economy.award(state["economy"], betrag, "goobay")
	)
	gs.notify_slice_changed("home")
	return betrag


## Geplatzte Verhandlung: Item heute nicht mehr listbar + Nachfrage-Malus.
static func abbruch_merken(gs: Object, item_id: String, kategorie: String, tag: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var goobay: Dictionary = state["home"]["goobay"]
			goobay["gesperrt"][item_id] = tag
			var tabelle: Dictionary = goobay["nachfrage"]
			if tabelle.has(kategorie):
				tabelle[kategorie] = GoobayLogic.nachfrage_nach_abbruch(float(tabelle[kategorie]))
	)
	gs.notify_slice_changed("home")
