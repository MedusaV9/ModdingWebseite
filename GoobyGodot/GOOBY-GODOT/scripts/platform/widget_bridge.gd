class_name WidgetBridgeService
extends Node
## iOS-WIDGETS (Autoload „WidgetBridge") — die schmale Shell um die pure
## Logik: sammelt den Widget-Snapshot (widget_snapshot.gd) und den
## Live-Activity-Plan und reicht beides an die Plugin-Anbindung
## (goobykit_bridge.gd) weiter. Auf Nicht-iOS-Plattformen komplett No-op
## (kein Prozess-Tick, keine Dateizugriffe) — der Headless-Boot bleibt sauber.
##
## MINIMAL-INVASIV (Auftrags-Vorgabe): KEIN fremdes Kernskript wird
## angefasst. Statt Hooks in reise_app.gd/bett.gd BEOBACHTET die Bridge den
## GameState (Signale vacation_changed/coins_changed/stats_changed/
## slice_changed/gooby_events) plus einen billigen Poll (POLL_INTERVAL_S,
## faengt signal-lose Aenderungen wie den Schlaf-Start) und flusht hart bei
## App-Pause/Focus-Out — exakt der Moment, in dem Widgets/Live Activities
## aktuell sein muessen (danach laeuft kein Godot-Code mehr).
##
## Live-Activity-Entscheidung (start/update/end) per Plan-Abgleich:
##  - Plan leer, Activity laeuft        → end_live_activity()
##  - Plan da, keine Activity           → start_live_activity(plan)
##  - Plan da, andere kind              → end + start (neue Activity)
##  - Plan da, gleiche kind, neuer Text → update_live_activity(plan)

const POLL_INTERVAL_S := 2.0

const WidgetSnapshotLogic := preload("res://scripts/platform/widget_snapshot.gd")
const BridgeScript := preload("res://scripts/platform/goobykit_bridge.gd")

var _bridge: Object = null
var _gs: Object = null
var _text_fn := Callable(self, "_translate")
var _quest_pool_fn := Callable(self, "_quest_pool")
var _tz_bias_override := 0
var _tz_bias_overridden := false
var _accum := 0.0
var _last_snapshot_key := ""
var _last_plan_json := ""
var _la_kind := ""


func _ready() -> void:
	if _bridge == null:
		_bridge = BridgeScript.new()
	if not _bridge.is_supported():
		set_process(false)
		return
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		attach_game_state(gs)


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_INTERVAL_S:
		return
	_accum = 0.0
	sync_now()


func _notification(what: int) -> void:
	# Pause/Focus-Out ist der letzte Moment vor dem Suspend — genau jetzt
	# muessen Snapshot + Live-Activity-Soll-Zustand auf Platte liegen.
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_WM_CLOSE_REQUEST
	):
		sync_now()


## Testeinstieg: Fake-Bridge + gepinnte Zeitzone + deterministische Text-/
## Pool-Quellen injizieren (Muster NotificationService.settings_override).
## Danach attach_game_state(gs) mit einem frischen GameState aufrufen.
func configure_for_tests(
	bridge: Object, tz_bias_min: int, text_fn: Callable, quest_pool_fn: Callable
) -> void:
	_bridge = bridge
	_tz_bias_override = tz_bias_min
	_tz_bias_overridden = true
	_text_fn = text_fn
	_quest_pool_fn = quest_pool_fn
	_last_snapshot_key = ""
	_last_plan_json = ""
	_la_kind = ""


## Snapshot + Live-Activity-Plan bauen und (nur bei Aenderung) an die
## native Seite geben. Oeffentlich: Tests und Pause-Pfad rufen direkt.
func sync_now() -> void:
	if _bridge == null or not _bridge.is_supported():
		return
	if _gs == null or not _gs.is_loaded():
		return
	var state: Dictionary = _gs.state()
	var now_ms: int = _gs.clock.now_ms()
	var local_day: String = _gs.clock.local_day()
	var bias := _tz_bias()
	var snapshot: Dictionary = WidgetSnapshotLogic.build(
		state, now_ms, local_day, bias, _text_fn, _quest_pool_fn.call()
	)
	_push_snapshot(snapshot)
	var plan: Dictionary = WidgetSnapshotLogic.live_activity_plan(
		state, now_ms, local_day, bias, _text_fn
	)
	_push_live_activity(plan)


## GameState-Signale verdrahten und initial syncen (Produktion: _ready;
## Tests: direkt mit einem frischen GameState-Objekt).
func attach_game_state(gs: Object) -> void:
	_gs = gs
	# Alles laeuft auf denselben debounce-ten Sync hinaus — die Signale
	# markieren nur "bald syncen"; vacation_changed/gooby_events sofort
	# (Live-Activity-relevante Momente: Buchung, Abholung, Aufwachen).
	if gs.has_signal("vacation_changed"):
		gs.vacation_changed.connect(func(_phase: String, _dest: String) -> void: sync_now())
	if gs.has_signal("gooby_events"):
		gs.gooby_events.connect(func(_events: Array) -> void: sync_now())
	if gs.has_signal("state_loaded"):
		gs.state_loaded.connect(func(_fresh: bool, _recovered: bool) -> void: sync_now())
	if gs.has_signal("coins_changed"):
		gs.coins_changed.connect(func(_coins: int) -> void: _mark_soon())
	if gs.has_signal("stats_changed"):
		gs.stats_changed.connect(func(_stats: Dictionary) -> void: _mark_soon())
	if gs.has_signal("slice_changed"):
		gs.slice_changed.connect(func(_id: String, _data: Variant) -> void: _mark_soon())
	if _gs.is_loaded():
		sync_now()


## Naechster Poll-Tick soll sofort feuern (Sammel-Debounce fuer laute
## Signale wie stats_changed im 5-s-Live-Tick).
func _mark_soon() -> void:
	_accum = POLL_INTERVAL_S


func _push_snapshot(snapshot: Dictionary) -> void:
	# generatedAtMs aendert sich bei JEDEM Build — fuer den "hat sich etwas
	# geaendert?"-Vergleich fliegt der Stempel raus (kein Schreib-Spam).
	var compare := snapshot.duplicate()
	compare.erase("generatedAtMs")
	var key := JSON.stringify(compare)
	if key == _last_snapshot_key:
		return
	if _bridge.set_widget_data(JSON.stringify(snapshot)):
		_last_snapshot_key = key


func _push_live_activity(plan: Dictionary) -> void:
	if plan.is_empty():
		if not _la_kind.is_empty():
			_bridge.end_live_activity()
			_la_kind = ""
			_last_plan_json = ""
		return
	var plan_json := JSON.stringify(plan)
	var kind := str(plan.get("kind", ""))
	if _la_kind.is_empty():
		if _bridge.start_live_activity(plan_json):
			_la_kind = kind
			_last_plan_json = plan_json
		return
	if kind != _la_kind:
		_bridge.end_live_activity()
		if _bridge.start_live_activity(plan_json):
			_la_kind = kind
			_last_plan_json = plan_json
		return
	if plan_json != _last_plan_json:
		if _bridge.update_live_activity(plan_json):
			_last_plan_json = plan_json


func _tz_bias() -> int:
	if _tz_bias_overridden:
		return _tz_bias_override
	return int(Time.get_time_zone_from_system().get("bias", 0))


func _translate(key: String, args: Dictionary) -> String:
	return I18nService.t(key, args)


func _quest_pool() -> Array:
	return DailyQuestCatalog.pool()
