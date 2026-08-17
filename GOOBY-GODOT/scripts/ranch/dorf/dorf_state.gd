class_name RanchDorfState
extends RefCounted
## Save-Anbindung des Reit-Dorfs Hufingen (RW-4) — ADDITIVER Unterschlüssel
## `ranch.dorf` im ranch-Slice, KEIN Save-Version-Bump. RanchState erhält
## fremde Schlüssel verbatim; dieses Modul heilt beim Lesen selbst
## (Self-Heal-Muster wie RanchBauState).
##
## Struktur ranch.dorf:
##   v, entdeckt (bool — erst nach dem ERSTEN Anritt; Schnellreise-Gate),
##   entdecktAm (ms), futter {hafer, leckerli}, hufeisen {owned, proPferd},
##   verkauft {tag, angebote — heute verkaufte Händler-Pferde},
##   pferdeGekauft/pferdeVerkauft (Statistik).

const SLICE_ID := "ranch"
const KEY := "dorf"


static func default_dorf() -> Dictionary:
	return {
		"v": 1,
		"entdeckt": false,
		"entdecktAm": 0,
		"futter": {"hafer": 0, "leckerli": 0},
		"hufeisen": {"owned": [], "proPferd": {}},
		"verkauft": {"tag": "", "angebote": []},
		"pferdeGekauft": 0,
		"pferdeVerkauft": 0,
	}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten.
static func normalize_dorf(raw: Variant) -> Dictionary:
	var dorf: Dictionary = raw.duplicate(true) if raw is Dictionary else default_dorf()
	dorf["v"] = maxi(1, int(_num(dorf.get("v"), 1.0)))
	dorf["entdeckt"] = bool(dorf.get("entdeckt", false))
	dorf["entdecktAm"] = maxi(0, int(_num(dorf.get("entdecktAm"), 0.0)))
	var futter: Dictionary = dorf.get("futter") if dorf.get("futter") is Dictionary else {}
	dorf["futter"] = {
		"hafer": maxi(0, int(_num(futter.get("hafer"), 0.0))),
		"leckerli": maxi(0, int(_num(futter.get("leckerli"), 0.0))),
	}
	var hufeisen: Dictionary = dorf.get("hufeisen") if dorf.get("hufeisen") is Dictionary else {}
	var owned: Array = hufeisen.get("owned") if hufeisen.get("owned") is Array else []
	var owned_clean: Array = []
	for id: Variant in owned:
		if id is String and not owned_clean.has(id):
			owned_clean.append(id)
	var pro_pferd: Dictionary = (
		hufeisen.get("proPferd") if hufeisen.get("proPferd") is Dictionary else {}
	)
	dorf["hufeisen"] = {"owned": owned_clean, "proPferd": pro_pferd.duplicate(true)}
	var verkauft: Dictionary = dorf.get("verkauft") if dorf.get("verkauft") is Dictionary else {}
	dorf["verkauft"] = {
		"tag": str(verkauft.get("tag", "")) if verkauft.get("tag") is String else "",
		"angebote": verkauft.get("angebote") if verkauft.get("angebote") is Array else [],
	}
	dorf["pferdeGekauft"] = maxi(0, int(_num(dorf.get("pferdeGekauft"), 0.0)))
	dorf["pferdeVerkauft"] = maxi(0, int(_num(dorf.get("pferdeVerkauft"), 0.0)))
	return dorf


## Normalisierter ranch.dorf-Stand aus dem GameState.
static func lese(gs: Object) -> Dictionary:
	if gs == null:
		return default_dorf()
	return normalize_dorf(gs.get_value("ranch.dorf", {}))


## Hufingen schon entdeckt? (Schnellreise erst nach dem ersten Anritt.)
static func ist_entdeckt(gs: Object) -> bool:
	return bool(lese(gs).get("entdeckt", false))


## Ankunft im Dorf: Entdeckung merken (idempotent). true = NEU entdeckt.
static func entdecke(gs: Object) -> bool:
	if gs == null or ist_entdeckt(gs):
		return false
	var jetzt := now_ms(gs)
	gs.update(
		func(state: Dictionary) -> void:
			var dorf := dorf_im_state(state)
			dorf["entdeckt"] = true
			dorf["entdecktAm"] = jetzt
	)
	gs.notify_slice_changed(SLICE_ID)
	return true


## Heutiger Tages-String (Händler-Rotation): Clock des GameState, sonst
## Systemdatum — deterministisch pro lokalem Tag.
static func heute(gs: Object) -> String:
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	var datum := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [datum["year"], datum["month"], datum["day"]]


static func now_ms(gs: Object) -> int:
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


## ranch.dorf innerhalb eines gs.update()-Blocks holen (+ normalisieren).
static func dorf_im_state(state: Dictionary) -> Dictionary:
	var ranch: Dictionary = state.get(SLICE_ID) if state.get(SLICE_ID) is Dictionary else {}
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = ranch
	var dorf := normalize_dorf(ranch.get(KEY))
	ranch[KEY] = dorf
	return dorf


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
