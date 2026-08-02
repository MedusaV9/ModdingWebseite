class_name McGoobyKauf
extends RefCounted
## Kauf-Logik des McGooby-DLC (G6/MCGOOBY-B) — pure static-Funktionen über
## dem GameState (Duck-Typing), 1:1 das Ranch-/GoobyeKauf-Muster (Doc §6.2
## nennt ranch_offer/kauf ausdrücklich als Code-Vorlage): headless testbar,
## die UI bekommt keinen eigenen Regel-Zweig.
##
## Ein Kauf ist ATOMAR: entweder Münzen weg UND Laden gekauft — oder
## nichts. Alles in EINEM `gs.update()`-Block (Economy.spend ist selbst
## atomar). Zeit über die injizierte Uhr des GameState (Clock-Muster).

const RESULT_OK := "ok"
const RESULT_LOCKED := "level_zu_niedrig"
const RESULT_OWNED := "schon_gekauft"
const RESULT_BROKE := "not_enough_coins"
const REASON := "mcgooby"

const Economy := preload("res://scripts/logic/economy.gd")


## Prüft den Kauf, ohne etwas zu ändern. Liefert RESULT_OK oder den Grund.
static func check(gs: Object) -> String:
	if gs == null:
		return RESULT_LOCKED
	if McGoobyState.ist_gekauft(gs):
		return RESULT_OWNED
	if not McGoobyState.ist_freigeschaltet(gs):
		return RESULT_LOCKED
	if int(gs.get_value("economy.coins", 0)) < McGoobyKatalog.preis():
		return RESULT_BROKE
	return RESULT_OK


static func kann_kaufen(gs: Object) -> bool:
	return check(gs) == RESULT_OK


## Kauft den Laden: Preis abbuchen + gekauft-Flag setzen. Liefert denselben
## Ergebnis-Code wie check(); nur RESULT_OK hat den State verändert.
static func kaufe(gs: Object) -> String:
	var grund := check(gs)
	if grund != RESULT_OK:
		return grund
	var preis := McGoobyKatalog.preis()
	var jetzt_ms := _now_ms(gs)
	# Einelementiges Array als Rückkanal: GDScript-Lambdas fangen lokale
	# Variablen per WERT ein, eine Zuweisung im Block käme sonst nie an.
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			var mcgooby := McGoobyState.ensure_mcgooby(state)
			mcgooby["gekauft"] = true
			mcgooby["gekauftAm"] = jetzt_ms
			mcgooby["angebotGesehen"] = true
			mcgooby["angebotVerschoben"] = false
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed(McGoobyState.SLICE_ID)
	return RESULT_OK


static func _now_ms(gs: Object) -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
