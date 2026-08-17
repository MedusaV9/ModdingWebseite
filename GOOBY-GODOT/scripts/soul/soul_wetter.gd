class_name SoulWetter
extends RefCounted
## Zuhause-Wetter (FB-6/SEELE) — deterministischer Adapter auf den
## Ranch-Wetterplan (ranch_wetter.gd, Datum+Seed → Tagesplan). Eigener Seed,
## damit das Zuhause-Wetter unabhängig von der Ranch würfelt, aber pro Tag
## stabil bleibt (gleicher Tag == gleiches Wetter, headless testbar).
##
## Winter-Veredelung: In Dez/Jan/Feb wird Niederschlag zu SCHNEE — die Basis
## kennt nur Regen-Typen. So gibt es einen echten „ersten Schnee“-Moment.

const RanchWetter := preload("res://scripts/ranch/wetter/ranch_wetter.gd")

const HOME_SEED := 47_110_815
const WINTER_MONATE: Array[int] = [12, 1, 2]


## Zustand fürs Zuhause: {typ, regen: bool, schnee: bool}. `datum` ist
## "YYYY-MM-DD", `stunde` 0..24 (float) — beides wird hereingereicht.
static func zustand(datum: String, stunde: float) -> Dictionary:
	var basis := RanchWetter.zustand(datum, stunde, HOME_SEED)
	var typ := str(basis.get("typ", "sonne"))
	var ist_regen := RanchWetter.REGEN_TYPEN.has(typ)
	var ist_schnee := ist_regen and ist_winter(datum)
	if ist_schnee:
		typ = "schnee"
		ist_regen = false
	return {"typ": typ, "regen": ist_regen, "schnee": ist_schnee}


static func ist_winter(datum: String) -> bool:
	return WINTER_MONATE.has(monat_von(datum))


## Monat aus "YYYY-MM-DD" (0 bei kaputtem Format — nie crashen).
static func monat_von(datum: String) -> int:
	var parts := datum.split("-")
	if parts.size() != 3 or not parts[1].is_valid_int():
		return 0
	return int(parts[1])
