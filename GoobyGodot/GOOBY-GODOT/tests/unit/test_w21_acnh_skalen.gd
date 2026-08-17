extends TestCase
## W21 „ACNH-UI" — Skalen-Wächter (UI-DESIGN-ACNH §3): das Redesign steht auf
## GENAU EINER Typo-Skala (5 Stufen), EINEM Spacing-Grid (4er), EINER
## Radien-Skala (3 Stufen + Pill), EINEM Knopf-System (2 Höhen), EINEM
## Balken-Standard und EINEM Icon-Set. Dieser Wächter hält:
## - die Token-Skalen selbst konsistent (Stufen, Monotonie, Grid-Vielfache),
## - JEDE Font-Größe und JEDEN Ecken-Radius des GEBAUTEN Themes auf der
##   Skala (Ausnahmen unten dokumentiert und bewusst eng),
## - die W21-Rollen (StatKapsel-Segmente, KontextDock) im Theme präsent
##   und korrekt gerundet (Kopf oben, Fuss unten, Mitte eckig),
## - die Themen-Stimmungen (MOODS) deckungsgleich mit AcWallpaper.CONTEXTS
##   (eine Farbquelle — Drift zwischen Tokens und Wand fällt sofort auf),
## - die round()-Konvention von AcTokens.px()/font_px().

const BUILDER := preload("res://themes/build_theme.gd")

## W21 P1: KEINE Radius-Ausnahmen mehr — ToastBubble ist auf RADIUS_CARD
## migriert (Paket „HUD-rechts+Toasts“), jede Rundung liegt auf der Skala.
const RADIUS_AUSNAHMEN := {}
## Mood-Schlüssel ↔ Wallpaper-Kontext (DLC-Moods bekommen ihre Wände erst
## im jeweiligen DLC-Paket — die halten wir hier noch nicht deckungsgleich).
const MOOD_ZU_KONTEXT := {"home": "default", "ranch": "ranch", "stadt": "city", "arcade": "arcade"}


func test_typo_skala_fuenf_stufen() -> void:
	assert_eq(AcTokens.TYPO_SKALA.size(), 5, "GENAU fünf Typo-Stufen")
	for i in range(1, AcTokens.TYPO_SKALA.size()):
		assert_true(
			AcTokens.TYPO_SKALA[i] > AcTokens.TYPO_SKALA[i - 1],
			"Typo-Skala steigt streng monoton (Stufe %d)" % i
		)
	# Alt-Namen sind reine Aliasse — Drift zwischen beiden Namensräumen
	# würde die „Font-Lotterie" durch die Hintertür wieder einführen.
	assert_eq(AcTokens.FONT_SIZE_BODY, AcTokens.SIZE_BODY, "Alias BODY")
	assert_eq(AcTokens.FONT_SIZE_BUTTON, AcTokens.SIZE_BUTTON, "Alias BUTTON")
	assert_eq(AcTokens.FONT_SIZE_TITLE, AcTokens.SIZE_TITLE, "Alias TITLE")
	assert_eq(AcTokens.FONT_SIZE_HEADLINE, AcTokens.SIZE_HEADLINE, "Alias HEADLINE")
	assert_eq(AcTokens.FONT_SIZE_CAPTION, AcTokens.SIZE_CAPTION, "Alias CAPTION")


func test_spacing_grid_vielfache() -> void:
	var stufen := [
		AcTokens.SPACE_XS, AcTokens.SPACE_S, AcTokens.SPACE_M, AcTokens.SPACE_L, AcTokens.SPACE_XL
	]
	for i in stufen.size():
		assert_eq(int(stufen[i]) % AcTokens.SPACE_GRID, 0, "SPACE-Stufe %d ist Grid-Vielfaches" % i)
		if i > 0:
			assert_true(int(stufen[i]) > int(stufen[i - 1]), "SPACE-Skala steigt (Stufe %d)" % i)


func test_radien_skala_drei_stufen_plus_pill() -> void:
	assert_eq(AcTokens.RADIUS_SKALA.size(), 3, "GENAU drei Radius-Stufen")
	for i in range(1, AcTokens.RADIUS_SKALA.size()):
		assert_true(
			AcTokens.RADIUS_SKALA[i] > AcTokens.RADIUS_SKALA[i - 1], "Radien steigen (Stufe %d)" % i
		)
	assert_true(
		AcTokens.RADIUS_PILL > AcTokens.RADIUS_SKALA[-1],
		"Pill-Sentinel liegt über der Skala (StyleBox clampt auf Halbhöhe)"
	)


func test_knopf_system_zwei_hoehen() -> void:
	assert_true(
		AcTokens.BTN_H_PRIMAER > AcTokens.BTN_H_KOMPAKT, "Primär ist die GRÖSSERE der zwei Höhen"
	)
	assert_eq(
		AcTokens.BTN_H_KOMPAKT,
		AcTokens.TOUCH_FLOOR,
		"Kompakt = Touch-Floor (kein Knopf rutscht darunter)"
	)


func test_icon_set_steigt() -> void:
	var icons := [AcTokens.ICON_S, AcTokens.ICON_M, AcTokens.ICON_L, AcTokens.ICON_XL]
	for i in range(1, icons.size()):
		assert_true(int(icons[i]) > int(icons[i - 1]), "Icon-Set steigt (Stufe %d)" % i)
	assert_true(AcTokens.BAR_H > 0, "Balken-Standard existiert (> 0)")


func test_theme_fonts_nur_von_der_skala() -> void:
	var theme: Theme = BUILDER.build()
	assert_true(
		theme.default_font_size in AcTokens.TYPO_SKALA, "Default-Font-Größe liegt auf der Skala"
	)
	for typ in theme.get_type_list():
		for name in theme.get_font_size_list(typ):
			var groesse := theme.get_font_size(name, typ)
			assert_true(
				groesse in AcTokens.TYPO_SKALA,
				"Font %s/%s (=%d) liegt auf der Typo-Skala" % [typ, name, groesse]
			)


func test_theme_radien_nur_von_der_skala() -> void:
	var theme: Theme = BUILDER.build()
	for typ in theme.get_type_list():
		for name in theme.get_stylebox_list(typ):
			var sb := theme.get_stylebox(name, typ)
			if not (sb is StyleBoxFlat):
				continue
			var schluessel := "%s/%s" % [typ, name]
			var radien := [
				(sb as StyleBoxFlat).corner_radius_top_left,
				(sb as StyleBoxFlat).corner_radius_top_right,
				(sb as StyleBoxFlat).corner_radius_bottom_right,
				(sb as StyleBoxFlat).corner_radius_bottom_left,
			]
			for radius: int in radien:
				if radius == 0 or radius >= AcTokens.RADIUS_PILL:
					continue  # eckig bzw. Pill-Clamp — beides erlaubt
				if RADIUS_AUSNAHMEN.get(schluessel, -1) == radius:
					continue
				assert_true(
					radius in AcTokens.RADIUS_SKALA,
					"Radius %s (=%d) liegt auf der Radien-Skala" % [schluessel, radius]
				)


func test_w21_rollen_im_theme() -> void:
	var theme: Theme = BUILDER.build()
	var kopf := theme.get_stylebox("panel", "StatKapselKopf") as StyleBoxFlat
	var mitte := theme.get_stylebox("panel", "StatKapselMitte") as StyleBoxFlat
	var fuss := theme.get_stylebox("panel", "StatKapselFuss") as StyleBoxFlat
	var dock := theme.get_stylebox("panel", "KontextDock") as StyleBoxFlat
	assert_true(
		kopf != null and mitte != null and fuss != null and dock != null,
		"StatKapsel-Segmente + KontextDock existieren im gebauten Theme"
	)
	assert_eq(kopf.corner_radius_top_left, AcTokens.RADIUS_CARD, "Kopf: oben gerundet")
	assert_eq(kopf.corner_radius_bottom_left, 0, "Kopf: unten eckig (stößt an Mitte)")
	assert_eq(mitte.corner_radius_top_left, 0, "Mitte: eckig")
	assert_eq(fuss.corner_radius_bottom_right, AcTokens.RADIUS_CARD, "Fuss: unten gerundet")
	assert_eq(fuss.corner_radius_top_right, 0, "Fuss: oben eckig (stößt an Mitte)")
	assert_eq(dock.corner_radius_top_left, AcTokens.RADIUS_CARD, "Dock: oben gerundet")
	assert_eq(dock.corner_radius_bottom_left, 0, "Dock: unten bündig (Kante/Boden)")


func test_moods_spiegeln_wallpaper_kontexte() -> void:
	for mood: String in AcTokens.MOODS:
		var werte: Dictionary = AcTokens.MOODS[mood]
		for pflicht in ["wash", "accent", "accent_dark", "soft"]:
			assert_true(werte.has(pflicht), "Mood %s hat '%s'" % [mood, pflicht])
	for mood: String in MOOD_ZU_KONTEXT:
		var wand: Dictionary = AcWallpaper.CONTEXTS[MOOD_ZU_KONTEXT[mood]]
		var stimmung: Dictionary = AcTokens.MOODS[mood]
		assert_eq(stimmung["wash"], wand["wash"], "Mood %s: wash == Wallpaper-Wash" % mood)
		assert_eq(stimmung["accent"], wand["accent"], "Mood %s: accent == Wallpaper" % mood)
		assert_eq(
			stimmung["accent_dark"], wand["accent_dark"], "Mood %s: accent_dark == Wallpaper" % mood
		)
		assert_eq(stimmung["soft"], wand["soft"], "Mood %s: soft == Wallpaper" % mood)


func test_px_rundungs_konvention() -> void:
	# round() statt int()-Trunkierung: 15×1.6875 = 25.3125 → 25; 22×1.6875
	# = 37.125 → 37; ABER 14×1.75 = 24.5 → 25 (int() hätte 24 geliefert).
	assert_eq(AcTokens.px(14.0, 1.75), 25, "px() rundet kaufmännisch (24.5 → 25)")
	assert_eq(AcTokens.px(15.0, 1.6875), 25, "px() rundet ab (25.3125 → 25)")
	assert_eq(AcTokens.font_px(15.0, 0.1), 10, "font_px() hält den Lesbarkeits-Boden (10)")
	assert_eq(
		AcTokens.font_px(AcTokens.SIZE_BODY, 1.5),
		30,
		"font_px() skaliert die Skala unverändert (20×1.5)"
	)
