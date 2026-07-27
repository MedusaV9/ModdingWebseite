class_name GalerieLogic
extends RefCounted
## Pure Fotogalerie-Logik (REST-4, EVAL Rang 14): normalisierte Sicht auf
## den Foto-Index im city-Slice (`city.fotos`, FotoModus-Format
## {pfad, at, ort?}), Favoriten-Toggle (additives `fav`-Flag am Eintrag —
## KEIN Version-Bump), Löschen aus dem Index und die Speicheranzeige
## (Deckel = FotoModus.MAX_FOTOS, Web-Cap 40).

## Foto-Deckel (identisch FotoModus.MAX_FOTOS — der Index ist gedeckelt).
const MAX_FOTOS := 40


## Normalisierte Foto-Liste (jüngste zuerst; Junk-Einträge fallen raus).
static func fotos_von(state: Dictionary) -> Array:
	var city: Variant = state.get("city")
	if not (city is Dictionary):
		return []
	var raw: Variant = (city as Dictionary).get("fotos")
	if not (raw is Array):
		return []
	var out: Array = []
	for eintrag: Variant in raw:
		if not (eintrag is Dictionary):
			continue
		var pfad := str((eintrag as Dictionary).get("pfad", ""))
		if pfad.is_empty():
			continue
		(
			out
			. append(
				{
					"pfad": pfad,
					"at": int(_num((eintrag as Dictionary).get("at"))),
					"ort": str((eintrag as Dictionary).get("ort", "")),
					"fav":
					(
						(eintrag as Dictionary).get("fav", false) is bool
						and bool((eintrag as Dictionary).get("fav", false))
					),
				}
			)
		)
	return out


## Nur die Favoriten.
static func favoriten(fotos: Array) -> Array:
	return fotos.filter(func(foto: Dictionary) -> bool: return bool(foto.get("fav", false)))


## Speicheranzeige: {n, max}.
static func speicher(state: Dictionary) -> Dictionary:
	return {"n": fotos_von(state).size(), "max": MAX_FOTOS}


## Favorit togglen (mutiert den Save-Draft; Rückgabe = neuer Zustand).
static func toggle_favorit(state: Dictionary, pfad: String) -> bool:
	var eintrag := _finde(state, pfad)
	if eintrag.is_empty():
		return false
	var neu := not (eintrag.get("fav", false) is bool and bool(eintrag.get("fav", false)))
	if neu:
		eintrag["fav"] = true
	else:
		eintrag.erase("fav")
	return neu


## Foto aus dem Index nehmen (Datei löscht der Aufrufer). true = entfernt.
static func entferne(state: Dictionary, pfad: String) -> bool:
	var city: Variant = state.get("city")
	if not (city is Dictionary):
		return false
	var liste: Variant = (city as Dictionary).get("fotos")
	if not (liste is Array):
		return false
	for i in (liste as Array).size():
		var eintrag: Variant = (liste as Array)[i]
		if eintrag is Dictionary and str((eintrag as Dictionary).get("pfad", "")) == pfad:
			(liste as Array).remove_at(i)
			return true
	return false


## Anzeigename eines Aufnahmeorts: `galerie.ort_<id>`-Key, sonst die
## CityMap (Ortsname), sonst "Unterwegs".
static func ort_name(ort: String) -> String:
	if ort.is_empty():
		return I18nService.t("galerie.ort_unbekannt")
	var key := "galerie.ort_%s" % ort
	if I18nService.has_key(key):
		return I18nService.t(key)
	var name_key := "city.ort.%s" % ort
	if I18nService.has_key(name_key):
		return I18nService.t(name_key)
	return ort.capitalize()


## Datum "TT.MM.JJJJ, HH:MM" aus einem Epoch-ms-Stempel.
static func datum(at_ms: int) -> String:
	@warning_ignore("integer_division")
	var d := Time.get_datetime_dict_from_unix_time(at_ms / 1000)
	return (
		"%02d.%02d.%04d, %02d:%02d"
		% [int(d["day"]), int(d["month"]), int(d["year"]), int(d["hour"]), int(d["minute"])]
	)


static func _finde(state: Dictionary, pfad: String) -> Dictionary:
	var city: Variant = state.get("city")
	if not (city is Dictionary):
		return {}
	var liste: Variant = (city as Dictionary).get("fotos")
	if not (liste is Array):
		return {}
	for eintrag: Variant in liste:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("pfad", "")) == pfad:
			return eintrag
	return {}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
