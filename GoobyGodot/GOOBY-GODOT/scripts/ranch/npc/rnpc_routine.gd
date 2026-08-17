class_name RNpcRoutine
extends RefCounted
## Tagesrouten der Ranch-NPCs (RW-3, C8) — PURE + static. NPCs stehen
## nicht herum: jede Definition trägt 2–4 Tagesstationen ({von, ort,
## taetigkeit}); zwischen zwei Stationen LAUFEN sie (WECHSEL_MIN Minuten
## Fußweg, linear interpoliert), nachts sind alle an ihrer letzten Station.
##
## Weltpositionen: RW-1 besitzt die Ranch-Welt. Solange dessen Orts-API
## (Handoff RW1-welt-api.md) fehlt, werden Positionen defensiv aus
## RanchWelt.hof_plan() abgeleitet (Duck-Typing, Gebäude/Teich/Reitplatz)
## und für neue Orte (waldrand, markt, …) aus der FALLBACK_ORTE-Tabelle
## ergänzt — Feld 480×380 m, Werte bewusst am selben Plan orientiert.

## Fußweg-Dauer zwischen zwei Stationen in Stunden (~20 min).
const WECHSEL_STUNDEN := 0.35

## Feste Anker für Orte, die der hof_plan (noch) nicht kennt — und
## Notnagel, falls RW-1s Welt-API im Prozess fehlt.
const FALLBACK_ORTE := {
	"stall": Vector3(40.0, 0.0, 44.0),
	"scheune": Vector3(38.0, 0.0, -18.0),
	"haus": Vector3(-46.0, 0.0, 24.0),
	"heulager": Vector3(74.0, 0.0, 10.0),
	"trog": Vector3(20.0, 0.0, 58.0),
	"teich": Vector3(138.0, 0.0, 44.0),
	"reitplatz": Vector3(-80.0, 0.0, -78.0),
	"koppel_pferde": Vector3(60.0, 0.0, -102.0),
	"weide": Vector3(-142.0, 0.0, 18.0),
	"tor": Vector3(0.0, 0.0, 178.0),
	"hof_mitte": Vector3(0.0, 0.0, 30.0),
	"markt": Vector3(-18.0, 0.0, 96.0),
	"schmiede": Vector3(62.0, 0.0, -30.0),
	"sattlerei": Vector3(-66.0, 0.0, 52.0),
	"waldrand": Vector3(-196.0, 0.0, -140.0),
	"huegel": Vector3(196.0, 0.0, -150.0),
	"foto_spot_teich": Vector3(150.0, 0.0, 58.0),
	"foto_spot_huegel": Vector3(184.0, 0.0, -136.0),
}

## Test-/Probe-Injektion: kompletter hof_plan-Ersatz (leer = echte Welt).
static var plan_override: Dictionary = {}


## Station einer Routine zu einer Uhrzeit (0..24). Vor der ersten Station
## gilt die LETZTE des Vortags (Nacht-Wrap).
static func station(routine: Array, stunde: float) -> Dictionary:
	if routine.is_empty():
		return {}
	var aktiv: Dictionary = routine[routine.size() - 1]
	for eintrag: Variant in routine:
		if eintrag is Dictionary and stunde >= float((eintrag as Dictionary).get("von", 0)):
			aktiv = eintrag
	return aktiv


## Position + Blick + Lauf-Zustand zu einer Uhrzeit:
## {pos: Vector3, laeuft: bool, ort: String, taetigkeit: String}.
## In den ersten WECHSEL_STUNDEN nach Stationsbeginn läuft der NPC vom
## alten zum neuen Ort (lineare Interpolation).
static func zustand(routine: Array, stunde: float) -> Dictionary:
	var jetzt := station(routine, stunde)
	if jetzt.is_empty():
		return {"pos": Vector3.ZERO, "laeuft": false, "ort": "", "taetigkeit": ""}
	var ziel := ort_position(str(jetzt.get("ort", "")))
	var von := float(jetzt.get("von", 0))
	var seit := stunde - von
	if seit < 0.0:
		seit += 24.0
	var vorher := _station_vor(routine, jetzt)
	var out := {
		"pos": ziel,
		"laeuft": false,
		"ort": str(jetzt.get("ort", "")),
		"taetigkeit": str(jetzt.get("taetigkeit", "")),
	}
	if vorher.is_empty() or seit >= WECHSEL_STUNDEN:
		return out
	var start := ort_position(str(vorher.get("ort", "")))
	out["pos"] = start.lerp(ziel, clampf(seit / WECHSEL_STUNDEN, 0.0, 1.0))
	out["laeuft"] = true
	return out


## Weltposition eines Orts-Kürzels — bevorzugt aus RW-1s hof_plan
## (Duck-Typing über plan_override/RanchWelt), sonst FALLBACK_ORTE.
static func ort_position(ort: String) -> Vector3:
	var plan := _plan()
	match ort:
		"stall", "scheune", "haus", "heulager":
			for geb: Variant in plan.get("gebaeude", []):
				if geb is Dictionary and str((geb as Dictionary).get("id", "")) == ort:
					return _vor_gebaeude((geb as Dictionary).get("pos", Vector3.ZERO))
		"trog":
			if plan.get("trog_pos") is Vector3:
				return plan["trog_pos"]
		"teich":
			if plan.get("teich_pos") is Vector3:
				return (plan["teich_pos"] as Vector3) + Vector3(-10.0, 0.0, -6.0)
		"tor":
			if plan.get("tor_pos") is Vector3:
				return (plan["tor_pos"] as Vector3) + Vector3(4.0, 0.0, -8.0)
		"reitplatz":
			if plan.get("reitplatz") is Rect2:
				var mitte := (plan["reitplatz"] as Rect2).get_center()
				return Vector3(mitte.x, 0.0, mitte.y)
		"koppel_pferde", "weide":
			var koppel_id := "pferde" if ort == "koppel_pferde" else "weide"
			for koppel: Variant in plan.get("koppeln", []):
				var passt := (
					koppel is Dictionary
					and str((koppel as Dictionary).get("id", "")) == koppel_id
					and (koppel as Dictionary).get("rect") is Rect2
				)
				if passt:
					var rect: Rect2 = (koppel as Dictionary)["rect"]
					# Am Zaunrand stehen, nicht mitten zwischen den Tieren.
					return Vector3(rect.get_center().x, 0.0, rect.end.y + 3.0)
	return FALLBACK_ORTE.get(ort, Vector3.ZERO)


## Alle Orts-Kürzel, die dieses Modul auflösen kann (Test-Anker).
static func bekannte_orte() -> Array:
	return FALLBACK_ORTE.keys()


static func _station_vor(routine: Array, jetzt: Dictionary) -> Dictionary:
	var index := routine.find(jetzt)
	if index < 0 or routine.size() < 2:
		return {}
	return routine[(index - 1 + routine.size()) % routine.size()]


## NPCs stehen VOR ihrem Gebäude (Süd-Seite), nicht im Mauerwerk.
static func _vor_gebaeude(pos: Variant) -> Vector3:
	var basis: Vector3 = pos if pos is Vector3 else Vector3.ZERO
	return basis + Vector3(0.0, 0.0, 9.0)


static func _plan() -> Dictionary:
	if not plan_override.is_empty():
		return plan_override
	# RW-1s Welt defensiv befragen: Klasse kann in Teil-Checkouts fehlen
	# oder ihre Form ändern — dann greifen die Fallback-Anker.
	var welt: Variant = load("res://scripts/ranch/ranch_welt.gd")
	if welt is GDScript and (welt as GDScript).has_method("hof_plan"):
		var plan: Variant = (welt as GDScript).hof_plan()
		if plan is Dictionary:
			return plan
	return {}
