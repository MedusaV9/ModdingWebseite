class_name RecapEngine
extends RefCounted
## Recap-Engine (FIX-4) — PURER Port des Web-Moduls systems/recap.js
## (PLAN4 §B5/§C-SYS2): Baseline-Snapshots, Delta-Statzeilen (18er-Katalog),
## ≤-12-Zeilen-Auswahl, Meilenstein-Mathematik (Level 5,10,…,40), Beat-Raster
## und der atomare Abschluss (History-Zeile, Baseline-Reset).
## KEINE Node-/Szenen-Abhängigkeiten — headless voll testbar.
##
## Save-Slice (additiv im bestehenden `recap`-Slice, KEIN Version-Bump —
## merge_defaults übernimmt unbekannte Keys verbatim):
##   recap: { history: [],            # ≤ 8 Zeilen {level, at, stats}
##            lastRecapLevel: 0, baseline: {}, baselineAt: 0, pendingLevel: 0 }
## Godot-Pfad-Mapping (Web → save v5): level→progression.level,
## coinsEarned/Spent→economy.*, distanceM/photos→profile.*,
## playsTotal→Σ minigames.plays, Zähler→achievements.counters,
## stickerCount→|stickers.unlocked|.

## Web-RECAP-Konstanten (verbatim; nur Namen nach GDScript-Konvention).
const MILESTONE_STEP := 5
const FIRST_MILESTONE := 5
const LAST_MILESTONE := 40
const HISTORY_MAX := 8
const MAX_LINES := 12
const TOP_LINES := 11
const MIN_LENGTH_SEC := 60.0
const MAX_LENGTH_SEC := 120.0
const INTRO_SEC := 4.0
const END_CARD_SEC := 14.0
const VIGNETTES := 8
const SKIP_AFTER_SEC := 10.0
const END_CARD_MIN_SEC := 3.0
const TEXT_POP_BEATS := 2
const TEXT_ROLLUP_BEATS := 2
const CONFETTI_BEATS := 4
const DEFAULT_GRID := {"bpm": 100.0, "offset_sec": 0.0, "beats_per_bar": 4}
const WEIGHT_ALWAYS_FIRST := 999
const DAY_MS := 86400000.0

## Der bindende 18-Zeilen-Katalog (§C-SYS2.4) — Reihenfolge = Katalog-Ordnung
## und deterministischer Tie-Breaker. Texte: strings/*/recap.json
## (`recap.stat.<id>` mit {n}; Singular `recap.stat.<id>_one` nur bei days).
const STAT_CATALOG := [
	{"id": "days", "weight": WEIGHT_ALWAYS_FIRST},
	{"id": "games", "weight": 10},
	{"id": "coinsEarned", "weight": 9},
	{"id": "tickles", "weight": 9},
	{"id": "feeds", "weight": 8},
	{"id": "harvests", "weight": 8},
	{"id": "stickers", "weight": 8},
	{"id": "quests", "weight": 7},
	{"id": "washes", "weight": 6},
	{"id": "sleeps", "weight": 6},
	{"id": "trips", "weight": 6},
	{"id": "distance", "weight": 5},
	{"id": "photos", "weight": 5},
	{"id": "deliveries", "weight": 4},
	{"id": "cures", "weight": 4},
	{"id": "cakes", "weight": 4},
	{"id": "nougat", "weight": 3},
	{"id": "coinsSpent", "weight": 3},
]

## Zeilen-Id → Snapshot-Key (beide Seiten gediffed, ≥ 0 geklemmt).
const LINE_SOURCE := {
	"games": "playsTotal",
	"coinsEarned": "coinsEarned",
	"tickles": "tickles",
	"feeds": "feeds",
	"harvests": "harvests",
	"stickers": "stickerCount",
	"quests": "questsDone",
	"washes": "washes",
	"sleeps": "sleeps",
	"trips": "trips",
	"distance": "distanceM",
	"photos": "photos",
	"deliveries": "deliveries",
	"cures": "cures",
	"cakes": "cakesServed",
	"nougat": "nougatGlobs",
	"coinsSpent": "coinsSpent",
}

## Zähler-Keys VERBATIM aus achievements.counters (§C-SYS2.4).
const SNAPSHOT_COUNTERS := [
	"feeds",
	"washes",
	"sleeps",
	"tickles",
	"trips",
	"harvests",
	"plantings",
	"waterings",
	"questsDone",
	"deliveries",
	"cures",
	"nougatGlobs",
	"cakesServed",
	"surfRuns",
]


## Der volle recap-Slice mit Defaults über einem rohen Slice (additiv —
## vorhandene Werte bleiben, fehlende Keys werden ergänzt).
static func slice_of(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("recap")
	var slice: Dictionary = raw if raw is Dictionary else {}
	var out := {
		"lastRecapLevel": maxi(0, int(_num(slice.get("lastRecapLevel")))),
		"baseline": slice.get("baseline") if slice.get("baseline") is Dictionary else {},
		"baselineAt": maxf(0.0, _num(slice.get("baselineAt"))),
		"pendingLevel": maxi(0, int(_num(slice.get("pendingLevel")))),
		"history": slice.get("history") if slice.get("history") is Array else [],
	}
	return out


## §B1-#3-Retro-Safety: höchster Meilenstein ≤ level (L23 → 20, L4 → 0).
static func initial_last_recap_level(level: int) -> int:
	var l := clampi(level, 0, LAST_MILESTONE)
	@warning_ignore("integer_division")
	return (l / MILESTONE_STEP) * MILESTONE_STEP


static func highest_milestone(level: int) -> int:
	return initial_last_recap_level(level)


## §C-SYS2.4-Baseline-Snapshot aus dem Save-State (Godot-Pfade, s. Header).
## Kaputte/fehlende Eingaben snapshoten als 0 — nie negative Zeilen.
static func snapshot(state: Dictionary, now_ms: float) -> Dictionary:
	var economy: Dictionary = _dict(state.get("economy"))
	var profile: Dictionary = _dict(state.get("profile"))
	var counters: Dictionary = _dict(_dict(state.get("achievements")).get("counters"))
	var plays: Dictionary = _dict(_dict(state.get("minigames")).get("plays"))
	var plays_total := 0.0
	for v: Variant in plays.values():
		plays_total += _num(v)
	var unlocked: Dictionary = _dict(_dict(state.get("stickers")).get("unlocked"))
	var level := int(_num(_dict(state.get("progression")).get("level")))
	var out := {
		"snapshotAtMs": maxf(0.0, now_ms),
		"level": maxi(1, level),
		"coinsEarned": _num(economy.get("coinsEarned")),
		"coinsSpent": _num(economy.get("coinsSpent")),
		"distanceM": _num(profile.get("distanceM")),
		"photos": _num(profile.get("photos")),
		"playsTotal": plays_total,
		"stickerCount": float(unlocked.size()),
	}
	for k: String in SNAPSHOT_COUNTERS:
		out[k] = _num(counters.get(k))
	return out


## Baseline vs. JETZT → geordnete Statzeilen [{id, value, weight}] in
## Katalog-Ordnung, days zuerst. Deltas = current − baseline, ≥ 0 geklemmt.
## days = ⌈(now − baselineAt)/86 400 000⌉, min. 1.
static func diff(baseline: Dictionary, state: Dictionary, now_ms: float) -> Array:
	var cur := snapshot(state, now_ms)
	var base_at := _num(baseline.get("snapshotAtMs", baseline.get("baselineAt")))
	var days := 1
	if base_at > 0.0:
		days = maxi(1, int(ceilf(maxf(0.0, now_ms - base_at) / DAY_MS)))
	var lines: Array = []
	for row: Dictionary in STAT_CATALOG:
		var id := str(row["id"])
		if id == "days":
			lines.append({"id": "days", "value": days, "weight": row["weight"]})
			continue
		var key := str(LINE_SOURCE[id])
		var value := maxi(0, roundi(_num(cur[key])) - roundi(_num(baseline.get(key))))
		lines.append({"id": id, "value": value, "weight": row["weight"]})
	return lines


## §C-SYS2.5-Auswahl: days immer zuerst, dann die Top-11 NICHT-Null-Zeilen
## nach (weight desc, value desc, Katalog-Ordnung) → ≤ 12 Zeilen.
static func select_lines(diff_lines: Array) -> Array:
	var order := {}
	for i in STAT_CATALOG.size():
		order[STAT_CATALOG[i]["id"]] = i
	var days: Dictionary = {"id": "days", "value": 1, "weight": WEIGHT_ALWAYS_FIRST}
	var rest: Array = []
	for line: Variant in diff_lines:
		if not (line is Dictionary):
			continue
		var row: Dictionary = line
		if str(row.get("id")) == "days":
			days = row
		elif order.has(row.get("id")) and _num(row.get("value")) > 0.0:
			rest.append(row)
	rest.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["weight"]) != int(b["weight"]):
				return int(a["weight"]) > int(b["weight"])
			if int(a["value"]) != int(b["value"]):
				return int(a["value"]) > int(b["value"])
			return int(order[a["id"]]) < int(order[b["id"]])
	)
	var out: Array = [days]
	out.append_array(rest.slice(0, TOP_LINES))
	return out


## Eine Statzeile rendern ({n}-Template aus strings/*/recap.json; days-
## Singular über `recap.stat.days_one`). "" bei unbekannter Id.
static func format_line(id: String, value: int) -> String:
	if not LINE_SOURCE.has(id) and id != "days":
		return ""
	var n := maxi(0, value)
	var one_key := "recap.stat.%s_one" % id
	if n == 1 and I18nService.has_key(one_key):
		return I18nService.t(one_key)
	return I18nService.t("recap.stat.%s" % id, {"n": n})


## Meilenstein-Mathematik (§B5.1): der NIEDRIGSTE offene 5er-Meilenstein,
## den prev→next überquert (oder unterhalb next noch schuldet), in [5, 40].
## 0 = nichts fällig. Bei Mehrfach-Sprüngen wird der niedrigste gemerkt.
static func milestone_crossed(prev_level: int, new_level: int, last_recap_level := -1) -> int:
	var prev := maxi(0, prev_level)
	var next := maxi(0, new_level)
	var last := last_recap_level if last_recap_level >= 0 else initial_last_recap_level(prev)
	if next <= last:
		return 0
	@warning_ignore("integer_division")
	var candidate := maxi(FIRST_MILESTONE, (last / MILESTONE_STEP + 1) * MILESTONE_STEP)
	if candidate <= last:
		return 0
	if candidate > mini(next, LAST_MILESTONE):
		return 0
	return candidate


## §B5.2 atomarer Abschluss (pur — NEUER Slice, State unangetastet):
## History-Zeile {level, at, stats} anhängen (Kappe 8), lastRecapLevel auf
## den HÖCHSTEN überschrittenen Meilenstein, Baseline neu, pending löschen.
## played_lines = die tatsächlich gezeigten Zeilen (sonst neu berechnet).
static func complete_recap(
	state: Dictionary, now_ms: float, played_lines: Array = []
) -> Dictionary:
	var prev := slice_of(state)
	var level := maxi(1, int(_num(_dict(state.get("progression")).get("level"))))
	var played := maxi(
		maxi(int(prev["pendingLevel"]), highest_milestone(level)), int(prev["lastRecapLevel"])
	)
	var lines := played_lines
	if lines.is_empty():
		lines = select_lines(diff(prev["baseline"], state, now_ms))
	var stats: Array = []
	for line: Variant in lines:
		if line is Dictionary:
			stats.append(
				{"id": str(line.get("id")), "value": maxi(0, roundi(_num(line.get("value"))))}
			)
	var entry := {"level": played, "at": now_ms, "stats": stats}
	var history: Array = (prev["history"] as Array).duplicate()
	history.append(entry)
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	var recap := {
		"lastRecapLevel": played,
		"baseline": snapshot(state, now_ms),
		"baselineAt": now_ms,
		"pendingLevel": 0,
		"history": history,
	}
	return {"recap": recap, "entry": entry}


# ── Beat-Raster (§B5.3 → §C-SYS2.6-Cue-Skelett) ──────────────────────────────


## Beat-Manifest normalisieren (Default-Grid als Feld-für-Feld-Fallback).
static func resolve_beats(beats: Dictionary) -> Dictionary:
	var bpm := _num(beats.get("bpm"))
	var offset := _num(beats.get("offset_sec", beats.get("offsetSec")))
	if beats.has("offset_ms") and not beats.has("offset_sec"):
		offset = _num(beats.get("offset_ms")) / 1000.0
	var bpb := int(_num(beats.get("beats_per_bar", beats.get("beatsPerBar"))))
	return {
		"bpm": bpm if bpm >= 30.0 and bpm <= 300.0 else float(DEFAULT_GRID["bpm"]),
		"offset_sec":
		offset if offset >= 0.0 and offset < 60.0 else float(DEFAULT_GRID["offset_sec"]),
		"beats_per_bar": bpb if bpb >= 2 and bpb <= 8 else int(DEFAULT_GRID["beats_per_bar"]),
	}


## §B5.1 beat_grid(beats, duration) → Cue-SKELETT auf dem Takt-Raster:
## 8 `cut`-Cues auf GERADEN Takten (monotonisch, erster ≥ Takt 2), `text`-
## Slots (≤ 2 pro Vignette + 1 Intro-Slot auf Takt 1), EIN `end`-Cue.
static func beat_grid(beats: Dictionary, duration_sec: float) -> Dictionary:
	var g := resolve_beats(beats)
	var dur := duration_sec if duration_sec > 0.0 else 100.0
	var total := clampf(dur, MIN_LENGTH_SEC, MAX_LENGTH_SEC)
	var beat_sec := 60.0 / float(g["bpm"])
	var bar_sec := float(g["beats_per_bar"]) * beat_sec
	var offset := float(g["offset_sec"])
	var vig_sec := (total - INTRO_SEC - END_CARD_SEC) / float(VIGNETTES)
	var cues: Array = []
	cues.append({"t": offset + bar_sec, "bar": 1, "kind": "text", "vignette": -1})
	var prev_bar := 0
	var cut_bars: Array[int] = []
	for i in VIGNETTES:
		var ideal := INTRO_SEC + float(i) * vig_sec
		var bar := maxi(prev_bar + 2, _even_bar_near(ideal, offset, bar_sec))
		cut_bars.append(bar)
		cues.append({"t": offset + bar * bar_sec, "bar": bar, "kind": "cut", "vignette": i})
		prev_bar = bar
	var end_bar := maxi(prev_bar + 2, _even_bar_near(total - END_CARD_SEC, offset, bar_sec))
	for i in VIGNETTES:
		var from := cut_bars[i]
		var until := cut_bars[i + 1] if i + 1 < VIGNETTES else end_bar
		if from + 1 < until:
			cues.append(
				{"t": offset + (from + 1) * bar_sec, "bar": from + 1, "kind": "text", "vignette": i}
			)
		var second := 0
		if from + 3 < until:
			second = from + 3
		elif from + 2 < until:
			second = from + 2
		if second > from + 1:
			cues.append(
				{"t": offset + second * bar_sec, "bar": second, "kind": "text", "vignette": i}
			)
	cues.append({"t": offset + end_bar * bar_sec, "bar": end_bar, "kind": "end"})
	cues.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["t"] != b["t"]:
				return float(a["t"]) < float(b["t"])
			return str(a["kind"]) == "cut" and str(b["kind"]) != "cut"
	)
	return {
		"bpm": g["bpm"],
		"beats_per_bar": g["beats_per_bar"],
		"offset_sec": offset,
		"bar_sec": bar_sec,
		"beat_sec": beat_sec,
		"total_sec": total,
		"cues": cues,
	}


static func _even_bar_near(t: float, offset: float, bar_sec: float) -> int:
	return maxi(0, 2 * roundi((t - offset) / (2.0 * bar_sec)))


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


## Web-`num()`: endliche Zahl > 0, sonst 0 (keine String-Koerzierung).
static func _num(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f > 0.0:
			return f
	return 0.0
