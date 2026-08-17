class_name QualityService
extends Node
## RW-7 — QualityService (Autoload „Quality“): wendet die AppSettings-Werte
## WIRKLICH auf Godot an (Doc RANCH-DLC-IDEAS-4 §4.3-Mapping) und betreibt
## Auto-Profil + Notbremse. Eine Stelle statt widersprüchlicher Logik pro
## Szene (Doc §1.3 „zentraler QualityManager“).
##
## Mapping (Regler → Godot):
## - graphics.scale_3d   → Viewport.scaling_3d_scale (+ FSR1 unter 100 %,
##                         nur im Forward+-Renderer verfuegbar)
## - graphics.fps        → Engine.max_fps
## - graphics.msaa       → Viewport.msaa_3d
## - graphics.shadows    → Viewport.positional_shadow_atlas_size +
##                         RenderingServer.directional_shadow_atlas_set_size
## - graphics.draw_distance → Viewport.mesh_lod_threshold + Faktor-API
##                         (`draw_distance_factor()`) für Szenen-Deko
## - graphics.particles  → Faktor-API (`particle_factor()`) + Signal
## - graphics.post_fx    → Environment.glow_enabled (falls vorhanden) + API
## - display.ui_scale    → UiScale.user_factor (zentrale UI-Regel, FIX1)
## - display.text_scale  → UiScale.text_factor
## - display.safe_area_extra → UiScale.extra_inset
## - controls.handedness/scheme → Duck-Typing-Glue: Nodes mit
##   `linkshaender`/`zuegel_modus`-Property (RideHud) werden beim Einhängen
##   und bei Änderung versorgt.
## - game.autosave       → GameState-SaveManager.debounce_ms (öffentliche
##   Property; AUS = nur noch Speichern bei App-Ende/manuell)
## - accessibility.color_vision/high_contrast → ColorFilter-Overlay
##
## Auto-Profil: graphics.preset == "auto" → DeviceProfile.classify() wählt
## das Bündel; PerfGovernor senkt bei dauerhaftem Einbruch eine Stufe und
## meldet das höflich (Signal `quality_reduced` + In-App-Banner).

signal quality_changed(bundle: Dictionary)
signal quality_reduced(from_preset: String, to_preset: String)

## Spiegelt save_manager.gd DEFAULT_DEBOUNCE_MS (kein class_name dort).
const AUTOSAVE_ON_DEBOUNCE_MS := 800
const AUTOSAVE_OFF_DEBOUNCE_MS := 1 << 40
const SHADOW_ATLAS := {"aus": 0, "niedrig": 2048, "hoch": 4096}
const DRAW_DISTANCE_MIN := 0.7
const DRAW_DISTANCE_MAX := 1.0
const LOD_THRESHOLD_FAR := 4.0
const LOD_THRESHOLD_NEAR := 1.0

## Test-Injektion: ersetzt /root/AppSettings bzw. das Ziel-Viewport.
var settings_override: Object = null
var viewport_override: Viewport = null
## Notbremse aus in Tests/Screenshots (Standard an).
var brake_enabled := true

var _governor := PerfGovernor.new()
var _applied: Dictionary = {}
var _auto_stufe := ""
var _filter: ColorFilter


func _ready() -> void:
	_filter = ColorFilter.new()
	add_child(_filter)
	var settings := _settings()
	if settings != null and settings.has_signal("setting_changed"):
		settings.setting_changed.connect(_on_setting_changed)
	get_tree().node_added.connect(_on_node_added)
	apply_all()


func _process(delta: float) -> void:
	if not brake_enabled or _auto_stufe.is_empty():
		return
	_governor.feed(delta)
	if _governor.should_step_down():
		_brake_step_down()


## Alles anwenden (Boot, Reload, Preset-Wechsel).
func apply_all() -> void:
	apply_graphics()
	apply_display()
	apply_accessibility()
	apply_controls()
	apply_autosave()


## Aktuell wirksames Grafik-Bündel (nach Auto-Auflösung) — für Tests/Overlay.
func applied_bundle() -> Dictionary:
	return _applied.duplicate()


func draw_distance_factor() -> float:
	return float(_applied.get("draw_distance", 1.0))


func particle_factor() -> float:
	return float(_applied.get("particles", 1.0))


func post_fx_level() -> String:
	return String(_applied.get("post_fx", "dezent"))


## Godot-LOD-Schwelle aus dem Sichtweiten-Regler, unabhängig von Schatten.
## Kurze Sichtweite darf früher auf grobe Meshes wechseln (4 px), maximale
## Sichtweite hält Details bis zur normalen 1-px-Schwelle.
static func lod_threshold_for(draw_distance: float) -> float:
	var normalized := inverse_lerp(
		DRAW_DISTANCE_MIN,
		DRAW_DISTANCE_MAX,
		clampf(draw_distance, DRAW_DISTANCE_MIN, DRAW_DISTANCE_MAX)
	)
	return lerpf(LOD_THRESHOLD_FAR, LOD_THRESHOLD_NEAR, normalized)


func apply_graphics() -> void:
	var settings := _settings()
	if settings == null:
		return
	var preset := String(settings.value_of("graphics.preset"))
	var bundle: Dictionary
	match preset:
		"auto":
			bundle = QualityProfiles.resolve_auto(DeviceProfile.classify(DeviceProfile.snapshot()))
			_auto_stufe = QualityProfiles.stufe_von(bundle)
		"benutzerdefiniert":
			bundle = {
				"scale_3d": settings.value_of("graphics.scale_3d"),
				"fps": int(settings.value_of("graphics.fps")),
				"msaa": settings.value_of("graphics.msaa"),
				"shadows": settings.value_of("graphics.shadows"),
				"draw_distance": settings.value_of("graphics.draw_distance"),
				"particles": settings.value_of("graphics.particles"),
				"post_fx": settings.value_of("graphics.post_fx"),
			}
			_auto_stufe = ""
		_:
			bundle = QualityProfiles.bundle(preset)
			_auto_stufe = ""
	_apply_bundle(bundle)


func apply_display() -> void:
	var settings := _settings()
	if settings == null:
		return
	UiScale.user_factor = float(settings.value_of("display.ui_scale"))
	UiScale.text_factor = float(settings.value_of("display.text_scale"))
	UiScale.extra_inset = float(settings.value_of("display.safe_area_extra"))


func apply_accessibility() -> void:
	var settings := _settings()
	if settings == null or _filter == null:
		return
	_filter.configure(
		String(settings.value_of("accessibility.color_vision")),
		settings.is_on("accessibility.high_contrast")
	)


## Duck-Typing-Glue für Bedienhilfen: alle Nodes im Baum, die die
## RideHud-Properties tragen, bekommen den Settings-Stand.
func apply_controls() -> void:
	var settings := _settings()
	if settings == null:
		return
	var left := String(settings.value_of("controls.handedness")) == "links"
	var zuegel := String(settings.value_of("controls.scheme")) == "zuegel"
	_apply_controls_to(get_tree().root, left, zuegel)


func apply_autosave() -> void:
	var settings := _settings()
	if settings == null:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var manager: Variant = gs.get("_manager")
	if manager == null or not ("debounce_ms" in manager):
		return
	if settings.is_on("game.autosave"):
		manager.debounce_ms = AUTOSAVE_ON_DEBOUNCE_MS
	else:
		manager.debounce_ms = AUTOSAVE_OFF_DEBOUNCE_MS


func _apply_bundle(bundle: Dictionary) -> void:
	_applied = bundle.duplicate()
	var fps := int(bundle.get("fps", 60))
	Engine.max_fps = fps
	_governor.retarget(float(fps))
	var viewport := _viewport()
	if viewport != null:
		var scale := clampf(float(bundle.get("scale_3d", 1.0)), 0.5, 1.0)
		viewport.scaling_3d_scale = scale
		# FSR1 gibt es nur im Forward+-Renderer — unter Mobile/Compatibility
		# (dieses Projekt: "mobile") wuerde die Zuweisung nur einen Fehler
		# loggen und intern auf bilinear zurueckfallen.
		var fsr_ok := RenderingServer.get_current_rendering_method() == "forward_plus"
		viewport.scaling_3d_mode = (
			Viewport.SCALING_3D_MODE_FSR
			if scale < 0.999 and fsr_ok
			else Viewport.SCALING_3D_MODE_BILINEAR
		)
		viewport.msaa_3d = _msaa_enum(String(bundle.get("msaa", "aus")))
		var shadows := String(bundle.get("shadows", "hoch"))
		viewport.positional_shadow_atlas_size = int(SHADOW_ATLAS.get(shadows, 4096))
		viewport.mesh_lod_threshold = lod_threshold_for(float(bundle.get("draw_distance", 1.0)))
		RenderingServer.directional_shadow_atlas_set_size(
			maxi(256, int(SHADOW_ATLAS.get(shadows, 4096))), true
		)
		_apply_post_fx(viewport, String(bundle.get("post_fx", "dezent")))
	quality_changed.emit(_applied.duplicate())


## Glow nur anfassen, wenn die Szene ein Environment mitbringt — Szenen ohne
## eigenes Environment bleiben unangetastet (kein Kampf um fremde Optik).
func _apply_post_fx(viewport: Viewport, level: String) -> void:
	var world := viewport.find_world_3d()
	if world == null or world.environment == null:
		return
	world.environment.glow_enabled = level == "hoch"


func _brake_step_down() -> void:
	var darunter := QualityProfiles.stufe_darunter(_auto_stufe)
	if darunter.is_empty():
		return
	var vorher := _auto_stufe
	_auto_stufe = darunter
	var bundle := QualityProfiles.bundle(darunter)
	_apply_bundle(bundle)
	quality_reduced.emit(vorher, darunter)
	var notify := get_node_or_null("/root/Notify")
	if notify != null and notify.has_method("show_banner"):
		notify.show_banner(
			I18nService.t("settings.qualitaet_gesenkt_titel"),
			I18nService.t("settings.qualitaet_gesenkt_text")
		)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("graphics."):
		apply_graphics()
	elif key.begins_with("display."):
		apply_display()
	elif key.begins_with("accessibility."):
		apply_accessibility()
	elif key.begins_with("controls."):
		apply_controls()
	elif key == "game.autosave":
		apply_autosave()


func _on_node_added(node: Node) -> void:
	# W15/TECHKIT (Doc G §9 R2): jedes startende Minigame bekommt den
	# Glow-Telemetrie-Wächter (5-s-p95 gegen das Budget des aktiven Bündels,
	# Session-Downgrade + user://-Merker — Logik komplett in PerfGlowWatch).
	if node is MinigameBase:
		PerfGlowWatch.attach_to(node)
	if not ("linkshaender" in node or "zuegel_modus" in node):
		return
	var settings := _settings()
	if settings == null:
		return
	var left := String(settings.value_of("controls.handedness")) == "links"
	var zuegel := String(settings.value_of("controls.scheme")) == "zuegel"
	_set_control_props(node, left, zuegel)


func _apply_controls_to(node: Node, left: bool, zuegel: bool) -> void:
	_set_control_props(node, left, zuegel)
	for child in node.get_children():
		_apply_controls_to(child, left, zuegel)


func _set_control_props(node: Node, left: bool, zuegel: bool) -> void:
	if "linkshaender" in node:
		node.set("linkshaender", left)
	if "zuegel_modus" in node:
		node.set("zuegel_modus", zuegel)


func _settings() -> Object:
	if settings_override != null:
		return settings_override
	return get_node_or_null("/root/AppSettings")


func _viewport() -> Viewport:
	if viewport_override != null:
		return viewport_override
	if not is_inside_tree():
		return null
	return get_tree().root


func _msaa_enum(msaa: String) -> int:
	match msaa:
		"2x":
			return Viewport.MSAA_2X
		"4x":
			return Viewport.MSAA_4X
		_:
			return Viewport.MSAA_DISABLED
