extends TestCase
## VIS-1 — Trailer-Review-Fixes: Korn/Lavendel sind texturierte Billboard-
## Büschel mit Wind-Shader (statt „gelber Pfeile"), Wasserflächen tragen
## den Wellen-Shader mit radialem UV + Ufer-Schilf (statt flacher blauer
## Scheiben), der Regen hat zwei Fall-Ebenen + Aufschlag-Ringe + Nass-
## Glanz, und der Reiter hebt den Pferdekörper auf den höchsten
## Huf-Kontakt (kein Boden-/Planken-Clipping mehr).


func test_korn_und_lavendel_sind_texturierte_bueschel() -> void:
	WeltFlora.reset_for_tests()
	for id: String in ["korn", "lavendel"]:
		var mesh := WeltFlora.mesh(id)
		assert_true(mesh != null, "%s baut" % id)
		var mat := mesh.surface_get_material(0) as ShaderMaterial
		assert_true(mat != null, "%s nutzt ShaderMaterial" % id)
		if mat == null:
			continue
		assert_true(
			mat.shader != null and mat.shader.resource_path == WeltFlora.WIND_SHADER,
			"%s nutzt den Wind-Shader" % id
		)
		assert_true(mat.get_shader_parameter("albedo_tex") != null, "%s hat eine Ähren-Textur" % id)
		var arrays: Array = (mesh as ArrayMesh).surface_get_arrays(0)
		assert_true(arrays[Mesh.ARRAY_TEX_UV] != null, "%s hat UVs fürs Alpha-Bild" % id)
	assert_true(
		WeltFlora.wind_materialien().size() >= 2, "Wind-Registry kennt die Billboard-Sorten"
	)
	var korn_hoch := WeltFlora.mesh("korn").get_aabb().size.y
	assert_true(
		korn_hoch > 0.85 and korn_hoch < 1.4, "Korn mannshoch-halb (~1m, ist %.2f)" % korn_hoch
	)


func test_wasser_scheibe_hat_radiales_uv_und_presets() -> void:
	WeltWasser.reset_for_tests()
	var mesh := WeltWasser.scheibe_mesh() as ArrayMesh
	assert_true(mesh != null, "Wasserscheibe baut")
	var groesse := mesh.get_aabb().size
	assert_almost(groesse.x, 2.0, 0.05, "Einheits-Scheibe (Radius 1)")
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var uv_min := 1.0
	var uv_max := 0.0
	for uv in uvs:
		uv_min = minf(uv_min, uv.x)
		uv_max = maxf(uv_max, uv.x)
	assert_almost(uv_min, 0.0, 0.001, "UV.x beginnt in der Mitte bei 0")
	assert_almost(uv_max, 1.0, 0.001, "UV.x endet am Ufer bei 1")
	var klar := WeltWasser.material("klar")
	assert_true(
		klar.shader != null and klar.shader.resource_path == WeltWasser.SHADER,
		"klar nutzt wasser.gdshader"
	)
	var moor := WeltWasser.material("moor")
	var klar_tief: Color = klar.get_shader_parameter("farbe_tief")
	var moor_tief: Color = moor.get_shader_parameter("farbe_tief")
	assert_true(moor_tief.get_luminance() < klar_tief.get_luminance(), "Moor ist trüber/dunkler")
	assert_eq(WeltWasser.materialien().size(), 2, "Registry kennt beide Materialien")
	var bach := WeltWasser.material("bach")
	assert_true(float(bach.get_shader_parameter("band_modus")) > 0.5, "Bach läuft im Band-Modus")


func test_terrain_wasser_nutzt_wellen_shader_und_ufer_schilf() -> void:
	WeltWasser.reset_for_tests()
	var wurzel := Node3D.new()
	RanchTerrain.new().baue_wasser(wurzel)
	for wasser_name: String in ["SeeWasser", "BuchtWasser", "BergseeWasser"]:
		var mi := wurzel.find_child(wasser_name, true, false) as MeshInstance3D
		assert_true(mi != null, "%s existiert" % wasser_name)
		if mi == null:
			continue
		assert_true(
			mi.material_override is ShaderMaterial, "%s trägt den Wasser-Shader" % wasser_name
		)
	var schilf := wurzel.find_child("SeeUferSchilf", true, false) as MultiMeshInstance3D
	assert_true(schilf != null, "See hat Ufer-Schilf")
	if schilf != null:
		assert_true(schilf.multimesh.instance_count > 8, "Schilfsaum ist gefüllt")
	var tuempel := wurzel.find_child("MoorTuempel", true, false) as MultiMeshInstance3D
	assert_true(
		tuempel != null and tuempel.material_override is ShaderMaterial,
		"Moor-Tümpel nutzen den Moor-Shader"
	)
	wurzel.free()


func test_regen_hat_zwei_ebenen_spritzer_und_nass_glanz() -> void:
	WeltWasser.reset_for_tests()
	var wasser_mat := WeltWasser.material("klar")
	var controller := RanchWetterController.new()
	tree.root.add_child(controller)
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	var sonne := DirectionalLight3D.new()
	controller.add_child(sonne)
	var terrain_mat := StandardMaterial3D.new()
	terrain_mat.roughness = 0.95
	controller.einrichten(env, sonne, terrain_mat)
	var regen := controller.find_child("Regen", false, false) as GPUParticles3D
	var fern := controller.find_child("RegenFern", false, false) as GPUParticles3D
	var spritzer := controller.find_child("RegenSpritzer", false, false) as GPUParticles3D
	assert_true(regen != null and fern != null, "Regen hat zwei Fall-Ebenen")
	assert_true(spritzer != null, "Aufschlag-Ringe existieren")
	controller.wetter_override = "regen"
	controller.tick(0.016, 12.0, Vector3.ZERO)
	assert_true(regen.emitting and fern.emitting and spritzer.emitting, "alle Ebenen regnen")
	assert_true(
		regen.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,
		"Streaks kippen mit der Fallrichtung"
	)
	var quad_mat := (regen.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_true(quad_mat.albedo_texture != null, "Streaks haben eine weiche Verlaufs-Textur")
	assert_true(terrain_mat.roughness < 0.7, "nasser Boden glänzt (Roughness sinkt)")
	assert_true(
		terrain_mat.albedo_color.get_luminance() < Color.WHITE.get_luminance(),
		"nasser Boden dunkelt ab"
	)
	assert_true(float(wasser_mat.get_shader_parameter("regen")) > 0.3, "Wasser kräuselt im Regen")
	controller.wetter_override = "sonne"
	controller.tick(0.016, 12.0, Vector3.ZERO)
	assert_false(regen.emitting or spritzer.emitting, "Sonne stoppt den Regen")
	assert_almost(terrain_mat.roughness, 0.95, 0.01, "trocken = matte Wiese")
	controller.queue_free()
	await wait_frames(1)


func test_streu_kleinteile_liegen_in_lokalen_zellen() -> void:
	var plaene := RanchStreu.plaene(1.0)
	var gras: Dictionary = {}
	for plan: Dictionary in plaene:
		if str(plan["glb"]).ends_with("grass_large.glb"):
			gras = plan
	assert_true(not gras.is_empty(), "Gras-Plan existiert")
	var transforms: Array = gras["transforms"]
	var zellen := RanchStreu.zellen(transforms)
	assert_true(zellen.size() >= 6, "Gras verteilt sich über mehrere Zellen (%d)" % zellen.size())
	var summe := 0
	for zelle: Array in zellen:
		summe += zelle.size()
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for t: Transform3D in zelle:
			min_p = min_p.min(Vector2(t.origin.x, t.origin.z))
			max_p = max_p.max(Vector2(t.origin.x, t.origin.z))
		var spanne := max_p - min_p
		assert_true(
			spanne.x <= RanchStreu.ZELLE_M + 0.001 and spanne.y <= RanchStreu.ZELLE_M + 0.001,
			(
				"Zell-Spanne %.0f/%.0f <= %.0f (lokales Culling greift)"
				% [spanne.x, spanne.y, RanchStreu.ZELLE_M]
			)
		)
	assert_eq(summe, transforms.size(), "keine Instanz geht beim Zellen-Split verloren")
	assert_true(
		RanchStreu.draw_call_schaetzung(plaene) <= RanchStreu.DRAW_CALL_BUDGET,
		"Zellen-Heuristik bleibt im Budget"
	)


func test_reiter_steht_auf_hoechstem_huf_kontakt() -> void:
	var reiter := RanchWeltReiter.new()
	tree.root.add_child(reiter)
	await wait_frames(1)
	var punkte: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(240.0, -440.0), Vector2(120.0, 80.0), Vector2(-200.0, 300.0)
	]
	for p in punkte:
		reiter.springe_zu(Vector3(p.x, 0.0, p.y), 0.7)
		var vor := -reiter.transform.basis.z
		var quer := reiter.transform.basis.x
		for eck: Vector2 in [
			Vector2(1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0)
		]:
			var huf := (
				reiter.position
				+ vor * eck.x * RanchWeltReiter.HUF_VOR_M
				+ quer * eck.y * RanchWeltReiter.HUF_SEITE_M
			)
			var boden := RanchGelaende.reit_hoehe(huf.x, huf.z)
			assert_true(
				(
					reiter.position.y + 0.001
					>= boden - absf(reiter.pferd.rotation.x) * RanchWeltReiter.HUF_VOR_M
				),
				(
					"Huf bei %s taucht nicht ein (Körper %.2f, Boden %.2f)"
					% [p, reiter.position.y, boden]
				)
			)
	reiter.queue_free()
	await wait_frames(1)
