class_name FurnitureVariants
extends RefCounted
## Farb-/Stoff-Varianten für Möbel (CONTENT-B, Doc "IKEA" §D: „Farbe/Muster/
## Stoff anpassen“). Eine Variante ist KEIN eigenes GLB, sondern ein
## Umfärbe-Material (`furniture_variant.gdshader`), das über die Materialien
## des geladenen Modells gelegt wird — ein Modell, sechs Looks, null Speicher.
##
## Datenweg: der Katalog-Eintrag führt `"variants": ["natur", "rose", ...]`,
## also nur IDs. Die Farbwerte stehen hier (eine Quelle), die Anzeigenamen in
## `strings/<locale>/shop.json` unter `shop.variant.<id>` — so bleibt DE/EN
## paritätisch, was in reinen Daten-JSONs nicht ginge.
##
## Gespeichert wird die Varianten-ID im Lager-Eintrag (`StorageLogic.add`
## kennt `variant` seit W2a); "natur" ist der neutrale Default.

## Neutrale Variante: kein Tint, das Asset zeigt seine Originalfarben.
const DEFAULT_ID := "natur"
## Bezugshelligkeit beim Umfärben (Luminanz einer mittleren Pastellfläche).
const REFERENCE_LUMINANCE := 0.62
## Wie stark die Variante das Original überschreibt (1.0 = komplett).
const STRENGTH := 0.9
const SHADER := preload("res://scripts/shop/furniture_variant.gdshader")

## Pastell-Palette (AC-Look). Weiß = neutral, alles andere multipliziert.
const PALETTE := {
	"natur": Color(1.0, 1.0, 1.0),
	"rose": Color(1.0, 0.835, 0.898),
	"mint": Color(0.788, 0.941, 0.878),
	"himmel": Color(0.812, 0.914, 0.961),
	"butter": Color(1.0, 0.937, 0.761),
	"lavendel": Color(0.886, 0.839, 0.961),
	"salbei": Color(0.839, 0.898, 0.776),
	"sand": Color(0.937, 0.878, 0.776),
	"koralle": Color(1.0, 0.824, 0.761),
	"schiefer": Color(0.835, 0.863, 0.886),
}

## Fallback für Katalog-Einträge OHNE eigene `variants`-Liste (die 72
## Basis-Möbel aus W2a) — sie bekommen im Laden trotzdem Farbauswahl.
const FALLBACK_IDS: Array[String] = ["natur", "rose", "mint", "himmel"]


## Varianten-IDs einer (ShopCatalog-)Def. Unbekannte IDs fliegen raus,
## "natur" steht garantiert an erster Stelle.
static func ids_for(item_def: Dictionary) -> Array:
	var raw: Variant = item_def.get("variants", [])
	var out: Array[String] = [DEFAULT_ID]
	if not (raw is Array) or (raw as Array).is_empty():
		raw = FALLBACK_IDS
	for entry: Variant in raw:
		var id := str(entry)
		if PALETTE.has(id) and not out.has(id):
			out.append(id)
	return out


static func is_known(variant_id: String) -> bool:
	return PALETTE.has(variant_id)


## Tint einer Variante (unbekannt → neutral weiß, nie ein Absturz).
static func tint(variant_id: String) -> Color:
	return PALETTE.get(variant_id, PALETTE[DEFAULT_ID])


## Gültige Variante für eine Def (fällt weich auf "natur" zurück).
static func normalize(item_def: Dictionary, variant_id: String) -> String:
	var allowed := ids_for(item_def)
	return variant_id if allowed.has(variant_id) else DEFAULT_ID


static func label_key(variant_id: String) -> String:
	return "shop.variant.%s" % variant_id


static func label(variant_id: String) -> String:
	return I18nService.t(label_key(variant_id))


## CPU-Spiegel der Shader-Rechnung (Tests/Vorschau): Helligkeit des Originals
## behalten, Farbton von der Variante nehmen. Ein simples Multiplizieren
## reicht NICHT — ein sattblaues Sofa × Rosé bleibt blau, und bei texturierten
## Packs (Albedo = Weiß) passierte gar nichts Sichtbares.
static func blend(base_albedo: Color, variant_id: String) -> Color:
	if variant_id == DEFAULT_ID:
		return base_albedo
	var color := tint(variant_id)
	var level := clampf(base_albedo.get_luminance() / REFERENCE_LUMINANCE, 0.35, 1.15)
	var recolored := Color(color.r * level, color.g * level, color.b * level, base_albedo.a)
	return base_albedo.lerp(recolored, STRENGTH)


## Legt die Variante auf ALLE Meshes unter `root`; die Originalmaterialien
## bleiben unangetastet (getönt wird immer eine Kopie). "natur" stellt den
## Ausgangszustand wieder her — wichtig beim Durchklicken in der Ausstellung.
static func apply(root: Node, variant_id: String) -> void:
	var neutral := variant_id == DEFAULT_ID
	for node in _mesh_instances(root):
		# Ein material_override an der MeshInstance schlägt ALLE Surface-
		# Materialien — dann muss genau dort getönt werden, sonst passiert
		# sichtbar nichts (FurnitureNode setzt es z. B. für Ghost-Möbel).
		var ganz := _basis_node(node)
		if ganz["source"] != null:
			node.material_override = (
				ganz["override"] if neutral else _tinted(ganz["source"], variant_id)
			)
			continue
		for surface in node.mesh.get_surface_count():
			var basis := _basis(node, surface)
			if neutral:
				node.set_surface_override_material(surface, basis["override"])
				continue
			var source: BaseMaterial3D = basis["source"]
			if source == null:
				continue
			node.set_surface_override_material(surface, _tinted(source, variant_id))


## Umfärbe-Material zu einem Originalmaterial. Die Texturen des Originals
## reisen mit (KayKit/Tiny-Treats-Atlanten), der Shader rechnet die Helligkeit
## pro Pixel um — deshalb wirkt die Variante auch auf getönten Atlanten.
static func _tinted(source: BaseMaterial3D, variant_id: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint", tint(variant_id))
	material.set_shader_parameter("base_color", source.albedo_color)
	material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("emission_color", source.emission)
	material.set_shader_parameter(
		"emission_strength", source.emission_energy_multiplier if source.emission_enabled else 0.0
	)
	material.set_shader_parameter("metallic_value", source.metallic)
	material.set_shader_parameter("roughness_value", source.roughness)
	material.set_shader_parameter("strength", STRENGTH)
	material.set_shader_parameter("reference_luminance", REFERENCE_LUMINANCE)
	return material


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root == null:
		return out
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		out.append_array(_mesh_instances(child))
	return out


## Ausgangszustand einer Surface, EINMAL pro Modell gemerkt (Meta):
##   source   = das zu tönende Originalmaterial
##   override = was vor dem ersten Tint im Override-Slot stand
## Beides ist nötig, weil der glTF-Import Materialien mal an der Mesh-Surface
## und mal (KayKit-Packs) direkt im Override-Slot der MeshInstance ablegt.
## Ohne das Merken würde ein Variantenwechsel den vorherigen Tint erneut
## tönen — und „natur“ würde bei Override-Assets das Material wegräumen
## (schneeweißes Möbel).
## Dasselbe für ein material_override an der MeshInstance selbst
## (source = null, wenn keins gesetzt ist → dann zählen die Surfaces).
static func _basis_node(node: MeshInstance3D) -> Dictionary:
	var key := "shop_variant_basis_node"
	if not node.has_meta(key):
		var override: Material = node.material_override
		node.set_meta(key, {"override": override, "source": override as BaseMaterial3D})
	return node.get_meta(key)


static func _basis(node: MeshInstance3D, surface: int) -> Dictionary:
	var key := "shop_variant_basis_%d" % surface
	if not node.has_meta(key):
		var override: Material = node.get_surface_override_material(surface)
		var source: Material = node.mesh.surface_get_material(surface)
		if source == null:
			source = override
		if source == null:
			source = node.material_override
		node.set_meta(key, {"override": override, "source": source as BaseMaterial3D})
	return node.get_meta(key)
