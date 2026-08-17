class_name CarStatsLogic
extends RefCounted
## Auto-Stats → Fahrparameter (Doc G §6, W13B/DRIVE) — PURE, deterministisch,
## geklemmt. EIN Mapping für alle Fahr-Minigames (cityDrive direkt, delivery-
## Rush über den bestehenden `car_speed_mult`-Hook) UND die Pregame-Auto-Zeile
## („Dein Auto: <Name> — Tempo ▮▮▯▯▯“).
##
## Vertrag: `stats` = {"speed": 1..10, "handling": 1..10, "boost": 1..10} aus
## scripts/city/data/cars.json (AutoKatalog). Der Start-Sedan (3/3/3) ist die
## NEUTRALBASIS und mappt exakt auf Multiplikator 1.0 — wer nie das Autohaus
## besucht, spielt zahlengleich wie vor W13B (bestehende Balance unberührt).
## Hostile/fehlende Werte fallen auf die Neutralbasis zurück und werfen nie.

## Neutralbasis (der Start-Sedan) und Wertebereich der Rohstats.
const STAT_BASE := 3
const STAT_MIN := 1
const STAT_MAX := 10

## Steigung pro Stat-Punkt über/unter der Basis (bewusst sanft — Autos sind
## ein Bonus, kein Pay-to-win: das beste Auto fährt ~21 % schneller).
const SPEED_STEP := 0.03
const HANDLING_STEP := 0.025
const BOOST_STEP := 0.03

## Harte Klemmen der Multiplikatoren (Difficulty-Balance bleibt intakt).
const SPEED_MULT_RANGE := Vector2(0.85, 1.25)
const HANDLING_MULT_RANGE := Vector2(0.85, 1.2)
const BOOST_MULT_RANGE := Vector2(0.85, 1.3)

## Pregame-Anzeige: 1..10 → 5 Balken-Slots.
const BAR_SLOTS := 5
const BAR_FULL := "▮"
const BAR_EMPTY := "▯"


## Rohstat defensiv lesen: Nicht-Zahlen → Basis, dann auf 1..10 klemmen.
static func clamp_stat(value: Variant) -> int:
	var n := STAT_BASE
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			n = int(floor(float(value)))
		_:
			n = STAT_BASE
	return clampi(n, STAT_MIN, STAT_MAX)


## Tempo-Multiplikator (wirkt auf Höchst-/Zieltempo). Basis 3 → exakt 1.0.
static func speed_mult(stats: Variant) -> float:
	return _mult(stats, "speed", SPEED_STEP, SPEED_MULT_RANGE)


## Lenk-Multiplikator (wirkt auf die Lenkrate). Basis 3 → exakt 1.0.
static func handling_mult(stats: Variant) -> float:
	return _mult(stats, "handling", HANDLING_STEP, HANDLING_MULT_RANGE)


## Beschleunigungs-Multiplikator (Anfahren/Rampe). Basis 3 → exakt 1.0.
static func boost_mult(stats: Variant) -> float:
	return _mult(stats, "boost", BOOST_STEP, BOOST_MULT_RANGE)


## Alle drei auf einmal — DER Contract für Host/Spiele:
## {"speed": f, "handling": f, "boost": f}.
static func multipliers(stats: Variant) -> Dictionary:
	return {
		"speed": speed_mult(stats),
		"handling": handling_mult(stats),
		"boost": boost_mult(stats),
	}


## Balkenzeile für die Pregame-Auto-Zeile: 1..10 → „▮▮▯▯▯“ (5 Slots,
## gefüllt = ceil(stat/2), min. 1 — auch ein Gurkenauto zeigt einen Balken).
static func bars(value: Variant) -> String:
	var filled := clampi(int(ceil(float(clamp_stat(value)) / 2.0)), 1, BAR_SLOTS)
	return BAR_FULL.repeat(filled) + BAR_EMPTY.repeat(BAR_SLOTS - filled)


static func _mult(stats: Variant, key: String, step: float, bounds: Vector2) -> float:
	var raw: Variant = (stats as Dictionary).get(key) if stats is Dictionary else null
	var value := clamp_stat(raw)
	return clampf(1.0 + float(value - STAT_BASE) * step, bounds.x, bounds.y)
