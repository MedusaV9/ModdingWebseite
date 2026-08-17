class_name ZahnbuersteState
extends RefCounted
## Zahnbürsten-Haltbarkeit (W13C GOOBYMAN, Doc H §6.4): der alte Einmal-Gag
## „Bürste bricht mit Balance-Chance“ wird zur Zustandsmaschine
## neu → benutzt → ausgefranst → GEBROCHEN. Jede Putz-Session würfelt
## (RNG wird IMMER hereingereicht) gegen die bestehende Balance-Pack-Chance
## `zahnbuersten_bruch_chance` (BadState.brush_break_chance — remote-änderbar
## ohne .ipa); ein Treffer = ein Abnutzungspunkt. Wie viele Punkte eine
## Bürste aushält, sagt ihre `haltbarkeit` im GOOBYMAN-Sortiment (bessere
## Qualität = mehr Punkte). Gebrochen = Zähneputzen blockiert, bis eine neue
## Bürste aus inventory.items aktiviert wird (Kauf beim GOOBYMAN).
##
## Eigener Save-Slice "zahnbuerste" (W1d-Slice-Registry, der `gooby`-Slice
## ist FROZEN): {typ, abnutzung, bruchInfoGesehen}. Migration: Bestands-Saves
## OHNE Slice bekommen den Default = intakte Standard-Bürste (kein Soft-Lock).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "zahnbuerste"

const ZUSTAND_NEU := "neu"
const ZUSTAND_BENUTZT := "benutzt"
const ZUSTAND_AUSGEFRANST := "ausgefranst"
const ZUSTAND_GEBROCHEN := "gebrochen"

## Inventar-Präfix der Ersatzbürsten (inventory.items, Kauf beim GOOBYMAN).
const ITEM_PREFIX := "zahnbuerste_"
## Fallback, wenn das Sortiment einen Bürsten-Typ nicht (mehr) kennt.
const HALTBARKEIT_FALLBACK := 3

static var _registered := false


## Idempotent — Muster BadState (zahnputz.setup ruft es zusätzlich lazy;
## unbekannte Slices überleben merge_defaults ohnehin unverändert).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"typ": "standard", "abnutzung": 0, "bruchInfoGesehen": false}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	var typ := str(slice.get("typ", "standard"))
	slice["typ"] = typ if not typ.is_empty() else "standard"
	slice["abnutzung"] = maxi(0, int(slice.get("abnutzung", 0)))
	slice["bruchInfoGesehen"] = _truthy(slice.get("bruchInfoGesehen"))
	return slice


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


# ── pure Zustandsmaschine (headless testbar, RNG/Chance injiziert) ───────────


## Zustand aus Abnutzungspunkten: 0 = neu, haltbarkeit = gebrochen, der
## letzte Punkt davor = ausgefranst, dazwischen = benutzt.
static func zustand(abnutzung: int, haltbarkeit: int) -> String:
	var max_punkte := maxi(1, haltbarkeit)
	var punkte := maxi(0, abnutzung)
	if punkte >= max_punkte:
		return ZUSTAND_GEBROCHEN
	if punkte <= 0:
		return ZUSTAND_NEU
	if punkte == max_punkte - 1:
		return ZUSTAND_AUSGEFRANST
	return ZUSTAND_BENUTZT


## Eine Putz-Session: roll01 ∈ [0..1) gegen die Balance-Chance — Treffer
## nutzt EINEN Punkt ab (gleiche Clamp-Semantik wie BadState.brush_breaks).
static func naechste_abnutzung(abnutzung: int, roll01: float, chance: float) -> int:
	if roll01 < clampf(chance, 0.0, 1.0):
		return maxi(0, abnutzung) + 1
	return maxi(0, abnutzung)


## Haltbarkeit eines Bürsten-Typs aus dem Sortiment (remote-überschreibbar
## übers Pack-System, s. GoobymanKatalog.waren). Unbekannt → Fallback 3.
static func haltbarkeit_von(typ: String, waren: Array) -> int:
	for ware: Variant in waren:
		if ware is Dictionary and str(ware.get("id", "")) == ITEM_PREFIX + typ:
			return maxi(1, int(ware.get("haltbarkeit", HALTBARKEIT_FALLBACK)))
	return HALTBARKEIT_FALLBACK


# ── GameState-Glue ───────────────────────────────────────────────────────────


static func slice_of(state: Dictionary) -> Dictionary:
	return normalize_slice(state.get(SLICE_ID))


static func aktueller_zustand(gs: Object, waren: Array = []) -> String:
	var slice := slice_of(_state(gs))
	var liste := waren if not waren.is_empty() else GoobymanKatalog.waren()
	return zustand(int(slice["abnutzung"]), haltbarkeit_von(str(slice["typ"]), liste))


static func ist_gebrochen(gs: Object) -> bool:
	return aktueller_zustand(gs) == ZUSTAND_GEBROCHEN


## Putz-Session verbuchen. roll01 kommt vom Aufrufer (zahnputz._rng bzw.
## Test-Konstante); chance < 0 = Balance-Pack-Chance wie bisher
## (`zahnbuersten_bruch_chance` via BadState — remote-änderbar).
## Rückgabe {"abgenutzt", "gebrochen", "erster_bruch", "zustand"}.
static func putz_session(gs: Object, roll01: float, chance := -1.0) -> Dictionary:
	var wirksam := chance if chance >= 0.0 else BadState.brush_break_chance()
	var waren := GoobymanKatalog.waren()
	var ergebnis := {
		"abgenutzt": false,
		"gebrochen": false,
		"erster_bruch": false,
		"zustand": ZUSTAND_NEU,
	}
	gs.update(
		func(state: Dictionary) -> void:
			var slice := _ensure(state)
			var haltbarkeit := haltbarkeit_von(str(slice["typ"]), waren)
			var vorher := int(slice["abnutzung"])
			if zustand(vorher, haltbarkeit) == ZUSTAND_GEBROCHEN:
				ergebnis["gebrochen"] = true
				ergebnis["zustand"] = ZUSTAND_GEBROCHEN
				return
			var nachher := naechste_abnutzung(vorher, roll01, wirksam)
			slice["abnutzung"] = nachher
			ergebnis["abgenutzt"] = nachher != vorher
			ergebnis["zustand"] = zustand(nachher, haltbarkeit)
			if ergebnis["zustand"] == ZUSTAND_GEBROCHEN:
				ergebnis["gebrochen"] = true
				if not _truthy(slice.get("bruchInfoGesehen")):
					slice["bruchInfoGesehen"] = true
					ergebnis["erster_bruch"] = true
	)
	gs.notify_slice_changed(SLICE_ID)
	return ergebnis


## Ersatzbürsten im Inventar ({typ: anzahl}, nur anzahl > 0).
static func ersatz_im_inventar(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var inventory: Variant = state.get("inventory")
	if not (inventory is Dictionary) or not (inventory.get("items") is Dictionary):
		return out
	var items: Dictionary = inventory["items"]
	for key: Variant in items:
		var id := str(key)
		if id.begins_with(ITEM_PREFIX) and int(items[id]) > 0:
			out[id.trim_prefix(ITEM_PREFIX)] = int(items[id])
	return out


## Beste Ersatzbürste (höchste Haltbarkeit) aus dem Inventar einspannen:
## verbraucht das Item, setzt typ + abnutzung 0. Rückgabe der aktivierte
## Typ ("" = kein Ersatz da — Zähneputzen bleibt blockiert).
static func aktiviere_ersatz(gs: Object) -> String:
	var waren := GoobymanKatalog.waren()
	var aktiviert := {"typ": ""}
	gs.update(
		func(state: Dictionary) -> void:
			var vorrat := ersatz_im_inventar(state)
			var bester := ""
			var beste_haltbarkeit := -1
			for typ: String in vorrat:
				var punkte := haltbarkeit_von(typ, waren)
				if punkte > beste_haltbarkeit:
					beste_haltbarkeit = punkte
					bester = typ
			if bester.is_empty():
				return
			var items: Dictionary = state["inventory"]["items"]
			items[ITEM_PREFIX + bester] = int(items.get(ITEM_PREFIX + bester, 0)) - 1
			if int(items[ITEM_PREFIX + bester]) <= 0:
				items.erase(ITEM_PREFIX + bester)
			var slice := _ensure(state)
			slice["typ"] = bester
			slice["abnutzung"] = 0
			aktiviert["typ"] = bester
	)
	if not str(aktiviert["typ"]).is_empty():
		gs.notify_slice_changed(SLICE_ID)
	return str(aktiviert["typ"])


static func _state(gs: Object) -> Dictionary:
	if gs != null and gs.has_method("state"):
		return gs.state()
	return {}


static func _ensure(state: Dictionary) -> Dictionary:
	state[SLICE_ID] = normalize_slice(state.get(SLICE_ID))
	return state[SLICE_ID]


## Strikt-bool (String == bool wäre in GDScript 4 ein Laufzeitfehler).
static func _truthy(value: Variant) -> bool:
	return value is bool and value
