class_name CodesEngine
extends RefCounted
## Offline-Codes-Engine (REST-4, EVAL Rang 11) — PURER Port von
## GOOBY/src/systems/codesEngine.js + data/codes.js (§B6/§C-SYS5, verbatim):
##   normalize()          trim → lowercase → ALLE Leerzeichen raus
##   redeem()             {ok:true, code} | {ok:false, reason:
##                        "unknown"|"already"|"locked"} — läuft IM
##                        gs.update-Draft; Effekte wendet der AUFRUFER an
##   is_double_coins_active/remaining_ms/lock_remaining_ms  Buff-/Sperr-Uhren
##
## Rate-Limit (§C-SYS5.3): LOCK_AFTER Fehlversuche im rollenden
## LOCK_WINDOW_SEC-Fenster → lockUntil = now + LOCK_SEC. Das Sperr-ENDE
## persistiert (codes.lockUntil); das Fenster selbst ist Session-Sache —
## der Aufrufer hält das attempts-Array (Tests injizieren ihre eigenen).

const LOCK_AFTER := 5
const LOCK_WINDOW_SEC := 60
const LOCK_SEC := 30

## Katalog (Web data/codes.js, verbatim + Godot-Zusätze): secret ist die
## NORMALISIERTE Form. Effekt-Vokabular (wendet der AUFRUFER an, §B6):
##   coins        Münzen über Economy.award(reason "code")
##   buff/minutes doubleCoins-Buff (codes.buffs.doubleCoinsUntil)
##   sticker      Sticker über den RewardHub (Cond-Typ "code")
##   unlock_flag  setzt einen Save-Pfad auf true (z. B. "gvz.goldi" —
##                der Goldi-Turm, Doc G §4.2 "NUR per Einlöse-Code")
const CODES: Array[Dictionary] = [
	{
		"id": "updateLiebe",
		"secret": "updateliebe",
		"effect": {"buff": "doubleCoins", "minutes": 10},
		"once": true,
	},
	{
		"id": "herzGooby",
		"secret": "ichlie3bdich",
		"effect": {"sticker": "herzGooby", "coins": 50},
		"once": true,
	},
	# W13/GVZ: „GOLDIGOLD“ schaltet Goldi frei (Pack-Pendant:
	# content/codes/data/codes.json, Eintrag goldiGold).
	{
		"id": "goldiGold",
		"secret": "goldigold",
		"effect": {"unlock_flag": "gvz.goldi"},
		"once": true,
	},
]


## Web normalize: trim → toLowerCase → \s+ komplett entfernen.
static func normalize(input: Variant) -> String:
	if not (input is String):
		return ""
	var out := ""
	for ch: String in (input as String).strip_edges().to_lower():
		if not (ch == " " or ch == "\t" or ch == "\n" or ch == "\r" or ch == "\v" or ch == "\f"):
			out += ch
	return out


static func code_by_secret(secret: String) -> Dictionary:
	for code: Dictionary in CODES:
		if str(code["secret"]) == secret:
			return code
	return {}


static func code_by_id(id: String) -> Dictionary:
	for code: Dictionary in CODES:
		if str(code["id"]) == id:
			return code
	return {}


## DER Einlöse-Pfad (§B6). Mutiert NUR den übergebenen State-Draft
## (Einlöse-Latch + Sperre) und das attempts-Array — keine Uhr-Reads.
static func redeem(state: Dictionary, input: Variant, now_ms: int, attempts: Array) -> Dictionary:
	var codes := _ensure_codes_slice(state)
	var lock_until := _num(codes.get("lockUntil"))
	if lock_until > float(now_ms):
		return {"ok": false, "reason": "locked"}

	var secret := normalize(input)
	var code := code_by_secret(secret) if not secret.is_empty() else {}
	if code.is_empty():
		# Rollendes Fenster: alte Versuche raus, diesen zählen, ggf. sperren.
		var window_start := float(now_ms) - float(LOCK_WINDOW_SEC) * 1000.0
		while not attempts.is_empty() and _num(attempts[0]) < window_start:
			attempts.pop_front()
		attempts.append(now_ms)
		if attempts.size() >= LOCK_AFTER:
			codes["lockUntil"] = now_ms + LOCK_SEC * 1000
			attempts.clear()
		return {"ok": false, "reason": "unknown"}

	var redeemed: Dictionary = codes["redeemed"]
	if bool(code.get("once", true)) and redeemed.has(str(code["id"])):
		return {"ok": false, "reason": "already"}

	redeemed[str(code["id"])] = now_ms
	return {"ok": true, "code": code.duplicate(true)}


## Läuft der Doppel-Münzen-Buff gerade? (HUD-Chip + Economy-Award-Pfad.)
static func is_double_coins_active(state: Dictionary, now_ms: int) -> bool:
	return remaining_ms(state, now_ms) > 0


## Rest-Millisekunden des Doppel-Münzen-Buffs (0 = inaktiv).
static func remaining_ms(state: Dictionary, now_ms: int) -> int:
	var until := _num(_dig(state, ["codes", "buffs", "doubleCoinsUntil"]))
	return maxi(0, int(until) - now_ms)


## Rest-Millisekunden der Fehlversuch-Sperre (0 = frei).
static func lock_remaining_ms(state: Dictionary, now_ms: int) -> int:
	var until := _num(_dig(state, ["codes", "lockUntil"]))
	return maxi(0, int(until) - now_ms)


## Verlauf: [{id, at_ms}] der eingelösten Codes, jüngste zuerst.
static func redeemed_entries(state: Dictionary) -> Array:
	var redeemed: Variant = _dig(state, ["codes", "redeemed"])
	if not (redeemed is Dictionary):
		return []
	var out: Array = []
	for id: Variant in (redeemed as Dictionary).keys():
		out.append({"id": str(id), "at_ms": int(_num((redeemed as Dictionary)[id]))})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["at_ms"]) > int(b["at_ms"])
	)
	return out


static func _ensure_codes_slice(state: Dictionary) -> Dictionary:
	if not (state.get("codes") is Dictionary):
		state["codes"] = {"redeemed": {}, "lockUntil": 0, "buffs": {"doubleCoinsUntil": 0}}
	var codes: Dictionary = state["codes"]
	if not (codes.get("redeemed") is Dictionary):
		codes["redeemed"] = {}
	if not (codes.get("buffs") is Dictionary):
		codes["buffs"] = {"doubleCoinsUntil": 0}
	return codes


static func _dig(state: Dictionary, path: Array) -> Variant:
	var cur: Variant = state
	for key: String in path:
		if not (cur is Dictionary):
			return null
		cur = (cur as Dictionary).get(key)
	return cur


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
