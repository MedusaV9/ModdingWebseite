extends TestCase
## RW-7 — DevService (Badge, Netzwerk-Log-Redaktion, enable/disable) und
## das Dev-Menü-Overlay (Bereiche, Perf-Overlay-Wiederverwendung).
## Mutierende Menue-Aktionen selbst sind in test_dev_actions.gd abgedeckt —
## hier geht es um Sichtbarkeit/Struktur, ohne den echten Save anzufassen.

const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _restore_dev_settings(prev_enabled: Variant, prev_active: Variant) -> void:
	var app := tree.root.get_node_or_null("/root/AppSettings")
	if app != null:
		app.set_setting("dev.enabled", prev_enabled)
		app.set_setting("dev.was_active", prev_active)
	SaveSchema.unregister_slice(DevActions.SLICE_ID)


func test_dev_service_enable_zeigt_badge_und_persistiert() -> void:
	var app := tree.root.get_node_or_null("/root/AppSettings")
	var dev := tree.root.get_node_or_null("/root/Dev")
	if app == null or dev == null:
		fail_test("AppSettings/Dev-Autoload fehlt")
		return
	var prev_enabled: Variant = app.get_setting("dev.enabled", false)
	var prev_active: Variant = app.get_setting("dev.was_active", false)
	assert_false(bool(dev.is_enabled()), "Dev ist standardmaessig aus")
	dev.enable()
	assert_true(bool(dev.is_enabled()))
	assert_true(bool(app.get_setting("dev.enabled", false)), "persistiert")
	var badge: Variant = dev.get("_badge_layer")
	assert_true(badge != null and (badge as CanvasLayer).visible, "DEV-Badge sichtbar")
	dev.disable()
	assert_false(bool(dev.is_enabled()))
	assert_false((badge as CanvasLayer).visible, "Badge verschwindet beim Deaktivieren")
	_restore_dev_settings(prev_enabled, prev_active)


func test_dev_menu_oeffnet_nur_im_dev_modus() -> void:
	var app := tree.root.get_node_or_null("/root/AppSettings")
	var dev := tree.root.get_node_or_null("/root/Dev")
	if app == null or dev == null:
		fail_test("AppSettings/Dev-Autoload fehlt")
		return
	var prev_enabled: Variant = app.get_setting("dev.enabled", false)
	var prev_active: Variant = app.get_setting("dev.was_active", false)
	dev.open_menu()
	assert_false(bool(dev.is_menu_open()), "ohne Dev-Modus bleibt das Menue zu")
	dev.enable()
	dev.open_menu()
	assert_true(bool(dev.is_menu_open()), "im Dev-Modus oeffnet es")
	dev.close_menu()
	await wait_frames(2)
	assert_false(bool(dev.is_menu_open()))
	dev.disable()
	_restore_dev_settings(prev_enabled, prev_active)


func test_dev_menu_struktur_und_perf_overlay() -> void:
	var app := tree.root.get_node_or_null("/root/AppSettings")
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev_overlay: Variant = app.get_setting("dev.perf_overlay", false)
	I18nService.set_locale("de")
	var menu: Control = DevMenu.new()
	tree.root.add_child(menu)
	for section: String in [
		"DevPerformance",
		"DevZeitWetter",
		"DevGoldLevel",
		"DevQuestPferd",
		"DevStickerSzene",
		"DevSave",
		"DevNetzwerk",
	]:
		assert_true(menu.find_child(section, true, false) != null, "Bereich fehlt: %s" % section)
	assert_true(menu.find_child("DevOff", true, false) != null, "Deaktivieren-Knopf")
	# Perf-Overlay-Wiederverwendung: Toggle schaltet /root/PerfOverlay.
	var overlay := tree.root.get_node_or_null("/root/PerfOverlay")
	var toggle := menu.find_child("PerfToggle", true, false) as CheckButton
	assert_true(toggle != null, "Perf-Toggle existiert")
	if overlay != null and toggle != null:
		toggle.button_pressed = true
		toggle.toggled.emit(true)
		assert_true(bool(overlay.is_shown()), "Toggle zeigt das Overlay")
		toggle.button_pressed = false
		toggle.toggled.emit(false)
		assert_false(bool(overlay.is_shown()))
	menu.get_parent().remove_child(menu)
	menu.free()
	app.set_setting("dev.perf_overlay", prev_overlay)


func test_netzwerk_log_wird_redigiert_und_gedeckelt() -> void:
	var app := tree.root.get_node_or_null("/root/AppSettings")
	var dev := tree.root.get_node_or_null("/root/Dev")
	if app == null or dev == null:
		fail_test("AppSettings/Dev-Autoload fehlt")
		return
	var prev_enabled: Variant = app.get_setting("dev.enabled", false)
	var prev_active: Variant = app.get_setting("dev.was_active", false)
	dev.enable()
	dev.call("_on_net_message", {"t": "CHAT", "d": {"sessionId": "geheim", "score": 3}})
	var log: Array = dev.net_log()
	assert_true(log.size() >= 1)
	if log.size() >= 1:
		var last: Dictionary = log[log.size() - 1]
		assert_eq(str(last["typ"]), "CHAT")
		var payload: Dictionary = last["payload"]
		assert_eq(str(payload["sessionId"]), "[redigiert]", "Secrets schon beim Erfassen raus")
		assert_eq(int(payload["score"]), 3)
	dev.disable()
	_restore_dev_settings(prev_enabled, prev_active)
