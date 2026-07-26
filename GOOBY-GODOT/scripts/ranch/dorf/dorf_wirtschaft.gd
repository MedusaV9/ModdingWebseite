class_name DorfWirtschaft
extends RefCounted
## Laden-Wirtschaft von Hufingen (RW-4) — atomare Käufe/Verkäufe über dem
## GameState (Duck-Typing, Muster RanchKauf/RanchBauState): erst prüfen,
## dann Economy.spend/award + Mutation in EINEM gs.update()-Block — oder
## gar nichts. Alles kostet GOLD, niemals Energie.
##
## Läden und ihre Ziele:
## - Futterhof: Heu → ranch.wirtschaft.lager (Heulager-Kapazität gilt!),
##   Hafer/Leckerli → ranch.dorf.futter; Ankauf von Heu/Äpfeln UNTER dem
##   Kaufpreis (Kaufen→Verkaufen macht nie Gewinn).
## - Reitladen: Sättel/Trensen/Decken über RanchWirtschaft.gear_kaufen
##   (EINE Wahrheit mit dem Hof-Laden von RANCH-2).
## - Möbel-Scheune: Ranch-Deko → ranch.bau.lager (Platzieren dann gratis),
##   Haus-Möbel → home.storage (Kapazität via StorageLogic).
## - Schmiede: Hufeisen-Cosmetics → ranch.dorf.hufeisen (einmalig je Sorte).

const Economy := preload("res://scripts/logic/economy.gd")
const StorageLogic := preload("res://scripts/home/storage_logic.gd")
const FurnitureCatalog := preload("res://scripts/home/furniture_catalog.gd")
const RanchPlaySlices := preload("res://scripts/ranch/data/ranch_play_slices.gd")

const SPEND_REASON := "ranch_dorf"

const FEHLER_UNBEKANNT := "unbekannt"
const FEHLER_ZU_TEUER := "zuTeuer"
const FEHLER_LAGER_VOLL := "lagerVoll"
const FEHLER_LAGER_LEER := "lagerLeer"
const FEHLER_SCHON_GEKAUFT := "schonGekauft"
const FEHLER_KEIN_LAGER := "keinLager"
const FEHLER_KEIN_PFERD := "keinPferd"
const FEHLER_NICHT_GEKAUFT := "nichtGekauft"


## Futterhof: eine Ware kaufen (heu/heu_bund/hafer/leckerli). Heu landet im
## Ranch-Lager und respektiert die Heulager-Kapazität (RanchBauEffekte).
static func futter_kaufen(
	gs: Object, ware_id: String, balance := {}, bau_balance := {}
) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var ware := _ware(DorfKatalog.futter_waren(bal), ware_id)
	if gs == null or ware.is_empty():
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var preis := maxi(0, int(_num(ware.get("preis"), 0.0)))
	var menge := maxi(1, int(_num(ware.get("menge"), 1.0)))
	var ist_heu := ware_id.begins_with("heu")
	if ist_heu:
		var bbal := bau_balance if not bau_balance.is_empty() else RanchBauKatalog.load_balance()
		var kapazitaet := RanchBauEffekte.heu_kapazitaet(RanchBauState.lese(gs), bbal)
		if _heu_bestand(gs) + menge > kapazitaet:
			return {"ok": false, "fehler": FEHLER_LAGER_VOLL, "preis": preis}
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			if ist_heu:
				var lager := _wirtschaft_lager_im_state(state)
				lager["heu"] = int(_num(lager.get("heu"), 0.0)) + menge
			else:
				var futter: Dictionary = RanchDorfState.dorf_im_state(state)["futter"]
				futter[ware_id] = int(_num(futter.get(ware_id), 0.0)) + menge
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "preis": preis, "menge": menge}


## Futterhof-Ankauf: Heu/Äpfel aus dem Ranch-Lager verkaufen (Preis UNTER
## dem Einkauf — ehrliche Senke, kein Gold-Dupe).
static func ernte_verkaufen(gs: Object, art: String, anzahl: int, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var ankauf := DorfKatalog.futter_ankauf(bal)
	if gs == null or anzahl <= 0 or not ankauf.has(art):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "erloes": 0}
	var lager: Variant = gs.get_value("ranch.wirtschaft.lager", {})
	var bestand := int(_num((lager if lager is Dictionary else {}).get(art), 0.0))
	if bestand < anzahl:
		return {"ok": false, "fehler": FEHLER_LAGER_LEER, "erloes": 0}
	var erloes := maxi(0, int(_num(ankauf.get(art), 0.0))) * anzahl
	gs.update(
		func(state: Dictionary) -> void:
			var l := _wirtschaft_lager_im_state(state)
			l[art] = maxi(0, int(_num(l.get(art), 0.0)) - anzahl)
			if erloes > 0:
				Economy.award(state["economy"], erloes, SPEND_REASON)
	)
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "erloes": erloes}


## Reitladen: Ausrüstung kaufen ("sattel_rot" ...). Regeln + Preise kommen
## aus RanchWirtschaft (EINE Wahrheit); hier nur die atomare Buchung.
static func gear_kaufen(gs: Object, gear_id: String) -> Dictionary:
	if gs == null:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var wbal := RanchWirtschaft.load_balance()
	var wirtschaft := RanchPlaySlices.normalize_wirtschaft(gs.get_value("ranch.wirtschaft", {}))
	var coins := int(_num(gs.get_value("economy.coins", 0), 0.0))
	var ergebnis := RanchWirtschaft.gear_kaufen(wirtschaft, coins, gear_id, wbal)
	if not bool(ergebnis["ok"]):
		return {"ok": false, "fehler": str(ergebnis["fehler"]), "preis": 0}
	var preis := coins - int(ergebnis["coins"])
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if preis > 0 and not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			if not (state.get("ranch") is Dictionary):
				state["ranch"] = {}
			state["ranch"]["wirtschaft"] = ergebnis["wirtschaft"]
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "preis": preis}


## Möbel-Scheune: Ranch-Deko kaufen → ranch.bau.lager (Platzieren im
## Baumodus ist dann gratis). Preis kommt aus dem Bau-Katalog (EINE Wahrheit).
static func deko_kaufen(
	gs: Object, deko_id: String, balance := {}, bau_balance := {}
) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var bbal := bau_balance if not bau_balance.is_empty() else RanchBauKatalog.load_balance()
	var def := _def(RanchBauKatalog.defs(bbal), deko_id)
	var im_sortiment := DorfKatalog.ranch_deko_ids(bal).has(deko_id)
	if gs == null or def.is_empty() or def["kategorie"] != "deko" or not im_sortiment:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var preis := int(def["kosten"])
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			RanchBauState.lager_hinzu(RanchBauState.bau_im_state(state), deko_id)
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "preis": preis}


## Möbel-Scheune: Haus-Möbel kaufen → home.storage (Kapazität gilt).
static func moebel_kaufen(gs: Object, item_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var ware := _ware(DorfKatalog.moebel(bal), item_id)
	var defs: Dictionary = FurnitureCatalog.defs()
	if gs == null or ware.is_empty() or not defs.has(item_id):
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var storage: Variant = gs.get_value("home.storage", null)
	if not (storage is Array):
		return {"ok": false, "fehler": FEHLER_KEIN_LAGER, "preis": 0}
	var kapazitaet := int(_num(gs.get_value("home.storageCapacity", 100), 100.0))
	if not StorageLogic.can_add(storage, item_id, defs, kapazitaet):
		return {"ok": false, "fehler": FEHLER_LAGER_VOLL, "preis": 0}
	var preis := maxi(0, int(_num(ware.get("preis"), 0.0)))
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("home") is Dictionary):
				return
			if not ((state["home"] as Dictionary).get("storage") is Array):
				return
			if not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			StorageLogic.add(state["home"]["storage"], item_id)
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	gs.notify_slice_changed("home")
	return {"ok": true, "fehler": "", "preis": preis}


## Schmiede: Hufeisen-Sorte kaufen (einmalig, Cosmetic — liegt danach in
## ranch.dorf.hufeisen.owned und ist jedem Pferd anlegbar).
static func schmiede_kaufen(gs: Object, ware_id: String, balance := {}) -> Dictionary:
	var bal := balance if not balance.is_empty() else DorfKatalog.load_balance()
	var ware := _ware(DorfKatalog.schmiede_waren(bal), ware_id)
	if gs == null or ware.is_empty():
		return {"ok": false, "fehler": FEHLER_UNBEKANNT, "preis": 0}
	var dorf := RanchDorfState.lese(gs)
	if (dorf["hufeisen"]["owned"] as Array).has(ware_id):
		return {"ok": false, "fehler": FEHLER_SCHON_GEKAUFT, "preis": 0}
	var preis := maxi(0, int(_num(ware.get("preis"), 0.0)))
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, SPEND_REASON):
				return
			bezahlt[0] = true
			var d := RanchDorfState.dorf_im_state(state)
			var owned: Array = d["hufeisen"]["owned"]
			if not owned.has(ware_id):
				owned.append(ware_id)
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "fehler": FEHLER_ZU_TEUER, "preis": preis}
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": "", "preis": preis}


## Gekaufte Hufeisen einem Pferd anlegen ("" legt ab). Kostenlos.
static func hufeisen_anlegen(gs: Object, pferd_id: String, ware_id: String) -> Dictionary:
	if gs == null:
		return {"ok": false, "fehler": FEHLER_UNBEKANNT}
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {})
	if not (pferde is Dictionary) or not (pferde as Dictionary).has(pferd_id):
		return {"ok": false, "fehler": FEHLER_KEIN_PFERD}
	var dorf := RanchDorfState.lese(gs)
	if ware_id != "" and not (dorf["hufeisen"]["owned"] as Array).has(ware_id):
		return {"ok": false, "fehler": FEHLER_NICHT_GEKAUFT}
	gs.update(
		func(state: Dictionary) -> void:
			var d := RanchDorfState.dorf_im_state(state)
			var pro_pferd: Dictionary = d["hufeisen"]["proPferd"]
			if ware_id == "":
				pro_pferd.erase(pferd_id)
			else:
				pro_pferd[pferd_id] = ware_id
	)
	gs.notify_slice_changed(RanchDorfState.SLICE_ID)
	return {"ok": true, "fehler": ""}


## Aktueller Heu-Bestand im Ranch-Lager.
static func _heu_bestand(gs: Object) -> int:
	var lager: Variant = gs.get_value("ranch.wirtschaft.lager", {})
	return int(_num((lager if lager is Dictionary else {}).get("heu"), 0.0))


# ── intern ───────────────────────────────────────────────────────────────────


## Waren-Eintrag ({id, preis, ...}) aus einer Liste suchen ({} = fehlt).
static func _ware(liste: Array, ware_id: String) -> Dictionary:
	for eintrag: Variant in liste:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("id", "")) == ware_id:
			return eintrag
	return {}


static func _def(defs: Dictionary, id: String) -> Dictionary:
	return defs[id] if defs.get(id) is Dictionary else {}


## `ranch.wirtschaft.lager` innerhalb eines gs.update()-Blocks (heilt
## fehlende Ebenen defensiv — RANCH-2s normalize glättet später).
static func _wirtschaft_lager_im_state(state: Dictionary) -> Dictionary:
	var ranch: Dictionary = state.get("ranch") if state.get("ranch") is Dictionary else {}
	if not (state.get("ranch") is Dictionary):
		state["ranch"] = ranch
	var wirtschaft: Dictionary = (
		ranch.get("wirtschaft") if ranch.get("wirtschaft") is Dictionary else {}
	)
	if not (ranch.get("wirtschaft") is Dictionary):
		ranch["wirtschaft"] = wirtschaft
	var lager: Dictionary = wirtschaft.get("lager") if wirtschaft.get("lager") is Dictionary else {}
	if not (wirtschaft.get("lager") is Dictionary):
		wirtschaft["lager"] = lager
	return lager


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
