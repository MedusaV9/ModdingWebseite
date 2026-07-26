class_name DevTrigger
extends RefCounted
## RW-7 — Aktivierungs-Logik fürs versteckte Dev-Menü (Doc §5.1, pure):
##
## 1. In der Sprachwahl muss „Deutsch“ BEREITS aktiv sein.
## 2. Innerhalb von 1,5 s dreimal auf den Text „Deutsch“ tippen —
##    ein Sprachwechsel über den Picker zählt NICHT (der Aufrufer meldet
##    nur echte Tipps auf die aktive Deutsch-Option).
## 3. Danach zeigt die UI den Warn-Dialog mit Halte-Bestätigung.
##
## Schutz: Tipps bei falscher Sprache oder verfallene Serien zählen als
## Fehlversuch; nach 3 Fehlversuchen 10 s Cooldown. Komplett headless
## testbar — die Zeit kommt als Parameter herein.

const TAPS_NEEDED := 3
const WINDOW_MS := 1500
const MAX_FAILS := 3
const COOLDOWN_MS := 10_000
## Halte-Dauer der Bestätigung im Warn-Dialog (Doc: 2 s halten).
const HOLD_MS := 2000

var _taps: Array[int] = []
var _fails := 0
var _blocked_until := 0


## Einen Tipp verbuchen. Rückgabe:
## {"triggered": bool, "count": int, "blocked_ms": int (Rest-Cooldown)}.
func register_tap(now_ms: int, language: String) -> Dictionary:
	if now_ms < _blocked_until:
		return {"triggered": false, "count": 0, "blocked_ms": _blocked_until - now_ms}
	if language != "de":
		_fail(now_ms)
		return {"triggered": false, "count": 0, "blocked_ms": _rest(now_ms)}
	var had_stale := false
	var fresh: Array[int] = []
	for t in _taps:
		if now_ms - t <= WINDOW_MS:
			fresh.append(t)
		else:
			had_stale = true
	if had_stale and fresh.is_empty():
		_fail(now_ms)
		if now_ms < _blocked_until:
			return {"triggered": false, "count": 0, "blocked_ms": _blocked_until - now_ms}
	_taps = fresh
	_taps.append(now_ms)
	if _taps.size() >= TAPS_NEEDED:
		_taps.clear()
		_fails = 0
		return {"triggered": true, "count": TAPS_NEEDED, "blocked_ms": 0}
	return {"triggered": false, "count": _taps.size(), "blocked_ms": 0}


func is_blocked(now_ms: int) -> bool:
	return now_ms < _blocked_until


func reset() -> void:
	_taps.clear()
	_fails = 0
	_blocked_until = 0


func _fail(now_ms: int) -> void:
	_taps.clear()
	_fails += 1
	if _fails >= MAX_FAILS:
		_fails = 0
		_blocked_until = now_ms + COOLDOWN_MS


func _rest(now_ms: int) -> int:
	return maxi(0, _blocked_until - now_ms)
