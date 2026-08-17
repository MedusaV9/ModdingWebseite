class_name McGoobyKauf
extends RefCounted
## Kauf-Logik des McGooby-DLC (Welle B, Doc §6.2) — pure static-Funktionen
## über dem GameState (Duck-Typing), 1:1 das RanchKauf-/GoobyeKauf-Muster:
## headless testbar, die UI bekommt keinen eigenen Regel-Zweig.
##
## Ein Kauf ist ATOMAR (W18/B1-Härtung): die Reihenfolge IM update-Block
## ist die Transaktion — ERST den Slice sicherstellen (ensure_mcgooby) und
## den Besitz gegenprüfen (Doppel-Klick-/Stale-check-Rennen), DANN abbuchen
## (Economy.spend ist selbst atomar), DANN registrieren. Nach spend() kann
## nichts mehr scheitern; Geld weg ohne Leistung ist ausgeschlossen.

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


## Kauft den Laden: Preis abbuchen, gekauft-Flag setzen. Liefert denselben
## Ergebnis-Code wie check(); nur RESULT_OK hat den State verändert.
static func kaufe(gs: Object) -> String:
	var grund := check(gs)
	if grund != RESULT_OK:
		return grund
	var preis := McGoobyKatalog.preis()
	var jetzt_ms := _now_ms(gs)
	# Einelementiges Array als Rückkanal: GDScript-Lambdas fangen lokale
	# Variablen per WERT ein, eine Zuweisung im Block käme sonst nie an.
	var ergebnis := [RESULT_BROKE]
	gs.update(
		func(state: Dictionary) -> void:
			var mcgooby := McGoobyState.ensure_mcgooby(state)
			if bool(mcgooby.get("gekauft", false)):
				ergebnis[0] = RESULT_OWNED
				return
			if not Economy.spend(state["economy"], preis, REASON):
				return
			mcgooby["gekauft"] = true
			mcgooby["gekauftAm"] = jetzt_ms
			mcgooby["angebotGesehen"] = true
			mcgooby["angebotVerschoben"] = false
			ergebnis[0] = RESULT_OK
	)
	if str(ergebnis[0]) != RESULT_OK:
		return str(ergebnis[0])
	gs.notify_slice_changed(McGoobyState.SLICE_ID)
	return RESULT_OK


static func _now_ms(gs: Object) -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
