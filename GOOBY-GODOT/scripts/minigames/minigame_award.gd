class_name MinigameAward
extends RefCounted
## Der EINE Minigame-Payout-Pfad — Port von GOOBY/src/systems/economy.js
## awardMinigame() auf das v5-Schema (W1d): Basis-Coins (§G5.2 inkl. Endlos-
## Pauschale), Tages-×2 beim ersten Spiel des Tages, Endlos-Tages-Cap über
## Economy.award(reason "endless"), +15 Spaß, plays/lastPlayDay, per-Modus-
## Boards (§G5.7-4) + beaten-Ziele, Minigame-XP mit Level-Up-Coins.
## ABWEICHUNGEN (dokumentiert): kein doppelGold/doubleCoinsBuff (Codes-Engine
## ist nicht Teil von M1-W2d) und kein profile.coinsEarned (v5 bucht Earned
## im economy-Slice über Economy.award).
## ERWEITERUNGEN (E10): Timed-Coins laufen gegen ein 150-c-Tages-Ledger
## (minigames.dayCoins — Spiegel des Web-§C-SYS11.1-Werts DAY_COIN_CAP, im
## Web bremst stattdessen das Energie-Gate) und `chunks` erlauben die
## Coin-Row PRO Teil-Score (GvZ: pro gewonnenem Level) statt pro Session.

const Economy := preload("res://scripts/logic/economy.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

## Web MINIGAME.DAILY_FIRST_PLAY_MULT / FUN_REWARD (data/constants.js).
const DAILY_FIRST_PLAY_MULT := 2
const FUN_REWARD := 15.0
## E10-P1-2: Tages-Cap aller Timed-Minigame-Coins (Web-Wert §C-SYS11.1 = 150).
const MINIGAME_DAY_CAP := 150


## Mutiert `state` in place (innerhalb von GameState.update aufrufen!) und
## liefert das Results-Breakdown. `today` = Clock.local_day().
## `chunks`: optionale coin-würdige Teil-Scores (GvZ pro Level) — nicht-leer
## wird die Coin-Row pro Chunk angewandt (Summe der Basen statt Session-Base).
## `modifier` (FERTIG-1, EVAL Rang 12): ModifierEngine.launch_params der
## konsumierten Runde — score_mult wirkt VOR allem (Coins/Best/Ziel sehen den
## geboosteten Score), coin_mult-Überschuss und die Glücksrolle laufen gegen
## das 150-c-Tages-Ledger (Economy.award 'modifier'/'glueckspilz'), xp_mult
## skaliert die Runden-XP. energy_free wirkt im Host (kein Energie-Abzug).
static func award(
	state: Dictionary,
	meta: Dictionary,
	score: int,
	difficulty: String,
	today: String,
	chunks: Array[int] = [],
	modifier: Dictionary = {}
) -> Dictionary:
	var id: String = meta["id"]
	var s := maxi(0, score)
	var score_mult := _num(modifier.get("score_mult"), 1.0)
	if score_mult > 1.0:
		s = maxi(0, int(round(float(s) * score_mult)))
	var mode := MinigameFrameworkLogic.normalize_difficulty(difficulty)
	var mg: Dictionary = state["minigames"]
	var legacy: Dictionary = mg["legacy"]
	var first_today: bool = _dict(legacy.get("lastPlayDay")).get(id) != today

	var base := 0
	if mode == "endless":
		base = MinigameFrameworkLogic.ENDLESS_FLAT_COINS
	elif chunks.size() > 0:
		for chunk in chunks:
			base += MinigameFrameworkLogic.apply_difficulty_coin_base(
				meta["coin_table"], chunk, mode
			)
	else:
		base = MinigameFrameworkLogic.apply_difficulty_coin_base(meta["coin_table"], s, mode)
	var daily_mult := DAILY_FIRST_PLAY_MULT if first_today else 1
	var paid := base * daily_mult
	var day_cap_reached := false
	var econ: Dictionary = state["economy"]
	if mode == "endless":
		# §C-SYS11.1 Zeile 6: JEDER Endlos-Coin zählt gegen das 100-c-Tageslimit.
		var granted := Economy.award(econ, paid, "endless", today)
		if granted < paid:
			day_cap_reached = true
		paid = granted
	else:
		var timed_granted := _book_minigame_day_coins(mg, paid, today)
		if timed_granted < paid:
			day_cap_reached = true
		paid = timed_granted
		Economy.award(econ, paid, "minigame", today)

	# FERTIG-1: doppelGold/muenzregen — nur der ÜBERSCHUSS über die normale
	# Auszahlung läuft gegen das 150-c-Modifier-Tages-Ledger (Anti-Farm).
	var mod_bonus := 0
	var mod_capped := false
	var coin_mult := _num(modifier.get("coin_mult"), 1.0)
	if coin_mult > 1.0 and paid > 0:
		var want := int(round(float(paid) * (coin_mult - 1.0)))
		mod_bonus = Economy.award(econ, want, "modifier", today)
		mod_capped = mod_bonus < want
	# FERTIG-1: Glückspilz — seeded 10–60-c-Rolle, gleiches Tages-Ledger.
	var glueck := 0
	if modifier.get("gluecksrolle", false):
		var roll := ModifierEngine.roll_glueckspilz(state)
		glueck = Economy.award(econ, roll, "glueckspilz", today)
		if glueck < roll:
			mod_capped = true

	var stats: Dictionary = state["gooby"]["stats"]
	stats["fun"] = clampf(float(stats.get("fun", 0.0)) + FUN_REWARD, 0.0, 100.0)
	mg["plays"][id] = int(_num(_dict(mg.get("plays")).get(id))) + 1
	legacy["lastPlayDay"][id] = today
	# FERTIG-1: Sticker "modifierMischief" zählt Runden MIT aktivem
	# Modifikator über achievements.counters.modifierPlays (Web-Counter).
	if not modifier.is_empty() and state.get("achievements") is Dictionary:
		var ach: Dictionary = state["achievements"]
		if not (ach.get("counters") is Dictionary):
			ach["counters"] = {}
		ach["counters"]["modifierPlays"] = (
			int(_num(_dict(ach["counters"]).get("modifierPlays"))) + 1
		)

	# §G5.7-4: per-Modus-Boards — best (Mittel) / bestByDiff / endlessBest.
	var prev := _prev_best(legacy, id, mode)
	var new_best := s > prev
	if mode == "normal":
		if new_best:
			legacy["best"][id] = s
	elif mode == "endless":
		if new_best:
			legacy["endlessBest"][id] = s
	elif new_best:
		var by_diff: Dictionary = legacy["bestByDiff"]
		if not (by_diff.get(id) is Dictionary):
			by_diff[id] = {}
		by_diff[id][mode] = s
	var target := int(_num(meta.get("target"), -1.0))
	var beat_target := mode != "endless" and target >= 0 and s >= target
	if beat_target:
		var beaten: Dictionary = legacy["beaten"]
		if not (beaten.get(id) is Dictionary):
			beaten[id] = {}
		beaten[id][mode] = true

	var prog: Dictionary = state["progression"]
	var xp_gain := Leveling.minigame_xp(paid)
	# FERTIG-1: Lernrausch — Runden-XP ×2 (nur die XP, nie die Coins).
	var xp_mult := _num(modifier.get("xp_mult"), 1.0)
	if xp_mult > 1.0:
		xp_gain = int(round(float(xp_gain) * xp_mult))
	var res := Leveling.apply_xp(
		{"xp": _num(prog.get("xp")), "level": int(_num(prog.get("level"), 1.0))}, float(xp_gain)
	)
	prog["xp"] = res["xp"]
	prog["level"] = res["level"]
	if int(res["coinsAwarded"]) > 0:
		Economy.award(econ, res["coinsAwarded"], "levelUp", today)

	return {
		"gameId": id,
		"score": s,
		"coins": paid,
		"firstToday": first_today,
		"best": maxi(prev, s),
		"newBest": new_best,
		"xp": xp_gain,
		"levelsGained": res["levelsGained"],
		"coinsFromLevels": res["coinsAwarded"],
		# EF-1/EVAL-1 D8: neues Level für die Level-Up-Feier im Results.
		"level": int(res["level"]),
		"difficulty": mode,
		"dayCapReached": day_cap_reached,
		"beatTarget": beat_target,
		# FERTIG-1 (EVAL Rang 12): Modifier-Wirkung für den Results-Screen.
		"modifier": modifier.duplicate(true),
		"modifierBonusCoins": mod_bonus,
		"gluecksrolleCoins": glueck,
		"modifierCapped": mod_capped,
	}


## Timed-Coins gegen das 150-c/Lokaltag-Ledger buchen (additive Keys im
## minigames-Slice — merge_defaults lässt sie überleben). Liefert den
## tatsächlich zahlbaren Teil (Muster Economy._book_day_ledger).
static func _book_minigame_day_coins(mg: Dictionary, amount: int, day: String) -> int:
	if str(mg.get("dayCoinsDay", "")) != day:
		mg["dayCoins"] = 0
		mg["dayCoinsDay"] = day
	var used := int(_num(mg.get("dayCoins")))
	var headroom := maxi(0, MINIGAME_DAY_CAP - used)
	var granted := mini(maxi(0, amount), headroom)
	mg["dayCoins"] = used + granted
	return granted


static func _prev_best(legacy: Dictionary, id: String, mode: String) -> int:
	if mode == "endless":
		return int(_num(_dict(legacy.get("endlessBest")).get(id)))
	if mode == "easy" or mode == "hard":
		return int(_num(_dict(_dict(legacy.get("bestByDiff")).get(id)).get(mode)))
	return int(_num(_dict(legacy.get("best")).get(id)))


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
