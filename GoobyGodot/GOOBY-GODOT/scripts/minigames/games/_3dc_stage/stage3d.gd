extends Node3D
## 3D-Bühne der Minispiele (Agent 3D-C): Kamera, WorldEnvironment (Himmel oder
## Weltraum, dezentes Glow, weiche Tonwertkurve), warmes Sonnen- plus Fülllicht.
##
## Die Spiele hängen die Bühne als Kind unter ihre MinigameBase-Wurzel (Node2D).
## Godot rendert die 3D-Welt eines Viewports immer HINTER den CanvasItems — der
## HUD (Labels, _draw-Overlays) liegt also automatisch obenauf und der
## MinigameBase-Vertrag (Node2D-Wurzel, setup/start/pause/end) bleibt unberührt.
##
## Zwei Bildausschnitts-Regeln (beide über apply_size an die Orientierung
## gekoppelt):
##   set_hfov(deg, min_v)       — waagerechter Blickwinkel bleibt konstant
##                                (Korridore: hochkant wie quer gleich breit);
##                                `min_v` ist ein senkrechter Mindestwinkel, den
##                                das BREITE Format braucht — sonst schrumpft
##                                die Höhe mit dem Seitenverhältnis weg
##   set_half_height(h, dist)   — h Meter sichtbare HALBE Höhe in `dist` Metern
##                                Entfernung (Bühnen, deren 2D-Projektion exakt
##                                erhalten bleiben muss)

## Grenzen des senkrechten Blickwinkels (sonst Fischauge im Hochformat).
const MIN_VFOV := 30.0
const MAX_VFOV := 104.0

var camera: Camera3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment

var _mode := "hfov"
var _hfov := 70.0
var _min_vfov := 0.0
var _half_h := 4.0
var _half_dist := 10.0
var _aspect := 390.0 / 844.0
var _glow_base := 0.3
var _glow_extra := 0.0


## Bühne bauen. `cfg` versteht: space (bool), bg (Color), sky_top, sky_horizon,
## ground_horizon, ground_bottom, ambient_color, ambient (float), sun_dir,
## sun_color, sun_energy, fill_color, fill_energy, shadows (bool),
## shadow_distance, glow (float), glow_threshold, fog (bool), fog_color,
## fog_from, fog_to, far.
func build(cfg: Dictionary) -> void:
	environment = Environment.new()
	if bool(cfg.get("space", false)):
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = cfg.get("bg", Color(0.03, 0.04, 0.13))
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = cfg.get("ambient_color", Color(0.5, 0.55, 0.9))
	else:
		_build_sky(cfg)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = float(cfg.get("ambient", 1.0))
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.7
	_build_glow(cfg)
	_build_fog(cfg)
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = cfg.get("sun_color", Color(1.0, 0.95, 0.86))
	sun.light_energy = float(cfg.get("sun_energy", 1.2))
	sun.light_specular = 0.25
	var dir: Vector3 = cfg.get("sun_dir", Vector3(-0.4, -0.9, -0.45))
	sun.look_at_from_position(Vector3.ZERO, dir.normalized(), Vector3.UP)
	if bool(cfg.get("shadows", true)):
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = float(cfg.get("shadow_distance", 28.0))
		sun.shadow_bias = 0.05
		sun.shadow_normal_bias = 1.2
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.light_color = cfg.get("fill_color", Color(0.76, 0.85, 1.0))
	fill.light_energy = float(cfg.get("fill_energy", 0.42))
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.65, -0.3, 0.7), Vector3.UP)
	add_child(fill)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.08
	camera.far = float(cfg.get("far", 220.0))
	camera.current = true
	add_child(camera)
	_hfov = float(cfg.get("hfov", 70.0))
	_apply_fov()


## Vom Spiel aus in apply_view() aufrufen: Seitenverhältnis merken, fov ziehen.
func apply_size(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		_aspect = size.x / size.y
	_apply_fov()


## Waagerechter Basis-Blickwinkel (Grad). `min_v` hält im Querformat eine
## senkrechte Untergrenze: dort ist das Seitenverhältnis > 2, ein konstanter
## Waagerechtwinkel presst die Höhe sonst auf ein Viertel zusammen und
## schneidet alles ab, was unter der Blickachse steht (z. B. das eigene Schiff).
func set_hfov(deg: float, min_v := 0.0) -> void:
	_mode = "hfov"
	_hfov = deg
	_min_vfov = min_v
	_apply_fov()


## Exakte Rahmung: `half_h` Meter halbe Bildhöhe in `dist` Metern Entfernung.
func set_half_height(half_h: float, dist: float) -> void:
	_mode = "half"
	_half_h = maxf(0.05, half_h)
	_half_dist = maxf(0.1, dist)
	_apply_fov()


## Sichtbare halbe Breite auf der Bezugsebene (Layout-Hilfe der Spiele).
func half_width() -> float:
	return visible_half_height() * _aspect


## Sichtbare halbe Höhe auf der Bezugsebene.
func visible_half_height() -> float:
	if _mode == "half":
		return _half_h
	return tan(deg_to_rad(camera.fov) * 0.5) * _half_dist


## Glow-Puls der EIGENEN Bühne (JuiceKit kennt nur das Host-Environment).
func pulse_glow(strength := 0.6) -> void:
	_glow_extra = maxf(_glow_extra, strength)


## Jeden Frame vom Spiel aus ticken (so pausiert die Bühne mit dem Spiel).
func tick(delta: float) -> void:
	if _glow_extra <= 0.0:
		return
	_glow_extra = maxf(0.0, _glow_extra - 2.2 * delta)
	environment.glow_intensity = _glow_base + _glow_extra


## Bildschirmpunkt → Punkt auf einer waagerechten Ebene (y = plane_y).
func ground_point(screen: Vector2, plane_y := 0.0) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return origin
	var t := (plane_y - origin.y) / dir.y
	return origin + dir * maxf(0.0, t)


## Bildschirmpunkt → Punkt auf einer senkrechten Ebene (z = plane_z).
func wall_point(screen: Vector2, plane_z := 0.0) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.z) < 0.0001:
		return origin
	var t := (plane_z - origin.z) / dir.z
	return origin + dir * maxf(0.0, t)


## Weltpunkt → Bildschirmpixel (für 2D-Overlays über der Bühne).
func to_screen(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


## Draw-Calls des laufenden Frames (Perf-Budget-Nachweis).
static func draw_calls() -> int:
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)


func _build_sky(cfg: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = cfg.get("sky_top", Color(0.44, 0.68, 0.95))
	sky_mat.sky_horizon_color = cfg.get("sky_horizon", Color(0.94, 0.93, 0.86))
	sky_mat.sky_energy_multiplier = float(cfg.get("sky_energy", 1.0))
	sky_mat.ground_horizon_color = cfg.get("ground_horizon", Color(0.9, 0.88, 0.82))
	sky_mat.ground_bottom_color = cfg.get("ground_bottom", Color(0.62, 0.6, 0.56))
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky


func _build_glow(cfg: Dictionary) -> void:
	_glow_base = float(cfg.get("glow", 0.3))
	if _glow_base <= 0.0:
		return
	environment.glow_enabled = true
	environment.glow_intensity = _glow_base
	environment.glow_strength = 1.0
	environment.glow_bloom = float(cfg.get("glow_bloom", 0.15))
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.glow_hdr_threshold = float(cfg.get("glow_threshold", 0.9))
	environment.glow_hdr_scale = 2.0


func _build_fog(cfg: Dictionary) -> void:
	if not bool(cfg.get("fog", false)):
		return
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = cfg.get("fog_color", Color(0.8, 0.86, 1.0))
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.1
	environment.fog_depth_begin = float(cfg.get("fog_from", 24.0))
	environment.fog_depth_end = float(cfg.get("fog_to", 90.0))
	environment.fog_depth_curve = 0.9
	environment.fog_density = 1.0
	environment.fog_sky_affect = 0.0


func _apply_fov() -> void:
	if camera == null:
		return
	if _mode == "half":
		var vertical := rad_to_deg(2.0 * atan(_half_h / _half_dist))
		camera.fov = clampf(vertical, MIN_VFOV, MAX_VFOV)
		return
	var half := deg_to_rad(clampf(_hfov, 20.0, 150.0)) * 0.5
	var from_h := rad_to_deg(2.0 * atan(tan(half) / maxf(0.25, _aspect)))
	camera.fov = clampf(maxf(from_h, _min_vfov), MIN_VFOV, MAX_VFOV)
