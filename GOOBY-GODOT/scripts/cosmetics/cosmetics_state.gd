class_name CosmeticsState
extends RefCounted
## Besitz-/Anlege-Logik der Garderobe (CONTENT-A) — PURE Funktionen auf dem
## BESTEHENDEN `cosmetics`-Slice aus save_schema.gd (v5, KEIN Version-Bump,
## keine neuen Keys):
##
##   cosmetics.outfits.owned      Array[String]  (hut/brille/hals/ruecken gemischt)
##   cosmetics.outfits.equipped   {hat, glasses, neck, back}  (null = frei)
##   cosmetics.fur.owned          Array[String]
##   cosmetics.fur.equipped       String (nie leer)
##
## Regeln:
## - EIN Item pro Slot. equip() wirft das bisherige Item desselben Slots raus
##   (und meldet es als "vorher" zurück) — Slot-Konflikte gibt es nicht.
## - Fell ist ein Ein-Slot-Zweig und NIE leer: unequip("fell") fällt auf das
##   Standard-Fell zurück.
## - Unbekannte/nicht besessene Ids werden WEICH ignoriert: Rückgabe
##   {ok=false, grund=...}, der Slice bleibt unangetastet. Nichts crasht,
##   auch wenn ein Pack verschwindet und der Save noch dessen Ids trägt.
## - Fell ist NUR im Shop kaufbar (CosmeticsCatalog.NUR_IM_SHOP): grant() mit
##   einer anderen Quelle als "shop" lehnt Fellfarben ab.
##
## Die Funktionen mutieren den übergebenen Slice IN PLACE (Godot-Dicts sind
## Referenzen) — genau wie economy.gd. GameState-Anbindung: apply_to_state().

const Economy := preload("res://scripts/logic/economy.gd")

const STANDARD_FELL := "cream"
const SLOTS: Array[String] = ["hat", "glasses", "neck", "back"]


## Frischer Slice (identisch zu save_schema.gd — hier nur für Tests/Fallbacks).
static func default_slice() -> Dictionary:
	return {
		"outfits":
		{"owned": [], "equipped": {"hat": null, "glasses": null, "neck": null, "back": null}},
		"fur": {"owned": [STANDARD_FELL], "equipped": STANDARD_FELL},
	}


## Repariert einen kaputten/alten Slice in place und gibt ihn zurück.
static func normalize(slice: Variant) -> Dictionary:
	var out: Dictionary = slice if slice is Dictionary else {}
	if not (out.get("outfits") is Dictionary):
		out["outfits"] = {}
	var outfits: Dictionary = out["outfits"]
	if not (outfits.get("owned") is Array):
		outfits["owned"] = []
	if not (outfits.get("equipped") is Dictionary):
		outfits["equipped"] = {}
	for slot in SLOTS:
		if not outfits["equipped"].has(slot):
			outfits["equipped"][slot] = null
	if not (out.get("fur") is Dictionary):
		out["fur"] = {}
	var fur: Dictionary = out["fur"]
	if not (fur.get("owned") is Array):
		fur["owned"] = []
	if not fur["owned"].has(STANDARD_FELL):
		fur["owned"].append(STANDARD_FELL)
	if not (fur.get("equipped") is String) or str(fur["equipped"]).is_empty():
		fur["equipped"] = STANDARD_FELL
	return out


## Besitzt der Spieler das Item? (Standard-Items gelten immer als besessen.)
static func is_owned(slice: Dictionary, id: String) -> bool:
	var def := CosmeticsCatalog.by_id(id)
	if not def.is_empty() and def["standard"]:
		return true
	var data := normalize(slice)
	if CosmeticsCatalog.kategorie_of(id) == CosmeticsCatalog.FELL:
		return data["fur"]["owned"].has(id)
	return data["outfits"]["owned"].has(id)


## Besessene Ids einer Kategorie ("" = alle Kategorien).
static func owned(slice: Dictionary, kategorie := "") -> Array:
	var data := normalize(slice)
	var out: Array = []
	for id: Variant in data["outfits"]["owned"]:
		if kategorie.is_empty() or CosmeticsCatalog.kategorie_of(str(id)) == kategorie:
			out.append(str(id))
	if kategorie.is_empty() or kategorie == CosmeticsCatalog.FELL:
		for id: Variant in data["fur"]["owned"]:
			out.append(str(id))
	return out


## Angelegtes Item einer Kategorie ("" = Slot frei).
static func equipped(slice: Dictionary, kategorie: String) -> String:
	var data := normalize(slice)
	if kategorie == CosmeticsCatalog.FELL:
		return str(data["fur"]["equipped"])
	var slot: Variant = CosmeticsCatalog.SLOT_BY_KATEGORIE.get(kategorie)
	if slot == null:
		return ""
	var value: Variant = data["outfits"]["equipped"].get(slot)
	return str(value) if value is String else ""


## Kategorie → angelegte Id (leere Slots fehlen NICHT, sie stehen auf "").
## Das ist die Eingabe für CosmeticAttach.apply_equipped().
static func equipped_map(slice: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kategorie in CosmeticsCatalog.KATEGORIEN:
		out[kategorie] = equipped(slice, kategorie)
	return out


## Item in den Besitz geben. `quelle` steuert die Shop-Regel: Fellfarben
## dürfen NUR über quelle="shop" kommen (User-Regel), alles andere darf auch
## als Belohnung/Code/Migration reinfallen.
## Rückgabe: {ok, grund, id}.
static func grant(slice: Dictionary, id: String, quelle := "shop") -> Dictionary:
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty():
		return _nein(id, "unbekannt")
	if (
		CosmeticsCatalog.NUR_IM_SHOP.has(def["kategorie"])
		and quelle != "shop"
		and not def["standard"]
	):
		return _nein(id, "nur_im_shop")
	var data := normalize(slice)
	var liste: Array = (
		data["fur"]["owned"]
		if def["kategorie"] == CosmeticsCatalog.FELL
		else data["outfits"]["owned"]
	)
	if liste.has(id):
		return _nein(id, "schon_besessen")
	liste.append(id)
	return {"ok": true, "grund": "", "id": id}


## Kaufprüfung ohne Nebenwirkung: {ok, grund, preis}.
## grund ∈ unbekannt|schon_besessen|level_zu_niedrig|zu_teuer|"".
static func can_buy(slice: Dictionary, econ: Dictionary, id: String, level := 1) -> Dictionary:
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty():
		return {"ok": false, "grund": "unbekannt", "preis": 0}
	var preis: int = def["preis"]
	if is_owned(slice, id):
		return {"ok": false, "grund": "schon_besessen", "preis": preis}
	if level < int(def["min_level"]):
		return {"ok": false, "grund": "level_zu_niedrig", "preis": preis}
	if not Economy.can_afford(econ, preis):
		return {"ok": false, "grund": "zu_teuer", "preis": preis}
	return {"ok": true, "grund": "", "preis": preis}


## Kauf: bucht die Münzen ab UND legt das Item in den Besitz — beides oder
## nichts. Rückgabe wie can_buy() plus {"gekauft": bool}.
static func buy(slice: Dictionary, econ: Dictionary, id: String, level := 1) -> Dictionary:
	var pruefung := can_buy(slice, econ, id, level)
	pruefung["gekauft"] = false
	if not pruefung["ok"]:
		return pruefung
	if not Economy.spend(econ, pruefung["preis"], "cosmetics"):
		pruefung["ok"] = false
		pruefung["grund"] = "zu_teuer"
		return pruefung
	grant(slice, id, "shop")
	pruefung["gekauft"] = true
	return pruefung


## Item anlegen. Verdrängt automatisch das bisherige Item desselben Slots.
## Rückgabe: {ok, grund, kategorie, vorher}.
static func equip(slice: Dictionary, id: String) -> Dictionary:
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty():
		return _nein(id, "unbekannt")
	if not is_owned(slice, id):
		return _nein(id, "nicht_besessen")
	var kategorie: String = def["kategorie"]
	var vorher := equipped(slice, kategorie)
	if vorher == id:
		return {"ok": true, "grund": "unveraendert", "kategorie": kategorie, "vorher": vorher}
	var data := normalize(slice)
	if kategorie == CosmeticsCatalog.FELL:
		data["fur"]["equipped"] = id
	else:
		data["outfits"]["equipped"][def["slot"]] = id
	return {"ok": true, "grund": "", "kategorie": kategorie, "vorher": vorher}


## Slot leeren. Fell kann nicht leer sein → fällt auf das Standard-Fell.
## Rückgabe: {ok, grund, kategorie, vorher}.
static func unequip(slice: Dictionary, kategorie: String) -> Dictionary:
	var vorher := equipped(slice, kategorie)
	var data := normalize(slice)
	if kategorie == CosmeticsCatalog.FELL:
		if vorher == _standard_fell():
			return {"ok": false, "grund": "unveraendert", "kategorie": kategorie, "vorher": vorher}
		data["fur"]["equipped"] = _standard_fell()
		return {"ok": true, "grund": "", "kategorie": kategorie, "vorher": vorher}
	if not CosmeticsCatalog.SLOT_BY_KATEGORIE.has(kategorie):
		return {"ok": false, "grund": "unbekannt", "kategorie": kategorie, "vorher": ""}
	if vorher.is_empty():
		return {"ok": false, "grund": "unveraendert", "kategorie": kategorie, "vorher": ""}
	data["outfits"]["equipped"][CosmeticsCatalog.SLOT_BY_KATEGORIE[kategorie]] = null
	return {"ok": true, "grund": "", "kategorie": kategorie, "vorher": vorher}


## Ein Tap in der Garderobe: angelegt → ablegen, sonst anlegen.
static func toggle(slice: Dictionary, id: String) -> Dictionary:
	var kategorie := CosmeticsCatalog.kategorie_of(id)
	if not kategorie.is_empty() and equipped(slice, kategorie) == id:
		return unequip(slice, kategorie)
	return equip(slice, id)


## Räumt Ids auf, die es im Katalog nicht (mehr) gibt — z. B. wenn ein Pack
## deinstalliert wurde. Nur die ANGELEGTEN Slots werden geleert; der Besitz
## bleibt stehen, damit ein wiederkehrendes Pack die Sachen zurückbringt.
## Rückgabe: Liste der geräumten Kategorien.
static func prune_equipped(slice: Dictionary) -> Array:
	var geraeumt: Array = []
	for kategorie in CosmeticsCatalog.KATEGORIEN:
		var id := equipped(slice, kategorie)
		if id.is_empty() or CosmeticsCatalog.has(id):
			continue
		var data := normalize(slice)
		if kategorie == CosmeticsCatalog.FELL:
			data["fur"]["equipped"] = _standard_fell()
		else:
			data["outfits"]["equipped"][CosmeticsCatalog.SLOT_BY_KATEGORIE[kategorie]] = null
		geraeumt.append(kategorie)
	return geraeumt


## Wie viele der vier Outfit-Slots sind belegt (Achievement "Full Fit").
static func slots_filled(slice: Dictionary) -> int:
	var count := 0
	for slot in SLOTS:
		var value: Variant = normalize(slice)["outfits"]["equipped"].get(slot)
		if value is String and not str(value).is_empty():
			count += 1
	return count


## GameState-Brücke: `mutator` bekommt (cosmetics_slice, economy_slice) und
## darf beide mutieren; danach feuern die Store-Signale. Rückgabe = das
## Ergebnis des Mutators.
static func apply_to_state(game_state: Object, mutator: Callable) -> Variant:
	if game_state == null or not game_state.has_method("update"):
		return null
	var ergebnis: Array = [null]
	game_state.update(
		func(state: Dictionary) -> void:
			if not (state.get("cosmetics") is Dictionary):
				state["cosmetics"] = default_slice()
			if not (state.get("economy") is Dictionary):
				state["economy"] = Economy.default_slice()
			ergebnis[0] = mutator.call(normalize(state["cosmetics"]), state["economy"])
	)
	if game_state.has_method("notify_slice_changed"):
		game_state.notify_slice_changed("cosmetics")
	return ergebnis[0]


static func _standard_fell() -> String:
	var standards := CosmeticsCatalog.standard_ids(CosmeticsCatalog.FELL)
	return str(standards[0]) if not standards.is_empty() else STANDARD_FELL


static func _nein(id: String, grund: String) -> Dictionary:
	return {
		"ok": false,
		"grund": grund,
		"id": id,
		"kategorie": CosmeticsCatalog.kategorie_of(id),
		"vorher": "",
	}
