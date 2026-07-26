extends TestCase
## RANCH-1 — DLC-Pack-Merge: das eingebaute `content/ranch/`-Pack ist die
## Blaupause für „Content-Erweiterung per Auto-Update“ (Doc B §4.2). Die
## ContentRegistry muss es als Pack kennen, die ranch-Domain (append-by-id)
## und die Balance-Werte (deep-merge) liefern — und RanchKatalog liest
## alles NUR über die Registry.

const PACK_JSON := "res://content/ranch/pack.json"
const RANCH_JSON := "res://content/ranch/data/ranch.json"
const BALANCE_JSON := "res://content/ranch/data/balance.json"
const RegistryScript := preload("res://scripts/updates/content_registry.gd")

var _dir_seq := 0


func _make_registry() -> Node:
	_dir_seq += 1
	var packs := "user://ranch_tests/packs_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(packs))
	var registry: Node = RegistryScript.new()
	registry.auto_reload = false
	registry.content_root = "res://content"
	registry.packs_dir = packs
	registry.reload()
	return registry


func _teardown_katalog() -> void:
	RanchKatalog.registry_override = null
	RanchKatalog.reset_cache()


func test_pack_manifest_ist_gueltig() -> void:
	var meta := UpdatesManifest.read_pack_meta(PACK_JSON)
	assert_false(meta.is_empty(), "pack.json lesbar")
	assert_eq(str(meta.get("id", "")), "ranch")
	assert_true(meta.get("domains") is Array, "Domains deklariert")
	assert_true((meta["domains"] as Array).has("ranch"), "ranch-Domain deklariert")
	assert_true((meta["domains"] as Array).has("balance"), "balance-Domain deklariert")
	assert_true(UpdatesManifest.priority_of(meta) > 0, "Prioritaet gesetzt")


func test_pack_dateien_haben_katalog_form() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RANCH_JSON))
	assert_true(parsed is Dictionary, "ranch.json parst")
	if not (parsed is Dictionary):
		return
	var doc: Dictionary = parsed
	assert_eq(str(doc.get("schema", "")), "gooby.ranch/1", "Schema-Kennung")
	assert_true(doc.get("items") is Array, "items-Liste")
	var welt_gefunden := false
	var pferde := 0
	for entry: Variant in doc["items"]:
		assert_true(entry is Dictionary, "Eintrag ist ein Objekt")
		var item: Dictionary = entry
		assert_true(item.has("id"), "Eintrag hat id")
		assert_true(item.has("typ"), "%s: Eintrag hat typ" % item.get("id", "?"))
		if str(item.get("typ", "")) == "welt":
			welt_gefunden = true
		if str(item.get("typ", "")) == "tier":
			for key in ["art", "name_key", "farbe", "start"]:
				assert_true(item.has(key), "%s: Tier-Feld %s" % [item["id"], key])
			assert_true(
				I18nService.has_key(str(item["name_key"])),
				"%s: name_key existiert in den Strings" % item["id"]
			)
			if str(item.get("art", "")) == "pferd":
				pferde += 1
	assert_true(welt_gefunden, "welt-Eintrag vorhanden")
	assert_true(pferde >= 3, "mindestens drei Pferde im Riesen-DLC")
	var balance: Variant = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_JSON))
	assert_true(balance is Dictionary and (balance as Dictionary).get("values") is Dictionary)


func test_registry_merged_ranch_domain() -> void:
	var registry := _make_registry()
	assert_true(registry.known_pack_ids().has("ranch"), "Pack bekannt")
	assert_eq(registry.version_of("ranch"), "1.0.0", "Version aus pack.json")
	var items: Array = registry.get_items("ranch")
	var ids: Array = items.map(func(item: Dictionary) -> String: return str(item["id"]))
	assert_true(ids.has("welt"), "welt-Eintrag gemergt")
	assert_true(ids.has("tier_pferd_karamell"), "Pferd gemergt")
	assert_true(ids.has("ausbau_stall_2"), "Ausbau gemergt")
	assert_eq(int(registry.get_balance("ranch.preis", -1)), 2500, "Preis via deep-merge")
	assert_eq(int(registry.get_balance("ranch.freischalt_level", -1)), 20, "Gate via deep-merge")
	registry.free()


func test_katalog_liest_nur_aus_der_registry() -> void:
	var registry := _make_registry()
	RanchKatalog.registry_override = registry
	RanchKatalog.reset_cache()
	assert_eq(RanchKatalog.preis(), 2500, "Preis aus dem eingebauten Pack")
	assert_eq(RanchKatalog.freischalt_level(), 20, "Level-Gate aus dem Pack")
	assert_true(RanchKatalog.tiere().size() >= 6, "Tier-Katalog gefuellt")
	assert_eq(
		str(RanchKatalog.tier("tier_pferd_wolke").get("art", "")), "pferd", "Tier-Lookup per id"
	)
	var welt := RanchKatalog.welt()
	assert_true(float(welt.get("feld_breite_m", 0.0)) > 0.0, "Weltdaten vorhanden")
	_teardown_katalog()
	registry.free()


func test_katalog_faellt_ohne_registry_auf_defaults() -> void:
	RanchKatalog.registry_override = null
	RanchKatalog.reset_cache()
	# Im Test-SceneTree gibt es kein /root/ContentRegistry-Autoload — der
	# Katalog muss mit den eingebauten Defaults funktionieren.
	assert_eq(RanchKatalog.preis(), RanchKatalog.DEFAULT_PREIS)
	assert_eq(RanchKatalog.freischalt_level(), RanchKatalog.DEFAULT_FREISCHALT_LEVEL)
	_teardown_katalog()
