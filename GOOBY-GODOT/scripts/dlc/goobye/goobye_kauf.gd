class_name GoobyeKauf
extends RefCounted
## Kauf-Logik des „Goo und Bye“-DLC (G5/P24) — pure static-Funktionen über
## dem GameState (Duck-Typing), 1:1 das RanchKauf-Muster (Doc §7.2 nennt
## ranch_offer/kauf ausdrücklich als Code-Vorlage): headless testbar, die
## UI bekommt keinen eigenen Regel-Zweig.
##
## Ein Kauf ist ATOMAR: entweder Münzen weg UND Laden gekauft UND das
## Eröffnungspaket-Lager (Warengutschein §2.2, `start`-Felder im Pack)
## eingeräumt — oder nichts. Alles in EINEM `gs.update()`-Block
## (Economy.spend ist selbst atomar).

const RESULT_OK := "ok"
const RESULT_LOCKED := "level_zu_niedrig"
const RESULT_OWNED := "schon_gekauft"
const RESULT_BROKE := "not_enough_coins"
const REASON := "gooundbye"

const Economy := preload("res://scripts/logic/economy.gd")


## Prüft den Kauf, ohne etwas zu ändern. Liefert RESULT_OK oder den Grund.
static func check(gs: Object) -> String:
	if gs == null:
		return RESULT_LOCKED
	if GoobyeState.ist_gekauft(gs):
		return RESULT_OWNED
	if not GoobyeState.ist_freigeschaltet(gs):
		return RESULT_LOCKED
	if int(gs.get_value("economy.coins", 0)) < GoobyeKatalog.preis():
		return RESULT_BROKE
	return RESULT_OK


static func kann_kaufen(gs: Object) -> bool:
	return check(gs) == RESULT_OK


## Kauft den Laden: Preis abbuchen, gekauft-Flag setzen, Startlager aus dem
## Pack einziehen. Liefert denselben Ergebnis-Code wie check(); nur
## RESULT_OK hat den State verändert.
static func kaufe(gs: Object) -> String:
	var grund := check(gs)
	if grund != RESULT_OK:
		return grund
	var preis := GoobyeKatalog.preis()
	var startlager := GoobyeKatalog.startlager()
	var jetzt_ms := _now_ms(gs)
	# Einelementiges Array als Rückkanal: GDScript-Lambdas fangen lokale
	# Variablen per WERT ein, eine Zuweisung im Block käme sonst nie an.
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			var goobye := GoobyeState.ensure_goobye(state)
			goobye["gekauft"] = true
			goobye["gekauftAm"] = jetzt_ms
			goobye["angebotGesehen"] = true
			goobye["angebotVerschoben"] = false
			var lager: Dictionary = goobye["lager"]
			for ware_id: String in startlager:
				lager[ware_id] = int(lager.get(ware_id, 0)) + int(startlager[ware_id])
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return RESULT_OK


static func _now_ms(gs: Object) -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
