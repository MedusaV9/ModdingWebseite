extends TestCase
## W18/J4 „Stadt-Tagesrhythmus" — Wächter: die Rhythmus-Schicht ist PURE
## und liefert an den vier Wächterstunden (8/13/19/23) exakt die erwarteten
## Dichten/Licht-Zustände; die Uhr kommt aus der INJIZIERTEN GameState-Clock
## (AGENTS-Regel), nicht aus der Systemzeit. Dazu der CC0-Haus-Guard:
## Pool-Häuser sind echte Vorstadt-GLBs, XZ-zentriert mit Unterkante y=0
## (Ecke-Ursprung-Falle!), im 90°-Raster gedreht und mit Fenster-Layout.

const CitySceneScript := preload("res://scripts/city/city_scene.gd")
const ClockScript := preload("res://scripts/logic/clock.gd")

const MS_JE_STUNDE := 3_600_000


class FakeGameStateMitClock:
	extends RefCounted
	var clock: RefCounted

	func get_value(_path: String, fallback: Variant = null) -> Variant:
		return fallback


func test_phasen_der_tagesuhr() -> void:
	assert_eq(CityRhythmus.phase(8.0), "morgen", "8 Uhr = morgen")
	assert_eq(CityRhythmus.phase(13.0), "mittag", "13 Uhr = mittag")
	assert_eq(CityRhythmus.phase(19.0), "abend", "19 Uhr = abend")
	assert_eq(CityRhythmus.phase(23.0), "nacht", "23 Uhr = nacht")
	assert_eq(CityRhythmus.phase(3.0), "nacht", "3 Uhr = nacht")
	assert_eq(CityRhythmus.phase(25.0), CityRhythmus.phase(1.0), "24-h-Wrap")


func test_dichte_kurven_an_den_waechterstunden() -> void:
	# Verkehr: morgens ruhig, mittags voll (TAG_AUTOS), abends golden,
	# nachts Nachtschwärmer (NACHT_AUTOS).
	assert_eq(CityRhythmus.verkehr_anzahl(8.0), 5, "8 Uhr: 5 Autos")
	assert_eq(CityRhythmus.verkehr_anzahl(13.0), CityVerkehr.TAG_AUTOS, "13 Uhr: volle Menge")
	assert_eq(CityRhythmus.verkehr_anzahl(19.0), 7, "19 Uhr: goldene Stunde")
	assert_eq(CityRhythmus.verkehr_anzahl(23.0), CityVerkehr.NACHT_AUTOS, "23 Uhr: Nachtschwärmer")
	assert_eq(CityRhythmus.fussgaenger_anzahl(8.0), 6, "8 Uhr: 6 Goobys")
	assert_eq(
		CityRhythmus.fussgaenger_anzahl(13.0), CityFussgaenger.TAG_ANZAHL, "13 Uhr: volle Menge"
	)
	assert_eq(CityRhythmus.fussgaenger_anzahl(19.0), 8, "19 Uhr: Abendbummel")
	assert_eq(
		CityRhythmus.fussgaenger_anzahl(23.0), CityFussgaenger.NACHT_ANZAHL, "23 Uhr: fast leer"
	)
	# Flotten-Maxima decken die Kurvengipfel (CityScene baut genau so viele).
	assert_eq(CityRhythmus.verkehr_max(), CityVerkehr.TAG_AUTOS)
	assert_eq(CityRhythmus.fussgaenger_max(), CityFussgaenger.TAG_ANZAHL)
	# Die CityVerkehr-/CityFussgaenger-Fassaden delegieren an die Kurve.
	for stunde: float in [8.0, 13.0, 19.0, 23.0]:
		assert_eq(CityVerkehr.anzahl(stunde), CityRhythmus.verkehr_anzahl(stunde))
		assert_eq(CityFussgaenger.anzahl(stunde), CityRhythmus.fussgaenger_anzahl(stunde))


func test_licht_und_fenster_zustaende() -> void:
	assert_false(CityAmbiente.lichter_an(8.0), "8 Uhr: Laternen aus")
	assert_false(CityAmbiente.lichter_an(13.0), "13 Uhr: Laternen aus")
	assert_true(CityAmbiente.lichter_an(19.0), "19 Uhr: goldene Stunde, Laternen an")
	assert_true(CityAmbiente.lichter_an(23.0), "23 Uhr: Laternen an")
	assert_almost(CityRhythmus.fenster_anteil(13.0), 0.0, 1e-6, "mittags kein Fensterlicht")
	assert_almost(CityRhythmus.fenster_anteil(19.5), 1.0, 1e-6, "abends leuchten alle")
	assert_almost(
		CityRhythmus.fenster_anteil(23.5),
		CityRhythmus.FENSTER_TIEFNACHT_ANTEIL,
		1e-6,
		"tief in der Nacht schlafen die meisten"
	)
	assert_almost(CityRhythmus.fenster_anteil(2.0), CityRhythmus.FENSTER_TIEFNACHT_ANTEIL, 1e-6)
	assert_true(CityRhythmus.zeitungs_gooby_aktiv(8.0), "morgens liest ein Gooby Zeitung")
	for stunde: float in [13.0, 19.0, 23.0]:
		assert_false(CityRhythmus.zeitungs_gooby_aktiv(stunde), "Zeitung nur morgens")


func test_stunde_von_ms_ist_pure_und_wrappt() -> void:
	# 1970-01-01 08:30:00 UTC.
	assert_almost(CityRhythmus.stunde_von_ms(30_600_000, 0), 8.5, 1e-4, "8:30 UTC")
	assert_almost(CityRhythmus.stunde_von_ms(30_600_000, 90), 10.0, 1e-4, "Bias +90 min")
	# 23:00 UTC + 120 min Bias wrappt auf 1:00 des Folgetags.
	assert_almost(CityRhythmus.stunde_von_ms(23 * MS_JE_STUNDE, 120), 1.0, 1e-4, "Tages-Wrap")


func test_stadt_liest_die_injizierte_clock() -> void:
	var gs := FakeGameStateMitClock.new()
	gs.clock = ClockScript.new()
	gs.clock.pin(30_600_000)
	var city: CityScene = CitySceneScript.new()
	city.game_state_override = gs
	# Nicht im Baum: _stunde() braucht nur den injizierten GameState.
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var erwartet := CityRhythmus.stunde_von_ms(30_600_000, bias)
	assert_almost(city._stunde(), erwartet, 1e-4, "Stunde kommt aus der gepinnten Clock")
	gs.clock.advance(2 * MS_JE_STUNDE)
	var erwartet2 := CityRhythmus.stunde_von_ms(30_600_000 + 2 * MS_JE_STUNDE, bias)
	assert_almost(city._stunde(), erwartet2, 1e-4, "advance() schiebt die Stadt-Uhr mit")
	city.stunde_override = 19.25
	assert_almost(city._stunde(), 19.25, 1e-6, "stunde_override gewinnt (Tests/Screenshots)")
	city.free()


## ------------------------------------------------------- CC0-Haus-Guard


func test_haus_pool_ist_cc0_vorstadt_mit_fenster_layout() -> void:
	assert_true(
		CityKulisse.HAUS_POOL.size() >= 6 and CityKulisse.HAUS_POOL.size() <= 10,
		"6–10 Haustypen im Pool: %d" % CityKulisse.HAUS_POOL.size()
	)
	var sorten := {}
	for eintrag: Dictionary in CityKulisse.HAUS_POOL:
		var glb := str(eintrag["glb"])
		sorten[glb] = true
		assert_true(glb.begins_with(CityKulisse.CC0_VORSTADT), "echtes Vorstadt-Haus: %s" % glb)
		assert_true(ResourceLoader.exists(glb), "GLB existiert: %s" % glb)
		assert_false(
			CityKulisse.fenster_konfig(glb).is_empty(), "Fenster-Layout gepflegt: %s" % glb
		)
	assert_eq(sorten.size(), CityKulisse.HAUS_POOL.size(), "keine Dubletten im Pool")


func test_cc0_haeuser_stehen_am_boden_und_im_raster() -> void:
	# Ecke-Ursprung-Falle: JEDES eingesetzte CC0-Gebäude muss XZ-zentriert
	# authored sein (sonst dreht das 90°-Raster es um die Ecke) und mit der
	# Unterkante auf y=0 stehen (CityBau setzt pos.y=0.05 aufs Distrikt-Pad).
	var glbs := {}
	for eintrag: Dictionary in CityKulisse.HAUS_POOL:
		glbs[str(eintrag["glb"])] = float(eintrag["scale"])
	for eintrag: Dictionary in CityKulisse.GEWERBE_POOL + CityKulisse.ZENTRUM_POOL:
		var glb := str(eintrag["glb"])
		if glb.begins_with("res://"):
			glbs[glb] = float(eintrag["scale"])
	var karte := CityMap.laden()
	var cc0_deko := 0
	for eintrag: Dictionary in karte.deko():
		var glb := str(eintrag.get("glb", ""))
		if not glb.begins_with(CityKulisse.CC0_VORSTADT):
			continue
		cc0_deko += 1
		glbs[glb] = float(eintrag.get("scale", 6.0))
		assert_eq(int(eintrag.get("rot", 0)) % 90, 0, "90°-Raster: %s" % eintrag.get("id"))
		assert_false(
			str(eintrag.get("tint", "")).is_empty(), "Pastell-Tint: %s" % eintrag.get("id")
		)
	assert_true(cc0_deko >= 7, "haus_a…f + spielerhaus sind CC0-Vorstadt (%d)" % cc0_deko)
	for glb: String in glbs:
		var aabb := _glb_aabb(glb)
		assert_true(aabb.size != Vector3.ZERO, "Meshes gefunden: %s" % glb)
		assert_almost(aabb.position.y, 0.0, 0.05, "Unterkante auf y=0: %s" % glb)
		var mitte := aabb.get_center()
		assert_almost(mitte.x, 0.0, 0.05, "X-zentriert: %s" % glb)
		assert_almost(mitte.z, 0.0, 0.05, "Z-zentriert: %s" % glb)
		var breite := maxf(aabb.size.x, aabb.size.z) * float(glbs[glb])
		assert_true(
			breite >= 5.0 and breite <= 13.0,
			"Fußabdruck passt in den Block (%s: %.1f m)" % [glb, breite]
		)


func test_glb_pfad_reicht_cc0_pfade_durch() -> void:
	assert_eq(
		CityBau.glb_pfad("gebaeude/building-a.glb"),
		"res://assets/city/gebaeude/building-a.glb",
		"Kit-Pfade bleiben unter assets/city"
	)
	var cc0 := CityKulisse.CC0_VORSTADT + "/building_type_a.glb"
	assert_eq(CityBau.glb_pfad(cc0), cc0, "res://-Pfade unverändert")


func test_fenster_transforms_folgen_dem_cc0_layout() -> void:
	var haus: Array[Dictionary] = [
		{
			"glb": CityKulisse.CC0_VORSTADT + "/building_type_a.glb",
			"pos": Vector3.ZERO,
			"rot_grad": 0.0,
			"scale": 6.0,
		}
	]
	var transforms := CityKulisse.fenster_transforms(haus, 7)
	assert_true(transforms.size() >= 1, "Fenster am CC0-Haus (%d)" % transforms.size())
	for xform in transforms:
		assert_almost(xform.origin.z, 0.55 * 6.0, 1e-4, "Quad knapp vor der Fassade")
		assert_almost(xform.origin.y, 0.24 * 6.0, 1e-4, "einstöckig: eine Fensterreihe")


## Kombinierte Mesh-AABB eines GLBs (lokal, unskaliert) — wie die
## J4-AABB-Vermessung, aber als dauerhafter Guard.
func _glb_aabb(pfad: String) -> AABB:
	if not ResourceLoader.exists(pfad):
		return AABB()
	var szene: PackedScene = load(pfad)
	if szene == null:
		return AABB()
	var wurzel: Node = szene.instantiate()
	var gesamt := AABB()
	var leer := true
	for mesh in wurzel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var rel := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != wurzel:
			if n is Node3D:
				rel = (n as Node3D).transform * rel
			n = n.get_parent()
		var aabb := rel * mi.mesh.get_aabb()
		if leer:
			gesamt = aabb
			leer = false
		else:
			gesamt = gesamt.merge(aabb)
	wurzel.free()
	return gesamt
