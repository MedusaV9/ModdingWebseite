extends TestCase
## W4-P3 POLISH-8 — CityAmbiente (pure Tag/Nacht-Kurve der Stadt):
## Lichtprofil, Laternen-/Autolicht-Schwellen und Ambient-SFX-Planung.

const PROFIL_KEYS := [
	"sonnen_energie",
	"sonnen_farbe",
	"elevation",
	"ambient_energie",
	"himmel_oben",
	"himmel_horizont",
	"boden_horizont",
	"boden_unten",
	"lichter_an",
	"ist_nacht",
]


func test_tageslicht_kurve() -> void:
	assert_almost(CityAmbiente.tageslicht(13.0), 1.0, 1e-6, "Mittag voll")
	assert_almost(CityAmbiente.tageslicht(23.5), 0.0, 1e-6, "Nacht dunkel")
	var abend := CityAmbiente.tageslicht(19.0)
	assert_true(abend > 0.0 and abend < 1.0, "Abendrampe dazwischen")
	assert_almost(CityAmbiente.tageslicht(26.0), CityAmbiente.tageslicht(2.0), 1e-6, "24h-Wrap")


func test_nacht_und_laternen_schwellen() -> void:
	assert_false(CityAmbiente.ist_nacht(12.0), "Mittag ist Tag")
	assert_true(CityAmbiente.ist_nacht(22.0), "22 Uhr ist Nacht")
	assert_false(CityAmbiente.lichter_an(12.0), "Laternen mittags aus")
	assert_true(CityAmbiente.lichter_an(20.0), "Laternen abends an")
	assert_true(CityAmbiente.lichter_an(5.0), "Laternen früh morgens an")


func test_licht_profil_tag_gegen_nacht() -> void:
	var tag := CityAmbiente.licht_profil(12.0)
	var nacht := CityAmbiente.licht_profil(23.0)
	for key: String in PROFIL_KEYS:
		assert_true(tag.has(key), "Profil-Key %s" % key)
	assert_true(float(tag["sonnen_energie"]) > float(nacht["sonnen_energie"]), "Sonne > Mond")
	assert_true(
		float(tag["ambient_energie"]) > float(nacht["ambient_energie"]), "Ambient tags heller"
	)
	var nacht_himmel: Color = nacht["himmel_oben"]
	assert_true(nacht_himmel.r < 0.15 and nacht_himmel.b < 0.3, "Nachthimmel dunkelblau")
	var mond: Color = nacht["sonnen_farbe"]
	assert_true(mond.b > mond.r, "Mondlicht kühl (B > R)")
	assert_false(bool(tag["ist_nacht"]))
	assert_true(bool(nacht["ist_nacht"]))
	assert_true(bool(nacht["lichter_an"]))


func test_daemmerung_faerbt_die_sonne_warm() -> void:
	var morgen: Color = CityAmbiente.licht_profil(8.5)["sonnen_farbe"]
	var mittag: Color = CityAmbiente.licht_profil(12.0)["sonnen_farbe"]
	assert_true(morgen.b < mittag.b, "Morgensonne wärmer (weniger Blau) als Mittag")


func test_sfx_planung() -> void:
	assert_almost(CityAmbiente.sfx_pause_s(0.0), CityAmbiente.SFX_PAUSE_MIN_S)
	assert_almost(CityAmbiente.sfx_pause_s(1.0), CityAmbiente.SFX_PAUSE_MAX_S)
	assert_almost(CityAmbiente.sfx_pause_s(2.0), CityAmbiente.SFX_PAUSE_MAX_S, 1e-6, "clamp")
	assert_eq(CityAmbiente.sfx_wahl(23.0, 0.1), "hupe", "nachts keine Vögel")
	assert_eq(CityAmbiente.sfx_wahl(12.0, 0.1), "vogel", "tags meist Vögel")
	assert_eq(CityAmbiente.sfx_wahl(12.0, 0.9), "hupe", "tags manchmal Hupe")


func test_leuchten_material_ist_emissiv_und_unshaded() -> void:
	var mat := CityAmbiente.leuchten_material(Color(1.0, 0.9, 0.6))
	assert_true(mat.emission_enabled, "emissiv")
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
