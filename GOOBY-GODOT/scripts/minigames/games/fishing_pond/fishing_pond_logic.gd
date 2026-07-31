class_name FishingPondLogic
extends RefCounted
## Pure Angelteich-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/fishingPond.logic.js (§C6.1 #10 / §C6 Arten,
## §C10.2 seltene Varianten). 90 s Runde, HALTEN senkt den Haken, LOSLASSEN
## angelt den nächsten Schwimmer im Fangradius; S/M/L geben 2/3/5, ein Stiefel
## −3; große Fische brauchen ~5 Wackel-Taps in 2 s, sonst reißt die Leine.

## Bindende §C6.1-#10-Zahlen; Coin-Zeile 3/4/26, Ziel 65.
const FISHING := {
	"DURATION_SEC": 90.0,
	"VALUES": {"S": 2, "M": 3, "L": 5, "boot": -3},
	"REEL_TAPS": 5,
	"REEL_WINDOW_SEC": 2.0,
	"REEL_MAX_FRAME_SEC": 0.1,
	"CATCH_RADIUS": 0.55,
	"HOOK_X": 0.0,
	"MAX_DEPTH": 3.9,
	"LOWER_SPEED": 2.1,
	"RAISE_SPEED": 3.4,
	"FISH_DEPTH_MIN": 0.55,
	"FISH_DEPTH_MAX": 3.7,
	"POND_HALF_W": 1.8,
	"FISH_COUNT": 7,
	"RESPAWN_SEC": 1.2,
	"SIZES":
	{
		"S": {"weight": 45, "scale": 0.34, "speed": [0.5, 0.85]},
		"M": {"weight": 35, "scale": 0.5, "speed": [0.38, 0.62]},
		"L": {"weight": 20, "scale": 0.72, "speed": [0.28, 0.48]},
	},
	"BOOT_MIN_GAP_SEC": 14.0,
	"BOOT_CHANCE": 0.6,
	"BOOT_SPEED": 0.28,
	"ENDLESS": false,
	"ENDLESS_FAILURE_LIMIT": 3,
}

## §C6 Artentabelle (Album-Set 1) — Größe → Kandidaten.
const FISH_SPECIES := {
	"S": ["tinyMinnow", "blueDace", "sunnyCarp"],
	"M": ["pinkKoi", "stripeBass"],
	"L": ["bigWhopper", "nightEel"],
}

const GOLDEN_FISH_CHANCE := 0.02
const NIGHT_EEL_CHANCE := 0.5

## §C10.2: je Größe eine seltene Sichtvariante (weight = Chance auf 100 Spawns).
const RARE_SPECIES := {
	"pearlMinnow": {"kind": "S", "weight": 8, "collectionId": "tinyMinnow"},
	"sunsetKoi": {"kind": "M", "weight": 5, "collectionId": "pinkKoi"},
	"gildedWhopper": {"kind": "L", "weight": 2, "collectionId": "goldenFish"},
}

const RARE_SET_BONUS := 15

## Artenfarben für die Teich-Schwimmer (Web-Hex 1:1).
const SPECIES_COLORS := {
	"tinyMinnow": "#9FB2C8",
	"blueDace": "#5B8BD9",
	"sunnyCarp": "#E8A33D",
	"pinkKoi": "#E88BB0",
	"stripeBass": "#7A9E7E",
	"bigWhopper": "#4E6E8E",
	"nightEel": "#6E5E9E",
	"goldenFish": "#FFD24A",
	"pearlMinnow": "#D8F5F2",
	"sunsetKoi": "#FF8A6B",
	"gildedWhopper": "#F7C948",
}


## §G5 Zeitarena-Difficulty; `normal` liefert die Basistabelle unverändert.
static func apply_difficulty(tune := FISHING, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var spawn_mult := 0.85 if hard else 1.2
	var window_mult := 0.8 if hard else 1.25
	var out := tune.duplicate()
	out["DURATION_SEC"] = (
		float(tune["DURATION_SEC"]) if hard else float(tune["DURATION_SEC"]) * 1.2
	)
	out["RESPAWN_SEC"] = float(tune["RESPAWN_SEC"]) * spawn_mult
	out["BOOT_MIN_GAP_SEC"] = float(tune["BOOT_MIN_GAP_SEC"]) * spawn_mult
	out["REEL_WINDOW_SEC"] = maxf(0.35, float(tune["REEL_WINDOW_SEC"]) * window_mult)
	out["CATCH_RADIUS"] = maxf(
		float(tune["CATCH_RADIUS"]) * 0.55, float(tune["CATCH_RADIUS"]) * window_mult
	)
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## §G5.4: gerissene Leinen (entkommene L-Fische) und Stiefel teilen das Limit.
static func create_endless_state(limit := int(FISHING["ENDLESS_FAILURE_LIMIT"])) -> Dictionary:
	return {"failures": 0, "limit": limit, "ended": false}


static func record_failure(state: Dictionary, kind: String) -> bool:
	if (kind == "lineBreak" or kind == "boot") and not bool(state["ended"]):
		state["failures"] = int(state["failures"]) + 1
	state["ended"] = int(state["failures"]) >= int(state["limit"])
	return bool(state["ended"])


## Haken senken solange gehalten wird (gedeckelt bei MAX_DEPTH).
static func lower_depth(depth: float, dt: float, tune := FISHING) -> float:
	return minf(float(tune["MAX_DEPTH"]), depth + float(tune["LOWER_SPEED"]) * dt)


## Fangwert nach Art: S 2 / M 3 / L 5 / Stiefel −3.
static func catch_value(kind: String) -> int:
	return int((FISHING["VALUES"] as Dictionary).get(kind, 0))


## Nur große Fische brauchen das Einhol-Gewackel.
static func needs_reel(kind: String) -> bool:
	return kind == "L"


## LOSLASSEN-Regel: nächster Schwimmer im Fangradius (x/Tiefe-Ebene).
static func nearest_catch(
	items: Array, hook_x: float, hook_depth: float, radius := float(FISHING["CATCH_RADIUS"])
) -> int:
	var best := -1
	var best_dist := INF
	for i in items.size():
		var item: Dictionary = items[i]
		var dx := float(item["x"]) - hook_x
		var dd := float(item["depth"]) - hook_depth
		var d := sqrt(dx * dx + dd * dd)
		if d <= radius and d < best_dist:
			best = i
			best_dist = d
	return best


## Einhol-Auflösung: ~5 schnelle Taps im Fenster, sonst entkommt der Fisch.
static func reel_resolve(tap_count: int, elapsed_sec: float, tune := FISHING) -> String:
	if tap_count >= int(tune["REEL_TAPS"]):
		return "caught"
	if elapsed_sec >= float(tune["REEL_WINDOW_SEC"]):
		return "escaped"
	return "reeling"


## Ruckel-toleranter Einhol-Timer: ein Frame kostet höchstens 0.1 s Fenster.
static func advance_reel_elapsed(elapsed_sec: float, dt: float, tune := FISHING) -> float:
	return elapsed_sec + minf(maxf(0.0, dt), float(tune["REEL_MAX_FRAME_SEC"]))


## Fischgröße nach Seltenheitsgewicht würfeln (S häufig … L selten).
static func roll_fish_kind(rng: Callable) -> String:
	var sizes: Dictionary = FISHING["SIZES"]
	var total := 0.0
	for kind: String in sizes:
		total += float(sizes[kind]["weight"])
	var roll := float(rng.call()) * total
	for kind: String in sizes:
		roll -= float(sizes[kind]["weight"])
		if roll < 0.0:
			return kind
	return "S"


## Seitliche Schwimmgeschwindigkeit (größere Fische sind langsamer).
static func fish_speed_for(kind: String, rng: Callable) -> float:
	var speed: Array = (FISHING["SIZES"] as Dictionary)[kind]["speed"]
	return float(speed[0]) + float(rng.call()) * (float(speed[1]) - float(speed[0]))


## Stiefel-Kadenz: erst nach der Mindestpause zulässig, dann Chancenwurf.
static func should_spawn_boot(rng: Callable, since_last_boot: float, tune := FISHING) -> bool:
	if since_last_boot < float(tune["BOOT_MIN_GAP_SEC"]):
		return false
	return float(rng.call()) < float(tune["BOOT_CHANCE"])


## Fang verbuchen, bei 0 abgefangen (ein Stiefel drückt nie ins Minus).
static func apply_catch(score: int, value: int) -> int:
	return maxi(0, score + value)


## Art eines gespawnten Fisches würfeln (§C6, deterministisch am rng-Strom).
static func roll_species(kind: String, rng: Callable, night := false) -> String:
	if kind == "L":
		if float(rng.call()) < GOLDEN_FISH_CHANCE:
			return "goldenFish"
		if night and float(rng.call()) < NIGHT_EEL_CHANCE:
			return "nightEel"
		return "bigWhopper"
	var options: Array = FISH_SPECIES.get(kind, FISH_SPECIES["S"])
	return options[mini(options.size() - 1, int(floor(float(rng.call()) * options.size())))]


## Erst die V3-Seltenheit würfeln, dann die unveränderte v2-Artentabelle.
static func roll_species_detail(kind: String, rng: Callable, night := false) -> Dictionary:
	for id: String in RARE_SPECIES:
		var def: Dictionary = RARE_SPECIES[id]
		if str(def["kind"]) != kind:
			continue
		if float(rng.call()) * 100.0 < float(def["weight"]):
			return {"species": id, "collectionId": str(def["collectionId"]), "rare": true}
		break
	var species := roll_species(kind, rng, night)
	return {"species": species, "collectionId": species, "rare": false}


## Album-Id einer Basis- oder Seltenheitsart.
static func species_collection_id(species: String) -> String:
	if RARE_SPECIES.has(species):
		return str(RARE_SPECIES[species]["collectionId"])
	return species


## W13/SAMMLUNG: Fangliste → fish-Set-Einträge fürs report_end (Web
## framework.js: award('fish', speciesId) pro Fang). Der "__bonus"-Marker
## (rare_set_bonus) ist kein Fang und fliegt raus; Seltenheiten mappen auf
## ihre Basis-Album-Id.
static func collection_ids(caught: Array) -> Array[String]:
	var ids: Array[String] = []
	for species: Variant in caught:
		if str(species) != "__bonus":
			ids.append(species_collection_id(str(species)))
	return ids


## Farbe einer Art (Fallback: neutrales Teichgrau).
static func species_color(species: String) -> Color:
	return Color(str(SPECIES_COLORS.get(species, "#9FB2C8")))


## §C10.2: alle drei Seltenheiten in EINEM Lauf geben exakt 15 Bonuspunkte.
static func rare_set_bonus(species: Array) -> int:
	for id: String in RARE_SPECIES:
		if not species.has(id):
			return 0
	return RARE_SET_BONUS


## Deterministischer Zertifizierungsbot (mechanikbasiert, Web-identisch).
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(FISHING, mode)
	var rng := GoobyRng.new(seed_value)
	var stream := func() -> float: return rng.next()
	var duration := 120.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	var attempts := int(floor(duration / (1.75 + float(tune["RESPAWN_SEC"]) * 0.25)))
	var score := 0
	var failures := 0
	for i in attempts:
		var kind := roll_fish_kind(stream)
		var accuracy := minf(
			0.94, 0.72 * (float(tune["CATCH_RADIUS"]) / float(FISHING["CATCH_RADIUS"]))
		)
		if rng.next() > accuracy:
			continue
		if kind == "L" and rng.next() > minf(0.96, float(tune["REEL_WINDOW_SEC"]) / 2.2):
			failures += 1
			continue
		score = apply_catch(score, catch_value(kind))
	return {"seed": seed_value, "mode": mode, "score": score, "failures": failures}
