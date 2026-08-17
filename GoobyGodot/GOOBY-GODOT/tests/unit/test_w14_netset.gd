extends TestCase
## W14/NETSET — Mehrspieler-Settings + Dev-Werkzeugkasten:
## (1) Override-Vorrang-Kette PUR (User-Settings > Pack-Config > Default)
##     inkl. Datei-Roundtrip und _resolve_net_config-Wirkung,
## (2) Secret-HELLO-Feld (FakeWsLink: mit Secret drin, ohne Secret NICHT),
## (3) Fehlertext-Mapping (Server-Code -> netset.mp.fehler.*, Keys DE+EN),
## (4) Dev-Aktionen ueber oeffentliche APIs: Gold setzen wirkt, Event-Trigger
##     feuert, Zeit-Offset verschiebt die Uhr (DevZeit ueber clock.pin).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _temp_dir() -> String:
	_seq += 1
	var dir := "user://w14_netset/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


func _fresh_gs() -> Node:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(_temp_dir() + "/save_v5.json")
	return gs


func _cleanup_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(DevActions.SLICE_ID)


## ------------------------------------------------- (1) Vorrang-Kette pur


func test_merge_vorrang_kette_user_pack_default() -> void:
	var defaults := {"host": "127.0.0.1", "port": 8765, "tls": false}
	var pack := {"host": "pack.example", "port": 9000, "tls": true}
	# Ohne User-Override gewinnt die Pack-Config.
	var merged := NetClient.merge_net_config(defaults, pack, {})
	assert_eq(str(merged["host"]), "pack.example", "Pack schlaegt Default")
	assert_eq(int(merged["port"]), 9000)
	assert_true(bool(merged["tls"]))
	assert_false(merged.has("secret"), "ohne Secret kein secret-Key")
	# User-Override gewinnt ueber Pack — auch tls=false, wenn der Key da ist.
	merged = NetClient.merge_net_config(
		defaults, pack, {"host": "user.example", "port": 4242, "tls": false, "secret": "sesam"}
	)
	assert_eq(str(merged["host"]), "user.example", "User schlaegt Pack")
	assert_eq(int(merged["port"]), 4242)
	assert_false(bool(merged["tls"]), "User-tls gewinnt, sobald der Key da ist")
	assert_eq(str(merged["secret"]), "sesam", "Secret wandert mit")
	# Leere/unbrauchbare User-Werte zaehlen als NICHT gesetzt.
	merged = NetClient.merge_net_config(defaults, pack, {"host": "  ", "port": 0})
	assert_eq(str(merged["host"]), "pack.example", "leerer User-Host faellt durch")
	assert_eq(int(merged["port"]), 9000, "Port 0 faellt durch")
	# Leere Pack-Config faellt auf den Default zurueck.
	merged = NetClient.merge_net_config(defaults, {}, {})
	assert_eq(str(merged["host"]), "127.0.0.1", "Default haelt")
	assert_eq(int(merged["port"]), 8765)


func test_user_override_datei_roundtrip() -> void:
	var path := _temp_dir() + "/override.json"
	assert_eq(NetClient.load_user_override(path), {}, "ohne Datei: leer")
	var ok := NetClient.save_user_override(
		{"host": "  gooby.local  ", "port": 1234, "tls": true, "secret": "abc"}, path
	)
	assert_true(ok, "Override gespeichert")
	var loaded := NetClient.load_user_override(path)
	assert_eq(str(loaded.get("host", "")), "gooby.local", "Host getrimmt")
	assert_eq(int(loaded.get("port", 0)), 1234)
	assert_true(bool(loaded.get("tls", false)))
	assert_eq(str(loaded.get("secret", "")), "abc")
	# Fremde Schluessel werden beim LESEN ignoriert (Allowlist).
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"host":"a.test","evil":"x"}')
	file.close()
	loaded = NetClient.load_user_override(path)
	assert_eq(str(loaded.get("host", "")), "a.test")
	assert_false(loaded.has("evil"), "unbekannte Keys bleiben draussen")
	# Kaputtes JSON: {} (Pack-Config gilt), kein Crash.
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{kaputt")
	file.close()
	assert_eq(NetClient.load_user_override(path), {}, "kaputte Datei == kein Override")
	# Zuruecksetzen: Datei weg; leeres Speichern loescht ebenfalls.
	assert_true(NetClient.clear_user_override(path))
	assert_false(FileAccess.file_exists(path), "clear entfernt die Datei")
	NetClient.save_user_override({"host": "b.test"}, path)
	NetClient.save_user_override({}, path)
	assert_false(FileAccess.file_exists(path), "leeres Speichern raeumt auf")


func test_resolve_net_config_liest_user_override_mit_vorrang() -> void:
	var dir := _temp_dir()
	var client := NetClient.new()
	client.auto_connect = false
	client.build_services = false
	client.identity_path = dir + "/identity.json"
	client.user_override_path = dir + "/override.json"
	tree.root.add_child(client)
	NetClient.save_user_override({"host": "10.0.0.7", "port": 4242}, client.user_override_path)
	var resolved: Dictionary = client._resolve_net_config()
	assert_eq(str(resolved["host"]), "10.0.0.7", "User-Override schlaegt Pack/Default")
	assert_eq(int(resolved["port"]), 4242)
	# config_override (Tests/Integration) schlaegt weiterhin ALLES.
	client.config_override = {"host": "fake.test", "port": 1, "tls": false}
	resolved = client._resolve_net_config()
	assert_eq(str(resolved["host"]), "fake.test", "config_override gewinnt")
	client.queue_free()
	await wait_frames(1)


## ------------------------------------------------- (2) Secret im HELLO


func test_hello_traegt_secret_aus_der_config() -> void:
	var dir := _temp_dir()
	var links: Array[FakeWsLink] = []
	var client := NetClient.new()
	client.auto_connect = false
	client.build_services = false
	client.identity_path = dir + "/identity.json"
	client.user_override_path = dir + "/override.json"
	client.config_override = {"host": "fake.test", "port": 1, "tls": false, "secret": "sesam"}
	client.link_factory = func() -> FakeWsLink:
		var link := FakeWsLink.new()
		links.append(link)
		return link
	tree.root.add_child(client)
	client.connect_now()
	links.back().open()
	await wait_frames(3)
	var hello: Dictionary = links.back().last_sent("HELLO")
	assert_false(hello.is_empty(), "HELLO wurde gesendet")
	var d: Dictionary = hello.get("d", {})
	assert_eq(str(d.get("secret", "")), "sesam", "Settings-Secret steht im HELLO")
	# Ohne Secret in der Config darf KEIN secret-Feld mitgehen (Kompatibilitaet).
	client.disconnect_now()
	client.config_override = {"host": "fake.test", "port": 1, "tls": false}
	client.connect_now()
	links.back().open()
	await wait_frames(3)
	d = links.back().last_sent("HELLO").get("d", {})
	assert_false(d.has("secret"), "ohne Config-Secret kein secret-Feld")
	client.queue_free()
	await wait_frames(1)


## --------------------------------------------- (3) Fehlertext-Mapping


func test_fehlertext_mapping_und_strings() -> void:
	assert_eq(
		MehrspielerSektion.fehler_text_key("SECRET_REQUIRED"), "netset.mp.fehler.secret_required"
	)
	assert_eq(MehrspielerSektion.fehler_text_key("SECRET_WRONG"), "netset.mp.fehler.secret_wrong")
	assert_eq(MehrspielerSektion.fehler_text_key("TIMEOUT"), "netset.mp.fehler.timeout")
	assert_eq(
		MehrspielerSektion.fehler_text_key("WAS_AUCH_IMMER"),
		"netset.mp.fehler.unbekannt",
		"unbekannte Codes landen auf unbekannt"
	)
	# Jeder gemappte Key existiert in DE UND EN (Chip-Grund ist nie leer).
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var keys: Array = MehrspielerSektion.FEHLER_KEYS.values()
	keys.append("netset.mp.fehler.unbekannt")
	for key: Variant in keys:
		assert_true(de.has(str(key)), "DE fehlt %s" % key)
		assert_true(en.has(str(key)), "EN fehlt %s" % key)


func test_parse_server_adresse() -> void:
	var p := MehrspielerSektion.parse_server_adresse("192.168.0.10")
	assert_eq(str(p["host"]), "192.168.0.10")
	assert_false(bool(p["tls"]), "nackter Host: Heimnetz-Standard ws://")
	assert_eq(int(p["port"]), -1, "kein Port in der Eingabe")
	p = MehrspielerSektion.parse_server_adresse("gooby.local:9001")
	assert_eq(str(p["host"]), "gooby.local")
	assert_eq(int(p["port"]), 9001)
	p = MehrspielerSektion.parse_server_adresse("wss://gooby.example:8443/pfad")
	assert_eq(str(p["host"]), "gooby.example")
	assert_true(bool(p["tls"]), "wss:// erzwingt TLS")
	assert_eq(int(p["port"]), 8443)
	p = MehrspielerSektion.parse_server_adresse("ws://10.0.0.5")
	assert_eq(str(p["host"]), "10.0.0.5")
	assert_false(bool(p["tls"]))


## ------------------------------------------------- (4) Dev-Aktionen


func test_dev_gold_setzen_wirkt() -> void:
	var gs := _fresh_gs()
	DevActions.set_gold(gs, 4321, NOW_MS)
	assert_eq(int(gs.get_value("economy.coins")), 4321, "Coins setzen wirkt")
	_cleanup_gs(gs)


func test_dev_event_trigger_feuert() -> void:
	var gs := _fresh_gs()
	var def := {"id": "w14_test_event", "szene_setup": "wohnzimmer"}
	assert_true(DevActions.trigger_event(gs, def, NOW_MS), "Trigger meldet Erfolg")
	assert_eq(str(gs.get_value("events.active.id", "")), "w14_test_event", "Event ist aktiv")
	assert_false(DevActions.trigger_event(gs, {}, NOW_MS), "leeres Def wird abgelehnt")
	# Die vom Engine-activate geplante Notification nicht in andere Tests leaken.
	NotifyStub.cancel_local("event_w14_test_event")
	_cleanup_gs(gs)


func test_dev_zeit_offset_verschiebt_uhr() -> void:
	var gs := _fresh_gs()
	var basis := NOW_MS
	var angezeigt := DevZeit.apply_offset(gs.clock, 2 * DevZeit.MS_PER_HOUR, basis)
	assert_eq(angezeigt, basis + 2 * DevZeit.MS_PER_HOUR)
	assert_eq(int(gs.clock.now_ms()), basis + 2 * DevZeit.MS_PER_HOUR, "Uhr laeuft 2 h vor")
	assert_eq(DevZeit.offset_stunden(26 * DevZeit.MS_PER_HOUR), 26, "Slider-Label-Stunden")
	# Offset 0 gibt die Uhr an die Echtzeit zurueck (unpin).
	DevZeit.apply_offset(gs.clock, 0, basis)
	var echt := int(Time.get_unix_time_from_system() * 1000.0)
	assert_true(absi(int(gs.clock.now_ms()) - echt) < 5_000, "nach Offset 0 tickt die Systemzeit")
	_cleanup_gs(gs)
