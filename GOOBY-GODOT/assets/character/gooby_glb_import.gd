@tool
extends EditorScenePostImport
## Gooby-GLB-Nachimport (VIS-2, Trailer-Review „Stilbruch: 3D-Modell glatt
## und texturlos gegen das flauschige 2D-Artwork“): ruestet das GoobyToon-
## Material zum warmen Fell-Look nach, OHNE Geometrie, Bones, Clips oder
## Shape-Keys anzufassen — der W1b-Rig-Vertrag bleibt exakt gleich, es
## werden ausschliesslich Material-Eigenschaften veraendert:
##   • weichere Schattierung: Lambert-Wrap statt Burley, matt (Roughness 1)
##   • next_pass-Fellhuelle (gooby_flaum.gdshader): feines Fell-Korn auf
##     dem Albedo, noise-erodierter Flaum an der Silhouette und ein warm-
##     rosiger Lichtsaum als Subsurface-Andeutung (Ohren!).
## Der Shader-Weg statt BaseMaterial-Rim/Backlight ist Absicht: er sieht im
## Forward-Mobile-Renderer (Spiel) und im gl_compatibility-Renderer
## (Trailer-Captures) identisch aus. Die Fell-Noise-Textur wird hier einmal
## deterministisch gebacken (fester Seed) und landet in der .scn —
## GoobyRigs care-pale-Override dupliziert das Material flach und behaelt
## damit den next_pass (kranker Gooby bleibt flauschig, nur blasser).

const FLAUM_SHADER_PFAD := "res://assets/character/gooby_flaum.gdshader"
## Fester Seed + feste Groesse: der Import bleibt deterministisch.
const NOISE_SEED := 20260727
const NOISE_PIXEL := 128
## Warm-Creme-Tönung aufs Albedo (multiplikativ): rueckt das kalte Weiss
## Richtung Artwork/App-Icon (Creme-Fell), laesst Augen/Rosa unberuehrt.
const WARM_TINT := Color(1.0, 0.93, 0.84)


func _post_import(scene: Node) -> Object:
	var mesh_inst := _finde_mesh(scene)
	if mesh_inst == null or mesh_inst.mesh == null:
		push_warning("gooby_glb_import: kein Mesh gefunden — GLB bleibt unveraendert.")
		return scene
	var basis := mesh_inst.mesh.surface_get_material(0) as StandardMaterial3D
	if basis == null:
		push_warning("gooby_glb_import: Surface 0 ist kein StandardMaterial3D.")
		return scene
	_mach_weich(basis)
	basis.next_pass = _baue_flaum_pass(basis)
	return scene


## Plueschtier statt Plastik: matt, ohne Glanzpunkt. Bewusst KEIN
## Lambert-Wrap: der bandet im gl_compatibility-Renderer sichtbar
## (Ring-Streifen auf dem Bauch) — die weiche Lichtkante kommt statt-
## dessen aus dem Flaum-Pass.
static func _mach_weich(material: StandardMaterial3D) -> void:
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.albedo_color = material.albedo_color * WARM_TINT


static func _baue_flaum_pass(basis: StandardMaterial3D) -> ShaderMaterial:
	var pass_material := ShaderMaterial.new()
	pass_material.shader = load(FLAUM_SHADER_PFAD)
	pass_material.set_shader_parameter("palette", basis.albedo_texture)
	pass_material.set_shader_parameter("fell_noise", _backe_fell_noise())
	pass_material.set_shader_parameter(
		"farbton", Vector3(basis.albedo_color.r, basis.albedo_color.g, basis.albedo_color.b)
	)
	pass_material.render_priority = 1
	return pass_material


## Nahtlose Fell-Noise-Textur, synchron + deterministisch gebacken
## (NoiseTexture2D generiert asynchron — beim Import unbrauchbar).
static func _backe_fell_noise() -> ImageTexture:
	var rauschen := FastNoiseLite.new()
	rauschen.seed = NOISE_SEED
	rauschen.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rauschen.frequency = 0.06
	rauschen.fractal_octaves = 4
	var bild := rauschen.get_seamless_image(NOISE_PIXEL, NOISE_PIXEL)
	return ImageTexture.create_from_image(bild)


static func _finde_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for kind in node.get_children():
		var treffer := _finde_mesh(kind)
		if treffer != null:
			return treffer
	return null
