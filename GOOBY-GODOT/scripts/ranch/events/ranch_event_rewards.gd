class_name RanchEventRewards
extends RefCounted
## Reward-Gutschrift der Ranch-Random-Events (W13/RANCH) — nutzt NUR
## bestehende Mechanismen: Münzen → `economy.coins` (Muster RQuestState),
## Items → `ranch.wirtschaft.lager` (Heu/Äpfel), Karotten → HAUPT-Inventar
## `inventory.food.carrot` (RanchWirtschaft-Vertrag), Pferde-Freundschaft →
## `ranch.tiere.pferde[id].bindung` (RanchHorseCare.clamp_wert) und der
## Hufschmied-Buff als zeitinjizierter Ablauf-Stempel
## `ranch.events.hufCheckUntil` (Muster GoobyBuffs.until_ms).
##
## Daten kommen aus dem `ranch_reward`-Feld der Event-Defs
## (content/events/data/events.json): {muenzen?, items?, bindung?,
## huf_check_h?, karotten_max?}. Alle Funktionen static, `gs` =
## Duck-Typing (/root/GameState oder Test-Instanz), Zeit wird IMMER
## hereingereicht (now_ms) — kein OS-Clock-Zugriff hier.

const SLICE_ID := "ranch"
const MS_PER_HOUR := 3_600_000


## `ranch_reward` eines Defs ({} wenn keins).
static func reward_von(def: Dictionary) -> Dictionary:
	var raw: Variant = def.get("ranch_reward")
	return raw if raw is Dictionary else {}


## Komplette Gutschrift eines aufgelösten Events. `pferd_id` = Ziel der
## Bindung (leer → erstes Pferd im Bestand). Gibt zurück, was wirklich
## gutgeschrieben wurde: {"muenzen": int, "items": Dictionary,
## "bindung": float, "huf_check_until": int}.
static func anwenden(gs: Object, def: Dictionary, now_ms: int, pferd_id := "") -> Dictionary:
	var out := {"muenzen": 0, "items": {}, "bindung": 0.0, "huf_check_until": 0}
	if gs == null:
		return out
	var reward := reward_von(def)
	if reward.is_empty():
		return out
	var muenzen := maxi(0, int(reward.get("muenzen", 0)))
	var items: Dictionary = reward.get("items") if reward.get("items") is Dictionary else {}
	if muenzen > 0:
		muenzen_gutschreiben(gs, muenzen)
		out["muenzen"] = muenzen
	if not items.is_empty():
		items_ins_lager(gs, items)
		out["items"] = items.duplicate(true)
	var bindung := maxf(0.0, float(reward.get("bindung", 0.0)))
	if bindung > 0.0:
		var ziel := pferd_id if not pferd_id.is_empty() else erstes_pferd_id(gs)
		if not ziel.is_empty():
			bindung_gutschreiben(gs, ziel, bindung)
			out["bindung"] = bindung
	var huf_h := maxf(0.0, float(reward.get("huf_check_h", 0.0)))
	if huf_h > 0.0:
		out["huf_check_until"] = huf_check_setzen(gs, now_ms, huf_h)
	return out


## Münzen aufs Konto (Muster RQuestState._belohnung_anwenden).
static func muenzen_gutschreiben(gs: Object, muenzen: int) -> void:
	if gs == null or muenzen <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("economy") is Dictionary):
				state["economy"] = {}
			var economy: Dictionary = state["economy"]
			economy["coins"] = int(economy.get("coins", 0)) + muenzen
	)
	gs.notify_slice_changed("economy")


## Items (z. B. gerettetes Heu) ins Ranch-Lager `ranch.wirtschaft.lager`.
static func items_ins_lager(gs: Object, items: Dictionary) -> void:
	if gs == null or items.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var lager := _lager_von(state)
			for item: String in items:
				lager[item] = int(lager.get(item, 0)) + maxi(0, int(items[item]))
	)
	gs.notify_slice_changed(SLICE_ID)


## Eine Karotte (Karottenregen) ins HAUPT-Inventar — Karotten leben laut
## RanchWirtschaft-Vertrag in `inventory.food.carrot`, nicht im Ranch-Lager.
static func karotte_gutschreiben(gs: Object, anzahl := 1) -> void:
	if gs == null or anzahl <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("inventory") is Dictionary):
				state["inventory"] = {}
			var inventory: Dictionary = state["inventory"]
			if not (inventory.get("food") is Dictionary):
				inventory["food"] = {}
			var food: Dictionary = inventory["food"]
			food["carrot"] = int(food.get("carrot", 0)) + anzahl
	)
	gs.notify_slice_changed("inventory")


## Pferde-Freundschaft: Bindung des Pferds anheben (0–100 geklemmt,
## RanchHorseCare-Wertebereich; kein Tagesdeckel — Event-Bonus wie der
## Quest-Herz-Bonus bei RNpcState).
static func bindung_gutschreiben(gs: Object, pferd_id: String, wert: float) -> void:
	if gs == null or pferd_id.is_empty() or wert <= 0.0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var pferde := _pferde_von(state)
			if not (pferde.get(pferd_id) is Dictionary):
				return
			var pferd: Dictionary = pferde[pferd_id]
			pferd["bindung"] = RanchHorseCare.clamp_wert(float(pferd.get("bindung", 0.0)) + wert)
	)
	gs.notify_slice_changed(SLICE_ID)


## Hufschmied: Gratis-Huf-Check als Ablauf-Stempel (now + dauer_h).
## Gibt den gesetzten until_ms zurück.
static func huf_check_setzen(gs: Object, now_ms: int, dauer_h: float) -> int:
	var until := now_ms + int(maxf(0.0, dauer_h) * MS_PER_HOUR)
	if gs == null:
		return until
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = {}
			var ranch: Dictionary = state[SLICE_ID]
			if not (ranch.get("events") is Dictionary):
				ranch["events"] = {}
			(ranch["events"] as Dictionary)["hufCheckUntil"] = until
	)
	gs.notify_slice_changed(SLICE_ID)
	return until


## Läuft der Huf-Check-Buff gerade (zeitinjiziert)?
static func huf_check_aktiv(gs: Object, now_ms: int) -> bool:
	if gs == null:
		return false
	return now_ms < int(gs.get_value("ranch.events.hufCheckUntil", 0))


## Erstes Pferd im Bestand (Bindungs-Ziel, "" = keins).
static func erstes_pferd_id(gs: Object) -> String:
	var pferde := RanchState.pferde(gs)
	for id: Variant in pferde.keys():
		return str(id)
	return ""


static func _lager_von(state: Dictionary) -> Dictionary:
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = {}
	var ranch: Dictionary = state[SLICE_ID]
	if not (ranch.get("wirtschaft") is Dictionary):
		ranch["wirtschaft"] = {}
	var wirtschaft: Dictionary = ranch["wirtschaft"]
	if not (wirtschaft.get("lager") is Dictionary):
		wirtschaft["lager"] = {}
	return wirtschaft["lager"]


static func _pferde_von(state: Dictionary) -> Dictionary:
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = {}
	var ranch: Dictionary = state[SLICE_ID]
	if not (ranch.get("tiere") is Dictionary):
		ranch["tiere"] = {}
	var tiere: Dictionary = ranch["tiere"]
	if not (tiere.get("pferde") is Dictionary):
		tiere["pferde"] = {}
	return tiere["pferde"]
