class_name OnboardingGuideLogic
extends RefCounted
## PURE Logik des handlungsgeführten Onboardings (REST-2, Port der Web-
## Schrittfolge aus GOOBY/src/ui/onboarding.js §D2 — dort: welcome/pet/feed/
## wash/hudTour/minigame/shopHint/teaser): Schritt-Katalog, Baseline-
## Schnappschuss und Erfüllungs-Checks laufen komplett über die VORHANDENEN
## Save-Zähler (achievements.counters, economy, minigames.plays, stickers) —
## kein eigener Event-Bus. Headless testbar; die UI (onboarding_guide.gd)
## reicht State und Slice herein.
##
## Save (ADDITIV im bestehenden `onboarding`-Dict, KEIN Version-Bump):
##   onboarding.guide = {"done", "skipped", "step", "base"}
## `base` friert die Zähler beim Schritt-Eintritt ein — „TU es“-Schritte
## gelten erst, wenn seither wirklich gehandelt wurde.

## Schrittfolge der ersten Viertelstunde. art: "manuell" = Weiter-Knopf,
## "auto" = erfüllt sich durch echtes Tun (Erfolgserlebnis inklusive).
const STEPS: Array[Dictionary] = [
	{"id": "ankunft", "art": "manuell"},
	{"id": "streicheln", "art": "auto"},
	{"id": "fuettern", "art": "auto"},
	{"id": "waschen", "art": "auto"},
	{"id": "muenzen", "art": "auto"},
	{"id": "minispiel", "art": "auto"},
	{"id": "moebel", "art": "auto"},
	{"id": "sticker", "art": "auto"},
	{"id": "ausblick", "art": "manuell"},
]

## Frische-Heuristik: nur wer wirklich noch am Anfang steht, bekommt die
## Tour — Bestands-Spielstände werden still als erledigt markiert.
const FRISCH_MAX_LEVEL := 2
const FRISCH_MAX_EARNED := 150
const FRISCH_MAX_PLAYS := 3


static func default_slice() -> Dictionary:
	return {"done": false, "skipped": false, "step": 0, "base": {}}


static func slice_of(state: Dictionary) -> Dictionary:
	var onboarding: Variant = state.get("onboarding", {})
	if onboarding is Dictionary and onboarding.get("guide") is Dictionary:
		return onboarding["guide"]
	return default_slice()


static func step_count() -> int:
	return STEPS.size()


static func step_at(index: int) -> Dictionary:
	if index < 0 or index >= STEPS.size():
		return {}
	return STEPS[index]


## Läuft die Tour für diesen Spielstand an? (Erst-Onboarding fertig, Tour
## weder erledigt noch übersprungen, Spielstand frisch genug.)
static func should_start(state: Dictionary) -> bool:
	var onboarding: Variant = state.get("onboarding", {})
	if not (onboarding is Dictionary):
		return false
	var flow_done: Variant = (onboarding as Dictionary).get("done")
	if not (flow_done is bool) or not flow_done:
		return false
	var guide := slice_of(state)
	if bool(guide.get("done", false)) or bool(guide.get("skipped", false)):
		return false
	return is_fresh(state)


static func is_fresh(state: Dictionary) -> bool:
	var level := int(_num(state.get("progression", {}).get("level"), 1.0))
	if level > FRISCH_MAX_LEVEL:
		return false
	if _econ(state, "coinsEarned") > FRISCH_MAX_EARNED:
		return false
	return _plays_sum(state) <= FRISCH_MAX_PLAYS


## Zähler-Schnappschuss beim Schritt-Eintritt.
static func snapshot(state: Dictionary) -> Dictionary:
	return {
		"pets": _counter(state, "petsToday"),
		"feeds": _counter(state, "feeds"),
		"washes": _counter(state, "washes"),
		"earned": _econ(state, "coinsEarned"),
		"spent": _econ(state, "coinsSpent"),
		"plays": _plays_sum(state),
		"sticker": sticker_count(state),
	}


## Ist der Schritt gegen seine Baseline erfüllt? Manuelle Schritte nie
## (die bestätigt der Weiter-Knopf).
static func satisfied(step_id: String, base: Dictionary, state: Dictionary) -> bool:
	match step_id:
		"streicheln":
			# petsToday ist tagesgebunden (Reset über petsDay) — jede
			# Veränderung mit Wert >= 1 ist ein echter Streichler seither.
			var pets := _counter(state, "petsToday")
			return pets >= 1 and pets != int(_num(base.get("pets"), 0.0))
		"fuettern":
			return _counter(state, "feeds") > int(_num(base.get("feeds"), 0.0))
		"waschen":
			return _counter(state, "washes") > int(_num(base.get("washes"), 0.0))
		"muenzen":
			return _econ(state, "coinsEarned") > int(_num(base.get("earned"), 0.0))
		"minispiel":
			return _plays_sum(state) > int(_num(base.get("plays"), 0.0))
		"moebel":
			return _econ(state, "coinsSpent") > int(_num(base.get("spent"), 0.0))
		"sticker":
			return sticker_count(state) > 0
	return false


static func sticker_count(state: Dictionary) -> int:
	var unlocked: Variant = state.get("stickers", {}).get("unlocked")
	return (unlocked as Dictionary).size() if unlocked is Dictionary else 0


static func _counter(state: Dictionary, key: String) -> int:
	return int(_num(state.get("achievements", {}).get("counters", {}).get(key), 0.0))


static func _econ(state: Dictionary, key: String) -> int:
	return int(_num(state.get("economy", {}).get(key), 0.0))


static func _plays_sum(state: Dictionary) -> int:
	var plays: Variant = state.get("minigames", {}).get("plays")
	if not (plays is Dictionary):
		return 0
	var total := 0
	for id: Variant in plays:
		total += int(_num(plays[id], 0.0))
	return total


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback
