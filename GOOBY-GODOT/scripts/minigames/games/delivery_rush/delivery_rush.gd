extends MinigameBase
## Liefer-Hetze (deliveryRush) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## DeliveryRushLogic (zahlengleich zum Web): 3 Pakete an 3 verschiedene
## Landmarken, 4-m-Abwurfring +50, Crash −5 (Boden 0), markiertes Paket
## −20 bei Schaden / +15 sauber, Zeitbonus +max(0, 120 − s) nach Abwurf 3.
##
## ECHTES 3D (Agent 3D-B): das 9×9-Kachelraster der Logik steht als Kenney-
## Stadt in der Welt, die Kamera hängt hinter dem Lieferwagen und Gooby fährt
## SICHTBAR mit. Die Fahrphysik (Lenkrate, Tempo, Kollider) ist unverändert —
## es sind dieselben (x, z)-Meter, nur nicht mehr von oben gezeichnet.
##
## KEIN Screenshake beim Fahren (Motion-Comfort-Regel) — der Crash bekommt
## stattdessen Bremsen, Frame-Freeze und eine Gooby-Grimasse.
##
## AUTOHAUS-HOOK: `car_speed_mult` bleibt 1.0 — hier hängt später das im
## Autohaus gekaufte Auto (Tempo/Handling) dran. Bewusst NICHT implementiert.

const Logic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")
const World := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_world.gd")
const Feel := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_feel.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const HintFeel := preload("res://scripts/minigames/hint_feel.gd")

const VAN_GLB := "res://assets/city/autos/delivery.glb"
const PARCEL_GLB := "res://assets/minigames/delivery_rush/car-kit/box.glb"

## Basis-Höchsttempo des Lieferwagens (m/s, §C4-Rampe).
const VAN_TOP_SPEED := 13.0
const VAN_ACCEL := 9.0
const VAN_TURN_RATE := 2.4
## Abseits der Straße bremst der Wagen auf diesen Anteil.
const OFFROAD_FACTOR := 0.45
## Fahrzeugmaße in Weltmetern (Lieferwagen und Verkehr).
const VAN_LEN_M := 7.0
const VAN_WIDTH_M := 3.4
const CAR_LEN_M := 5.2
const CAR_WIDTH_M := 2.6
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Verkehr: Grundzahl der Autos auf dem Ring, ×TRAFFIC_DENSITY_MULT.
const TRAFFIC_BASE := 6
const TRAFFIC_SPEED := 7.5
const TRAFFIC_HIT_M := 3.4
const CRASH_COOLDOWN_SEC := 1.5

## Verfolgerkamera (Meter hinter/über dem Wagen) und Blickpunkt davor.
const CAM_BACK := 11.5
const CAM_LIFT := 5.4
const CAM_LOOK_AHEAD := 9.0
const CAM_PORTRAIT_LIFT := 2.2
const CAM_PORTRAIT_BACK := 1.5
## Hochkant: Zielpunkt näher heran und tiefer ziehen (Blick auf die Straße).
const CAM_PORTRAIT_AHEAD := 3.0
const CAM_PORTRAIT_AIM_DOWN := 1.4
const HFOV_BASE := 84.0
const HFOV_KICK := 7.0
const STREAK_RATE: Array = [[7.0, 0.0], [10.0, 5.0], [13.0, 11.0]]
## G5 M1: Intro-Beat (s) — Stadt-Totale + Ziel-Banner, Sim/Eingabe warten.
const INTRO_S := 1.5
## Kamera-Hub/-Rückzug der Intro-Totale (m) — Blick über die Abendstadt.
const INTRO_LIFT := 16.0
const INTRO_BACK := 10.0
## Autopilot (nur Screenshots/Zertifizierung): so scharf zielt er.
const BOT_STEER_GAIN := 1.6
## Höhe des Gooby-Rigs auf dem Wagendach (m).
const GOOBY_H := 1.7
## Wegweiser-Band: so viele Kacheln weit wird die Route auf die Straße gemalt.
const ROUTE_TILES := 9
## Breite des Wegweiser-Bandes (m). Web: `T.ROUTE_LINE_WIDTH_M` = 1,6 — mit 3,0
## lag hochkant ein magentafarbener Teppich über dem unteren Bilddrittel.
const ROUTE_WIDTH_M := 1.6
## So weit reicht das Band hinter den Wagen zurück (m) — siehe `_sync_route`.
const ROUTE_TRAIL_M := 10.0
## Der Bot peilt nicht den nächstbesten Routenpunkt an, sondern den ersten, der
## mindestens so weit vor ihm liegt — sonst kurvt er um jede Kachelmitte herum
## und landet dabei regelmäßig auf der Wiese.
const BOT_LOOKAHEAD_M := 7.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var leg_elapsed := 0.0
var crashes := 0
var drops := 0
var parcel := 0
var fragile_index := 0
var fragile_damaged := false
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false
## Hook: kommt später aus dem Autohaus (Tempo/Handling des gekauften Autos).
var car_speed_mult := 1.0
## Für Screenshot-/Zertifizierungsläufe: der Autopilot fährt zum Abwurfring.
var autoplay := false

var van_pos := Vector2.ZERO
var van_heading := 0.0
var van_speed := 0.0
var steer := 0.0
## Lieferserie ohne Crash (nur Anzeige/Feel — Combo-Ton steigt pro Stufe).
var delivery_streak := 0

var _grid: Array = []
var _colliders: Array[Dictionary] = []
var _targets: Array[String] = []
## W13/SAMMLUNG: beliefert = besucht — Landmark-Ids für das landmarks-Set.
var _visited_landmarks: Array[String] = []
var _drop_points: Array[Vector2] = []
var _traffic: Array[Dictionary] = []
var _endless_state: Dictionary = {}
var _crash_cool := 0.0
var _ui := 1.0
var _time_label: Label
var _target_label: Label
var _hint_label: Label
## W19: Milchglas-Plate hinter dem Steuer-Hinweis (Feel.make_hint stylt beide).
var _hint_plate := StyleBoxFlat.new()
var _banner := ""
var _banner_t := 0.0
## W19: der Erste-Lieferung-Beat feuert genau EINMAL pro Runde.
var _first_leg_shown := false
var _stage: Node3D
var _world: Node3D
var _van: Node3D
var _gooby: Node3D
var _parcels: Array[Node3D] = []
var _ring: Node3D
var _route_prop: Node3D
var _route: Array[Vector2] = []
var _route_t := 0.0
var _streaks: MultiMeshInstance3D
var _dust: GPUParticles3D
var _pop: GPUParticles3D
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_ready := false
var _intro_left := 0.0
var _feel: Node


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.DELIVERY, ctx.difficulty)
	rng = ctx.rng()
	_grid = Logic.build_grid()
	_colliders = Logic.layout_colliders()
	var ids: Array[String] = []
	for row: Dictionary in Logic.LANDMARKS:
		ids.append(str(row["id"]))
	_targets = Logic.pick_deliveries(rng, ids)
	fragile_index = Logic.pick_fragile_parcel(rng)
	_rebuild_drop_points()
	_endless_state = Logic.create_endless_state(int(tune["ENDLESS_EXPIRED_LIMIT"]))
	var start := Logic.tile_to_world(Logic.SHOP_TILE.x, Logic.SHOP_TILE.y)
	van_pos = Vector2(start.x + 6.5, start.y)
	van_heading = -PI * 0.5
	_spawn_traffic()
	_build_stage()
	_build_hud()
	# G5 M1: Intro-Beat — Ziel-Banner + Stadt-Totale; Sim-Uhr, Verkehr und
	# Eingabe warten, der Lauf bleibt danach zahlengleich (Crosscheck-Vertrag).
	# VOR _sync_world gesetzt, damit die Kamera direkt in der Totale startet.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.deliveryRush.intro"), INTRO_S + 0.7)
	_sync_world(0.0)
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true
	if _feel != null:
		_feel.stop_motor()


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.call("apply_size", view_size)
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_target_label.position = Vector2(pad, 44.0 * _ui)
	_target_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	# W21 DR-1: kein direktes `size =` — das klemmt an der GECACHTEN Umbruch-Mindesthöhe
	# (1. Layout: Breite ~0 → Label ~3400 px hoch, der Text stand unsichtbar unterm Bild).
	var s := HintFeel.clamp_size(_hint_label, hint_w)
	_hint_label.position = Vector2((view_size.x - s.x) * 0.5, view_size.y - s.y - 6.0 * _ui)


func _process(delta: float) -> void:
	# Motor-Loop VOR dem Aktiv-Guard syncen (rocket-Muster): nur so pausiert
	# der Loop auch, wenn die Runde vorbei ist oder das Spiel nicht aktiv ist.
	if _feel != null:
		_feel.tick(delta)
		var driving := is_active() and not finished and _intro_left <= 0.0 and not _reduced_motion()
		_feel.sync_motor(delta, driving, van_speed / VAN_TOP_SPEED)
	if not is_active() or finished:
		return
	# G5 M1: im Intro-Beat schwebt die Kamera aus der Stadt-Totale in die
	# Verfolger-Pose; Sim-Uhr, Verkehr und Eingabe warten (zahlengleich).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_route_t -= delta
		if _route_t <= 0.0:
			_route_t = 0.25
			_recompute_route()
		_update_labels()
		_sync_world(delta)
		queue_redraw()
		return
	elapsed += delta
	leg_elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	# W19: sobald das Intro-Banner fällt, benennt der Erste-Lieferung-Beat das
	# erste Ziel — die Web-paritätische Anfahrt wird ERKLÄRT, nicht verkürzt.
	if not _first_leg_shown and _banner_t <= 0.0:
		_first_leg_shown = true
		var beat: String = _feel.first_leg_text(drops, parcel, _targets)
		if not beat.is_empty():
			_set_banner(beat, Feel.FIRST_LEG_BANNER_S)
	_crash_cool = maxf(0.0, _crash_cool - delta)
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.25
		_recompute_route()
	if autoplay:
		_autopilot()
	var before := van_pos
	_step_van(delta)
	_step_traffic(delta)
	_check_drop(before)
	if Logic.parcel_expired(leg_elapsed, tune):
		_expire_parcel()
	_update_labels()
	_fade_hint()
	_sync_world(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# G5 M1: im Intro-Beat wartet auch die Eingabe (kein Frühstart-Lenken).
	if not is_active() or finished or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch:
		steer = _steer_from(event.position) if event.pressed else 0.0
	elif event is InputEventScreenDrag:
		steer = _steer_from(event.position)
	elif event is InputEventKey and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				steer = -1.0 if event.pressed else 0.0
			KEY_RIGHT, KEY_D:
				steer = 1.0 if event.pressed else 0.0


## Aktuelles Lieferziel (Weltpunkt des Abwurfrings).
func current_drop() -> Vector2:
	if parcel < _drop_points.size():
		return _drop_points[parcel]
	return Vector2.ZERO


## Autopilot für Screenshot-Läufe: fährt die Wegweiser-Route ab (also über die
## Straßen, nicht quer über die Wiesen). Er greift NUR an `steer` an — genau
## dort, wo sonst der Finger liegt, also ändert er keine einzige Spielregel.
func _autopilot() -> void:
	var to := _lookahead() - van_pos
	if to.length() < 0.5:
		return
	var want := atan2(to.x, -to.y)
	var diff := wrapf(want - van_heading, -PI, PI)
	steer = clampf(diff * BOT_STEER_GAIN, -1.0, 1.0)


## Erster Routenpunkt weiter als BOT_LOOKAHEAD_M — der letzte, wenn keiner passt.
func _lookahead() -> Vector2:
	for point: Vector2 in _route:
		if van_pos.distance_to(point) >= BOT_LOOKAHEAD_M:
			return point
	return _route[-1] if not _route.is_empty() else current_drop()


## Kürzeste Kachelkette vom Wagen zum Abwurfring über die Straßen (Breitensuche
## auf dem 9×9-Raster der Logik). Reine Darstellung/Bot-Hilfe — die Suche liest
## `Logic.is_road`, sie ändert nichts daran.
func _recompute_route() -> void:
	_route.clear()
	if parcel >= _drop_points.size():
		return
	var drop := current_drop()
	var goal := Logic.world_to_tile(drop.x, drop.y)
	var start := _nearest_road_tile(Logic.world_to_tile(van_pos.x, van_pos.y))
	goal = _nearest_road_tile(goal)
	if start == goal:
		_route.append(drop)
		return
	var came: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		if here == goal:
			break
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := here + step
			if came.has(next) or not Logic.is_road(next.x, next.y):
				continue
			came[next] = here
			queue.append(next)
	if not came.has(goal):
		_route.append(drop)
		return
	var chain: Array[Vector2i] = []
	var walk := goal
	while walk != start:
		chain.push_front(walk)
		walk = came[walk]
	for tile: Vector2i in chain:
		var w := Logic.tile_to_world(tile.x, tile.y)
		_route.append(w)
		if _route.size() >= ROUTE_TILES:
			break
	_route.append(drop)


## Nächste befahrbare Kachel zu `tile` (Ziele liegen oft auf einem Bauplatz).
func _nearest_road_tile(tile: Vector2i) -> Vector2i:
	if Logic.is_road(tile.x, tile.y):
		return tile
	var best := tile
	var best_d := 9999
	for r in Logic.GRID:
		for c in Logic.GRID:
			if not Logic.is_road(r, c):
				continue
			var d := absi(r - tile.x) + absi(c - tile.y)
			if d < best_d:
				best_d = d
				best = Vector2i(r, c)
	return best


func _steer_from(pos: Vector2) -> float:
	return clampf((pos.x - view_size.x * 0.5) / (view_size.x * 0.4), -1.0, 1.0)


func _anchor_of(id: String) -> Dictionary:
	for row: Dictionary in Logic.LANDMARKS:
		if str(row["id"]) == id:
			return {"x": float(row["x"]), "z": float(row["z"])}
	return {"x": 0.0, "z": 0.0}


## Abwurfringe der aktuellen Zielliste neu ausrechnen (aus den Kollidern raus).
func _rebuild_drop_points() -> void:
	_drop_points.clear()
	for id in _targets:
		var p := Logic.drop_point(_anchor_of(id), _colliders)
		_drop_points.append(Vector2(float(p["x"]), float(p["z"])))


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Web-ABENDBAND (`CITY_BANDS.dusk` in cityDrive.js, das sich
				# deliveryRush teilt): Himmel #eeb493, Hemi 0,78, Sonne 0,72,
				# Nebel 55…140. Das Tagband darüber sah aus wie eine Landstraße
				# unter Mittagshimmel — der Pfirsichhimmel ist das Markenbild.
				"sky_top": Color(0.86, 0.63, 0.55),
				"sky_horizon": Color(0.933, 0.706, 0.576),
				"ground_horizon": Color(0.72, 0.63, 0.55),
				"ground_bottom": Color(0.4, 0.42, 0.4),
				"fog_color": Color(0.933, 0.706, 0.576),
				"fog_from": 55.0,
				"fog_to": 140.0,
				"glow": 0.32,
				"sun_dir": Vector3(-0.5, -0.5, -0.7),
				"sun_color": Color(1.0, 0.855, 0.706),
				"sun_energy": 0.72,
				"ambient_color": Color(0.9, 0.79, 0.71),
				"ambient": 1.2,
				"fill_color": Color(0.72, 0.76, 0.92),
				# Kräftiger als bei den Korridor-Spielen: die Stadt steht frei,
				# also sieht man dauernd sonnenabgewandte Hauswände. Mit 0,14
				# fielen die zu schwarzen Platten zusammen.
				"fill_energy": 0.5,
				# Etwas satter und knackiger als die Bühnen-Vorgabe (1,14/1,05):
				# der Pfirsichdunst wusch Wiese und Fassaden zu Pastell aus.
				"saturation": 1.22,
				"contrast": 1.07,
				"hfov": HFOV_BASE,
				"shadow_distance": 60.0,
				"far": 420.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", _colliders, ctx.rng())
	_build_van()
	_build_ring()
	_build_route()
	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	# Schmal und weit außen: in der Häuserschlucht legten sich breite Striche
	# als weiße Stangen über die Fassaden (`no_depth_test`).
	_streaks.call("build", 14, Vector2(3.4, 4.6), Vector2(6.0, 14.0), Vector2(0.045, 1.0))
	_dust = (
		Fx
		. particles(
			{
				# Klein und blass: mit 0,34 m Kantenlänge und 0,7 Deckkraft lag
				# hinter dem Wagen eine Spur heller WÜRFEL auf dem Asphalt statt
				# einer Staubfahne.
				"color": Color(0.86, 0.82, 0.72, 0.32),
				"amount": 18,
				"lifetime": 0.6,
				"speed": Vector2(0.6, 1.8),
				"spread": 40.0,
				"gravity": Vector3(0.0, -2.2, 0.0),
				"size": Vector2(0.06, 0.18),
			}
		)
	)
	_stage.add_child(_dust)
	_pop = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.85, 0.4, 1.0),
				"amount": 24,
				"lifetime": 0.9,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(2.0, 5.0),
				"spread": 180.0,
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.12, 0.3),
			}
		)
	)
	_stage.add_child(_pop)
	# G5: Fahrgefühl-Schicht (Motor-Loop, Bump-Drossel, Banner-/Kompass-Draw).
	_feel = Feel.new()
	add_child(_feel)
	_feel.build_motor()


## Lieferwagen + Gooby + Paketstapel. Gooby thront SICHTBAR vorn auf dem
## Fahrerhaus — im Fahrerhaus säße er hinter der Ladekiste und wäre für die
## Verfolgerkamera unsichtbar; die Pakete stapeln sich hinter ihm auf dem Dach.
func _build_van() -> void:
	_van = Node3D.new()
	_stage.add_child(_van)
	_van.add_child(Models.node(VAN_GLB, VAN_WIDTH_M, true))
	var size := Models.fitted_size(VAN_GLB, VAN_WIDTH_M)
	_gooby = GoobyMount.new()
	_gooby.call("mount", GOOBY_H, true, false)
	# `parts()` zieht die Unterkante auf y = 0 — das DACH liegt also bei size.y,
	# nicht bei 0,62·size.y (dort saß Gooby vorher IM Laderaum). Lokales +z ist
	# vorne: Gooby fährt HINTEN auf dem Dach mit (dort ist er der Verfolger-
	# kamera am nächsten und damit groß im Bild), die Pakete stehen vor ihm.
	_gooby.position = Vector3(0.0, size.y * 0.99, -size.z * 0.24)
	_van.add_child(_gooby)
	var parcel_w := 1.1
	for i in int(tune["PARCELS"]):
		var box := Models.node(PARCEL_GLB, parcel_w, true)
		box.position = Vector3(
			-0.62 if i % 2 == 0 else 0.62,
			size.y * 0.99,
			size.z * 0.12 + floorf(float(i) / 2.0) * parcel_w * 1.1
		)
		box.rotation.y = fmod(float(i) * 0.7, 0.6)
		_van.add_child(box)
		_parcels.append(box)


## Abwurfring: leuchtender Reifen plus Lichtsäule, damit das Ziel schon aus
## zwei Blocks Entfernung im Bild steht.
func _build_ring() -> void:
	_ring = Node3D.new()
	_stage.add_child(_ring)
	var radius := float(tune["DROP_RADIUS_M"])
	var torus := Fx.ring(radius, 0.42, Color(1.0, 0.82, 0.3))
	torus.rotation_degrees.x = -90.0
	torus.position.y = 0.2
	_ring.add_child(torus)
	var beam := CylinderMesh.new()
	beam.top_radius = radius * 0.82
	beam.bottom_radius = radius * 0.82
	beam.height = 22.0
	beam.radial_segments = 18
	beam.rings = 1
	beam.material = Fx.glass(Color(1.0, 0.86, 0.42, 0.16), true)
	var pillar := MeshInstance3D.new()
	pillar.mesh = beam
	pillar.position.y = 11.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(pillar)


## Wegweiser-Band: rosa Pfeile auf dem Asphalt, die zum Abwurfring führen —
## dieselbe Lesehilfe wie im Web. Ohne sie fährt man in einer Verfolgerkamera
## blind durch ein Raster aus identischen Blocks.
func _build_route() -> void:
	# Ein flaches Band-Stück von 1 m Länge; `_sync_route` streckt es je Abschnitt
	# über die Instanz-Basis zu einem durchgehenden Läufer. (Die erste Fassung
	# setzte 4,2 m breite Prismen-Pfeile — im Bild lag ein einzelnes Riesendreieck
	# quer auf der Wiese statt eines Wegweisers.)
	var tape := BoxMesh.new()
	tape.size = Vector3(ROUTE_WIDTH_M, 0.05, 1.0)
	# Web: `MeshBasicMaterial(PRIMARY_PINK, opacity 0.55)` — also UNBELEUCHTET.
	# Als beleuchtetes Material lag das Band im Schlagschatten der Häuser und
	# verschwand genau dort, wo man es zum Abbiegen braucht.
	# G5 (Audit A §2.7): 0,44 statt 0,55 Deckkraft — das grelle Vollband
	# dominierte das Bild (Beleg deliveryRush_hoch.png), lesbar bleibt es.
	tape.material = Fx.glass(Color(0.95, 0.36, 0.62, 0.44), true)
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.09, 0.0))
	_route_prop = MultiProp.new()
	_stage.add_child(_route_prop)
	# Drei Instanzen je Abschnitt, dazu Abwurfpunkt und Schleppe hinter dem Wagen.
	_route_prop.call("build", [{"mesh": tape, "xform": lift}], (ROUTE_TILES + 3) * 3)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_tint(_time_label)
	add_child(_time_label)
	_target_label = Label.new()
	_target_label.theme_type_variation = &"CaptionLabel"
	_tint(_target_label)
	add_child(_target_label)
	_hint_label = _feel.make_hint(_hint_plate)
	add_child(_hint_label)
	_update_labels()


## Heller Text mit weichem Schattenrand — er liegt auf Straße und Wiese.
func _tint(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.24, 0.16, 0.5))
	label.add_theme_constant_override("outline_size", 7)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _spawn_traffic() -> void:
	var count := MinigameFrameworkLogic.js_round(TRAFFIC_BASE * float(tune["TRAFFIC_DENSITY_MULT"]))
	for i in count:
		(
			_traffic
			. append(
				{
					"s": rng.next() * 480.0,
					"speed": TRAFFIC_SPEED * (0.8 + rng.next() * 0.5),
					"cross": i % 3 == 2,
					"lane": 2.5 if rng.next() < 0.5 else -2.5,
					"tint": Color(0.85, 0.35, 0.4) if i % 2 == 0 else Color(0.42, 0.62, 0.9),
				}
			)
		)


func _step_van(delta: float) -> void:
	van_heading += steer * VAN_TURN_RATE * delta
	var top := VAN_TOP_SPEED * float(tune["SPEED_MULT"]) * car_speed_mult
	var tile := Logic.world_to_tile(van_pos.x, van_pos.y)
	if not Logic.is_road(tile.x, tile.y):
		top *= OFFROAD_FACTOR
	van_speed = move_toward(van_speed, top, VAN_ACCEL * delta)
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var next_pos := van_pos + dir * van_speed * delta
	if _blocked(next_pos):
		van_speed *= 0.3
		# G5 (Audit A §2.7): gedrosselter Bump statt mg_junk-Spam jeden Frame —
		# Ton-Cooldown, Karosserie-Ruck und Kontakt-Staub macht die Feel-Schicht.
		_feel.bump(self, _reduced_motion(), _dust, Vector3(next_pos.x, 0.5, next_pos.y))
	else:
		van_pos = next_pos
	var limit := Logic.TILE_M * (Logic.GRID * 0.5)
	van_pos.x = clampf(van_pos.x, -limit, limit)
	van_pos.y = clampf(van_pos.y, -limit, limit)


func _blocked(pos: Vector2) -> bool:
	for b in _colliders:
		if (
			pos.x > float(b["minX"])
			and pos.x < float(b["maxX"])
			and pos.y > float(b["minZ"])
			and pos.y < float(b["maxZ"])
		):
			return true
	return false


func _step_traffic(delta: float) -> void:
	for car in _traffic:
		car["s"] = fposmod(float(car["s"]) + float(car["speed"]) * delta, 480.0)
		var p := _traffic_pos(car)
		if _crash_cool <= 0.0 and p.distance_to(van_pos) <= TRAFFIC_HIT_M:
			_crash()


## Position eines Verkehrsautos auf seinem geschlossenen Kurs.
func _traffic_pos(car: Dictionary) -> Vector2:
	var lane := float(car["lane"])
	if bool(car["cross"]):
		# Kreuzstraße r = 4 (z = 0), hin und zurück.
		var s := fmod(float(car["s"]), 240.0)
		var x := (s if s <= 120.0 else 240.0 - s) - 60.0
		return Vector2(x, lane)
	var s2 := float(car["s"])
	if s2 < 120.0:
		return Vector2(-60.0 + s2, -60.0 + lane)
	if s2 < 240.0:
		return Vector2(60.0 - lane, -60.0 + (s2 - 120.0))
	if s2 < 360.0:
		return Vector2(60.0 - (s2 - 240.0), 60.0 - lane)
	return Vector2(-60.0 + lane, 60.0 - (s2 - 360.0))


## Fahrtrichtung eines Verkehrsautos (numerisch aus zwei Abtastungen — die
## Kurse sind Streckenzüge, eine Ableitung wäre an den Ecken unstetig).
func _traffic_dir(car: Dictionary) -> Vector2:
	var probe := {
		"s": fposmod(float(car["s"]) + 0.4, 480.0), "lane": car["lane"], "cross": car["cross"]
	}
	var step := _traffic_pos(probe) - _traffic_pos(car)
	return step.normalized() if step.length() > 0.001 else Vector2(0.0, 1.0)


func _crash() -> void:
	_crash_cool = CRASH_COOLDOWN_SEC
	crashes += 1
	var prev := score
	score = Logic.apply_crash(score)
	var extra := Logic.fragile_crash_penalty(fragile_index, parcel, fragile_damaged)
	if extra > 0:
		fragile_damaged = true
		score = maxi(0, score - extra)
		_set_banner(I18nService.t("mg.deliveryRush.fragile_broken", {"n": extra}))
	else:
		_set_banner(I18nService.t("mg.deliveryRush.crash", {"n": int(tune["CRASH_PENALTY"])}))
	van_speed *= 0.2
	delivery_streak = 0
	AudioDirector.try_play(self, "mg_spill", 0.85)
	_gooby.call("emote", "dizzy", 1.5)
	# G5: auch der Verkehrs-Crash ruckt die Karosserie (KEIN Screenshake).
	_feel.kick()
	if not _reduced_motion():
		Fx.burst(_dust, _van.global_position + Vector3(0.0, 0.6, 0.0))
	# KEIN Screenshake: Dauerfahrt, Motion-Comfort-Regel.
	if ctx.juice != null:
		ctx.juice.hit_freeze(70)
		# Kurzer roter Randblitz statt Shake: klar, aber nicht bestrafend.
		ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
	ctx.report_score(score, score - prev)


func _check_drop(before: Vector2) -> void:
	if parcel >= _targets.size():
		return
	var center := current_drop()
	var hit := Logic.segment_hits_drop(
		{"x": before.x, "z": before.y},
		{"x": van_pos.x, "z": van_pos.y},
		{"x": center.x, "z": center.y},
		float(tune["DROP_RADIUS_M"])
	)
	if not hit:
		return
	var prev := score
	score = Logic.apply_drop(score)
	var bonus := Logic.fragile_delivery_bonus(fragile_index, parcel, fragile_damaged)
	if bonus > 0:
		score += bonus
	_visited_landmarks.append(_targets[parcel])
	drops += 1
	parcel += 1
	delivery_streak += 1
	leg_elapsed = 0.0
	# Steigende Tonhöhe pro Lieferserie — der stärkste Dopamin-Hebel.
	AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(delivery_streak))
	_stage.call("pulse_glow", 1.0)
	_gooby.call("emote", "ecstatic", 1.4)
	# Q2: Gold-Pop am Ring nur ohne Reduced Motion (eigene Fx.burst-Call-Site).
	if not _reduced_motion():
		Fx.burst(_pop, Vector3(center.x, 1.2, center.y))
	if ctx.juice != null:
		ctx.juice.float_text(_project(center), "+%d" % (score - prev), Color(1.0, 0.82, 0.35))
		ctx.juice.overlay_ring(_project(center), Color(1.0, 0.85, 0.35), 76.0)
		ctx.juice.hit_freeze(50)
		# G5: JEDE Zustellung feiert kurz — kleiner Konfetti-Gruß am Ziel
		# (den großen Regen behält der Zeitbonus-Sieg; RM gatet der JuiceKit).
		ctx.juice.confetti(30)
		if delivery_streak >= 2:
			ctx.juice.show_combo(delivery_streak)
	_set_banner(
		I18nService.t("mg.deliveryRush.delivered", {"n": drops, "max": int(tune["PARCELS"])})
	)
	ctx.report_score(score, score - prev)
	if drops >= int(tune["PARCELS"]):
		if bool(tune["ENDLESS"]):
			# Endlos: neue Runde Ziele, weiterfahren bis 3 Pakete verfallen.
			var ids: Array[String] = []
			for row: Dictionary in Logic.LANDMARKS:
				ids.append(str(row["id"]))
			_targets = Logic.pick_deliveries(rng, ids)
			_rebuild_drop_points()
			parcel = 0
			drops = 0
			fragile_index = Logic.pick_fragile_parcel(rng)
			fragile_damaged = false
			return
		_finish_with_bonus()


func _expire_parcel() -> void:
	leg_elapsed = 0.0
	delivery_streak = 0
	AudioDirector.try_play(self, "mg_junk")
	if ctx.juice != null:
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
	_gooby.call("emote", "sad", 1.4)
	var ended := Logic.record_expiry(_endless_state)
	_set_banner(
		I18nService.t(
			"mg.deliveryRush.expired",
			{"n": int(_endless_state["expired"]), "max": int(_endless_state["limit"])}
		)
	)
	if ended:
		_finish()
		return
	parcel = mini(parcel + 1, _targets.size() - 1)


func _finish_with_bonus() -> void:
	var prev := score
	var bonus := Logic.time_bonus(elapsed, tune)
	score += bonus
	ctx.report_score(score, score - prev)
	_set_banner(I18nService.t("mg.deliveryRush.time_bonus", {"n": bonus}))
	AudioDirector.try_play(self, "mg_win")
	if ctx.juice != null:
		# Siegmoment: kurze Zeitlupe + Goldblitz + Konfetti.
		ctx.juice.win_moment()
	_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	# W13/SAMMLUNG: belieferte Landmarken füllen das landmarks-Set (Host
	# bucht firstOnly via CollectionsLogic.award_report — Web framework.js).
	(
		ctx
		. report_end(
			{
				"score": score,
				"drops": drops,
				"crashes": crashes,
				"elapsed": elapsed,
				"collections": {"landmarks": _visited_landmarks},
			}
		)
	)


func _set_banner(text: String, sec := 1.6) -> void:
	_banner = text
	_banner_t = sec


## Label UND Plate hängen am selben Alpha (Feel.hint_alpha, tea_party-Muster).
func _fade_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = Feel.hint_alpha(elapsed)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.deliveryRush.expired_count",
			{"n": int(_endless_state["expired"]), "max": int(_endless_state["limit"])}
		)
	else:
		_time_label.text = I18nService.t("mg.game.time", {"sec": int(elapsed)})
	if parcel < _targets.size():
		var name_key := "mg.deliveryRush.spot.%s" % _targets[parcel]
		var mark := " ★" if parcel == fragile_index else ""
		_target_label.text = I18nService.t(
			"mg.deliveryRush.target",
			{"name": I18nService.t(name_key) + mark, "n": drops + 1, "max": int(tune["PARCELS"])}
		)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


func _sync_world(delta: float) -> void:
	_stage.call("tick", delta)
	_gooby.call("tick", delta)
	_sync_van()
	_sync_traffic()
	_sync_ring()
	_sync_route()
	_sync_camera(delta)


## Pfeilkette entlang der Route: ein Pfeil je Zwischenpunkt, ausgerichtet auf
## den jeweils nächsten. Alles in EINEM MultiMesh (ein Draw-Call).
func _sync_route() -> void:
	_route_prop.call("begin")
	# Das Band beginnt HINTER dem Wagen, nicht an ihm: von der Verfolgerkamera
	# aus deckt der Kasten die eigene Kachel komplett ab, und ein Läufer, der
	# erst an der Stoßstange anfängt, ist schlicht unsichtbar. Im Web zieht sich
	# der rosa Streifen unter dem Wagen hindurch bis in den Vordergrund — das
	# ist es, was ihn als durchgehende Fahrspur lesbar macht.
	var back := Vector2(sin(van_heading), -cos(van_heading)) * ROUTE_TRAIL_M
	var chain: Array[Vector2] = [van_pos - back, van_pos]
	chain.append_array(_route)
	var goal := current_drop()
	for i in range(1, chain.size()):
		var step := chain[i] - chain[i - 1]
		if step.length() < 0.5:
			continue
		var dir := step.normalized()
		var fwd := Vector3(dir.x, 0.0, dir.y)
		var right := Vector3.UP.cross(fwd).normalized()
		# Dritte Spalte = lokale z-Achse: mit der Teilstücklänge gestreckt liegt
		# das Band lückenlos, egal wie lang der Abschnitt ist.
		var piece := step.length() / 3.0
		for k in 3:
			var t := (float(k) + 0.5) / 3.0
			var p := chain[i - 1].lerp(chain[i], t)
			# G5 (Audit A §2.7): in Hausnähe wird das Band schmaler — auf den
			# letzten Metern dominierte der volle Läufer das Zielbild.
			var slim := Feel.route_slim(p.distance_to(goal))
			var basis := Basis(right * slim, Vector3.UP, fwd * piece)
			_route_prop.call("push", Transform3D(basis, Vector3(p.x, 0.0, p.y)))
	_route_prop.call("flush")


func _sync_van() -> void:
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var right := Vector3.UP.cross(fwd).normalized()
	var lean := clampf(steer * van_speed / VAN_TOP_SPEED, -1.0, 1.0)
	var basis := Basis(right, Vector3.UP, fwd) * Basis(Vector3.BACK, -lean * 0.06)
	# G5: Karosserie-Ruck nach Bump/Crash — kurzer Nicker um die Querachse,
	# der über die Feel-Schicht abklingt (KEIN Screenshake, Motion-Comfort).
	if _feel.body_kick > 0.0:
		basis = basis * Basis(Vector3.RIGHT, _feel.body_kick * 0.06)
	_van.transform = Transform3D(basis, Vector3(van_pos.x, 0.0, van_pos.y))
	var left := maxi(0, int(tune["PARCELS"]) - drops)
	for i in _parcels.size():
		_parcels[i].visible = i < left
	_dust.global_position = _van.global_transform * Vector3(0.0, 0.15, -VAN_LEN_M * 0.4)
	_dust.emitting = van_speed > VAN_TOP_SPEED * 0.55 and not _reduced_motion()


func _sync_traffic() -> void:
	var prop: Node3D = _world.get("traffic_prop")
	prop.call("begin")
	for car in _traffic:
		var p := _traffic_pos(car)
		var d := _traffic_dir(car)
		var fwd := Vector3(d.x, 0.0, d.y)
		var right := Vector3.UP.cross(fwd).normalized()
		var pose := Transform3D(Basis(right, Vector3.UP, fwd), Vector3(p.x, 0.0, p.y))
		prop.call("push", pose, car["tint"])
	prop.call("flush")


func _sync_ring() -> void:
	if parcel >= _drop_points.size():
		_ring.visible = false
		return
	var drop := current_drop()
	_ring.visible = true
	_ring.position = Vector3(drop.x, 0.0, drop.y)
	var pulse := 1.0 + 0.08 * sin(elapsed * 4.0)
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_ring.rotation.y = elapsed * 0.6


func _sync_camera(delta: float) -> void:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var dir := Vector2(sin(van_heading), -cos(van_heading))
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var lift := CAM_LIFT + (0.0 if landscape else CAM_PORTRAIT_LIFT)
	var back := CAM_BACK + (0.0 if landscape else CAM_PORTRAIT_BACK)
	var here := Vector3(van_pos.x, 0.0, van_pos.y)
	var wanted := here - fwd * back + Vector3(0.0, lift, 0.0)
	# Hochkant öffnet die Blickwinkel-Umrechnung den senkrechten Ausschnitt weit:
	# mit dem Querformat-Zielpunkt füllte reiner Himmel die obere Bildhälfte.
	# Also zielt die Kamera hochkant kürzer und tiefer — der Blick liegt dann
	# auf der Straße, wo gespielt wird.
	var ahead := CAM_LOOK_AHEAD - (0.0 if landscape else CAM_PORTRAIT_AHEAD)
	var aim_y := 1.6 - (0.0 if landscape else CAM_PORTRAIT_AIM_DOWN)
	var look := here + fwd * ahead + Vector3(0.0, aim_y, 0.0)
	# G5 M1: im Intro hebt sich die Kamera zur Stadt-Totale und schwebt dann
	# in die Verfolger-Pose (Reduced Motion überspringt den Flug).
	if _intro_left > 0.0 and not _reduced_motion():
		var e := 1.0 - ease(clampf(1.0 - _intro_left / INTRO_S, 0.0, 1.0), 0.4)
		wanted += Vector3(0.0, INTRO_LIFT, 0.0) * e - fwd * (INTRO_BACK * e)
	if not _cam_ready:
		_cam_pos = wanted
		_cam_look = look
		_cam_ready = true
	_cam_pos = _cam_pos.lerp(wanted, minf(1.0, delta * 6.0))
	_cam_look = _cam_look.lerp(look, minf(1.0, delta * 9.0))
	# W19 Kulissen-Klemme: NIE ein Gebäude zwischen Kamera und Wagen — auch die
	# GEGLÄTTETE Pose wird gekappt (der Lerp schwenkt beim Abbiegen sonst durch
	# Blockecken); die Intro-Totale bleibt außen vor (hoher Blick, Sim gated).
	if _intro_left <= 0.0:
		_cam_pos = Feel.clamp_cam(_cam_pos, van_pos, _colliders)
	cam.position = _cam_pos
	if _cam_pos.distance_to(_cam_look) > 0.05:
		cam.look_at(_cam_look, Vector3.UP)
	var band01 := clampf(van_speed / VAN_TOP_SPEED, 0.0, 1.0)
	_stage.call("set_fov_bonus", HFOV_KICK * band01)
	_streaks.set("enabled", not _reduced_motion())
	_streaks.call("update", delta, van_speed, SpeedLines.rate_at(van_speed, STREAK_RATE))


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


## Weltmeter (x, z) → Bildschirmpixel (für Fließtexte und den Kompass).
func _project(world: Vector2) -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return view_size * 0.5
	return cam.unproject_position(Vector3(world.x, 1.0, world.y))


# ── 2D-Overlay (Kompass + Banner über der 3D-Szene) ──────────────────────


## G5 M7 (Audit A §2.7) + W19: Hinweis-Plate, Kompass-Meter mit Kontur und
## Banner auf Milchglas — alle Maler leben in der Feel-Schicht. Der Kompass
## ist in der Verfolgerkamera PFLICHT (Ring oft hinter Häusern).
func _draw() -> void:
	_feel.draw_hint_plate(self, _hint_plate, _hint_label, Feel.hint_alpha(elapsed))
	if parcel < _drop_points.size():
		_feel.draw_compass(self, van_pos, van_heading, current_drop(), view_size, _ui)
	_feel.draw_banner(self, _banner, _banner_t, view_size, _ui)
