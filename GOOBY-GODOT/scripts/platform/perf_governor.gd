class_name PerfGovernor
extends RefCounted
## RW-7 — Notbremse (Doc §4.2 „Auto“-Ablauf, Punkt 4): erkennt DAUERHAFT
## einbrechende Bildrate und meldet „eine Stufe senken“. Pure Logik, wird
## vom `QualityService` pro Frame mit `delta` gefüttert; komplett headless
## testbar (Zeit kommt als Parameter herein).
##
## Regeln:
## - Ein Frame gilt als „schlecht“, wenn die momentane Rate unter
##   BUDGET_ANTEIL × Ziel-FPS liegt.
## - Erst wenn schlechte Frames SLOW_S Sekunden am Stück dominieren
##   (kurze gute Frames setzen NICHT sofort zurück, gute GOOD_RESET_S
##   Sekunden schon), feuert `should_step_down()` einmal.
## - Danach Hysterese: COOLDOWN_S Sekunden keine weitere Herabstufung
##   (Doc §3.7: „frühestens nach 60 s … sonst pulsiert die Qualität“).

const BUDGET_ANTEIL := 0.75
const SLOW_S := 5.0
const GOOD_RESET_S := 2.0
const COOLDOWN_S := 60.0
## Frames länger als das gelten als Ladehänger und zählen nicht (sonst
## würde ein einzelner Szenenwechsel die Qualität senken).
const HITCH_S := 0.5

var target_fps := 60.0

var _slow_accum := 0.0
var _good_accum := 0.0
var _cooldown_left := 0.0
var _pending := false


func _init(fps: float = 60.0) -> void:
	target_fps = maxf(1.0, fps)


## Pro Frame füttern. delta in Sekunden.
func feed(delta: float) -> void:
	if delta <= 0.0 or delta >= HITCH_S:
		return
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
		return
	var fps := 1.0 / delta
	if fps < target_fps * BUDGET_ANTEIL:
		_slow_accum += delta
		_good_accum = 0.0
		if _slow_accum >= SLOW_S:
			_pending = true
	else:
		_good_accum += delta
		if _good_accum >= GOOD_RESET_S:
			_slow_accum = 0.0
			_good_accum = 0.0


## true genau EINMAL, wenn die Bremse ziehen soll; setzt Cooldown.
func should_step_down() -> bool:
	if not _pending:
		return false
	_pending = false
	_slow_accum = 0.0
	_good_accum = 0.0
	_cooldown_left = COOLDOWN_S
	return true


## Neues Ziel (z. B. nach Herabstufung) — Messfenster sauber neu starten.
func retarget(fps: float) -> void:
	target_fps = maxf(1.0, fps)
	_slow_accum = 0.0
	_good_accum = 0.0
	_pending = false


func is_cooling_down() -> bool:
	return _cooldown_left > 0.0
