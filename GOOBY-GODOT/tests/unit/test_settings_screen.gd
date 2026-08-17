extends TestCase
## RW-7 — Settings-Screen (UI): alle Abschnitte existieren, Regler schreiben
## sofort in AppSettings UND wirken messbar (Engine.max_fps, UiScale),
## Einzelregler markieren das Profil als "benutzerdefiniert", die
## CC-BY-Credits stehen unter "Ueber", und der versteckte Dev-Trigger
## (3 Tipps auf das aktive "Deutsch" + Halte-Bestaetigung) aktiviert
## den Entwicklermodus. Der ECHTE AppSettings-Autoload wird benutzt und am
## Testende wieder auf die Ausgangswerte gestellt.

const SETTINGS_SCENE := preload("res://scripts/ui/settings_screen.tscn")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const SECTIONS := [
	"SectionAllgemein",
	"SectionGrafik",
	"SectionAnzeige",
	"SectionSteuerung",
	"SectionBarrierefreiheit",
	"SectionAudio",
	"SectionBenachrichtigungen",
	"SectionSpiel",
	"SectionSpielstand",
	"SectionUpdates",
	"SectionUeber",
]


func _app() -> Node:
	return tree.root.get_node_or_null("/root/AppSettings")


func _mount_screen() -> Control:
	I18nService.set_locale("de")
	var screen: Control = SETTINGS_SCENE.instantiate()
	tree.root.add_child(screen)
	return screen


func _unmount(screen: Control) -> void:
	screen.get_parent().remove_child(screen)
	screen.free()


func test_alle_abschnitte_existieren() -> void:
	var screen := _mount_screen()
	for section: String in SECTIONS:
		assert_true(
			screen.find_child(section, true, false) != null, "Abschnitt fehlt: %s" % section
		)
	_unmount(screen)


func test_credits_mit_cc_by_namensnennungen() -> void:
	var screen := _mount_screen()
	var title := screen.find_child("CreditsTitle", true, false) as Label
	assert_true(title != null, "Credits-Titel unter Ueber")
	var joined := ""
	for i in 12:
		var line := screen.find_child("CreditLine%d" % i, true, false) as Label
		if line != null:
			joined += line.text + "\n"
	for pflicht in [
		"congusbongus", "Alan McKinney", "DoKashiteru", "kurt", "Gregor Quendel", "tcarisland"
	]:
		assert_true(joined.contains(pflicht), "CC-BY-Namensnennung fehlt: %s" % pflicht)
	_unmount(screen)


func test_preset_wahl_schreibt_und_wirkt() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev_graphics: Dictionary = (app.get_setting("graphics") as Dictionary).duplicate(true)
	var prev_fps := Engine.max_fps
	var screen := _mount_screen()
	var picker := (
		screen.find_child("RowGraphicsPreset", true, false).get_node("Value") as OptionButton
	)
	# Index 1 = "niedrig" (auto/niedrig/mittel/hoch/benutzerdefiniert).
	picker.select(1)
	picker.item_selected.emit(1)
	assert_eq(str(app.value_of("graphics.preset")), "niedrig", "Preset persistiert")
	assert_eq(Engine.max_fps, 30, "QualityService wendet Niedrig sofort an (30 FPS)")
	_unmount(screen)
	app.set_setting("graphics", prev_graphics)
	app.set_setting("graphics.preset", str(prev_graphics.get("preset", "auto")))
	Engine.max_fps = prev_fps


func test_einzelregler_markiert_benutzerdefiniert() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev_graphics: Dictionary = (app.get_setting("graphics") as Dictionary).duplicate(true)
	var prev_fps := Engine.max_fps
	var screen := _mount_screen()
	var slider := (
		screen.find_child("RowGraphicsParticles", true, false).get_node("Value") as HSlider
	)
	slider.value = 0.35
	assert_eq(
		str(app.value_of("graphics.preset")),
		"benutzerdefiniert",
		"Einzelregler stellt das Profil auf benutzerdefiniert"
	)
	assert_almost(float(app.value_of("graphics.particles")), 0.35, 0.001)
	_unmount(screen)
	app.set_setting("graphics", prev_graphics)
	app.set_setting("graphics.preset", str(prev_graphics.get("preset", "auto")))
	Engine.max_fps = prev_fps


func test_ui_scale_regler_wirkt_auf_uiscale() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev := float(app.value_of("display.ui_scale"))
	var screen := _mount_screen()
	var slider := screen.find_child("RowDisplayUiScale", true, false).get_node("Value") as HSlider
	slider.value = 1.15
	assert_almost(float(app.value_of("display.ui_scale")), 1.15, 0.001, "persistiert")
	assert_almost(UiScale.user_factor, 1.15, 0.001, "wirkt sofort auf die zentrale UiScale")
	_unmount(screen)
	app.set_setting("display.ui_scale", prev)


func test_benachrichtigungs_gate_schreibt() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev: bool = app.is_on("notifications.pflege")
	var screen := _mount_screen()
	var toggle := screen.find_child("RowNotifyPflege", true, false).get_node("Value") as CheckButton
	toggle.button_pressed = false
	toggle.toggled.emit(false)
	assert_false(app.is_on("notifications.pflege"))
	assert_false(app.notify_allowed("pflege"), "Gate greift sofort")
	_unmount(screen)
	app.set_setting("notifications.pflege", prev)


func test_autosave_toggle_schreibt() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev: bool = app.is_on("game.autosave")
	var screen := _mount_screen()
	var toggle := screen.find_child("RowGameAutosave", true, false).get_node("Value") as CheckButton
	toggle.button_pressed = false
	toggle.toggled.emit(false)
	assert_false(app.is_on("game.autosave"))
	_unmount(screen)
	app.set_setting("game.autosave", prev)


func test_dev_trigger_drei_tipps_plus_halten() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev_enabled: Variant = app.get_setting("dev.enabled", false)
	var prev_active: Variant = app.get_setting("dev.was_active", false)
	var screen := _mount_screen()
	# Zwei Tipps reichen NICHT:
	screen.call("_on_language_pressed", "de")
	screen.call("_on_language_pressed", "de")
	assert_true(screen.find_child("DevUnlockDialog", true, false) == null, "2 Tipps oeffnen nichts")
	screen.call("_on_language_pressed", "de")
	var dialog := screen.find_child("DevUnlockDialog", true, false)
	assert_true(dialog != null, "3 Tipps oeffnen den Warn-Dialog")
	var dev := tree.root.get_node_or_null("/root/Dev")
	if dialog != null and dev != null:
		assert_false(bool(dev.is_enabled()), "vor der Bestaetigung bleibt Dev aus")
		dialog.set_process(false)
		dialog.call("_on_hold_down")
		dialog.call("_process", 2.1)
		await wait_frames(2)
		assert_true(bool(dev.is_enabled()), "Halte-Bestaetigung aktiviert den Dev-Modus")
		assert_true(bool(app.get_setting("dev.enabled", false)), "persistiert in AppSettings")
		dev.disable()
	_unmount(screen)
	app.set_setting("dev.enabled", prev_enabled)
	app.set_setting("dev.was_active", prev_active)
	SaveSchema.unregister_slice(DevActions.SLICE_ID)


func test_sprachwechsel_ueber_segmente() -> void:
	var app := _app()
	if app == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var prev_lang: Variant = app.get_setting("language", "de")
	var screen := _mount_screen()
	screen.call("_on_language_pressed", "en")
	assert_eq(I18nService.get_locale(), "en", "Segment-Tipp wechselt die Sprache")
	assert_eq(str(app.get_setting("language")), "en", "persistiert")
	screen.call("_on_language_pressed", "de")
	assert_eq(I18nService.get_locale(), "de")
	_unmount(screen)
	I18nService.set_locale("de")
	app.set_setting("language", prev_lang)


func test_einstellungen_haben_durchgaengige_fokusnavigation() -> void:
	var screen := _mount_screen()
	await wait_frames(2)
	var back := screen.get_node("%BackButton") as Button
	assert_eq(back.focus_mode, Control.FOCUS_ALL, "Zurück ist per Tastatur erreichbar")
	assert_eq(tree.root.gui_get_focus_owner(), back, "Screen startet mit stabilem Fokus")
	var controls := FocusNavigation.focusable(screen)
	assert_true(controls.size() >= 20, "alle Settings-Gruppen liefern Fokusziele")
	for control in controls:
		assert_false(control.focus_next.is_empty(), "%s hat kein nächstes Fokusziel" % control.name)
		assert_false(
			control.focus_previous.is_empty(), "%s hat kein vorheriges Fokusziel" % control.name
		)
	for node_name in [
		"LangDE",
		"LangEN",
		"TutorialResetButton",
		"DlcButton",
		"UpdateCheckButton",
		"NewsButton",
	]:
		var control := screen.find_child(node_name, true, false) as Control
		assert_ne(control, null, "%s existiert" % node_name)
		if control != null:
			assert_eq(control.focus_mode, Control.FOCUS_ALL, "%s erlaubt Fokus" % node_name)
	_unmount(screen)
