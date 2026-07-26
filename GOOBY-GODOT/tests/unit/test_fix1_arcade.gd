extends TestCase
## FIX1 P0 „Arcade-Bilder ohne Smoothing / Bereich sieht buggy aus“:
## Cover-Filter (Linear + Mipmaps, inkl. Import-Preset-Wache) und das
## responsive Grid (Spaltenzahl aus der Breite, Kacheln füllen die Zeile).

const COVERS_DIR := "res://assets/covers"


func test_grid_columns_pure_aus_der_breite() -> void:
	# iPhone 11 quer (Canvas ~1558, minus Ränder ≈ 1526): 5er-Deckel.
	assert_eq(ArcadeScreen.grid_columns(1526.0, 1.0), 5, "breiter Quer-Canvas → 5 Spalten")
	# Desktop-Basisbreite 1280 minus Ränder ≈ 1248 → 5 Kacheln à 230+16.
	assert_eq(ArcadeScreen.grid_columns(1248.0, 1.0), 5, "1280er-Basis → 5 Spalten")
	assert_eq(ArcadeScreen.grid_columns(900.0, 1.0), 3, "mittel → 3 Spalten")
	# Hochkant (f≈1,78, Kachel ≈409 px): 2 Spalten auf dem 1280er-Canvas.
	assert_eq(ArcadeScreen.grid_columns(1248.0, 1280.0 / 720.0), 2, "hoch skaliert → 2")
	# Nie unter MIN_COLUMNS, nie über MAX_COLUMNS, 0-Breite crasht nicht.
	assert_eq(ArcadeScreen.grid_columns(100.0, 1.0), ArcadeScreen.MIN_COLUMNS, "schmal → Minimum")
	assert_eq(ArcadeScreen.grid_columns(0.0, 1.0), ArcadeScreen.MIN_COLUMNS, "0-Breite → Minimum")
	assert_eq(ArcadeScreen.grid_columns(99_999.0, 1.0), ArcadeScreen.MAX_COLUMNS, "riesig → Deckel")


func test_cover_importe_generieren_mipmaps() -> void:
	# Wache gegen Regression: OHNE `mipmaps/generate=true` flimmern die
	# heruntergerechneten Cover (der gemeldete „kein Smoothing“-Bug).
	var dir := DirAccess.open(COVERS_DIR)
	assert_true(dir != null, "Cover-Ordner existiert")
	if dir == null:
		return
	var geprueft := 0
	for file in dir.get_files():
		if not file.ends_with(".png.import"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [COVERS_DIR, file])
		assert_true(text.contains("mipmaps/generate=true"), "%s muss Mipmaps generieren" % file)
		geprueft += 1
	assert_true(geprueft > 0, "mindestens ein Cover-Import geprüft (war %d)" % geprueft)


func test_arcade_screen_kacheln_filtern_und_fuellen() -> void:
	var screen: ArcadeScreen = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	var grid: GridContainer = screen.find_children("*", "GridContainer", true, false)[0]
	assert_true(grid.get_child_count() > 0, "Grid hat Kacheln")
	assert_true(
		grid.columns >= ArcadeScreen.MIN_COLUMNS and grid.columns <= ArcadeScreen.MAX_COLUMNS,
		"Spaltenzahl responsiv geklemmt (war %d)" % grid.columns
	)
	var covers := 0
	for tile: Control in grid.get_children():
		assert_true(
			tile.size_flags_horizontal & Control.SIZE_EXPAND_FILL != 0,
			"Kachel %s füllt die Zeile" % tile.name
		)
		for rect: TextureRect in tile.find_children("*", "TextureRect", true, false):
			assert_eq(
				rect.texture_filter,
				CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"Cover in %s filtert mit Mipmaps" % tile.name
			)
			covers += 1
	assert_true(covers > 0, "mindestens ein Cover geprüft (war %d)" % covers)
	screen.queue_free()
	await wait_frames(1)
