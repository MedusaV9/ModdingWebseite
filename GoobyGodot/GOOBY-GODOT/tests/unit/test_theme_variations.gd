extends TestCase
## Präventivtest (FIX-A, E7-P3-5): JEDE im Quellcode gesetzte
## `theme_type_variation` muss im AC-Theme existieren. Godot fällt bei
## unbekannten Variationen STILL auf die Basisklasse zurück — so entstanden
## 46 tote PrimaryButton/AccentButton/GhostButton-Referenzen (E7-P0-1).
## Dieser Test scannt scripts/ + scenes/ (.gd und .tscn) und macht die
## Namens-Drift beim nächsten Mal am Entstehungstag laut.

const SCAN_ROOTS: Array[String] = ["res://scripts", "res://scenes"]
## Matcht `theme_type_variation = &"Name"` (gd + tscn) und `= "Name"`.
## Dynamische Zuweisungen (Variablen) kann ein Source-Scan nicht auflösen —
## deren Literale stehen aber an den Call-Sites und werden dort gefunden.
const ASSIGN_PATTERN := 'theme_type_variation\\s*[:=]\\s*&?"([^"]+)"'


func test_jede_gesetzte_variation_existiert_im_theme() -> void:
	var theme := ThemeService.theme()
	var types := theme.get_type_list()
	var regex := RegEx.new()
	assert_eq(regex.compile(ASSIGN_PATTERN), OK, "RegEx kompiliert nicht.")
	var used := {}
	for root in SCAN_ROOTS:
		_scan_dir(root, regex, used)
	assert_true(
		used.size() >= 20,
		"Source-Scan verdächtig leer (%d Variationen) — Pattern/Pfade prüfen." % used.size()
	)
	for variation: String in used:
		assert_true(
			types.has(variation) or ClassDB.class_exists(variation),
			(
				(
					'theme_type_variation "%s" fehlt im Theme (genutzt in %s) — '
					+ "in themes/build_theme.gd ergänzen und ac_theme.tres regenerieren."
				)
				% [variation, used[variation]]
			)
		)


func test_fix_a_varianten_haben_ac_look() -> void:
	# Stichprobe der FIX-A-Neuzugänge: richtige Basen + Kernwerte.
	var theme := ThemeService.theme()
	var primary := theme.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat
	assert_eq(primary.bg_color.to_html(false), "59c9b9", "PrimaryButton = TEAL.")
	var accent := theme.get_stylebox("normal", "AccentButton") as StyleBoxFlat
	assert_eq(accent.bg_color.to_html(false), "ff7ba9", "AccentButton = PINK.")
	var ghost := theme.get_stylebox("normal", "GhostButton") as StyleBoxFlat
	assert_almost(ghost.bg_color.a, 0.0, 1e-4, "GhostButton-Fill transparent.")
	assert_eq(ghost.border_width_left, 2, "GhostButton hat Umriss.")
	var card_btn := theme.get_stylebox("normal", "AcCardButton") as StyleBoxFlat
	assert_eq(card_btn.corner_radius_top_left, AcTokens.RADIUS_CARD, "AcCardButton-Radius 28.")
	assert_eq(card_btn.bg_color.to_html(false), "fffaf2", "AcCardButton = PAPER.")
	assert_true(card_btn.shadow_size > 0, "AcCardButton hat Shadow-Pop.")


func _scan_dir(path: String, regex: RegEx, used: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(child, regex, used)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			_scan_file(child, regex, used)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, regex: RegEx, used: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	for m in regex.search_all(text):
		var variation := m.get_string(1)
		if variation.is_empty():
			continue
		if not used.has(variation):
			used[variation] = path
