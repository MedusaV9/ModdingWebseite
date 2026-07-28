class_name SoulState
extends RefCounted
## Soul-Save-Slice (FB-6/SEELE, additiv per SaveSchema-Registry — Muster wie
## RandomEventEngine.register_slice). Merkt sich alles, was Gooby über DICH
## und eure gemeinsame Zeit weiß: erster Kennenlern-Tag, letzter Besuch,
## Geburtstage, gefeierte Rituale, gezeigte Erinnerungen, Lieblingsessen
## (aus echten Fütterungen), bekannte Möbel (für Neuanschaffungs-Kommentare)
## und die globale Frequenzbremse (nie aufdringlich!).
##
## Pure Statics, Zeit wird IMMER hereingereicht — headless testbar.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "soul"

static var _registered := false


## Idempotent — vor GameState.initialize() bzw. beim Raum-Attach nachziehen
## (Registry ersetzt Re-Registrierungen, s. save_schema.gd Header).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"firstMetAt": 0,
		"lastVisitAt": 0,
		"lastGreetDay": "",
		"lastGreetKind": "",
		"playerBirthday": {"month": 0, "day": 0},
		"askedBirthdayAt": 0,
		"celebrated": {},
		"memoryShownAt": {},
		"surpriseAt": {},
		"knownItems": {},
		"favFurniture": "",
		"foodGiven": {},
		"ambient": {"day": "", "count": 0, "lastAt": 0},
		"totalMoments": 0,
		# SEELE-2 (additiv, KEIN Version-Bump): durchgehende Stimmung +
		# Goobys aktueller kleiner Wunsch ({id, seitMs}) + erfüllte Wünsche.
		"stimmung": SoulMood.default_stimmung(),
		"wunsch": {},
		"wunschErfuellt": {},
		# FEEL-AC (additiv): Frequenzbremse + Gates der inszenierten Gefühle.
		"feelings": SoulFeelings.default_feelings(),
	}


## Self-Heal (Web-mergeDefaults-Stil): kaputte Typen fallen auf Defaults.
static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else {}
	var out := default_slice()
	for key in ["firstMetAt", "lastVisitAt", "askedBirthdayAt", "totalMoments"]:
		out[key] = maxi(0, int(_num(slice.get(key))))
	for key in ["lastGreetDay", "lastGreetKind", "favFurniture"]:
		if slice.get(key) is String:
			out[key] = slice[key]
	out["playerBirthday"] = _normalize_birthday(slice.get("playerBirthday"))
	var map_keys := ["celebrated", "memoryShownAt", "surpriseAt", "knownItems", "foodGiven"]
	map_keys.append_array(["wunsch", "wunschErfuellt"])
	for key: String in map_keys:
		if slice.get(key) is Dictionary:
			out[key] = (slice[key] as Dictionary).duplicate(true)
	out["stimmung"] = SoulMood.normalize(slice.get("stimmung"))
	out["feelings"] = SoulFeelings.normalize(slice.get("feelings"))
	var ambient: Variant = slice.get("ambient")
	if ambient is Dictionary:
		out["ambient"] = {
			"day": str(ambient.get("day", "")),
			"count": maxi(0, int(_num(ambient.get("count")))),
			"lastAt": maxi(0, int(_num(ambient.get("lastAt")))),
		}
	return out


## Monat/Tag nur, wenn beides ein plausibles Datum ergibt — sonst ungesetzt.
static func _normalize_birthday(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		var month := int(_num(raw.get("month")))
		var day := int(_num(raw.get("day")))
		if month >= 1 and month <= 12 and day >= 1 and day <= 31:
			return {"month": month, "day": day}
	return {"month": 0, "day": 0}


## Slice aus dem GameState lesen (immer normalisiert — nie roh vertrauen).
static func slice_of(gs: Object) -> Dictionary:
	return normalize_slice(gs.get_value(SLICE_ID, {}))


## Erst-Setup + Besuchs-Stempel: firstMetAt einmalig (Fallback: meta.createdAt,
## der Tag, an dem Gooby eingezogen ist == Goobys Geburtstag). Gibt die
## Lücke seit dem letzten Besuch in ms zurück (0 beim allerersten Mal).
static func touch_visit(gs: Object, now_ms: int) -> int:
	var slice := slice_of(gs)
	var last := int(slice["lastVisitAt"])
	var gap := (now_ms - last) if last > 0 else 0
	gs.update(
		func(state: Dictionary) -> void:
			var s := _ensure(state)
			if int(_num(s.get("firstMetAt"))) <= 0:
				var created := int(_num(state.get("meta", {}).get("createdAt")))
				s["firstMetAt"] = created if created > 0 else now_ms
			s["lastVisitAt"] = now_ms
	)
	gs.notify_slice_changed(SLICE_ID)
	return maxi(0, gap)


## Generischer Slice-Schreibzugriff für den Service (ein update()-Pfad).
static func mutate(gs: Object, mutator: Callable) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var s := _ensure(state)
			mutator.call(s)
	)
	gs.notify_slice_changed(SLICE_ID)


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


static func _ensure(state: Dictionary) -> Dictionary:
	state[SLICE_ID] = normalize_slice(state.get(SLICE_ID))
	return state[SLICE_ID]


static func _num(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0
