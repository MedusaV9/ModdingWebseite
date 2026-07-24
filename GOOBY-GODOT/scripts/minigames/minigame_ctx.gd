class_name MinigameCtx
extends RefCounted
## Kontext, den der Host jedem Minigame in setup(ctx) übergibt (Vertrag für
## alle Spiele inkl. W3b GvZ — Details im Handoff W2d-framework-api.md).
## Spiele lesen difficulty/orientation, ziehen ihren RNG über rng() und
## melden Punkte/Ende NUR über report_score()/report_end() zurück — nie
## direkt an GameState (das Award-Buchen gehört dem Host).

## Registry-Id des Spiels (z. B. "teaParty").
var game_id := ""
## Effektive Difficulty des Laufs: easy|normal|hard|endless.
var difficulty := "normal"
## Effektive Orientierung des Laufs: portrait|landscape.
var orientation := "portrait"
## Seed des Laufs (Host würfelt; Tests/Replays setzen ihn deterministisch).
var run_seed := 1
## JuiceKit des Hosts (hit_freeze/shake/bloom_pulse/slowmo/float_text).
var juice: JuiceKit
## Host-Callback: on_score.call(total: int, delta: int).
var on_score: Callable = Callable()
## Host-Callback: on_end.call(result: Dictionary) — result MUSS "score" haben.
var on_end: Callable = Callable()


## Deterministischer mulberry32-RNG; ohne Argument mit dem Lauf-Seed.
func rng(seed_value: int = -1) -> GoobyRng:
	return GoobyRng.new(run_seed if seed_value < 0 else seed_value)


func report_score(total: int, delta := 0) -> void:
	if on_score.is_valid():
		on_score.call(total, delta)


func report_end(result: Dictionary) -> void:
	if on_end.is_valid():
		on_end.call(result)
