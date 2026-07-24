extends TestCase
## OrientationService-Tests (W1a) — Klassifikation + Lock-Auflösung sind pure
## static funcs und laufen komplett headless.

const SERVICE_SCRIPT := preload("res://scripts/core/orientation_service.gd")


func test_classification_for_six_resolutions() -> void:
	var landscape: int = SERVICE_SCRIPT.Orientation.LANDSCAPE
	var portrait: int = SERVICE_SCRIPT.Orientation.PORTRAIT
	# Design-Basis 1280×720 quer/hoch
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(1280, 720)), landscape, "1280x720")
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(720, 1280)), portrait, "720x1280")
	# iPhone 15 Pro Max quer/hoch
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(2796, 1290)), landscape, "2796x1290")
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(1290, 2796)), portrait, "1290x2796")
	# iPad Pro 11" quer/hoch
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(2388, 1668)), landscape, "2388x1668")
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(1668, 2388)), portrait, "1668x2388")
	# Kante: Quadrat gilt als LANDSCAPE (Querformat bevorzugt — dokumentiert)
	assert_eq(SERVICE_SCRIPT.classify(Vector2i(1000, 1000)), landscape, "Quadrat")


func test_lock_mode_resolution_to_screen_orientation() -> void:
	var auto_mode: int = SERVICE_SCRIPT.LockMode.AUTO
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(SERVICE_SCRIPT.LockMode.LANDSCAPE, "auto"),
		DisplayServer.SCREEN_SENSOR_LANDSCAPE,
		"Lock LANDSCAPE"
	)
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(SERVICE_SCRIPT.LockMode.PORTRAIT, "auto"),
		DisplayServer.SCREEN_SENSOR_PORTRAIT,
		"Lock PORTRAIT"
	)
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(auto_mode, "landscape"),
		DisplayServer.SCREEN_SENSOR_LANDSCAPE,
		"AUTO + globale Präferenz landscape"
	)
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(auto_mode, "portrait"),
		DisplayServer.SCREEN_SENSOR_PORTRAIT,
		"AUTO + globale Präferenz portrait"
	)
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(auto_mode, "auto"),
		DisplayServer.SCREEN_SENSOR,
		"AUTO + auto = voller Sensor"
	)
	# Lock schlägt globale Präferenz
	assert_eq(
		SERVICE_SCRIPT.resolve_screen_orientation(SERVICE_SCRIPT.LockMode.PORTRAIT, "landscape"),
		DisplayServer.SCREEN_SENSOR_PORTRAIT,
		"Lock hat Vorrang vor globaler Präferenz"
	)


func test_lock_unlock_emits_signals_headless_safe() -> void:
	var service: Node = SERVICE_SCRIPT.new()
	tree.root.add_child(service)
	var locks: Array = []
	service.lock_changed.connect(func(mode: int) -> void: locks.append(mode))
	service.lock(SERVICE_SCRIPT.LockMode.PORTRAIT)
	assert_eq(service.current_lock, SERVICE_SCRIPT.LockMode.PORTRAIT)
	service.unlock()
	assert_eq(service.current_lock, SERVICE_SCRIPT.LockMode.AUTO)
	assert_eq(locks, [SERVICE_SCRIPT.LockMode.PORTRAIT, SERVICE_SCRIPT.LockMode.AUTO] as Array)
	assert_true(service.get_orientation() in [0, 1], "Orientierung muss klassifiziert sein.")
	service.queue_free()
	await wait_frames(1)
