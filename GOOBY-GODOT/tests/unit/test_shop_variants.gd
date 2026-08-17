extends TestCase
## CONTENT-B — Farb-/Stoff-Varianten: Palette, Auswahl-Regeln und der
## Material-Tint auf einem echten Möbel-GLB (keine neuen Modelle!).

const TINT_ID := "rose"


func test_palette_ist_pastellig_und_vollstaendig() -> void:
	assert_true(FurnitureVariants.PALETTE.has(FurnitureVariants.DEFAULT_ID), "Neutral existiert")
	assert_eq(FurnitureVariants.tint(FurnitureVariants.DEFAULT_ID), Color(1, 1, 1), "neutral")
	assert_true(FurnitureVariants.PALETTE.size() >= 6, "genug Farben zur Auswahl")
	for variant_id: String in FurnitureVariants.PALETTE:
		var color: Color = FurnitureVariants.PALETTE[variant_id]
		assert_true(color.get_luminance() > 0.6, "%s: pastellig hell" % variant_id)
		assert_true(
			I18nService.has_key(FurnitureVariants.label_key(variant_id)),
			"String-Key fehlt: %s" % FurnitureVariants.label_key(variant_id)
		)


func test_ids_for_mit_und_ohne_katalog_liste() -> void:
	var mit := FurnitureVariants.ids_for({"variants": ["rose", "mint", "gibtsnicht", "rose"]})
	assert_eq(mit, ["natur", "rose", "mint"], "unbekannte + doppelte fliegen raus")
	var ohne := FurnitureVariants.ids_for({})
	assert_eq(ohne[0], FurnitureVariants.DEFAULT_ID, "Neutral zuerst")
	assert_true(ohne.size() >= 4, "Basis-Möbel bekommen die Fallback-Palette")


func test_normalize_faellt_weich_zurueck() -> void:
	var item := {"variants": ["rose", "mint"]}
	assert_eq(FurnitureVariants.normalize(item, "mint"), "mint", "erlaubte Variante bleibt")
	assert_eq(FurnitureVariants.normalize(item, "schiefer"), "natur", "fremde → neutral")
	assert_eq(FurnitureVariants.normalize(item, ""), "natur", "leer → neutral")


func test_unbekannter_tint_stuerzt_nicht_ab() -> void:
	assert_eq(FurnitureVariants.tint("gibtsnicht"), Color(1, 1, 1))
	assert_false(FurnitureVariants.is_known("gibtsnicht"))


func test_tint_landet_auf_dem_modell_und_laesst_sich_zuruecknehmen() -> void:
	var item := ShopCatalog.def("loungeSofa")
	assert_false(item.is_empty(), "Test-Möbel im Katalog")
	var node := FurnitureNode.create(item, Vector2i.ZERO, 0, "variant-test")
	assert_true(node != null, "Modell baut sich")
	if node == null:
		return
	var meshes := _meshes(node)
	assert_true(meshes.size() >= 1, "Modell hat Meshes")
	var originale := _materials(node)

	FurnitureVariants.apply(node, TINT_ID)
	var getoent := 0
	for material in _materials(node):
		assert_true(material is ShaderMaterial, "Variante ist ein Umfärbe-Material")
		if not (material is ShaderMaterial):
			continue
		getoent += 1
		var shader_material: ShaderMaterial = material
		assert_eq(shader_material.shader, FurnitureVariants.SHADER, "unser Shader")
		var farbe: Variant = shader_material.get_shader_parameter("tint")
		assert_true((farbe as Color).is_equal_approx(FurnitureVariants.tint(TINT_ID)), "Farbe")
	assert_true(getoent >= 1, "mindestens eine Surface umgefärbt")

	FurnitureVariants.apply(node, FurnitureVariants.DEFAULT_ID)
	assert_eq(_materials(node), originale, "Neutral stellt die Originalmaterialien her")
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			assert_true(
				mesh.get_surface_override_material(surface) == null,
				"Neutral räumt die Overrides wieder ab"
			)
	node.free()


## Die Umfärbe-Rechnung selbst (der Shader macht pro Pixel dasselbe): satte
## Originalfarben bekommen den Farbton der Variante, die Helligkeit bleibt.
func test_umfaerben_behaelt_helligkeit_und_nimmt_den_farbton() -> void:
	var blau := Color(0.30, 0.45, 0.80)
	var rose := FurnitureVariants.blend(blau, TINT_ID)
	assert_true(rose.r > rose.b, "aus blau wird rosé (%s)" % rose)
	assert_almost(rose.get_luminance(), blau.get_luminance(), 0.3, "Helligkeit bleibt grob")
	var dunkel := FurnitureVariants.blend(Color(0.08, 0.08, 0.09), TINT_ID)
	assert_true(dunkel.get_luminance() < rose.get_luminance(), "dunkle Teile bleiben dunkel")
	assert_eq(FurnitureVariants.blend(blau, FurnitureVariants.DEFAULT_ID), blau, "natur = Original")


## Regression: bei den KayKit-.gltf-Möbeln hängt das Material an der
## MeshInstance (material_override), nicht an der Mesh-Surface — und es ist
## texturiert. Wer nur `albedo_color` multipliziert, ändert sichtbar NICHTS.
func test_variante_greift_auch_bei_override_materialien() -> void:
	var item := ShopCatalog.def("armchairCosy")
	assert_false(item.is_empty(), "KayKit-Sessel im Katalog")
	var node := FurnitureNode.create(item, Vector2i.ZERO, 0, "variant-override")
	if node == null:
		return
	var originale := _materials(node)
	for material in originale:
		assert_false(material is ShaderMaterial, "Ausgangszustand ohne Umfärbe-Material")
	FurnitureVariants.apply(node, TINT_ID)
	var getoent := 0
	for material in _materials(node):
		if material is ShaderMaterial:
			getoent += 1
			var quelle: Variant = (material as ShaderMaterial).get_shader_parameter("albedo_tex")
			assert_true(quelle is Texture2D, "Atlas-Textur reist mit")
	assert_true(getoent >= 1, "auch das Override-Material wird umgefärbt")
	FurnitureVariants.apply(node, FurnitureVariants.DEFAULT_ID)
	assert_eq(_materials(node), originale, "natur stellt das Original her")
	node.free()


func test_wiederholtes_toenen_baut_sich_nicht_auf() -> void:
	var item := ShopCatalog.def("loungeSofa")
	var node := FurnitureNode.create(item, Vector2i.ZERO, 0, "variant-twice")
	if node == null:
		return
	FurnitureVariants.apply(node, TINT_ID)
	var erste := _first_shader_params(node)
	FurnitureVariants.apply(node, "mint")
	FurnitureVariants.apply(node, TINT_ID)
	assert_eq(_first_shader_params(node), erste, "Basisfarbe bleibt das Original, nicht der Tint")
	node.free()


## Basisfarbe + Ziel-Tint des ersten Umfärbe-Materials.
func _first_shader_params(root: Node) -> Array:
	for material in _materials(root):
		if material is ShaderMaterial:
			var shader_material: ShaderMaterial = material
			return [
				shader_material.get_shader_parameter("base_color"),
				shader_material.get_shader_parameter("tint"),
			]
	return []


## Die Materialien, die WIRKLICH gerendert werden (material_override schlägt
## Surface-Override schlägt Mesh-Material) — unabhängig davon, wo der Import
## sie abgelegt hat.
func _materials(root: Node) -> Array:
	var out: Array = []
	for mesh in _meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.material_override
			if material == null:
				material = mesh.get_surface_override_material(surface)
			if material == null:
				material = mesh.mesh.surface_get_material(surface)
			out.append(material)
	return out


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
