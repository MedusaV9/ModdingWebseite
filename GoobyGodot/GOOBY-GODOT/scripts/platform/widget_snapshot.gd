class_name WidgetSnapshot
extends RefCounted
## iOS-WIDGETS (Snapshot-Builder) — PURE Statics: baut aus dem v5-Save-State
## den Widget-Snapshot fuer Home-Screen-/Lock-Screen-Widgets und den
## Live-Activity-Plan. Zeit, Lokaltag, Zeitzonen-Offset und Uebersetzer
## werden INJIZIERT (AGENTS-Regel: keine OS-Uhr in testbarer Kernlogik).
##
## Der Snapshot ist der EINE Vertrag zwischen Godot und der SwiftUI-Seite
## (ios/widgets/Sources/WidgetSnapshotModel.swift liest exakt diese Keys).
## Alle Texte sind FERTIG lokalisiert (die Widgets laufen ohne Godot und
## koennen keine I18n-Keys aufloesen) — text_fn ist in Produktion
## I18nService.t, in Tests ein deterministischer Fake.
##
## Live-Activity-Anwendungsfaelle (Prioritaet absteigend, EINE Activity):
##  1. "vacation" — Reise-Countdown (away: bis returnAt; returnReady:
##     Abhol-Countdown bis pickupBy). Endet mit der Abholung (phase none).
##  2. "sleep"    — Gooby schlaeft bis wakeAt (Langzeit-Aktion).
##  3. "daily"    — Tagesbonus-Reset-Countdown bis Mitternacht, NUR wenn
##     heute geclaimt UND Serie >= DAILY_LA_MIN_STREAK (schuetzenswerte
##     Serie statt Dauer-Spam).

const Vacation := preload("res://scripts/logic/vacation.gd")
const Stats := preload("res://scripts/logic/stats.gd")
const Sleep := preload("res://scripts/logic/sleep.gd")

## Schema-Version des Snapshots (Swift prueft nur >= 1 und liest defensiv).
const VERSION := 1
## Tagesbonus-Live-Activity erst ab dieser Serie (sonst Daueralarm).
const DAILY_LA_MIN_STREAK := 3
## Stimmungs-Band → Emoji (Swift zeigt es 1:1; Schlaf/Urlaub uebersteuern).
const MOOD_EMOJI := {
	"ecstatic": "🤩",
	"happy": "😊",
	"neutral": "🙂",
	"grumpy": "😕",
	"miserable": "😢",
}
const EMOJI_SLEEP := "😴"
const EMOJI_TRAVEL := "✈️"
const MS_PER_DAY := 86400000


## Der komplette Widget-Snapshot. text_fn: Callable(key, args) -> String.
## quest_pool: DailyQuestCatalog.pool() in Produktion (Tests injizieren).
static func build(
	state: Dictionary,
	now_ms: int,
	local_day: String,
	tz_bias_min: int,
	text_fn: Callable,
	quest_pool: Array = []
) -> Dictionary:
	var nickname := _nickname(state)
	var stats := _stats_of(state)
	var mood_value := Stats.mood(stats)
	var band := _mood_band(mood_value)
	var sleeping := _is_sleeping(state)
	var vac := Vacation.slice_of(state)
	var quests := _quest_counts(state, local_day, quest_pool)
	var daily := _daily_info(state, now_ms, local_day, tz_bias_min)
	return {
		"v": VERSION,
		"generatedAtMs": now_ms,
		"nickname": nickname,
		"coins": int(_num(_dict(state.get("economy")).get("coins"))),
		"stats":
		{
			"hunger": int(round(_num(stats.get("hunger")))),
			"energy": int(round(_num(stats.get("energy")))),
			"hygiene": int(round(_num(stats.get("hygiene")))),
			"fun": int(round(_num(stats.get("fun")))),
		},
		"mood":
		{
			"value": int(round(mood_value)),
			"band": band,
			"emoji": _emoji(band, sleeping, vac),
		},
		"sleep":
		{
			"sleeping": sleeping,
			"wakeAtMs": int(_num(_dict(_dict(state.get("gooby")).get("sleep")).get("wakeAt"))),
		},
		"vacation":
		{
			"phase": str(vac.get("phase", Vacation.PHASE_NONE)),
			"destId": str(vac.get("destId", "")),
			"destName": _dest_name(vac, text_fn),
			"returnAtMs": int(_num(vac.get("returnAt"))),
			"pickupByMs": int(_num(vac.get("pickupBy"))),
		},
		"quests": quests,
		"daily": daily,
		"countdown": _countdown(state, vac, daily, text_fn, nickname),
		"statusText": _status_text(state, now_ms, tz_bias_min, vac, band, stats, text_fn),
	}


## Gewuenschter Live-Activity-Zustand ({} = keine Activity). Felder:
## kind/title/statusText/emoji/startedAtMs/endsAtMs — Swift startet,
## aktualisiert oder beendet die Activity per Abgleich (widget_bridge.gd
## entscheidet start/update/end, hier ist nur der PLAN).
static func live_activity_plan(
	state: Dictionary, now_ms: int, local_day: String, tz_bias_min: int, text_fn: Callable
) -> Dictionary:
	var nickname := _nickname(state)
	var vac := Vacation.slice_of(state)
	var phase := str(vac.get("phase", Vacation.PHASE_NONE))
	if phase == Vacation.PHASE_AWAY:
		var ziel := _dest_name(vac, text_fn)
		return {
			"kind": "vacation",
			"title": text_fn.call("widgets.la.urlaub_titel", {"gooby": nickname, "ziel": ziel}),
			"statusText":
			text_fn.call(
				"widgets.la.urlaub_text",
				{"zeit": format_time(int(_num(vac.get("returnAt"))), tz_bias_min)}
			),
			"emoji": EMOJI_TRAVEL,
			"startedAtMs": int(_num(vac.get("bookedAt"))),
			"endsAtMs": int(_num(vac.get("returnAt"))),
		}
	if phase == Vacation.PHASE_RETURN_READY or phase == Vacation.PHASE_OVERDUE:
		return {
			"kind": "vacation",
			"title": text_fn.call("widgets.la.abholung_titel", {"gooby": nickname}),
			"statusText":
			text_fn.call(
				"widgets.la.abholung_text",
				{"zeit": format_time(int(_num(vac.get("pickupBy"))), tz_bias_min)}
			),
			"emoji": EMOJI_TRAVEL,
			"startedAtMs": int(_num(vac.get("returnAt"))),
			"endsAtMs": int(_num(vac.get("pickupBy"))),
		}
	if _is_sleeping(state):
		var sleep_slice := _dict(_dict(state.get("gooby")).get("sleep"))
		return {
			"kind": "sleep",
			"title": text_fn.call("widgets.la.schlaf_titel", {"gooby": nickname}),
			"statusText":
			text_fn.call(
				"widgets.la.schlaf_text",
				{"zeit": format_time(int(_num(sleep_slice.get("wakeAt"))), tz_bias_min)}
			),
			"emoji": EMOJI_SLEEP,
			"startedAtMs": int(_num(sleep_slice.get("startedAt"))),
			"endsAtMs": int(_num(sleep_slice.get("wakeAt"))),
		}
	var daily := _daily_info(state, now_ms, local_day, tz_bias_min)
	if bool(daily["claimedToday"]) and int(daily["streak"]) >= DAILY_LA_MIN_STREAK:
		return {
			"kind": "daily",
			"title": text_fn.call("widgets.la.bonus_titel", {"tag": int(daily["streak"])}),
			"statusText": text_fn.call("widgets.la.bonus_text", {}),
			"emoji": "🎁",
			"startedAtMs": now_ms,
			"endsAtMs": int(daily["nextResetMs"]),
		}
	return {}


## Epoch-ms der NAECHSTEN lokalen Mitternacht (bias wie
## Time.get_time_zone_from_system().bias, Minuten oestlich von UTC).
static func next_midnight_ms(now_ms: int, tz_bias_min: int) -> int:
	var local_s := int(floor(now_ms / 1000.0)) + tz_bias_min * 60
	var next_local_midnight_s := (int(floor(local_s / 86400.0)) + 1) * 86400
	return (next_local_midnight_s - tz_bias_min * 60) * 1000


## "HH:MM" in Lokalzeit fuer einen Epoch-ms-Stempel (Text-Platzhalter).
static func format_time(ms: int, tz_bias_min: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(floor(ms / 1000.0)) + tz_bias_min * 60)
	return "%02d:%02d" % [int(d["hour"]), int(d["minute"])]


## --- intern ------------------------------------------------------------------


static func _nickname(state: Dictionary) -> String:
	var raw: Variant = _dict(state.get("meta")).get("goobyNickname")
	var name := str(raw).strip_edges() if raw is String else ""
	return name if not name.is_empty() else "Gooby"


static func _stats_of(state: Dictionary) -> Dictionary:
	return Stats.clamp_stats(_dict(_dict(state.get("gooby")).get("stats")))


static func _is_sleeping(state: Dictionary) -> bool:
	return Sleep.is_sleeping({"sleep": _dict(_dict(state.get("gooby")).get("sleep"))})


static func _mood_band(mood_value: float) -> String:
	for entry: Dictionary in Stats.MOOD_BANDS:
		if mood_value >= float(entry["min"]):
			return str(entry["id"])
	return "miserable"


static func _emoji(band: String, sleeping: bool, vac: Dictionary) -> String:
	if str(vac.get("phase", Vacation.PHASE_NONE)) != Vacation.PHASE_NONE:
		return EMOJI_TRAVEL
	if sleeping:
		return EMOJI_SLEEP
	return str(MOOD_EMOJI.get(band, MOOD_EMOJI["neutral"]))


static func _dest_name(vac: Dictionary, text_fn: Callable) -> String:
	var dest_id := str(vac.get("destId", ""))
	if dest_id.is_empty():
		return ""
	return str(text_fn.call("travel.ziel.%s" % dest_id, {}))


## Tagesquest-Zaehler: claimed/complete/claimable nur fuer das HEUTIGE Brett
## (ein Brett von gestern zaehlt 0 — der Roll passiert erst beim App-Start).
static func _quest_counts(state: Dictionary, local_day: String, quest_pool: Array) -> Dictionary:
	var out := {"claimed": 0, "claimable": 0, "total": DailyQuestEngine.QUESTS_PER_DAY}
	var slice := _dict(state.get("quests"))
	if str(slice.get("day", "")) != local_day or not (slice.get("active") is Array):
		return out
	var by_id := DailyQuestEngine.pool_by_id(quest_pool)
	for entry: Variant in slice["active"]:
		if not (entry is Dictionary):
			continue
		if bool((entry as Dictionary).get("claimed", false)):
			out["claimed"] = int(out["claimed"]) + 1
			continue
		var def: Dictionary = by_id.get(str((entry as Dictionary).get("id", "")), {})
		if not def.is_empty() and DailyQuestEngine.is_complete(entry, def, state):
			out["claimable"] = int(out["claimable"]) + 1
	return out


static func _daily_info(
	state: Dictionary, now_ms: int, local_day: String, tz_bias_min: int
) -> Dictionary:
	var daily := _dict(state.get("daily"))
	return {
		"streak": maxi(0, int(_num(daily.get("streak")))),
		"claimedToday": str(daily.get("lastClaimDay", "")) == local_day,
		"nextResetMs": next_midnight_ms(now_ms, tz_bias_min),
	}


## Der EINE Widget-Countdown (Prioritaet: Schlaf > Urlaub > Tagesbonus).
static func _countdown(
	state: Dictionary, vac: Dictionary, daily: Dictionary, text_fn: Callable, nickname: String
) -> Dictionary:
	if _is_sleeping(state):
		var wake_at := int(_num(_dict(_dict(state.get("gooby")).get("sleep")).get("wakeAt")))
		return {
			"kind": "sleepWake",
			"endsAtMs": wake_at,
			"label": str(text_fn.call("widgets.countdown.aufwachen", {"gooby": nickname})),
		}
	var phase := str(vac.get("phase", Vacation.PHASE_NONE))
	if phase == Vacation.PHASE_AWAY:
		return {
			"kind": "vacationReturn",
			"endsAtMs": int(_num(vac.get("returnAt"))),
			"label":
			str(text_fn.call("widgets.countdown.rueckkehr", {"ziel": _dest_name(vac, text_fn)})),
		}
	if phase == Vacation.PHASE_RETURN_READY or phase == Vacation.PHASE_OVERDUE:
		return {
			"kind": "vacationPickup",
			"endsAtMs": int(_num(vac.get("pickupBy"))),
			"label": str(text_fn.call("widgets.countdown.abholung", {})),
		}
	if not bool(daily["claimedToday"]):
		# endsAtMs 0 (nicht now_ms): der Snapshot bleibt zwischen zwei Builds
		# byte-gleich, solange sich nichts aendert (Schreib-Debounce).
		return {
			"kind": "dailyReady",
			"endsAtMs": 0,
			"label": str(text_fn.call("widgets.countdown.tagesbonus_bereit", {})),
		}
	return {
		"kind": "dailyReset",
		"endsAtMs": int(daily["nextResetMs"]),
		"label": str(text_fn.call("widgets.countdown.tagesbonus", {})),
	}


## Statuszeile (deutsch): Schlaf > Urlaub > niedrigster kritischer Stat >
## Stimmung — genau EINE kurze, liebevolle Zeile.
static func _status_text(
	state: Dictionary,
	_now_ms: int,
	tz_bias_min: int,
	vac: Dictionary,
	band: String,
	stats: Dictionary,
	text_fn: Callable
) -> String:
	var nickname := _nickname(state)
	if _is_sleeping(state):
		var wake_at := int(_num(_dict(_dict(state.get("gooby")).get("sleep")).get("wakeAt")))
		return str(
			text_fn.call(
				"widgets.status.schlaeft",
				{"gooby": nickname, "zeit": format_time(wake_at, tz_bias_min)}
			)
		)
	match str(vac.get("phase", Vacation.PHASE_NONE)):
		Vacation.PHASE_AWAY:
			return str(
				text_fn.call(
					"widgets.status.urlaub", {"gooby": nickname, "ziel": _dest_name(vac, text_fn)}
				)
			)
		Vacation.PHASE_RETURN_READY:
			return str(text_fn.call("widgets.status.abholbereit", {"gooby": nickname}))
		Vacation.PHASE_OVERDUE:
			return str(text_fn.call("widgets.status.ueberfaellig", {"gooby": nickname}))
	var low_key := _lowest_low_stat(stats)
	if not low_key.is_empty():
		return str(text_fn.call("widgets.status.%s" % low_key, {"gooby": nickname}))
	var band_keys := {
		"ecstatic": "uebergluecklich",
		"happy": "gluecklich",
		"neutral": "zufrieden",
		"grumpy": "muffelig",
		"miserable": "elend",
	}
	var key := str(band_keys.get(band, "zufrieden"))
	return str(text_fn.call("widgets.status.%s" % key, {"gooby": nickname}))


## Der niedrigste Stat unter der LOW-Schwelle (Text-Key) oder "".
static func _lowest_low_stat(stats: Dictionary) -> String:
	var keys := {"hunger": "hunger", "energy": "muede", "hygiene": "dreckig", "fun": "gelangweilt"}
	var lowest := ""
	var lowest_value := Stats.LOW_STAT
	for stat_key: String in Stats.KEYS:
		var value := _num(stats.get(stat_key))
		if value < lowest_value:
			lowest_value = value
			lowest = str(keys[stat_key])
	return lowest


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
