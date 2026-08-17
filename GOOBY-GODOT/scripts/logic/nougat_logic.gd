class_name NougatLogic
extends RefCounted
## Nougatschleuse — PURE Logik (W13/FOOD, P1 Punkt 17; Web-Vorlage
## GOOBY/src/systems/nougat.logic.js §B7/§C6.4).
##
## Der Wand-Schokospender in der Küche: Tap → Refusal-Matrix (schlafend /
## krank / Cooldown, in dieser Reihenfolge) → Kurbel+Klecks-Sequenz (Wiring:
## scripts/home/interactables/nougatschleuse.gd) → Wirkung über die
## BESTEHENDEN Pipes (Stats.apply_deltas, Health.on_eat Junk ×2,
## Weight.on_eat ×1, Leveling.apply_xp) auf dem v5-Save.
##
## GODOT-ABWEICHUNG vom Web (bewusst, W13-Auftrag „Nutella-Ausgabe"): die
## Schleuse VERBRAUCHT kein Glas, sie SPENDET zusätzlich zum Klecks ein
## `nutella`-Glas in inventory.food (Belohnung, vom Cooldown gedeckelt).
## Die Web-Refusal `noJar` entfällt deshalb; alle übrigen Zahlen sind
## verbatim §C6.4. Zeit wird IMMER injiziert (now_ms) — kein Time.*-Zugriff.

const Stats := preload("res://scripts/logic/stats.gd")
const HealthLogic := preload("res://scripts/logic/health.gd")
const WeightLogic := preload("res://scripts/logic/weight.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")
const Economy := preload("res://scripts/logic/economy.gd")

## §C6.4: 30 ECHTE Minuten Pause zwischen zwei Kleckesen (easterEggs.nougat.lastGlobAt).
const COOLDOWN_MIN := 30
## Stat-Deltas pro Klecks (durch Stats.apply_deltas, web-keyed).
const STAT_DELTAS := {"hunger": 15, "fun": 10, "hygiene": -8}
## junkScore +2 — DOPPELTER Junk (purer Nougat): Health.on_eat(junk) ×2.
const JUNK_EATS := 2
## Gewicht +2 — Weight.on_eat(junk) ×1 (WEIGHT.EAT_JUNK = 2, NICHT doppelt).
const WEIGHT_EATS := 1
## XP pro Klecks.
const XP := 2
## Das ausgegebene (Web: verbrauchte) Glas — Katalog-Id aus food_catalog.gd.
const JAR_FOOD_ID := "nutella"
## Kurbel+Klecks-Sequenzlänge (Anim-Budget der Wiring-Schicht, §C6.4 ≈ 2,8 s).
const SEQUENCE_SEC := 2.8
## Schoko-Bäckchen halten 60 s (oder bis zur Wäsche) — Doku für die Wiring.
const MESSY_FACE_SEC := 60
## Shop-Karte (§C6.3): Möbel-Katalog `nougatschleuse`, 400 Münzen, Web-Gate L5.
const PRICE := 400
const UNLOCK_LEVEL := 5
const FURNITURE_ID := "nougatschleuse"


## easterEggs.nougat-Slice mit Defaults — legt fehlende Ebenen an (Referenz!).
static func slice(state: Dictionary) -> Dictionary:
	if not (state.get("easterEggs") is Dictionary):
		state["easterEggs"] = {}
	var eggs: Dictionary = state["easterEggs"]
	if not (eggs.get("nougat") is Dictionary):
		eggs["nougat"] = {"lastGlobAt": 0, "installed": false}
	return eggs["nougat"]


static func is_installed(state: Dictionary) -> bool:
	return bool(slice(state).get("installed", false))


## Beim Andocken/Platzieren: installed setzen. true = frisch installiert
## (die Wiring-Schicht feiert dann einmalig mit `nougat.installiert`).
static func mark_installed(state: Dictionary) -> bool:
	var nougat := slice(state)
	if bool(nougat.get("installed", false)):
		return false
	nougat["installed"] = true
	return true


## Rest-Cooldown ab dem persistierten Stempel (0 = bereit). Defensiv-Clamp
## wie Web V3/FIX-A: ein lastGlobAt weiter in der Zukunft als EIN voller
## Cooldown kann kein legitimer Uhren-Versatz sein → wie „gerade gekleckst"
## behandeln, damit die Maschine nie für ~285k Jahre zusperrt.
static func cooldown_remaining_ms(state: Dictionary, now_ms: int) -> int:
	var last := int(_num(slice(state).get("lastGlobAt")))
	if last <= 0:
		return 0
	var cooldown_ms := COOLDOWN_MIN * 60000
	if last > now_ms + cooldown_ms:
		last = now_ms
	return maxi(0, last + cooldown_ms - now_ms)


## §C6.4-Refusal-Matrix (Web-Reihenfolge, ohne noJar — s. Kopfkommentar):
## nicht schlafend, nicht krank, Cooldown abgelaufen.
## Rückgabe {ok: true} oder {ok: false, reason: "sleeping"|"sick"|"cooldown"}.
static func can_glob(state: Dictionary, now_ms: int) -> Dictionary:
	var gooby: Dictionary = state.get("gooby", {}) if state.get("gooby") is Dictionary else {}
	var sleep: Variant = gooby.get("sleep")
	if sleep is Dictionary and (sleep as Dictionary).get("sleeping", false) == true:
		return {"ok": false, "reason": "sleeping"}
	var health: Variant = gooby.get("health")
	if health is Dictionary and str((health as Dictionary).get("state", "")) == "sick":
		return {"ok": false, "reason": "sick"}
	if cooldown_remaining_ms(state, now_ms) > 0:
		return {"ok": false, "reason": "cooldown"}
	return {"ok": true}


## EIN Klecks, komplette Wirkung (§C6.4-Zahlen) — mutiert `state` in place
## (Muster FoodCatalog.apply_feed; Aufrufer sitzt in gs.update und ruft
## danach RewardHub.note_action für die Sticker-Auswertung nougatGlobs).
## Fail-closed: Refusals werden hier NOCHMAL geprüft; {} = nichts passiert.
## Ergebnis: {deltas, hunger_gain, jar_id, jars, globs, xp, level,
## levels_gained, coins_awarded}.
static func apply_glob(state: Dictionary, now_ms: int) -> Dictionary:
	var verdict := can_glob(state, now_ms)
	if not bool(verdict.get("ok", false)):
		return {}
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return {}
	var before: Dictionary = gooby.get("stats", {}) if gooby.get("stats") is Dictionary else {}
	var deltas := {
		"hunger": float(STAT_DELTAS["hunger"]),
		"fun": float(STAT_DELTAS["fun"]),
		"hygiene": float(STAT_DELTAS["hygiene"]),
	}
	var after := Stats.apply_deltas(before, deltas)
	gooby["stats"] = after
	# Doppelter Junk (§C6.4): zwei Junk-„Bisse" durch die Health-Pipe →
	# junkScore +2, Warn-/Erholungs-Semantik wie zwei Junk-Mahlzeiten.
	var health: Variant = gooby.get("health")
	for i in JUNK_EATS:
		health = HealthLogic.on_eat(health, true)
	gooby["health"] = health
	# Gewicht +2 = EIN Junk-Mahl (WEIGHT.EAT_JUNK) — bewusst nicht doppelt.
	var weight: Variant = gooby.get("weight", WeightLogic.DEFAULT)
	for i in WEIGHT_EATS:
		weight = WeightLogic.on_eat(weight, true)
	gooby["weight"] = weight
	# XP +2 über die Leveling-Pipe; Level-Up-Münzen über den EINEN Geldpfad.
	var prog := _dict_at(state, "progression")
	var res := Leveling.apply_xp(
		{"xp": _num(prog.get("xp")), "level": int(_num_or(prog.get("level"), 1.0))}, float(XP)
	)
	prog["xp"] = res["xp"]
	prog["level"] = res["level"]
	if int(res["coinsAwarded"]) > 0:
		Economy.award(_dict_at(state, "economy"), res["coinsAwarded"], "levelUp")
	# Die Ausgabe: ein Nutella-Glas kullert in den Vorrat (W13-Gag).
	var inventory := _dict_at(state, "inventory")
	if not (inventory.get("food") is Dictionary):
		inventory["food"] = {}
	var food: Dictionary = inventory["food"]
	food[JAR_FOOD_ID] = int(_num(food.get(JAR_FOOD_ID))) + 1
	# Cooldown starten + Sticker-Zähler bumpen (nutellaGlob/nougatFlood/
	# kueche_nutellabrot hängen alle am Counter nougatGlobs).
	var nougat := slice(state)
	nougat["lastGlobAt"] = now_ms
	nougat["installed"] = true
	var counters := _counters(state)
	counters["nougatGlobs"] = int(_num(counters.get("nougatGlobs"))) + 1
	return {
		"deltas": deltas,
		"hunger_gain": float(after.get("hunger", 0.0)) - float(_num(before.get("hunger"))),
		"jar_id": JAR_FOOD_ID,
		"jars": int(food[JAR_FOOD_ID]),
		"globs": int(counters["nougatGlobs"]),
		"xp": XP,
		"level": int(res["level"]),
		"levels_gained": int(res["levelsGained"]),
		"coins_awarded": int(res["coinsAwarded"]),
	}


static func _dict_at(state: Dictionary, key: String) -> Dictionary:
	if not (state.get(key) is Dictionary):
		state[key] = {}
	return state[key]


static func _counters(state: Dictionary) -> Dictionary:
	var achievements := _dict_at(state, "achievements")
	if not (achievements.get("counters") is Dictionary):
		achievements["counters"] = {}
	return achievements["counters"]


static func _num(value: Variant) -> float:
	return float(value) if (value is int or value is float) else 0.0


static func _num_or(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback
