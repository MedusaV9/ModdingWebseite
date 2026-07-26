class_name RecapDirector
extends RefCounted
## Recap-Director (FIX-4) — PURER Timeline-Bauer, Port des Web-Moduls
## systems/recapDirector.js: Beat-Raster + Statzeilen + Stationen →
## kompletter Cue-Zeitplan, den recap_scene.gd rendert. Deterministisch:
## gleiche Eingaben → identischer Output (headless testbar).
##
## Godot-Abweichung zur Web-Version (bewusst, User-Wunsch): statt der acht
## Fantasy-Biome fährt die Kamera durch die STATIONEN von Goobys Tag/Woche —
## die tatsächlich erreichten Orte aus dem GameState (Zuhause immer, Garten
## ab 1 Ernte/Pflanzung, Stadt ab 1 Ausflug, Arcade ab 1 Spiel, Urlaub nach
## der ersten Reise, ...). Fehlende Belege werden mit den Grund-Stationen
## aufgefüllt, es sind IMMER genau 8 (Web: Biome zyklisch).

## Stations-Katalog: id → Label-Key (strings/*/recap.json), Wallpaper-Pattern
## (AcWallpaper, assets/ui/patterns), Gooby-Clip + Emotion (GoobyRig-Namen).
const STATION_CATALOG := {
	"home":
	{"label_key": "recap.station.home", "pattern": "leaves", "clip": "wave", "emotion": "happy"},
	"kitchen":
	{"label_key": "recap.station.kitchen", "pattern": "dots", "clip": "sit", "emotion": "happy"},
	"garden":
	{"label_key": "recap.station.garden", "pattern": "leaves", "clip": "hop", "emotion": "happy"},
	"city":
	{"label_key": "recap.station.city", "pattern": "dots", "clip": "walk", "emotion": "neutral"},
	"shop":
	{
		"label_key": "recap.station.shop",
		"pattern": "shop",
		"clip": "idle_lookaround",
		"emotion": "happy",
	},
	"arcade":
	{
		"label_key": "recap.station.arcade",
		"pattern": "arcade",
		"clip": "celebrate",
		"emotion": "ecstatic",
	},
	"park":
	{"label_key": "recap.station.park", "pattern": "trophy", "clip": "hop", "emotion": "ecstatic"},
	"vacation":
	{
		"label_key": "recap.station.vacation",
		"pattern": "passport",
		"clip": "wave",
		"emotion": "ecstatic",
	},
	"bath":
	{
		"label_key": "recap.station.bath",
		"pattern": "dots",
		"clip": "brush_teeth",
		"emotion": "happy",
	},
	"night":
	{"label_key": "recap.station.night", "pattern": "dots", "clip": "sleep", "emotion": "sleepy"},
}

## Grund-Reise ohne Belege: ein ruhiger Tag daheim.
const BASE_STATION_IDS: Array[String] = [
	"home", "kitchen", "garden", "bath", "city", "shop", "arcade", "night"
]


## Die 8 Stationen des Tages/der Woche aus dem Save-State: belegte Orte
## zuerst (Reihenfolge eines Gooby-Tages), aufgefüllt mit BASE_STATION_IDS.
static func stations_for(state: Dictionary) -> Array:
	var counters: Dictionary = _dict(_dict(state.get("achievements")).get("counters"))
	var plays: Dictionary = _dict(_dict(state.get("minigames")).get("plays"))
	var park: Dictionary = _dict(state.get("park"))
	var vacation: Dictionary = _dict(state.get("vacation"))
	var picked: Array = ["home"]
	if _n(counters.get("feeds")) > 0.0:
		picked.append("kitchen")
	if _n(counters.get("harvests")) + _n(counters.get("plantings")) > 0.0:
		picked.append("garden")
	if _n(counters.get("washes")) > 0.0:
		picked.append("bath")
	if _n(counters.get("trips")) > 0.0:
		picked.append("city")
	if (
		_n(counters.get("deliveries")) > 0.0
		or _n(_dict(state.get("economy")).get("coinsSpent")) > 0.0
	):
		picked.append("shop")
	if not plays.is_empty():
		picked.append("arcade")
	if _n(park.get("visits")) > 0.0:
		picked.append("park")
	if str(vacation.get("phase", "")) not in ["", "none"] or _n(vacation.get("tripsDone")) > 0.0:
		picked.append("vacation")
	if _n(counters.get("sleeps")) > 0.0:
		picked.append("night")
	for id: String in BASE_STATION_IDS:
		if picked.size() >= RecapEngine.VIGNETTES:
			break
		if not picked.has(id):
			picked.append(id)
	# night immer als Finale, wenn dabei — der Tag endet im Bett.
	if picked.has("night"):
		picked.erase("night")
		picked = picked.slice(0, RecapEngine.VIGNETTES - 1)
		picked.append("night")
	else:
		picked = picked.slice(0, RecapEngine.VIGNETTES)
	var out: Array = []
	for id: String in picked:
		var row: Dictionary = (STATION_CATALOG[id] as Dictionary).duplicate()
		row["id"] = id
		out.append(row)
	return out


## mulberry32-PRNG-Port — deterministischer 0..1-Strom aus uint32-Seed.
## Web pickTrack: zufälliger Recap-Track, gleicher Seed → gleiche Wahl.
static func pick_track(track_ids: Array, seed_value: int) -> String:
	var ids: Array[String] = []
	for id: Variant in track_ids:
		if id is String and not (id as String).is_empty():
			ids.append(id)
	if ids.is_empty():
		return ""
	var a := seed_value & 0xFFFFFFFF
	a = (a + 0x6D2B79F5) & 0xFFFFFFFF
	var t := (a ^ (a >> 15)) * (a | 1) & 0xFFFFFFFF
	t = (t + ((t ^ (t >> 7)) * (t | 61) & 0xFFFFFFFF)) ^ t
	t = t & 0xFFFFFFFF
	var rnd := float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
	return ids[int(rnd * ids.size()) % ids.size()]


## Kompletter Cue-Zeitplan (Kontrakt s. Web-Header): mapped die
## select_lines()-Zeilen aufs beat_grid()-Skelett — Zeile 1 (days) auf den
## Intro-Slot, der Rest Round-Robin (≤ 2 pro Vignette, Pass 1 zuerst).
static func build_timeline(opts: Dictionary) -> Dictionary:
	var beats: Dictionary = _dict(opts.get("beats"))
	var duration_sec := float(opts.get("duration_sec", 100.0))
	var grid := RecapEngine.beat_grid(beats, duration_sec)
	var stations: Array = opts.get("stations", []) if opts.get("stations") is Array else []
	if stations.is_empty():
		for id: String in BASE_STATION_IDS:
			var row: Dictionary = (STATION_CATALOG[id] as Dictionary).duplicate()
			row["id"] = id
			stations.append(row)
	var rows: Array = []
	var raw_lines: Array = opts.get("lines", []) if opts.get("lines") is Array else []
	for line: Variant in raw_lines:
		if line is Dictionary and (line as Dictionary).get("id") is String:
			rows.append(line)
		if rows.size() >= RecapEngine.MAX_LINES:
			break
	var days: Variant = null
	var rest: Array = []
	for row: Dictionary in rows:
		if str(row["id"]) == "days" and days == null:
			days = row
		else:
			rest.append(row)

	var intro_slots: Array = []
	var vignette_slots: Dictionary = {}
	for cue: Dictionary in grid["cues"]:
		if str(cue["kind"]) != "text":
			continue
		var v := int(cue.get("vignette", -1))
		if v == -1:
			intro_slots.append(cue)
		else:
			if not vignette_slots.has(v):
				vignette_slots[v] = []
			(vignette_slots[v] as Array).append(cue)

	var placed: Array = []
	var li := 0
	for pass_i in 2:
		for v in RecapEngine.VIGNETTES:
			if li >= rest.size():
				break
			var slots: Array = vignette_slots.get(v, [])
			if pass_i < slots.size():
				placed.append({"slot": slots[pass_i], "line": rest[li]})
				li += 1

	var cues: Array = []
	var first_cut_t := float(grid["total_sec"])
	var end_cue: Dictionary = {}
	for cue: Dictionary in grid["cues"]:
		match str(cue["kind"]):
			"cut":
				var vi := int(cue["vignette"])
				if vi == 0:
					first_cut_t = float(cue["t"])
				(
					cues
					. append(
						{
							"t": cue["t"],
							"bar": cue["bar"],
							"kind": "cut",
							"vignette": vi,
							"station": stations[vi % stations.size()],
						}
					)
				)
			"end":
				end_cue = {
					"t": cue["t"],
					"bar": cue["bar"],
					"kind": "end",
					"confetti_beats": RecapEngine.CONFETTI_BEATS,
				}
				cues.append(end_cue)
	if days != null and not intro_slots.is_empty():
		cues.append(_text_cue(intro_slots[0], days))
	for hit: Dictionary in placed:
		cues.append(_text_cue(hit["slot"], hit["line"]))
	cues.append({"t": 0.0, "bar": 0, "kind": "intro", "dur_sec": first_cut_t})
	cues.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["t"] != b["t"]:
				return float(a["t"]) < float(b["t"])
			if a["bar"] != b["bar"]:
				return int(a["bar"]) < int(b["bar"])
			return str(a["kind"]) < str(b["kind"])
	)

	if end_cue.is_empty():
		end_cue = {"t": grid["total_sec"], "bar": 0}
	return {
		"v": 1,
		"level": maxi(0, int(opts.get("level", 0))),
		"track_id": str(opts.get("track_id", "")),
		"duration_sec": duration_sec,
		"total_sec": grid["total_sec"],
		"bpm": grid["bpm"],
		"beats_per_bar": grid["beats_per_bar"],
		"offset_sec": grid["offset_sec"],
		"bar_sec": grid["bar_sec"],
		"beat_sec": grid["beat_sec"],
		"skip_after_sec": RecapEngine.SKIP_AFTER_SEC,
		"end_card":
		{
			"t": end_cue["t"],
			"bar": end_cue["bar"],
			"min_show_sec": RecapEngine.END_CARD_MIN_SEC,
			"confetti_beats": RecapEngine.CONFETTI_BEATS,
		},
		"cues": cues,
	}


static func _text_cue(slot: Dictionary, line: Dictionary) -> Dictionary:
	var value := maxi(0, roundi(float(line.get("value", 0))))
	return {
		"t": slot["t"],
		"bar": slot["bar"],
		"kind": "text",
		"vignette": int(slot.get("vignette", -1)),
		"line_id": str(line["id"]),
		"value": value,
		"text": RecapEngine.format_line(str(line["id"]), value),
		"pop_beats": RecapEngine.TEXT_POP_BEATS,
		"rollup_beats": RecapEngine.TEXT_ROLLUP_BEATS,
	}


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _n(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if is_finite(f) and f > 0.0:
			return f
	return 0.0
