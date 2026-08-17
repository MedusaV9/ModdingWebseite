class_name GoobyBuffs
extends RefCounted
## Buff-System (W3d CONTENT, Doc F §4.1): Event-Rewards sind Zeit-Buffs
## `{stat, delta, until_ms}` — sichtbar an der Stat-Leiste (H-UI, M2-Anbindung).
## Buffs stapeln NICHT pro buff_id (Doc F: „stapeln nicht pro Event-Id“) —
## erneutes Gewähren ersetzt den Eintrag und verlängert nur die Laufzeit.
##
## Slice-Registrierung via W1d-SaveSchema-Registry (GODOT-PLAN §W1d-Zeile:
## W3d meldet `events`+`stickers`(vorhanden)+`buffs` an). Alle Funktionen
## static; pure Logik nimmt den Slice als Dictionary (headless testbar).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "buffs"
const MS_PER_HOUR := 3_600_000

static var _registered := false


## Idempotent — MUSS vor GameState.initialize() laufen (frische Saves).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"aktiv": []}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	if not (slice.get("aktiv") is Array):
		slice["aktiv"] = []
	var aktiv: Array = slice["aktiv"]
	for i in range(aktiv.size() - 1, -1, -1):
		var buff: Variant = aktiv[i]
		if not (buff is Dictionary) or str(buff.get("id", "")) == "":
			aktiv.remove_at(i)
	return slice


# ── pure Logik (Slice rein/raus, keine Nodes) ────────────────────────────────


## Buff setzen/ersetzen (kein Stacking pro id). Mutiert `slice`, gibt den
## Buff-Eintrag zurück.
static func add_buff(
	slice: Dictionary, buff_id: String, stat: String, wert: float, dauer_h: float, now_ms: int
) -> Dictionary:
	var buff := {
		"id": buff_id,
		"stat": stat,
		"wert": wert,
		"until_ms": now_ms + int(dauer_h * MS_PER_HOUR),
	}
	var aktiv: Array = slice.get("aktiv", [])
	for i in aktiv.size():
		if str(aktiv[i].get("id", "")) == buff_id:
			aktiv[i] = buff
			return buff
	aktiv.append(buff)
	slice["aktiv"] = aktiv
	return buff


## Aktive (nicht abgelaufene) Buffs zum Zeitpunkt now_ms.
static func active(slice: Dictionary, now_ms: int) -> Array:
	var result: Array = []
	for buff: Variant in slice.get("aktiv", []):
		if buff is Dictionary and int(buff.get("until_ms", 0)) > now_ms:
			result.append(buff)
	return result


## Abgelaufene Buffs entfernen (mutiert). Gibt Anzahl entfernter zurück.
static func prune(slice: Dictionary, now_ms: int) -> int:
	var aktiv: Array = slice.get("aktiv", [])
	var removed := 0
	for i in range(aktiv.size() - 1, -1, -1):
		if int(aktiv[i].get("until_ms", 0)) <= now_ms:
			aktiv.remove_at(i)
			removed += 1
	return removed


## Summierter Bonus auf eine Stat ("fun"/"hunger"/…) zum Zeitpunkt now_ms.
static func stat_bonus(slice: Dictionary, stat: String, now_ms: int) -> float:
	var total := 0.0
	for buff: Variant in active(slice, now_ms):
		if str(buff.get("stat", "")) == stat:
			total += float(buff.get("wert", 0.0))
	return total


# ── GameState-Glue ───────────────────────────────────────────────────────────


## Buff über den Store gewähren (Signale + Autosave via update()).
static func grant(
	gs: Object, buff_id: String, stat: String, wert: float, dauer_h: float, now_ms: int
) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = default_slice()
			prune(state[SLICE_ID], now_ms)
			add_buff(state[SLICE_ID], buff_id, stat, wert, dauer_h, now_ms)
	)
	gs.notify_slice_changed(SLICE_ID)


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false
