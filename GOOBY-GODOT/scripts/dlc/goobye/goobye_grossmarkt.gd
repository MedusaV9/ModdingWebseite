class_name GoobyeGrossmarkt
extends RefCounted
## Großmarkt-Rechnung des „Goo und Bye“ (G6/GOOBYE-B, Doc §4.1/§4.2) —
## PURE + static, ohne Nodes und ohne Uhr: Paletten-Preise mit
## Mengenrabatt (Staffel ab 10 Stück, −5 %), Rampen-Tagesangebot
## (EINE Warengruppe pro Tag −15 % auf den Einkauf, deterministisch aus
## dem Tages-Seed) und Kofferraum-Deckel (§4.2 — Kisten sind die fühlbare
## Größe). Der Kauf selbst ist ATOMAR im GoobyeKauf-Muster: Münzen runter
## UND Lager rauf in EINEM gs.update-Block — oder gar nichts.
##
## Der Running-Gag lebt: Gooby kauft beim „Konkurrenten“ REHWEI ein, und
## beide tun so, als wäre das völlig normal (Doc §4.1).

const RESULT_OK := "ok"
const RESULT_LEER := "korb_leer"
const RESULT_KOFFERRAUM := "kofferraum_voll"
const RESULT_BROKE := "not_enough_coins"
const REASON := "gooundbye_einkauf"

const Economy := preload("res://scripts/logic/economy.gd")


## Tagesangebot der Rampe: EINE Warengruppe pro Tag ist im Einkauf
## rabattiert — deterministisch aus dem Tages-Seed, aber bewusst ANDERS
## rotiert als der Verkaufs-Tagestrend (sonst zeigten Rampe und Regal
## immer dieselbe Gruppe). "" nur ohne Katalog.
static func tagesangebot_gruppe(seed_wert: int) -> String:
	var gruppen := GoobyeKatalog.gruppen()
	if gruppen.is_empty():
		return ""
	var idx := posmod(seed_wert * 31 + 7, gruppen.size())
	return str((gruppen[idx] as Dictionary).get("id", ""))


## Stückpreis an der Rampe: Einkaufspreis (§2.2), Tagesangebots-Gruppe
## bekommt den Rampen-Rabatt. Nie unter 1 Münze.
static func stueckpreis(ware: Dictionary, angebot_gruppe := "") -> int:
	var preis := float(GoobyePreis.einkaufspreis(ware))
	if not angebot_gruppe.is_empty() and str(ware.get("gruppe", "")) == angebot_gruppe:
		preis *= 1.0 - GoobyeKatalog.tagesrabatt()
	return maxi(1, roundi(preis))


## Preis einer Paletten-Zeile (`menge` Stück einer Ware): Stückpreis ×
## Menge, ab der Staffel-Schwelle (§4.1: 10 Stück) −5 % auf die Zeile.
static func palette_preis(ware: Dictionary, menge: int, angebot_gruppe := "") -> int:
	if menge <= 0 or ware.is_empty():
		return 0
	var summe := float(stueckpreis(ware, angebot_gruppe) * menge)
	if menge >= GoobyeKatalog.mengenrabatt_ab():
		summe *= 1.0 - GoobyeKatalog.mengenrabatt()
	return maxi(1, roundi(summe))


## Gesamtkosten eines Warenkorbs {wareId: menge} (unbekannte Ids zählen 0).
static func korb_summe(korb: Dictionary, angebot_gruppe := "") -> int:
	var summe := 0
	for ware_id: Variant in korb:
		var ware := GoobyeKatalog.ware(str(ware_id))
		summe += palette_preis(ware, int(korb[ware_id]), angebot_gruppe)
	return summe


## Kistenzahl eines Warenkorbs (1 Stück = 1 Kiste — kindgerecht fühlbar).
## Nur Katalog-Waren zählen: was man zahlt = was verladen wird = was ankommt.
static func korb_kisten(korb: Dictionary) -> int:
	var kisten := 0
	for ware_id: Variant in korb:
		if not GoobyeKatalog.ware(str(ware_id)).is_empty():
			kisten += maxi(0, int(korb[ware_id]))
	return kisten


## Passt der Korb in den Kofferraum (§4.2)?
static func passt_in_kofferraum(korb: Dictionary) -> bool:
	return korb_kisten(korb) <= GoobyeKatalog.kofferraum_kisten()


## Prüft den Einkauf, ohne etwas zu ändern (Fail-closed-Reihenfolge:
## leer → Kofferraum → Münzen). Liefert RESULT_OK oder den Grund.
static func check(gs: Object, korb: Dictionary, angebot_gruppe := "") -> String:
	if korb_kisten(korb) <= 0:
		return RESULT_LEER
	if not passt_in_kofferraum(korb):
		return RESULT_KOFFERRAUM
	if gs == null or int(gs.get_value("economy.coins", 0)) < korb_summe(korb, angebot_gruppe):
		return RESULT_BROKE
	return RESULT_OK


## Kauft den Korb ATOMAR: Münzen runter UND Lager rauf in EINEM
## update-Block. Ergebnis: {ok, grund, kosten, kisten}.
static func kaufen(gs: Object, korb: Dictionary, angebot_gruppe := "") -> Dictionary:
	var grund := check(gs, korb, angebot_gruppe)
	var kosten := korb_summe(korb, angebot_gruppe)
	var kisten := korb_kisten(korb)
	if grund != RESULT_OK:
		return {"ok": false, "grund": grund, "kosten": kosten, "kisten": kisten}
	# Einelementiges Array als Rückkanal (Lambda fängt per Wert).
	var bezahlt := [false]
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], kosten, REASON):
				return
			bezahlt[0] = true
			var goobye := GoobyeState.ensure_goobye(state)
			var lager: Dictionary = goobye["lager"]
			for ware_id: Variant in korb:
				var menge := int(korb[ware_id])
				if menge > 0 and not GoobyeKatalog.ware(str(ware_id)).is_empty():
					lager[str(ware_id)] = int(lager.get(str(ware_id), 0)) + menge
	)
	if not bool(bezahlt[0]):
		return {"ok": false, "grund": RESULT_BROKE, "kosten": kosten, "kisten": kisten}
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return {"ok": true, "grund": RESULT_OK, "kosten": kosten, "kisten": kisten}
