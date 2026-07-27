extends Node
## GameState (W1d/STATE) — zentraler Store, Autoload-KANDIDAT unter
## /root/GameState (Anmeldung: /tmp/gooby-godot/handoffs/W1d-autoload-requests.md).
##
## API-Kontrakt (EINGEFROREN — /tmp/gooby-godot/handoffs/W1d-state-api.md):
## - Lesen:      get_value("economy.coins"), state() (Direktreferenz, nur lesen)
## - Schreiben:  set_value(path, value)  ODER  update(func(s): ...) — beides
##   diff't die beobachteten Werte und emittiert die Signale unten; Autosave
##   ist debounced (save_manager.gd), flush bei Quit/Pause.
## - Signale wie im Web-store.js: coins_changed / stats_changed /
##   level_changed(level, xp_ratio) / vacation_changed + generisches
##   slice_changed(slice_id, data) via notify_slice_changed().
##
## W1c-Kopplung (W1c-needs-from-state.md): apply_onboarding_profile(profile)
## nimmt exakt das onboarding_flow.gd-`completed`-Payload; mark_news_50_seen()
## persistiert das 5.0-News-Flag.

signal state_loaded(fresh: bool, recovered: bool)
signal coins_changed(coins: int)
signal stats_changed(stats: Dictionary)
signal level_changed(level: int, xp_ratio: float)
signal xp_changed(xp: float)
signal vacation_changed(phase: String, dest_id: String)
signal slice_changed(slice_id: String, data: Variant)
## BUGHUNT-P1: Web-Eventstrings aus Offline-Catchup/Live-Tick ("wokeUp",
## "statLow:<stat>", "vacationPostcard", ...) — UI-Konsumenten (Toasts)
## hängen sich hier an.
signal gooby_events(events: Array)

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SaveManager := preload("res://scripts/state/save_manager.gd")
const Clock := preload("res://scripts/logic/clock.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")
const GoobyTicker := preload("res://scripts/state/gooby_ticker.gd")

## BUGHUNT-P1: Intervall des Live-Ticks in Sekunden (Web: 5-s-Loop in
## main.js). Der Tick laesst Stats live verfallen und weckt schlafende
## Goobys automatisch — vorher lag die komplette Lebenslogik brach.
const LIVE_TICK_INTERVAL_SEC := 5.0

## E15-P1: alle bekannten Produktions-Save-Slices (id → Skriptpfad). Lazy
## via load() statt preload — kein Parse-Zyklus zu Home/City/Minigame-Code.
## register_default_slices() registriert sie VOR dem Load in initialize();
## spaetere Domain-eigene register_slice()-Aufrufe bleiben idempotente No-ops.
const DEFAULT_SLICE_SCRIPTS := {
	"home": "res://scripts/home/home_state.gd",
	"events": "res://scripts/events/random_events.gd",
	"buffs": "res://scripts/events/buffs.gd",
	"bad": "res://scripts/home/interactables/bad_state.gd",
	"city": "res://scripts/city/city_state.gd",
	"gvz": "res://scripts/minigames/games/gvz/gvz_progress.gd",
	# FERTIG-1 (EVAL Rang 12): Arcade-Modifier-Events — additiver Slice.
	"modifiers": "res://scripts/minigames/modifier_engine.gd",
}

## Pinnbare Uhr — EINZIGE Zeitquelle fuer State-Code (Tests pinnen sie).
var clock := Clock.new()

var _manager := SaveManager.new()
var _state: Dictionary = {}
var _loaded := false
var _tick_accum := 0.0


func _ready() -> void:
	if not _loaded:
		initialize()


func _process(delta: float) -> void:
	if not _loaded:
		return
	_tick_accum += delta
	if _tick_accum >= LIVE_TICK_INTERVAL_SEC:
		_tick_accum = 0.0
		run_live_tick()
	_manager.autosave_tick(_state, Time.get_ticks_msec())


func _notification(what: int) -> void:
	if not _loaded:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_manager.flush_if_dirty(_state)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		# BUGHUNT-P1: nach App-Resume die versteckte Zeit nachholen (§E4) —
		# Schlaf zu Ende, 0.3x-Verfall, Urlaubs-Phasen.
		run_catch_up()


## Frozen Slice-API (GODOT-PLAN §W1d/§3.1): DER additive Erweiterungsweg fuer
## Domain-Slices — delegiert an die SaveSchema-Registry (identisches
## Verhalten, Re-Registrierung ersetzt). Validator optional (self-heal).
func register_slice(slice_name: String, default_factory: Callable, validator := Callable()) -> void:
	SaveSchema.register_slice(slice_name, default_factory, validator)


## E15-P1: registriert ALLE bekannten Default-Slices (DEFAULT_SLICE_SCRIPTS)
## direkt in der SaveSchema-Registry — laeuft am Anfang von initialize(),
## damit Defaults/Validatoren beim Load garantiert da sind (auch `city`,
## das im Produktions-Bootpfad sonst nie registriert wurde). Idempotent.
static func register_default_slices() -> void:
	for id: String in DEFAULT_SLICE_SCRIPTS:
		var script: Variant = load(DEFAULT_SLICE_SCRIPTS[id])
		if script == null:
			push_warning("[game_state] Slice-Skript fehlt: %s" % DEFAULT_SLICE_SCRIPTS[id])
			continue
		SaveSchema.register_slice(
			id, Callable(script, "default_slice"), Callable(script, "normalize_slice")
		)


## Load (or reload) the save. `save_path` override = headless tests.
func initialize(save_path := "user://save_v5.json") -> void:
	register_default_slices()
	_manager = SaveManager.new()
	_manager.save_path = save_path
	var res := _manager.load_state(clock.now_ms())
	_state = res["state"]
	# BUGHUNT-P1: Offline-Zeit VOR dem Initial-Emit nachholen — HUD/Room
	# sehen sofort die nachgeholten Werte (statt eingefrorener Stats).
	var events := GoobyTicker.catch_up(_state, clock.now_ms())
	_loaded = true
	_tick_accum = 0.0
	_manager.mark_dirty(Time.get_ticks_msec())
	state_loaded.emit(res["fresh"], res["recovered"])
	_emit_watched(_snapshot_watched_empty())
	if not events.is_empty():
		gooby_events.emit(events)


## BUGHUNT-P1: Offline-Nachholung (§E4) ausserhalb von initialize() — laeuft
## bei NOTIFICATION_APPLICATION_RESUMED (App kommt aus dem Hintergrund).
## Diff't die beobachteten Werte, persistiert und broadcastet die Web-Events
## ("wokeUp", "statLow:<stat>", "vacationPostcard", ...).
func run_catch_up() -> void:
	var before := _snapshot_watched()
	var events := GoobyTicker.catch_up(_state, clock.now_ms())
	_emit_watched(before)
	_manager.mark_dirty(Time.get_ticks_msec())
	if not events.is_empty():
		gooby_events.emit(events)


## BUGHUNT-P1: ein Live-Tick (§C1) — Stats verfallen seit lastTickAt,
## Schlaf tickt (inkl. Auto-Wecken mit Grants), Urlaub friert ein. Wird von
## _process() alle LIVE_TICK_INTERVAL_SEC aufgerufen; Tests rufen direkt.
func run_live_tick() -> void:
	var before := _snapshot_watched()
	var events := GoobyTicker.live_tick(_state, clock.now_ms())
	_emit_watched(before)
	_manager.mark_dirty(Time.get_ticks_msec())
	if not events.is_empty():
		gooby_events.emit(events)


func is_loaded() -> bool:
	return _loaded


## Direct state reference — READ ONLY. Writes MUST go through set_value/update
## so signals + autosave fire.
func state() -> Dictionary:
	return _state


## Dot-path read ("economy.coins", "gooby.stats.energy"). Flat map keys with
## colons ("living:shelf1") are safe — only "." splits.
func get_value(path: String, default: Variant = null) -> Variant:
	var node: Variant = _state
	for part in path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return default
	return node


## Dot-path write; creates intermediate dicts. Emits diffs + debounced save.
func set_value(path: String, value: Variant) -> void:
	update(
		func(s: Dictionary) -> void:
			var parts := path.split(".")
			var node: Dictionary = s
			for i in parts.size() - 1:
				var part := parts[i]
				if not (node.get(part) is Dictionary):
					node[part] = {}
				node = node[part]
			node[parts[parts.size() - 1]] = value
	)


## Atomic-style mutation: mutator(state) darf frei mutieren; danach werden
## die beobachteten Werte gedifft, Signale emittiert und der Autosave
## angestossen (Web store.update()-Muster).
func update(mutator: Callable) -> void:
	var before := _snapshot_watched()
	mutator.call(_state)
	_emit_watched(before)
	_manager.mark_dirty(Time.get_ticks_msec())


## Fuer nicht-beobachtete Slices (Sticker, Garten, ...): nach einem update()
## zusaetzlich das generische Signal ausloesen.
func notify_slice_changed(slice_id: String) -> void:
	slice_changed.emit(slice_id, _state.get(slice_id))


## Replace the whole state (Umzugskoffer import / dev tools) + save + re-emit.
func import_state(new_state: Dictionary) -> void:
	var before := _snapshot_watched()
	_state = new_state
	_emit_watched(before)
	save_now()


func save_now() -> bool:
	return _manager.save_now(_state)


## W1c onboarding_flow.gd `completed(profile)` — exact contract (frozen).
func apply_onboarding_profile(profile: Dictionary) -> void:
	update(
		func(s: Dictionary) -> void:
			var meta: Dictionary = s["meta"]
			var player_name: String = str(profile.get("player_name", "")).strip_edges()
			if not player_name.is_empty():
				meta["playerName"] = player_name.left(24)
			var nickname: String = str(profile.get("gooby_nickname", "")).strip_edges()
			meta["goobyNickname"] = nickname if not nickname.is_empty() else "Gooby"
			var editor: Variant = profile.get("editor")
			if editor is Dictionary:
				var morphs: Dictionary = meta["charMorphs"]
				for k in ["eyes_apart", "eye_scale", "ear_len", "chubby"]:
					if editor.has(k):
						morphs[k] = editor[k]
			s["onboarding"]["done"] = true
	)
	notify_slice_changed("meta")
	notify_slice_changed("onboarding")


## W1c news_50_panel.gd `news_seen` — persist the 5.0 news flag.
func mark_news_50_seen() -> void:
	update(func(s: Dictionary) -> void: s["onboarding"]["whatsNew5Seen"] = true)
	notify_slice_changed("onboarding")


## XP-Ring-Verhaeltnis fuer das HUD (W1c set_level(level, xp_ratio)).
## Bei MAX_LEVEL ist der Ring voll (1.0).
func xp_ratio() -> float:
	var level := int(get_value("progression.level", 1))
	if level >= Leveling.MAX_LEVEL:
		return 1.0
	var xp := float(get_value("progression.xp", 0.0))
	return clampf(xp / float(Leveling.xp_to_next(level)), 0.0, 1.0)


# ── watched-value diffing (web store event pattern) ──────────────────────────


func _snapshot_watched() -> Dictionary:
	var gooby: Dictionary = _state.get("gooby", {})
	var vac: Dictionary = _state.get("vacation", {})
	return {
		"coins": _state.get("economy", {}).get("coins", 0),
		"stats": gooby.get("stats", {}).duplicate(),
		"level": _state.get("progression", {}).get("level", 1),
		"xp": _state.get("progression", {}).get("xp", 0),
		"vacation_phase": vac.get("phase", "none"),
		"vacation_dest": vac.get("destId", ""),
	}


## Sentinel snapshot that differs from everything → initial full emit.
func _snapshot_watched_empty() -> Dictionary:
	return {
		"coins": null,
		"stats": null,
		"level": null,
		"xp": null,
		"vacation_phase": null,
		"vacation_dest": "",
	}


func _emit_watched(before: Dictionary) -> void:
	var now := _snapshot_watched()
	if now["coins"] != before["coins"]:
		coins_changed.emit(int(now["coins"]))
	if now["stats"] != before["stats"]:
		stats_changed.emit(now["stats"])
	if now["level"] != before["level"] or now["xp"] != before["xp"]:
		if now["xp"] != before["xp"]:
			xp_changed.emit(float(now["xp"]))
		level_changed.emit(int(now["level"]), xp_ratio())
	if now["vacation_phase"] != before["vacation_phase"]:
		vacation_changed.emit(str(now["vacation_phase"]), str(now["vacation_dest"]))
