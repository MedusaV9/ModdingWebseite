class_name GvzProgress
extends RefCounted
## Kampagnen-Fortschritt von GvZ als additiver GameState-Slice "gvz"
## (W1d-Slice-Registry, Muster = CityState). Sterne 1–3 nach verbrauchten
## Panik-Goobys (Doc G §4.4: "1–3 nach verlorenen Dampfwalzen"), Best-Scores,
## Erst-Abschluss-Flags (für den First-Clear-Bonus) und das Goldi-Code-Flag
## (Doc G §4.2 — der Codes-Engine-Haken setzt `goldi:true`, §B/M2).
## Alle Zugriffe über Duck-Typing (`gs` = /root/GameState ODER Test-Double).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "gvz"
const LEVEL_COUNT := 15

static var _registered := false


## Slice registrieren (idempotent; nachträglich heilt normalize beim Load).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"v": 1, "stars": {}, "best": {}, "cleared": {}, "goldi": false}


## Self-Heal: Typen reparieren, gültige Daten VERBATIM erhalten.
static func normalize_slice(raw: Variant) -> Dictionary:
	var gvz: Dictionary = raw if raw is Dictionary else default_slice()
	gvz["v"] = maxi(1, int(_num(gvz.get("v"), 1.0)))
	for key: String in ["stars", "best", "cleared"]:
		if not (gvz.get(key) is Dictionary):
			gvz[key] = {}
	gvz["goldi"] = bool(gvz.get("goldi", false))
	return gvz


## Sterne für einen Sieg: 3 ohne Panik-Gooby, 2 bei einem, sonst 1.
static func stars_for(mowers_used: int) -> int:
	if mowers_used <= 0:
		return 3
	return 2 if mowers_used == 1 else 1


## Gesamt-Score eines Siegs (Doc G Coin-Row-würdig): Kill-Score aus dem Lauf
## + Stern-Bonus + Level-Bonus + einmaliger Erst-Abschluss-Bonus.
static func final_score(
	run_score: int, level_id: int, stars: int, first_clear: bool, balance: Dictionary
) -> int:
	var score: Dictionary = balance.get("score", {})
	var total := run_score
	total += stars * int(score.get("star_bonus", 10))
	total += level_id * int(score.get("level_bonus", 4))
	if first_clear:
		total += int(score.get("first_clear_bonus", 50))
	return total


static func level_stars(gs: Object, level_id: int) -> int:
	if gs == null:
		return 0
	return int(_num(gs.get_value("%s.stars.%d" % [SLICE_ID, level_id], 0)))


static func is_cleared(gs: Object, level_id: int) -> bool:
	if gs == null:
		return false
	return bool(gs.get_value("%s.cleared.%d" % [SLICE_ID, level_id], false))


## Höchstes spielbares Level: alles bis zum ersten noch nicht
## abgeschlossenen Level (L1 ist immer offen).
static func max_unlocked(gs: Object) -> int:
	for id in range(1, LEVEL_COUNT + 1):
		if not is_cleared(gs, id):
			return id
	return LEVEL_COUNT


static func total_stars(gs: Object) -> int:
	var total := 0
	for id in range(1, LEVEL_COUNT + 1):
		total += level_stars(gs, id)
	return total


## Anzahl WIRKLICH abgeschlossener Level (0..15). max_unlocked() taugt dafür
## nicht: es ist nach dem Vollabschluss auf LEVEL_COUNT gedeckelt und meldete
## via "-1" 14 statt 15 (E11-P1-5).
static func cleared_count(gs: Object) -> int:
	var total := 0
	for id in range(1, LEVEL_COUNT + 1):
		if is_cleared(gs, id):
			total += 1
	return total


static func goldi_unlocked(gs: Object) -> bool:
	if gs == null:
		return false
	return bool(gs.get_value("%s.goldi" % SLICE_ID, false))


## Sieg verbuchen. Liefert {first_clear, new_best, stars_before}.
## Ohne GameState (Pure-Tests/Host-lose Läufe) nur das Ergebnis-Dict.
static func record_win(gs: Object, level_id: int, stars: int, score: int) -> Dictionary:
	var first_clear := not is_cleared(gs, level_id)
	var stars_before := level_stars(gs, level_id)
	var best_before := 0
	if gs != null:
		best_before = int(_num(gs.get_value("%s.best.%d" % [SLICE_ID, level_id], 0)))
	var new_best := score > best_before
	if gs != null:
		var key := str(level_id)
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
