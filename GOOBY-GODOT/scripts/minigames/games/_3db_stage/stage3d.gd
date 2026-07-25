extends Node3D
## 3D-Bühne der Minispiele (Agent 3D-B): WorldEnvironment (Himmel, Tiefen-Nebel,
## dezentes Glow), Sonne + Himmelslicht und die Kamera samt Orientierungs-Regel.
##
## Die Spiele hängen diese Bühne als Kind unter ihre MinigameBase-Wurzel (Node2D).
## Godot rendert die 3D-Welt eines Viewports IMMER hinter den CanvasItems —
## HUD-Labels und _draw()-Overlays liegen also automatisch obenauf, und der
## MinigameBase-Vertrag (Node2D-Wurzel, setup/start/pause/end) bleibt unberührt.
##
## Orientierungs-Regel: die Kamera denkt in WAAGERECHTEM Blickwinkel. `apply_size`
## rechnet ihn je Seitenverhältnis in Godots senkrechtes `fov` um — dadurch ist
## die Strecke hochkant wie quer gleich breit im Bild (das war beim 2D-Vorgänger
## eine handverdrahtete Fallgrube).

## Grenzen des senkrechten Blickwinkels — hochkant würde die Umrechnung sonst
## ins Fischauge laufen.
const MIN_VFOV := 38.0
const MAX_VFOV := 96.0

## LICHT-EICHUNG (der wichtigste Wert dieser Datei).
##
## Die Web-Vorlage rechnet mit three.js-Lichtstärken um 1,0 — three.js teilt die
## Lambert-Reflexion aber durch π, Godot nicht. Wer die Web-Zahlen eins zu eins
## übernimmt, rendert die Szene rund 2,5-fach zu hell: die Kenney-Modelle sind
## fast weiß, und ACES schiebt sie vollends aus dem Bild. Deshalb geben die
## Spiele hier WEB-Stärken an (sun_energy ≈ 1,0, ambient ≈ 1,0) und diese Bühne
## teilt sie durch π — dann liest ein weißes Haus wieder als helles Grau.
const LIGHT_SCALE := 1.0 / PI

var camera: Camera3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var environment: Environment

var _hfov := 74.0
var _fov_bonus := 0.0
var _aspect := 16.0 / 9.0
var _glow_base := 0.0
var _glow_extra := 0.0
var _glow_decay := 0.0


## Bühne aufbauen. `cfg` versteht: sky_top, sky_horizon, ground_horizon,
## ground_bottom, fog (Color), fog_from, fog_to, glow (float), sun_dir
## (Vector3), sun_color, sun_energy, ambient (float), shadows (bool).
func build(cfg: Dictionary) -> void:
	environment = Environment.new()
	_build_sky(cfg)
	_build_fog(cfg)
	_build_glow(cfg)
	# Tonemapping: Filmic zog alles milchig-grau, Linear brannte die hellen
	# Gehwege zu reinem Weiß aus. ACES rollt die Spitzen weich ab und hält die
	# Kenney-Flächenfarben satt — dazu ein Hauch mehr Sättigung/Kontrast.
	environment.tonemap_mode = int(cfg.get("tonemap", Environment.TONE_MAPPER_ACES)) as int
	# BELICHTUNG: gemessen gegen die Web-Vorlage lagen ALLE fünf Spiele mit 0,86
	# rund 40 Luma-Stufen zu hell, und ihr 95 %-Quantil klebte bei 235…246 —
	# also im Anschlag. Genau das ließ die Szenen „flach/2D" wirken: wo eine
	# Fläche ausbrennt, verschwindet ihr Helligkeitsverlauf, und mit ihm die
	# Plastizität. Dunkler belichtet kommen die Verläufe (und damit die Form)
	# zurück, ohne dass an den Lichtstärken gedreht werden muss.
	environment.tonemap_exposure = float(cfg.get("exposure", 0.55))
	environment.tonemap_white = float(cfg.get("white", 1.7))
	environment.adjustment_enabled = true
	environment.adjustment_contrast = float(cfg.get("contrast", 1.05))
	environment.adjustment_saturation = float(cfg.get("saturation", 1.14))
	# Web-Vorbild ist ein HemisphereLight in WARMEM Weiß. Nimmt man stattdessen
	# den blauen Himmel als Umgebungslicht, kippt die ganze Stadt ins Blaue —
	# `ambient_color` hält den Farbton in der Hand des Spiels.
	if cfg.has("ambient_color"):
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.0
		environment.ambient_light_color = cfg["ambient_color"]
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = float(cfg.get("ambient", 1.0)) * LIGHT_SCALE
	# KEINE Himmelsspiegelung. Die Web-Vorlage rendert durchweg mit
	# MeshLambertMaterial — das kennt überhaupt kein Specular. Godot spiegelt
	# per Vorgabe den Himmel, und weil Fresnel bei streifendem Blick gegen 1
	# geht, legte sich quer über JEDEN Horizont ein ausgebrannter heller
	# Balken (im Kinderzimmer des toy_racer war der Dielenboden dort 254 statt
	# 188). Ohne Spiegelquelle bleibt der Boden bis zur Wand durchgezeichnet.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = cfg.get("sun_color", Color(1.0, 0.96, 0.88))
	sun.light_energy = float(cfg.get("sun_energy", 1.0)) * LIGHT_SCALE
	sun.light_specular = 0.2
	var dir: Vector3 = cfg.get("sun_dir", Vector3(-0.45, -0.85, -0.32))
	sun.look_at_from_position(Vector3.ZERO, dir.normalized(), Vector3.UP)
	# KEINE Sonnenscheibe am Himmel: ProceduralSkyMaterial malt sie mit
	# `light_color · light_energy`, und unsere Energien liegen (LIGHT_SCALE)
	# unter der Himmelshelligkeit — die „Sonne" wurde dadurch zum schwarzen
	# Fleck über der Skyline. Die Lichter beleuchten nur noch die Welt.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	if bool(cfg.get("shadows", true)):
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = float(cfg.get("shadow_distance", 46.0))
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 1.4
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = cfg.get("fill_color", Color(0.72, 0.82, 1.0))
	fill.light_energy = float(cfg.get("fill_energy", 0.2)) * LIGHT_SCALE
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.6, -0.35, 0.7), Vector3.UP)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.12
	camera.far = float(cfg.get("far", 260.0))
	camera.current = true
	add_child(camera)
	_hfov = float(cfg.get("hfov", 74.0))
	_apply_fov()


## Vom Spiel aus apply_view() aufrufen: Seitenverhältnis merken, fov nachziehen.
func apply_size(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		_aspect = size.x / size.y
	_apply_fov()


## Waagerechter Basis-Blickwinkel (Grad) — pro Spiel einmal gesetzt.
func set_hfov(deg: float) -> void:
	_hfov = deg
	_apply_fov()


## Tempo-Zuschlag auf den Blickwinkel (FOV-Kick), in Grad, weich gefahren.
func set_fov_bonus(deg: float) -> void:
	if is_equal_approx(_fov_bonus, deg):
		return
	_fov_bonus = deg
	_apply_fov()


## Glow-Puls (Pickups/Kombos). Eigener Puls statt JuiceKit.bloom_pulse: das Kit
## kennt nur das Host-WorldEnvironment, unsere Bühne hat ihr eigenes.
func pulse_glow(strength := 0.6) -> void:
	_glow_extra = maxf(_glow_extra, strength)
	_glow_decay = 2.4


## Jeden Frame aufrufen (das Spiel tickt die Bühne, damit Pause wirklich pausiert).
func tick(delta: float) -> void:
	if _glow_extra <= 0.0:
		return
	_glow_extra = maxf(0.0, _glow_extra - _glow_decay * delta)
	environment.glow_intensity = _glow_base + _glow_extra


## Aktuelle Draw-Calls des Frames (Perf-Budget-Nachweis).
static func draw_calls() -> int:
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)


func _build_sky(cfg: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = cfg.get("sky_top", Color(0.36, 0.6, 0.92))
	sky_mat.sky_horizon_color = cfg.get("sky_horizon", Color(0.78, 0.9, 1.0))
	sky_mat.sky_energy_multiplier = float(cfg.get("sky_energy", 1.0))
	sky_mat.ground_horizon_color = cfg.get("ground_horizon", Color(0.72, 0.82, 0.86))
	sky_mat.ground_bottom_color = cfg.get("ground_bottom", Color(0.42, 0.46, 0.44))
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.18
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
	environment.fog_light_color = cfg.get("fog_color", Color(0.78, 0.9, 1.0))
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.1
	environment.fog_depth_begin = float(cfg.get("fog_from", 30.0))
	environment.fog_depth_end = float(cfg.get("fog_to", 96.0))
	environment.fog_depth_curve = 0.9
	environment.fog_density = 1.0
	environment.fog_sky_affect = 0.0


func _build_glow(cfg: Dictionary) -> void:
	_glow_base = float(cfg.get("glow", 0.32))
	if _glow_base <= 0.0:
		return
	environment.glow_enabled = true
	environment.glow_intensity = _glow_base
	environment.glow_strength = 1.0
	# `glow_bloom` schiebt JEDEN Pixel in den Glow-Puffer (auch dunkle), und
	# SOFTLIGHT hebt damit das ganze Bild an — die Pastellflächen der fünf
	# Spiele wurden dadurch kreidig. Nur echte Lichter sollen leuchten:
	# Schwelle über 1, kein Grundbloom, additiv drauf.
	environment.glow_bloom = float(cfg.get("glow_bloom", 0.0))
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_hdr_threshold = float(cfg.get("glow_threshold", 1.2))
	environment.glow_hdr_scale = 2.0


func _apply_fov() -> void:
	if camera == null:
		return
	var half := deg_to_rad(clampf(_hfov + _fov_bonus, 20.0, 150.0)) * 0.5
	var vertical := rad_to_deg(2.0 * atan(tan(half) / maxf(0.25, _aspect)))
	camera.fov = clampf(vertical, MIN_VFOV, MAX_VFOV)
