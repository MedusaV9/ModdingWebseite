class_name RocketRescueLogic
extends RefCounted
## Pure Raketen-Rettung-Zahlen — zahlengleicher Port von
## GOOBY/src/minigames/games/rocketRescue.logic.js (PLAN3 §C10.1 #3).
## Lander-Physik mit Schub + Neigung, 5 gesetzte Plattformen mit je einem
## gestrandeten Hasen, Tank 100 / Schub 8 pro Sekunde, angekündigte Windböen
## ab dem 3. Rettungsbein, harte Landung = Abpraller −10 Sprit (NIE Tod),
## Score = 30·gerettet + Sprit/2 + 5 je Sanftlandung.
##
## Die Zustandsmaschine liegt in `rocket_rescue_engine.gd`, der PD-Bot in
## `rocket_rescue_bot.gd` — diese Datei hält nur Konstanten + reine Formeln.

## Bindende §C10.1-#3-Zahlen; Coin-Zeile 5/4/28, Ziel 115.
const ROCKET := {
	"DURATION_SEC": 120.0,
	"WORLD_HALF_W": 8.0,
	"CEILING_Y": 11.0,
	"GRAVITY": 2.4,
	"THRUST_ACCEL": 5.6,
	"TILT_MAX_RAD": 0.5,
	"TILT_RATE": 3.2,
	"WALL_RESTITUTION": 0.3,
	"FUEL_MAX": 100.0,
	"FUEL_BURN_PER_SEC": 8.0,
	"FUEL_PICKUP_COUNT": 8,
	"FUEL_PICKUP_AMOUNT": 30.0,
	"FUEL_PICKUP_RADIUS": 0.85,
	"FUEL_RESPAWN_SEC": 9.0,
	"PLATFORM_COUNT": 5,
	"PLATFORM_HALF_W": 1.05,
	"PAD_X": 0.0,
	"PAD_Y": 0.0,
	"PAD_HALF_W": 1.6,
	"LAND_MAX_VY": 1.2,
	"SOFT_MAX_VY": 0.5,
	"RESCUE_POINTS": 30,
	"SOFT_LANDING_BONUS": 5,
	"FUEL_SCORE_DIVISOR": 2.0,
	"DEPART_CLEAR_M": 0.4,
	"HARD_FUEL_PENALTY": 10.0,
	"BOUNCE_RESTITUTION": 0.45,
	"WIND_FROM_RESCUES": 2,
	"WIND_TELEGRAPH_SEC": 1.0,
	"WIND_GUST_SEC": 1.6,
	"WIND_ACCEL": 1.7,
	"WIND_EVERY_MIN_SEC": 6.0,
	"WIND_EVERY_MAX_SEC": 10.0,
	"TOW_SPEED": 3.4,
	"MAX_DT": 1.0 / 20.0,
	"BOT_CRUISE_CLEARANCE_M": 1.2,
	"BOT_ALIGN_X_M": 0.45,
	"BOT_ALIGN_VX": 0.8,
	"BOT_MAX_VX": 2.7,
	"BOT_VX_GAIN": 1.6,
	"BOT_LAT_ACCEL_EFF": 1.0,
	"BOT_DESCEND_VX": 0.7,
	"BOT_TILT_DEADBAND": 0.22,
	"BOT_VY_GAIN": 0.85,
	"BOT_MAX_RISE": 2.6,
	"BOT_MAX_DESCEND": 1.1,
	"BOT_SOFT_DESCEND": 0.42,
	"BOT_FLARE_BELOW_M": 1.2,
	"BOT_REFUEL_ENTER": 45.0,
	"BOT_REFUEL_EXIT": 75.0,
	"BOT_REFUEL_RANGE_M": 12.0,
	"BOT_REFUEL_SKIP_BELOW_M": 2.5,
	"ENDLESS": false,
	"ENDLESS_THIN_PER_RESCUE": 0.1,
	"PICKUP_RATE": 1.0,
}

## V4/GAME-POLISH-4-Juice (nur Optik, nie Flugmathematik).
const ROCKET_JUICE := {
	"TOUCH_SQUASH": 0.82,
	"TOUCH_SQUASH_SEC": 0.28,
	"BEACON_POP_SCALE": 2.1,
	"BEACON_POP_SEC": 0.55,
	"RESCUE_HEARTS": 5,
	"SOFT_SPARKLES": 6,
	"COMPLETE_CONFETTI_2ND": 14,
}

## §G5.3-Toleranzzeilen: Leicht ×1.25, Schwer/Endlos ×0.8.
const ROCKET_DIFFICULTY := {
	"easy": {"tol": 1.25, "endless": false},
	"normal": {"tol": 1.0, "endless": false},
	"hard": {"tol": 0.8, "endless": false},
	"endless": {"tol": 0.8, "endless": true},
}

## Höhenbänder der Plattformleiter (werden je Runde gemischt).
const BANDS: Array[float] = [2.4, 3.9, 5.4, 6.9, 8.3]


## §G5.3-Modus ableiten; `normal` liefert die Basistabelle unverändert
## (identische rng-Ströme: PLATFORM_HALF_W fließt NIE in die Ablehnungsprobe).
static func apply_difficulty(tune := ROCKET, mode := "normal") -> Dictionary:
	var id := mode if ROCKET_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = ROCKET_DIFFICULTY[id]
	var out := tune.duplicate(true)
	out["LAND_MAX_VY"] = float(tune["LAND_MAX_VY"]) * float(row["tol"])
	out["SOFT_MAX_VY"] = float(tune["SOFT_MAX_VY"]) * float(row["tol"])
	out["PLATFORM_HALF_W"] = float(tune["PLATFORM_HALF_W"]) * float(row["tol"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## §C-SYS4.3: nur „Münzregen“ greift — mehr Spritkanister, die schneller
## zurückschweben (die Kanister SIND die Münzen dieses Spiels).
static func apply_modifier(tune: Dictionary, modifier: Dictionary) -> Dictionary:
	if modifier.is_empty() or str(modifier.get("type", "")) != "muenzregen":
		return tune
	var raw := float(modifier.get("coinRate", 1.0))
	var rate := maxf(0.1, raw if is_finite(raw) and raw != 0.0 else 1.0)
	var out := tune.duplicate(true)
	out["FUEL_PICKUP_COUNT"] = int(round(float(tune["FUEL_PICKUP_COUNT"]) * rate))
	out["FUEL_RESPAWN_SEC"] = float(tune["FUEL_RESPAWN_SEC"]) / rate
	out["PICKUP_RATE"] = rate
	return out


## Flächen-Ids sind `"pad"`, ein Plattform-Index oder `null` — GDScript wirft
## bei `int != String` einen Fehler, JS' `===` vergleicht einfach den Typ mit.
static func same_id(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


## V8-genaues `Math.hypot` (Kahan-Summe auf den größten Betrag normiert).
## Ein einfaches sqrt(x²+y²) weicht bei ~36 % der Eingaben im letzten Bit ab
## und würde die 7200-Frame-Bot-Simulation aus dem Tritt bringen.
static func hypot(x: float, y: float) -> float:
	if is_inf(x) or is_inf(y):
		return INF
	var ax := absf(x)
	var ay := absf(y)
	var scale := maxf(ax, ay)
	if scale == 0.0:
		scale = 1.0
	var total := 0.0
	var comp := 0.0
	for value: float in [ax / scale, ay / scale]:
		var summand := value * value - comp
		var prelim := total + summand
		comp = (prelim - total) - summand
		total = prelim
	return sqrt(total) * scale


## Gesetztes Rundenlayout: 5 Plattformen mit Mindestabstand + Spritkanister.
static func create_layout(rng: Callable, tune := ROCKET) -> Dictionary:
	var pad := {
		"x": float(tune["PAD_X"]), "y": float(tune["PAD_Y"]), "halfW": float(tune["PAD_HALF_W"])
	}
	var bands: Array[float] = BANDS.duplicate()
	# Fisher–Yates über die Höhenbänder — jede Runde mischt die Leiter neu.
	for i in range(bands.size() - 1, 0, -1):
		var j := int(floor(float(rng.call()) * (i + 1)))
		var tmp: float = bands[i]
		bands[i] = bands[j]
		bands[j] = tmp
	var platforms: Array[Dictionary] = []
	for i in int(tune["PLATFORM_COUNT"]):
		var y: float = bands[i % bands.size()] + (float(rng.call()) - 0.5) * 0.6
		var x := 0.0
		var ok := false
		var attempt := 0
		while attempt < 24 and not ok:
			x = (float(rng.call()) * 2.0 - 1.0) * (float(tune["WORLD_HALF_W"]) - 1.4)
			ok = (
				(absf(x) >= float(pad["halfW"]) + 1.0 or y >= 4.5)
				and _clear_of_platforms(platforms, x, y)
			)
			attempt += 1
		if not ok:
			x = (1.0 if i % 2 == 0 else -1.0) * (2.4 + i * 1.1)
		platforms.append({"x": x, "y": y, "halfW": float(tune["PLATFORM_HALF_W"]), "bunny": true})
	var fuel_pickups: Array[Dictionary] = []
	for i in int(tune["FUEL_PICKUP_COUNT"]):
		var x := 0.0
		var y := 0.0
		var ok := false
		var attempt := 0
		while attempt < 24 and not ok:
			x = (float(rng.call()) * 2.0 - 1.0) * (float(tune["WORLD_HALF_W"]) - 1.1)
			y = 1.6 + float(rng.call()) * (float(tune["CEILING_Y"]) - 2.6)
			ok = _clear_of_pickup_spots(platforms, x, y)
			attempt += 1
		fuel_pickups.append({"x": x, "y": y, "taken": false, "respawnT": 0.0})
	return {"platforms": platforms, "fuelPickups": fuel_pickups, "pad": pad}


static func _clear_of_platforms(platforms: Array[Dictionary], x: float, y: float) -> bool:
	for p in platforms:
		if absf(float(p["x"]) - x) < 2.3 and absf(float(p["y"]) - y) < 1.5:
			return false
	return true


static func _clear_of_pickup_spots(platforms: Array[Dictionary], x: float, y: float) -> bool:
	for p in platforms:
		if absf(float(p["x"]) - x) <= 1.4 and absf(float(p["y"]) - y) <= 1.2:
			return false
	return true


## §C10.1-Landeklassen: ≤ 0.5 m/s sanft, ≤ 1.2 m/s ok, darüber hart.
static func classify_landing(vy_abs: float, tune := ROCKET) -> String:
	if vy_abs <= float(tune["SOFT_MAX_VY"]):
		return "soft"
	if vy_abs <= float(tune["LAND_MAX_VY"]):
		return "ok"
	return "hard"


## Rundenpunkte: 30·gerettet + Restsprit/2 + 5 je Sanftlandung.
static func round_score(
	rescued: int, fuel_remaining: float, soft_landings: int, tune := ROCKET
) -> int:
	return maxi(
		0,
		int(
			floor(
				(
					float(tune["RESCUE_POINTS"]) * rescued
					+ maxf(0.0, fuel_remaining) / float(tune["FUEL_SCORE_DIVISOR"])
					+ float(tune["SOFT_LANDING_BONUS"]) * soft_landings
				)
			)
		)
	)


## Bildschirmdrittel → Neigungsbefehl (links −1, Mitte 0, rechts +1).
## `has_touch=false` steht für das JS-`null` (Finger nicht auf dem Glas).
static func tilt_command_for(nx: float, has_touch := true) -> int:
	if not has_touch:
		return 0
	if nx < -1.0 / 3.0:
		return -1
	if nx > 1.0 / 3.0:
		return 1
	return 0
