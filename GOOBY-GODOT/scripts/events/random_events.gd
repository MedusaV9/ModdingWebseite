class_name RandomEventEngine
extends RefCounted
## Random-Event-Engine (W3d CONTENT, Doc F §4) — datengetrieben aus dem
## W2b-Pack `content/events` (Domain "events", append-by-id). Ein Event-Def:
##   {id, weight, cooldown_days, trigger_window:["HH:MM","HH:MM"],
##    wahrscheinlichkeit, notification_text_de, timeout_min, fail_text_de,
##    reward:{buff_id,stat,wert,dauer_h}|null, szene_setup, props?}
##
## Die Engine würfelt beim App-Start/Resume (`roll_on_start`), plant die
## lokale Notification über `NotifyStub` (Backend-Merge mit W3a — Handoff)
## und verwaltet Timeout/Fail: verpasste Events zeigen beim nächsten Start
## die Fail-Bubble („Gooby hat es schon alleine hingekommen -_-“).
## Max. 1 aktives Event; Cooldown pro Event-Id in Tagen.
##
## Pure Kern-Statics (Fenster/Cooldown/Roll/Timeout) sind headless testbar —
## Zeit + Zufall werden IMMER hereingereicht (kein OS-Clock-Zugriff hier).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "events"
const MS_PER_MIN := 60_000
const MS_PER_DAY := 86_400_000
const DOMAIN := "events"

static var _registered := false


## Idempotent — MUSS vor GameState.initialize() laufen (frische Saves).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"active": {}, "cooldowns": {}, "failPending": "", "resolvedTotal": 0}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	if not (slice.get("active") is Dictionary):
		slice["active"] = {}
	if not (slice.get("cooldowns") is Dictionary):
		slice["cooldowns"] = {}
	if not (slice.get("failPending") is String):
		slice["failPending"] = ""
	slice["resolvedTotal"] = maxi(0, int(slice.get("resolvedTotal", 0)))
	return slice


## Event-Defs aus der ContentRegistry (leer, wenn Autoload fehlt — Tests
## reichen Defs direkt herein).
static func defs_from_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


# ── pure Kern-Logik ──────────────────────────────────────────────────────────


## "HH:MM" → Minuten seit Mitternacht (-1 bei kaputtem Format).
static func parse_minutes(hhmm: String) -> int:
	var parts := hhmm.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var hours := int(parts[0])
	var minutes := int(parts[1])
	if hours < 0 or hours > 23 or minutes < 0 or minutes > 59:
		return -1
	return hours * 60 + minutes


## Liegt `minutes_of_day` im Fenster? Übernacht-Fenster (22:30→03:00) wrappen.
static func window_contains(window: Array, minutes_of_day: int) -> bool:
	if window.size() != 2:
		return true
	var start := parse_minutes(str(window[0]))
	var end := parse_minutes(str(window[1]))
	if start < 0 or end < 0:
		return true
	if start <= end:
		return minutes_of_day >= start and minutes_of_day <= end
	return minutes_of_day >= start or minutes_of_day <= end


## Ist das Event gerade würfelbar? (Fenster + Cooldown + kein aktives Event.)
static func is_available(
	def: Dictionary, slice: Dictionary, now_ms: int, minutes_of_day: int
) -> bool:
	if not (slice.get("active", {}) as Dictionary).is_empty():
		return false
	if not window_contains(def.get("trigger_window", []), minutes_of_day):
		return false
	var until := int((slice.get("cooldowns", {}) as Dictionary).get(str(def.get("id", "")), 0))
	return now_ms >= until


## Gewichtete Auswahl unter den verfügbaren Defs. `roll_gate` (0..1) prüft die
## Trigger-Wahrscheinlichkeit des Gewinners, `roll_pick` (0..1) wählt nach
## weight. Gibt {} zurück, wenn nichts triggert (beides deterministisch).
static func pick_event(
	defs: Array,
	slice: Dictionary,
	now_ms: int,
	minutes_of_day: int,
	roll_pick: float,
	roll_gate: float
) -> Dictionary:
	var available: Array = []
	var total_weight := 0.0
	for def: Variant in defs:
		if def is Dictionary and is_available(def, slice, now_ms, minutes_of_day):
			available.append(def)
			total_weight += maxf(0.0, float(def.get("weight", 1)))
	if available.is_empty() or total_weight <= 0.0:
		return {}
	var at := clampf(roll_pick, 0.0, 0.999999) * total_weight
	var chosen: Dictionary = available[0]
	for def: Dictionary in available:
		var w := maxf(0.0, float(def.get("weight", 1)))
		if at < w:
			chosen = def
			break
		at -= w
	if roll_gate >= float(chosen.get("wahrscheinlichkeit", 1.0)):
		return {}
	return chosen


## Timeout-Deadline eines aktivierten Events.
static func timeout_deadline(def: Dictionary, started_ms: int) -> int:
	return started_ms + int(maxf(1.0, float(def.get("timeout_min", 8))) * MS_PER_MIN)


static func is_timed_out(active: Dictionary, now_ms: int) -> bool:
	return not active.is_empty() and now_ms >= int(active.get("timeout_ms", 0))


## Cooldown-Ende nach Aktivierung.
static func cooldown_until(def: Dictionary, now_ms: int) -> int:
	return now_ms + int(maxf(0.0, float(def.get("cooldown_days", 1))) * MS_PER_DAY)


# ── GameState-Glue (Store-Signale + Autosave via update()) ───────────────────


## App-Start/Resume: (1) abgelaufenes aktives Event → Fail-Bubble vormerken,
## (2) sonst ggf. neues Event würfeln + Notification planen. Gibt das neu
## aktivierte Def zurück ({} wenn keins).
static func roll_on_start(
	gs: Object, defs: Array, now_ms: int, minutes_of_day: int, rng: RandomNumberGenerator
) -> Dictionary:
	var slice := _slice_of(gs)
	var active: Dictionary = slice.get("active", {})
	if not active.is_empty():
		if is_timed_out(active, now_ms):
			fail_active(gs, defs, now_ms)
		return {}
	var chosen := pick_event(defs, slice, now_ms, minutes_of_day, rng.randf(), rng.randf())
	if chosen.is_empty():
		return {}
	activate(gs, chosen, now_ms)
	return chosen


## Event aktivieren: active-Eintrag + Cooldown + Notification (sofort fällig).
static func activate(gs: Object, def: Dictionary, now_ms: int) -> void:
	var id := str(def.get("id", ""))
	gs.update(
		func(state: Dictionary) -> void:
			var slice: Dictionary = _ensure_slice(state)
			slice["active"] = {
				"id": id,
				"started_ms": now_ms,
				"timeout_ms": timeout_deadline(def, now_ms),
				"szene": str(def.get("szene_setup", "")),
			}
			slice["cooldowns"][id] = cooldown_until(def, now_ms)
	)
	gs.notify_slice_changed(SLICE_ID)
	NotifyStub.schedule_local(
		"event_" + id, "GOOBY", str(def.get("notification_text_de", "")), now_ms
	)


## Aktives Event erfolgreich auflösen: Reward-Buff gewähren + aufräumen.
static func resolve_active(gs: Object, defs: Array, now_ms: int) -> void:
	var def := _active_def(gs, defs)
	if def.is_empty():
		return
	var reward: Variant = def.get("reward")
	gs.update(
		func(state: Dictionary) -> void:
			var slice: Dictionary = _ensure_slice(state)
			slice["active"] = {}
			slice["resolvedTotal"] = int(slice.get("resolvedTotal", 0)) + 1
	)
	gs.notify_slice_changed(SLICE_ID)
	if reward is Dictionary:
		GoobyBuffs.grant(
			gs,
			str(reward.get("buff_id", "buff")),
			str(reward.get("stat", "fun")),
			float(reward.get("wert", 0.0)),
			float(reward.get("dauer_h", 1.0)),
			now_ms
		)
	NotifyStub.cancel_local("event_" + str(def.get("id", "")))


## Aktives Event als verpasst markieren → Fail-Text für die nächste Bubble.
static func fail_active(gs: Object, defs: Array, _now_ms: int) -> void:
	var def := _active_def(gs, defs)
	if def.is_empty():
		return
	gs.update(
		func(state: Dictionary) -> void:
			var slice: Dictionary = _ensure_slice(state)
			slice["active"] = {}
			slice["failPending"] = str(
				def.get("fail_text_de", "Gooby hat es schon alleine hingekommen -_-")
			)
	)
	gs.notify_slice_changed(SLICE_ID)
	NotifyStub.cancel_local("event_" + str(def.get("id", "")))


## Vorgemerkte Fail-Bubble abholen (und löschen). "" = keine.
static func take_fail_notice(gs: Object) -> String:
	var text := str(gs.get_value("events.failPending", ""))
	if text.is_empty():
		return ""
	gs.set_value("events.failPending", "")
	gs.notify_slice_changed(SLICE_ID)
	return text


## Aktueller active-Eintrag ({} wenn keiner).
static func active_of(gs: Object) -> Dictionary:
	var active: Variant = gs.get_value("events.active", {})
	return active if active is Dictionary else {}


static func def_by_id(defs: Array, id: String) -> Dictionary:
	for def: Variant in defs:
		if def is Dictionary and str(def.get("id", "")) == id:
			return def
	return {}


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


static func _slice_of(gs: Object) -> Dictionary:
	var slice: Variant = gs.get_value(SLICE_ID, {})
	return normalize_slice(slice if slice is Dictionary else {})


static func _active_def(gs: Object, defs: Array) -> Dictionary:
	var active := active_of(gs)
	if active.is_empty():
		return {}
	return def_by_id(defs, str(active.get("id", "")))


static func _ensure_slice(state: Dictionary) -> Dictionary:
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = default_slice()
	return normalize_slice(state[SLICE_ID])
