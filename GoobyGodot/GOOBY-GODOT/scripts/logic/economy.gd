extends RefCounted
## Pure coin math — port of the award/spend core of GOOBY/src/systems/economy.js
## (§C1.5/§C-SYS11: the single money path; V4/G54 day-cap ledgers).
##
## Operates on ONE economy dict (the v5 `economy` slice — see save_schema.gd):
##   {"coins", "coinsEarned", "coinsSpent",
##    "dayCoins", "dayCoinsDay", "endlessCoins", "endlessCoinsDay"}
## Functions mutate the dict in place (Godot dicts are references) and return
## the granted amount / success, exactly like the web store.update() drafts.
## Reason tags mirror the web: 'glueckspilz'/'modifier' book against the
## 150 c/local-day modifier ledger, 'endless' against the 100 c/local-day
## endless ledger; every other reason is uncapped logging metadata.
## Parity proven against golden_values.json economy.steps.

## §C-SYS11.1 row 5: modifier surplus (doppelGold + glueckspilz) per local day.
const DAY_COIN_CAP := 150
## §C-SYS11.1 row 6: coins from `reason: 'endless'` per local day.
const ENDLESS_DAY_CAP := 100
## Quick Delivery (§C4.6): +20% markup, rounded up.
const QUICK_DELIVERY_MARKUP := 0.2
const QUICK_DELIVERY_PRICE := 400
const QUICK_DELIVERY_LEVEL := 8
const STARTING_COINS := 100


## Fresh economy slice (v5 defaults; STARTING_COINS mirrors web §C5.1).
static func default_slice() -> Dictionary:
	return {
		"coins": STARTING_COINS,
		"coinsEarned": 0,
		"coinsSpent": 0,
		"dayCoins": 0,
		"dayCoinsDay": "",
		"endlessCoins": 0,
		"endlessCoinsDay": "",
	}


## Normalize a coin award: integer >= 0 (fractions round AGAINST the player).
static func norm_award(amount: Variant) -> int:
	return maxi(0, int(floor(_num(amount))))


## Normalize a cost: integer >= 0, rounded UP.
static func norm_cost(amount: Variant) -> int:
	return maxi(0, int(ceil(_num(amount))))


## Can the player pay `amount` coins right now?
static func can_afford(econ: Dictionary, amount: Variant) -> bool:
	return int(econ.get("coins", 0)) >= norm_cost(amount)


## Grant coins (floored, never negative). `day` = clock.local_day() of the
## booking (day-cap ledgers roll over lazily on a new day string).
## Returns the coins ACTUALLY granted after the §C-SYS11.1 caps (0 = capped —
## UI renders the "Tagesbonus erreicht" note).
static func award(econ: Dictionary, amount: Variant, reason := "", day := "") -> int:
	var n := norm_award(amount)
	if n == 0:
		return 0
	var granted := n
	if reason == "glueckspilz" or reason == "modifier":
		granted = _book_day_ledger(econ, n, day, "dayCoins", "dayCoinsDay", DAY_COIN_CAP)
	elif reason == "endless":
		granted = _book_day_ledger(econ, n, day, "endlessCoins", "endlessCoinsDay", ENDLESS_DAY_CAP)
	if granted > 0:
		econ["coins"] = int(econ.get("coins", 0)) + granted
		econ["coinsEarned"] = int(econ.get("coinsEarned", 0)) + granted
	return granted


## Spend coins atomically: either the full amount is deducted or nothing
## happens (returns false — never partial, never negative balances).
static func spend(econ: Dictionary, amount: Variant, _reason := "") -> bool:
	var n := norm_cost(amount)
	if not can_afford(econ, n):
		return false
	econ["coins"] = int(econ.get("coins", 0)) - n
	econ["coinsSpent"] = int(econ.get("coinsSpent", 0)) + n
	return true


## Quick-delivery price (§C4.6): +20% markup, rounded UP. Integer-cent math so
## float noise never flips the ceil (5 * 1.2 must be 6, not 7).
static func quick_price(base: Variant) -> int:
	var cents := roundf(maxf(0.0, _num(base)) * 100.0 * (1.0 + QUICK_DELIVERY_MARKUP))
	return int(ceil(cents / 100.0))


## Book `amount` against a per-local-day ledger; returns the granted part
## (0 when capped). Mirrors web bookModifierDayCoins/bookEndlessDayCoins.
static func _book_day_ledger(
	econ: Dictionary, amount: int, day: String, coins_key: String, day_key: String, cap: int
) -> int:
	if econ.get(day_key, "") != day:
		econ[coins_key] = 0
		econ[day_key] = day
	var headroom := maxi(0, cap - int(econ.get(coins_key, 0)))
	var granted := mini(maxi(0, amount), headroom)
	econ[coins_key] = int(econ.get(coins_key, 0)) + granted
	return granted


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
