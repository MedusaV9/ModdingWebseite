class_name RanchSpieleProgress
extends RefCounted
## Fortschritt der beiden Ranch-Minispiele (RANCH-2) im Unterschlüssel
## `ranch.spiele.<spiel>` des ranch-Slices (Struktur: RanchPlaySlices,
## Muster = GobnomProgress). Spiele: "parcours" (10 Kurse) und "herde"
## (10 Level); Schlüssel je Level "k<id>". Alle Zugriffe über Duck-Typing
## (`gs` = /root/GameState ODER Test-Double) — ohne GameState liefern die
## Leser Defaults und record_win() bucht nichts.

const SPIEL_PARCOURS := "parcours"
const SPIEL_HERDE := "herde"
const LEVEL_COUNT := 10


static func level_key(level_id: int) -> String:
	return "k%d" % level_id


static func level_stars(gs: Object, spiel: String, level_id: int) -> int:
	if gs == null:
		return 0
	var key := level_key(level_id)
	return int(_num(gs.get_value("ranch.spiele.%s.stars.%s" % [spiel, key], 0)))


static func level_best(gs: Object, spiel: String, level_id: int) -> int:
	if gs == null:
		return 0
	var key := level_key(level_id)
	return int(_num(gs.get_value("ranch.spiele.%s.best.%s" % [spiel, key], 0)))


static func is_cleared(gs: Object, spiel: String, level_id: int) -> bool:
	if gs == null:
		return false
	var key := level_key(level_id)
	return bool(gs.get_value("ranch.spiele.%s.cleared.%s" % [spiel, key], false))


## Höchstes spielbares Level: alles bis zum ersten nicht abgeschlossenen
## (Level 1 ist immer offen).
static func max_unlocked(gs: Object, spiel: String) -> int:
	for id in range(1, LEVEL_COUNT + 1):
		if not is_cleared(gs, spiel, id):
			return id
	return LEVEL_COUNT


static func total_stars(gs: Object, spiel: String) -> int:
	var total := 0
	for id in range(1, LEVEL_COUNT + 1):
		total += level_stars(gs, spiel, id)
	return total


## Sieg verbuchen (Sterne/Best nur verbessern, cleared bleibt true).
## Liefert {"first_clear": bool, "new_best": bool, "stars_before": int}.
static func record_win(
	gs: Object, spiel: String, level_id: int, stars: int, score: int
) -> Dictionary:
	var first_clear := not is_cleared(gs, spiel, level_id)
	var stars_before := level_stars(gs, spiel, level_id)
	var best_before := level_best(gs, spiel, level_id)
	var new_best := score > best_before
	if gs != null:
		var key := level_key(level_id)
		gs.update(
			func(state: Dictionary) -> void:
				var ranch: Dictionary = (
					state.get("ranch") if state.get("ranch") is Dictionary else {}
				)
				ranch["spiele"] = RanchPlaySlices.normalize_spiele(ranch.get("spiele"))
				var eintrag: Dictionary = ranch["spiele"][spiel]
				eintrag["cleared"][key] = true
				eintrag["stars"][key] = maxi(stars_before, stars)
				eintrag["best"][key] = maxi(best_before, score)
				state["ranch"] = ranch
		)
		gs.notify_slice_changed("ranch")
	return {"first_clear": first_clear, "new_best": new_best, "stars_before": stars_before}


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
