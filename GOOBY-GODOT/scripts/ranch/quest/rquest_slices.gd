class_name RQuestSlices
extends RefCounted
## Save-Unterschlüssel des Ranch-DLC (RW-3): `ranch.quests` + `ranch.npc` —
## ADDITIV im `ranch`-Slice, KEIN Save-Version-Bump (Slice-Registry-Muster,
## s. save_schema.gd Header und RanchPlaySlices als Vorbild).
##
## Besitzlage: RANCH-1 (RanchState) besitzt den Top-Level-Slice `ranch`;
## sein normalize erhält fremde Schlüssel VERBATIM — meine Unterschlüssel
## überleben also jede Heilung. Damit sie trotzdem IMMER wohlgeformt sind,
## heilen alle RW-3-Zugriffe (RQuestState/RNpc*) beim LESEN über
## normalize_quests()/normalize_npc() (normalize-on-read). Läuft RW-3-Code
## in einem Prozess ganz ohne ranch-Registrierung (isolierte Tests),
## registriert ensure_registered() den Slice defensiv selbst — und weicht
## aus, wenn `ranch` bereits registriert ist.
##
## Struktur (alle Zeiten epoch-ms, Tage als YYYY-MM-DD):
##   ranch.quests = {v, aktiv:{questId:{status, zielIndex, zaehler,
##     bereitAt, angenommenAt}}, erledigt:[questId],
##     tages:{datum, erledigt:[questId]}, freigeschaltet:[id]}
##   ranch.npc = {v, freunde:{npcId:{punkte, geredetTag, geschenkTag,
##     letzteBegegnungAt, geschichtenGehoert:[knoten]}}}

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "ranch"
## Quest-Status-Werte im Save (verfügbar/erledigt sind abgeleitet:
## verfügbar = weder aktiv noch erledigt; erledigt = in `erledigt`).
const STATUS_AKTIV := "aktiv"
const STATUS_WARTEND := "wartend"
const STATUS_ERFUELLBAR := "erfuellbar"
const STATI: Array[String] = [STATUS_AKTIV, STATUS_WARTEND, STATUS_ERFUELLBAR]

static var _registered := false


## Slice defensiv registrieren (idempotent). Ist `ranch` schon registriert
## (RANCH-1/RANCH-2 zuerst), passiert bewusst NICHTS — Re-Registrierung
## würde deren Registrierung ersetzen.
static func ensure_registered() -> void:
	if _registered:
		return
	if SaveSchema.registered_slice_ids().has(SLICE_ID):
		_registered = true
		return
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)
	_registered = true


## Nur für Tests: Registrier-Merker zurücksetzen (Registry ist prozessweit).
static func reset_for_tests() -> void:
	_registered = false


## Kompletter ranch-Slice-Default (nur MEINE Unterschlüssel; RANCH-1/-2
## ergänzen ihre eigenen additiv).
static func default_slice() -> Dictionary:
	return {"v": 1, "quests": default_quests(), "npc": default_npc()}


## Self-Heal des ranch-Slices: MEINE Unterschlüssel normalisieren, alle
## fremden Schlüssel VERBATIM erhalten (RANCH-1/-2-Daten überleben).
static func normalize_slice(raw: Variant) -> Dictionary:
	var ranch: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	ranch["v"] = maxi(1, int(_num(ranch.get("v"), 1.0)))
	ranch["quests"] = normalize_quests(ranch.get("quests"))
	ranch["npc"] = normalize_npc(ranch.get("npc"))
	return ranch


static func default_quests() -> Dictionary:
	return {
		"v": 1,
		"aktiv": {},
		"erledigt": [],
		"tages": {"datum": "", "erledigt": []},
		"freigeschaltet": [],
	}


## quests-Unterschlüssel heilen: Typen reparieren, kaputte Einträge
## verwerfen, gültige VERBATIM erhalten.
static func normalize_quests(raw: Variant) -> Dictionary:
	var quests: Dictionary = raw if raw is Dictionary else default_quests()
	quests["v"] = maxi(1, int(_num(quests.get("v"), 1.0)))
	var roh_aktiv: Dictionary = quests.get("aktiv") if quests.get("aktiv") is Dictionary else {}
	var aktiv := {}
	for id: Variant in roh_aktiv.keys():
		if roh_aktiv[id] is Dictionary:
			aktiv[str(id)] = _normalize_lauf(roh_aktiv[id])
	quests["aktiv"] = aktiv
	quests["erledigt"] = _string_liste(quests.get("erledigt"))
	var tages: Dictionary = quests.get("tages") if quests.get("tages") is Dictionary else {}
	quests["tages"] = {
		"datum": str(tages.get("datum", "")) if tages.get("datum") is String else "",
		"erledigt": _string_liste(tages.get("erledigt")),
	}
	quests["freigeschaltet"] = _string_liste(quests.get("freigeschaltet"))
	return quests


## Fabrik für einen frischen Quest-Lauf (Annahme-Zeitpunkt in ms).
static func neuer_lauf(now_ms: int) -> Dictionary:
	return {
		"status": STATUS_AKTIV,
		"zielIndex": 0,
		"zaehler": 0,
		"bereitAt": 0,
		"angenommenAt": maxi(0, now_ms),
	}


static func default_npc() -> Dictionary:
	return {"v": 1, "freunde": {}}


## npc-Unterschlüssel heilen.
static func normalize_npc(raw: Variant) -> Dictionary:
	var npc: Dictionary = raw if raw is Dictionary else default_npc()
	npc["v"] = maxi(1, int(_num(npc.get("v"), 1.0)))
	var roh: Dictionary = npc.get("freunde") if npc.get("freunde") is Dictionary else {}
	var freunde := {}
	for id: Variant in roh.keys():
		if roh[id] is Dictionary:
			freunde[str(id)] = _normalize_freund(roh[id])
	npc["freunde"] = freunde
	return npc


## Fabrik für einen frischen Freundschafts-Eintrag.
static func neuer_freund() -> Dictionary:
	return {
		"punkte": 0.0,
		"geredetTag": "",
		"geschenkTag": "",
		"letzteBegegnungAt": 0,
		"geschichtenGehoert": [],
	}


static func _normalize_lauf(raw: Dictionary) -> Dictionary:
	var lauf := neuer_lauf(0)
	var status := str(raw.get("status", STATUS_AKTIV))
	lauf["status"] = status if STATI.has(status) else STATUS_AKTIV
	lauf["zielIndex"] = maxi(0, int(_num(raw.get("zielIndex"), 0.0)))
	lauf["zaehler"] = maxi(0, int(_num(raw.get("zaehler"), 0.0)))
	lauf["bereitAt"] = maxi(0, int(_num(raw.get("bereitAt"), 0.0)))
	lauf["angenommenAt"] = maxi(0, int(_num(raw.get("angenommenAt"), 0.0)))
	return lauf


static func _normalize_freund(raw: Dictionary) -> Dictionary:
	var freund := neuer_freund()
	freund["punkte"] = clampf(_num(raw.get("punkte"), 0.0), 0.0, 100.0)
	freund["geredetTag"] = str(raw.get("geredetTag", "")) if raw.get("geredetTag") is String else ""
	freund["geschenkTag"] = (
		str(raw.get("geschenkTag", "")) if raw.get("geschenkTag") is String else ""
	)
	freund["letzteBegegnungAt"] = maxi(0, int(_num(raw.get("letzteBegegnungAt"), 0.0)))
	freund["geschichtenGehoert"] = _string_liste(raw.get("geschichtenGehoert"))
	return freund


## Rohliste → deduplizierte String-Liste (kaputte Einträge fliegen raus).
static func _string_liste(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for eintrag: Variant in raw:
			if eintrag is String and not out.has(eintrag):
				out.append(eintrag)
	return out


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
