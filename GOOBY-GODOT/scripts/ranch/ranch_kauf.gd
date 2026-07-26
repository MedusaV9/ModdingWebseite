class_name RanchKauf
extends RefCounted
## Kauf-Logik der Gooby Ranch (RANCH-1) — pure static-Funktionen über dem
## GameState (Duck-Typing), Muster = CONTENT-B ShopPurchase: headless
## testbar, die UI bekommt keinen eigenen Regel-Zweig.
##
## Ein Kauf ist ATOMAR: entweder Münzen weg UND Ranch gekauft UND die
## Start-Tiere aus dem Pack eingezogen — oder nichts. Alles in EINEM
## `gs.update()`-Block (Economy.spend ist selbst atomar).
##
## Absprache mit RANCH-2 (RANCH2-needs.md §1): Pferde ziehen als
## `RanchPlaySlices.neues_pferd(...)` in `ranch.tiere.pferde` ein (Pflege/
## Reiten-Struktur), Kühe/Schafe/Hühner als Weltbild-Liste `ranch.hoftiere`.

const RESULT_OK := "ok"
const RESULT_LOCKED := "level_zu_niedrig"
const RESULT_OWNED := "schon_gekauft"
const RESULT_BROKE := "not_enough_coins"
const REASON := "ranch"

const Economy := preload("res://scripts/logic/economy.gd")
const RanchPlaySlices := preload("res://scripts/ranch/data/ranch_play_slices.gd")


## Prüft den Kauf, ohne etwas zu ändern. Liefert RESULT_OK oder den Grund.
static func check(gs: Object) -> String:
	if gs == null:
		return RESULT_LOCKED
	if RanchState.ist_gekauft(gs):
		return RESULT_OWNED
	if not RanchState.ist_freigeschaltet(gs):
		return RESULT_LOCKED
	if int(gs.get_value("economy.coins", 0)) < RanchKatalog.preis():
		return RESULT_BROKE
	return RESULT_OK


static func kann_kaufen(gs: Object) -> bool:
	return check(gs) == RESULT_OK


## Kauft die Ranch: Preis abbuchen, gekauft-Flag setzen, Start-Tiere aus
## dem Content-Pack einziehen. Liefert denselben Ergebnis-Code wie check();
## nur RESULT_OK hat den State verändert.
static func kaufe(gs: Object) -> String:
	var grund := check(gs)
	if grund != RESULT_OK:
		return grund
	var preis := RanchKatalog.preis()
	var start_hoftiere := _start_hoftiere()
	var start_pferde := _start_pferde()
	var jetzt_ms := _now_ms(gs)
	# Einelementiges Array als Rückkanal: GDScript-Lambdas fangen lokale
	# Variablen per WERT ein, eine Zuweisung im Block käme sonst nie an.
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			var ranch: Dictionary = state[RanchState.SLICE_ID]
			ranch["gekauft"] = true
			ranch["gekauftAm"] = jetzt_ms
			ranch["angebotGesehen"] = true
			ranch["angebotVerschoben"] = false
			ranch["hoftiere"] = start_hoftiere
			var tiere: Dictionary = RanchPlaySlices.normalize_tiere(ranch.get("tiere"))
			for pferd_id: String in start_pferde:
				if not tiere["pferde"].has(pferd_id):
					tiere["pferde"][pferd_id] = start_pferde[pferd_id]
			ranch["tiere"] = tiere
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	gs.notify_slice_changed(RanchState.SLICE_ID)
	return RESULT_OK


## Start-Hoftiere (Kühe/Schafe/Hühner) aus dem Pack — Anzeige-Namen zieht
## die UI über die name_key-Strings, hier reisen nur Daten.
static func _start_hoftiere() -> Array:
	var out: Array = []
	for eintrag: Dictionary in RanchKatalog.tiere():
		if not bool(eintrag.get("start", false)) or str(eintrag.get("art", "")) == "pferd":
			continue
		(
			out
			. append(
				{
					"id": str(eintrag.get("id", "")),
					"art": str(eintrag.get("art", "")),
					"name_key": str(eintrag.get("name_key", "")),
					"farbe": str(eintrag.get("farbe", "#FFFFFF")),
				}
			)
		)
	return out


## Start-Pferde aus dem Pack in RANCH-2s Pflege-Struktur (id → Pferd).
## `fell_id` mappt auf RanchPlaySlices.FELLFARBEN; meine Anzeige-Hexfarben
## reisen als Zusatz-Schlüssel mit (RANCH-2s normalize erhält sie VERBATIM).
static func _start_pferde() -> Dictionary:
	var out: Dictionary = {}
	for eintrag: Dictionary in RanchKatalog.tiere():
		if not bool(eintrag.get("start", false)) or str(eintrag.get("art", "")) != "pferd":
			continue
		var name_key := str(eintrag.get("name_key", ""))
		var name := name_key.get_slice(".", name_key.get_slice_count(".") - 1).capitalize()
		var pferd := RanchPlaySlices.neues_pferd(name, str(eintrag.get("fell_id", "braun")))
		pferd["packId"] = str(eintrag.get("id", ""))
		pferd["nameKey"] = name_key
		pferd["farbeHex"] = str(eintrag.get("farbe", "#D9A066"))
		pferd["maehneHex"] = str(eintrag.get("maehne", ""))
		out[str(eintrag.get("id", ""))] = pferd
	return out


static func _now_ms(gs: Object) -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
