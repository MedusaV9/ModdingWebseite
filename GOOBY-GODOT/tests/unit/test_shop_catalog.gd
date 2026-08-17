extends TestCase
## CONTENT-B — Möbel-Masse & Katalog-Qualität: Menge, existierende GLBs,
## plausible Footprints gegen die echten Mesh-Bounds, Varianten-Schema,
## DE/EN-Parität der Möbelnamen und Vertragstreue der ShopCatalog-Schicht
## gegenüber `FurnitureCatalog` (die NICHT angefasst wird).

## User-Wunsch D: „SEHR viele Möbel am Ende“ — Untergrenze fürs Regal.
const MIN_ITEMS := 145
## Kategorien, die die Ausstellung mindestens führen muss (User: Küche mit
## Deko-Artikeln wie Toaster, Bad, Büro, Party-Deko, Bilder …).
const PFLICHT_KATEGORIEN: Array[String] = [
	"bad",
	"bilder",
	"buero",
	"deko",
	"garten",
	"kueche",
	"lampen",
	"party",
	"pflanzen",
	"regale",
	"schlafen",
	"sitzen",
	"teppiche",
	"tische",
]
## Footprint-Seitenverhältnis darf höchstens um diesen Faktor von der
## Grundfläche des Modells abweichen (sonst steht das Möbel „gequetscht“).
const MAX_ASPECT_DRIFT := 3.0
## Unter dieser Tiefe/Breite ist ein Modell brettartig (Poster, Zaun, TV) —
## das Seitenverhältnis sagt dann nichts über den Platzbedarf aus.
const FLAT_LIMIT := 0.15


func test_katalog_hat_sehr_viele_moebel() -> void:
	ShopCatalog.reset_cache()
	var ids := ShopCatalog.ids()
	assert_true(ids.size() >= MIN_ITEMS, "mind. %d Möbel (sind: %d)" % [MIN_ITEMS, ids.size()])
	var per_kategorie := {}
	for id: String in ids:
		var kategorie := str(ShopCatalog.def(id)["kategorie"])
		per_kategorie[kategorie] = int(per_kategorie.get(kategorie, 0)) + 1
	for kategorie in PFLICHT_KATEGORIEN:
		assert_true(
			int(per_kategorie.get(kategorie, 0)) >= 3,
			"Kategorie %s braucht Auswahl (hat %d)" % [kategorie, per_kategorie.get(kategorie, 0)]
		)


func test_kueche_hat_die_gewuenschten_geraete() -> void:
	# User-Wunsch D wörtlich: „viele Deko-Artikel (Toaster etc.)“.
	for id in ["toaster", "kitchenMicrowave", "kitchenCoffeeMachine", "kitchenBlender"]:
		var item := ShopCatalog.def(id)
		assert_false(item.is_empty(), "Küchengerät fehlt: %s" % id)
		assert_eq(str(item.get("kategorie", "")), "kueche", "%s: Kategorie" % id)


func test_alle_glb_pfade_existieren() -> void:
	for id: String in ShopCatalog.ids():
		var item := ShopCatalog.def(id)
		if str(item.get("proc", "")) != "":
			assert_eq(str(item.get("glb", "")), "", "%s: proc-Möbel ohne GLB" % id)
			continue
		var path := FurnitureCatalog.glb_path(item)
		assert_true(ResourceLoader.exists(path), "GLB fehlt: %s (%s)" % [path, id])


func test_footprints_passen_zu_den_mesh_bounds() -> void:
	for id: String in ShopCatalog.ids():
		var item := ShopCatalog.def(id)
		if int(item["layer"]) != GridData.Layer.FLOOR and int(item["layer"]) != GridData.Layer.RUG:
			continue  # WALL/SURFACE hängen bzw. stehen auf — Tiefe ist egal
		var bounds := _bounds(item)
		if bounds.size.x < FLAT_LIMIT or bounds.size.z < FLAT_LIMIT:
			continue
		var fp: Vector2i = item["footprint"]
		var want := float(fp.x) / float(fp.y)
		var got := bounds.size.x / bounds.size.z
		var drift := maxf(want / got, got / want)
		assert_true(
			drift <= MAX_ASPECT_DRIFT,
			(
				"%s: Footprint %d×%d passt nicht zum Modell (%.2f×%.2f m, Faktor %.2f)"
				% [id, fp.x, fp.y, bounds.size.x, bounds.size.z, drift]
			)
		)


func test_varianten_schema() -> void:
	for id: String in ShopCatalog.ids():
		var item := ShopCatalog.def(id)
		var variants: Variant = item.get("variants")
		assert_true(variants is Array, "%s: variants ist eine Liste" % id)
		if not (variants is Array):
			continue
		var list: Array = variants
		assert_true(list.size() >= 4, "%s: mind. 4 Farben (hat %d)" % [id, list.size()])
		assert_true(list.size() <= 6, "%s: höchstens 6 Farben (hat %d)" % [id, list.size()])
		assert_eq(str(list[0]), FurnitureVariants.DEFAULT_ID, "%s: Neutral zuerst" % id)
		var seen := {}
		for variant_id: Variant in list:
			assert_true(FurnitureVariants.is_known(str(variant_id)), "%s: %s" % [id, variant_id])
			assert_false(seen.has(str(variant_id)), "%s: %s doppelt" % [id, variant_id])
			seen[str(variant_id)] = true


func test_namen_de_en_und_preise() -> void:
	for id: String in ShopCatalog.ids():
		var item := ShopCatalog.def(id)
		var name_de := str(item["name_de"])
		var name_en := str(item["name_en"])
		assert_true(name_de != "" and name_de != id, "%s: deutscher Name" % id)
		assert_true(name_en != "", "%s: englischer Name" % id)
		assert_true(int(item["preis"]) >= 0, "%s: Preis nicht negativ" % id)
		assert_true(int(item["lagerwert"]) >= 1 and int(item["lagerwert"]) <= 4, "%s: Lager" % id)
	# Im Regal steht NUR, was auch einen Preis hat (Preis 0 = Werkstatt-Möbel).
	for item: Dictionary in ShopCatalog.filter(""):
		assert_true(int(item["preis"]) > 0, "%s: Ladenpreis > 0" % item["id"])


func test_ids_und_namen_sind_eindeutig() -> void:
	var de_seen := {}
	for id: String in ShopCatalog.ids():
		var name_de := str(ShopCatalog.def(id)["name_de"])
		assert_false(
			de_seen.has(name_de),
			"Doppelter DE-Name: %s (%s/%s)" % [name_de, de_seen.get(name_de, ""), id]
		)
		de_seen[name_de] = id


func test_shop_catalog_bricht_den_basis_vertrag_nicht() -> void:
	# Die Basis-Defs müssen 1:1 die von FurnitureCatalog sein — ShopCatalog
	# darf nur `variants`/`pack` ergänzen, sonst laufen Laden und Baumodus
	# auseinander.
	for id: String in FurnitureCatalog.ids():
		var base: Dictionary = FurnitureCatalog.defs()[id]
		var shop := ShopCatalog.def(id)
		assert_false(shop.is_empty(), "%s: im Laden vorhanden" % id)
		for key: String in base:
			assert_eq(shop.get(key), base[key], "%s: Feld %s unverändert" % [id, key])
		assert_false(bool(shop.get("pack", true)), "%s: kommt aus dem Basis-Katalog" % id)


func test_kategorien_haben_alle_einen_string_key() -> void:
	for kategorie: String in ShopCatalog.categories():
		assert_true(
			I18nService.has_key("shop.kategorie.%s" % kategorie),
			"String-Key fehlt: shop.kategorie.%s" % kategorie
		)


func test_suche_und_kategorie_filter() -> void:
	var alle := ShopCatalog.filter("")
	var verkaeuflich := 0
	for id: String in ShopCatalog.ids():
		if ShopCatalog.sellable(ShopCatalog.def(id)):
			verkaeuflich += 1
	assert_eq(alle.size(), verkaeuflich, "leerer Filter = alles Verkäufliche")
	var kueche := ShopCatalog.by_category("kueche")
	assert_true(kueche.size() >= 10, "Küche gut bestückt (%d)" % kueche.size())
	for item: Dictionary in kueche:
		assert_eq(str(item["kategorie"]), "kueche")
	var toaster := ShopCatalog.filter("toast")
	assert_true(toaster.size() >= 1, "Suche nach 'toast' findet den Toaster")
	var englisch := ShopCatalog.filter("microwave")
	assert_true(englisch.size() >= 1, "Suche greift auch auf EN-Namen")
	var nichts := ShopCatalog.filter("zzzgibtesnicht")
	assert_true(nichts.is_empty(), "unsinnige Suche liefert nichts")
	var preise_sortiert := true
	for i in range(1, alle.size()):
		if int(alle[i]["preis"]) < int(alle[i - 1]["preis"]):
			preise_sortiert = false
	assert_true(preise_sortiert, "Regal ist nach Preis sortiert")


func test_footprint_text() -> void:
	assert_eq(ShopCatalog.footprint_text({"footprint": Vector2i(4, 2)}), "4×2")
	assert_eq(ShopCatalog.footprint_text({}), "1×1")


## Zusammengefasste Mesh-AABB eines Katalog-Modells (Modellmaße in Metern,
## unabhängig vom Grid-Fit, den FurnitureNode später macht).
func _bounds(item: Dictionary) -> AABB:
	var path := FurnitureCatalog.glb_path(item)
	if not ResourceLoader.exists(path):
		return AABB()
	var scene: PackedScene = load(path)
	if scene == null:
		return AABB()
	var root := scene.instantiate()
	var box := _merge(root, Transform3D.IDENTITY, AABB(), [false])
	root.free()
	return box


func _merge(node: Node, xform: Transform3D, box: AABB, found: Array) -> AABB:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var own := local * (node as MeshInstance3D).mesh.get_aabb()
		box = box.merge(own) if found[0] else own
		found[0] = true
	for child in node.get_children():
		box = _merge(child, local, box, found)
	return box
