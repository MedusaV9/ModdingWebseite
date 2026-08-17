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
##   umsatz {tage, gestern, gesamt}  (Kassensturz-Zettel, §2.3),
##   transport {lieferwagen, unterwegs{bestelltAt, ankunftAt, warenkorb}}
##     (Welle B §4.2 — Großmarkt-Fahrt, fahrer_sim-Zeitmodell),
##   tagesangebot {gruppe, tag}  (Welle B §4.4 — 1 Warengruppe pro Tag),
##   kuehlModule (int, Welle B §4.3 — Kühl-Kapazität statt Frische-Timer)

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "dlc"
const KEY := "goobye"

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
		"transport": {"lieferwagen": false, "unterwegs": {}},
		"tagesangebot": {"gruppe": "", "tag": ""},
		"kuehlModule": 1,
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
	goobye["lager"] = _heile_mengen(goobye.get("lager"))
	var umsatz: Dictionary = goobye.get("umsatz") if goobye.get("umsatz") is Dictionary else {}
	for feld: String in ["tage", "gestern", "gesamt"]:
		umsatz[feld] = maxi(0, int(umsatz.get(feld, 0)))
	goobye["umsatz"] = umsatz
	goobye["transport"] = _normalize_transport(goobye.get("transport"))
	goobye["tagesangebot"] = _normalize_tagesangebot(goobye.get("tagesangebot"))
	goobye["kuehlModule"] = maxi(1, int(goobye.get("kuehlModule", 1)))
	return goobye


## Mengen-Dictionary heilen (Lager UND Transport-Warenkorb): nur Waren mit
## Menge > 0, Keys als Strings.
static func _heile_mengen(raw: Variant) -> Dictionary:
	var quelle: Dictionary = raw if raw is Dictionary else {}
	var heil: Dictionary = {}
	for ware_id: Variant in quelle:
		var menge := int(quelle[ware_id])
		if menge > 0:
			heil[str(ware_id)] = menge
	return heil


## Transport-Self-Heal (Welle B §4.2): kaputte Timestamps werden REPARIERT
## statt gelöscht — eine bezahlte Fahrt darf ihre Ware nie verlieren
## (§1.4-Geist). Nur ein leerer Warenkorb löscht die Fahrt.
static func _normalize_transport(raw: Variant) -> Dictionary:
	var transport: Dictionary = raw if raw is Dictionary else {}
	var heil := {"lieferwagen": bool(transport.get("lieferwagen", false)), "unterwegs": {}}
	var unterwegs: Variant = transport.get("unterwegs")
	if not (unterwegs is Dictionary):
		return heil
	var korb := _heile_mengen((unterwegs as Dictionary).get("warenkorb"))
	if korb.is_empty():
		return heil
	var bestellt := maxi(0, int((unterwegs as Dictionary).get("bestelltAt", 0)))
	var ankunft := maxi(bestellt, int((unterwegs as Dictionary).get("ankunftAt", 0)))
	heil["unterwegs"] = {"bestelltAt": bestellt, "ankunftAt": ankunft, "warenkorb": korb}
	return heil


## Tagesangebot-Self-Heal (Welle B §4.4): {gruppe, tag} als Strings.
static func _normalize_tagesangebot(raw: Variant) -> Dictionary:
	var angebot: Dictionary = raw if raw is Dictionary else {}
	return {"gruppe": str(angebot.get("gruppe", "")), "tag": str(angebot.get("tag", ""))}


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
