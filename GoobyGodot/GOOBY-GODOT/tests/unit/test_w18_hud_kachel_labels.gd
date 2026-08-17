extends TestCase
## W18/E6-Wache — HUD-Kachel-Labels passen IMMER, in BEIDEN Leitformaten
## (quer 2868×1320, hoch 1320×2868) und in BEIDEN Skalen-Welten:
## - „geraet“: simulierte iPhone-Retina-Skala + Notch (screen_scale_override
##   3.0 + insets, Rechnung wie fb3_ui_audit/test_g7_hud_dynamik), und
## - „desktop“: KEIN Override — exakt die Playtest-/xvfb-Welt (f=1 in quer),
##   in der die W18-Regression sichtbar war („Albu“/„IGohb“/„Garde“-
##   Fragmente: Kachel nur ~50 px breit, 22 px Textfläche, und selbst
##   MIN_PX-Schrift passte nicht mehr).
## Für JEDE Kachel gilt: der sichtbare Text ist ein VOLLSTÄNDIGES Wort
## (voller Titel oder `hud.<id>_kurz`-Kurzform, nie ein Fragment), die
## Textbreite bei der gesetzten Schriftgröße passt in die ECHTE Textfläche
## (btn.size minus StyleBox-Innenränder — Render-Wahrheit, nicht nur die
## eigene Mess-Hilfe) und es ist KEIN Trimmen nötig (OVERRUN_NO_TRIMMING).
## Dazu pure Kaskaden-Tests für `HudLabelFit.einpassen`/`mindest_breite`.

const HUD_SCENE := preload("res://scripts/ui/hud.tscn")
## [Fenster-px, Insets in PUNKTEN l/t/r/b für den Geräte-Modus]
const FORMATE: Array = [
	[Vector2i(2868, 1320), [59.0, 0.0, 59.0, 21.0]],
	[Vector2i(1320, 2868), [0.0, 59.0, 0.0, 34.0]],
]
const GERAETE_SCALE := 3.0


func _pin(fenster: Vector2i) -> void:
	tree.root.size = fenster
	tree.root.size_changed.emit()
	await wait_frames(2)


func _kurzform(id: StringName) -> String:
	var key := "hud.%s_kurz" % String(id)
	return I18nService.t(key) if I18nService.has_key(key) else ""


## Kachel-Wache für den aktuellen Fenster-/Skalen-Zustand.
## W21/ACNH P1: das Ruhe-Cockpit quer ist ICON-ONLY — der volle Name lebt
## im Tooltip; Labels erscheinen erst im offenen Mehr-Cluster, und DANN
## gelten alle Fit-Regeln (vollständiges Wort, keine Fragmente/Trimmen).
func _pruefe_kacheln(hud: Hud, kontext: String) -> void:
	if hud.current_layout == HudLayoutLogic.Layout.LANDSCAPE:
		for id: StringName in hud._buttons:
			var btn: Button = hud._buttons[id]
			assert_eq(btn.text, "", "%s: Ruhe-Cockpit ist icon-only @ %s" % [id, kontext])
			assert_eq(
				btn.tooltip_text,
				I18nService.t("hud." + String(id)),
				"%s: Tooltip trägt den vollen Namen @ %s" % [id, kontext]
			)
		hud._on_mehr_pressed()
		await wait_frames(2)
		_pruefe_labels(hud, kontext + " mehr-offen")
		hud._on_mehr_pressed()
		await wait_frames(1)
		return
	_pruefe_labels(hud, kontext)


## Label-Fit-Regeln für den Zustand, in dem Labels sichtbar sind
## (Hochkant-Dock bzw. offenes Mehr-Cluster im Cockpit).
func _pruefe_labels(hud: Hud, kontext: String) -> void:
	for id: StringName in hud._buttons:
		var btn: Button = hud._buttons[id]
		var voll := I18nService.t("hud." + String(id))
		var kurz := _kurzform(id)
		assert_true(
			btn.text == voll or (not kurz.is_empty() and btn.text == kurz),
			(
				"%s: „%s“ ist weder voller Titel „%s“ noch Kurzform „%s“ @ %s"
				% [id, btn.text, voll, kurz, kontext]
			)
		)
		var px := btn.get_theme_font_size("font_size")
		assert_true(
			px >= HudLabelFit.MIN_PX,
			"%s: Schriftgröße %d unter MIN_PX %d @ %s" % [id, px, HudLabelFit.MIN_PX, kontext]
		)
		# Render-Wahrheit: echte Knopfbreite minus StyleBox-Innenränder —
		# NICHT nur die eigene Mess-Hilfe (die war in W18 die Lücke: sie maß
		# custom_minimum_size, der Knopf war real anders breit).
		var style := btn.get_theme_stylebox("normal")
		var raender := 0.0
		if style != null:
			raender = style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
		var echt_avail := btn.size.x - raender
		var breite := HudLabelFit.text_breite(btn.get_theme_font("font"), btn.text, px)
		assert_true(
			breite <= echt_avail + 0.5,
			(
				"%s: „%s“ (%d px) misst %.1f > echte Textfläche %.1f @ %s"
				% [id, btn.text, px, breite, echt_avail, kontext]
			)
		)
		assert_eq(
			btn.text_overrun_behavior,
			TextServer.OVERRUN_NO_TRIMMING,
			"%s: braucht Trimmen (Fit-Shrink unter Schwelle) @ %s" % [id, kontext]
		)


func test_kachel_labels_passen_in_beiden_leitformaten_und_skalen() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	for format: Array in FORMATE:
		var fenster: Vector2i = format[0]
		var insets_pt: Array = format[1]
		for geraet in [true, false]:
			if geraet:
				UiScale.screen_scale_override = GERAETE_SCALE
			else:
				# Desktop-/Playtest-Welt: keine Overrides, keine Notch.
				UiScale.screen_scale_override = 0.0
				UiScale.insets_override = Rect2()
			await _pin(fenster)
			if geraet:
				var canvas := Vector2(tree.root.get_visible_rect().size)
				var px_pro_pt := (
					minf(canvas.x, canvas.y) / (minf(fenster.x, fenster.y) / GERAETE_SCALE)
				)
				var l := float(insets_pt[0]) * px_pro_pt
				var t := float(insets_pt[1]) * px_pro_pt
				var r := float(insets_pt[2]) * px_pro_pt
				var b := float(insets_pt[3]) * px_pro_pt
				UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)
				tree.root.size_changed.emit()
				await wait_frames(2)
			var hud: Hud = HUD_SCENE.instantiate()
			tree.root.add_child(hud)
			await wait_frames(3)
			await _pruefe_kacheln(hud, "%s %s" % [fenster, "geraet" if geraet else "desktop"])
			hud.free()
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


## EN-Gegenprobe im engsten Fall (quer, Desktop-Skala): auch die englischen
## Titel („Furniture“/„Wardrobe“/„Decorate“) enden nie als Fragment.
func test_kachel_labels_passen_auf_englisch_im_engsten_fall() -> void:
	var fenster_vorher: Vector2i = tree.root.size
	var locale_vorher := I18nService.get_locale()
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	await _pin(Vector2i(2868, 1320))
	I18nService.set_locale("en")
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(3)
	await _pruefe_kacheln(hud, "(2868, 1320) desktop en")
	hud.free()
	I18nService.set_locale(locale_vorher)
	tree.root.size = fenster_vorher
	tree.root.size_changed.emit()
	await wait_frames(1)


# ── Pure Kaskaden-Logik (headless, ohne Nodes) ───────────────────────────────


func _mess_font() -> Font:
	return ThemeService.theme().get_font("font", "Button")


func test_einpassen_behaelt_vollen_titel_wenn_er_passt() -> void:
	var font := _mess_font()
	var fit := HudLabelFit.einpassen(font, "Reise", "Weg", 12, 200.0)
	assert_eq(String(fit["text"]), "Reise", "Voller Titel bleibt, wenn er passt")
	assert_eq(int(fit["px"]), 12, "Wunschgröße bleibt bei viel Platz")
	assert_true(bool(fit["passt"]), "passt=true bei viel Platz")


func test_einpassen_schrumpft_vor_der_kurzform() -> void:
	var font := _mess_font()
	# Breite so wählen, dass der volle Titel NUR geschrumpft passt.
	var eng := HudLabelFit.text_breite(font, "Garderobe", HudLabelFit.MIN_PX) + 1.0
	var fit := HudLabelFit.einpassen(font, "Garderobe", "Outfit", 12, eng)
	assert_eq(String(fit["text"]), "Garderobe", "Autoshrink hat Vorrang vor der Kurzform")
	assert_true(bool(fit["passt"]), "geschrumpfter voller Titel passt")


func test_einpassen_nimmt_kurzform_wenn_minimum_nicht_reicht() -> void:
	var font := _mess_font()
	var voll_min := HudLabelFit.text_breite(font, "Garderobe", HudLabelFit.MIN_PX)
	var kurz_min := HudLabelFit.text_breite(font, "Outfit", HudLabelFit.MIN_PX)
	assert_true(kurz_min < voll_min, "Messbasis: Kurzform ist schmaler")
	var eng := (voll_min + kurz_min) / 2.0
	var fit := HudLabelFit.einpassen(font, "Garderobe", "Outfit", 12, eng)
	assert_eq(String(fit["text"]), "Outfit", "Kurzform ersetzt den zu breiten Titel")
	assert_true(bool(fit["passt"]), "Kurzform passt")


func test_einpassen_ellipsis_bleibt_letzter_ausweg() -> void:
	var font := _mess_font()
	var fit := HudLabelFit.einpassen(font, "Garderobe", "Outfit", 12, 1.0)
	assert_false(bool(fit["passt"]), "1 px Platz: nichts passt → passt=false")
	assert_eq(String(fit["text"]), "Outfit", "schmalerer Kandidat clippt am wenigsten")
	var ohne_kurz := HudLabelFit.einpassen(font, "Garderobe", "", 12, 1.0)
	assert_false(bool(ohne_kurz["passt"]), "ohne Kurzform bleibt passt=false")
	assert_eq(String(ohne_kurz["text"]), "Garderobe", "ohne Kurzform bleibt der Titel")


func test_mindest_breite_nimmt_schmalsten_kandidaten() -> void:
	var font := _mess_font()
	var voll := HudLabelFit.text_breite(font, "Garderobe", HudLabelFit.MIN_PX)
	var kurz := HudLabelFit.text_breite(font, "Outfit", HudLabelFit.MIN_PX)
	assert_almost(
		HudLabelFit.mindest_breite(font, "Garderobe", "Outfit"),
		minf(voll, kurz),
		0.01,
		"Kurzform zählt für die Mindestbreite"
	)
	assert_almost(
		HudLabelFit.mindest_breite(font, "Garderobe", ""),
		voll,
		0.01,
		"ohne Kurzform zählt der volle Titel"
	)
