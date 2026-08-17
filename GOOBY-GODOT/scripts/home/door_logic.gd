class_name DoorLogic
extends RefCounted
## Tür-Statemaschine (W2a HOUSE) — PURE, headless-testbar (Doc A §5 + Doc F).
## Die Szenen-Seite (door_transition.gd) füttert Events; hier lebt NUR die
## Logik: Gag-Würfel (~12 %, nie 2× hintereinander, nur wenn Türen animiert),
## Tap-Mash-Minigame (5–8 Taps mit Decay) und Skip-Regeln.

enum State { IDLE, OPENING, WALKING, STUCK, POPPING, TRAVEL }

const STUCK_CHANCE := 0.12
const TAPS_MIN := 5
const TAPS_MAX := 8
## Mash-Druck-Verfall pro Sekunde (in Taps) — mashen, nicht einmal tippen!
const MASH_DECAY_PER_SEC := 0.8
## W4-P3 POLISH-7: Widerstand steigt — der Verfall skaliert mit dem
## Fortschritt (bei vollem Balken verfällt der Druck (1+GAIN)-mal so
## schnell). Die letzten Taps müssen also schneller kommen.
const RESISTANCE_GAIN := 1.6

var state := State.IDLE
var animated := true
var will_stick := false
var taps_required := 0

var _mash := 0.0


## `stuck_roll`/`taps_roll` sind injizierte Zufallswerte 0..1 (Tests: fix).
func _init(
	doors_animated: bool, previous_was_stuck: bool, stuck_roll := 1.0, taps_roll := 0.0
) -> void:
	animated = doors_animated
	will_stick = animated and not previous_was_stuck and stuck_roll < STUCK_CHANCE
	taps_required = TAPS_MIN + clampi(int(taps_roll * (TAPS_MAX - TAPS_MIN + 1)), 0, 3)


## Reise beginnt. Ohne Animation (Settings-Toggle) → sofort TRAVEL (Cut).
func begin() -> int:
	if state != State.IDLE:
		return state
	state = State.OPENING if animated else State.TRAVEL
	return state


## Türblatt ist offen → Gooby läuft los.
func door_opened() -> int:
	if state == State.OPENING:
		state = State.WALKING
	return state


## Gooby ist am Türrahmen → Gag oder direkt durch.
func reached_door() -> int:
	if state == State.WALKING:
		state = State.STUCK if will_stick else State.TRAVEL
	return state


## Ein Mash-Tap während STUCK. Bei genug Druck → POPPING (durchploppen).
func tap_mash() -> int:
	if state != State.STUCK:
		return state
	_mash += 1.0
	if _mash >= float(taps_required):
		state = State.POPPING
	return state


## Mash-Druck verfällt mit der Zeit (Szene ruft das pro Frame).
## Der Verfall wächst mit dem Fortschritt (Widerstandskurve, POLISH-7).
func mash_decay(delta: float) -> void:
	if state == State.STUCK:
		_mash = maxf(0.0, _mash - decay_rate() * delta)


## Aktueller Verfall in Taps/s (für Tests und UI-Feedback).
func decay_rate() -> float:
	return MASH_DECAY_PER_SEC * (1.0 + RESISTANCE_GAIN * mash_ratio())


## Fortschritt 0..1 für den Mash-Balken.
func mash_ratio() -> float:
	if taps_required <= 0:
		return 0.0
	return clampf(_mash / float(taps_required), 0.0, 1.0)


## True, wenn der NÄCHSTE Tap durchploppen würde (Squash-Telegraphie).
func ist_letzter_tap() -> bool:
	return state == State.STUCK and _mash >= float(taps_required) - 1.0


## Plopp-Animation fertig → weiterreisen.
func pop_finished() -> int:
	if state == State.POPPING:
		state = State.TRAVEL
	return state


## Skip per Tap (Doc A §5 Punkt 4) — NICHT während des Tap-Mash
## (da ist Tippen der Weg nach draußen) und nicht nach TRAVEL.
func skip() -> int:
	if state in [State.OPENING, State.WALKING, State.POPPING]:
		state = State.TRAVEL
	return state


func is_traveling() -> bool:
	return state == State.TRAVEL
