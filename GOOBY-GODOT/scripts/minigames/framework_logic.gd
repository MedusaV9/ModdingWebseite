class_name MinigameFrameworkLogic
extends RefCounted
## Pure Difficulty-/Coin-/Orientierungs-Policy — zahlengleicher Port von
## GOOBY/src/minigames/framework.logic.js (§G5/§E0.1-2/POLISH-E/V4-ORIENT).
## Goldwerte: tests/expected/framework.json (via tools/cross_check.mjs DIREKT
## aus der Web-Logik erzeugt); Beweis: tests/unit/test_mg_framework_logic.gd.
##
## ABWEICHUNG zum Web (dokumentiert): die Save-Reader (difficulty_slice_of,
## endless_unlocked, best_for_mode) lesen das v5-Schema — Boards liegen unter
## `minigames.legacy.*` (save_schema.gd), Level unter `progression.level`,
## die Schwierigkeitswahl unter `minigames.difficulty.<id>` (additiver Key,
## merge_defaults lässt ihn überleben).

## §G5.2 — die vier Modi; `normal` ist Default (Live-Zahlen).
const DIFFICULTY_MODES: Array[String] = ["easy", "normal", "hard", "endless"]
## §G5.2 Coin-Multiplikatoren (geteiltes Orakel Framework ↔ Award-Pfad).
const DIFFICULTY_COIN_MULT := {"easy": 0.7, "normal": 1.0, "hard": 1.3}
## §G5.2 — Endlos zahlt pauschal 5 c pro Lauf (Tages-×2 wirkt danach).
const ENDLESS_FLAT_COINS := 5
## §G5.5 — ENDLOS-Pill braucht beaten[id].hard UND Level >= 10.
const ENDLESS_MIN_LEVEL := 10
## §G5.1 — cityDrive (Trip-Semantik) + goobyWelt (Chill-Special) ohne Modi.
const DIFFICULTY_EXCLUDED_GAMES: Array[String] = ["cityDrive", "goobyWelt"]
## POLISH-E — Strikes bis zum Teleport (Spiegel von DRIVE.CRASHES_FOR_TOW).
const STRIKES_FOR_TELEPORT := 3


## JS Math.round rundet .5 Richtung +unendlich; für x >= 0 == floor(x + 0.5).
static func js_round(x: float) -> int:
	return int(floor(x + 0.5))


static func normalize_difficulty(mode: Variant) -> String:
	if mode is String and DIFFICULTY_MODES.has(mode):
		return mode
	return "normal"


## Ist das Difficulty-System für dieses Spiel überhaupt aktiv (§G5.1)?
static func difficulty_enabled(game_id: String, meta: Dictionary = {}) -> bool:
	if DIFFICULTY_EXCLUDED_GAMES.has(game_id):
		return false
	if meta.get("dev", false) == true:
		return false
	return true


## Die Difficulty, mit der ein Launch WIRKLICH läuft (§G5.1/§G5.7-1):
## Trip-/Travel-Launches (params.mode gesetzt) und exkludierte Spiele sind
## immer 'normal'; sonst wird params.difficulty normalisiert.
static func effective_difficulty(
	game_id: String, params: Dictionary = {}, meta: Dictionary = {}
) -> String:
	if params.get("mode") != null:
		return "normal"
	if not difficulty_enabled(game_id, meta):
		return "normal"
	return normalize_difficulty(params.get("difficulty"))


## §G5.2 Basis-Coin-Mathe (VOR Tages-×2): min(max, max(min,
## round(rowClamp(score) × mult))). Endlos nutzt das NICHT (flat override).
static func apply_difficulty_coin_base(coin_table: Dictionary, score: Variant, mode: String) -> int:
	var s := maxi(0, int(floor(_num(score))))
	var divisor := _num(coin_table.get("divisor", 1), 1.0)
	var row_min := int(_num(coin_table.get("min", 0)))
	var row_max := int(_num(coin_table.get("max", 0)))
	var row_clamp := mini(row_max, maxi(row_min, int(floor(float(s) / divisor))))
	var mult := _num(DIFFICULTY_COIN_MULT.get(mode, 1.0), 1.0)
	return mini(row_max, maxi(row_min, js_round(float(row_clamp) * mult)))


## Defensiver v5-Slice-Reader (§G5.5) — hostile/fehlende Container werfen nie.
static func difficulty_slice_of(state: Dictionary, game_id: String) -> Dictionary:
	var mg := _dict(state.get("minigames"))
	var legacy := _dict(mg.get("legacy"))
	var sel_raw: Variant = _dict(mg.get("difficulty")).get(game_id)
	var selected := "normal"
	if sel_raw is String and (sel_raw == "easy" or sel_raw == "hard"):
		selected = sel_raw
	return {
		"selected": selected,
		"beaten": _dict(_dict(legacy.get("beaten")).get(game_id)),
		"bestByDiff": _dict(_dict(legacy.get("bestByDiff")).get(game_id)),
		"best": maxi(0, int(floor(_num(_dict(legacy.get("best")).get(game_id))))),
		"endlessBest": maxi(0, int(floor(_num(_dict(legacy.get("endlessBest")).get(game_id))))),
	}


## §G5.5 Endlos-Lock: beaten[id].hard == true UND Level >= 10.
static func endless_unlocked(state: Dictionary, game_id: String) -> bool:
	var level := maxi(1, int(floor(_num(_dict(state.get("progression")).get("level"), 1.0))))
	var beaten: Dictionary = difficulty_slice_of(state, game_id)["beaten"]
	return beaten.get("hard", false) == true and level >= ENDLESS_MIN_LEVEL


## Per-Modus-Best für Results/Pregame (§G5.5: best = Mittel-Board).
static func best_for_mode(state: Dictionary, game_id: String, mode: String) -> int:
	var slice := difficulty_slice_of(state, game_id)
	if mode == "endless":
		return slice["endlessBest"]
	if mode == "easy" or mode == "hard":
		return maxi(0, int(floor(_num((slice["bestByDiff"] as Dictionary).get(mode)))))
	return slice["best"]


## POLISH-E Strike-Entscheidung: Zähler hoch, Teleport AB dem 3. Strike.
static func apply_strike(strikes: Variant) -> Dictionary:
	var n := maxi(0, int(floor(_num(strikes)))) + 1
	return {"strikes": n, "teleport": n >= STRIKES_FOR_TELEPORT}


## Alles außer dem Literal 'landscape' bedeutet Hochkant (CSS-Baseline).
static func normalize_orientation(value: Variant) -> String:
	return "landscape" if (value is String and value == "landscape") else "portrait"


## V4/ORIENT: Rotate-Gate NUR für Landscape-Spiele in Hochkant-Viewports.
static func should_show_rotate_gate(orientation_flag: Variant, viewport_is_landscape: bool) -> bool:
	if normalize_orientation(orientation_flag) != "landscape":
		return false
	return viewport_is_landscape != true


## V4/ORIENT: Landscape-Spiele entsperren die Rotation, alles andere lockt
## Hochkant; exit() stellt immer 'portrait' (App-Baseline) wieder her.
static func orientation_lock_for(game_orientation: Variant) -> String:
	return "unlock" if normalize_orientation(game_orientation) == "landscape" else "portrait"


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
