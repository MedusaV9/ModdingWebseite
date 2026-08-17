class_name ModifierEngine
extends RefCounted
## Arcade-Modifier-Engine (FERTIG-1, EVAL Rang 12) — Port des Web-Schedulers
## GOOBY/src/systems/modifierEngine.js auf das v5-Schema. PUR: keine Nodes,
## keine Zeitquelle (Aufrufer reicht now_ms), deterministisch über den
## persistierten mulberry32-Stream (GoobyRng == Web-rand01, bit-identisch).
##
## Ablauf (Web §B4/§C-SYS4): erstes Event GRACE_MIN nach dem ersten Boot,
## danach alle CADENCE_MIN 50–120 min (seeded uniform). Ein Event ist EIN
## (Spiel, Typ)-Paar, 45 min ODER das Runden-Budget gültig. Der Host
## konsumiert beim echten Rundenstart eine Runde (consume), Früh-Abbruch
## erstattet ≤ 1×/Event (refund). Anti-Farm: Überschüsse laufen über das
## 150-c/Tag-Ledger in economy (Economy.award, Reason 'modifier'/
## 'glueckspilz' — deckungsgleich mit dem Web-§C-SYS11.1).
##
## BEWUSSTE GODOT-ABWEICHUNGEN (dokumentiert, ehrlich):
## - Freischaltung über FORTSCHRITT: jeder Typ hat ein min_level (das Web
##   gatete über Spiel-Unlocks; Godot-Spiele sind alle sichtbar). Der Pool
##   wächst also mit dem Spielerlevel — Level 2 bis Level 12.
## - Alle 6 Typen wirken ZENTRAL über das Framework (Host/Award), damit
##   JEDES registrierte Spiel modifizierbar ist: riesenGooby/stickerChance
##   aus dem Web (per-Spiel-Gameplay bzw. Random-Drops, die es in Godot
##   nicht gibt) sind durch `lernrausch` (XP ×2) und `federleicht`
##   (Runde kostet keine Energie) ersetzt.
## - Der Tick läuft im GoobyTicker (5-s-Live-Tick + Offline-Catch-up).
##
## Save-Slice `modifiers` (ADDITIV, KEIN Version-Bump — Registrierung über
## game_state.gd DEFAULT_SLICE_SCRIPTS):
##   {nextAt: int(ms), seed: int, current: null|Dictionary, lastGameId: ""}
##   current = {gameId, type, startedAt, endsAt, playsLeft, refundUsed?}

## Web-§B4-Timing (Minuten) — Zahlen eingefroren wie im Web.
const GRACE_MIN := 30
const WINDOW_MIN := 45
const CADENCE_MIN_LO := 50
const CADENCE_MIN_HI := 120
const MS_PER_MIN := 60000

## §C-SYS4.2 Glücksrolle-Grenzen (inklusiv).
const GLUECKSPILZ_MIN := 10
const GLUECKSPILZ_MAX := 60

## Stabile Roll-Reihenfolge der Typen (Determinismus des Seed-Streams).
const TYPE_IDS: Array[String] = [
	"doppelGold", "muenzregen", "turbo", "lernrausch", "federleicht", "glueckspilz"
]

## Der Modifikator-Pool. Effekte werden ZENTRAL angewandt (Host/Award):
## coin_mult → Auszahlung ×n (Überschuss gegen das Tages-Ledger),
## score_mult → Punkte ×n am Rundenende, xp_mult → Runden-XP ×n,
## energy_free → Rundenstart kostet keine Energie, gluecksrolle → +10–60 c.
const TYPES := {
	"doppelGold":
	{
		"plays": 2,
		"min_level": 2,
		"coin_mult": 2.0,
		"name_key": "modifier.name.doppelGold",
		"desc_key": "modifier.desc.doppelGold",
		"icon": "coin",
		"color": Color(1.0, 0.83, 0.3),
	},
	"muenzregen":
	{
		"plays": 3,
		"min_level": 4,
		"coin_mult": 1.5,
		"name_key": "modifier.name.muenzregen",
		"desc_key": "modifier.desc.muenzregen",
		"icon": "sparkle",
		"color": Color(0.25, 0.79, 0.75),
	},
	"turbo":
	{
		"plays": 3,
		"min_level": 6,
		"score_mult": 1.5,
		"name_key": "modifier.name.turbo",
		"desc_key": "modifier.desc.turbo",
		"icon": "energy",
		"color": Color(1.0, 0.48, 0.4),
	},
	"lernrausch":
	{
		"plays": 3,
		"min_level": 8,
		"xp_mult": 2.0,
		"name_key": "modifier.name.lernrausch",
		"desc_key": "modifier.desc.lernrausch",
		"icon": "book",
		"color": Color(0.55, 0.73, 0.36),
	},
	"federleicht":
	{
		"plays": 3,
		"min_level": 10,
		"energy_free": true,
		"name_key": "modifier.name.federleicht",
		"desc_key": "modifier.desc.federleicht",
		"icon": "feather",
		"color": Color(0.73, 0.65, 0.94),
	},
	"glueckspilz":
	{
		"plays": 3,
		"min_level": 12,
		"gluecksrolle": true,
		"name_key": "modifier.name.glueckspilz",
		"desc_key": "modifier.desc.glueckspilz",
		"icon": "clover",
		"color": Color(1.0, 0.62, 0.85),
	},
}


## Frischer Slice (Web defaultSlice; Tages-Ledger liegen in economy).
static func default_slice() -> Dictionary:
	return {"nextAt": 0, "seed": 0, "current": null, "lastGameId": ""}


## Defensive Slice-Normalisierung (save_schema-Registry-Callback).
static func normalize_slice(raw: Variant) -> Dictionary:
	var out := default_slice()
	if not (raw is Dictionary):
		return out
	var src: Dictionary = raw
	out["nextAt"] = maxi(0, int(_num(src.get("nextAt"))))
	out["seed"] = int(_num(src.get("seed"))) & 0xFFFFFFFF
	if src.get("lastGameId") is String:
		out["lastGameId"] = src["lastGameId"]
	var cur: Variant = src.get("current")
	if cur is Dictionary and TYPES.has(str(cur.get("type", ""))):
		var plays := int(_num(cur.get("playsLeft")))
		var ends := int(_num(cur.get("endsAt")))
		if plays > 0 and ends > 0 and str(cur.get("gameId", "")) != "":
			out["current"] = {
				"gameId": str(cur["gameId"]),
				"type": str(cur["type"]),
				"startedAt": maxi(0, int(_num(cur.get("startedAt")))),
				"endsAt": ends,
				"playsLeft": plays,
				"refundUsed": cur.get("refundUsed") == true,
			}
	return out


## Initiale Stream-Position aus meta.createdAt (Web deriveModifierSeed);
## Junk fällt auf 1 zurück, damit der Sentinel 0 nie kleben bleibt.
static func initial_seed(state: Dictionary) -> int:
	var meta := _dict(state.get("meta"))
	var created := int(_num(meta.get("createdAt")))
	var seed_value := created & 0xFFFFFFFF
	return seed_value if seed_value != 0 else 1


## Web-rand01: EIN mulberry32-Zug an der persistierten Stream-Position.
static func rand01(seed_value: int) -> float:
	return GoobyRng.new(seed_value).next()


## Freischaltung über Fortschritt: alle Typen mit min_level <= level.
static func unlocked_types(level: int) -> Array[String]:
	var out: Array[String] = []
	for type_id in TYPE_IDS:
		if level >= int(TYPES[type_id]["min_level"]):
			out.append(type_id)
	return out


## Ids aller spielbaren Registry-Spiele (Default-Kandidaten eines Rolls).
static func playable_game_ids() -> Array[String]:
	var out: Array[String] = []
	for game in MinigameRegistry.playable():
		out.append(str(game["id"]))
	return out


## Alle wählbaren (Spiel, Typ)-Paare: Typ freigeschaltet, Spiel != lastGameId.
## Stabile Reihenfolge (Typ-Reihenfolge × Spiel-Reihenfolge) — ein Seed
## bildet für immer auf dasselbe Paar ab. `game_ids` ist für Tests injizierbar.
static func eligible_pairs(
	level: int, last_game_id := "", game_ids: Array[String] = []
) -> Array[Dictionary]:
	var games := game_ids if not game_ids.is_empty() else playable_game_ids()
	var pairs: Array[Dictionary] = []
	for type_id in unlocked_types(level):
		for game_id in games:
			if game_id == last_game_id:
				continue
			pairs.append({"gameId": game_id, "type": type_id})
	return pairs


## Der Scheduler-Tick (Web §B4) — PUR: mutiert `state` nie; liefert
## {"changes": null|Dictionary, "event": ""|"scheduled"|"started"|
##  "expired"|"rescheduled"}. Der Aufrufer weist changes zu.
static func tick(state: Dictionary, now_ms: int, game_ids: Array[String] = []) -> Dictionary:
	var base: Variant = state.get("modifiers")
	var m := default_slice()
	var changed := true
	if base is Dictionary:
		m = (base as Dictionary).duplicate(true)
		changed = false
	var event := ""

	if int(_num(m.get("seed"))) == 0:
		m["seed"] = initial_seed(state)
		changed = true
	var cur: Variant = m.get("current")
	if cur is Dictionary and now_ms >= int(_num((cur as Dictionary).get("endsAt"))):
		# Fenster vorbei: Event weg, No-Repeat-Pin bleibt, Plan bleibt.
		m["lastGameId"] = str((cur as Dictionary).get("gameId", ""))
		m["current"] = null
		changed = true
		event = "expired"
	if int(_num(m.get("nextAt"))) <= 0:
		m["nextAt"] = now_ms + GRACE_MIN * MS_PER_MIN
		changed = true
		if event == "":
			event = "scheduled"
	elif m.get("current") == null and now_ms >= int(_num(m.get("nextAt"))):
		var level := maxi(1, int(_num(_dict(state.get("progression")).get("level"), 1.0)))
		var rolled := _roll_event(m, now_ms, level, game_ids)
		m = rolled["m"]
		changed = true
		event = "started" if rolled["started"] else "rescheduled"
	return {"changes": m if changed else null, "event": event}


## Eine Runde beim ECHTEN Rundenstart konsumieren (§C-SYS4.4). Mutiert
## state.modifiers. Liefert {ok, modifier(=Snapshot VOR dem Abzug), cleared}.
static func consume(state: Dictionary, game_id: String, now_ms: int) -> Dictionary:
	var active := get_active_for(state, game_id, now_ms)
	if active.is_empty():
		return {"ok": false}
	var m := _dict(state.get("modifiers")).duplicate(true)
	var cur := _dict(m.get("current"))
	var snapshot := cur.duplicate(true)
	var plays_left := int(_num(cur.get("playsLeft"))) - 1
	if plays_left <= 0:
		m["current"] = null
		m["lastGameId"] = str(cur.get("gameId", ""))
	else:
		cur["playsLeft"] = plays_left
		m["current"] = cur
	state["modifiers"] = m
	return {"ok": true, "modifier": snapshot, "cleared": plays_left <= 0}


## Früh-Abbruch-Erstattung (max. EINMAL pro Event, Anti-Farming). Wirkt,
## solange das Original-Fenster noch offen ist — auch wenn der letzte
## consume das Event gerade geleert hat. Mutiert state.modifiers.
static func refund(state: Dictionary, snapshot: Dictionary, now_ms: int) -> Dictionary:
	if snapshot.is_empty() or snapshot.get("refundUsed") == true:
		return {"ok": false}
	if now_ms >= int(_num(snapshot.get("endsAt"))):
		return {"ok": false}
	var m := _dict(state.get("modifiers"))
	if m.is_empty():
		return {"ok": false}
	var out := m.duplicate(true)
	var cur: Variant = out.get("current")
	if (
		cur is Dictionary
		and str((cur as Dictionary).get("gameId", "")) == str(snapshot.get("gameId", ""))
		and int(_num((cur as Dictionary).get("startedAt"))) == int(_num(snapshot.get("startedAt")))
	):
		if (cur as Dictionary).get("refundUsed") == true:
			return {"ok": false}
		var fixed: Dictionary = (cur as Dictionary).duplicate(true)
		fixed["playsLeft"] = int(_num(fixed.get("playsLeft"))) + 1
		fixed["refundUsed"] = true
		out["current"] = fixed
		state["modifiers"] = out
		return {"ok": true}
	if cur == null and str(out.get("lastGameId", "")) == str(snapshot.get("gameId", "")):
		var restored := snapshot.duplicate(true)
		restored["playsLeft"] = 1
		restored["refundUsed"] = true
		out["current"] = restored
		state["modifiers"] = out
		return {"ok": true}
	return {"ok": false}


## Read-only-Deskriptor des aktiven Events FÜR dieses Spiel — die eine
## Quelle für Arcade-Badge, Pregame-Banner und den Host-Consume-Gate.
## Leeres Dictionary = kein passendes aktives Event.
static func get_active_for(state: Dictionary, game_id: String, now_ms: int) -> Dictionary:
	var cur := _dict(_dict(state.get("modifiers")).get("current"))
	if cur.is_empty() or str(cur.get("gameId", "")) != game_id:
		return {}
	if int(_num(cur.get("playsLeft"))) <= 0 or now_ms >= int(_num(cur.get("endsAt"))):
		return {}
	return _descriptor(cur)


## Aktives Event unabhängig vom Spiel (Arcade-Badge auf der Ziel-Kachel).
static func active_event(state: Dictionary, now_ms: int) -> Dictionary:
	var cur := _dict(_dict(state.get("modifiers")).get("current"))
	if cur.is_empty():
		return {}
	return get_active_for(state, str(cur.get("gameId", "")), now_ms)


## Launch-Payload für den Host/Award und (optional) das Spiel via ctx:
## reine Zahlen {type, coin_mult?, score_mult?, xp_mult?, energy_free?, ...}.
static func launch_params(snapshot: Dictionary) -> Dictionary:
	var def := _dict(TYPES.get(str(snapshot.get("type", ""))))
	if def.is_empty():
		return {}
	var out := {"type": str(snapshot["type"])}
	for key in ["coin_mult", "score_mult", "xp_mult", "energy_free"]:
		if def.has(key):
			out[key] = def[key]
	if def.get("gluecksrolle", false):
		out["gluecksrolle"] = true
	return out


## Seeded Glücksrolle (§C-SYS4.2): uniform 10–60, EIN Zug (seed++). Mutiert
## state.modifiers.seed; die Auszahlung bucht der Aufrufer über Economy.
static func roll_glueckspilz(state: Dictionary) -> int:
	var m: Dictionary = _dict(state.get("modifiers")).duplicate(true)
	if m.is_empty():
		m = default_slice()
	if int(_num(m.get("seed"))) == 0:
		m["seed"] = initial_seed(state)
	var seed_value := int(_num(m.get("seed")))
	var span := GLUECKSPILZ_MAX - GLUECKSPILZ_MIN + 1
	var bonus := GLUECKSPILZ_MIN + int(floor(rand01(seed_value) * span))
	m["seed"] = (seed_value + 1) & 0xFFFFFFFF
	state["modifiers"] = m
	return bonus


## Dev-Zwang: Event JETZT für ein explizites Paar starten (Level-Locks
## werden bewusst umgangen — Dev-Fläche). Mutiert state.modifiers.
static func force_event(state: Dictionary, pick: Dictionary, now_ms: int) -> Dictionary:
	var type_id := str(pick.get("type", ""))
	var def := _dict(TYPES.get(type_id))
	if def.is_empty():
		return {"ok": false, "reason": "unknown"}
	var game_id := str(pick.get("gameId", ""))
	if game_id.is_empty():
		return {"ok": false, "reason": "ineligible"}
	var m: Dictionary = _dict(state.get("modifiers")).duplicate(true)
	if m.is_empty():
		m = default_slice()
	if int(_num(m.get("seed"))) == 0:
		m["seed"] = initial_seed(state)
	m["current"] = {
		"gameId": game_id,
		"type": type_id,
		"startedAt": now_ms,
		"endsAt": now_ms + WINDOW_MIN * MS_PER_MIN,
		"playsLeft": int(def["plays"]),
	}
	if int(_num(m.get("nextAt"))) <= now_ms:
		m["nextAt"] = now_ms + GRACE_MIN * MS_PER_MIN
	state["modifiers"] = m
	return {"ok": true}


## Dev-Clear: aktives Event verwerfen; der Plan (nextAt) bleibt.
static func clear_event(state: Dictionary) -> Dictionary:
	var m := _dict(state.get("modifiers"))
	if not (m.get("current") is Dictionary):
		return {"ok": false}
	var out := m.duplicate(true)
	out["lastGameId"] = str(_dict(out.get("current")).get("gameId", ""))
	out["current"] = null
	state["modifiers"] = out
	return {"ok": true}


## Restzeit als "m:ss" fürs Badge/Banner (nie negativ).
static func countdown_text(ends_at: int, now_ms: int) -> String:
	var rest_s := maxi(0, int(ceil(float(ends_at - now_ms) / 1000.0)))
	return "%d:%02d" % [rest_s / 60, rest_s % 60]


## Rollt das nächste Event auf eine Slice-KOPIE (2 Seed-Züge: Paar-Index +
## Kadenz). Kein wählbares Paar (Level zu niedrig) → nur neu planen.
static func _roll_event(
	m: Dictionary, now_ms: int, level: int, game_ids: Array[String]
) -> Dictionary:
	var out := m.duplicate(true)
	var pairs := eligible_pairs(level, str(out.get("lastGameId", "")), game_ids)
	var started := false
	var seed_value := int(_num(out.get("seed")))
	if pairs.size() > 0:
		var pair: Dictionary = pairs[int(floor(rand01(seed_value) * pairs.size()))]
		seed_value = (seed_value + 1) & 0xFFFFFFFF
		var def := _dict(TYPES.get(str(pair["type"])))
		out["current"] = {
			"gameId": str(pair["gameId"]),
			"type": str(pair["type"]),
			"startedAt": now_ms,
			"endsAt": now_ms + WINDOW_MIN * MS_PER_MIN,
			"playsLeft": int(def["plays"]),
		}
		started = true
	var cadence := CADENCE_MIN_LO + rand01(seed_value) * (CADENCE_MIN_HI - CADENCE_MIN_LO)
	seed_value = (seed_value + 1) & 0xFFFFFFFF
	out["seed"] = seed_value
	out["nextAt"] = int(round(float(now_ms) + cadence * MS_PER_MIN))
	return {"m": out, "started": started}


static func _descriptor(cur: Dictionary) -> Dictionary:
	var type_id := str(cur.get("type", ""))
	var def := _dict(TYPES.get(type_id))
	if def.is_empty():
		return {}
	var out := {
		"type": type_id,
		"gameId": str(cur.get("gameId", "")),
		"name_key": str(def["name_key"]),
		"desc_key": str(def["desc_key"]),
		"icon": str(def["icon"]),
		"color": def["color"],
		"remaining_plays": int(_num(cur.get("playsLeft"))),
		"startedAt": int(_num(cur.get("startedAt"))),
		"endsAt": int(_num(cur.get("endsAt"))),
	}
	out.merge(launch_params(cur))
	return out


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant, fallback := 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
