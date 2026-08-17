extends Node3D
## 3D-Bühne der fünf Rückbau-Spiele (Agent 3D-A): Himmel/Nebel/Glow, warmes
## Sonnenlicht + kühles Fülllicht und die Kamera samt Orientierungs-Regel.
##
## Die Spiele hängen die Bühne als Kind unter ihre MinigameBase-Wurzel (Node2D).
## Godot rendert die 3D-Welt eines Viewports IMMER hinter den CanvasItems —
## HUD-Labels und Zielhilfen liegen also obenauf und der MinigameBase-Vertrag
## (Node2D-Wurzel, setup/start/pause/end) bleibt unberührt.
##
## Orientierungs-Regel: der Blickwinkel bleibt in BEIDEN Formaten gleich (ein
## ruhiges Tele um 46°, kein Fischauge) — die Anpassung macht die DISTANZ.
## `fit()` rechnet sie in Bildschirmkoordinaten aus, also automatisch richtig
## für das schmale Hochformat und das breite Querformat. Ein aspektabhängiger
## Blickwinkel (der erste Versuch) endet hochkant zwangsläufig bei >100° und
## lässt das Spielfeld winzig in der Bildmitte versinken.

## Grenzen des senkrechten Blickwinkels.
const MIN_VFOV := 22.0
const MAX_VFOV := 78.0

var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment

var _fov := 46.0
var _aspect := 390.0 / 844.0
var _glow_base := 0.0
var _glow_extra := 0.0
var _shake := 0.0
var _shake_amp := 0.0
var _cam_base := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()


## Bühne bauen. `cfg` kennt: sky_top, sky_horizon, ground_horizon,
## ground_bottom, sky_energy, fog (bool), fog_color, fog_from, fog_to,
## glow (float), glow_threshold, sun_dir, sun_color, sun_energy, shadows,
## shadow_distance, fill_color, fill_energy, ambient, hfov, far.
func build(cfg: Dictionary) -> void:
	_rng.randomize()
	_isolate_world()
	environment = Environment.new()
	_build_sky(cfg)
	_build_fog(cfg)
	_build_glow(cfg)
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = float(cfg.get("white", 2.4))
	environment.tonemap_exposure = float(cfg.get("exposure", 1.0))
	# Himmel-Ambient allein kippt die Pastellfarben ins Kalte (der Himmel ist
	# blau). Ein Anteil warmes Grundlicht hält Grün grün und Weiß cremig.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = cfg.get("ambient_color", Color(0.86, 0.88, 0.92))
	environment.ambient_light_sky_contribution = float(cfg.get("sky_ambient", 0.45))
	environment.ambient_light_energy = float(cfg.get("ambient", 0.6))
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = cfg.get("sun_color", Color(1.0, 0.95, 0.86))
	sun.light_energy = float(cfg.get("sun_energy", 1.2))
	sun.light_specular = 0.25
	var dir: Vector3 = cfg.get("sun_dir", Vector3(-0.4, -0.9, -0.3))
	sun.look_at_from_position(Vector3.ZERO, dir.normalized(), Vector3.UP)
	if bool(cfg.get("shadows", true)):
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = float(cfg.get("shadow_distance", 28.0))
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.1
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.light_color = cfg.get("fill_color", Color(0.74, 0.84, 1.0))
	fill.light_energy = float(cfg.get("fill_energy", 0.4))
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.55, -0.4, 0.7), Vector3.UP)
	add_child(fill)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = float(cfg.get("far", 120.0))
	camera.current = true
	add_child(camera)
	_fov = float(cfg.get("fov", 46.0))
	_apply_fov()


## Kamera setzen (Position + Blickpunkt). Das ist zugleich die Ruhelage, auf
## die der Screenshake zurückfällt.
func aim(from: Vector3, look: Vector3) -> void:
	if camera == null:
		return
	camera.position = from
	if not from.is_equal_approx(look):
		camera.look_at(look, Vector3.UP)
	_cam_base = camera.transform


## Kamera so setzen, dass eine Kugel (center, radius) komplett ins Bild passt.
## `pitch_deg` ist der Höhenwinkel der Kamera über dem Ziel, `yaw_deg` dreht
## sie um das Ziel (180° = Blick in +z). Das ist die orientierungsfeste
## Alternative zu handverdrahteten Kamerapositionen: hochkant ist das Bild
## schmaler, die nötige Distanz rechnet sich von selbst.
func frame(center: Vector3, radius: float, pitch_deg: float, yaw_deg := 180.0, pad := 1.08) -> void:
	if camera == null:
		return
	var half_v := deg_to_rad(camera.fov) * 0.5
	var half_h := atan(tan(half_v) * _aspect)
	var distance := (radius * pad) / maxf(0.08, sin(minf(half_v, half_h)))
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	aim(center + dir * distance, center)


## Kamera so weit zurückziehen, dass ALLE `points` im Bild liegen. Sie schaut
## dabei auf `center`, steht `pitch_deg` darüber und `yaw_deg` darum herum.
##
## Warum iterativ statt Formel: eine Bahn ist kein Ball. Eine Hüllkugel würde
## bei einer schmalen, tiefen Bahn viel zu weit wegziehen (hochkant besonders),
## weil sie den kleineren der beiden Halbwinkel bedienen muss. Der Abgleich in
## Bildschirmkoordinaten füllt das Bild in BEIDEN Achsen aus — und tut das für
## Hoch- und Querformat automatisch richtig.
func fit(
	points: Array, center: Vector3, pitch_deg: float, yaw_deg := 180.0, margin := 0.86
) -> void:
	if camera == null or points.is_empty():
		return
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var radius := 0.5
	for point: Vector3 in points:
		radius = maxf(radius, (point - center).length())
	var distance := radius * 2.2
	for _pass in 4:
		aim(center + dir * distance, center)
		var screen := camera.get_viewport().get_visible_rect().size
		if screen.x < 4.0 or screen.y < 4.0:
			return
		var mid := screen * 0.5
		var worst := 0.0
		for point: Vector3 in points:
			if camera.is_position_behind(point):
				worst = maxf(worst, 2.0)
				continue
			var at := camera.unproject_position(point) - mid
			worst = maxf(worst, absf(at.x) / (mid.x * margin))
			worst = maxf(worst, absf(at.y) / (mid.y * margin))
		if absf(worst - 1.0) <= 0.01:
			break
		distance = clampf(distance * worst, radius * 0.6, radius * 40.0)
	aim(center + dir * distance, center)


## Senkrechter Blickwinkel (Grad) — in beiden Orientierungen derselbe.
func set_fov(deg: float) -> void:
	_fov = deg
	_apply_fov()


## Vom Spiel aus apply_view() aufrufen: Seitenverhältnis merken, fov nachziehen.
func apply_size(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		_aspect = size.x / size.y
	_apply_fov()


## True, sobald das Bild höher als breit ist (Hochkant-Regel der Spiele).
func portrait() -> bool:
	return _aspect < 1.0


## Glow-Puls (Treffer, Kombos). Eigener Puls statt JuiceKit.bloom_pulse: das
## Kit kennt nur das Host-WorldEnvironment, unsere Bühne hat ihr eigenes.
func pulse_glow(strength := 0.6) -> void:
	_glow_extra = maxf(_glow_extra, strength)


## Kamera-Rütteln in Metern. Reduced Motion schaltet es ab (gleiche Regel wie
## JuiceKit.shake — hier noch einmal, weil die Kamera dem Kit nicht gehört).
func shake(amount := 0.12, seconds := 0.28) -> void:
	if reduced_motion():
		return
	_shake_amp = maxf(_shake_amp, amount)
	_shake = maxf(_shake, seconds)


## AppSettings-Duck-Typing wie im JuiceKit; ohne Autoload = Bewegung erlaubt.
func reduced_motion() -> bool:
	if not is_inside_tree():
		return false
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.is_reduced_motion())
	return false


## Jeden Frame vom Spiel aufrufen (damit Pause wirklich pausiert).
func tick(delta: float) -> void:
	if _glow_extra > 0.0 and environment != null:
		_glow_extra = maxf(0.0, _glow_extra - 2.2 * delta)
		environment.glow_intensity = _glow_base + _glow_extra
	if camera == null:
		return
	if _shake <= 0.0:
		if not camera.transform.is_equal_approx(_cam_base):
			camera.transform = _cam_base
		return
	_shake = maxf(0.0, _shake - delta)
	var k := _shake_amp * (_shake / 0.28)
	var offset := Vector3(
		_rng.randf_range(-k, k), _rng.randf_range(-k, k), _rng.randf_range(-k, k) * 0.4
	)
	camera.transform = Transform3D(_cam_base.basis, _cam_base.origin + offset)
	if _shake <= 0.0:
		_shake_amp = 0.0
		camera.transform = _cam_base


## Bildschirmpunkt auf eine waagerechte Ebene y = plane_y projizieren
## (Screen-to-World für die unveränderte Touch-Steuerung).
func plane_point(screen: Vector2, plane_y := 0.0) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-5:
		return origin
	return origin + dir * ((plane_y - origin.y) / dir.y)


## Weltpunkt → Bildschirmpixel (Float-Texte, Trefferkreise im HUD).
func to_screen(world: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world)


## Draw-Calls des Frames (Perf-Budget-Nachweis im Screenshot-Treiber).
static func draw_calls() -> int:
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)


## Der MinigameHost hängt das Spiel in einen SubViewport, der standardmäßig die
## World3D des Fensters MITBENUTZT. Ohne eigene Welt landen Bühne und Kamera
## also auch im Hauptfenster: die Kulisse quillt hinter dem Letterbox-Rahmen
## hervor und die Kamera reißt die Szene den anderen Bildschirmen weg. Eine
## eigene World3D je Spiel-Viewport kapselt beides.
func _isolate_world() -> void:
	var viewport := get_viewport()
	if viewport is SubViewport and not viewport.own_world_3d:
		(viewport as SubViewport).own_world_3d = true


func _build_sky(cfg: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = cfg.get("sky_top", Color(0.42, 0.66, 0.95))
	sky_mat.sky_horizon_color = cfg.get("sky_horizon", Color(0.88, 0.94, 1.0))
	sky_mat.sky_energy_multiplier = float(cfg.get("sky_energy", 1.0))
	sky_mat.ground_horizon_color = cfg.get("ground_horizon", Color(0.8, 0.86, 0.88))
	sky_mat.ground_bottom_color = cfg.get("ground_bottom", Color(0.5, 0.54, 0.52))
	sky_mat.sun_angle_max = 28.0
	sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky


func _build_fog(cfg: Dictionary) -> void:
	if not bool(cfg.get("fog", true)):
		return
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = cfg.get("fog_color", Color(0.86, 0.93, 1.0))
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.12
	environment.fog_depth_begin = float(cfg.get("fog_from", 14.0))
	environment.fog_depth_end = float(cfg.get("fog_to", 46.0))
	environment.fog_depth_curve = 0.85
	environment.fog_density = float(cfg.get("fog_density", 1.0))
	environment.fog_sky_affect = 0.0


func _build_glow(cfg: Dictionary) -> void:
	_glow_base = float(cfg.get("glow", 0.3))
	if _glow_base <= 0.0:
		return
	environment.glow_enabled = true
	environment.glow_intensity = _glow_base
	environment.glow_strength = 1.0
	environment.glow_bloom = float(cfg.get("glow_bloom", 0.14))
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.glow_hdr_threshold = float(cfg.get("glow_threshold", 0.9))
	environment.glow_hdr_scale = 2.0


func _apply_fov() -> void:
	if camera == null:
		return
	camera.fov = clampf(_fov, MIN_VFOV, MAX_VFOV)
