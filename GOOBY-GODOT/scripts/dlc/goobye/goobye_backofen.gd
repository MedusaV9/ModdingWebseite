class_name GoobyeBackofen
extends RefCounted
## Backstation des „Goo und Bye“ (G6/GOOBYE-B, Doc §3.4/§7.1 „Backecke“) —
## PURE + static, die Uhr wird als tag_key INJIZIERT (game_state-Clock-
## Muster, kein Time.*-Zugriff): Gooby schiebt eine Blech-Charge in den
## Ofen, zahlt die Selbstkosten (backen_kosten_faktor × Einkaufspreis je
## Brot) und bekommt frisches Brot ins Lager — ATOMAR in EINEM
## update-Block, oder gar nichts. Der eigentliche Zauber ist der DUFT:
## sobald heute EINE Charge gebacken wurde, bekommt die Backwaren-Gruppe
## den Duft-Bonus auf die Griff-Chance (GoobyeMarkttag, duft_gruppe).
## Tagesdeckel statt Timer: MAX_CHARGEN pro Tag — kein Warten, kein
## Verderb, keine Strafe (§1.4).

const Economy := preload("res://scripts/logic/economy.gd")

const WARE := "bread"
const DUFT_GRUPPE := "backwaren"
const BROT_JE_CHARGE := 3
const MAX_CHARGEN := 3
const REASON := "gooundbye_backen"

const RESULT_OK := "ok"
const RESULT_AUSGEBACKEN := "ausgebacken"
const RESULT_BROKE := "not_enough_coins"


## Selbstkosten einer Charge (§7.1): Faktor × Einkaufspreis × Stückzahl.
static func kosten() -> int:
	var brot := GoobyeKatalog.ware(WARE)
	if brot.is_empty():
		return 1
	var je_stueck := float(GoobyePreis.einkaufspreis(brot)) * GoobyeKatalog.backen_kosten_faktor()
	return maxi(1, roundi(je_stueck * float(BROT_JE_CHARGE)))


## Heute gebackene Chargen (0, wenn der Save-Tag nicht tag_key ist).
static func chargen_heute(gs: Object, tag_key: String) -> int:
	if gs == null or str(gs.get_value("dlc.goobye.backofen.tag", "")) != tag_key:
		return 0
	return maxi(0, int(gs.get_value("dlc.goobye.backofen.chargen", 0)))


## Duftet es heute nach frischem Brot (Griff-Bonus für Backwaren, §7.1)?
static func duft_aktiv(gs: Object, tag_key: String) -> bool:
	return chargen_heute(gs, tag_key) > 0


## Passt heute noch eine Charge in den Ofen?
static func kann_backen(gs: Object, tag_key: String) -> bool:
	return gs != null and chargen_heute(gs, tag_key) < MAX_CHARGEN


## Eine Charge backen: Münzen runter, Brot rauf, Tages-Zähler hoch — alles
## in EINEM update-Block (Fail-closed: Deckel → Münzen). Ergebnis:
## {ok, grund, kosten, menge, chargen, duft}.
static func backen(gs: Object, tag_key: String) -> Dictionary:
	var preis := kosten()
	var ergebnis := {
		"ok": false,
		"grund": RESULT_BROKE,
		"kosten": preis,
		"menge": 0,
		"chargen": chargen_heute(gs, tag_key),
		"duft": duft_aktiv(gs, tag_key),
	}
	if gs == null:
		return ergebnis
	if not kann_backen(gs, tag_key):
		ergebnis["grund"] = RESULT_AUSGEBACKEN
		return ergebnis
	# Einelementiges Array als Rückkanal (Lambda fängt per Wert).
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, REASON):
				return
			bezahlt[0] = true
			var goobye := GoobyeState.ensure_goobye(state)
			var lager: Dictionary = goobye["lager"]
			lager[WARE] = int(lager.get(WARE, 0)) + BROT_JE_CHARGE
			var backofen: Dictionary = goobye["backofen"]
			if str(backofen.get("tag", "")) != tag_key:
				backofen["tag"] = tag_key
				backofen["chargen"] = 0
			backofen["chargen"] = int(backofen.get("chargen", 0)) + 1
	)
	if not bool(bezahlt[0]):
		return ergebnis
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	ergebnis["ok"] = true
	ergebnis["grund"] = RESULT_OK
	ergebnis["menge"] = BROT_JE_CHARGE
	ergebnis["chargen"] = chargen_heute(gs, tag_key)
	ergebnis["duft"] = true
	return ergebnis
