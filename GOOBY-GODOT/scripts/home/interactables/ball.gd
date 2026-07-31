class_name WurfBall
extends Node3D
## Ball-Wurf im Wohnzimmer (W13/BALL, EVAL-Restliste #17) — die letzte
## fehlende Home-Interaktion. Web-Referenz: GOOBY/src/home/interactions.js
## (setupBall/maybeFetch). Der Node ist NUR Verdrahtung + Visuals; die
## komplette Physik/Zustandsmaschine lebt PUR in BallLogic (ball_logic.gd).
##
## Ablauf: Flick über dem Ball → ballistischer Flug mit Bounce → Gooby
## flitzt hin (GoobyReactions.apportiere, Wackel-Ohren beim Fangen) →
## Kopfstoß zurück Richtung Spawn → +3 Spaß, Gewicht −0.2, `balls`-Counter
## +1 (Profil-Statistik), Herzchen + „+3“-Float, 15 s Apport-Cooldown.
##
## Einhängen: liegt als Kind der Wohnzimmer-Szene (scenes/home/wohnzimmer.tscn)
## und wartet auf `ready_for_reveal` des Raums — dann steht das Grid und der
## Ball sucht sich deterministisch eine freie Zelle vor der Kamera.

## Bevorzugter Liegeplatz (Anteil der Grid-Maße): rechts vor der Raummitte.
const SPAWN_ANTEIL := Vector2(0.62, 0.66)
## Flick-Erkennung: Radius um den Ball (Web: Ray-Distanz 0.35 m) + wie viele
## letzte Pointer-Geschwindigkeiten gemittelt werden.
const GRIFF_RADIUS := 0.35
const FLICK_PROBEN := 3
## Web-Optik: Ball dreht beim Rollen mit (mesh.rotation += vel * dt * 6).
const ROLL_FAKTOR := 6.0
const HERZ_TEILE := 3

## Tests/Screenshots: Zeit injizierbar (< 0 = echte Systemzeit).
var now_ms_override := -1
## Zufall nur für die Spruch-Auswahl — injizierbar (AGENTS-Regel).
var rng := RandomNumberGenerator.new()
var logic := BallLogic.new()

var _room: Node = null
var _gs: Object = null
var _spawn := Vector3.ZERO
var _mount: Node3D = null
var _greift := false
var _flick_spuren: Array[Vector2] = []


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	var room := get_parent()
	if room != null and room.has_signal("ready_for_reveal"):
		room.ready_for_reveal.connect(_on_room_ready, CONNECT_ONE_SHOT)


func _on_room_ready() -> void:
	_room = get_parent()
	if _room == null or not _room.has_method("game_state"):
		return
	_gs = _room.game_state()
	rng.randomize()
	_spawn = _finde_liegeplatz()
	position = _spawn
	_baue_optik()
	set_process(true)
	set_process_input(true)


# ── Aufbau ────────────────────────────────────────────────────────────────────


## Deterministischer Liegeplatz: freie Grid-Zelle, die dem bevorzugten
## Punkt (rechts vor der Raummitte, Kameraseite) am nächsten liegt.
func _finde_liegeplatz() -> Vector3:
	var grid: GridData = _room.get("grid")
	if grid == null:
		return Vector3(1.0, 0.0, 1.0)
	var wunsch := Vector2(grid.size.x * SPAWN_ANTEIL.x, grid.size.y * SPAWN_ANTEIL.y)
	var best := Vector2i(grid.size.x / 2, grid.size.y / 2)
	var best_d := INF
	for cell: Vector2i in grid.free_cells():
		var d := Vector2(cell.x + 0.5, cell.y + 0.5).distance_squared_to(wunsch)
		if d < best_d:
			best_d = d
			best = cell
	return GridData.world_center(best, Vector2i.ONE, 0)


## Optik: Blender-Prop (tools/blender/props/build_ball_prop.py) mit weichem
## Primitive-Fallback (Headless/kaputter Import — wie HomeProps üblich).
func _baue_optik() -> void:
	_mount = Node3D.new()
	_mount.name = "BallMount"
	_mount.position = logic.pos
	add_child(_mount)
	var glb := HomeProps.prop_glb("wurfball")
	if glb != null:
		_mount.add_child(glb)
	else:
		var mesh := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = BallLogic.RADIUS
		kugel.height = BallLogic.RADIUS * 2.0
		mesh.mesh = kugel
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#FF7BA9")
		mat.roughness = 0.55
		mesh.material_override = mat
		_mount.add_child(mesh)
	_mount.add_child(_mache_griff_zone())


func _mache_griff_zone() -> Area3D:
	var area := Area3D.new()
	area.name = "BallGriff"
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = GRIFF_RADIUS
	shape.shape = kugel
	area.add_child(shape)
	area.input_event.connect(_on_griff_input)
	return area


# ── Flick-Eingabe ─────────────────────────────────────────────────────────────


func _on_griff_input(
	_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int
) -> void:
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed or logic.zustand != BallLogic.RUHT or _room_busy():
		return
	_greift = true
	_flick_spuren.clear()


## Während des Griffs Pointer-Geschwindigkeiten sammeln; beim Loslassen
## werfen. Nie konsumieren — andere Eingaben laufen ungestört weiter.
func _input(event: InputEvent) -> void:
	if not _greift:
		return
	if event is InputEventMouseMotion:
		_merke_flick((event as InputEventMouseMotion).velocity)
	elif event is InputEventScreenDrag:
		_merke_flick((event as InputEventScreenDrag).velocity)
	var losgelassen: bool = (
		(event is InputEventMouseButton and not event.pressed)
		or (event is InputEventScreenTouch and not event.pressed)
	)
	if losgelassen:
		_greift = false
		_wirf(_flick_mittel())


func _merke_flick(velocity_px: Vector2) -> void:
	_flick_spuren.append(velocity_px)
	if _flick_spuren.size() > FLICK_PROBEN:
		_flick_spuren.pop_front()


func _flick_mittel() -> Vector2:
	if _flick_spuren.is_empty():
		return Vector2.ZERO
	var summe := Vector2.ZERO
	for probe: Vector2 in _flick_spuren:
		summe += probe
	return summe / _flick_spuren.size()


func _wirf(flick_px: Vector2) -> void:
	if _room_busy() or not logic.werfen(flick_px):
		return
	AudioDirector.try_play(self, "gvz_pop", 1.15)


# ── Flug-Takt ─────────────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if logic.zustand != BallLogic.FLIEGT and logic.zustand != BallLogic.BRINGT_ZURUECK:
		return
	var schritt := logic.step(delta)
	_mount.position = logic.pos
	_mount.rotation.x += logic.vel.z * delta * ROLL_FAKTOR
	_mount.rotation.z -= logic.vel.x * delta * ROLL_FAKTOR
	if bool(schritt["bounced"]):
		AudioDirector.try_play(self, "mg_good", 1.05)
	if bool(schritt["resting"]):
		_gelandet()


func _gelandet() -> void:
	var gooby := _gooby()
	var dist := INF
	if gooby is Node3D:
		var ball_welt := global_position + logic.pos
		var von: Vector3 = (gooby as Node3D).global_position
		dist = Vector2(ball_welt.x - von.x, ball_welt.z - von.z).length()
	match logic.landung_verarbeiten(dist, _now_ms()):
		BallLogic.LANDUNG_APPORT:
			_starte_apport()
		_:
			pass


# ── Apport: Gooby holt den Ball ───────────────────────────────────────────────


func _starte_apport() -> void:
	var ziel := global_position + logic.pos
	var runner := _room.get_node_or_null("GoobyReactions") if _room != null else null
	if runner is GoobyReactions and (runner as GoobyReactions).apportiere(ziel, _on_gooby_faengt):
		return
	if _fallback_lauf(ziel):
		return
	logic.apport_abgebrochen()


## Ohne Reaktions-Runner (nackte Test-Szene): Gooby läuft direkt hin.
func _fallback_lauf(ziel: Vector3) -> bool:
	var gooby := _gooby()
	if gooby == null:
		return false
	_lauf_und_fang(gooby, ziel)
	return true


func _lauf_und_fang(gooby: Node, ziel: Vector3) -> void:
	gooby.set_wander_enabled(false)
	await gooby.walk_to(ziel + Vector3(0.3, 0.0, 0.3), 5.0)
	if gooby.get("rig") != null:
		gooby.rig.set_emotion("ecstatic")
		gooby.rig.play_clip("hop")
	_on_gooby_faengt()
	gooby.set_wander_enabled(true)


## Fang-Moment (Web maybeFetch-Callback): Kopfstoß zurück, Belohnung buchen,
## sichtbar feiern (Float + Herzchen + knuffiger Spruch), Sticker anstoßen.
func _on_gooby_faengt() -> void:
	if logic.kopfstoss(_now_ms()) == Vector3.ZERO:
		return
	AudioDirector.try_play(self, "pet_squish")
	var result := {}
	if _gs != null:
		_gs.update(
			func(state: Dictionary) -> void:
				result.merge(BallLogic.apply_apport_reward(state), true)
		)
		RewardHub.note_action(_gs)
	_feiere(result)


func _feiere(result: Dictionary) -> void:
	if _room == null:
		return
	var ball_welt := global_position + logic.pos
	var gain := int(roundf(float(result.get("fun_gain", 0.0))))
	if gain > 0:
		RewardFx.float_text(_room, ball_welt + Vector3(0.0, 0.6, 0.0), "+%d" % gain, RewardFx.MINT)
	RewardFx.herz_burst(_room, ball_welt + Vector3(0.0, 0.3, 0.0), HERZ_TEILE)
	if _room.has_method("say"):
		_room.say(I18nService.t(BallLogic.spruch_key(rng)))


# ── Helfer ────────────────────────────────────────────────────────────────────


func _gooby() -> Node:
	if _room != null and _room.has_method("gooby"):
		return _room.gooby()
	return null


func _room_busy() -> bool:
	return (
		_room != null and _room.has_method("is_build_mode_active") and _room.is_build_mode_active()
	)


func _now_ms() -> int:
	if now_ms_override >= 0:
		return now_ms_override
	return int(Time.get_unix_time_from_system() * 1000.0)
