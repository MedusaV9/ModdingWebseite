class_name HeimkehrLogik
extends RefCounted
## W19/MITBRINGSEL (Doc E §3.2 Rückkehr + §3.3 Punkt 3) — PURE Logik der
## Urlaubs-Heimkehr (Dictionaries rein, Dictionaries raus; Zeit IMMER
## injiziert — Muster UrlaubsAktivitaeten/TaxiLogic):
##
## 1. HEIMKEHR-LATCHES: `ReiseLogic.abholen` stempelt bei JEDER Abholung
##    Ziel + Abflug-Timestamp + Abhol-Zeitpunkt in den vacation-Slice
##    (additive Felder, s. vacation.gd). „Rückkehr steht aus“ heißt:
##    abgeholt, aber noch nicht daheim gefeiert (`heimkehrGefeiert`).
## 2. MITBRINGSEL: pro Urlaub bringt Gooby GENAU EIN deterministisch
##    gewähltes Mitbringsel mit — seeded RNG aus Ziel + Abflug-Timestamp
##    (Save-Daten, kein OS-Zufall). Es landet additiv in inventory.items
##    (dieselbe Pipeline wie der W15-Souvenir-Spot — kein Duplikat).
## 3. 24-h-GOOBY-FREE-FENSTER: nach der Rückkehr sind am Flughafen für
##    24 h die BEIDEN nicht mitgebrachten Ziel-Deko-Varianten kaufbar
##    („nur aus dem Urlaub mitbringbar“) — danach schließt das Fenster.

const Vacation := preload("res://scripts/logic/vacation.gd")
const Economy := preload("res://scripts/logic/economy.gd")

## Dauer des GOOBY-FREE-Mitbringsel-Fensters nach der Abholung (Doc E
## §3.3: „24 h nach Rückkehr“). Zahl friert HIER (Owning-Module).
const FENSTER_MS := 24 * 3_600_000

## Die drei Mitbringsel-Varianten je Ziel (Namen: heimkehr.mitbringsel.
## typ.<typ>, formatiert mit dem lokalisierten Zielnamen travel.ziel.*).
const TYPEN: Array[String] = ["schneekugel", "magnet", "wimpel"]
## Fenster-Preise „leicht überteuert“ (Flughafen!) — sanfter Münz-Sink.
const TYP_PREISE := {"schneekugel": 55, "magnet": 35, "wimpel": 45}
## Anzahl der Wiedersehens-Sprüche (heimkehr.spruch.1..n).
const SPRUCH_ANZAHL := 2

## Kauf-Ergebnis-Codes (Werte identisch zu OrtFlughafen.KAUF_*).
const KAUF_OK := "ok"
const KAUF_ZU := "geschlossen"
const KAUF_PLEITE := "pleite"
const KAUF_REASON := "gooby_free"


## Steht die Wiedersehens-Inszenierung noch aus? NUR wenn Gooby wirklich
## daheim ist (phase none), eine Abholung gestempelt wurde und der Moment
## noch nicht gefeiert ist. Pure — direkt über dem State-Dictionary.
static func ausstehend(state: Dictionary) -> bool:
	var v := Vacation.slice_of(state)
	if str(v["phase"]) != Vacation.PHASE_NONE:
		return false
	if int(v["heimkehrAt"]) <= 0 or bool(v["heimkehrGefeiert"]):
		return false
	return Vacation.CATALOG.has(str(v["heimkehrZiel"]))


## ------------------------------------------------------------ Mitbringsel


## Deterministische Varianten-Wahl: seeded RNG aus Ziel + Abflug-Timestamp
## (beides Save-Daten) — gleicher Urlaub, gleiches Mitbringsel, immer.
static func mitbringsel_typ(ziel_id: String, abflug_ms: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [ziel_id, abflug_ms])
	return TYPEN[rng.randi_range(0, TYPEN.size() - 1)]


## Item-Id einer Ziel-Variante (landet in inventory.items).
static func mitbringsel_id(ziel_id: String, typ: String) -> String:
	return "mitbringsel_%s_%s" % [ziel_id, typ]


## Das Mitbringsel eines Urlaubs: {item_id, typ, ziel_id}.
static func mitbringsel(ziel_id: String, abflug_ms: int) -> Dictionary:
	var typ := mitbringsel_typ(ziel_id, abflug_ms)
	return {"item_id": mitbringsel_id(ziel_id, typ), "typ": typ, "ziel_id": ziel_id}


## Anzeigename einer Variante („Schneekugel „Glitzermeer““) — Zielname
## kommt aus der bestehenden travel-Domain (nur konsumiert).
static func mitbringsel_name(typ: String, ziel_id: String) -> String:
	var ziel := I18nService.t("travel.ziel.%s" % ziel_id)
	return I18nService.t("heimkehr.mitbringsel.typ.%s" % typ, {"ziel": ziel})


## Deterministischer Wiedersehens-Spruch (1 von SPRUCH_ANZAHL) — eigener
## Hash-Salt, damit Spruch und Mitbringsel nicht korrelieren.
static func spruch_key(ziel_id: String, abflug_ms: int) -> String:
	var wahl := posmod(hash("spruch|%s|%d" % [ziel_id, abflug_ms]), SPRUCH_ANZAHL)
	return "heimkehr.spruch.%d" % (wahl + 1)


## Reunion feiern, atomar und GENAU EINMAL: Latch stempeln + Mitbringsel
## additiv in inventory.items. Rückgabe {ok, item_id, typ, ziel_id,
## spruch_key}; ok=false wenn nichts aussteht (idempotent).
static func feiern(gs: Object) -> Dictionary:
	var keiner := {"ok": false, "item_id": "", "typ": "", "ziel_id": "", "spruch_key": ""}
	if gs == null or not ausstehend(gs.state()):
		return keiner
	var v := Vacation.slice_of(gs.state())
	var ziel_id := str(v["heimkehrZiel"])
	var abflug := int(v["heimkehrAbflug"])
	var geschenk := mitbringsel(ziel_id, abflug)
	var item_id := str(geschenk["item_id"])
	gs.update(
		func(state: Dictionary) -> void:
			var slice := Vacation.slice_of(state)
			slice["heimkehrGefeiert"] = true
			state["vacation"] = slice
			var items: Dictionary = state["inventory"]["items"]
			items[item_id] = int(items.get(item_id, 0)) + 1
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("vacation")
		gs.notify_slice_changed("inventory")
	return {
		"ok": true,
		"item_id": item_id,
		"typ": str(geschenk["typ"]),
		"ziel_id": ziel_id,
		"spruch_key": spruch_key(ziel_id, abflug),
	}


## ---------------------------------------------------- GOOBY-FREE-Fenster


## Ist das 24-h-Mitbringsel-Fenster am Flughafen offen? (Zeit injiziert;
## unabhängig vom Feier-Latch — das Fenster hängt NUR an der Abholung.)
static func fenster_offen(state: Dictionary, now_ms: int) -> bool:
	var v := Vacation.slice_of(state)
	var ab := int(v["heimkehrAt"])
	if ab <= 0 or not Vacation.CATALOG.has(str(v["heimkehrZiel"])):
		return false
	return now_ms >= ab and now_ms < ab + FENSTER_MS


## Aufgerundete Rest-Stunden des Fensters (für den dezenten Hinweis).
static func fenster_rest_h(state: Dictionary, now_ms: int) -> int:
	if not fenster_offen(state, now_ms):
		return 0
	var ab := int(Vacation.slice_of(state)["heimkehrAt"])
	return ceili(float(ab + FENSTER_MS - now_ms) / 3_600_000.0)


## Exklusives Fenster-Sortiment: die BEIDEN Varianten, die Gooby NICHT
## mitgebracht hat (deterministisch komplementär). Leer bei zuem Fenster.
static func fenster_sortiment(state: Dictionary, now_ms: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not fenster_offen(state, now_ms):
		return out
	var v := Vacation.slice_of(state)
	var ziel_id := str(v["heimkehrZiel"])
	var mitgebracht := mitbringsel_typ(ziel_id, int(v["heimkehrAbflug"]))
	for typ: String in TYPEN:
		if typ == mitgebracht:
			continue
		(
			out
			. append(
				{
					"id": mitbringsel_id(ziel_id, typ),
					"typ": "mitbringsel",
					"mitbringsel_typ": typ,
					"ziel_id": ziel_id,
					"preis": int(TYP_PREISE[typ]),
				}
			)
		)
	return out


## Fenster-Kauf, atomar (Muster OrtFlughafen.kaufe_gfree): Münzen weg UND
## Ware in inventory.items, oder nichts. Exklusiv: nur Waren, die im
## AKTUELLEN Fenster-Sortiment stehen (fremde/abgelaufene Ids → zu).
static func kaufe(gs: Object, ware: Dictionary, now_ms: int) -> String:
	if gs == null:
		return KAUF_ZU
	var ware_id := str(ware.get("id", ""))
	var im_fenster := false
	for angebot: Dictionary in fenster_sortiment(gs.state(), now_ms):
		if str(angebot["id"]) == ware_id:
			im_fenster = true
			break
	if not im_fenster:
		return KAUF_ZU
	var preis := int(ware.get("preis", 0))
	if int(gs.get_value("economy.coins", 0)) < preis:
		return KAUF_PLEITE
	# Einelementiges Dictionary als Rückkanal (Lambdas fangen per Wert).
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], preis, KAUF_REASON):
				return
			zahlung["ok"] = true
			var items: Dictionary = state["inventory"]["items"]
			items[ware_id] = int(items.get(ware_id, 0)) + 1
	)
	if not bool(zahlung["ok"]):
		return KAUF_PLEITE
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("inventory")
	return KAUF_OK
