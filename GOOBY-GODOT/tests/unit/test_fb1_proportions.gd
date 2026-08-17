extends TestCase
## FB1: Proportions- und Palettenwächter für den wiederhergestellten
## Web-Gooby (User: "Gooby braucht sein altes Model aus der alten
## vor-Godot-Version wieder"). Die Korridore stammen aus der Web-Referenz
## (GOOBY/src/character/gooby.js, Rezept ×RIG_SCALE≈0.657) — siehe
## /tmp/gooby-godot/artifacts/FB1/parameter_tabelle.md des FB1-Laufs.
##
## Zusätzlich wird die Palette-Textur byte-genau geprüft: build_mesh.py muss
## sRGB-Werte DIREKT in die PNG schreiben. Mit Linear-Werten dekodiert der
## Renderer doppelt und alle Pinktöne übersättigen (Nase (206,66,90) statt
## (232,139,160)) — genau der Bug, der den "neuen" Gooby fremd aussehen ließ.

const GLB_PATH := "res://assets/character/gooby.glb"
## Palette-UV-Zellen (gooby_params.PALETTE_ORDER, 4×4-Raster); glTF flippt V
## gegenüber Blender (v_gltf = 1 − v_blender).
const UV_CELL_EYE := Vector2(0.375, 0.375)
const UV_CELL_BODY := Vector2(0.125, 0.125)
## Erwartete sRGB-Bytes an den Zellmitten (x, y in Pixeln, 256²-Textur).
const PALETTE_CELLS := {
	"body": [Vector2i(32, 32), Color8(246, 234, 215)],
	"earInner": [Vector2i(160, 32), Color8(246, 168, 184)],
	"nose": [Vector2i(224, 32), Color8(232, 139, 160)],
	"cheek": [Vector2i(32, 96), Color8(249, 198, 207)],
}
## Toleranz pro Kanal (0–255): deckt Import-/Kompressionsrauschen ab, schlägt
## aber beim Linear-Bug (Abweichungen 30–70) sicher fehl.
const PALETTE_TOLERANZ := 6.0


func test_proportionen_treffen_web_referenz() -> void:
	var mass := _measure()
	assert_true(
		mass["hoehe"] >= 1.00 and mass["hoehe"] <= 1.10,
		"Gesamthöhe %.3f außerhalb 1.00–1.10 (Web: 1.05)" % mass["hoehe"]
	)
	var koerper_halb: float = mass["koerper_breite"] / 2.0
	assert_true(
		koerper_halb >= 0.27 and koerper_halb <= 0.33,
		"Körper-Halbbreite %.3f außerhalb 0.27–0.33 (Web: ≈0.30)" % koerper_halb
	)
	var kopf_halb: float = mass["kopf_breite"] / 2.0
	assert_true(
		kopf_halb >= 0.20 and kopf_halb <= 0.25,
		"Kopf-Halbbreite %.3f außerhalb 0.20–0.25 (Web: ≈0.224)" % kopf_halb
	)
	assert_true(
		mass["kopf_koerper"] >= 0.70 and mass["kopf_koerper"] <= 0.78,
		"Kopf/Körper-Breite %.3f außerhalb 0.70–0.78 (Web: 0.739)" % mass["kopf_koerper"]
	)
	assert_true(
		mass["auge_kopf"] >= 0.12 and mass["auge_kopf"] <= 0.17,
		"Auge/Kopf-Breite %.3f außerhalb 0.12–0.17 (Web: 0.143)" % mass["auge_kopf"]
	)


func test_palette_ist_srgb_byte_genau() -> void:
	var image := _palette_image()
	assert_true(image != null, "keine Palette-Textur am Gooby-Material gefunden")
	if image == null:
		return
	assert_eq(image.get_width(), 256, "Palette-Textur ist nicht 256 px breit")
	for teil: String in PALETTE_CELLS:
		var px: Vector2i = PALETTE_CELLS[teil][0]
		var soll: Color = PALETTE_CELLS[teil][1]
		var ist := image.get_pixel(px.x, px.y)
		var delta := (
			maxf(absf(ist.r - soll.r), maxf(absf(ist.g - soll.g), absf(ist.b - soll.b))) * 255.0
		)
		assert_true(
			delta <= PALETTE_TOLERANZ,
			(
				(
					"Palette-Zelle '%s' weicht ab: ist (%d,%d,%d), soll (%d,%d,%d) — "
					% [teil, ist.r8, ist.g8, ist.b8, soll.r8, soll.g8, soll.b8]
				)
				+ "build_mesh.py schreibt vermutlich wieder Linear- statt sRGB-Werte"
			)
		)


## Misst die Proportionen aus den Mesh-Vertices; Körperteile werden über die
## Palette-UV-Zelle unterschieden (build_mesh.py: 1 Zelle pro Teil). Gleiche
## Logik wie scripts/character/fb1_render_probe.gd.
func _measure() -> Dictionary:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var mesh_instance: MeshInstance3D = null
	for child in model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance = child
		break
	var arrays := mesh_instance.get_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var min_y := INF
	var max_y := -INF
	var body_max_x := 0.0
	var head_max_x := 0.0
	var eye_min_x := INF
	var eye_max_x := -INF
	for i in range(verts.size()):
		var v := verts[i]
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
		if uvs[i].distance_to(UV_CELL_BODY) < 0.01:
			# Körper = breitestes Band unten, nur Rückseite (Ärmchen/Füße
			# teilen die body-Zelle, liegen aber vorn). Kopf = Band um das
			# Kopfzentrum (0.48–0.62), wohin die Ohren nicht reichen.
			if v.y < 0.45 and v.z < -0.03:
				body_max_x = maxf(body_max_x, absf(v.x))
			elif v.y >= 0.48 and v.y <= 0.62:
				head_max_x = maxf(head_max_x, absf(v.x))
		if uvs[i].distance_to(UV_CELL_EYE) < 0.01 and v.x < 0.0:
			eye_min_x = minf(eye_min_x, v.x)
			eye_max_x = maxf(eye_max_x, v.x)
	model.free()
	var kopf_breite := head_max_x * 2.0
	var koerper_breite := body_max_x * 2.0
	var auge_breite := eye_max_x - eye_min_x
	return {
		"hoehe": max_y - min_y,
		"koerper_breite": koerper_breite,
		"kopf_breite": kopf_breite,
		"kopf_koerper": kopf_breite / koerper_breite if koerper_breite > 0.0 else 0.0,
		"auge_kopf": auge_breite / kopf_breite if kopf_breite > 0.0 else 0.0,
	}


## Holt das Albedo-Textur-Image vom Gooby-Material aus dem GLB.
func _palette_image() -> Image:
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()
	var image: Image = null
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var material := mesh_instance.get_active_material(0) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			image = material.albedo_texture.get_image()
			if image.is_compressed():
				image.decompress()
			break
	model.free()
	return image
