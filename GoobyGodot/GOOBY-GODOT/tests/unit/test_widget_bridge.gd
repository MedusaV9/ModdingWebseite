extends TestCase
## iOS-WIDGETS: Tests fuer die WidgetBridge-Shell (widget_bridge.gd) mit
## Fake-Bridge — verifiziert Snapshot-Push (inkl. Schreib-Debounce), die
## Live-Activity-Zustandsmaschine (start/update/end/kind-Wechsel) und den
## No-op auf nicht unterstuetzten Plattformen. Dazu: die Datei-Outbox der
## GoobyKitBridge (atomarer Write, Seq-Restore nach Neustart).

const WidgetBridgeScript := preload("res://scripts/platform/widget_bridge.gd")
const GoobyKitBridgeScript := preload("res://scripts/platform/goobykit_bridge.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW := 1786528800000
const MS_PER_DAY := 86400000

var _seq := 0


class FakeBridge:
	extends RefCounted
	var supported := true
	var calls: Array = []
	var accept := true

	func is_supported() -> bool:
		return supported

	func set_widget_data(json: String) -> bool:
		calls.append(["set_widget_data", json])
		return accept

	func start_live_activity(json: String) -> bool:
		calls.append(["start_live_activity", json])
		return accept

	func update_live_activity(json: String) -> bool:
		calls.append(["update_live_activity", json])
		return accept

	func end_live_activity() -> bool:
		calls.append(["end_live_activity", ""])
		return accept

	func names() -> Array:
		var out: Array = []
		for call: Array in calls:
			out.append(call[0])
		return out

	func last_json(method: String) -> Dictionary:
		for i in range(calls.size() - 1, -1, -1):
			if calls[i][0] == method:
				var parsed: Variant = JSON.parse_string(calls[i][1])
				return parsed if parsed is Dictionary else {}
		return {}


func test_snapshot_wird_beim_attach_gepusht() -> void:
	var setup := _frische_bridge()
	var fake: FakeBridge = setup["fake"]
	assert_true(fake.names().has("set_widget_data"), "Snapshot beim Attach")
	var snap := fake.last_json("set_widget_data")
	assert_eq(str(snap.get("nickname", "")), "Flauschi", "Spitzname im Snapshot")
	assert_true(snap.has("coins"), "coins vorhanden")
	assert_true(snap.has("statusText"), "statusText vorhanden")
	assert_true(snap.has("countdown"), "countdown vorhanden")
	assert_false(fake.names().has("start_live_activity"), "frischer Stand: keine LA")
	_teardown(setup)


func test_debounce_schreibt_nur_bei_aenderung() -> void:
	var setup := _frische_bridge()
	var fake: FakeBridge = setup["fake"]
	var service: Node = setup["service"]
	var writes_before := fake.names().count("set_widget_data")
	service.sync_now()
	service.sync_now()
	assert_eq(
		fake.names().count("set_widget_data"), writes_before, "unveraenderter Stand: kein Write"
	)
	setup["gs"].set_value("economy.coins", 4242)
	service.sync_now()
	assert_eq(
		fake.names().count("set_widget_data"), writes_before + 1, "Muenz-Aenderung: ein Write"
	)
	assert_eq(int(fake.last_json("set_widget_data").get("coins", 0)), 4242, "neuer Muenzstand")
	_teardown(setup)


func test_live_activity_start_update_end() -> void:
	var setup := _frische_bridge()
	var fake: FakeBridge = setup["fake"]
	var service: Node = setup["service"]
	var gs: Node = setup["gs"]
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["sleep"] = {
				"sleeping": true, "startedAt": NOW - 60000, "wakeAt": NOW + 600000
			}
	)
	service.sync_now()
	assert_true(fake.names().has("start_live_activity"), "Schlaf-Start startet LA")
	assert_eq(str(fake.last_json("start_live_activity").get("kind", "")), "sleep", "LA-Art")
	var updates_before := fake.names().count("update_live_activity")
	service.sync_now()
	assert_eq(
		fake.names().count("update_live_activity"), updates_before, "gleicher Plan: kein Update"
	)
	gs.update(func(s: Dictionary) -> void: s["gooby"]["sleep"]["wakeAt"] = NOW + 1200000)
	service.sync_now()
	assert_eq(
		fake.names().count("update_live_activity"), updates_before + 1, "neuer wakeAt: Update"
	)
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["sleep"] = {"sleeping": false, "startedAt": 0, "wakeAt": 0}
	)
	service.sync_now()
	assert_true(fake.names().has("end_live_activity"), "Aufwachen beendet LA")
	_teardown(setup)


func test_live_activity_kind_wechsel_beendet_und_startet_neu() -> void:
	var setup := _frische_bridge()
	var fake: FakeBridge = setup["fake"]
	var service: Node = setup["service"]
	var gs: Node = setup["gs"]
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["sleep"] = {
				"sleeping": true, "startedAt": NOW - 60000, "wakeAt": NOW + 600000
			}
	)
	service.sync_now()
	fake.calls.clear()
	gs.update(
		func(s: Dictionary) -> void:
			s["gooby"]["sleep"] = {"sleeping": false, "startedAt": 0, "wakeAt": 0}
			s["vacation"]["phase"] = "away"
			s["vacation"]["destId"] = "beach"
			s["vacation"]["bookedAt"] = NOW - MS_PER_DAY
			s["vacation"]["returnAt"] = NOW + 2 * MS_PER_DAY
			s["vacation"]["pickupBy"] = NOW + 3 * MS_PER_DAY
	)
	service.sync_now()
	var names := fake.names()
	var end_idx := names.find("end_live_activity")
	var start_idx := names.find("start_live_activity")
	assert_true(end_idx >= 0, "alte LA beendet")
	assert_true(start_idx > end_idx, "neue LA erst NACH dem Ende gestartet")
	assert_eq(str(fake.last_json("start_live_activity").get("kind", "")), "vacation", "neue Art")
	_teardown(setup)


func test_nicht_unterstuetzt_ist_no_op() -> void:
	var setup := _frische_bridge(false)
	var fake: FakeBridge = setup["fake"]
	assert_eq(fake.calls, [], "unsupported: kein einziger Bridge-Call")
	_teardown(setup)


func test_vacation_signal_triggert_sofort_sync() -> void:
	var setup := _frische_bridge()
	var fake: FakeBridge = setup["fake"]
	var gs: Node = setup["gs"]
	fake.calls.clear()
	# vacation_changed feuert ueber das watched-value-Diffing von update().
	gs.update(
		func(s: Dictionary) -> void:
			s["vacation"]["phase"] = "away"
			s["vacation"]["destId"] = "beach"
			s["vacation"]["bookedAt"] = NOW
			s["vacation"]["returnAt"] = NOW + MS_PER_DAY
			s["vacation"]["pickupBy"] = NOW + 2 * MS_PER_DAY
	)
	assert_true(
		fake.names().has("start_live_activity"), "Signal allein stoesst LA an (ohne sync_now)"
	)
	_teardown(setup)


func test_goobykit_outbox_schreibt_und_restauriert() -> void:
	var dir := _tmp_dir("outbox")
	var bridge: RefCounted = GoobyKitBridgeScript.new(dir, true)
	assert_true(bridge.is_supported(), "force_enabled")
	assert_true(bridge.set_widget_data('{"v":1}'), "Snapshot-Write ok")
	var snap_path := dir.path_join("widget_snapshot.json")
	assert_true(FileAccess.file_exists(snap_path), "Snapshot-Datei liegt")
	assert_false(FileAccess.file_exists(snap_path + ".tmp"), "tmp-Datei weggeraeumt")
	assert_eq(FileAccess.get_file_as_string(snap_path), '{"v":1}', "Inhalt 1:1")
	assert_true(bridge.start_live_activity('{"kind":"sleep"}'), "LA-Start ok")
	var la_path := dir.path_join("live_activity.json")
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(la_path))
	assert_eq(int(envelope.get("seq", 0)), 1, "Seq 1 nach erstem Start")
	assert_true(bool(envelope.get("active", false)), "aktiv")
	assert_eq(str(envelope.get("payload", {}).get("kind", "")), "sleep", "Payload durchgereicht")
	bridge.end_live_activity()
	envelope = JSON.parse_string(FileAccess.get_file_as_string(la_path))
	assert_false(bool(envelope.get("active", true)), "inaktiv nach end")
	# App-Neustart: neue Bridge liest die Outbox und macht bei Seq 2 weiter.
	var bridge2: RefCounted = GoobyKitBridgeScript.new(dir, true)
	bridge2.start_live_activity('{"kind":"vacation"}')
	envelope = JSON.parse_string(FileAccess.get_file_as_string(la_path))
	assert_eq(int(envelope.get("seq", 0)), 2, "Seq laeuft nach Neustart weiter")


func test_goobykit_ist_auf_linux_deaktiviert() -> void:
	var bridge: RefCounted = GoobyKitBridgeScript.new()
	assert_false(bridge.is_supported(), "Linux/Headless: nicht unterstuetzt")
	assert_false(bridge.set_widget_data("{}"), "Write no-op")
	assert_false(bridge.start_live_activity("{}"), "Start no-op")


func _frische_bridge(supported := true) -> Dictionary:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(_tmp_dir("gs") + "/save_v5.json")
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})
	var fake := FakeBridge.new()
	fake.supported = supported
	var service: Node = WidgetBridgeScript.new()
	service.configure_for_tests(fake, 0, Callable(self, "_text"), Callable(self, "_leerer_pool"))
	service.attach_game_state(gs)
	return {"gs": gs, "service": service, "fake": fake}


func _teardown(setup: Dictionary) -> void:
	setup["service"].free()
	setup["gs"].free()


func _tmp_dir(label: String) -> String:
	_seq += 1
	var dir := "user://widget_bridge_tests/%s_%d_%d" % [label, Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


func _text(key: String, _args: Dictionary) -> String:
	return key


func _leerer_pool() -> Array:
	return []
