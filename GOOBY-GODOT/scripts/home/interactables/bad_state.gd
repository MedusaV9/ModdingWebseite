class_name BadState
extends RefCounted
## Bad-Suite-Zustand (W3d CONTENT, Doc F §3.2): eigener Save-Slice "bad" via
## W1d-Slice-Registry (der `gooby`-Slice ist FROZEN). Pure Timer-Logik für
## Klo-Bedürfnis, Zähneputz-Pflicht und Duschvorhang-Peek — Zeit wird immer
## hereingereicht (headless testbar).
##
## Slice: {kloLastMs, needsBrushing, brushBrokenCount, lights{uid:bool},
##         showerStartedMs}

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SLICE_ID := "bad"
## Klo-Bedürfnis: von 0 auf 1 in 4 Stunden.
const KLO_FULL_MS := 4 * 3_600_000
## Duschvorhang-Peek nach 45 s Sitzenlassen (Doc F §3.2).
const SHOWER_PEEK_MS := 45_000
## Zahnputz-Rubbelgeste: 5 s Coverage.
const BRUSH_RUB_S := 5.0
## Fallback, wenn die ContentRegistry den Balance-Key nicht liefert.
const BRUSH_BREAK_CHANCE_FALLBACK := 0.02

static var _registered := false


## Idempotent — MUSS vor GameState.initialize() laufen (frische Saves).
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {
		"kloLastMs": 0,
		"needsBrushing": false,
		"brushBrokenCount": 0,
		"lights": {},
		"showerStartedMs": 0,
	}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	slice["kloLastMs"] = maxi(0, int(slice.get("kloLastMs", 0)))
	slice["needsBrushing"] = _truthy(slice.get("needsBrushing"))
	slice["brushBrokenCount"] = maxi(0, int(slice.get("brushBrokenCount", 0)))
	if not (slice.get("lights") is Dictionary):
		slice["lights"] = {}
	var lights: Dictionary = slice["lights"]
	for uid: Variant in lights.keys():
		lights[uid] = _truthy(lights[uid])
	slice["showerStartedMs"] = maxi(0, int(slice.get("showerStartedMs", 0)))
	return slice


# ── pure Timer-Logik ─────────────────────────────────────────────────────────


## Klo-Bedürfnis 0..1 (0 = gerade gewesen, 1 = MUSS).
static func klo_need01(last_ms: int, now_ms: int) -> float:
	if last_ms <= 0:
		return 0.0
	return clampf(float(now_ms - last_ms) / float(KLO_FULL_MS), 0.0, 1.0)


## Ist der Klo-Gang fällig?
static func klo_due(last_ms: int, now_ms: int) -> bool:
	return last_ms > 0 and klo_need01(last_ms, now_ms) >= 1.0


## Duschvorhang-Peek fällig? (Gooby sitzt seit started_ms hinterm Vorhang.)
static func shower_peek_due(started_ms: int, now_ms: int) -> bool:
	return started_ms > 0 and now_ms - started_ms >= SHOWER_PEEK_MS


## Bricht die Zahnbürste? roll01 ∈ [0..1) gegen die Balance-Chance.
static func brush_breaks(roll01: float, chance: float) -> bool:
	return roll01 < clampf(chance, 0.0, 1.0)


# ── GameState-Glue ───────────────────────────────────────────────────────────


## Balance-Chance aus der W2b-ContentRegistry (Fallback, wenn Autoload fehlt).
static func brush_break_chance() -> float:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
		if registry != null and registry.has_method("get_balance"):
			return float(
				registry.get_balance("zahnbuersten_bruch_chance", BRUSH_BREAK_CHANCE_FALLBACK)
			)
	return BRUSH_BREAK_CHANCE_FALLBACK


## Nach dem Aufwachen: Zähneputzen wird Pflicht (Doc F §3.2).
static func mark_woke_up(gs: Object) -> void:
	_write(gs, "needsBrushing", true)


## Zähne geputzt: Pflicht weg, Counter hoch (Sticker-Signal), Buff kommt vom
## Aufrufer (zahnputz.gd). broke=true zählt den Bürsten-Bruch.
static func mark_brushed(gs: Object, broke: bool) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var slice := _ensure(state)
			slice["needsBrushing"] = false
			if broke:
				slice["brushBrokenCount"] = int(slice.get("brushBrokenCount", 0)) + 1
			var counters: Variant = state.get("achievements", {}).get("counters")
			if counters is Dictionary:
				counters["teeth_brushed"] = int(counters.get("teeth_brushed", 0)) + 1
	)
	gs.notify_slice_changed(SLICE_ID)
	gs.notify_slice_changed("achievements")


static func needs_brushing(gs: Object) -> bool:
	return bool(gs.get_value("bad.needsBrushing", false))


## Klo-Gang erledigt → Timer neu.
static func mark_klo_done(gs: Object, now_ms: int) -> void:
	_write(gs, "kloLastMs", now_ms)


## Klo-Timer starten, falls noch nie gesetzt (Erstkontakt mit dem Bad).
static func ensure_klo_timer(gs: Object, now_ms: int) -> void:
	if int(gs.get_value("bad.kloLastMs", 0)) <= 0:
		_write(gs, "kloLastMs", now_ms)


static func set_shower_started(gs: Object, started_ms: int) -> void:
	_write(gs, "showerStartedMs", started_ms)


## Lampen-Zustand pro Möbel-uid (true = an; Default an).
static func light_on(gs: Object, uid: String) -> bool:
	var lights: Variant = gs.get_value("bad.lights", {})
	if lights is Dictionary and lights.has(uid):
		return _truthy(lights[uid])
	return true


static func set_light_on(gs: Object, uid: String, on: bool) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var slice := _ensure(state)
			slice["lights"][uid] = on
	)
	gs.notify_slice_changed(SLICE_ID)


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


static func _write(gs: Object, key: String, value: Variant) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var slice := _ensure(state)
			slice[key] = value
	)
	gs.notify_slice_changed(SLICE_ID)


static func _ensure(state: Dictionary) -> Dictionary:
	if not (state.get(SLICE_ID) is Dictionary):
		state[SLICE_ID] = default_slice()
	state[SLICE_ID] = normalize_slice(state[SLICE_ID])
	return state[SLICE_ID]


## Typ-sicheres „ist wirklich true“ (String == bool ist in GDScript 4 ein
## Laufzeitfehler — feindliche Saves dürfen hier nicht crashen).
static func _truthy(value: Variant) -> bool:
	return value is bool and value
