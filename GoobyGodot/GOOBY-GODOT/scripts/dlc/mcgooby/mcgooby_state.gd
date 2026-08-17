class_name McGoobyState
extends RefCounted
## McGooby-Slice-Anbindung ans GameState (Welle A+B) — via FROZEN Slice-Registry,
## Muster RanchState/CityState. Alle Funktionen static, `gs` = Duck-Typing
## (`/root/GameState` oder Test-Double mit get_value/set_value). ADDITIV:
## neuer Slice `mcgooby` über register_slice, KEIN Save-Version-Bump
## (Doc §10.1: additive Unterschlüssel mit normalize-Self-Heal).
##
## Slice-Struktur Welle B (Doc §10.1 `besitz` + Demo-Gate der Probeschicht):
##   mcgooby.v,
##   mcgooby.introGesehen (bool — Eröffnungs-Hook-Karte lief, Doc §1.3),
##   mcgooby.gekauft (bool) + gekauftAm (ms) — Kauf-Gate (McGoobyKauf),
##   mcgooby.angebotGesehen / angebotVerschoben (Muster GoobyeState),
##   mcgooby.demoTag (String YYYY-MM-DD — letzte Probeschicht VOR dem Kauf;
##     genau EINE Demo-Schicht pro lokalem Tag, nach Kauf unbegrenzt),
##   mcgooby.schichten { gespielt (int), bestwert (int Punkte),
##     perfekt (int — fehlerfreie Schichten, Welle C: Rang-Futter für den
##     Laden-Sterne-Fortschritt, McGoobyFortschritt/Doc §6.1),
##     rangGefeiert (int 0..5 — höchster bereits GEFEIERTER Laden-Rang:
##     Save-Latch des Aufstiegs-Beats, W20 — genau EIN Konfetti-Moment
##     pro erreichter Stufe, Reload-fest; McGoobyFortschritt.aufstieg_pruefen) }.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "mcgooby"

static var _registered := false


## Registriert den mcgooby-Slice (idempotent, VOR GameState.initialize() —
## seit Welle B steht der Slice zusätzlich in der Boot-Registry
## DEFAULT_SLICE_SCRIPTS, weil der KAUF im Hub läuft, bevor je eine
## McGooby-Szene lädt; W18/B1-Lehre).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"v": 1,
		"introGesehen": false,
		"gekauft": false,
		"gekauftAm": 0,
		"angebotGesehen": false,
		"angebotVerschoben": false,
		"demoTag": "",
		"schichten": {"gespielt": 0, "bestwert": 0, "perfekt": 0, "rangGefeiert": 0},
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten (Muster
## RanchState.normalize_slice — Alt-Saves ohne Slice bekommen Defaults,
## Welle-A-Saves die neuen Besitz-/Demo-Felder als Defaults dazu).
static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	slice["v"] = maxi(1, int(slice.get("v", 1)))
	slice["introGesehen"] = bool(slice.get("introGesehen", false))
	slice["gekauft"] = bool(slice.get("gekauft", false))
	slice["gekauftAm"] = maxi(0, int(slice.get("gekauftAm", 0)))
	slice["angebotGesehen"] = bool(slice.get("angebotGesehen", false))
	slice["angebotVerschoben"] = bool(slice.get("angebotVerschoben", false))
	slice["demoTag"] = str(slice.get("demoTag", ""))
	var schichten: Dictionary = (
		slice.get("schichten") if slice.get("schichten") is Dictionary else {}
	)
	schichten["gespielt"] = maxi(0, int(schichten.get("gespielt", 0)))
	schichten["bestwert"] = maxi(0, int(schichten.get("bestwert", 0)))
	schichten["perfekt"] = maxi(0, int(schichten.get("perfekt", 0)))
	schichten["rangGefeiert"] = clampi(
		int(schichten.get("rangGefeiert", 0)), 0, McGoobyFortschritt.MAX_STERNE
	)
	slice["schichten"] = schichten
	return slice


## Ensure-Muster (GoobyeState.ensure_goobye): fehlenden/kaputten Slice im
## update-Block anlegen/heilen — der Kauf läuft im Hub, BEVOR je eine
## McGooby-Szene registriert hat (W18/B1: nie Geld weg ohne Leistung).
static func ensure_mcgooby(state: Dictionary) -> Dictionary:
	state[SLICE_ID] = normalize_slice(state.get(SLICE_ID))
	return state[SLICE_ID]


## Eröffnungs-Hook schon gesehen? (Erststart-Erkennung der Schicht-Szene.)
static func ist_intro_gesehen(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("mcgooby.introGesehen", false))


static func setze_intro_gesehen(gs: Object) -> void:
	if gs != null:
		gs.set_value("mcgooby.introGesehen", true)


## ---------------------------------------------------------- Kauf & Gate


## Laden gekauft?
static func ist_gekauft(gs: Object) -> bool:
	return gs != null and bool(gs.get_value("mcgooby.gekauft", false))


## Level-Gate: ab diesem Level ist der Kauf freigeschaltet (Balance-Pack,
## Doc §6.2: Level 14 — McGoobyKatalog.freischalt_level). Die Probeschicht
## selbst bleibt davon unberührt (Demo-Teaser für ALLE, s. schicht_erlaubt).
static func ist_freigeschaltet(gs: Object) -> bool:
	if gs == null:
		return false
	var level := int(gs.get_value("progression.level", 1))
	return level >= McGoobyKatalog.freischalt_level()


## „Später kaufen“: Angebot gesehen + verschoben merken (Muster GoobyeState).
static func angebot_verschieben(gs: Object) -> void:
	if gs == null:
		return
	gs.set_value("mcgooby.angebotGesehen", true)
	gs.set_value("mcgooby.angebotVerschoben", true)


## ---------------------------------------------------------- Demo-Gate


## Lokaler Kalendertag als Gate-Schlüssel — Zeit IMMER injiziert: hängt am
## gs eine Clock (GameState.clock), zählt DIE; sonst die Systemuhr (Muster
## GoobyeKauf._now_ms). Tests pinnen die Clock oder reichen den Tag direkt.
static func heute_tag(gs: Object) -> String:
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	return Time.get_date_string_from_system()


## Darf JETZT eine Schicht starten? Nach Kauf immer; vorher genau EINE
## Probeschicht pro Tag (Teaser). Ohne GameState (isolierte Screens) offen —
## es gibt dann nichts zu verbuchen.
static func schicht_erlaubt(gs: Object, tag: String) -> bool:
	if gs == null:
		return true
	if ist_gekauft(gs):
		return true
	return str(gs.get_value("mcgooby.demoTag", "")) != tag


## Probeschicht des Tages verbuchen (idempotent; nach dem Kauf ein No-op —
## gekaufte Läden brauchen keinen Demo-Stempel mehr).
static func demo_verbuchen(gs: Object, tag: String) -> void:
	if gs == null or ist_gekauft(gs):
		return
	gs.set_value("mcgooby.demoTag", tag)


## Schicht verbuchen: Zähler hoch, Bestwert = Maximum (nie runter);
## fehlerfreie Schichten zählen zusätzlich für den Rang (Welle C).
static func schicht_verbuchen(gs: Object, punkte: int, fehlerfrei := false) -> void:
	if gs == null:
		return
	var gespielt := int(gs.get_value("mcgooby.schichten.gespielt", 0))
	gs.set_value("mcgooby.schichten.gespielt", gespielt + 1)
	var bestwert := int(gs.get_value("mcgooby.schichten.bestwert", 0))
	gs.set_value("mcgooby.schichten.bestwert", maxi(bestwert, maxi(0, punkte)))
	if fehlerfrei:
		var perfekt := int(gs.get_value("mcgooby.schichten.perfekt", 0))
		gs.set_value("mcgooby.schichten.perfekt", perfekt + 1)


static func reset_for_tests() -> void:
	_registered = false
