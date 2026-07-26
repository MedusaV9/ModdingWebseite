extends TestCase
## RW-7 — Geraeteerkennung (DeviceProfile), Qualitaetsprofile
## (QualityProfiles), Notbremse (PerfGovernor) und der QualityService,
## der die AppSettings-Werte MESSBAR auf Godot anwendet (Engine.max_fps,
## Viewport.scaling_3d_scale/msaa_3d/Schatten-Atlas, UiScale-Faktoren,
## Autosave-Debounce).

const AppSettingsScript := preload("res://scripts/core/app_settings.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

var _seq := 0


func _fresh_path(file: String) -> String:
	_seq += 1
	var dir := "user://rw7_tests/quality_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return "%s/%s" % [dir, file]


## ------------------------------------------------------ DeviceProfile (pur)


func test_device_classify_klassen() -> void:
	var hoch := DeviceProfile.classify(
		{"memory_mb": 6000.0, "screen_px": Vector2(2556, 1179), "refresh_hz": 120.0}
	)
	assert_eq(hoch["klasse"], "hoch")
	assert_true(hoch["supports_120"])
	assert_eq(hoch["fps"], 120, "ProMotion-Geraet zielt auf 120")
	var mittel := DeviceProfile.classify(
		{"memory_mb": 4000.0, "screen_px": Vector2(1792, 828), "refresh_hz": 60.0}
	)
	assert_eq(mittel["klasse"], "mittel")
	assert_false(mittel["supports_120"])
	assert_eq(mittel["fps"], 60)
	var niedrig := DeviceProfile.classify(
		{"memory_mb": 2000.0, "screen_px": Vector2(1334, 750), "refresh_hz": 60.0}
	)
	assert_eq(niedrig["klasse"], "niedrig")
	assert_eq(niedrig["fps"], 30)


func test_device_classify_ohne_messwerte() -> void:
	var unbekannt := DeviceProfile.classify({})
	assert_eq(unbekannt["klasse"], "mittel", "ohne Fakten konservativ Mittel")
	var hoch_ohne_promotion := DeviceProfile.classify(
		{"memory_mb": 8000.0, "screen_px": Vector2(2532, 1170), "refresh_hz": 60.0}
	)
	assert_eq(hoch_ohne_promotion["fps"], 60, "hoch ohne 120-Hz-Display = 60")


func test_device_snapshot_ist_headless_sicher() -> void:
	var facts := DeviceProfile.snapshot()
	assert_true(facts.has("memory_mb"))
	assert_true(facts.has("refresh_hz"))
	var result := DeviceProfile.classify(facts)
	assert_true(["niedrig", "mittel", "hoch"].has(str(result["klasse"])))


## --------------------------------------------------- QualityProfiles (pur)


func test_profile_buendel_und_auto() -> void:
	assert_eq(QualityProfiles.bundle("niedrig")["fps"], 30)
	assert_eq(QualityProfiles.bundle("hoch")["scale_3d"], 1.0)
	assert_eq(QualityProfiles.bundle("unbekannt")["fps"], 60, "Fallback = Mittel")
	var auto_hoch := QualityProfiles.resolve_auto({"klasse": "hoch", "supports_120": true})
	assert_eq(auto_hoch["fps"], 120, "Auto + ProMotion = 120")
	var auto_niedrig := QualityProfiles.resolve_auto({"klasse": "niedrig", "supports_120": false})
	assert_eq(auto_niedrig["fps"], 30)
	assert_eq(QualityProfiles.stufe_darunter("hoch"), "mittel")
	assert_eq(QualityProfiles.stufe_darunter("mittel"), "niedrig")
	assert_eq(QualityProfiles.stufe_darunter("niedrig"), "", "unter Niedrig geht nichts")


## ------------------------------------------------------- PerfGovernor (pur)


func test_notbremse_feuert_nach_dauerhaftem_einbruch() -> void:
	var gov := PerfGovernor.new(60.0)
	# 20 FPS (unter 75 % von 60) fuer 5 Sekunden am Stueck:
	for _i in 101:
		gov.feed(0.05)
	assert_true(gov.should_step_down(), "5 s schlecht = eine Stufe runter")
	assert_false(gov.should_step_down(), "feuert nur einmal")
	assert_true(gov.is_cooling_down(), "danach Hysterese-Cooldown")


func test_notbremse_ignoriert_hitches_und_gute_frames() -> void:
	var gov := PerfGovernor.new(60.0)
	for _i in 50:
		gov.feed(0.05)
	gov.feed(0.8)
	assert_false(gov.should_step_down(), "Ladehaenger (>0,5 s) zaehlt nicht")
	# 2 s gute Frames setzen den Slow-Zaehler zurueck:
	for _i in 130:
		gov.feed(1.0 / 60.0)
	for _i in 60:
		gov.feed(0.05)
	assert_false(gov.should_step_down(), "nach Reset reichen 3 s schlecht nicht")


func test_notbremse_cooldown_blockt_weitere_stufen() -> void:
	var gov := PerfGovernor.new(60.0)
	for _i in 101:
		gov.feed(0.05)
	assert_true(gov.should_step_down())
	for _i in 101:
		gov.feed(0.05)
	assert_false(gov.should_step_down(), "im 60-s-Cooldown keine weitere Stufe")


## --------------------------------------- QualityService (wirkt auf Godot!)


func _service_mit(settings: Node) -> Array:
	var viewport := SubViewport.new()
	tree.root.add_child(viewport)
	var svc := QualityService.new()
	svc.settings_override = settings
	svc.viewport_override = viewport
	svc.brake_enabled = false
	tree.root.add_child(svc)
	return [svc, viewport]


func test_preset_wirkt_auf_engine_und_viewport() -> void:
	var prev_fps := Engine.max_fps
	var settings: Node = AppSettingsScript.new(_fresh_path("settings.json"))
	settings.set_setting("graphics.preset", "niedrig")
	var pair := _service_mit(settings)
	var svc: QualityService = pair[0]
	var viewport: SubViewport = pair[1]
	assert_eq(Engine.max_fps, 30, "Niedrig setzt Engine.max_fps=30")
	assert_almost(viewport.scaling_3d_scale, 0.67, 0.001, "Niedrig rendert 3D bei 67 %")
	# FSR1 gibt es nur im Forward+-Renderer — sonst (Mobile/Compatibility/
	# Headless-Dummy) faellt der Service bewusst auf Bilinear zurueck.
	var want_mode := (
		Viewport.SCALING_3D_MODE_FSR
		if RenderingServer.get_current_rendering_method() == "forward_plus"
		else Viewport.SCALING_3D_MODE_BILINEAR
	)
	assert_eq(viewport.scaling_3d_mode, want_mode, "unter 100 % = FSR1 (nur Forward+)")
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.positional_shadow_atlas_size, 0, "Schatten aus")
	settings.set_setting("graphics.preset", "hoch")
	assert_eq(Engine.max_fps, 60, "Hoch = 60")
	assert_almost(viewport.scaling_3d_scale, 1.0, 0.001)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "100 % = Bilinear")
	assert_eq(viewport.msaa_3d, Viewport.MSAA_2X)
	assert_eq(viewport.positional_shadow_atlas_size, 4096)
	svc.free()
	viewport.free()
	settings.free()
	Engine.max_fps = prev_fps


func test_benutzerdefinierte_einzelwerte_wirken() -> void:
	var prev_fps := Engine.max_fps
	var settings: Node = AppSettingsScript.new(_fresh_path("settings.json"))
	settings.set_setting("graphics.preset", "benutzerdefiniert")
	settings.set_setting("graphics.fps", 120)
	settings.set_setting("graphics.scale_3d", 0.8)
	settings.set_setting("graphics.msaa", "4x")
	var pair := _service_mit(settings)
	var svc: QualityService = pair[0]
	var viewport: SubViewport = pair[1]
	assert_eq(Engine.max_fps, 120)
	assert_almost(viewport.scaling_3d_scale, 0.8, 0.001)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	assert_almost(svc.draw_distance_factor(), 1.0, 0.001, "Faktor-API fuer Szenen-Deko")
	svc.free()
	viewport.free()
	settings.free()
	Engine.max_fps = prev_fps


func test_display_werte_setzen_uiscale_faktoren() -> void:
	var prev_fps := Engine.max_fps
	var settings: Node = AppSettingsScript.new(_fresh_path("settings.json"))
	var pair := _service_mit(settings)
	var svc: QualityService = pair[0]
	settings.set_setting("display.ui_scale", 1.3)
	settings.set_setting("display.text_scale", 1.5)
	settings.set_setting("display.safe_area_extra", 12)
	assert_almost(UiScale.user_factor, 1.3, 0.001, "display.ui_scale -> UiScale.user_factor")
	assert_almost(UiScale.text_factor, 1.5, 0.001)
	assert_almost(UiScale.extra_inset, 12.0, 0.001)
	settings.set_setting("display.ui_scale", 1.0)
	settings.set_setting("display.text_scale", 1.0)
	settings.set_setting("display.safe_area_extra", 0)
	assert_almost(UiScale.user_factor, 1.0, 0.001)
	svc.free()
	(pair[1] as Node).free()
	settings.free()
	Engine.max_fps = prev_fps


func test_autosave_schalter_steuert_debounce() -> void:
	var prev_fps := Engine.max_fps
	var gs := tree.root.get_node_or_null("/root/GameState")
	if gs == null:
		return
	var manager: Variant = gs.get("_manager")
	if manager == null or not ("debounce_ms" in manager):
		return
	var prev_debounce: int = manager.debounce_ms
	var settings: Node = AppSettingsScript.new(_fresh_path("settings.json"))
	var pair := _service_mit(settings)
	var svc: QualityService = pair[0]
	settings.set_setting("game.autosave", false)
	assert_true(
		int(manager.debounce_ms) >= QualityService.AUTOSAVE_OFF_DEBOUNCE_MS,
		"AUS schiebt den Debounce praktisch ins Unendliche"
	)
	settings.set_setting("game.autosave", true)
	assert_eq(int(manager.debounce_ms), QualityService.AUTOSAVE_ON_DEBOUNCE_MS)
	manager.debounce_ms = prev_debounce
	svc.free()
	(pair[1] as Node).free()
	settings.free()
	Engine.max_fps = prev_fps


func test_notbremse_senkt_auto_stufe_und_meldet() -> void:
	var prev_fps := Engine.max_fps
	var settings: Node = AppSettingsScript.new(_fresh_path("settings.json"))
	var pair := _service_mit(settings)
	var svc: QualityService = pair[0]
	svc.brake_enabled = true
	var reduziert: Array = []
	svc.quality_reduced.connect(
		func(von: String, nach: String) -> void: reduziert.append([von, nach])
	)
	# Auto-Profil laeuft (Default) — dauerhaft schlechte Frames einspeisen:
	var applied_vorher: Dictionary = svc.applied_bundle()
	for _i in 140:
		svc._process(0.05)
	assert_eq(reduziert.size(), 1, "genau eine Herabstufung gemeldet")
	if reduziert.size() == 1:
		assert_eq(
			QualityProfiles.stufe_darunter(str(reduziert[0][0])),
			str(reduziert[0][1]),
			"genau eine Stufe tiefer"
		)
	assert_ne(svc.applied_bundle(), applied_vorher, "Buendel wurde gewechselt")
	svc.free()
	(pair[1] as Node).free()
	settings.free()
	Engine.max_fps = prev_fps
