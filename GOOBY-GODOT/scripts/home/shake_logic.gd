class_name ShakeLogic
extends RefCounted
## Pure Schüttel-Erkennung (W13B GESCHICHTEN, Doc F §5): Beschleunigungs-
## Samples rein → Eskalationsstufe raus. Kein Input-, Zeit- oder Node-Zugriff
## — der Aufrufer (ShakeSecret) reicht `Input.get_accelerometer()` + dt
## herein, Tests füttern synthetische Sequenzen (deterministisch).
##
## Verfahren (Doc F §5): Gravitations-Anteil per Low-Pass (α=0.1) abziehen;
## Shake-Metrik = gleitendes RMS der Rest-Beschleunigung über 0.5 s;
## Akkumulator `energy` (+RMS·dt, Decay 2.5/s). Stufen: 1 ab energy>4
## (~1 s leichtes Schütteln), 2 ab >9 (~2.5 s kräftig), 3 ab >15 (~4 s wild).
## Ruhe → Abklingen bis Stufe 0. Cooldown-Prüfung (10 min nach Stufe 3)
## ist ebenfalls pure und zeitinjiziert.

const GRAVITY_ALPHA := 0.1
const RMS_WINDOW_S := 0.5
const DECAY_PER_S := 2.5
const STAGE1_ENERGY := 4.0
const STAGE2_ENERGY := 9.0
const STAGE3_ENERGY := 15.0
const COOLDOWN_MS := 10 * 60 * 1000

var energy := 0.0

var _gravity := Vector3.ZERO
var _gravity_primed := false
## Fenster-Samples als (dt, |rest|²) — Vector2 spart eine Dictionary-Alloc.
var _window: Array[Vector2] = []
var _window_dur := 0.0


## Stufe für einen Energiewert (0 = ruhig).
static func stage_for_energy(value: float) -> int:
	if value > STAGE3_ENERGY:
		return 3
	if value > STAGE2_ENERGY:
		return 2
	if value > STAGE1_ENERGY:
		return 1
	return 0


## Ist die 10-min-Sperre nach Stufe 3 abgelaufen? (0 = nie ausgelöst.)
static func cooldown_ready(last_stage3_ms: int, now_ms: int) -> bool:
	return last_stage3_ms <= 0 or now_ms - last_stage3_ms >= COOLDOWN_MS


## Ein Accelerometer-Sample einspeisen; gibt die aktuelle Stufe zurück.
func feed(accel: Vector3, dt: float) -> int:
	if dt <= 0.0:
		return stage()
	if not _gravity_primed:
		# Erstes Sample = Gravitation: ruhig liegende Geräte starten bei 0.
		_gravity = accel
		_gravity_primed = true
	else:
		_gravity = _gravity.lerp(accel, GRAVITY_ALPHA)
	var rest := accel - _gravity
	_window.append(Vector2(dt, rest.length_squared()))
	_window_dur += dt
	while _window.size() > 1 and _window_dur - _window[0].x > RMS_WINDOW_S:
		_window_dur -= _window[0].x
		_window.remove_at(0)
	energy = maxf(0.0, energy + (rms() - DECAY_PER_S) * dt)
	return stage()


## Gleitendes RMS der Rest-Beschleunigung über das 0.5-s-Fenster.
func rms() -> float:
	if _window_dur <= 0.0:
		return 0.0
	var sum := 0.0
	for sample: Vector2 in _window:
		sum += sample.y * sample.x
	return sqrt(sum / _window_dur)


func stage() -> int:
	return stage_for_energy(energy)


## Energie/Fenster leeren (nach Stufe 3 bzw. im Cooldown); der Gravitations-
## Low-Pass bleibt geprimt — Kippen des Geräts löst danach nichts aus.
func reset() -> void:
	energy = 0.0
	_window.clear()
	_window_dur = 0.0
