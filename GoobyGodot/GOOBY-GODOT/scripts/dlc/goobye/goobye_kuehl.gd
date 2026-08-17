class_name GoobyeKuehl
extends RefCounted
## Kühl-Kapazität des „Goo und Bye“ (W19 Welle B, Doc §4.3) — PURE + static.
## Kein Verderb, kein Frische-Timer: Kühlware (Gruppe `kuehlware`) braucht
## KAPAZITÄT — sie ist nur listbar (= einräumbar ins Regal), solange genug
## Kühlmodule brummen. Ein Planungs-Constraint ohne Verlustangst; das
## Lager kühlt Onkel Alwins alte Kühltheke gratis mit (nur das REGAL zählt).
##
## Start-Bestand: 1 Modul (die Welle-A-Kühltheke) — Alt-Saves listen ihren
## Start-Käse weiter ohne Umbau. Weitere Module kauft man am Bestell-Sheet
## (§3.2: Kühlmodule 150–300 ᴳ; Kauf atomar, W18-Geld-Regel).

const Economy := preload("res://scripts/logic/economy.gd")

const GRUPPE_KUEHL := "kuehlware"
const STUECK_JE_MODUL := 8
const MODUL_PREIS := 150

const RESULT_OK := "ok"
const RESULT_BROKE := "not_enough_coins"
const REASON := "gooundbye_kuehlmodul"


static func kapazitaet(module: int) -> int:
	return maxi(0, module) * STUECK_JE_MODUL


static func ist_kuehlware(ware_id: String) -> bool:
	return str(GoobyeKatalog.ware(ware_id).get("gruppe", "")) == GRUPPE_KUEHL


## Kühlware-Stück im Regal (über alle Slots).
static func kuehl_stueck(regal: Dictionary) -> int:
	var summe := 0
	for slot: Dictionary in regal.get("slots", []):
		if ist_kuehlware(str(slot.get("ware", ""))):
			summe += maxi(0, int(slot.get("menge", 0)))
	return summe


## Wie viele Stück dieser Ware dürfen JETZT noch ins Regal? Trockenware
## unbegrenzt (`wunsch`), Kühlware bis zur freien Kühl-Kapazität.
static func einraeumbar(regal: Dictionary, ware_id: String, wunsch: int, module: int) -> int:
	if wunsch <= 0:
		return 0
	if not ist_kuehlware(ware_id):
		return wunsch
	return clampi(kapazitaet(module) - kuehl_stueck(regal), 0, wunsch)


## Kühlmodule im Save (Default 1 — die Welle-A-Kühltheke).
static func module_von(gs: Object) -> int:
	if gs == null:
		return 1
	return maxi(1, int(gs.get_value("dlc.goobye.kuehlModule", 1)))


## Kühlmodul kaufen: ATOMAR Münzen runter UND Modul-Zähler rauf (ein
## gs.update-Block). Nur RESULT_OK hat den State verändert.
static func kaufe_modul(gs: Object) -> String:
	if gs == null:
		return RESULT_BROKE
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], MODUL_PREIS, REASON):
				return
			bezahlt[0] = true
			var goobye := GoobyeState.ensure_goobye(state)
			goobye["kuehlModule"] = maxi(1, int(goobye.get("kuehlModule", 1))) + 1
	)
	if not bool(bezahlt[0]):
		return RESULT_BROKE
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return RESULT_OK
