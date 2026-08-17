class_name PerfGlowWatch
extends Node
## W15/TECHKIT (Doc G §9 R2) — HDR-/Glow-Auto-Downgrade-Telemetrie.
##
## Kleiner Wächter, den der QualityService an JEDES startende Minigame hängt
## (MinigameBase betritt den Baum → attach_to): misst über die ersten
## WINDOW_SEC Sekunden der AKTIVEN Runde die Frame-Zeiten
## (Performance TIME_PROCESS + TIME_PHYSICS_PROCESS). Liegt das p95 über dem
## Budget des aktiven Quality-Bündels (1000/fps × Headroom, Schwelle via
## Quality.applied_bundle()), wird Glow/HDR NUR FÜR DIESE SESSION gesenkt:
## WorldEnvironment.glow aus, JuiceKit.world_environment = null (bloom_pulse
## wird No-Op — öffentliche Hook-Property), Viewport.use_hdr_2d aus.
##
## Der Downgrade wird PRO SPIEL in user:// gemerkt (NICHT im Save!) — beim
## nächsten Start desselben Spiels greift er sofort, ohne neue Messfahrt.
## Das Dev-Panel (Perf-Tab) zeigt die Merker-Liste und setzt sie zurück.
##
## Testbarkeit: Zeit + Messwerte sind injiziert (feed(frame_ms, dt) treibt
## die Statemaschine, budget_ms_override ersetzt die Quality-Schwelle,
## store_path zeigt auf ein Temp-Verzeichnis) — _process ist nur der dünne
## Laufzeit-Treiber mit echtem Monitor-Feed.

## Messfenster ab Rundenstart (Doc G §9 R2: „über 5 s").
const WINDOW_SEC := 5.0
## p95 darf bis zu 125 % des Frame-Budgets kosten, bevor gedrosselt wird.
const BUDGET_HEADROOM := 1.25
## Unter so wenigen Messframes ist kein p95-Urteil erlaubt (Hänger ≠ Trend).
const MIN_SAMPLES := 30
## Merker-Datei (user://, bewusst NICHT der Save).
const STORE_PATH := "user://glow_downgrades.json"

## Beobachtetes Spiel (MinigameBase, Duck-Typing: ctx + is_active()).
var game: Node = null
## Injektion für Tests: Merker-Pfad, Budget, Monitor-Feed, Quality-Node.
var store_path := STORE_PATH
var budget_ms_override := -1.0
var monitor: Callable = Callable()
var quality_override: Object = null

## Statemaschine: messen → ok | gedrosselt; „vorab" = Merker griff sofort.
var phase := "messen"
var elapsed := 0.0
var samples: Array[float] = []
var game_id := ""


## QualityService-Einstieg: Wächter als Kind ans frisch eingehängte Spiel.
static func attach_to(game_node: Node) -> PerfGlowWatch:
	var watch := PerfGlowWatch.new()
	watch.name = "PerfGlowWatch"
	watch.game = game_node
	# deferred: attach_to feuert aus dem node_added-Signal — nicht mitten
	# im Baum-Umbau ein weiteres Kind einhängen.
	game_node.add_child.call_deferred(watch)
	return watch


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game):
		set_process(false)
		return
	if game_id.is_empty():
		game_id = _resolve_game_id()
		if game_id.is_empty():
			return
		if is_downgraded(game_id, store_path):
			phase = "vorab"
			_apply_downgrade()
			set_process(false)
			return
	if not _game_active():
		return
	feed(_read_frame_ms(), delta)
	if phase != "messen":
		set_process(false)


## Kern-Statemaschine (zeitinjiziert): einen Messframe einspeisen.
## Liefert die Phase nach dem Frame ("messen" | "ok" | "gedrosselt").
func feed(frame_ms: float, dt: float) -> String:
	if phase != "messen":
		return phase
	if is_finite(frame_ms) and frame_ms >= 0.0:
		samples.append(frame_ms)
	elapsed += maxf(dt, 0.0)
	if elapsed < WINDOW_SEC:
		return phase
	var p := p95(samples)
	if samples.size() >= MIN_SAMPLES and p > budget_ms():
		phase = "gedrosselt"
		_apply_downgrade()
		if not game_id.is_empty():
			mark_downgraded(game_id, p, store_path)
	else:
		phase = "ok"
	return phase


## Budget-Schwelle (ms) aus dem aktiven Quality-Bündel (Duck-Typing) —
## Tests überschreiben per budget_ms_override.
func budget_ms() -> float:
	if budget_ms_override > 0.0:
		return budget_ms_override
	var fps := 60.0
	var quality := _quality()
	if quality != null and quality.has_method("applied_bundle"):
		fps = maxf(30.0, float((quality.applied_bundle() as Dictionary).get("fps", 60)))
	return 1000.0 / fps * BUDGET_HEADROOM


## p95 einer Messreihe (pur): sortiert, Index ceil(0.95·n)−1.
static func p95(values: Array) -> float:
	var clean: Array[float] = []
	for value: Variant in values:
		if (value is float or value is int) and is_finite(float(value)):
			clean.append(float(value))
	if clean.is_empty():
		return 0.0
	clean.sort()
	var idx := clampi(int(ceil(clean.size() * 0.95)) - 1, 0, clean.size() - 1)
	return clean[idx]


## ------------------------------------------------------- user://-Merker


static func load_store(path := STORE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"schema": 1, "games": {}}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {"schema": 1, "games": {}}
	var store: Dictionary = json.data
	if not (store.get("games") is Dictionary):
		store["games"] = {}
	return store


static func save_store(store: Dictionary, path := STORE_PATH) -> void:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[glow_watch] Merker nicht schreibbar: %s" % path)
		return
	file.store_string(JSON.stringify(store, "\t") + "\n")
	file.close()


static func is_downgraded(game_id_value: String, path := STORE_PATH) -> bool:
	return (load_store(path)["games"] as Dictionary).has(game_id_value)


static func mark_downgraded(
	game_id_value: String, p95_ms: float, path := STORE_PATH, at := ""
) -> void:
	var store := load_store(path)
	var stamp := at if not at.is_empty() else Time.get_datetime_string_from_system()
	store["games"][game_id_value] = {"p95_ms": snappedf(p95_ms, 0.1), "at": stamp}
	save_store(store, path)


## Merker-Liste fürs Dev-Panel: [{game, p95_ms, at}], alphabetisch.
static func entries(path := STORE_PATH) -> Array[Dictionary]:
	var games: Dictionary = load_store(path)["games"]
	var ids: Array = games.keys()
	ids.sort()
	var rows: Array[Dictionary] = []
	for id: Variant in ids:
		var row: Dictionary = games[id] if games[id] is Dictionary else {}
		(
			rows
			. append(
				{
					"game": str(id),
					"p95_ms": float(row.get("p95_ms", 0.0)),
					"at": str(row.get("at", "")),
				}
			)
		)
	return rows


## Dev-Panel-Reset: alle Merker löschen (nächster Start misst wieder frisch).
static func clear_store(path := STORE_PATH) -> void:
	save_store({"schema": 1, "games": {}}, path)


## ------------------------------------------------------- Session-Downgrade


## Glow/HDR für DIESE Session senken — ausschließlich über bestehende
## öffentliche Hooks (JuiceKit.world_environment, Environment.glow_enabled,
## Viewport.use_hdr_2d). Kein Save, keine Settings-Änderung.
func _apply_downgrade() -> void:
	var juice := _juice()
	if juice != null:
		var env: WorldEnvironment = juice.get("world_environment")
		if env != null and is_instance_valid(env) and env.environment != null:
			env.environment.glow_enabled = false
		juice.set("world_environment", null)
	if game != null and is_instance_valid(game) and game.is_inside_tree():
		var viewport := game.get_viewport()
		if viewport != null:
			if viewport.use_hdr_2d:
				viewport.use_hdr_2d = false
			var world := viewport.find_world_3d()
			if world != null and world.environment != null:
				world.environment.glow_enabled = false


func _resolve_game_id() -> String:
	if game == null or not is_instance_valid(game):
		return ""
	var ctx: Variant = game.get("ctx")
	if ctx is Object and (ctx as Object).get("game_id") != null:
		return str((ctx as Object).get("game_id"))
	return ""


func _juice() -> Object:
	if game == null or not is_instance_valid(game):
		return null
	var ctx: Variant = game.get("ctx")
	if ctx is Object:
		var juice: Variant = (ctx as Object).get("juice")
		if juice is Object and is_instance_valid(juice):
			return juice
	return null


func _game_active() -> bool:
	return game != null and game.has_method("is_active") and bool(game.call("is_active"))


func _read_frame_ms() -> float:
	if monitor.is_valid():
		return float(monitor.call())
	return (
		(
			Performance.get_monitor(Performance.TIME_PROCESS)
			+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		)
		* 1000.0
	)


func _quality() -> Object:
	if quality_override != null:
		return quality_override
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Quality")
