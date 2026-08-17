class_name RanchBauState
extends RefCounted
## Save-Anbindung des Ranch-Baumodus (RW-4) — ADDITIVER Unterschlüssel
## `ranch.bau` im bestehenden ranch-Slice, KEIN Save-Version-Bump.
## RanchState (RANCH-1) erhält fremde Schlüssel verbatim; dieses Modul
## heilt seinen Unterschlüssel deshalb defensiv bei JEDEM Lesen selbst
## (Muster RanchPlaySlices: Self-Heal statt Registry-Eingriff).
##
## ALLE Käufe sind ATOMAR (Muster RanchKauf): Prüfen → in EINEM
## gs.update()-Block Economy.spend + Mutation — oder gar nichts.
## Bauen kostet GOLD (User-Wunsch), niemals Energie.
##
## Struktur ranch.bau:
##   v, items (RanchGridData-Save-Einträge), zonen (freigeschaltete Ids),
##   anlagen {id: {stufe}}, lager {item_id: anzahl — Möbel-Scheune-Käufe},
##   bestandMigriert (Alt-Käufe boxen2/3, reitplatz, weidezaun gemappt),
##   uidSeq.

const Economy := preload("res://scripts/logic/economy.gd")

const SLICE_ID := "ranch"
const KEY := "bau"
const SPEND_REASON := "ranch_bau"

const FEHLER_UNBEKANNT := "unbekannt"
const FEHLER_SCHON_GEBAUT := "schonGebaut"
const FEHLER_ZU_TEUER := "zuTeuer"
const FEHLER_PLATZ := "keinPlatz"
const FEHLER_NICHT_GEBAUT := "nichtGebaut"
const FEHLER_AUSGEBAUT := "vollAusgebaut"
const FEHLER_SCHON_FREI := "schonFrei"

## Standard-Plätze der Bestands-Migration (Start-Zone: x 0..9, y 6..15).
const MIGRATION_PLAETZE := {
	"stallboxen": Vector2i(1, 7),
	"weide": Vector2i(5, 7),
	"parcours": Vector2i(0, 11),
}


static func default_bau() -> Dictionary:
	return {
		"v": 1,
		"items": [],
		"zonen": ["start"],
		"anlagen": {},
		"lager": {},
		"bestandMigriert": false,
		"uidSeq": 1,
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten.
static func normalize_bau(raw: Variant) -> Dictionary:
	var bau: Dictionary = raw.duplicate(true) if raw is Dictionary else default_bau()
	bau["v"] = maxi(1, int(_num(bau.get("v"), 1.0)))
	if not (bau.get("items") is Array):
		bau["items"] = []
	var zonen: Array = bau.get("zonen") if bau.get("zonen") is Array else []
	if not zonen.has("start"):
		zonen.insert(0, "start")
	bau["zonen"] = zonen
	var anlagen_raw: Dictionary = bau.get("anlagen") if bau.get("anlagen") is Dictionary else {}
	var anlagen := {}
	for id: Variant in anlagen_raw:
		var eintrag: Variant = anlagen_raw[id]
		var stufe := int(_num(eintrag.get("stufe") if eintrag is Dictionary else null, 1.0))
		anlagen[str(id)] = {"stufe": maxi(1, stufe)}
	bau["anlagen"] = anlagen
	var lager_raw: Dictionary = bau.get("lager") if bau.get("lager") is Dictionary else {}
	var lager := {}
	for id: Variant in lager_raw:
		var anzahl := maxi(0, int(_num(lager_raw[id], 0.0)))
		if anzahl > 0:
			lager[str(id)] = anzahl
	bau["lager"] = lager
	bau["bestandMigriert"] = bool(bau.get("bestandMigriert", false))
	bau["uidSeq"] = maxi(1, int(_num(bau.get("uidSeq"), 1.0)))
	return bau


## Normalisierter ranch.bau-Stand aus dem GameState.
static func lese(gs: Object) -> Dictionary:
	if gs == null:
		return default_bau()
	return normalize_bau(gs.get_value("ranch.bau", {}))


## Freigeschaltete Zonen-Rechtecke des Standes (für RanchGridData).
static func zonen_rects(bau: Dictionary, balance: Dictionary) -> Array:
	var out: Array = []
	var tabelle := RanchBauKatalog.zonen(balance)
	for id: Variant in bau.get("zonen", []):
		if tabelle.has(str(id)):
			out.append(tabelle[str(id)]["rect"])
	return out


## Grid aus dem Save rekonstruieren: {"grid": RanchGridData, "leftovers"}.
static func grid_von(gs: Object, balance: Dictionary) -> Dictionary:
	var bau := lese(gs)
	return RanchGridData.from_save(
		bau.get("items", []),
		RanchBauKatalog.defs(balance),
		RanchBauKatalog.grid_groesse(balance),
		zonen_rects(bau, balance)
	)


## Aktuelle Stufe einer Anlage (0 = nicht gebaut).
static func anlage_stufe(bau: Dictionary, anlage_id: String) -> int:
	var anlagen: Dictionary = bau.get("anlagen") if bau.get("anlagen") is Dictionary else {}
	if not anlagen.has(anlage_id):
		return 0
	return maxi(1, int(_num(_dict(anlagen, anlage_id).get("stufe"), 1.0)))


## Ein Zell-Item platzieren (Anlage/Deko/Boden). Atomar: Gold + Eintrag.
## Deko aus dem Lager (Möbel-Scheune-Kauf) ist beim Platzieren gratis.
static func platziere(
	gs: Object, item_id: String, at: Vector2i, rot: int, balance := {}
) -> Dictionary:
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var defs := RanchBauKatalog.defs(bal)
	if gs == null or not defs.has(item_id):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "uid": "", "kosten": 0}
	var def: Dictionary = defs[item_id]
	if bool(def.get("kante", false)):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "uid": "", "kosten": 0}
	var bau := lese(gs)
	if def["kategorie"] == "anlage":
		if bool(def.get("upgrade", false)):
			return {"ok": false, "fehler": FEHLER_UNBEKANNT, "uid": "", "kosten": 0}
		if anlage_stufe(bau, item_id) > 0:
			return {"ok": false, "fehler": FEHLER_SCHON_GEBAUT, "uid": "", "kosten": 0}
	var grid: RanchGridData = (
		RanchGridData
		. from_save(bau["items"], defs, RanchBauKatalog.grid_groesse(bal), zonen_rects(bau, bal))["grid"]
	)
	var check := grid.can_place(def, at, rot)
	if not check["ok"]:
		return {"ok": false, "fehler": str(check["reason"]), "uid": "", "kosten": 0}
	var aus_lager: bool = int(_num(_dict(bau, "lager").get(item_id), 0.0)) > 0
	var kosten := 0 if aus_lager else int(def["kosten"])
	return _buche_platzierung(gs, def, {"at": at, "rot": rot}, kosten, aus_lager)


## Einen Zaun auf eine Kante setzen (beliebige Seite, wird normalisiert).
static func platziere_kante(
	gs: Object, item_id: String, cell: Vector2i, seite: String, balance := {}
) -> Dictionary:
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var defs := RanchBauKatalog.defs(bal)
	if gs == null or not defs.has(item_id):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "uid": "", "kosten": 0}
	var def: Dictionary = defs[item_id]
	if not bool(def.get("kante", false)):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "uid": "", "kosten": 0}
	var bau := lese(gs)
	var grid: RanchGridData = (
		RanchGridData
		. from_save(bau["items"], defs, RanchBauKatalog.grid_groesse(bal), zonen_rects(bau, bal))["grid"]
	)
	var check := grid.can_place_kante(def, cell, seite)
	if not check["ok"]:
		return {"ok": false, "fehler": str(check["reason"]), "uid": "", "kosten": 0}
	var norm := RanchGridData.normalize_kante(cell, seite)
	return _buche_platzierung(
		gs, def, {"at": norm["cell"], "kante": norm["seite"]}, int(def["kosten"]), false
	)


## Abriss mit Teilerstattung (abriss_erstattung × bezahlte Kosten, floor).
static func entferne(gs: Object, uid: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var defs := RanchBauKatalog.defs(bal)
	if gs == null:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "erstattung": 0}
	var bau := lese(gs)
	var eintrag := {}
	for kandidat: Variant in bau["items"]:
		if kandidat is Dictionary and str(kandidat.get("uid", "")) == uid:
			eintrag = kandidat
			break
	var item_id := str(eintrag.get("item", ""))
	if eintrag.is_empty() or not defs.has(item_id):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "erstattung": 0}
	var def: Dictionary = defs[item_id]
	var bezahlt := int(def["kosten"])
	if def["kategorie"] == "anlage":
		var stufen := RanchBauKatalog.stufen_kosten(bal, item_id)
		var stufe := anlage_stufe(bau, item_id)
		bezahlt = 0
		for i in mini(stufe, stufen.size()):
			bezahlt += maxi(0, int(_num(stufen[i], 0.0)))
	var erstattung := int(floor(bezahlt * RanchBauKatalog.abriss_erstattung(bal)))
	gs.update(
		func(state: Dictionary) -> void:
			var b := bau_im_state(state)
			var neu: Array = []
			for kandidat: Variant in b["items"]:
				if not (kandidat is Dictionary) or str(kandidat.get("uid", "")) != uid:
					neu.append(kandidat)
			b["items"] = neu
			if def["kategorie"] == "anlage":
				(b["anlagen"] as Dictionary).erase(item_id)
			if erstattung > 0:
				Economy.award(state["economy"], erstattung, SPEND_REASON)
	)
	gs.notify_slice_changed(SLICE_ID)
	return {"ok": true, "fehler": "", "erstattung": erstattung}


## Nächste Ausbaustufe einer Anlage kaufen. Beim Upgrade-Typ (weidezaun)
## kauft Stufe 1 direkt — er hat keine Platzierung.
static func ausbauen(gs: Object, anlage_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var stufen := RanchBauKatalog.stufen_kosten(bal, anlage_id)
	if gs == null or stufen.is_empty():
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "stufe": 0, "kosten": 0}
	var defs := RanchBauKatalog.defs(bal)
	var ist_upgrade := bool(_dict(defs, anlage_id).get("upgrade", false))
	var bau := lese(gs)
	var stufe := anlage_stufe(bau, anlage_id)
	if stufe == 0 and not ist_upgrade:
		return {"ok": false, "fehler": FEHLER_NICHT_GEBAUT, "stufe": 0, "kosten": 0}
	if stufe >= stufen.size():
		return {"ok": false, "fehler": FEHLER_AUSGEBAUT, "stufe": stufe, "kosten": 0}
	var kosten := RanchBauKatalog.naechste_stufe_kosten(bal, anlage_id, stufe)
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], kosten, SPEND_REASON):
				return
			bezahlt[0] = true
			var b := bau_im_state(state)
			b["anlagen"][anlage_id] = {"stufe": stufe + 1}
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "stufe": stufe, "kosten": kosten}
	gs.notify_slice_changed(SLICE_ID)
	return {"ok": true, "fehler": "", "stufe": stufe + 1, "kosten": kosten}


## Eine Grid-Zone (nord/ost) freikaufen.
static func zone_freischalten(gs: Object, zone_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var tabelle := RanchBauKatalog.zonen(bal)
	if gs == null or not tabelle.has(zone_id):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "kosten": 0}
	var bau := lese(gs)
	if (bau["zonen"] as Array).has(zone_id):
		return {"ok": false, "fehler": FEHLER_SCHON_FREI, "kosten": 0}
	var kosten := int(tabelle[zone_id]["kosten"])
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], kosten, SPEND_REASON):
				return
			bezahlt[0] = true
			var b := bau_im_state(state)
			if not (b["zonen"] as Array).has(zone_id):
				(b["zonen"] as Array).append(zone_id)
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "kosten": kosten}
	gs.notify_slice_changed(SLICE_ID)
	return {"ok": true, "fehler": "", "kosten": kosten}


## Deko ins Bau-Lager legen (Möbel-Scheune liefert hierher) — KEIN Kauf,
## die Abbuchung macht DorfWirtschaft im selben update-Block des Ladens.
static func lager_hinzu(bau: Dictionary, item_id: String, anzahl := 1) -> void:
	var lager: Dictionary = bau.get("lager") if bau.get("lager") is Dictionary else {}
	lager[item_id] = int(_num(lager.get(item_id), 0.0)) + maxi(1, anzahl)
	bau["lager"] = lager


## Bestands-Migration (idempotent): Alt-Käufe aus ranch.wirtschaft.ausbau
## (boxen 1..3, reitplatz, weidezaun) werden 1:1 auf Grid-Anlagen gemappt —
## KEIN Fortschrittsverlust (IDEAS-3 §6). Stufe-1-Anlagen „inkl.“
## (Stallboxen, Weide) zieht die Migration immer ein.
static func migriere_bestand(gs: Object, balance := {}) -> bool:
	if gs == null:
		return false
	var bau := lese(gs)
	if bool(bau.get("bestandMigriert", false)):
		return false
	var bal := balance if not balance.is_empty() else RanchBauKatalog.load_balance()
	var defs := RanchBauKatalog.defs(bal)
	var alt: Dictionary = gs.get_value("ranch.wirtschaft.ausbau", {})
	if not (alt is Dictionary):
		alt = {}
	var plan: Array = []
	plan.append({"id": "stallboxen", "stufe": clampi(int(_num(alt.get("boxen"), 1.0)), 1, 4)})
	plan.append({"id": "weide", "stufe": 1})
	if alt.get("reitplatz") is bool and alt["reitplatz"]:
		plan.append({"id": "parcours", "stufe": 1})
	gs.update(
		func(state: Dictionary) -> void:
			var b := bau_im_state(state)
			if bool(b.get("bestandMigriert", false)):
				return
			for schritt: Dictionary in plan:
				var id: String = schritt["id"]
				if (b["anlagen"] as Dictionary).has(id) or not defs.has(id):
					continue
				var at: Vector2i = MIGRATION_PLAETZE.get(id, Vector2i(0, 6))
				var uid := "rb-%06d" % int(b["uidSeq"])
				b["uidSeq"] = int(b["uidSeq"]) + 1
				(b["items"] as Array).append({"uid": uid, "item": id, "at": [at.x, at.y], "rot": 0})
				b["anlagen"][id] = {"stufe": int(schritt["stufe"])}
			if alt.get("weidezaun") is bool and alt["weidezaun"]:
				if not (b["anlagen"] as Dictionary).has("weidezaun"):
					b["anlagen"]["weidezaun"] = {"stufe": 1}
			b["bestandMigriert"] = true
	)
	gs.notify_slice_changed(SLICE_ID)
	return true


# ── intern ───────────────────────────────────────────────────────────────────


## Gemeinsames atomares Buchen einer Platzierung (Zelle ODER Kante).
static func _buche_platzierung(
	gs: Object, def: Dictionary, platz: Dictionary, kosten: int, aus_lager: bool
) -> Dictionary:
	var item_id := str(def["id"])
	var bezahlt := [false]
	var uid_box := [""]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], kosten, SPEND_REASON):
				return
			bezahlt[0] = true
			var b := bau_im_state(state)
			var uid := "rb-%06d" % int(b["uidSeq"])
			b["uidSeq"] = int(b["uidSeq"]) + 1
			uid_box[0] = uid
			var at: Vector2i = platz["at"]
			var entry := {"uid": uid, "item": item_id, "at": [at.x, at.y]}
			if platz.has("kante"):
				entry["kante"] = str(platz["kante"])
			else:
				entry["rot"] = posmod(int(platz.get("rot", 0)), 4)
			(b["items"] as Array).append(entry)
			if def["kategorie"] == "anlage":
				b["anlagen"][item_id] = {"stufe": 1}
			if aus_lager:
				var lager: Dictionary = b["lager"]
				var rest := int(_num(lager.get(item_id), 0.0)) - 1
				if rest > 0:
					lager[item_id] = rest
				else:
					lager.erase(item_id)
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "uid": "", "kosten": kosten}
	gs.notify_slice_changed(SLICE_ID)
	return {"ok": true, "fehler": "", "uid": str(uid_box[0]), "kosten": kosten}


## ranch.bau innerhalb eines gs.update()-Blocks holen (und normalisieren).
static func bau_im_state(state: Dictionary) -> Dictionary:
	var ranch: Dictionary = state.get(SLICE_ID) if state.get(SLICE_ID) is Dictionary else {}
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = ranch
	var bau := normalize_bau(ranch.get(KEY))
	ranch[KEY] = bau
	return bau


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
