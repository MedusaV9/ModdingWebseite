class_name RanchEventHost
extends Node3D
## Ranch-Runner-Hook der Random-Events (W13/RANCH) — dockt die bestehende
## Engine (RandomEventEngine) an die Ranch an, OHNE den Haus-EventRunner
## umzubauen. Gleicher Einbau wie im Haus (home_entry → EventRunner):
##   RanchEventHost.attach_to(hof_szene)   # nach dem Hof-Aufbau
##
## Der Host würfelt mit context="ranch" (Defs tragen `context: "ranch"` in
## content/events/data/events.json) und NUR wenn die Ranch gekauft ist.
## Scheduler-Semantik (Zeitfenster, Timeout, Fail-Text, Cooldown, max 1
## aktives Event) kommt komplett aus der Engine. Szenen-Hooks:
##   ranch_ausgebuext   — Pferd einfangen (antippen) → Bindung + Münzen
##   ranch_heudieb      — 3 Krähen verscheuchen (3× tippen) → Heu gerettet
##   ranch_hufschmied   — Hufschmied besuchen → Huf-Check-Buff 24 h
##   ranch_karottenregen — Karotten einsammeln (max 10) → Inventar
##
## Zeit/Zufall IMMER injizierbar (now_ms_override/minuten_override/
## rng_override VOR add_child setzen — Muster game_state_override der
## Hof-Szene); Default = gs.clock (pinnbare Uhr) + Systemuhrzeit.

signal event_resolved(event_id: String)

const CONTEXT := "ranch"
const PFERD_FELL := Color("#D9A066")
const PFERD_MAEHNE := Color("#8A5A33")
const KRAEHE_FARBE := Color("#2E3138")
const SCHMIED_FARBE := Color("#7A5C43")
const KAROTTE_FARBE := Color("#F28C28")
const TAP_UNSICHTBAR := Color(1, 1, 1, 0.02)

## Tests/Screenshots injizieren VOR add_child (Muster Hof-Szene).
var game_state_override: Object = null
var now_ms_override := -1
var minuten_override := -1
var rng_override: RandomNumberGenerator = null

var _scene: Node = null
var _gs: Object = null
var _defs: Array = []
var _def: Dictionary = {}
var _props: Array = []
var _remaining := 0
var _karotten := 0
var _running := false
var _rng := RandomNumberGenerator.new()


## Host an die Ranch-Szene hängen (idempotent). Zeigt Fail-Bubbles und
## startet das aktive Ranch-Event bzw. würfelt ein neues (nur gekauft).
static func attach_to(scene: Node, defs: Array = []) -> RanchEventHost:
	var existing := scene.get_node_or_null("RanchEventHost")
	if existing is RanchEventHost:
		return existing
	var host := RanchEventHost.new()
	host.name = "RanchEventHost"
	scene.add_child(host)
	host.setup(scene, defs)
	return host


func setup(scene: Node, defs: Array = []) -> void:
	_scene = scene
	_rng = rng_override if rng_override != null else RandomNumberGenerator.new()
	if rng_override == null:
		_rng.randomize()
	_gs = game_state_override
	if _gs == null and scene.has_method("game_state"):
		_gs = scene.game_state()
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	_defs = defs if not defs.is_empty() else RandomEventEngine.defs_from_registry()
	if _gs == null or not RanchState.ist_gekauft(_gs):
		return
	# Erst rollen (räumt abgelaufene Events + würfelt ggf. neu), DANN die
	# Fail-Bubble zeigen — so erscheint sie noch im selben Ranch-Besuch.
	RandomEventEngine.roll_on_start(_gs, _defs, _now_ms(), _minuten(), _rng, CONTEXT)
	var fail_text := RandomEventEngine.take_fail_notice(_gs)
	if not fail_text.is_empty():
		_melde(fail_text)
	var active := RandomEventEngine.active_of(_gs)
	if active.is_empty():
		return
	var def := RandomEventEngine.def_by_id(_defs, str(active.get("id", "")))
	if not def.is_empty():
		start(def)


## Event-Szene direkt starten (Tests; normal via setup()). Nicht-Ranch-
## Setups (aktives Haus-Event) werden ignoriert — der Haus-Runner macht die.
func start(def: Dictionary) -> void:
	if _running:
		return
	_running = true
	_def = def
	match str(def.get("szene_setup", "")):
		"ranch_ausgebuext":
			_setup_ausgebuext()
		"ranch_heudieb":
			_setup_heudieb(maxi(1, int(def.get("props", 3))))
		"ranch_hufschmied":
			_setup_hufschmied()
		"ranch_karottenregen":
			_setup_karottenregen(maxi(1, int(def.get("props", 10))))
		_:
			_running = false
			_def = {}


func is_running() -> bool:
	return _running


# ── (1) Ausgebüxt: Pferd einfangen ───────────────────────────────────────────


## Ein Pferd trabt frei überm Hof — Tap fängt es ein (Bindung + Münzen).
func _setup_ausgebuext() -> void:
	var pferd := RanchPferd.neu(PFERD_FELL, PFERD_MAEHNE)
	pferd.position = _anker() + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, 10.0)
	pferd.set_gangart(RanchPferd.GANG_TRAB)
	add_child(pferd)
	_props.append(pferd)
	var fang := _prop(TAP_UNSICHTBAR, Vector3(1.6, 2.2, 2.6), _on_pferd_gefangen, false)
	fang.position = Vector3(0.0, 1.1, 0.0)
	pferd.add_child(fang)
	_melde(I18nService.t("revents.ausgebuext.bubble"))


func _on_pferd_gefangen() -> void:
	if not _running:
		return
	for prop: Node3D in _props:
		if is_instance_valid(prop) and prop is RanchPferd:
			(prop as RanchPferd).set_gangart(RanchPferd.GANG_IDLE)
	_melde(I18nService.t("revents.ausgebuext.danke"))
	_resolve()


# ── (2) Heudieb: Krähen verscheuchen ─────────────────────────────────────────


## Freche Krähen hocken auf dem Heustapel — jede fliegt bei einem Tap auf,
## sind alle weg, ist das Heu gerettet (+Ballen ins Lager).
func _setup_heudieb(kraehen: int) -> void:
	_remaining = kraehen
	for i in kraehen:
		var kraehe := _prop(KRAEHE_FARBE, Vector3(0.35, 0.3, 0.4), _on_kraehe_verscheucht)
		kraehe.position = (
			_anker() + Vector3(-2.0 + 2.0 * float(i), 1.4, _rng.randf_range(-1.0, 1.0))
		)
		add_child(kraehe)
		_props.append(kraehe)
	_melde(I18nService.t("revents.heudieb.bubble"))


func _on_kraehe_verscheucht() -> void:
	if not _running:
		return
	_remaining -= 1
	if _remaining > 0:
		_melde(I18nService.t("revents.heudieb.kraah"))
		return
	_melde(I18nService.t("revents.heudieb.danke"))
	_resolve()


# ── (3) Hufschmied: Gratis-Huf-Check ─────────────────────────────────────────


## Der wandernde Hufschmied steht kurz am Tor — ein Besuch (Tap) gibt den
## 24-h-Huf-Check-Buff (zeitinjiziert, RanchEventRewards.huf_check_aktiv).
func _setup_hufschmied() -> void:
	var schmied := _prop(SCHMIED_FARBE, Vector3(0.7, 1.7, 0.5), _on_hufschmied_besucht, false)
	schmied.position = _anker() + Vector3(4.0, 0.85, -3.0)
	add_child(schmied)
	_props.append(schmied)
	_melde(I18nService.t("revents.hufschmied.bubble"))


func _on_hufschmied_besucht() -> void:
	if not _running:
		return
	_melde(I18nService.t("revents.hufschmied.danke"))
	_resolve()


# ── (4) Karottenregen: einsammeln (max 10) ───────────────────────────────────


## GOOBY-Wetterphänomen: Karotten liegen verstreut — jeder Tap sammelt EINE
## sofort ins Haupt-Inventar (inventory.food.carrot); sind alle eingesammelt,
## ist das Event gelöst. Verpasste Karotten verfallen mit dem Timeout.
func _setup_karottenregen(karotten: int) -> void:
	_remaining = karotten
	_karotten = 0
	for i in karotten:
		var karotte := _prop(KAROTTE_FARBE, Vector3(0.16, 0.4, 0.16), _on_karotte_gesammelt)
		karotte.position = (
			_anker() + Vector3(_rng.randf_range(-7.0, 7.0), 0.2, _rng.randf_range(-5.0, 5.0))
		)
		add_child(karotte)
		_props.append(karotte)
	_melde(I18nService.t("revents.karottenregen.bubble"))


func _on_karotte_gesammelt() -> void:
	if not _running:
		return
	_remaining -= 1
	_karotten += 1
	RanchEventRewards.karotte_gutschreiben(_gs)
	if _remaining > 0:
		return
	_melde(I18nService.t("revents.karottenregen.danke", {"n": _karotten}))
	_resolve()


# ── gemeinsame Helfer ────────────────────────────────────────────────────────


## Aktives Event auflösen: Engine räumt (Cooldown bleibt), Rewards über die
## bestehenden Mechanismen gutschreiben (RanchEventRewards).
func _resolve() -> void:
	var event_id := str(_def.get("id", ""))
	if _gs != null:
		var now_ms := _now_ms()
		RandomEventEngine.resolve_active(_gs, _defs, now_ms)
		RanchEventRewards.anwenden(_gs, _def, now_ms, _zufalls_pferd_id())
	_clear_props()
	_running = false
	_def = {}
	# W15/VOICE2 (W13-Request): Ranch-Event erledigt → Ranch-Kommentar.
	SeeleRunner.kommentar_global("w13.ranch")
	event_resolved.emit(event_id)


## Bindungs-Ziel: deterministisch (injizierter Zufall) ein Pferd aus dem
## Bestand — das „ausgebüxte“ Pferd des Spielers.
func _zufalls_pferd_id() -> String:
	var ids: Array = RanchState.pferde(_gs).keys()
	if ids.is_empty():
		return ""
	ids.sort()
	return str(ids[_rng.randi_range(0, ids.size() - 1)])


func _anker() -> Vector3:
	if _scene != null and _scene.has_method("event_anker"):
		return _scene.event_anker()
	return Vector3.ZERO


func _melde(text: String) -> void:
	if _scene != null and _scene.has_method("zeige_meldung"):
		_scene.zeige_meldung(text)


func _prop(color: Color, box_size: Vector3, on_tap: Callable, free_on_tap := true) -> Node3D:
	return EventProps.make_prop(
		color, box_size, on_tap, free_on_tap, func(prop: Node3D) -> void: _props.erase(prop)
	)


func _clear_props() -> void:
	for prop: Node3D in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props = []


func _now_ms() -> int:
	if now_ms_override >= 0:
		return now_ms_override
	if _gs != null:
		var clock: Variant = _gs.get("clock")
		if clock is Object and (clock as Object).has_method("now_ms"):
			return int(clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _minuten() -> int:
	if minuten_override >= 0:
		return minuten_override
	var uhr := Time.get_datetime_dict_from_system()
	return int(uhr["hour"]) * 60 + int(uhr["minute"])
