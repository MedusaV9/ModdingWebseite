class_name GobnomProgress
extends RefCounted
## Fortschritt von GOB NOM als additiver GameState-Slice "gobnom"
## (W1d-Slice-Registry, Muster = GvzProgress). ZWEI Tracks: Kampagne (15)
## und Coop (10, Doc G §5.4); Schlüssel sind "c<id>" bzw. "n<id>".
## Sterne 0–3 = eingesammelte NUTELLA-Gläser des besten Laufs (Doc G §5.2
## "Nutella-Glas einsammeln (Stern-Äquivalent)"). Best-Scores +
## Erst-Abschluss-Flags für den First-Clear-Bonus.
## Alle Zugriffe über Duck-Typing (`gs` = /root/GameState ODER Test-Double).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "gobnom"
const CAMPAIGN_COUNT := 15
const COOP_COUNT := 10
const TRACK_CAMPAIGN := "campaign"
const TRACK_COOP := "coop"

static var _registered := false


## Slice registrieren (idempotent; nachträglich heilt normalize beim Load).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"v": 1, "stars": {}, "best": {}, "cleared": {}}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten.
static func normalize_slice(raw: Variant) -> Dictionary:
	var gobnom: Dictionary = raw if raw is Dictionary else default_slice()
	gobnom["v"] = maxi(1, int(_num(gobnom.get("v"), 1.0)))
	for key: String in ["stars", "best", "cleared"]:
		if not (gobnom.get(key) is Dictionary):
			gobnom[key] = {}
	return gobnom


## Slice-Schlüssel eines Levels: Kampagne "c<id>", Coop "n<id>".
static func level_key(track: String, level_id: int) -> String:
	return "%s%d" % ["n" if track == TRACK_COOP else "c", level_id]


static func level_count(track: String) -> int:
	return COOP_COUNT if track == TRACK_COOP else CAMPAIGN_COUNT


## Gesamt-Score eines Siegs (Coin-Row-würdig): Basis + Glas-Bonus +
## Level-Bonus + einmaliger Erst-Abschluss-Bonus (alles aus der Balance).
static func final_score(level_id: int, jars: int, first_clear: bool, balance: Dictionary) -> int:
	var score: Dictionary = balance.get("score", {})
	var total := int(score.get("win_base", 40))
	total += jars * int(score.get("jar_bonus", 25))
	total += level_id * int(score.get("level_bonus", 4))
	if first_clear:
		total += int(score.get("first_clear_bonus", 50))
	return total


static func level_stars(gs: Object, track: String, level_id: int) -> int:
	if gs == null:
		return 0
	var key := level_key(track, level_id)
	return int(_num(gs.get_value("%s.stars.%s" % [SLICE_ID, key], 0)))


static func is_cleared(gs: Object, track: String, level_id: int) -> bool:
	if gs == null:
		return false
	var key := level_key(track, level_id)
	return bool(gs.get_value("%s.cleared.%s" % [SLICE_ID, key], false))


## Höchstes spielbares Level eines Tracks: alles bis zum ersten noch nicht
## abgeschlossenen Level (L1/CN1 sind immer offen).
static func max_unlocked(gs: Object, track: String) -> int:
	for id in range(1, level_count(track) + 1):
		if not is_cleared(gs, track, id):
			return id
	return level_count(track)


static func total_stars(gs: Object, track: String) -> int:
	var total := 0
	for id in range(1, level_count(track) + 1):
		total += level_stars(gs, track, id)
	return total


## Anzahl WIRKLICH abgeschlossener Level eines Tracks (max_unlocked deckelt).
static func cleared_count(gs: Object, track: String) -> int:
	var total := 0
	for id in range(1, level_count(track) + 1):
		if is_cleared(gs, track, id):
			total += 1
	return total


## Sieg verbuchen. Liefert {first_clear, new_best, stars_before}.
## Ohne GameState (Pure-Tests/Host-lose Läufe) nur das Ergebnis-Dict.
static func record_win(
	gs: Object, track: String, level_id: int, stars: int, score: int
) -> Dictionary:
	var first_clear := not is_cleared(gs, track, level_id)
	var stars_before := level_stars(gs, track, level_id)
	var key := level_key(track, level_id)
	var best_before := 0
	if gs != null:
		best_before = int(_num(gs.get_value("%s.best.%s" % [SLICE_ID, key], 0)))
	var new_best := score > best_before
	if gs != null:
		gs.update(
			func(state: Dictionary) -> void:
				var slice: Dictionary = state.get(SLICE_ID, default_slice())
				slice["cleared"][key] = true
				slice["stars"][key] = maxi(stars_before, stars)
				slice["best"][key] = maxi(best_before, score)
				state[SLICE_ID] = slice
		)
		gs.notify_slice_changed(SLICE_ID)
	return {"first_clear": first_clear, "new_best": new_best, "stars_before": stars_before}


## Nur für Tests: Registry-Status zurücksetzen.
static func reset_for_tests() -> void:
	_registered = false


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
