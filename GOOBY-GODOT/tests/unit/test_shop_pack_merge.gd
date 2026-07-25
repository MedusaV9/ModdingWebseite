extends TestCase
## CONTENT-B — Nachlieferbarkeit: zusätzliche Möbel kommen als Content-Pack
## (`content/furniture/`) über die ContentRegistry-Domain `furniture_extra`
## und werden vom ShopCatalog in den Basis-Katalog gemischt. Damit braucht
## neues Mobiliar KEIN App-Update (Doc B §4.2 / User-Wunsch B).

const PACK_JSON := "res://content/furniture/pack.json"
const EXTRA_JSON := "res://content/furniture/data/furniture_extra.json"


class FakeRegistry:
	extends RefCounted

	var items: Array = []

	func get_items(_domain: String) -> Array:
		return items


func _teardown() -> void:
	ShopCatalog.registry_override = null
	ShopCatalog.reset_cache()


func test_pack_manifest_ist_gueltig() -> void:
	var meta := UpdatesManifest.read_pack_meta(PACK_JSON)
	assert_false(meta.is_empty(), "pack.json lesbar")
	assert_eq(str(meta.get("id", "")), "furniture")
	assert_true(meta.get("domains") is Array, "Domains deklariert")
	assert_true((meta["domains"] as Array).has(ShopCatalog.PACK_DOMAIN), "Domain passt")
	assert_true(UpdatesManifest.priority_of(meta) > 0, "Priorität gesetzt")


func test_mitgelieferte_pack_datei_hat_katalog_form() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_JSON))
	assert_true(parsed is Dictionary, "furniture_extra.json parst")
	if not (parsed is Dictionary):
		return
	var doc: Dictionary = parsed
	assert_eq(str(doc.get("schema", "")), "gooby.furniture/1", "gleiches Schema wie die Basis")
	assert_true(doc.get("items") is Array, "items-Liste")
	assert_true((doc["items"] as Array).size() >= 1, "Pack liefert Möbel")
	for entry: Variant in doc["items"]:
		assert_true(entry is Dictionary, "Eintrag ist ein Objekt")
		var item: Dictionary = entry
		for key in ["id", "name_de", "name_en", "glb", "footprint", "layer", "preis"]:
			assert_true(item.has(key), "%s: Feld %s" % [item.get("id", "?"), key])
		assert_true(
			ResourceLoader.exists("%s/%s" % [FurnitureCatalog.ASSETS_DIR, item["glb"]]),
			"%s: GLB existiert" % item["id"]
		)


func test_pack_moebel_landen_im_shop_katalog() -> void:
	var registry := FakeRegistry.new()
	registry.items = [
		{
			"id": "packTestLampe",
			"name_de": "Testlampe",
			"name_en": "Test Lamp",
			"glb": "lampRoundFloor.glb",
			"footprint": [1, 1],
			"layer": "FLOOR",
			"preis": 99,
			"lagerwert": 2,
			"kategorie": "lampen",
			"can_toggle_light": true,
			"variants": ["natur", "rose", "mint", "butter"],
		}
	]
	ShopCatalog.registry_override = registry
	ShopCatalog.reset_cache()
	var item := ShopCatalog.def("packTestLampe")
	assert_false(item.is_empty(), "Pack-Möbel ist da")
	assert_eq(int(item["preis"]), 99)
	assert_eq(item["footprint"], Vector2i(1, 1))
	assert_eq(int(item["layer"]), GridData.Layer.FLOOR)
	assert_true(bool(item["can_toggle_light"]), "Flag übernommen")
	assert_true(bool(item["pack"]), "als Pack-Möbel markiert")
	assert_true(bool(item["blocks_movement"]), "FLOOR blockiert per Default")
	assert_eq(item["variants"], ["natur", "rose", "mint", "butter"])
	assert_true(ShopCatalog.by_category("lampen").size() >= 1)
	assert_true(FurnitureNode.create(item, Vector2i.ZERO, 0, "pack") != null, "baut sich")
	_teardown()


func test_pack_darf_ein_basis_moebel_ueberschreiben() -> void:
	var vorher := int(ShopCatalog.def("chair")["preis"])
	var registry := FakeRegistry.new()
	registry.items = [
		{
			"id": "chair",
			"name_de": "Stuhl (Angebot)",
			"name_en": "Chair (Sale)",
			"glb": "chair.glb",
			"footprint": [1, 1],
			"layer": "FLOOR",
			"preis": 5,
			"kategorie": "sitzen",
		}
	]
	ShopCatalog.registry_override = registry
	ShopCatalog.reset_cache()
	assert_eq(int(ShopCatalog.def("chair")["preis"]), 5, "Pack gewinnt (Balancing per Update)")
	assert_ne(vorher, 5, "Basis-Preis war ein anderer")
	_teardown()


func test_kaputte_pack_eintraege_werden_uebersprungen() -> void:
	var registry := FakeRegistry.new()
	registry.items = [
		{"name_de": "ohne id", "layer": "FLOOR"},
		{"id": "packOhneLayer", "layer": "SCHUPPEN"},
		"kein Objekt",
	]
	ShopCatalog.registry_override = registry
	ShopCatalog.reset_cache()
	assert_true(ShopCatalog.def("packOhneLayer").is_empty(), "unbekannter Layer → raus")
	assert_true(ShopCatalog.ids().size() >= FurnitureCatalog.ids().size(), "Basis bleibt heil")
	_teardown()


## Der ECHTE Weg (kein Fake): das eingebaute Pack liegt unter res://content/
## und muss über den ContentRegistry-Autoload im Laden ankommen.
func test_eingebautes_pack_kommt_ueber_die_echte_registry_an() -> void:
	_teardown()
	var registry := tree.root.get_node_or_null(NodePath("ContentRegistry"))
	assert_true(registry != null, "ContentRegistry-Autoload fehlt")
	if registry == null:
		return
	assert_true(registry.known_pack_ids().has("furniture"), "Möbel-Pack wird erkannt")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_JSON))
	for entry: Variant in (parsed as Dictionary)["items"]:
		var id := str((entry as Dictionary)["id"])
		var item := ShopCatalog.def(id)
		assert_false(item.is_empty(), "Pack-Möbel %s fehlt im Laden" % id)
		assert_true(bool(item.get("pack", false)), "%s: als Pack-Möbel markiert" % id)
		assert_true(FurnitureNode.create(item, Vector2i.ZERO, 0, "p-%s" % id) != null, id)
