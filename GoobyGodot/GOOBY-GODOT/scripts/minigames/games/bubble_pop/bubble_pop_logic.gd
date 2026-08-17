class_name BubblePopLogic
extends RefCounted
## Blasen-Platzer (bubblePop) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/bubblePop.logic.js (§C6.1 #11). 60 s, das
## Zielessen rotiert alle 12 s, Treffer +2, falsche Blase −2 + 0,5 s Stun,
## Stachelblasen platzen nie (Antippen −1). Steig- und Spawn-Kadenz rampen
## linear. Alle Konstanten/Formeln 1:1 aus der Web-Quelle; Determinismus
## über GoobyRng (mulberry32, bit-identisch). Coin-Zeile: /4, 4..24, Ziel 80.

## Bindende §C6.1-#11-Zahlen + G10-Tuning.
const BUBBLE := {
	"DURATION_SEC": 60.0,
	"TARGET_ROTATE_SEC": 12.0,
	"MATCH_PTS": 2,
	"WRONG_PTS": -2,
	"STUN_SEC": 0.5,
	"SPIKY_PTS": -1,
	"RISE_START": 0.62,
	"RISE_END": 1.1,
	"SPAWN_SEC_START": 0.9,
	"SPAWN_SEC_END": 0.5,
	"TARGET_CHANCE": 0.52,
	"SPIKY_CHANCE": 0.15,
	"CHAIN_WINDOW_SEC": 2.0,
	"CHAIN_COUNT": 3,
	"CHAIN_RADIUS": 1.25,
	"FOOD_TOUCH_RADIUS": 0.42,
	"SPIKY_TOUCH_RADIUS": 0.6,
	"ENDLESS": false,
	"ENDLESS_SPIKY_LIMIT": 3,
	"ENDLESS_SPAWN_FLOOR_SEC": 0.35,
}

## Mini-Essen in den Blasen (Web-Reihenfolge — die Rotation hängt daran).
const FOODS: Array[String] = ["carrot", "apple", "banana", "cheese", "donut-sprinkles", "cupcake"]

## Farbenblind-sichere Identität: Farbe ist redundant zum Symbol (Web-Tabelle).
const STYLES := {
	"carrot": {"color": Color("E76F51"), "symbol": "▲"},
	"apple": {"color": Color("2A9D8F"), "symbol": "●"},
	"banana": {"color": Color("E9C46A"), "symbol": "◆"},
	"cheese": {"color": Color("3A86FF"), "symbol": "+"},
	"donut-sprinkles": {"color": Color("8338EC"), "symbol": "★"},
	"cupcake": {"color": Color("FF70A6"), "symbol": "≈"},
}

## V4/GAME-POLISH-1: Feier-Kadenz der Treffer-Serie (rein audiovisuell).
const MATCH_STREAK_EVERY := 5


## §G5 Timed-Arena-Difficulty; `normal` liefert die Basistabelle unverändert.
static func apply_difficulty(tune: Dictionary = BUBBLE, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var spawn_mult := 0.85 if hard else 1.2
	var window_mult := 0.8 if hard else 1.25
	var out := tune.duplicate()
	out["DURATION_SEC"] = (
		float(tune["DURATION_SEC"]) if hard else float(tune["DURATION_SEC"]) * 1.2
	)
	out["SPAWN_SEC_START"] = float(tune["SPAWN_SEC_START"]) * spawn_mult
	out["SPAWN_SEC_END"] = float(tune["SPAWN_SEC_END"]) * spawn_mult
	out["TARGET_ROTATE_SEC"] = maxf(0.35, float(tune["TARGET_ROTATE_SEC"]) * window_mult)
	out["ENDLESS"] = mode == "endless"
	return out


## Steiggeschwindigkeit zum Rundenzeitpunkt (lineare Rampe).
static func rise_speed_at(elapsed: float, duration := 60.0, tune: Dictionary = BUBBLE) -> float:
	var t := _ramp_t(elapsed, duration, tune)
	return float(tune["RISE_START"]) + (float(tune["RISE_END"]) - float(tune["RISE_START"])) * t


## Sekunden bis zur nächsten Blase (Dichte-Rampe, im Endlos mit Boden).
static func spawn_interval_at(elapsed: float, duration := 60.0, tune: Dictionary = BUBBLE) -> float:
	var t := _ramp_t(elapsed, duration, tune)
	var start := float(tune["SPAWN_SEC_START"])
	var interval := start + (float(tune["SPAWN_SEC_END"]) - start) * t
	if bool(tune["ENDLESS"]):
		return maxf(float(tune["ENDLESS_SPAWN_FLOOR_SEC"]), interval)
	return interval


## Welcher Ziel-Slot gerade aktiv ist (rotiert alle TARGET_ROTATE_SEC).
static func target_index_at(elapsed: float, tune: Dictionary = BUBBLE) -> int:
	return maxi(0, int(floor(elapsed / float(tune["TARGET_ROTATE_SEC"]))))


## Geseedete Zielreihenfolge: jedes Essen kommt dran, bevor eines wiederholt
## wird, und zwei aufeinanderfolgende Ziele sind nie gleich.
static func target_order(rng: GoobyRng, count: int) -> Array[String]:
	var order: Array[String] = []
	while order.size() < count:
		var shuffled: Array[String] = FOODS.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := int(floor(rng.next() * float(i + 1)))
			var tmp := shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		if order.size() > 0 and shuffled[0] == order[order.size() - 1]:
			shuffled.push_back(shuffled.pop_front())
		order.append_array(shuffled)
	return order.slice(0, count)


## Nächste Blase würfeln: stachelig, Ziel-Essen oder ein anderes Essen.
static func roll_bubble(
	rng: GoobyRng, target_food: String, tune: Dictionary = BUBBLE
) -> Dictionary:
	if rng.next() < float(tune["SPIKY_CHANCE"]):
		return {"kind": "spiky", "food": ""}
	if rng.next() < float(tune["TARGET_CHANCE"]):
		return {"kind": "food", "food": target_food}
	var others: Array[String] = []
	for food in FOODS:
		if food != target_food:
			others.append(food)
	var idx := mini(others.size() - 1, int(floor(rng.next() * float(others.size()))))
	return {"kind": "food", "food": others[idx]}


## Tipp-Regel (§C6.1 #11): Treffer +2 · falsch −2 + Stun · Stachel −1 ohne Platzen.
static func pop_result(bubble: Dictionary, target_food: String) -> Dictionary:
	if bubble["kind"] == "spiky":
		return {
			"result": "spiky",
			"delta": int(BUBBLE["SPIKY_PTS"]),
			"stunSec": 0.0,
			"pops": false,
		}
	if bubble["food"] == target_food:
		return {"result": "match", "delta": int(BUBBLE["MATCH_PTS"]), "stunSec": 0.0, "pops": true}
	return {
		"result": "wrong",
		"delta": int(BUBBLE["WRONG_PTS"]),
		"stunSec": float(BUBBLE["STUN_SEC"]),
		"pops": true,
	}


## Score-Delta anwenden, bei 0 gefloort.
static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## Frischer V3-Ketten-Tracker (3 gleiche Treffer in 2 s zünden eine Kette).
static func create_pop_chain() -> Dictionary:
	return {"style": "", "count": 0, "lastAt": -INF, "chains": 0}


## Treffer in die Kette buchen; liefert {triggered, count}.
static func record_pop_chain(chain: Dictionary, style: String, at_sec: float) -> Dictionary:
	var same_style: bool = chain["style"] == style
	var in_window := at_sec - float(chain["lastAt"]) <= float(BUBBLE["CHAIN_WINDOW_SEC"])
	var continues := same_style and in_window
	chain["style"] = style
	chain["count"] = (int(chain["count"]) + 1) if continues else 1
	chain["lastAt"] = at_sec
	if int(chain["count"]) < int(BUBBLE["CHAIN_COUNT"]):
		return {"triggered": false, "count": int(chain["count"])}
	chain["count"] = 0
	chain["chains"] = int(chain["chains"]) + 1
	return {"triggered": true, "count": 0}


## Aktive gleichfarbige Nachbarn im Kettenradius (Indizes).
static func chain_neighbor_indices(
	bubbles: Array, style: String, x: float, y: float, radius := 1.25
) -> Array[int]:
	var out: Array[int] = []
	for i in bubbles.size():
		var b: Dictionary = bubbles[i]
		if not bool(b.get("active", false)) or str(b.get("food", "")) != style:
			continue
		if Vector2(float(b["x"]) - x, float(b["y"]) - y).length() <= radius:
			out.append(i)
	return out


## Trefferradius je Blasenart (Stacheln reichen weiter als der Körper).
static func touch_radius_for(kind: String) -> float:
	if kind == "spiky":
		return float(BUBBLE["SPIKY_TOUCH_RADIUS"])
	return float(BUBBLE["FOOD_TOUCH_RADIUS"])


## Jede 5. Treffer-Serie feiert (nur Juice, keine Punkte).
static func match_streak_milestone(streak: int) -> bool:
	return streak > 0 and streak % MATCH_STREAK_EVERY == 0


## §G5.4 Endlos endet mit der 3. geplatzten Stachelblase.
static func endless_should_end(spiky_pops: int, tune: Dictionary = BUBBLE) -> bool:
	return bool(tune["ENDLESS"]) and spiky_pops >= int(tune["ENDLESS_SPIKY_LIMIT"])


## Deterministische Bot-Zertifizierung (zahlengleich zum Web-Release-Bot).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(BUBBLE, mode)
	var rng := GoobyRng.new(seed_value)
	var duration := 90.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	var elapsed := 0.0
	var score := 0
	var matches := 0
	var spiky_pops := 0
	var reaction_accuracy := minf(
		0.93, 0.93 * (float(tune["TARGET_ROTATE_SEC"]) / float(BUBBLE["TARGET_ROTATE_SEC"]))
	)
	while elapsed < duration and spiky_pops < int(tune["ENDLESS_SPIKY_LIMIT"]):
		elapsed += spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
		var bubble := roll_bubble(rng, "carrot", tune)
		if bubble["kind"] == "spiky":
			if rng.next() < 0.025:
				spiky_pops += 1
			continue
		if bubble["food"] == "carrot" and rng.next() < reaction_accuracy:
			score += int(tune["MATCH_PTS"])
			matches += 1
			if matches % int(tune["CHAIN_COUNT"]) == 0:
				score += int(tune["MATCH_PTS"])
	return {"seed": seed_value, "mode": mode, "score": score, "spikyPops": spiky_pops}


## Gemeinsame Rampen-Zeit: getaktete Modi klemmen bei 1, Endlos wächst weiter.
static func _ramp_t(elapsed: float, duration: float, tune: Dictionary) -> float:
	if bool(tune["ENDLESS"]):
		return maxf(0.0, elapsed / duration)
	return minf(1.0, maxf(0.0, elapsed / duration))
