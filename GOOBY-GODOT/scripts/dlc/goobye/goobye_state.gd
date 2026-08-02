class_name GoobyeState
extends RefCounted
## Save-Anbindung des „Goo und Bye“ (G5/P24) ans GameState (W1d) — Muster
## RanchState, aber als UNTERSCHLÜSSEL `dlc.goobye.*` eines gemeinsamen
## additiven `dlc`-Slices (Koordinaten-Absprache G5: weitere DLCs docken
## als Geschwister-Unterschlüssel an, normalize erhält fremde Unterschlüssel
## VERBATIM). Alle Funktionen static, `gs` = Duck-Typing (/root/GameState
## oder Test-Instanz). ADDITIV über die public APIs (SaveSchema.register_slice
## + gs.update-Ensure-Muster wie random_events.gd) — KEIN Save-Version-Bump,
## kein Eingriff in game_state.gd/save_schema.gd.
##
## Struktur dlc.goobye:
##   v, gekauft (bool), gekauftAm (ms), angebotGesehen, angebotVerschoben,
##   erstbesuchGesehen (Story-Beat §1.3 einmalig),
##   lager {wareId: menge}  (ohne Verfall, §4.3),
##   umsatz {tage, gestern, gesamt}  (Kassensturz-Zettel, §2.3)
## Welle B (G6/GOOBYE-B) ADDITIV:
##   preise {gruppeId: faktor}  (Preis-Schieber je Warengruppe, §2.2/§4.4),
##   alwin {streak, best, bedientGesamt}  (Alwin-Streak + Belohnung, §6.3),
##   backofen {tag, chargen}  (Backecke-Tagesdeckel + Duft, §7.1)

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "dlc"
const KEY := "goobye"

## Grobe Heil-Klemme für gespeicherte Preis-Faktoren (Obermenge der
## Balance-Spanne — die Sim klemmt zur Laufzeit nochmal exakt).
const FAKTOR_HEIL_MIN := 0.5
const FAKTOR_HEIL_MAX := 1.5

static var _registered := false


## Registriert den dlc-Slice (idempotent; VOR GameState.initialize() ideal,
## nachträglich heilt das Ensure-Muster in den update-Blöcken).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {KEY: default_goobye()}


static func default_goobye() -> Dictionary:
	return {
		"v": 1,
		"gekauft": false,
		"gekauftAm": 0,
		"angebotGesehen": false,
		"angebotVerschoben": false,
		"erstbesuchGesehen": false,
		"lager": {},
		"umsatz": {"tage": 0, "gestern": 0, "gesamt": 0},
		"preise": {},
		"alwin": {"streak": 0, "best": 0, "bedientGesamt": 0},
		"backofen": {"tag": "", "chargen": 0},
	}


## Self-Heal: eigenen Unterschlüssel reparieren, FREMDE dlc-Unterschlüssel
## (künftige Geschwister-DLCs) unangetastet lassen.
static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else {}
	slice[KEY] = normalize_goobye(slice.get(KEY))
	return slice


static func normalize_goobye(raw: Variant) -> Dictionary:
	var goobye: Dictionary = raw if raw is Dictionary else default_goobye()
	goobye["v"] = maxi(1, int(goobye.get("v", 1)))
	goobye["gekauft"] = bool(goobye.get("gekauft", false))
	goobye["gekauftAm"] = maxi(0, int(goobye.get("gekauftAm", 0)))
	goobye["angebotGesehen"] = bool(goobye.get("angebotGesehen", false))
	goobye["angebotVerschoben"] = bool(goobye.get("angebotVerschoben", false))
	goobye["erstbesuchGesehen"] = bool(goobye.get("erstbesuchGesehen", false))
	var lager: Dictionary = goobye.get("lager") if goobye.get("lager") is Dictionary else {}
	var heil_lager: Dictionary = {}
	for ware_id: Variant in lager:
		var menge := int(lager[ware_id])
		if menge > 0:
			heil_lager[str(ware_id)] = menge
	goobye["lager"] = heil_lager
	var umsatz: Dictionary = goobye.get("umsatz") if goobye.get("umsatz") is Dictionary else {}
	for feld: String in ["tage", "gestern", "gesamt"]:
		umsatz[feld] = maxi(0, int(umsatz.get(feld, 0)))
	goobye["umsatz"] = umsatz
	goobye["preise"] = _normalize_preise(goobye.get("preise"))
	var alwin: Dictionary = goobye.get("alwin") if goobye.get("alwin") is Dictionary else {}
	for feld: String in ["streak", "best", "bedientGesamt"]:
		alwin[feld] = maxi(0, int(alwin.get(feld, 0)))
	goobye["alwin"] = alwin
	var backofen: Dictionary = (
		goobye.get("backofen") if goobye.get("backofen") is Dictionary else {}
	)
	backofen["tag"] = str(backofen.get("tag", ""))
	backofen["chargen"] = maxi(0, int(backofen.get("chargen", 0)))
	goobye["backofen"] = backofen
	return goobye


## Preis-Schieber-Faktoren heilen: nur Gruppen-Ids mit plausiblem Faktor
## überleben; 1.0 (Richtwert) wird gar nicht erst gespeichert.
static func _normalize_preise(raw: Variant) -> Dictionary:
	var preise: Dictionary = raw if raw is Dictionary else {}
	var heil: Dictionary = {}
	for gruppe_id: Variant in preise:
		var faktor := clampf(float(preise[gruppe_id]), FAKTOR_HEIL_MIN, FAKTOR_HEIL_MAX)
		if not is_equal_approx(faktor, 1.0):
			heil[str(gruppe_id)] = faktor
	return heil


## Laden gekauft?
static func ist_gekauft(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("dlc.goobye.gekauft", false))


## Level-Gate: ab diesem Level ist der Laden freigeschaltet (Balance-Pack,
## Default 12 — GoobyeKatalog.freischalt_level).
static func ist_freigeschaltet(gs: Object) -> bool:
	if gs == null:
		return false
	var level := int(gs.get_value("progression.level", 1))
	return level >= GoobyeKatalog.freischalt_level()


## „Später kaufen“: Angebot gesehen + verschoben merken (Muster RanchState).
static func angebot_verschieben(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			goobye["angebotGesehen"] = true
			goobye["angebotVerschoben"] = true
	)
	gs.notify_slice_changed(SLICE_ID)


## Angebot als gesehen markieren (ohne verschieben).
static func angebot_gesehen(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			goobye["angebotGesehen"] = true
	)
	gs.notify_slice_changed(SLICE_ID)


## Story-Beat §1.3 (Schlüsselübergabe-Karte beim Erstbetreten): merkt den
## Besuch und sagt, ob DIESER Aufruf der erste war.
static func erstbesuch_merken(gs: Object) -> bool:
	if gs == null:
		return false
	if bool(gs.get_value("dlc.goobye.erstbesuchGesehen", false)):
		return false
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			goobye["erstbesuchGesehen"] = true
	)
	gs.notify_slice_changed(SLICE_ID)
	return true


## Lager-Stand (wareId → Stück; Kopie).
static func lager_von(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("dlc.goobye.lager", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## Lager komplett setzen (die Szene arbeitet auf einer Kopie und schreibt
## beim Verlassen zurück — Welle A hält das bewusst schlicht). 0-Mengen
## werden schon beim Schreiben herausgeheilt (gleiche Regel wie normalize).
static func lager_setzen(gs: Object, lager: Dictionary) -> void:
	if gs == null:
		return
	var heil: Dictionary = {}
	for ware_id: Variant in lager:
		if int(lager[ware_id]) > 0:
			heil[str(ware_id)] = int(lager[ware_id])
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			goobye["lager"] = heil
	)
	gs.notify_slice_changed(SLICE_ID)


## Tagesabschluss (Kassensturz §2.3): Umsatz verbuchen.
static func umsatz_verbuchen(gs: Object, betrag: int) -> void:
	if gs == null or betrag < 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			var umsatz: Dictionary = goobye["umsatz"]
			umsatz["tage"] = int(umsatz.get("tage", 0)) + 1
			umsatz["gestern"] = betrag
			umsatz["gesamt"] = int(umsatz.get("gesamt", 0)) + betrag
	)
	gs.notify_slice_changed(SLICE_ID)


## Preis-Schieber-Stellungen je Warengruppe (gruppeId → faktor; Kopie).
## Fehlende Gruppen bedeuten Richtwert (1.0) — so bleibt der Save klein.
static func preise_von(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("dlc.goobye.preise", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## Eine Schieber-Stellung merken (Welle B, §2.2): 1.0 löscht den Eintrag
## (Richtwert = Default), alles andere wird grob geklemmt gespeichert.
static func preis_faktor_setzen(gs: Object, gruppe_id: String, faktor: float) -> void:
	if gs == null or gruppe_id.is_empty():
		return
	var wert := clampf(faktor, FAKTOR_HEIL_MIN, FAKTOR_HEIL_MAX)
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := ensure_goobye(state)
			var preise: Dictionary = goobye["preise"]
			if is_equal_approx(wert, 1.0):
				preise.erase(gruppe_id)
			else:
				preise[gruppe_id] = wert
	)
	gs.notify_slice_changed(SLICE_ID)


## Nur für Tests: Registry-Status zurücksetzen.
static func reset_for_tests() -> void:
	_registered = false


## Ensure-Muster (random_events.gd): fehlende Schlüssel im update-Block
## anlegen/heilen — robust, auch wenn der Slice erst NACH initialize()
## registriert wurde (Alt-Saves, isolierte Tests).
static func ensure_goobye(state: Dictionary) -> Dictionary:
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = default_slice()
	var slice: Dictionary = state[SLICE_ID]
	slice[KEY] = normalize_goobye(slice.get(KEY))
	return slice[KEY]
