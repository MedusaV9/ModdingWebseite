extends TestCase
## FB-2 — Himmel-Stimmungen: sieben vollständige Pastell-Stimmungen,
## deterministisches + STETIGES Blenden über Tageszeit und Wetterlagen
## (keine Sprünge beim Wetterwechsel), Nacht hat Sterne aber keine Sonne.

const PFLICHT_KEYS: Array[String] = [
	"zenit",
	"horizont",
	"boden",
	"dunst",
	"sonne_farbe",
	"sonne_groesse",
	"sonne_glow",
	"wolken_farbe",
	"wolken_menge",
	"sterne",
]


func test_alle_sieben_stimmungen_sind_vollstaendig() -> void:
	assert_eq(HimmelStimmungen.STIMMUNGEN.size(), 7, "sieben Stimmungen")
	for id: String in HimmelStimmungen.STIMMUNGEN:
		var p := HimmelStimmungen.stimmung(id)
		for key: String in PFLICHT_KEYS:
			assert_true(p.has(key), "%s hat %s" % [id, key])


func test_parameter_sind_deterministisch() -> void:
	var wetter := {"typ": "regen", "vorher": "sonne", "blend": 0.4}
	var a := HimmelStimmungen.parameter(17.3, wetter)
	var b := HimmelStimmungen.parameter(17.3, wetter)
	for key: String in PFLICHT_KEYS:
		assert_eq(a[key], b[key], "gleiche Eingabe = gleicher Himmel (%s)" % key)


func test_tagesverlauf_blendet_stetig() -> void:
	# Über den ganzen Tag in 6-Minuten-Schritten: keine Farbsprünge —
	# der Himmel muss WEICH zwischen den Tages-Keyframes mischen. Die
	# schnellste echte Blende (Abendrot → Nacht, 1,4 h) ändert die
	# Kanalsumme um ~0.14 je Schritt; ein harter Keyframe-Sprung läge
	# bei > 0.5. Schwelle dazwischen = Stetigkeits-Nachweis.
	var wetter := {"typ": "sonne", "vorher": "sonne", "blend": 1.0}
	var vorher: Color = HimmelStimmungen.parameter(0.0, wetter)["zenit"]
	var max_sprung := 0.0
	var stunde := 0.1
	while stunde <= 24.0:
		var jetzt: Color = HimmelStimmungen.parameter(stunde, wetter)["zenit"]
		var sprung := absf(jetzt.r - vorher.r) + absf(jetzt.g - vorher.g) + absf(jetzt.b - vorher.b)
		max_sprung = maxf(max_sprung, sprung)
		vorher = jetzt
		stunde += 0.1
	assert_true(max_sprung < 0.25, "kein Farbsprung im Tagesverlauf (max %.3f)" % max_sprung)


func test_wetter_blend_wischt_stetig_zwischen_lagen() -> void:
	# blend=0 = alte Lage, blend=1 = neue Lage, dazwischen echtes Mischen.
	var klar := HimmelStimmungen.parameter(12.0, {"typ": "sonne", "vorher": "sonne", "blend": 1.0})
	var grau := HimmelStimmungen.parameter(12.0, {"typ": "regen", "vorher": "regen", "blend": 1.0})
	var start := HimmelStimmungen.parameter(12.0, {"typ": "regen", "vorher": "sonne", "blend": 0.0})
	var ende := HimmelStimmungen.parameter(12.0, {"typ": "regen", "vorher": "sonne", "blend": 1.0})
	var mitte := HimmelStimmungen.parameter(12.0, {"typ": "regen", "vorher": "sonne", "blend": 0.5})
	assert_almost(float(start["wolken_menge"]), float(klar["wolken_menge"]), 1e-5, "blend=0 = alt")
	assert_almost(float(ende["wolken_menge"]), float(grau["wolken_menge"]), 1e-5, "blend=1 = neu")
	assert_true(
		(
			float(mitte["wolken_menge"]) > float(start["wolken_menge"])
			and float(mitte["wolken_menge"]) < float(ende["wolken_menge"])
		),
		"blend=0.5 liegt dazwischen"
	)


func test_wetter_zieht_den_himmel_zu() -> void:
	var sonne := HimmelStimmungen.parameter(13.0, {"typ": "sonne", "vorher": "sonne", "blend": 1.0})
	var regen := HimmelStimmungen.parameter(13.0, {"typ": "regen", "vorher": "regen", "blend": 1.0})
	var sturm := HimmelStimmungen.parameter(
		13.0, {"typ": "gewitter", "vorher": "gewitter", "blend": 1.0}
	)
	assert_true(
		float(regen["wolken_menge"]) > float(sonne["wolken_menge"]) + 0.3, "Regen = viele Wolken"
	)
	var sturm_zenit: Color = sturm["zenit"]
	var sonne_zenit: Color = sonne["zenit"]
	assert_true(sturm_zenit.get_luminance() < sonne_zenit.get_luminance() - 0.1, "Gewitter dunkel")


func test_nacht_hat_sterne_und_keine_sonne() -> void:
	var nacht := HimmelStimmungen.parameter(23.5, {"typ": "sonne", "vorher": "sonne", "blend": 1.0})
	assert_true(float(nacht["sterne"]) > 0.8, "Sternfeld an")
	assert_true(float(nacht["sonne_glow"]) < 0.05, "keine Sonne")
	var mittag := HimmelStimmungen.parameter(
		12.0, {"typ": "sonne", "vorher": "sonne", "blend": 1.0}
	)
	assert_almost(float(mittag["sterne"]), 0.0, 1e-4, "mittags keine Sterne")


func test_stimmung_bei_liefert_dominante_stimmung() -> void:
	assert_eq(HimmelStimmungen.stimmung_bei(12.5, "sonne"), "mittag")
	assert_eq(HimmelStimmungen.stimmung_bei(23.0, "sonne"), "nacht")
	assert_eq(HimmelStimmungen.stimmung_bei(12.5, "regen"), "bedeckt")
	assert_eq(HimmelStimmungen.stimmung_bei(12.5, "gewitter"), "gewitter")


func test_pastell_niemals_grell() -> void:
	# GOOBY-Stil: kein Kanal einer Grundfarbe brennt über 1.0 aus.
	for id: String in HimmelStimmungen.STIMMUNGEN:
		var p := HimmelStimmungen.stimmung(id)
		for key: String in ["zenit", "horizont", "boden"]:
			var farbe: Color = p[key]
			assert_true(
				farbe.r <= 1.0 and farbe.g <= 1.0 and farbe.b <= 1.0, "%s.%s pastell" % [id, key]
			)
