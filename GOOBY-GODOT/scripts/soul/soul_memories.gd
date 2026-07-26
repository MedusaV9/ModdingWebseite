class_name SoulMemories
extends RefCounted
## Persönliche Erinnerungen (FB-6/SEELE) — Gooby erwähnt NUR Dinge, die
## WIRKLICH passiert sind. Jeder Kandidat wird aus echten Save-Daten gebaut
## (Rekorde, Urlaube, Zähler, Streaks); ohne Daten gibt es KEINE Erinnerung.
## PURE Statics: State + Zeit werden hereingereicht, Auswahl über roll (0..1).

const MEMORY_COOLDOWN_MS := 3 * 86_400_000

## Schwellen, ab denen ein Zähler eine Erinnerung wert ist.
const MIN_TICKLES := 20
const MIN_HARVESTS := 10
const MIN_STREAK := 3
const MIN_PLAYTIME_MIN := 600


## Alle aktuell möglichen Erinnerungen: Array aus
## {id, text_key, args: Dictionary}. Reihenfolge stabil (deterministisch).
static func candidates(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add_best_minigame(out, state)
	_add_vacation(out, state)
	_add_counters(out, state)
	_add_streak(out, state)
	_add_park(out, state)
	_add_playtime(out, state)
	return out


## Kandidat wählen, der laut memoryShownAt lange nicht dran war. roll (0..1)
## wählt deterministisch unter den erlaubten; {} wenn keiner erlaubt ist.
static func pick(
	memory_candidates: Array[Dictionary], shown_at: Dictionary, now_ms: int, roll: float
) -> Dictionary:
	var allowed: Array[Dictionary] = []
	for candidate in memory_candidates:
		var last := int(shown_at.get(str(candidate["id"]), 0))
		if last <= 0 or now_ms - last >= MEMORY_COOLDOWN_MS:
			allowed.append(candidate)
	if allowed.is_empty():
		return {}
	var index := int(clampf(roll, 0.0, 0.999999) * allowed.size())
	return allowed[index]


## Bester Minigame-Rekord (minigames.legacy.best: {gameId: score}).
static func _add_best_minigame(out: Array[Dictionary], state: Dictionary) -> void:
	var best: Variant = _dig(state, ["minigames", "legacy", "best"])
	if not (best is Dictionary) or (best as Dictionary).is_empty():
		return
	var top_id := ""
	var top_score := 0
	var ids: Array = (best as Dictionary).keys()
	ids.sort()
	for game_id: Variant in ids:
		var score := int(_num(best[game_id]))
		if score > top_score:
			top_score = score
			top_id = str(game_id)
	if top_id.is_empty() or top_score <= 0:
		return
	(
		out
		. append(
			{
				"id": "rekord_" + top_id,
				"text_key": "soul.erinnerung.rekord",
				"args": {"spiel": _game_title(top_id), "punkte": top_score},
			}
		)
	)


## Urlaubs-Erinnerung nur bei ECHT besuchten Zielen (vacation.visited).
static func _add_vacation(out: Array[Dictionary], state: Dictionary) -> void:
	var visited: Variant = _dig(state, ["vacation", "visited"])
	if not (visited is Dictionary) or (visited as Dictionary).is_empty():
		return
	var dests: Array = (visited as Dictionary).keys()
	dests.sort()
	var dest := str(dests[0])
	(
		out
		. append(
			{
				"id": "urlaub_" + dest,
				"text_key": "soul.erinnerung.urlaub",
				"args": {"ziel": _dest_title(dest)},
			}
		)
	)


## Zähler-Erinnerungen (achievements.counters) — nur ab Schwelle.
static func _add_counters(out: Array[Dictionary], state: Dictionary) -> void:
	var counters: Variant = _dig(state, ["achievements", "counters"])
	if not (counters is Dictionary):
		return
	var tickles := int(_num((counters as Dictionary).get("tickles")))
	if tickles >= MIN_TICKLES:
		(
			out
			. append(
				{
					"id": "kitzeln",
					"text_key": "soul.erinnerung.kitzeln",
					"args": {"anzahl": tickles},
				}
			)
		)
	var harvests := int(_num((counters as Dictionary).get("harvests")))
	if harvests >= MIN_HARVESTS:
		(
			out
			. append(
				{
					"id": "garten",
					"text_key": "soul.erinnerung.garten",
					"args": {"anzahl": harvests},
				}
			)
		)


static func _add_streak(out: Array[Dictionary], state: Dictionary) -> void:
	var streak := int(_num(_dig(state, ["daily", "streak"])))
	if streak >= MIN_STREAK:
		(
			out
			. append(
				{
					"id": "streak",
					"text_key": "soul.erinnerung.streak",
					"args": {"tage": streak},
				}
			)
		)


static func _add_park(out: Array[Dictionary], state: Dictionary) -> void:
	var visits := int(_num(_dig(state, ["park", "visits"])))
	if visits > 0:
		(
			out
			. append(
				{
					"id": "funkelpark",
					"text_key": "soul.erinnerung.funkelpark",
					"args": {"anzahl": visits},
				}
			)
		)


static func _add_playtime(out: Array[Dictionary], state: Dictionary) -> void:
	var minutes := int(_num(_dig(state, ["profile", "playtimeMin"])))
	if minutes >= MIN_PLAYTIME_MIN:
		(
			out
			. append(
				{
					"id": "spielzeit",
					"text_key": "soul.erinnerung.spielzeit",
					"args": {"stunden": int(minutes / 60.0)},
				}
			)
		)


## Spieltitel über den I18n-Katalog der Minigames ("mg.<id>.title"),
## Fallback: die rohe Id (nie crashen, nie leere Erinnerung).
static func _game_title(game_id: String) -> String:
	var key := "mg.%s.title" % game_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return game_id


static func _dest_title(dest_id: String) -> String:
	var key := "travel.ziel.%s" % dest_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return dest_id


static func _dig(state: Dictionary, path: Array) -> Variant:
	var node: Variant = state
	for part: Variant in path:
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return null
	return node


static func _num(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0
