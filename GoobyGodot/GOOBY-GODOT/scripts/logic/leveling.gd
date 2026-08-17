extends RefCounted
## Pure leveling logic — 1:1 port of GOOBY/src/systems/leveling.js (§C1.5).
##
## Numbers from GOOBY/src/data/constants.js (XP + LEVELING blocks); parity is
## proven against tests/fixtures/golden_values.json.
##
## M2 REWORK HOOK (GODOT-PLAN: Level-System-Rework fuer Multiplayer ist ein
## M2-Milepost): die Kurve ist hier bewusst als EIN Paar Konstanten + EINE
## Funktion (xp_to_next) isoliert. Der Rework tauscht nur diese Datei aus;
## Migration v4→v5 setzt XP deshalb schon heute auf 0 (Level bleibt 1:1 —
## niemand verliert ein Level, siehe migration_v4.gd / Doc H §5.2).

const MAX_LEVEL := 40
const XP_BASE := 100
const XP_STEP := 50
## Level-up reward = 25 * newLevel coins (§C1.5).
const LEVEL_UP_COINS_PER_LEVEL := 25
## Minigame finish XP = 10 + min(15, floor(coinsEarned / 2)) (§C1.5).
const MINIGAME_BASE := 10
const MINIGAME_BONUS_CAP := 15
const MINIGAME_COIN_DIVISOR := 2
## XP grants used by the state layer (subset relevant to W1d core paths).
const XP_COMPLETED_SLEEP := 10


## XP required to advance from level L to L+1: 100 + 50*(L-1).
static func xp_to_next(level: int) -> int:
	return XP_BASE + XP_STEP * (level - 1)


## Cumulative XP needed to reach a level from level 1 (to L10 = 2700).
static func cumulative_xp_to_level(level: int) -> int:
	var sum := 0
	for l in range(1, level):
		sum += xp_to_next(l)
	return sum


## Apply an XP grant, handling multi-level-ups and the max-level cap.
## progress: {"xp": float, "level": int}. Pure — returns
## {"xp", "level", "levelsGained", "coinsAwarded"}.
## (The web's runtime-only `xpGranted` store emit is a game_state concern —
## the state layer emits after calling this, keeping the math pure.)
static func apply_xp(progress: Dictionary, amount: float) -> Dictionary:
	var level := int(clampi(_int_or(progress.get("level"), 1), 1, MAX_LEVEL))
	var xp := maxf(0.0, _num_or(progress.get("xp"), 0.0))
	var levels_gained := 0
	var coins_awarded := 0
	if level >= MAX_LEVEL:
		# At max level XP is no longer accumulated.
		return {"xp": 0, "level": level, "levelsGained": 0, "coinsAwarded": 0}
	xp += maxf(0.0, amount)
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		levels_gained += 1
		coins_awarded += LEVEL_UP_COINS_PER_LEVEL * level
	if level >= MAX_LEVEL:
		xp = 0.0
	return {
		"xp": xp,
		"level": level,
		"levelsGained": levels_gained,
		"coinsAwarded": coins_awarded,
	}


## XP for finishing a minigame (§C1.5): 10 + min(15, floor(coinsEarned / 2)).
static func minigame_xp(coins_earned: float) -> int:
	var bonus := int(floor(maxf(0.0, coins_earned) / MINIGAME_COIN_DIVISOR))
	return MINIGAME_BASE + mini(MINIGAME_BONUS_CAP, bonus)


## G4/P21 (QW #24): eine gespeicherte 0 ist ein GÜLTIGER Wert, kein „fehlt“ —
## der alte `n != 0`-Fallback war eine versteckte Falle für Felder, bei denen
## 0 legitim ist (XP, Zähler). Den Level-Fall (min 1) deckt der Clamp am
## Aufrufer (apply_xp) ab.
static func _int_or(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return int(floor(float(value)))
		_:
			return fallback


static func _num_or(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
