class_name MemoryMatchLogic
extends RefCounted
## Memory (memoryMatch) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/memoryMatch.logic.js (§C6.1 #5). 4×4 mit 8 Paaren,
## ab Level 6 (MINIGAME.MEMORY_BIG_LAYOUT_LEVEL) 4×6 mit 12 Paaren; Score =
## 20 − Fehlgriffe + Zeitbonus (0–8) + 20 Board-Bonus (V4/G71b: in JEDEM
## Modus), Deckel 48. Kein Fail-State. Coin-Zeile: /2, 5..24, Ziel 40.

## Web MINIGAME.MEMORY_BIG_LAYOUT_LEVEL (data/constants.js §C1.5).
const BIG_LAYOUT_LEVEL := 6

## Bindende §C6.1-#5-Zahlen + G8-Tuning.
const MEMORY := {
	"SCORE_BASE": 20,
	"TIME_BONUS_MAX": 8,
	"TIME_BONUS_STEP_SEC": 5.0,
	"PAR_SEC_SMALL": 48.0,
	"PAR_SEC_BIG": 85.0,
	"CARD_W": 0.82,
	"CARD_H": 1.0,
	"SPACING_X": 0.93,
	"SPACING_Y": 1.12,
	"REVEAL_SEC": 0.85,
	"FLIP_SEC": 0.28,
	"PEEK_EARN_MATCHES": 3,
	"PEEK_SEC": 1.0,
	"PREVIEW_SPEED_MULT": 1.0,
	"WINDOW_MULT": 1.0,
	"RAMP_FLOOR_STEP": 0,
	"CLEAR_BONUS": 20,
	"ENDLESS": false,
	"ENDLESS_MISS_FLIPS": 12,
}

## Kleines 4×4-Board (8 Paare) und großes 4×6-Board (12 Paare, Hochkant).
const SMALL := {"cols": 4, "rows": 4, "pairs": 8}
const BIG := {"cols": 4, "rows": 6, "pairs": 12}

const MEMORY_DIFFICULTY := {
	"easy": {"previewSpeed": 0.85, "window": 1.25, "rampFloor": 0, "bonus": 20, "endless": false},
	"normal": {"previewSpeed": 1.0, "window": 1.0, "rampFloor": 0, "bonus": 20, "endless": false},
	"hard": {"previewSpeed": 1.15, "window": 0.8, "rampFloor": -1, "bonus": 20, "endless": false},
	"endless": {"previewSpeed": 1.15, "window": 0.8, "rampFloor": -1, "bonus": 20, "endless": true},
}

## Kartenmotive (Kenney-Food-Kit-Keys) — die ersten 8 bedienen das 4×4-Board.
const FACE_KEYS: Array[String] = [
	"carrot",
	"apple",
	"banana",
	"cheese",
	"watermelon",
	"donut-sprinkles",
	"cupcake",
	"burger",
	"ice-cream",
	"pizza",
	"cake",
	"strawberry",
]


## §G5 Sequenz-/Puzzle-Difficulty; `normal` liefert die Basistabelle.
static func apply_difficulty(tune: Dictionary = MEMORY, mode := "normal") -> Dictionary:
	var id := mode if MEMORY_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = MEMORY_DIFFICULTY[id]
	var out := tune.duplicate()
	out["REVEAL_SEC"] = maxf(0.35, float(tune["REVEAL_SEC"]) * float(row["window"]))
	out["PEEK_SEC"] = maxf(0.35, float(tune["PEEK_SEC"]) * float(row["window"]))
	out["FLIP_SEC"] = float(tune["FLIP_SEC"]) / float(row["previewSpeed"])
	out["PREVIEW_SPEED_MULT"] = float(row["previewSpeed"])
	out["WINDOW_MULT"] = float(row["window"])
	out["RAMP_FLOOR_STEP"] = int(row["rampFloor"])
	out["CLEAR_BONUS"] = int(row["bonus"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## Grid für ein Gooby-Level (§C1.5: 4×6 ab Level 6, sonst 4×4).
static func layout_for_level(level: int) -> Dictionary:
	return BIG if level >= BIG_LAYOUT_LEVEL else SMALL


## Gemischtes Deck aus Paar-Ids (Fisher-Yates mit dem geseedeten RNG).
static func build_deck(pairs: int, rng: GoobyRng) -> Array[int]:
	var deck: Array[int] = []
	for i in pairs:
		deck.append(i)
		deck.append(i)
	for i in range(deck.size() - 1, 0, -1):
		var j := int(floor(rng.next() * float(i + 1)))
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck


## Zeitbonus 0–8: voll bis zum Par, −1 je 5 s darüber.
static func time_bonus(elapsed: float, layout: Dictionary) -> int:
	var par := (
		float(MEMORY["PAR_SEC_BIG"])
		if int(layout["pairs"]) > int(SMALL["pairs"])
		else float(MEMORY["PAR_SEC_SMALL"])
	)
	var over := maxf(0.0, elapsed - par)
	var bonus := (
		int(MEMORY["TIME_BONUS_MAX"]) - int(ceil(over / float(MEMORY["TIME_BONUS_STEP_SEC"])))
	)
	return maxi(0, mini(int(MEMORY["TIME_BONUS_MAX"]), bonus))


## Endstand: 20 − Fehlgriffe + Zeitbonus + Board-Bonus, bei 0 gefloort.
static func memory_score(
	misses: int, elapsed: float, layout: Dictionary, tune: Dictionary = MEMORY
) -> int:
	return maxi(
		0,
		(
			int(tune["SCORE_BASE"])
			- misses
			+ time_bonus(elapsed, layout)
			+ int(tune.get("CLEAR_BONUS", 0))
		)
	)


## Zwei aufgedeckte Karten passen, wenn beide dieselbe Paar-Id tragen.
static func is_match(a: int, b: int) -> bool:
	return a == b


## Saubere-Treffer-Serie fortschreiben, die den einmaligen Spick-Blick zahlt.
static func advance_peek_progress(state: Dictionary, matched: bool) -> Dictionary:
	var clean_matches := int(state["cleanMatches"]) + 1 if matched else 0
	var earned := not bool(state["peekUsed"]) and clean_matches >= int(MEMORY["PEEK_EARN_MATCHES"])
	return {
		"cleanMatches": clean_matches,
		"peekReady": bool(state["peekReady"]) or earned,
		"peekUsed": bool(state["peekUsed"]),
	}


## Ein Spick-Blick pro Runde, und nur nachdem er verdient wurde.
static func can_use_peek(state: Dictionary) -> bool:
	return bool(state["peekReady"]) and not bool(state["peekUsed"])


## Synchrone Aufdeck-Zulassung — schließt das Doppel-Flip-Rennen.
static func can_flip_card(state: Dictionary) -> bool:
	return (
		state["phase"] == "play"
		and not bool(state["peeking"])
		and int(state["pickedCount"]) < 2
		and state["cardState"] == "down"
	)


## Zentrierte Grid-Ausmaße (Layout-Audit für schmale Viewports).
static func grid_extents(layout: Dictionary) -> Dictionary:
	return {
		"width": (int(layout["cols"]) - 1) * float(MEMORY["SPACING_X"]) + float(MEMORY["CARD_W"]),
		"height": (int(layout["rows"]) - 1) * float(MEMORY["SPACING_Y"]) + float(MEMORY["CARD_H"]),
	}


## §G5.4 Endlos: Boards ketten, bis 12 Fehlgriffe zusammengekommen sind.
static func endless_should_end(misses: int, tune: Dictionary = MEMORY) -> bool:
	return bool(tune["ENDLESS"]) and misses >= int(tune["ENDLESS_MISS_FLIPS"])


## Deterministische Bot-Zertifizierung (zahlengleich zum Web-Modell).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(MEMORY, mode)
	var rng := GoobyRng.new(seed_value)
	var layout := BIG
	var recall_fail := 0.08
	if mode == "easy":
		recall_fail = 0.04
	elif mode == "hard" or mode == "endless":
		recall_fail = 0.12
	var misses := 0
	for _i in int(layout["pairs"]):
		if rng.next() < recall_fail:
			misses += 1
	var pace := 1.05
	if mode == "easy":
		pace = 1.2
	elif mode == "hard":
		pace = 0.92
	var elapsed := float(int(layout["pairs"])) * pace
	var raw_tune := tune.duplicate()
	raw_tune["CLEAR_BONUS"] = 0
	return {
		"seed": seed_value,
		"mode": mode,
		"score": memory_score(misses, elapsed, layout, tune),
		"rawScore": memory_score(misses, elapsed, layout, raw_tune),
		"misses": misses,
		"elapsed": elapsed,
	}
