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
## Host-Callback: on_coin_chunk.call(amount: int) — coin-würdiger Teil-Score
## (z. B. GvZ pro gewonnenem Level). Optional; ohne Meldung wird die Coin-Row
## wie bisher einmal auf den Session-Score angewandt.
var on_coin_chunk: Callable = Callable()
## FERTIG-1 (EVAL Rang 12): aktiver Runden-Modifier (ModifierEngine.
## launch_params — {type, coin_mult?, score_mult?, xp_mult?, energy_free?,
## gluecksrolle?}) oder {} ohne Event. Alle Effekte wirken ZENTRAL im
## Host/Award; Spiele LESEN hier nur, wenn sie zusätzlich reagieren wollen.
var modifier: Dictionary = {}
## W13B/DRIVE (Doc G §6): das AUSGEWÄHLTE Autohaus-Auto für Fahr-Spiele
## (FrameworkLogic.CAR_GAMES) — CarDef-Kopie + {"farbe": hex, "mults":
## {"speed", "handling", "boost"}} aus CarStatsLogic. {} bei Nicht-Fahr-
## Spielen oder ohne GameState (Tests): Spiele MÜSSEN ohne auskommen
## (Neutralbasis = alle Multiplikatoren 1.0).
var car: Dictionary = {}
## Host-Callback für strike() — liefert {"strikes": int, "teleport": bool}.
var on_strike: Callable = Callable()

## Fallback-Zähler, wenn kein Host verdrahtet ist (reine Logik-Tests).
var _local_strikes := 0


## Deterministischer mulberry32-RNG; ohne Argument mit dem Lauf-Seed.
func rng(seed_value: int = -1) -> GoobyRng:
	return GoobyRng.new(run_seed if seed_value < 0 else seed_value)


func report_score(total: int, delta := 0) -> void:
	if on_score.is_valid():
		on_score.call(total, delta)


func report_end(result: Dictionary) -> void:
	if on_end.is_valid():
		on_end.call(result)


## Teil-Score als eigene Coin-Einheit melden (E10-P1-3: GvZ-Award pro Level).
func report_coin_chunk(amount: int) -> void:
	if on_coin_chunk.is_valid():
		on_coin_chunk.call(amount)


## POLISH-E/W13B: einen Strike melden (z. B. Crash im City Drive). Der Host
## zählt über MinigameFrameworkLogic.apply_strike und beendet die Runde AB
## dem 3. Strike mit der Teleport-Cutscene (Award läuft regulär über den
## aktuellen Score). Rückgabe wie apply_strike: {"strikes": n, "teleport":
## bool} — Spiele dürfen darauf reagieren (Grimasse, Banner), MÜSSEN aber
## nichts tun: das Rundenende gehört dem Host.
func strike() -> Dictionary:
	if on_strike.is_valid():
		return on_strike.call()
	var result := MinigameFrameworkLogic.apply_strike(_local_strikes)
	_local_strikes = int(result["strikes"])
	return result
