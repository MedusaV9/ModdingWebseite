class_name UrlaubsAktivitaeten
extends RefCounted
## W15/URLAUB — PURE Zustands-Maschinen der Vor-Ort-Erlebnisse (Dictionaries
## rein, Dictionaries raus; Zeit IMMER injiziert — Muster TaxiLogic):
##
## 1. TAP-SPOTS (strand: Muscheln sammeln, berge: Bergblumen finden):
##    n Spots, jeder zählt genau EINMAL; fertig, wenn alle getippt sind.
## 2. SOUVENIR-SPOT: ein tägliches Fundstück (UTC-Tagesindex-Cooldown über
##    `vacation.souvenirTag`); Gutschrift läuft ADDITIV über die
##    bestehenden APIs (Economy.award + inventory.items — Aufrufer).
## 3. BESTELL-GAG (stadt: Café-Kellner): Rotation über die Quatsch-
##    Bestellungen (`urlaub.bestellung`-Array) — reine Index-Mathematik.

const Vacation := preload("res://scripts/logic/vacation.gd")
const Economy := preload("res://scripts/logic/economy.gd")
const Stats := preload("res://scripts/logic/stats.gd")

## Standard-Anzahl Tap-Spots (Doc-Wunsch: „5 Tap-Spots am Strand“).
const TAP_ANZAHL := 5

## Kleine Boni (Kuschel-Feature — bewusst klein, kein Farm-Loop).
const FUN_STREICHELN := 4.0
const FUN_MINI_FERTIG := 6.0
const FUN_SOUVENIR := 3.0

## Tägliches Fundstück: Münzen obendrauf (additiv zu den souvenirCoins
## der Abholung — Reason wie reise_app: "souvenir").
const SOUVENIR_COINS := 5

## ---------------------------------------------------------- Tap-Spots


## Frischer Tap-Zustand: {gesamt, getroffen: {index: true}}.
static func tap_neu(anzahl: int = TAP_ANZAHL) -> Dictionary:
	return {"gesamt": maxi(1, anzahl), "getroffen": {}}


## Spot `index` tippen. Rückgabe {ok, fertig, rest}; ok=false bei
## Doppel-Tipp oder Index außerhalb (Zustand bleibt dann unberührt).
static func tap_tippe(zustand: Dictionary, index: int) -> Dictionary:
	var gesamt := int(zustand.get("gesamt", 0))
	var getroffen: Dictionary = zustand.get("getroffen", {})
	var rest := gesamt - getroffen.size()
	if index < 0 or index >= gesamt or bool(getroffen.get(index, false)):
		return {"ok": false, "fertig": rest <= 0, "rest": rest}
	getroffen[index] = true
	zustand["getroffen"] = getroffen
	rest = gesamt - getroffen.size()
	return {"ok": true, "fertig": rest <= 0, "rest": rest}


static func tap_fertig(zustand: Dictionary) -> bool:
	var getroffen: Dictionary = zustand.get("getroffen", {})
	return getroffen.size() >= int(zustand.get("gesamt", 0))


## ------------------------------------------------------ Souvenir-Spot


## UTC-Tagesindex eines Zeitpunkts (Cooldown-Einheit des Fundstücks).
static func souvenir_tag(now_ms: int) -> int:
	return int(floor(float(now_ms) / float(Vacation.MS_PER_DAY)))


## Liegt heute noch ein Fundstück am Spot? (Ein Fund pro UTC-Tag.)
static func souvenir_bereit(v: Dictionary, now_ms: int) -> bool:
	return int(v.get("souvenirTag", 0)) != souvenir_tag(now_ms)


## Fundstück-Definition eines Ziels: {item_id, coins}. Das Item landet
## additiv in inventory.items (Muster OrtScene-Dialog-Effekt "item").
static func souvenir_fund(dest_id: String) -> Dictionary:
	return {"item_id": "souvenir_%s" % dest_id, "coins": SOUVENIR_COINS}


## Fund einlösen (atomar über gs.update): Tages-Latch stempeln, Item +
## Münzen additiv gutschreiben. Rückgabe {ok, item_id, coins}.
static func souvenir_einloesen(gs: Object, dest_id: String, now_ms: int) -> Dictionary:
	var keiner := {"ok": false, "item_id": "", "coins": 0}
	if gs == null:
		return keiner
	var v := Vacation.slice_of(gs.state())
	if not souvenir_bereit(v, now_ms):
		return keiner
	var fund := souvenir_fund(dest_id)
	gs.update(
		func(state: Dictionary) -> void:
			var slice := Vacation.slice_of(state)
			slice["souvenirTag"] = souvenir_tag(now_ms)
			state["vacation"] = slice
			var items: Dictionary = state["inventory"]["items"]
			var item_id := str(fund["item_id"])
			items[item_id] = int(items.get(item_id, 0)) + 1
			Economy.award(state["economy"], int(fund["coins"]), "souvenir")
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("vacation")
	return {"ok": true, "item_id": str(fund["item_id"]), "coins": int(fund["coins"])}


## -------------------------------------------------------- Bestell-Gag


## Nächste Quatsch-Bestellung (Rotation, nie leer bei anzahl > 0):
## Rückgabe der Index 0..anzahl-1 für `urlaub.bestellung`-Einträge.
static func bestellung_index(zaehler: int, anzahl: int) -> int:
	if anzahl <= 0:
		return -1
	return posmod(zaehler, anzahl)


## ------------------------------------------------------------- Boni


## Kleiner Spaß-Bonus über die BESTEHENDE Stats-Mathematik (clamp 0..100).
static func fun_bonus(gs: Object, delta: float) -> void:
	if gs == null or delta <= 0.0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Dictionary = state.get("gooby", {})
			var stats: Dictionary = gooby.get("stats", {})
			gooby["stats"] = Stats.apply_deltas(stats, {"fun": delta})
			state["gooby"] = gooby
	)
