class_name CityDriveLogic
extends RefCounted
## Pure City-Drive-ARCADE-Logik (W13B/DRIVE) — die Godot-Rundenfassung des
## §C4.7-Münzlaufs aus GOOBY/src/minigames/games/cityDrive.js. Alle Web-
## Zahlen VERBATIM aus data/constants.js (DRIVE/DRIVE_TUNING) + cityDrive.js
## (ARCADE_SPEED): 90-s-Lauf, 26 aktive Münzen (Respawn beim Einsammeln,
## Radius 3 m), Auto-Throttle 9 → 15 m/s (Rampe erst nach 20 s), Crash =
## Tempo × 0.3 + 2 s Schonfrist, 3 Crashes = Abschlepp-Teleport
## (DRIVE.CRASHES_FOR_TOW → ctx.strike(), Cutscene macht der Host).
##
## GODOT-EIGEN (dokumentierte Ableitungen, das Web excludiert cityDrive aus
## difficultyTargets §G5.1): die Punkte-Skala ×10 (1 Münze = 10 Punkte ⇒
## Coin-Row /10 zahlt zahlengleich zum Web-Pickup), Checkpoint-Ringe als
## Ankunfts-Semantik der Trips (ARRIVAL-Nicken, +30), Difficulty-Zeilen nach
## dem deliveryRush-Muster (SPEED/TRAFFIC ±) und das Schwer-Ziel nach der
## §G5.4-Regel „≈ 80 % vom Cap-Score“ (Cap 350 = divisor 10 × max 35 ⇒ 280).
##
## Enthält wie delivery_rush_logic.gd einen MINIMALEN Stadtraster-Teil
## (kompaktes 7×7-Ring+Kreuz statt der 9×9-Trips-Stadt) — bewusst lokal,
## damit W13B nicht in city_scene/cityBuilder-Dateien anderer Agents greift.

## Bindende Zahlen (Web-Quelle im Kommentar; „Godot“ = dokumentiert eigen).
const ARCADE := {
	"DURATION_SEC": 90.0,  # DRIVE.ARCADE_DURATION_SEC
	"COINS_ACTIVE": 26,  # DRIVE_TUNING.ARCADE_COINS_ACTIVE
	"PICKUP_RADIUS_M": 3.0,  # DRIVE_TUNING.PICKUP_RADIUS_M
	"PICKUP_POINTS": 10,  # DRIVE.PICKUP_COINS (1 c) × Punkte-Skala 10
	"CHECKPOINT_POINTS": 30,  # Godot: Ankunfts-Nicken (Trips: ARRIVAL_BONUS)
	"CHECKPOINT_RADIUS_M": 4.0,  # DRIVE.PARKING_RADIUS
	"ZERO_CRASH_BONUS": 50,  # DRIVE.ZERO_CRASH_BONUS (5 c) × Punkte-Skala 10
	"CRASH_SPEED_MULT": 0.3,  # DRIVE.CRASH_SPEED_MULT
	"CRASH_INVULN_SEC": 2.0,  # DRIVE_TUNING.CRASH_INVULN_SEC
	"BASE_SPEED": 9.0,  # DRIVE.BASE_SPEED
	"MAX_SPEED": 15.0,  # cityDrive.js ARCADE_SPEED.MAX_SPEED_MS
	"RAMP_DELAY_SEC": 20.0,  # cityDrive.js ARCADE_SPEED.RAMP_DELAY_SEC
	"SPEED_RAMP_SEC": 22.0,  # DRIVE_TUNING.SPEED_RAMP_SEC
	"STEER_RATE": 1.9,  # DRIVE_TUNING.STEER_RATE (CityCarFeel.STEER_RATE)
	"ACCEL_UP": 5.5,  # carController update() (CityCarFeel.ACCEL_UP)
	"ACCEL_DOWN": 9.0,  # carController update() (CityCarFeel.ACCEL_DOWN)
	"SPEED_MULT": 1.0,  # Difficulty-Hebel (deliveryRush-Muster)
	"TRAFFIC_DENSITY_MULT": 1.0,  # Difficulty-Hebel (deliveryRush-Muster)
	"CAR_SPEED_MULT": 1.0,  # Autohaus (CarStatsLogic.speed_mult)
	"CAR_HANDLING_MULT": 1.0,  # Autohaus (CarStatsLogic.handling_mult)
	"CAR_BOOST_MULT": 1.0,  # Autohaus (CarStatsLogic.boost_mult)
	"STRIKE_LIMIT": 3,  # DRIVE.CRASHES_FOR_TOW
	"ENDLESS": false,
}

## Ein Checkpoint spawnt mindestens so weit weg (m) — sonst „Ankunft“ gratis.
const CHECKPOINT_MIN_DIST_M := 40.0

# ── Kompaktes Stadtraster (7×7 Ring+Kreuz, Kacheln wie die 9×9-Stadt) ───────
const GRID := 7
const TILE_M := 20.0
const CENTER := 3
const RING_MIN := 1
const RING_MAX := GRID - 2


## Kachel (r, c) → Weltmitte. x wächst nach Osten (+c), z nach Süden (+r).
static func tile_to_world(r: int, c: int) -> Vector2:
	return Vector2((c - CENTER) * TILE_M, (r - CENTER) * TILE_M)


static func world_to_tile(x: float, z: float) -> Vector2i:
	return Vector2i(
		MinigameFrameworkLogic.js_round(z / TILE_M + CENTER),
		MinigameFrameworkLogic.js_round(x / TILE_M + CENTER)
	)


## Festes Ring+Kreuz-Straßennetz (kompakte Fassung des §G-G7-Rasters).
static func is_road(r: int, c: int) -> bool:
	if r < RING_MIN or r > RING_MAX or c < RING_MIN or c > RING_MAX:
		return false
	var on_ring := r == RING_MIN or r == RING_MAX or c == RING_MIN or c == RING_MAX
	var on_cross := r == CENTER or c == CENTER
	return on_ring or on_cross


## Alle befahrbaren Kacheln (für Münz-Streuung und Checkpoint-Wahl).
static func road_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in GRID:
		for c in GRID:
			if is_road(r, c):
				out.append(Vector2i(r, c))
	return out


## Gebäude-Kollider je bebauter Block-Kachel (halbe Kachel, achsenparallel —
## dasselbe Muster wie delivery_rush_logic.layout_colliders).
static func layout_colliders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := TILE_M * 0.34
	for r in GRID:
		for c in GRID:
			if is_road(r, c) or r < RING_MIN or r > RING_MAX or c < RING_MIN or c > RING_MAX:
				continue
			var w := tile_to_world(r, c)
			out.append(
				{"minX": w.x - half, "maxX": w.x + half, "minZ": w.y - half, "maxZ": w.y + half}
			)
	return out


# ── Difficulty + Autohaus ───────────────────────────────────────────────────


## §G5-Modi nach dem deliveryRush-Muster: `normal` = Web-Arcade-Semantik,
## easy/hard drehen an Tempo + Verkehrsdichte, endless kappt den Timer
## (Ende dann NUR über 3 Strikes — Spiegel der Web-Tow-Semantik).
static func apply_difficulty(tune := ARCADE, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var out := tune.duplicate()
	out["SPEED_MULT"] = 1.2 if hard else 0.85
	out["TRAFFIC_DENSITY_MULT"] = 1.15 if hard else 0.85
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## Autohaus-Multiplikatoren (CarStatsLogic.multipliers) einmischen —
## defensiv: fehlende/hostile Werte bleiben Neutralbasis 1.0.
static func with_car(tune: Dictionary, mults: Variant) -> Dictionary:
	if not (mults is Dictionary) or (mults as Dictionary).is_empty():
		return tune
	var m := mults as Dictionary
	var out := tune.duplicate()
	out["CAR_SPEED_MULT"] = _mult_or_one(m.get("speed"))
	out["CAR_HANDLING_MULT"] = _mult_or_one(m.get("handling"))
	out["CAR_BOOST_MULT"] = _mult_or_one(m.get("boost"))
	return out


# ── Fahrmodell (Auto-Throttle, Web-Rampe) ───────────────────────────────────


## Zieltempo bei Rundenzeit t: BASE 9 bis RAMP_DELAY 20 s, danach linear auf
## MAX 15 über SPEED_RAMP_SEC 22 s (Web ARCADE_SPEED) — mal Difficulty- und
## Autohaus-Tempo-Multiplikator.
static func target_speed(elapsed: float, tune := ARCADE) -> float:
	var base := float(tune["BASE_SPEED"])
	var top := float(tune["MAX_SPEED"])
	var ramp := clampf(
		(elapsed - float(tune["RAMP_DELAY_SEC"])) / float(tune["SPEED_RAMP_SEC"]), 0.0, 1.0
	)
	var speed := base + (top - base) * ramp
	return speed * float(tune["SPEED_MULT"]) * float(tune["CAR_SPEED_MULT"])


## Ein Tempo-Integrationsschritt Richtung Ziel (asymmetrisch 5.5/9 m/s² wie
## carController) — der Boost-Multiplikator wirkt NUR aufs Beschleunigen.
static func step_speed(speed: float, target: float, dt: float, tune := ARCADE) -> float:
	var accel := float(tune["ACCEL_DOWN"])
	if speed < target:
		accel = float(tune["ACCEL_UP"]) * float(tune["CAR_BOOST_MULT"])
	return speed + signf(target - speed) * minf(absf(target - speed), accel * dt)


## Effektive Lenkrate (rad/s bei Voll-Auslenkung) — Handling-Multiplikator.
static func steer_rate(tune := ARCADE) -> float:
	return float(tune["STEER_RATE"]) * float(tune["CAR_HANDLING_MULT"])


# ── Reine Regeln (Score, Timer, Streuung) ───────────────────────────────────


static func apply_pickup(score: int, tune := ARCADE) -> int:
	return score + int(tune["PICKUP_POINTS"])


static func apply_checkpoint(score: int, tune := ARCADE) -> int:
	return score + int(tune["CHECKPOINT_POINTS"])


## +50, wenn die Runde ohne Crash endet (Web ZERO_CRASH_BONUS × 10).
static func zero_crash_bonus(crashes: int, tune := ARCADE) -> int:
	return int(tune["ZERO_CRASH_BONUS"]) if crashes <= 0 else 0


static func time_left(elapsed: float, tune := ARCADE) -> float:
	return maxf(0.0, float(tune["DURATION_SEC"]) - elapsed)


## Timer abgelaufen? (Endlos kennt keinen Timer — Ende nur über Strikes.)
static func round_over(elapsed: float, tune := ARCADE) -> bool:
	return not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"])


## Gesäte Münz-Streuung: `count` Punkte auf zufälligen Straßenkacheln mit
## Quer-Jitter (±6 m — bleibt auf dem 13-m-Asphaltband). Deterministisch
## über den injizierten RNG.
static func scatter_coins(rng: GoobyRng, count: int) -> Array[Vector2]:
	var tiles := road_tiles()
	var out: Array[Vector2] = []
	for _i in count:
		var tile := tiles[int(rng.next() * float(tiles.size())) % tiles.size()]
		var w := tile_to_world(tile.x, tile.y)
		var jx := (rng.next() - 0.5) * 12.0
		var jz := (rng.next() - 0.5) * 12.0
		out.append(Vector2(w.x + jx, w.y + jz))
	return out


## Gesäte Checkpoint-Wahl: zufällige Straßenkachel mit Mindestabstand zum
## Wagen (CHECKPOINT_MIN_DIST_M) — der fernste Kandidat, falls keiner passt.
static func next_checkpoint(rng: GoobyRng, from: Vector2) -> Vector2:
	var tiles := road_tiles()
	var best := from
	var best_d := -1.0
	for _guard in 12:
		var tile := tiles[int(rng.next() * float(tiles.size())) % tiles.size()]
		var w := tile_to_world(tile.x, tile.y)
		var d := from.distance_to(w)
		if d >= CHECKPOINT_MIN_DIST_M:
			return w
		if d > best_d:
			best_d = d
			best = w
	return best


## Voller Rundenscore (Test-/Tuning-Helfer + Bot-Grundlage).
static func round_score(pickups: int, checkpoints: int, crashes: int, tune := ARCADE) -> int:
	var score := 0
	for _i in pickups:
		score = apply_pickup(score, tune)
	for _i in checkpoints:
		score = apply_checkpoint(score, tune)
	return score + zero_crash_bonus(crashes, tune)


## Deterministisches Zertifizierungsmodell (geschlossene Form wie
## deliveryRush.simulate_autoplay): der Bot fährt auf Schwer SCHNELLER
## (SPEED_MULT 1.2) und sammelt daher mehr Münzen/Checkpoints ein, kassiert
## aber Crashes — Monotonie easy < normal < hard gilt PRO Seed (derselbe
## Jitter wirkt auf alle Modi gleich).
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(ARCADE, mode)
	var jitter := (seed_value % 5) - 2
	var pickups := 20
	var checkpoints := 4
	var crashes := 1
	if mode == "easy":
		pickups = 16
		checkpoints = 3
		crashes = 0
	elif mode == "hard" or mode == "endless":
		pickups = 25
		checkpoints = 5
		crashes = 2
	pickups = maxi(0, pickups + jitter)
	var score := round_score(pickups, checkpoints, crashes, tune)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"pickups": pickups,
		"checkpoints": checkpoints,
		"crashes": crashes,
	}


static func _mult_or_one(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return clampf(float(value), 0.5, 1.5)
		_:
			return 1.0
