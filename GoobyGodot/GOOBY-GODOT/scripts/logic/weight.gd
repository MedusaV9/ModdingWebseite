extends RefCounted
## Gewichts- und Fitness-Modell — Port von GOOBY/src/systems/weight.js (§B5/§C4).
##
## KOSMETISCH-ONLY (§C4.2 bindend): Gewicht aendert nie Stats, Verfallsraten,
## Minispiel-Verfuegbarkeit, Scores oder Preise — es treibt nur Goobys
## Silhouette (Tier-Scale auf dem Rig), Anim-Flavor und zwei Sticker.
## Im v5-Save ist das Gewicht der nackte Float `gooby.weight` (5–95,
## Default 50) — alle Funktionen hier sind PURE Wert-rein/Wert-raus.
##
## Sanft und liebevoll: Der Rig blendet nicht hart zwischen Stufen um,
## sondern nutzt body_scale() — eine stetige Kurve durch die Web-TIER_SCALE-
## Ankerpunkte. Gooby wird bei viel Suessem weich runder und bei Bewegung
## wieder schlanker, ohne Sprung und ohne Kommentar.

## Klemmbereich + Startwert (§B5).
const MIN := 5.0
const MAX := 95.0
const DEFAULT := 50.0
## on_eat-Deltas (§B5): Junk +2.0, gesund +0.5.
const EAT_JUNK := 2.0
const EAT_HEALTHY := 0.5
## on_minigame_end-Deltas (§B5): aktive Spiele −1.0, alle anderen −0.25.
const GAME_ACTIVE := -1.0
const GAME_OTHER := -0.25
## on_ball_fetch-Delta (§B5): −0.2.
const BALL_FETCH := -0.2
## Passive Drift: Richtung 50 mit ±2.0 pro 24 h (§B5).
const DRIFT_TARGET := 50.0
const DRIFT_PER_MIN := 2.0 / 1440.0

## "Aktive" Minispiele mit vollem −1.0 (§B5-Liste verbatim).
const ACTIVE_GAMES: Array[String] = [
	"runner",
	"trampoline",
	"danceParty",
	"bunnyHop",
	"gardenRush",
	"veggieChop",
	"goalieGooby",
	"starHopper",
]

## Stufen-Grenzen (§C4.3, ohne Hysterese): <= 25 / <= 60 / <= 85 / darueber.
const TIER_SLEEK_MAX := 25.0
const TIER_CHUBBY_MAX := 60.0
const TIER_CHONKY_MAX := 85.0
const TIERS: Array[String] = ["sleek", "chubby", "chonky", "floof"]
## Stufe → Koerper-X/Z-Scale (§C4.3) — die Web-Zahlen 1:1.
const TIER_SCALE := {"sleek": 0.93, "chubby": 1.0, "chonky": 1.07, "floof": 1.14}

## Ankerpunkte der stetigen Silhouetten-Kurve: Stufen-Mitten → TIER_SCALE.
## (Zwischen den Ankern wird linear interpoliert — sanfte Uebergaenge statt
## Stufensprung; die Endwerte klemmen auf den Web-Stufenwert.)
const SCALE_ANCHORS := [
	[15.0, 0.93],
	[42.5, 1.0],
	[72.5, 1.07],
	[90.0, 1.14],
]


## Gewichtswert auf [5, 95] klemmen (§B5); Nicht-Zahlen fallen auf 50.
static func clamp_weight(value: Variant) -> float:
	var n := _num_or(value, DEFAULT)
	if is_nan(n) or is_inf(n):
		n = DEFAULT
	return clampf(n, MIN, MAX)


## Fuetterung anwenden (§B5): Junk +2.0, gesund +0.5. Pure — neuer Wert.
static func on_eat(value: Variant, junk: bool) -> float:
	return clamp_weight(clamp_weight(value) + (EAT_JUNK if junk else EAT_HEALTHY))


## Beendetes Minispiel anwenden (§B5): aktive −1.0, andere −0.25.
static func on_minigame_end(value: Variant, game_id: String) -> float:
	var delta := GAME_ACTIVE if ACTIVE_GAMES.has(game_id) else GAME_OTHER
	return clamp_weight(clamp_weight(value) + delta)


## Ball-Apport anwenden (§B5): −0.2.
static func on_ball_fetch(value: Variant) -> float:
	return clamp_weight(clamp_weight(value) + BALL_FETCH)


## Passive Drift Richtung 50 mit ±2.0 pro 24 h (§B5), nie ueber das Ziel
## hinaus. Offline-Sim (§E4): Aufrufer geben mult = 0.3 und deckeln dt_min
## selbst bei 480 Sim-Minuten.
static func tick(value: Variant, dt_min: float, mult := 1.0) -> float:
	var v := clamp_weight(value)
	var step := DRIFT_PER_MIN * maxf(0.0, dt_min) * mult
	if v > DRIFT_TARGET:
		v = maxf(DRIFT_TARGET, v - step)
	elif v < DRIFT_TARGET:
		v = minf(DRIFT_TARGET, v + step)
	return clamp_weight(v)


## Kosmetische Stufe fuer einen Gewichtswert (§C4.3, exakte Grenzen):
## <= 25 sleek · <= 60 chubby (Default) · <= 85 chonky · > 85 floof.
static func tier_of(value: Variant) -> String:
	var v := _num_or(value, DEFAULT)
	if v <= TIER_SLEEK_MAX:
		return "sleek"
	if v <= TIER_CHUBBY_MAX:
		return "chubby"
	if v <= TIER_CHONKY_MAX:
		return "chonky"
	return "floof"


## Stetige Koerper-X/Z-Scale fuer den Rig: linear durch die SCALE_ANCHORS
## (Stufen-Mitte → Web-TIER_SCALE), an den Raendern geklemmt. Monoton
## steigend; scale(15)=0.93, scale(42.5)=1.0, scale(90)=1.14.
static func body_scale(value: Variant) -> float:
	var v := clamp_weight(value)
	var first: Array = SCALE_ANCHORS[0]
	if v <= float(first[0]):
		return float(first[1])
	for i in range(1, SCALE_ANCHORS.size()):
		var a: Array = SCALE_ANCHORS[i - 1]
		var b: Array = SCALE_ANCHORS[i]
		if v <= float(b[0]):
			var t := (v - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), t)
	var last: Array = SCALE_ANCHORS[SCALE_ANCHORS.size() - 1]
	return float(last[1])


static func _num_or(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
