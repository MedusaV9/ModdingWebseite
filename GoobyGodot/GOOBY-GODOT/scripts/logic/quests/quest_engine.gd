class_name DailyQuestEngine
extends RefCounted
## Tagesquest-Engine (REST-2, Port von GOOBY/src/systems/quests.js §B7/§C5.1):
## PURE Statics — Save-Slice, Pool, Kontext und Zeit werden hereingereicht,
## damit alles headless testbar bleibt (Muster SoulService/StickerUnlocks).
##
## Semantik (bindend, Web-verbatim wo portierbar):
## - roll_today(): 3 Quests pro Lokaltag, DETERMINISTISCH aus dem Datum
##   gewürfelt (mulberry32(hash32(day)) — alle Spieler sehen dieselben
##   Karten), `braucht`-gefiltert gegen den Spielstand (keine Aufgaben für
##   gesperrte Inhalte), >= 2 verschiedene Kategorien pro Brett.
## - Fortschritt läuft über die VORHANDENEN Zähler des Saves (achievements-
##   Counter, minigames.plays, economy.coinsEarned/Spent, Bestwert-Boards):
##   beim Roll wird pro Quest eine Baseline eingefroren, Fortschritt ist die
##   Differenz seither. Kein zweiter Event-Bus, kein Polling-Zwang.
## - claim(): Fortschritt >= Ziel && !claimed -> markiert claimed und liefert
##   {muenzen, xp}; die Auszahlung (Economy/Leveling/questsDone-Zähler)
##   übernimmt der Aufrufer (quest_service.gd) — Web-§B3-Muster.
## - reroll_today(): 1x pro Lokaltag, ersetzt NUR unangefasste Quests mit
##   frischen Picks (Seed hash32(day + ":r")).
## - Abschluss-Bonus: alle 3 geclaimt -> einmalig BONUS_COINS/BONUS_XP
##   (bonusDay-Guard) — der „alle drei geschafft“-Moment aus der Aufgabe.
##
## Save-Slice (ADDITIV im bestehenden `quests`-Dict, KEIN Version-Bump):
##   {completedTotal, day, active: [{id, claimed, base:{...}}], rerolledDay,
##    bonusDay}

## Zahl der Karten pro Tag (Web §B7).
const QUESTS_PER_DAY := 3
## Mindestzahl verschiedener Kategorien auf dem Brett (Web §B7).
const MIN_CATEGORIES := 2
## Abschluss-Bonus, wenn alle drei Quests geclaimt sind.
const BONUS_COINS := 50
const BONUS_XP := 25


## Sind die `braucht`-Bedingungen eines Pool-Eintrags erfüllt?
## ctx: {"level": int, "minigames": Array[String], "garden": bool}
static func requires_met(braucht: Variant, ctx: Dictionary) -> bool:
	if not (braucht is Dictionary) or (braucht as Dictionary).is_empty():
		return true
	var req: Dictionary = braucht
	var games: Array = ctx.get("minigames", [])
	if req.has("minigame") and not games.has(str(req["minigame"])):
		return false
	if bool(req.get("garden", false)) and not bool(ctx.get("garden", true)):
		return false
	if req.has("level") and int(ctx.get("level", 1)) < int(req["level"]):
		return false
	return true


## Alle Pool-Einträge, die zum aktuellen Fortschritt passen.
static func eligible_defs(pool: Array, ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def: Variant in pool:
		if def is Dictionary and requires_met((def as Dictionary).get("braucht"), ctx):
			out.append(def)
	return out


## Steht für `day` schon der richtige Roll im Slice?
static func roll_needed(slice: Dictionary, day: String) -> bool:
	if str(slice.get("day", "")) != day:
		return true
	return not (slice.get("active") is Array) or (slice["active"] as Array).is_empty()


## Heutige 3 Quests würfeln — deterministisch pro Lokaltag. Mutiert `slice`
## in place (innerhalb von GameState.update aufrufen). No-op, wenn der Tag
## schon gerollt ist.
static func roll_today(
	slice: Dictionary, day: String, pool: Array, ctx: Dictionary, state: Dictionary
) -> bool:
	if not roll_needed(slice, day):
		return false
	var picks := _pick_set(_rng_state(hash32(day)), eligible_defs(pool, ctx), [], QUESTS_PER_DAY)
	var active: Array = []
	for def: Dictionary in picks:
		active.append(make_entry(def, state))
	slice["day"] = day
	slice["active"] = active
	slice["bonusDay"] = str(slice.get("bonusDay", ""))
	return true


## Freier Tages-Reroll (Web §B7): 1x pro Tag, ersetzt nur unangefasste
## Quests. Mutiert `slice`; liefert false ohne Reroll (schon benutzt/nichts
## ersetzbar/kein Roll für heute).
static func reroll_today(
	slice: Dictionary, day: String, pool: Array, ctx: Dictionary, state: Dictionary
) -> bool:
	if str(slice.get("day", "")) != day or str(slice.get("rerolledDay", "")) == day:
		return false
	var by_id := pool_by_id(pool)
	var active: Array = slice.get("active", [])
	var replace_idx: Array[int] = []
	var kept: Array[Dictionary] = []
	var taken_ids: Array[String] = []
	for i in active.size():
		var entry: Variant = active[i]
		if not (entry is Dictionary):
			replace_idx.append(i)
			continue
		taken_ids.append(str(entry.get("id", "")))
		var def: Dictionary = by_id.get(str(entry.get("id", "")), {})
		var untouched: bool = (
			not bool(entry.get("claimed", false))
			and (def.is_empty() or progress_of(entry, def, state) <= 0)
		)
		if untouched:
			replace_idx.append(i)
		elif not def.is_empty():
			kept.append(def)
	if replace_idx.is_empty():
		return false
	var eligible: Array[Dictionary] = []
	for def in eligible_defs(pool, ctx):
		if not taken_ids.has(str(def.get("id", ""))):
			eligible.append(def)
	var picks := _pick_set(_rng_state(hash32(day + ":r")), eligible, kept, replace_idx.size())
	for k in picks.size():
		active[replace_idx[k]] = make_entry(picks[k], state)
	slice["rerolledDay"] = day
	return true


## Brett-Eintrag mit eingefrorener Zähler-Baseline.
static func make_entry(def: Dictionary, state: Dictionary) -> Dictionary:
	return {"id": str(def.get("id", "")), "claimed": false, "base": baseline_of(def, state)}


## Baseline der Messung eines Defs im aktuellen Save-Stand.
static func baseline_of(def: Dictionary, state: Dictionary) -> Dictionary:
	var messung := _messung(def)
	match str(messung.get("typ", "")):
		"counter":
			return {"n": _counter(state, str(messung.get("key", "")))}
		"spiele_gesamt":
			return {"n": _plays_sum(state)}
		"spiele_verschieden":
			return {"m": _plays_map(state)}
		"spiel_runden", "spiel_punkte":
			return {"n": _plays_of(state, str(messung.get("spiel", "")))}
		"muenzen_verdient":
			return {"n": _econ_int(state, "coinsEarned")}
		"muenzen_ausgegeben":
			return {"n": _econ_int(state, "coinsSpent")}
	return {}


## Fortschritt eines Brett-Eintrags (0..ziel) aus den LIVE-Zählern.
static func progress_of(entry: Dictionary, def: Dictionary, state: Dictionary) -> int:
	var ziel := target_of(def)
	var messung := _messung(def)
	var base: Dictionary = entry.get("base") if entry.get("base") is Dictionary else {}
	var raw := _raw_progress(messung, base, state, ziel)
	return clampi(raw, 0, ziel)


static func is_complete(entry: Dictionary, def: Dictionary, state: Dictionary) -> bool:
	return progress_of(entry, def, state) >= target_of(def)


static func target_of(def: Dictionary) -> int:
	return maxi(1, int(_num(def.get("ziel"), 1.0)))


## Claim-Prüfung + Markierung. Mutiert `slice` (claimed, completedTotal);
## liefert {"ok": bool, "muenzen": int, "xp": int}. Auszahlung macht der
## Aufrufer.
static func claim(slice: Dictionary, id: String, def: Dictionary, state: Dictionary) -> Dictionary:
	var entry := _entry_of(slice, id)
	if entry.is_empty() or def.is_empty():
		return {"ok": false, "muenzen": 0, "xp": 0}
	if bool(entry.get("claimed", false)) or not is_complete(entry, def, state):
		return {"ok": false, "muenzen": 0, "xp": 0}
	entry["claimed"] = true
	slice["completedTotal"] = int(_num(slice.get("completedTotal"), 0.0)) + 1
	return {
		"ok": true,
		"muenzen": maxi(0, int(_num(def.get("muenzen"), 0.0))),
		"xp": maxi(0, int(_num(def.get("xp"), 0.0))),
	}


## Alle drei geclaimt?
static func all_claimed(slice: Dictionary) -> bool:
	var active: Array = slice.get("active", []) if slice.get("active") is Array else []
	if active.size() < QUESTS_PER_DAY:
		return false
	for entry: Variant in active:
		if not (entry is Dictionary) or not bool((entry as Dictionary).get("claimed", false)):
			return false
	return true


## Abschluss-Bonus fällig? (alle drei geclaimt, heute noch nicht bezahlt)
static func bonus_due(slice: Dictionary, day: String) -> bool:
	return all_claimed(slice) and str(slice.get("bonusDay", "")) != day


## Bonus als bezahlt markieren (mutiert `slice`).
static func mark_bonus_paid(slice: Dictionary, day: String) -> void:
	slice["bonusDay"] = day


## Zahl der abholbereiten Quests (HUD-Badge/„Was nun?“).
static func claimable_count(slice: Dictionary, by_id: Dictionary, state: Dictionary) -> int:
	var n := 0
	for entry: Variant in slice.get("active", []) if slice.get("active") is Array else []:
		if not (entry is Dictionary) or bool((entry as Dictionary).get("claimed", false)):
			continue
		var def: Dictionary = by_id.get(str((entry as Dictionary).get("id", "")), {})
		if not def.is_empty() and is_complete(entry, def, state):
			n += 1
	return n


static func pool_by_id(pool: Array) -> Dictionary:
	var map := {}
	for def: Variant in pool:
		if def is Dictionary:
			map[str((def as Dictionary).get("id", ""))] = def
	return map


## 32-bit-Stringhash (Port des xmur3-Rezepts aus systems/quests.js) —
## liefert für denselben Tag auf allen Geräten denselben Seed.
static func hash32(text: String) -> int:
	var h := (1779033703 ^ text.length()) & 0xFFFFFFFF
	for i in text.length():
		h = _imul32(h ^ text.unicode_at(i), 3432918353)
		h = ((h << 13) | (h >> 19)) & 0xFFFFFFFF
	h = _imul32(h ^ (h >> 16), 2246822507)
	h = _imul32(h ^ (h >> 13), 3266489909)
	return (h ^ (h >> 16)) & 0xFFFFFFFF


## Nächster deterministischer 0..1-Wert (mulberry32; `rng` = _rng_state()).
static func rand_next(rng: Dictionary) -> float:
	rng["a"] = (int(rng["a"]) + 0x6D2B79F5) & 0xFFFFFFFF
	var a: int = rng["a"]
	var t := _imul32(a ^ (a >> 15), (a | 1) & 0xFFFFFFFF)
	t = ((t + _imul32(t ^ (t >> 7), (t | 61) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


# ── intern ────────────────────────────────────────────────────────────────────


static func _rng_state(seed_value: int) -> Dictionary:
	return {"a": seed_value & 0xFFFFFFFF}


## `count` Defs ziehen (ohne `kept`-Ids), letzter Zug erzwingt — wenn möglich
## — die Mindest-Kategorienvielfalt (Web pickQuestSet, deterministisch).
static func _pick_set(
	rng: Dictionary, eligible: Array[Dictionary], kept: Array[Dictionary], count: int
) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	var taken := {}
	for def in kept:
		taken[str(def.get("id", ""))] = true
	for i in count:
		var candidates: Array[Dictionary] = []
		for def in eligible:
			if not taken.has(str(def.get("id", ""))):
				candidates.append(def)
		if candidates.is_empty():
			break
		if i == count - 1:
			candidates = _prefer_new_category(candidates, kept + chosen)
		var pick := candidates[int(rand_next(rng) * candidates.size()) % candidates.size()]
		chosen.append(pick)
		taken[str(pick.get("id", ""))] = true
	return chosen


static func _prefer_new_category(
	candidates: Array[Dictionary], board: Array[Dictionary]
) -> Array[Dictionary]:
	var cats := {}
	for def in board:
		cats[str(def.get("kategorie", ""))] = true
	if cats.is_empty() or cats.size() >= MIN_CATEGORIES:
		return candidates
	var fresh: Array[Dictionary] = []
	for def in candidates:
		if not cats.has(str(def.get("kategorie", ""))):
			fresh.append(def)
	return fresh if not fresh.is_empty() else candidates


## JS-Math.imul-Äquivalent auf unsigned 32-bit (ohne 64-bit-Überlauf).
static func _imul32(a: int, b: int) -> int:
	var au := a & 0xFFFFFFFF
	var bu := b & 0xFFFFFFFF
	var lo := au & 0xFFFF
	var hi := (au >> 16) & 0xFFFF
	return (lo * bu + (((hi * bu) & 0xFFFF) << 16)) & 0xFFFFFFFF


static func _messung(def: Dictionary) -> Dictionary:
	return def.get("messung") if def.get("messung") is Dictionary else {}


static func _raw_progress(
	messung: Dictionary, base: Dictionary, state: Dictionary, ziel: int
) -> int:
	match str(messung.get("typ", "")):
		"counter":
			return _counter(state, str(messung.get("key", ""))) - int(_num(base.get("n"), 0.0))
		"streicheln_heute":
			return _pets_today(state)
		"spiele_gesamt":
			return _plays_sum(state) - int(_num(base.get("n"), 0.0))
		"spiele_verschieden":
			return _distinct_new_plays(state, base)
		"spiel_runden":
			var spiel := str(messung.get("spiel", ""))
			return _plays_of(state, spiel) - int(_num(base.get("n"), 0.0))
		"spiel_punkte":
			return _score_progress(messung, base, state, ziel)
		"muenzen_verdient":
			return _econ_int(state, "coinsEarned") - int(_num(base.get("n"), 0.0))
		"muenzen_ausgegeben":
			return _econ_int(state, "coinsSpent") - int(_num(base.get("n"), 0.0))
	return 0


## Punkte-Quests: zählt erst NACH einer heutigen Runde des Spiels; dann gilt
## der beste Boards-Wert (best/bestByDiff/endlessBest) gegen das Ziel.
static func _score_progress(
	messung: Dictionary, base: Dictionary, state: Dictionary, ziel: int
) -> int:
	var spiel := str(messung.get("spiel", ""))
	if _plays_of(state, spiel) <= int(_num(base.get("n"), 0.0)):
		return 0
	return mini(_best_of(state, spiel), ziel)


static func _counter(state: Dictionary, key: String) -> int:
	return int(_num(_dig(state, ["achievements", "counters", key]), 0.0))


## Streichler+Kitzler HEUTE: petsToday ist selbst tagesgebunden (petsDay).
static func _pets_today(state: Dictionary) -> int:
	return int(_num(_dig(state, ["achievements", "counters", "petsToday"]), 0.0))


static func _plays_map(state: Dictionary) -> Dictionary:
	var plays: Variant = _dig(state, ["minigames", "plays"])
	var out := {}
	if plays is Dictionary:
		for id: Variant in plays:
			out[str(id)] = int(_num(plays[id], 0.0))
	return out


static func _plays_sum(state: Dictionary) -> int:
	var total := 0
	for n: int in _plays_map(state).values():
		total += n
	return total


static func _plays_of(state: Dictionary, spiel: String) -> int:
	return int(_num(_dig(state, ["minigames", "plays", spiel]), 0.0))


static func _distinct_new_plays(state: Dictionary, base: Dictionary) -> int:
	var before: Dictionary = base.get("m") if base.get("m") is Dictionary else {}
	var now := _plays_map(state)
	var distinct := 0
	for id: String in now:
		if int(now[id]) > int(_num(before.get(id), 0.0)):
			distinct += 1
	return distinct


static func _best_of(state: Dictionary, spiel: String) -> int:
	var best := int(_num(_dig(state, ["minigames", "legacy", "best", spiel]), 0.0))
	best = maxi(best, int(_num(_dig(state, ["minigames", "legacy", "endlessBest", spiel]), 0.0)))
	var by_diff: Variant = _dig(state, ["minigames", "legacy", "bestByDiff", spiel])
	if by_diff is Dictionary:
		for mode: Variant in by_diff:
			best = maxi(best, int(_num(by_diff[mode], 0.0)))
	return best


static func _econ_int(state: Dictionary, key: String) -> int:
	return int(_num(_dig(state, ["economy", key]), 0.0))


static func _entry_of(slice: Dictionary, id: String) -> Dictionary:
	for entry: Variant in slice.get("active", []) if slice.get("active") is Array else []:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == id:
			return entry
	return {}


static func _dig(data: Variant, path: Array) -> Variant:
	var current: Variant = data
	for part: String in path:
		if not (current is Dictionary) or not current.has(part):
			return null
		current = current[part]
	return current


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback
