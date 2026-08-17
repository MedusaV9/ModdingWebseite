class_name GoobyRng
extends RefCounted
## mulberry32 — BIT-identischer Port des Web-Referenz-RNGs aller Minigames
## (GOOBY/src/minigames/framework.js createRng / die .logic.js-Bots).
## Alle Zwischenwerte werden als vorzeichenlose 32-Bit-Muster in Godots
## int64 gehalten; _imul() repliziert JS Math.imul (Multiplikation mod 2^32,
## 16-Bit-Split gegen int64-Überlauf). Division durch 2^32 ist in IEEE-754
## exakt → Werte sind bit-identisch zum Web. Goldwert-Beweis:
## tests/unit/test_mg_rng.gd + tests/expected/rng.json (tools/cross_check.mjs).

const _MASK32 := 0xFFFFFFFF

var _state: int = 0


func _init(seed_value: int = 1) -> void:
	_state = seed_value & _MASK32


## Nächster Wert in [0, 1) — exakt wie das Web-`rng()` (u32 / 2^32 ist in
## IEEE-754 eine exakte Operation, daher bit-identisch zu JS).
func next() -> float:
	return float(next_u32()) / 4294967296.0


## Roher 32-Bit-Kern (`(t ^ (t >>> 14)) >>> 0` im Web) — der Goldwert-Test
## vergleicht HIER (Ganzzahlen), weil Godots Dezimal-Literal-Parser bei
## 17-stelligen Float-Literalen um 1 ulp abweichen kann (Node parst korrekt
## gerundet); die Float-Ausgabe selbst ist trotzdem bit-identisch.
func next_u32() -> int:
	_state = (_state + 0x6D2B79F5) & _MASK32
	var t := _imul(_state ^ (_state >> 15), _state | 1)
	t = (t + _imul(t ^ (t >> 7), t | 61)) & _MASK32
	return t ^ (t >> 14)


## Uniform in [lo, hi) — Komfort für Spiel-Szenen (verbraucht genau 1 next()).
func range_f(lo: float, hi: float) -> float:
	return lo + next() * (hi - lo)


## JS Math.imul-Replikat: (a * b) mod 2^32 auf 32-Bit-Mustern.
static func _imul(a: int, b: int) -> int:
	var ua := a & _MASK32
	var ub := b & _MASK32
	var hi := (((ua >> 16) * ub) & 0xFFFF) << 16
	return (hi + (ua & 0xFFFF) * ub) & _MASK32
