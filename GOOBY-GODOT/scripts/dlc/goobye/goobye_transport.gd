class_name GoobyeTransport
extends RefCounted
## Großmarkt-Fahrt des „Goo und Bye“ (W19 Welle B, Doc §4.2) — PURE + static.
## Die Ware wird WIRKLICH gefahren: Bestellen bucht die Münzen ab und legt
## eine Fahrt in den Save (dlc.goobye.transport.unterwegs), Ankunft und
## Fahrt-Phase sind eine REINE Funktion der Save-Timestamps und der
## injizierten Uhr (fahrer_sim.gd-Zeitmodell: App zu/auf/Neustart egal —
## gleiche Zeit = gleiche Position, kein Node-Tick, kein RNG).
##
## Kofferraum (§4.2): 1 Kiste = 1 Stück Ware. Kleines Auto 12, Kombi 24,
## der freischaltbare „Goo und Bye“-Lieferwagen 48 Kisten — Autos bekommen
## damit erstmals einen WIRTSCHAFTLICHEN Unterschied (rein logistisch:
## jedes Auto schafft jede Bestellung, große schaffen mehr in einer Fahrt).
##
## Geld-Regel (W18-Lehre): Bestellen ist ATOMAR — Münzen weg UND Fahrt im
## Save, oder nichts (EIN gs.update-Block, Economy.spend ist selbst atomar).

const Economy := preload("res://scripts/logic/economy.gd")

## Kofferraum-Stufen (§4.2). Die großen Bestands-Autos (cars.json) zählen
## als Kombi; alles andere (Start-Sedan, Flitzer) als klein.
const KISTEN_KLEIN := 12
const KISTEN_KOMBI := 24
const KISTEN_LIEFERWAGEN := 48
const KOMBI_AUTOS: Array[String] = ["suv", "van"]

## Zeitmodell (reale Millisekunden, deterministisch): Hinfahrt zur
## REHWEI-Rampe, Beladen je Kiste, Rückfahrt — Ankunft = Summe.
const HIN_MS := 40_000
const RUECK_MS := 40_000
const BELADEN_JE_KISTE_MS := 2_000

const PHASE_HINFAHRT := "hinfahrt"
const PHASE_BELADEN := "beladen"
const PHASE_RUECKFAHRT := "rueckfahrt"
const PHASE_DA := "da"

## Ergebnis-Codes (stabile Strings für UI/Tests, Muster GoobyeKauf).
const RESULT_OK := "ok"
const RESULT_LEER := "korb_leer"
const RESULT_ZU_VIEL := "kofferraum_voll"
const RESULT_UNTERWEGS := "schon_unterwegs"
const RESULT_BROKE := "not_enough_coins"
const RESULT_NICHT_DA := "noch_unterwegs"
const REASON := "gooundbye_grossmarkt"

## Lieferwagen-Kauf (W19 Welle C, §7.1 Level 5 „schaltet frei“): Preis
## stimmig über dem teuersten Autohaus-Wagen (van 780 ᴳ) — der Firmenwagen
## ist das beste Logistik-Fahrzeug des Spiels und ein Mittelfrist-Ziel.
const LIEFERWAGEN_PREIS := 1500
const LIEFERWAGEN_LEVEL := 5
const RESULT_GESPERRT := "laden_level_zu_niedrig"
const RESULT_SCHON_DA := "schon_gekauft"
const REASON_LIEFERWAGEN := "gooundbye_lieferwagen"

## ------------------------------------------------------------ Kofferraum


## Kisten-Kapazität eines Autos (PURE): Lieferwagen schlägt alles.
static func kisten_kapazitaet(auto_id: String, lieferwagen_frei := false) -> int:
	if lieferwagen_frei:
		return KISTEN_LIEFERWAGEN
	if KOMBI_AUTOS.has(auto_id):
		return KISTEN_KOMBI
	return KISTEN_KLEIN


## Kapazität für den Spielstand: aktives Auto aus der Garage/dem Autohaus
## (AutoKatalog) ODER der freigeschaltete Firmen-Lieferwagen.
static func kapazitaet_fuer(gs: Object) -> int:
	var auto_id := ""
	if gs != null:
		auto_id = str(AutoKatalog.aktives_auto(gs).get("id", ""))
	return kisten_kapazitaet(auto_id, lieferwagen_frei(gs))


static func lieferwagen_frei(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("dlc.goobye.transport.lieferwagen", false))


## Roher Save-Schalter (Test-Griff/Altbestand Welle B) — der SPIELER-Weg
## ist `kaufe_lieferwagen` mit Level-Gate und Münz-Abbuchung.
static func lieferwagen_freischalten(gs: Object) -> void:
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			goobye["transport"]["lieferwagen"] = true
	)
	gs.notify_slice_changed(GoobyeState.SLICE_ID)


## Lieferwagen kaufen (W19 Welle C, §7.1): erst ab Laden-Level 5, dann
## ATOMAR — Münzen weg UND Schalter im Save, oder nichts (ein Block;
## Doppel-Tap-Rennen: der Schon-da-Check läuft NOCHMAL im Block).
static func kaufe_lieferwagen(gs: Object) -> String:
	if gs == null:
		return RESULT_BROKE
	if lieferwagen_frei(gs):
		return RESULT_SCHON_DA
	if GoobyeLevel.level_fuer(gs) < LIEFERWAGEN_LEVEL:
		return RESULT_GESPERRT
	var ergebnis := [RESULT_BROKE]
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			if bool(goobye["transport"].get("lieferwagen", false)):
				ergebnis[0] = RESULT_SCHON_DA
				return
			if not Economy.spend(state["economy"], LIEFERWAGEN_PREIS, REASON_LIEFERWAGEN):
				return
			ergebnis[0] = RESULT_OK
			goobye["transport"]["lieferwagen"] = true
	)
	if str(ergebnis[0]) == RESULT_OK:
		gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return str(ergebnis[0])


## ------------------------------------------------------------ Warenkorb


## Korb heilen (PURE): nur bekannte Katalog-Waren mit Menge > 0.
static func korb_heilen(korb: Dictionary) -> Dictionary:
	var heil: Dictionary = {}
	for ware_id: Variant in korb:
		var menge := int(korb[ware_id])
		if menge > 0 and not GoobyeKatalog.ware(str(ware_id)).is_empty():
			heil[str(ware_id)] = menge
	return heil


static func kisten_im_korb(korb: Dictionary) -> int:
	var summe := 0
	for ware_id: Variant in korb:
		summe += maxi(0, int(korb[ware_id]))
	return summe


## Bestellkosten: Großmarkt-Einkaufspreis (60 % des Richtwerts, §2.2)
## je Stück — unbekannte Waren zählen nicht.
static func kosten(korb: Dictionary) -> int:
	var summe := 0
	for ware_id: Variant in korb:
		var ware := GoobyeKatalog.ware(str(ware_id))
		if ware.is_empty():
			continue
		summe += GoobyePreis.einkaufspreis(ware) * maxi(0, int(korb[ware_id]))
	return summe


## ------------------------------------------------------------ Zeitmodell


static func fahrzeit_ms(kisten: int) -> int:
	return HIN_MS + maxi(0, kisten) * BELADEN_JE_KISTE_MS + RUECK_MS


static func ankunft_ms(bestellt_ms: int, kisten: int) -> int:
	return bestellt_ms + fahrzeit_ms(kisten)


## Fahrt-Zustand zur Uhrzeit now_ms — DETERMINISTISCH (fahrer_sim-Muster).
## Rückgabe: {phase, fortschritt: 0..1 (Gesamtfahrt), rest_ms}.
static func status(bestellt_ms: int, ankunft_ms_wert: int, now_ms: int) -> Dictionary:
	if now_ms >= ankunft_ms_wert:
		return {"phase": PHASE_DA, "fortschritt": 1.0, "rest_ms": 0}
	var dauer := maxi(1, ankunft_ms_wert - bestellt_ms)
	var fortschritt := clampf(float(now_ms - bestellt_ms) / float(dauer), 0.0, 1.0)
	var rest := ankunft_ms_wert - now_ms
	var hin_ende := bestellt_ms + mini(HIN_MS, dauer)
	var rueck_start := ankunft_ms_wert - mini(RUECK_MS, dauer)
	var phase := PHASE_BELADEN
	if now_ms < hin_ende:
		phase = PHASE_HINFAHRT
	elif now_ms >= rueck_start:
		phase = PHASE_RUECKFAHRT
	return {"phase": phase, "fortschritt": fortschritt, "rest_ms": rest}


## ------------------------------------------------------------ Save-Flüsse


## Laufende Fahrt ({} = keine; tiefe Kopie).
static func unterwegs_von(gs: Object) -> Dictionary:
	if gs == null:
		return {}
	var raw: Variant = gs.get_value("dlc.goobye.transport.unterwegs", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


## Fahrt-Status der laufenden Bestellung ({} = keine Fahrt).
static func status_von(gs: Object, now_ms := -1) -> Dictionary:
	var fahrt := unterwegs_von(gs)
	if fahrt.is_empty():
		return {}
	return status(int(fahrt["bestelltAt"]), int(fahrt["ankunftAt"]), _now(gs, now_ms))


## Bestellen (§4.2 Bestell-Sheet): prüft Korb/Kapazität/laufende Fahrt,
## bucht dann ATOMAR Münzen ab UND legt die Fahrt in den Save. Nur
## RESULT_OK hat den State verändert.
static func bestelle(gs: Object, korb: Dictionary, now_ms := -1) -> String:
	if gs == null:
		return RESULT_LEER
	var heil := korb_heilen(korb)
	if heil.is_empty():
		return RESULT_LEER
	var kisten := kisten_im_korb(heil)
	if kisten > kapazitaet_fuer(gs):
		return RESULT_ZU_VIEL
	if not unterwegs_von(gs).is_empty():
		return RESULT_UNTERWEGS
	var preis := kosten(heil)
	var jetzt := _now(gs, now_ms)
	# Einelementiges Array als Rückkanal (Lambda fängt per Wert) — und der
	# Unterwegs-Check läuft NOCHMAL im Block (Doppel-Tap-Rennen, W18/d2).
	var ergebnis := [RESULT_BROKE]
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			if not (goobye["transport"]["unterwegs"] as Dictionary).is_empty():
				ergebnis[0] = RESULT_UNTERWEGS
				return
			if not Economy.spend(state["economy"], preis, REASON):
				return
			ergebnis[0] = RESULT_OK
			var transport: Dictionary = goobye["transport"]
			transport["unterwegs"] = {
				"bestelltAt": jetzt,
				"ankunftAt": ankunft_ms(jetzt, kisten),
				"warenkorb": heil,
			}
	)
	if str(ergebnis[0]) == RESULT_OK:
		gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return str(ergebnis[0])


## „Alles ausladen“ (§4.2): erst NACH der Ankunft — Warenkorb wandert
## komplett ins Lager, die Fahrt wird abgeräumt (ein Block, verlustfrei).
## Rückgabe: {ok, grund, kisten, warenkorb}.
static func ausladen(gs: Object, now_ms := -1) -> Dictionary:
	var fahrt := unterwegs_von(gs)
	if fahrt.is_empty():
		return {"ok": false, "grund": RESULT_LEER, "kisten": 0, "warenkorb": {}}
	if _now(gs, now_ms) < int(fahrt["ankunftAt"]):
		return {"ok": false, "grund": RESULT_NICHT_DA, "kisten": 0, "warenkorb": {}}
	var korb: Dictionary = fahrt["warenkorb"]
	gs.update(
		func(state: Dictionary) -> void:
			var goobye := GoobyeState.ensure_goobye(state)
			var lager: Dictionary = goobye["lager"]
			for ware_id: String in korb:
				lager[ware_id] = int(lager.get(ware_id, 0)) + int(korb[ware_id])
			goobye["transport"]["unterwegs"] = {}
	)
	gs.notify_slice_changed(GoobyeState.SLICE_ID)
	return {"ok": true, "grund": RESULT_OK, "kisten": kisten_im_korb(korb), "warenkorb": korb}


## Injizierte Uhr (AGENTS-Regel): now_ms-Parameter für Tests, sonst
## gs.clock (Clock-Muster game_state.gd) — nie direkt die OS-Uhr in Logik.
static func _now(gs: Object, now_ms: int) -> int:
	if now_ms >= 0:
		return now_ms
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)
