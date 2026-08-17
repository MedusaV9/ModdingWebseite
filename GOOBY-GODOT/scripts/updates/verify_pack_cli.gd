extends SceneTree
## CI-Smoketest (Doc B §7): lädt ein gebautes .pck und liest dessen pack.json —
## fängt den Klassiker „JSON-Export-Filter vergessen → Pack ohne Daten“.
##
## Aufruf (aus GOOBY-GODOT/):
##   godot --headless --path . --script res://scripts/updates/verify_pack_cli.gd \
##     -- --pack=/abs/pfad/cosmetics-v1.0.0.pck --id=cosmetics [--expect-version=1.0.0]
## Exit 0 = ok, 1 = Fehler. Owner: W2b (tools/packs/build_packs.sh ruft das auf).


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var pack_path := str(args.get("pack", ""))
	var pack_id := str(args.get("id", ""))
	if pack_path.is_empty() or pack_id.is_empty():
		printerr("verify_pack_cli: --pack=<pfad.pck> und --id=<pack_id> sind Pflicht.")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(pack_path, true):
		printerr("verify_pack_cli: Pack lädt nicht: %s" % pack_path)
		quit(1)
		return
	var meta_path := "res://content/%s/pack.json" % pack_id
	var meta := UpdatesManifest.read_pack_meta(meta_path)
	if meta.is_empty():
		printerr("verify_pack_cli: %s fehlt/kaputt im Pack (Export-Filter prüfen!)" % meta_path)
		quit(1)
		return
	if str(meta.get("id", "")) != pack_id:
		printerr("verify_pack_cli: pack.json-id '%s' != erwartet '%s'." % [meta.get("id"), pack_id])
		quit(1)
		return
	var expect_version := str(args.get("expect-version", ""))
	if not expect_version.is_empty() and str(meta.get("version", "")) != expect_version:
		printerr(
			(
				"verify_pack_cli: version '%s' != erwartet '%s'."
				% [meta.get("version"), expect_version]
			)
		)
		quit(1)
		return
	print("verify_pack_cli: OK — %s v%s aus %s" % [pack_id, meta.get("version"), pack_path])
	quit(0)


func _parse_args(user_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in user_args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			parsed[body] = "true"
		else:
			parsed[body.substr(0, eq)] = body.substr(eq + 1)
	return parsed
