extends TestCase
## W2b UPDATES — ContentRegistry: Domain-Merges (append-by-id, deep-merge,
## last-writer-wins), user-config-Overlay, Fallbacks, get_net_config-Kontrakt
## (handoffs/W2b-config-api.md). Injizierte Temp-Roots statt res://content.

const BASE := "user://w2b_registry_test"


func test_append_by_id_override() -> void:
	var registry := _make_registry()
	var cosmetics := registry.get_cosmetics()
	var ids: Array = cosmetics.map(func(item): return item["id"])
	assert_eq(ids, ["hut_a", "hut_b", "hut_c"], "a von alpha, b überschrieben, c von beta")
	for item: Dictionary in cosmetics:
		if item["id"] == "hut_b":
			assert_eq(
				str(item["name_de"]), "Hut B (beta)", "höhere Priorität gewinnt bei Id-Kollision"
			)
	registry.free()
	_wipe(BASE)


func test_balance_deep_merge() -> void:
	var registry := _make_registry()
	assert_eq(registry.get_balance("nur_alpha"), 1.0, "alpha-Basiswert bleibt")
	assert_eq(registry.get_balance("nur_beta"), 2.0, "beta ergänzt")
	assert_eq(registry.get_balance("nested.tief_alpha"), 1.0, "deep-merge erhält alpha-Zweig")
	assert_eq(registry.get_balance("nested.tief_beta"), 9.0, "deep-merge überschreibt beta-Zweig")
	assert_eq(registry.get_balance("gibt_es_nicht", -1.0), -1.0, "Default bei fehlendem Key")
	registry.free()
	_wipe(BASE)


func test_config_last_writer_und_net() -> void:
	var registry := _make_registry()
	assert_eq(
		str(registry.get_config("manifest_url")), "https://alpha.example/m.json", "alpha-only"
	)
	assert_eq(str(registry.get_config("net.host")), "beta.example", "beta gewinnt (last writer)")
	var net := registry.get_net_config()
	assert_eq(str(net["host"]), "beta.example", "get_net_config host")
	assert_eq(int(net["port"]), 4242, "get_net_config port als int")
	assert_eq(bool(net["tls"]), true, "ehrlicher Offline-/WSS-Default garantiert TLS")
	registry.free()
	_wipe(BASE)


func test_user_config_overlay_gewinnt_immer() -> void:
	var registry := _make_registry(false)
	_write_json(
		BASE + "/packs/config.json",
		{"schema": 1, "net": {"host": "remote.example", "port": 999}, "flags": {"neu": true}}
	)
	registry.reload()
	var net := registry.get_net_config()
	assert_eq(str(net["host"]), "remote.example", "user://packs/config.json gewinnt (Doc B §1.1)")
	assert_eq(int(net["port"]), 999, "port aus Remote-Config")
	assert_eq(registry.get_config("flags.neu"), true, "neue Flags kommen an")
	assert_eq(
		str(registry.get_config("manifest_url")),
		"https://alpha.example/m.json",
		"nicht überschriebene Keys bleiben"
	)
	registry.free()
	_wipe(BASE)


func test_fallbacks_und_versionen() -> void:
	var registry := _make_registry()
	assert_eq(registry.get_items("gibt_es_nicht"), [], "unbekannte Domain → leeres Array")
	assert_eq(registry.get_stickers(), [], "keine Sticker geliefert → leer")
	assert_eq(registry.version_of("alpha"), "1.0.0", "version_of alpha")
	assert_eq(registry.version_of("beta"), "2.5.0", "version_of beta")
	assert_eq(registry.version_of("nix"), "0.0.0", "unbekanntes Pack → 0.0.0")
	assert_eq(registry.known_pack_ids(), ["alpha", "beta"], "bekannte Packs sortiert")
	var reload_count := [0]
	registry.content_reloaded.connect(func() -> void: reload_count[0] += 1)
	registry.reload()
	assert_eq(reload_count[0], 1, "content_reloaded feuert pro reload()")
	registry.free()
	_wipe(BASE)


func test_installed_only_pack_wird_uebersprungen() -> void:
	# Ein per Update NEU eingeführtes Pack steht in installed.json, aber sein
	# PCK wurde (noch) nicht geladen → kein res://content/<id>/ → sauber skippen.
	var registry := _make_registry(false)
	(
		UpdatesManifest
		. write_installed(
			BASE + "/packs/installed.json",
			{
				"schema": 1,
				"packs":
				{"phantom": {"version": "1.0.0", "enabled": true, "file": "phantom-v1.0.0.pck"}},
			}
		)
	)
	registry.reload()
	assert_eq(registry.known_pack_ids(), ["alpha", "beta"], "phantom ohne Daten wird ignoriert")
	registry.free()
	_wipe(BASE)


## Baut zwei Test-Packs: alpha (prio 100) und beta (prio 400) — beta gewinnt.
func _make_registry(do_reload := true) -> ContentRegistryService:
	_wipe(BASE)
	var root := BASE + "/content"
	_write_json(
		root + "/alpha/pack.json",
		{"id": "alpha", "version": "1.0.0", "priority": 100, "domains": ["cosmetics", "balance"]}
	)
	_write_json(
		root + "/alpha/data/cosmetics.json",
		{
			"schema": 1,
			"items":
			[
				{"id": "hut_a", "name_de": "Hut A"},
				{"id": "hut_b", "name_de": "Hut B (alpha)"},
			],
		}
	)
	_write_json(
		root + "/alpha/data/balance.json",
		{
			"schema": 1,
			"values": {"nur_alpha": 1.0, "nested": {"tief_alpha": 1.0, "tief_beta": 2.0}},
		}
	)
	_write_json(
		root + "/alpha/data/config.json",
		{
			"schema": 1,
			"manifest_url": "https://alpha.example/m.json",
			"net": {"host": "alpha.example"}
		}
	)
	_write_json(
		root + "/beta/pack.json",
		{"id": "beta", "version": "2.5.0", "priority": 400, "domains": ["cosmetics", "balance"]}
	)
	_write_json(
		root + "/beta/data/cosmetics.json",
		{
			"schema": 1,
			"items":
			[
				{"id": "hut_b", "name_de": "Hut B (beta)"},
				{"id": "hut_c", "name_de": "Hut C"},
			],
		}
	)
	_write_json(
		root + "/beta/data/balance.json",
		{"schema": 1, "values": {"nur_beta": 2.0, "nested": {"tief_beta": 9.0}}}
	)
	_write_json(
		root + "/beta/data/config.json",
		{"schema": 1, "net": {"host": "beta.example", "port": 4242}}
	)
	var registry := ContentRegistryService.new()
	registry.auto_reload = false
	registry.content_root = root
	registry.packs_dir = BASE + "/packs"
	DirAccess.make_dir_recursive_absolute(BASE + "/packs")
	if do_reload:
		registry.reload()
	return registry


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
