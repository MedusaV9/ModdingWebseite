class_name DeliveryRushLogic
extends RefCounted
## Pure Liefer-Hetze-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/deliveryRush.logic.js (§C1.2 #5 / §C10.2 / §G5).
## Goobys Lieferwagen startet am Laden mit 3 Paketen; eine gesäte Folge aus 3
## VERSCHIEDENEN Zielen der 6 Stadt-Landmarken; 4-m-Abwurfringe geben je +50;
## Crashs −5 mit Boden 0; Zeitbonus +max(0, 120 − s) nach dem 3. Abwurf.
## Coin-Zeile /8, 5..32, Energie 6, Ziel 200.
##
## Enthält zusätzlich den MINIMALEN Stadtraster-Teil aus
## GOOBY/src/city/cityBuilder.js (Raster, isRoad, tileToWorld, Landmarken),
## den die Wegfindung und die Szene brauchen — bewusst hier lokal, damit MG-3
## nicht in die Stadt-Dateien anderer Agents greift.

## Bindende §C1.2-#5-Zahlen + V2/G28-Tuning.
const DELIVERY := {
	"PARCELS": 3,
	"LANDMARK_POOL": 6,
	"DROP_RADIUS_M": 4.0,
	"DROP_POINTS": 50,
	"CRASH_PENALTY": 5,
	"TIME_BONUS_FROM_SEC": 120.0,
	"FRAGILE_CRASH_PENALTY": 20,
	"FRAGILE_CLEAN_BONUS": 15,
	"SPEED_MULT": 1.0,
	"TRAFFIC_DENSITY_MULT": 1.0,
	"CRASH_ALLOWANCE": 0,
	"COIN_RATE": 1.0,
	"COIN_INTERVAL_SEC": 8.0,
	"COIN_POINTS": 3,
	"ENDLESS": false,
	"PARCEL_EXPIRE_SEC": 45.0,
	"ENDLESS_EXPIRED_LIMIT": 3,
}

## V4/GAME-POLISH-5: rein kosmetische Juice-Zahlen (nie Score/Timing).
const DELIVERY_FX := {
	"STREAK_RATE": [[10.5, 0], [11.8, 4], [13.0, 9]],
	"STREAK_POOL": 12,
	"DUST_MIN_SPEED": 6.5,
	"DUST_MIN_YAW_RATE": 0.55,
	"DUST_INTERVAL_SEC": 0.09,
	"NEAR_BANNER_COOLDOWN_SEC": 2.5,
	"POP_SEC": 0.7,
	"POP_LIFT_M": 2.6,
	"POP_SPIN_RAD": 5.0,
}

# ── Stadtraster (Auszug cityBuilder.js — DRIVE_TUNING GRID/TILE_M) ──────────
const GRID := 9
const TILE_M := 20.0
const CENTER := 4
const RING_MIN := 1
const RING_MAX := GRID - 2
const HOME_TILE := Vector2i(7, 2)
const SHOP_TILE := Vector2i(3, 6)
const VET_TILE := Vector2i(2, 2)

## Die 6 Landmarken (§C9.3) mit ihrem Kurbside-Ankerpunkt in Weltmetern.
## shop/vetClinic = ihre Parkbuchten (cityBuilder: ±6.5 m neben dem Blockmittel).
const LANDMARKS := [
	{"id": "shop", "x": 46.5, "z": -20.0},
	{"id": "vetClinic", "x": -46.5, "z": -40.0},
	{"id": "fountain", "x": 12.0, "z": 12.0},
	{"id": "skyTower", "x": 20.0, "z": -46.0},
	{"id": "parkGazebo", "x": -46.0, "z": 20.0},
	{"id": "windmillCafe", "x": 20.0, "z": 48.0},
]

## Block-Kacheln mit Gebäude-Kollidern (Landmarken-Kacheln bleiben frei).
const LANDMARK_TILES := [
	Vector2i(2, 2), Vector2i(5, 5), Vector2i(2, 5), Vector2i(5, 2), Vector2i(6, 5)
]
const PARK_TILE := Vector2i(6, 6)


## Kachel (r, c) → Weltmitte. x wächst nach Osten (+c), z nach Süden (+r).
static func tile_to_world(r: int, c: int) -> Vector2:
	return Vector2((c - CENTER) * TILE_M, (r - CENTER) * TILE_M)


static func world_to_tile(x: float, z: float) -> Vector2i:
	return Vector2i(
		MinigameFrameworkLogic.js_round(z / TILE_M + CENTER),
		MinigameFrameworkLogic.js_round(x / TILE_M + CENTER)
	)


## Festes Ring+Kreuz-Straßennetz (§G G7).
static func is_road(r: int, c: int) -> bool:
	if r < RING_MIN or r > RING_MAX or c < RING_MIN or c > RING_MAX:
		return false
	var on_ring := r == RING_MIN or r == RING_MAX or c == RING_MIN or c == RING_MAX
	var on_cross := r == CENTER or c == CENTER
	return on_ring or on_cross


## Kachelraster als Array[Array[Dictionary]] (`kind`: road|block|rim).
static func build_grid() -> Array:
	var grid: Array = []
	for r in GRID:
		var row: Array = []
		for c in GRID:
			var kind := "rim"
			if is_road(r, c):
				kind = "road"
			elif r >= 1 and r <= RING_MAX and c >= 1 and c <= RING_MAX:
				kind = "block"
			row.append({"kind": kind, "r": r, "c": c})
		grid.append(row)
	return grid


## Gebäude-Kollider je bebauter Block-Kachel (halbe Kachel, achsenparallel).
static func layout_colliders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := TILE_M * 0.34
	for r in GRID:
		for c in GRID:
			if is_road(r, c) or r < 1 or r > RING_MAX or c < 1 or c > RING_MAX:
				continue
			var tile := Vector2i(r, c)
			if tile == SHOP_TILE or tile == PARK_TILE or LANDMARK_TILES.has(tile):
				continue
			var w := tile_to_world(r, c)
			out.append(
				{"minX": w.x - half, "maxX": w.x + half, "minZ": w.y - half, "maxZ": w.y + half}
			)
	return out


# ── Reine Regeln ───────────────────────────────────────────────────────────


## Paket-Wurfbogen: lineare Interpolation plus sin()-Hub (0 an beiden Enden).
## Weltpunkte sind bewusst Dictionaries mit float-Keys statt Vector2/Vector3 —
## Godots Vektortypen halten nur 32-Bit-Floats und der Port würde sonst vom
## Web abweichen (dieselbe Begründung wie in basket_bounce_logic.gd).
static func parcel_arc_pos(from: Dictionary, to: Dictionary, t: float, lift := 2.6) -> Dictionary:
	var k := minf(1.0, maxf(0.0, t))
	if k == 0.0:
		return {"x": float(from["x"]), "y": float(from["y"]), "z": float(from["z"])}
	if k == 1.0:
		return {"x": float(to["x"]), "y": float(to["y"]), "z": float(to["z"])}
	return {
		"x": float(from["x"]) + (float(to["x"]) - float(from["x"])) * k,
		"y": float(from["y"]) + (float(to["y"]) - float(from["y"])) * k + sin(PI * k) * lift,
		"z": float(from["z"]) + (float(to["z"]) - float(from["z"])) * k,
	}


## §G5 Runner-/Steer-Difficulty. `normal` behält die Arcade-Semantik.
static func apply_difficulty(tune := DELIVERY, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var out := tune.duplicate()
	out["SPEED_MULT"] = 1.2 if hard else 0.85
	out["TRAFFIC_DENSITY_MULT"] = 1.15 if hard else 0.85
	out["CRASH_ALLOWANCE"] = int(tune["CRASH_ALLOWANCE"]) + (0 if hard else 1)
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## Coin-Rate der Szene anwenden (Trip-Parameter).
static func with_coin_rate(tune: Dictionary, coin_rate := 1.0) -> Dictionary:
	var rate := coin_rate if (is_finite(coin_rate) and coin_rate > 0.0) else 1.0
	if rate == 1.0:
		return tune
	var out := tune.duplicate()
	out["COIN_RATE"] = rate
	out["COIN_INTERVAL_SEC"] = float(tune["COIN_INTERVAL_SEC"]) / rate
	return out


static func create_endless_state(limit := int(DELIVERY["ENDLESS_EXPIRED_LIMIT"])) -> Dictionary:
	return {"expired": 0, "limit": limit, "ended": false}


## Ein abgelaufenes Paket buchen; true = Lauf zu Ende.
static func record_expiry(state: Dictionary) -> bool:
	if not bool(state["ended"]):
		state["expired"] = int(state["expired"]) + 1
	state["ended"] = int(state["expired"]) >= int(state["limit"])
	return bool(state["ended"])


static func parcel_expired(leg_elapsed: float, tune := DELIVERY) -> bool:
	return bool(tune["ENDLESS"]) and leg_elapsed >= float(tune["PARCEL_EXPIRE_SEC"])


## Gesäte Zielwahl (§C1.5): PARCELS VERSCHIEDENE Landmarken, gesätes
## Fisher-Yates; startet die Folge am `shop`, wird sie rotiert (Start = Laden).
static func pick_deliveries(
	rng: GoobyRng, ids: Array, count := int(DELIVERY["PARCELS"])
) -> Array[String]:
	var pool: Array[String] = []
	for id in ids:
		pool.append(str(id))
	for i in range(pool.size() - 1, 0, -1):
		var j := int(floor(rng.next() * (i + 1)))
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picks := pool.slice(0, count)
	if picks.size() > 1 and picks[0] == "shop":
		picks.append(picks.pop_front())
	return picks


## Gesätes markiertes Paket (0..2), nach der Zielwahl gewürfelt.
static func pick_fragile_parcel(rng: GoobyRng, count := int(DELIVERY["PARCELS"])) -> int:
	return mini(count - 1, int(floor(rng.next() * count)))


## Ein Crash beschädigt nur das GERADE getragene markierte Paket, und nur einmal.
static func fragile_crash_penalty(
	fragile_index: int, current_parcel: int, already_damaged: bool
) -> int:
	if fragile_index == current_parcel and not already_damaged:
		return int(DELIVERY["FRAGILE_CRASH_PENALTY"])
	return 0


## +15, wenn das markierte Paket unbeschädigt ankommt.
static func fragile_delivery_bonus(fragile_index: int, delivered_parcel: int, damaged: bool) -> int:
	if fragile_index == delivered_parcel and not damaged:
		return int(DELIVERY["FRAGILE_CLEAN_BONUS"])
	return 0


static func apply_drop(score: int) -> int:
	return score + int(DELIVERY["DROP_POINTS"])


## Crash: −5, Boden 0 (nie Abschleppen, nie Fail).
static func apply_crash(score: int) -> int:
	return maxi(0, score - int(DELIVERY["CRASH_PENALTY"]))


## Zeitbonus nach dem 3. Abwurf: +max(0, 120 − s), auf ganze Punkte abgerundet.
static func time_bonus(elapsed_sec: float, tune := DELIVERY) -> int:
	return maxi(0, int(floor(float(tune["TIME_BONUS_FROM_SEC"]) - elapsed_sec)))


## Voller Rundenscore einer sauberen Fahrt (Test-/Tuning-Helfer).
static func round_score(drops: int, crashes: int, elapsed_sec: float, tune := DELIVERY) -> int:
	var score := 0
	for _i in drops:
		score = apply_drop(score)
	for _i in crashes:
		score = apply_crash(score)
	if drops >= int(tune["PARCELS"]):
		score += time_bonus(elapsed_sec, tune)
	return score


## Kurbside-Abwurfpunkt (§C9.4): aus jedem schneidenden Kollider herausschieben.
static func drop_point(anchor: Dictionary, colliders: Array, clearance := 1.6) -> Dictionary:
	var x := float(anchor["x"])
	var z := float(anchor["z"])
	for _guard in 4:
		var hit: Dictionary = {}
		for b: Dictionary in colliders:
			if (
				x > float(b["minX"]) - clearance
				and x < float(b["maxX"]) + clearance
				and z > float(b["minZ"]) - clearance
				and z < float(b["maxZ"]) + clearance
			):
				hit = b
				break
		if hit.is_empty():
			break
		var pushes: Array[Dictionary] = [
			{"dx": float(hit["minX"]) - clearance - x, "dz": 0.0},
			{"dx": float(hit["maxX"]) + clearance - x, "dz": 0.0},
			{"dx": 0.0, "dz": float(hit["minZ"]) - clearance - z},
			{"dx": 0.0, "dz": float(hit["maxZ"]) + clearance - z},
		]
		var best: Dictionary = pushes[0]
		for p: Dictionary in pushes:
			if (
				absf(float(p["dx"])) + absf(float(p["dz"]))
				< absf(float(best["dx"])) + absf(float(best["dz"]))
			):
				best = p
		x += float(best["dx"])
		z += float(best["dz"])
	return {"x": x, "z": z}


## Gefegter Ringtest: erkennt einen schnellen Wagen, der den 4-m-Kreis
## zwischen zwei Frames überspringt.
static func segment_hits_drop(
	from: Dictionary, to: Dictionary, center: Dictionary, radius := float(DELIVERY["DROP_RADIUS_M"])
) -> bool:
	var fx := float(from["x"])
	var fz := float(from["z"])
	var dx := float(to["x"]) - fx
	var dz := float(to["z"]) - fz
	var len2 := dx * dx + dz * dz
	var t := 0.0
	if len2 > 0.0:
		t = maxf(
			0.0, minf(1.0, ((float(center["x"]) - fx) * dx + (float(center["z"]) - fz) * dz) / len2)
		)
	var x := fx + dx * t
	var z := fz + dz * t
	var ox := float(center["x"]) - x
	var oz := float(center["z"]) - z
	return sqrt(ox * ox + oz * oz) <= radius


## Nächste Straßenkachel zu einer (evtl. abseitigen) Kachelkoordinate.
static func nearest_road_tile(grid: Array, r: int, c: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for rr in grid.size():
		var row: Array = grid[rr]
		for cc in row.size():
			if str((row[cc] as Dictionary)["kind"]) != "road":
				continue
			var d := float((rr - r) * (rr - r) + (cc - c) * (cc - c))
			if d < best_d:
				best_d = d
				best = Vector2i(rr, cc)
	return best


## Kürzester Straßenweg zwischen zwei Straßenkacheln (4-Nachbarn-BFS).
## Leeres Array = kein Weg (oder Start/Ziel liegt nicht auf der Straße).
static func road_path_between(grid: Array, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var rows := grid.size()
	if rows == 0:
		return empty
	var cols: int = (grid[0] as Array).size()
	if not _is_road_cell(grid, from) or not _is_road_cell(grid, to):
		return empty
	var prev := {from.x * cols + from.y: -1}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			break
		for step in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var nxt: Vector2i = cur + step
			if nxt.x < 0 or nxt.x >= rows or nxt.y < 0 or nxt.y >= cols:
				continue
			var nkey := nxt.x * cols + nxt.y
			if not _is_road_cell(grid, nxt) or prev.has(nkey):
				continue
			prev[nkey] = cur.x * cols + cur.y
			queue.append(nxt)
	var to_key := to.x * cols + to.y
	if not prev.has(to_key):
		return empty
	var path: Array[Vector2i] = []
	var walk: int = to_key
	while walk != -1:
		path.insert(0, Vector2i(walk / cols, walk % cols))
		walk = int(prev[walk])
	return path


static func _is_road_cell(grid: Array, tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= grid.size():
		return false
	var row: Array = grid[tile.x]
	if tile.y < 0 or tile.y >= row.size():
		return false
	return str((row[tile.y] as Dictionary)["kind"]) == "road"


## Deterministisches Arcade-Zertifizierungsmodell (geschlossene Form wie im Web).
static func simulate_autoplay(seed_value: int, mode := "normal", coin_rate := 1.0) -> Dictionary:
	var tune := with_coin_rate(apply_difficulty(DELIVERY, mode), coin_rate)
	var jitter := (seed_value % 7) - 3
	var elapsed := 41.0 + jitter
	if mode == "easy":
		elapsed = 32.0 + jitter
	elif mode == "hard" or mode == "endless":
		elapsed = 49.0 + jitter
	var crashes := 1
	if mode == "easy":
		crashes = 0
	elif mode == "hard" or mode == "endless":
		crashes = 2
	var coin_points := 0
	if float(tune["COIN_RATE"]) > 1.0:
		coin_points = (
			int(floor(elapsed / float(tune["COIN_INTERVAL_SEC"]))) * int(tune["COIN_POINTS"])
		)
	var score := round_score(int(tune["PARCELS"]), crashes, elapsed, tune) + coin_points
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"elapsed": elapsed,
		"crashes": crashes,
		"coinPoints": coin_points,
	}
