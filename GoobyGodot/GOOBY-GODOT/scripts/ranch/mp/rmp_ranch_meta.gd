class_name RmpRanchMeta
extends RefCounted
## Ranch-Metadaten für den Freundes-Besuch (RW-6) — PURE Builder/Validator.
## Der Host lädt vor dem Besuch ein kleines JSON hoch (PUT /api/ranch,
## Server-Limit 16 KB), der Gast rendert daraus Ausbau, Pferde (Name/Rasse/
## Level) und Trophäen. Es reisen NUR Anzeige-Daten — nie Wirtschaft/Lager
## (keine Manipulations-Fläche, Doc RANCH-DLC-IDEAS-4 §2.2).
##
## Quellen (Lese-APIs fremder Module, additiv):
##   ranch.wirtschaft.ausbau   (RanchPlaySlices)   → boxen/reitplatz/weidezaun
##   ranch.tiere.pferde        (RanchPlaySlices)   → name/rasse/level/farbe
##   ranch.comp                (RanchCompState)    → trophaeen/schleifen
##   meta.playerName/goobyNickname (GameState)

const MAX_BYTES := 16 * 1024
const MAX_PFERDE := 12
const MAX_TROPHAEEN := 24
const MAX_NAME_LEN := 24


## Meta-Snapshot aus dem Save bauen (gs = GameState oder Test-Double).
static func build_from_state(gs: Object) -> Dictionary:
	var meta := {
		"v": 1,
		"name": _kurz(str(_wert(gs, "meta.playerName", "Gooby-Fan"))),
		"goobyName": _kurz(str(_wert(gs, "meta.goobyNickname", "Gooby"))),
		"ausbau": {"boxen": 1, "reitplatz": false, "weidezaun": false},
		"pferde": [],
		"trophaeen": [],
		"schleifen": 0,
	}
	var ausbau: Variant = _wert(gs, "ranch.wirtschaft.ausbau", {})
	if ausbau is Dictionary:
		meta["ausbau"] = {
			"boxen": clampi(int(_num((ausbau as Dictionary).get("boxen"), 1.0)), 1, 3),
			"reitplatz": bool((ausbau as Dictionary).get("reitplatz", false)),
			"weidezaun": bool((ausbau as Dictionary).get("weidezaun", false)),
		}
	var pferde_roh: Variant = _wert(gs, "ranch.tiere.pferde", {})
	if pferde_roh is Dictionary:
		var pferde: Array = []
		for id: Variant in pferde_roh as Dictionary:
			if pferde.size() >= MAX_PFERDE:
				break
			var pferd: Variant = (pferde_roh as Dictionary)[id]
			if not (pferd is Dictionary):
				continue
			(
				pferde
				. append(
					{
						"name": _kurz(str((pferd as Dictionary).get("name", ""))),
						"rasse": str((pferd as Dictionary).get("rasse", "puschelhufer")),
						"level": clampi(int(_num((pferd as Dictionary).get("level"), 1.0)), 1, 99),
						"farbe": str((pferd as Dictionary).get("farbe", "braun")),
					}
				)
			)
		meta["pferde"] = pferde
	var comp := RanchCompState.lese(gs)
	var trophaeen: Array = comp.get("trophaeen", [])
	meta["trophaeen"] = trophaeen.slice(0, MAX_TROPHAEEN)
	meta["schleifen"] = (comp.get("schleifen", {}) as Dictionary).size()
	return meta


## Prüfung vor Upload UND nach Download (Fremd-Daten heilen/abweisen).
static func validate(meta: Variant) -> Dictionary:
	if not (meta is Dictionary):
		return {"ok": false, "reason": "BAD_META"}
	var text := JSON.stringify(meta)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok": false, "reason": "TOO_LARGE"}
	if not ((meta as Dictionary).get("pferde") is Array):
		return {"ok": false, "reason": "BAD_META"}
	if ((meta as Dictionary)["pferde"] as Array).size() > MAX_PFERDE:
		return {"ok": false, "reason": "TOO_MANY_HORSES"}
	return {"ok": true, "reason": ""}


## Geheilte Anzeige-Form für den Gast (nie fremdem JSON blind trauen).
static func normalize(meta: Variant) -> Dictionary:
	var roh: Dictionary = meta if meta is Dictionary else {}
	var sauber := {
		"v": 1,
		"name": _kurz(str(roh.get("name", "?"))),
		"goobyName": _kurz(str(roh.get("goobyName", "Gooby"))),
		"ausbau": {"boxen": 1, "reitplatz": false, "weidezaun": false},
		"pferde": [],
		"trophaeen": [],
		"schleifen": maxi(0, int(_num(roh.get("schleifen"), 0.0))),
	}
	if roh.get("ausbau") is Dictionary:
		var ausbau: Dictionary = roh["ausbau"]
		sauber["ausbau"] = {
			"boxen": clampi(int(_num(ausbau.get("boxen"), 1.0)), 1, 3),
			"reitplatz": bool(ausbau.get("reitplatz", false)),
			"weidezaun": bool(ausbau.get("weidezaun", false)),
		}
	if roh.get("pferde") is Array:
		for pferd: Variant in (roh["pferde"] as Array).slice(0, MAX_PFERDE):
			if pferd is Dictionary:
				(
					(sauber["pferde"] as Array)
					. append(
						{
							"name": _kurz(str((pferd as Dictionary).get("name", "?"))),
							"rasse": str((pferd as Dictionary).get("rasse", "puschelhufer")),
							"level":
							clampi(int(_num((pferd as Dictionary).get("level"), 1.0)), 1, 99),
							"farbe": str((pferd as Dictionary).get("farbe", "braun")),
						}
					)
				)
	if roh.get("trophaeen") is Array:
		for id: Variant in (roh["trophaeen"] as Array).slice(0, MAX_TROPHAEEN):
			if id is String:
				(sauber["trophaeen"] as Array).append(id)
	return sauber


static func _wert(gs: Object, key: String, fallback: Variant) -> Variant:
	if gs == null or not gs.has_method("get_value"):
		return fallback
	return gs.get_value(key, fallback)


static func _kurz(text: String) -> String:
	return text.substr(0, MAX_NAME_LEN)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
