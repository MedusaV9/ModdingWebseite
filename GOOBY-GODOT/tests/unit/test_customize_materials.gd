extends TestCase
## HAUS-CUSTOM — Material-Schicht: Palette, prozedurale Graustufen-Muster,
## geteilte Umfärbe-ShaderMaterials (Cache!), CPU-Vorschau (blend/preview)
## und die DE/EN-Parität aller Gestalten-Strings inkl. Palette-Namen.


func test_palette_und_farben() -> void:
	assert_true(CustomizeMaterials.PALETTE.size() >= 24, "reiche Palette (AC-Pastelle)")
	assert_true(CustomizeMaterials.ist_farbe("creme"))
	assert_false(CustomizeMaterials.ist_farbe("neongruen"))
	assert_eq(
		CustomizeMaterials.farbe("gibtsnicht"),
		CustomizeMaterials.PALETTE["creme"],
		"unbekannte Farbe = Creme, nie ein Crash"
	)


func test_jedes_muster_erzeugt_textur() -> void:
	CustomizeMaterials.reset_cache()
	for muster: String in CustomizeMaterials.MUSTER_META:
		var tex := CustomizeMaterials.pattern_texture(muster)
		assert_true(tex != null, "%s: Textur da" % muster)
		assert_eq(tex.get_width(), CustomizeMaterials.TEX_PX, "%s: 128 px breit" % muster)
		assert_eq(CustomizeMaterials.pattern_texture(muster), tex, "%s: Textur gecacht" % muster)


func test_muster_unterscheiden_sich() -> void:
	var punkte := CustomizeMaterials.pattern_texture("punkte").get_image()
	var streifen := CustomizeMaterials.pattern_texture("streifen").get_image()
	var unterschiedlich := false
	for y in range(0, CustomizeMaterials.TEX_PX, 8):
		for x in range(0, CustomizeMaterials.TEX_PX, 8):
			if punkte.get_pixel(x, y) != streifen.get_pixel(x, y):
				unterschiedlich = true
	assert_true(unterschiedlich, "Muster sind visuell verschieden")


func test_surface_material_cache_und_parameter() -> void:
	CustomizeMaterials.reset_cache()
	var mat := CustomizeMaterials.surface("punkte", "rose")
	assert_eq(CustomizeMaterials.surface("punkte", "rose"), mat, "EIN Material pro Kombination")
	assert_ne(CustomizeMaterials.surface("punkte", "mint"), mat, "andere Farbe = anderes Material")
	assert_eq(mat.get_shader_parameter("tint"), CustomizeMaterials.farbe("rose"), "Tint gesetzt")
	assert_true(mat.get_shader_parameter("muster_tex") != null, "Muster-Textur angebunden")
	assert_almost(
		float(mat.get_shader_parameter("meter_pro_kachel")), 0.8, 1e-6, "Kachelmaß aus Meta"
	)
	var flat := CustomizeMaterials.flat("teal")
	assert_eq(CustomizeMaterials.flat("teal"), flat, "flat ebenfalls gecacht")
	assert_eq(flat.albedo_color, CustomizeMaterials.farbe("teal"))


func test_blend_formel_und_preview() -> void:
	var hell := CustomizeMaterials.blend(Color(0.78, 0.78, 0.78), "rose")
	var rose := CustomizeMaterials.farbe("rose")
	assert_almost(hell.r, rose.r, 0.01, "Bezugshelligkeit = pure Palettenfarbe (r)")
	assert_almost(hell.g, rose.g, 0.01, "(g)")
	var dunkel := CustomizeMaterials.blend(Color(0.5, 0.5, 0.5), "rose")
	assert_true(dunkel.r < hell.r, "dunkles Muster = dunklere Fläche")
	var halb := CustomizeMaterials.blend(Color(0.2, 0.9, 0.3), "rose", 0.0)
	assert_almost(halb.g, 0.9, 1e-6, "Stärke 0 = Quellfarbe bleibt (Wildblumen-Trick)")
	var preview := CustomizeMaterials.preview_texture("punkte", "rose", 96)
	assert_eq(preview.get_width(), 96, "Vorschau auf Kachelgröße skaliert")
	assert_eq(CustomizeMaterials.preview_texture("punkte", "rose", 96), preview, "gecacht")


func test_icons_fuer_alle_optionen() -> void:
	CustomizeIcons.reset_cache()
	for art: String in CustomizeCatalog.OPTION_ARTEN:
		for option: Dictionary in CustomizeCatalog.optionen(art):
			var id := str(option.get("id", ""))
			var farben := CustomizeCatalog.farben(art, id)
			var farbe := str(farben[0]) if not farben.is_empty() else "creme"
			var icon := CustomizeIcons.option_preview(art, id, farbe)
			assert_true(icon != null, "%s/%s: Kachelbild da" % [art, id])
			assert_eq(icon.get_width(), CustomizeIcons.PX, "%s/%s: Kachelgröße" % [art, id])


func test_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for farb_id: String in CustomizeMaterials.PALETTE:
		var key := "customize.farbe.%s" % farb_id
		assert_true(de.has(key), "DE-Name fehlt: %s" % key)
		assert_true(en.has(key), "EN-Name fehlt: %s" % key)
	for kategorie: String in [
		"wand",
		"boden",
		"fassade",
		"dach",
		"tuer",
		"fenster",
		"hausnummer",
		"briefkasten",
		"vordach",
		"grund_boden",
		"weg",
		"zaun",
	]:
		var key := "customize.kategorie.%s" % kategorie
		assert_true(de.has(key) and en.has(key), "Kategorie-Label fehlt: %s" % key)
	for key: String in [
		"customize.title",
		"customize.kaufen",
		"customize.zufall",
		"customize.reset",
		"customize.im_besitz",
		"customize.bereich.innen",
		"customize.bereich.haus",
		"customize.bereich.grund",
	]:
		assert_true(de.has(key) and en.has(key), "Basis-Key fehlt: %s" % key)
