class_name PancakeTowerLogic
extends RefCounted
## Pure Pfannkuchenturm-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/pancakeTower.logic.js (§C6.1 #8 / §C10.2).
## Ein Pfannkuchen pendelt über dem Stapel, Tippen lässt ihn fallen; der
## Überhang wird abgeschnitten, jede 5. Lage ist ein Topping (+4, kein
## Schrumpfen), ein perfekter Wurf gibt +2 und stellt 10 % Breite zurück.
## Ende bei Breite < 20 % oder 40 Lagen. Ab Lage 8 schwankt der Turm.

## Bindende §C6.1-#8-Zahlen; Coin-Zeile 2/4/26, Ziel 45.
const PANCAKE := {
	"BASE_WIDTH": 1.5,
	"LAYER_HEIGHT": 0.16,
	"PERFECT_EPS": 0.045,
	"PERFECT_POINTS": 2,
	"PERFECT_RESTORE_PCT": 0.1,
	"TOPPING_EVERY": 5,
	"TOPPING_POINTS": 4,
	"POINTS_PER_LAYER": 2,
	"END_WIDTH_FRAC": 0.2,
	"MAX_LAYERS": 40.0,
	"SLIDE_AMPLITUDE": 1.05,
	"SLIDE_PERIOD_START": 2.6,
	"SLIDE_PERIOD_STEP": 0.055,
	"SLIDE_PERIOD_MIN": 1.15,
	"FALL_SPEED": 7.0,
	"WOBBLE_START_LAYER": 8,
	"WOBBLE_FORCE": 0.7,
	"WOBBLE_SPRING": 10.0,
	"WOBBLE_DAMPING": 3.2,
	"WOBBLE_MAX_RAD": 0.16,
	"PERFECT_WOBBLE_DAMP": 0.4,
	"FALLEN_DESPAWN_SEC": 1.4,
	"TOLERANCE_MULT": 1.0,
	"OVERHANG_TOLERANCE_MULT": 1.0,
	"ENDLESS": false,
}

## §G5.3 Physik/Skill-Zeilen (Toleranz-Multiplikator, Boden 0.55).
const PANCAKE_DIFFICULTY := {
	"easy": {"tolerance": 1.25, "endless": false},
	"normal": {"tolerance": 1.0, "endless": false},
	"hard": {"tolerance": 0.8, "endless": false},
	"endless": {"tolerance": 0.8, "endless": true},
}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle.
static func apply_difficulty(tune: Dictionary = PANCAKE, mode := "normal") -> Dictionary:
	var id := mode if PANCAKE_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = PANCAKE_DIFFICULTY[id]
	var tolerance := maxf(0.55, float(row["tolerance"]))
	var out := tune.duplicate()
	out["PERFECT_EPS"] = float(tune["PERFECT_EPS"]) * tolerance
	out["TOLERANCE_MULT"] = tolerance
	out["OVERHANG_TOLERANCE_MULT"] = tolerance
	out["MAX_LAYERS"] = INF if bool(row["endless"]) else float(tune["MAX_LAYERS"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## Jede 5. Lage ist eine Topping-Lage (5, 10, 15 …).
static func is_topping_layer(index: int, tune := PANCAKE) -> bool:
	return index > 0 and index % int(tune["TOPPING_EVERY"]) == 0


## Pendelperiode einer Lage (kleiner = schneller = schwerer).
static func slide_period(layer_index: int, tune := PANCAKE) -> float:
	return maxf(
		float(tune["SLIDE_PERIOD_MIN"]),
		float(tune["SLIDE_PERIOD_START"]) - (layer_index - 1) * float(tune["SLIDE_PERIOD_STEP"])
	)


## Pendelposition zur Zeit t (Phase 0..1 gibt Variation pro Lage).
static func slide_x(t: float, layer_index: int, phase := 0.0, tune := PANCAKE) -> float:
	var period := slide_period(layer_index, tune)
	return float(tune["SLIDE_AMPLITUDE"]) * sin((t / period + phase) * PI * 2.0)


## Herzstück: Abwurf gegen den Stapel auswerten (Schnitt-Mathematik §C6.1 #8).
static func resolve_drop(
	stack: Dictionary, drop_center: float, topping: bool, tune := PANCAKE
) -> Dictionary:
	var center := float(stack["center"])
	var width := float(stack["width"])
	var offset := drop_center - center
	var abs_off := absf(offset)

	if abs_off <= float(tune["PERFECT_EPS"]):
		var restored := width
		if not topping:
			restored = minf(
				float(tune["BASE_WIDTH"]),
				width + float(tune["BASE_WIDTH"]) * float(tune["PERFECT_RESTORE_PCT"])
			)
		var pts := int(tune["PERFECT_POINTS"])
		if topping:
			pts += int(tune["TOPPING_POINTS"])
		return {
			"landed": true,
			"perfect": true,
			"center": center,
			"width": restored,
			"cut": {},
			"points": pts,
		}

	var effective_off := abs_off / float(tune["OVERHANG_TOLERANCE_MULT"])
	var overlap := width - effective_off
	if overlap <= 0.0:
		return {
			"landed": false,
			"perfect": false,
			"center": center,
			"width": width,
			"cut": {},
			"points": 0,
		}

	var side := 1.0 if offset > 0.0 else -1.0
	if topping:
		var max_off := maxf(0.0, (width - overlap) / 2.0)
		return {
			"landed": true,
			"perfect": false,
			"center": center + side * minf(abs_off, max_off),
			"width": width,
			"cut": {},
			"points": int(tune["TOPPING_POINTS"]),
		}

	return {
		"landed": true,
		"perfect": false,
		"center": center + offset / 2.0,
		"width": overlap,
		"cut":
		{
			"size": minf(width, effective_off),
			"side": side,
			"center": drop_center + side * (overlap / 2.0),
		},
		"points": 0,
	}


## Endebedingung: Breite < 20 % der Basis oder 40 Lagen (Endlos: unendlich).
static func is_tower_done(width: float, layers: int, tune := PANCAKE) -> bool:
	if width < float(tune["BASE_WIDTH"]) * float(tune["END_WIDTH_FRAC"]):
		return true
	return float(layers) >= float(tune["MAX_LAYERS"])


## Rundenpunkte: Lagen × 2 + Boni.
static func tower_score(layers: int, bonus_points: int, tune := PANCAKE) -> int:
	return maxi(0, layers * int(tune["POINTS_PER_LAYER"]) + bonus_points)


static func initial_wobble_state() -> Dictionary:
	return {"angle": 0.0, "velocity": 0.0, "phase": 0.0}


## Gedämpfte, angetriebene Turmschwingung (aktiv ab Lage 8).
static func step_wobble(state: Dictionary, dt: float, layers: int, tune := PANCAKE) -> Dictionary:
	var h := maxf(0.0, dt)
	var phase := float(state["phase"]) + h
	var start := int(tune["WOBBLE_START_LAYER"])
	var active := layers >= start
	var ramp := minf(1.0, float(layers - start + 1) / 8.0) if active else 0.0
	var drive := sin(phase * 2.3) * float(tune["WOBBLE_FORCE"]) * ramp if active else 0.0
	var accel := (
		drive
		- float(state["angle"]) * float(tune["WOBBLE_SPRING"])
		- float(state["velocity"]) * float(tune["WOBBLE_DAMPING"])
	)
	var velocity := float(state["velocity"]) + accel * h
	var limit := float(tune["WOBBLE_MAX_RAD"])
	var angle := maxf(-limit, minf(limit, float(state["angle"]) + velocity * h))
	return {"angle": angle, "velocity": velocity, "phase": phase}


## Perfekte Abwürfe beruhigen den Turm (Endlos ab Lage 8 aber nicht mehr).
static func damp_wobble(state: Dictionary, tune := PANCAKE, layers := 0) -> Dictionary:
	if bool(tune["ENDLESS"]) and layers >= int(tune["WOBBLE_START_LAYER"]):
		return state.duplicate()
	return {
		"angle": float(state["angle"]) * float(tune["PERFECT_WOBBLE_DAMP"]),
		"velocity": float(state["velocity"]) * float(tune["PERFECT_WOBBLE_DAMP"]),
		"phase": float(state["phase"]),
	}


## Welt-x der schwankenden Stapelspitze (Rotation um die Basis).
static func wobble_top_x(local_center: float, height_above_base: float, angle: float) -> float:
	return local_center * cos(angle) - height_above_base * sin(angle)


## Umkehrung von wobble_top_x für ein Stück, das bei world_x landet.
static func wobble_local_x(world_x: float, height_above_base: float, angle: float) -> float:
	var c := cos(angle)
	return (world_x + height_above_base * sin(angle)) / (1e-6 if absf(c) < 1e-6 else c)


## Abgeschnittene Stücke und Toppings teilen sich dieselbe Lebensdauer.
static func is_fallen_expired(age: float, tune := PANCAKE) -> bool:
	return age >= float(tune["FALLEN_DESPAWN_SEC"])


## Deterministische Bot-Zertifizierung (identisch zum Web-Release-Bot).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(PANCAKE, mode)
	var rng := GoobyRng.new(seed_value)
	var stack := {"center": 0.0, "width": float(tune["BASE_WIDTH"])}
	var layers := 0
	var bonus_points := 0
	var limit := 120.0 if bool(tune["ENDLESS"]) else float(tune["MAX_LAYERS"])
	var spread := 0.065
	if mode == "easy":
		spread = 0.055
	elif mode == "hard" or mode == "endless":
		spread = 0.075
	while not is_tower_done(float(stack["width"]), layers, tune) and float(layers) < limit:
		var index := layers + 1
		var topping := is_topping_layer(index, tune)
		var offset := (rng.next() - 0.5) * spread * 2.0
		var drop := resolve_drop(stack, float(stack["center"]) + offset, topping, tune)
		if not bool(drop["landed"]):
			break
		layers += 1
		bonus_points += int(drop["points"])
		stack = {"center": float(drop["center"]), "width": float(drop["width"])}
	return {
		"seed": seed_value,
		"mode": mode,
		"score": tower_score(layers, bonus_points, tune),
		"layers": layers,
		"width": float(stack["width"]),
	}
