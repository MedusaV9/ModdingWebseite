extends TestCase
## W13B COUCH-COOP: Besucher-Couch-Regel (§C32) + Coop-Fahrt mit Radio-Sync
## (Doc C §3.6) — FakeLink-Muster (NetTestRig + echter VisitService/CoopDrive
## gegen FakeWsLink, keine 3D-Last: Szene/Gooby/Remote/HUD sind Mini-Fakes).
## Abgedeckt: Regel-Matrix (Zeit × Energien), Couch-Suche + Boden-Fallback,
## Einschlaf-/Aufweck-Flow inkl. NAP-Relay beider Seiten, drive:-Join/Leave-
## Statemaschine, Radio-Sync-Nachricht → beidseitiger Senderwechsel
## (Fake-Radio-API) und das Kaufhinweis-Gate ohne Gastgeber-Radio.

const ROOM := "visit:test-1"
const PEER := "GOOBY-PEER"
const COUCH_ITEM := "loungeSofa"


## Mini-Besuchsszene (Duck-Typing-Oberfläche des VisitManagers).
class FakeScene:
	extends Node

	var role := "guest"
	var snapshot: Dictionary = {}
	var my_room_id := "living"
	var my_gooby: Node = null
	var remote: Node = null
	var hud: Node = null
	var raumwechsel: Array = []

	var _vs: VisitService = null

	func visit_service() -> VisitService:
		return _vs

	func _switch_room(room_id: String, _via_door: String) -> void:
		raumwechsel.append(room_id)
		my_room_id = room_id


class FakeGooby:
	extends Node3D

	var clips: Array = []

	func play_clip(clip: String) -> void:
		clips.append(clip)


class FakeRemote:
	extends Node3D

	var naps: Array = []
	var wakes := 0

	func start_nap(pos: Vector3) -> void:
		naps.append(pos)

	func end_nap() -> void:
		wakes += 1


class FakeHud:
	extends Node

	var toasts: Array = []

	func show_toast(text: String) -> void:
		toasts.append(text)


class FakePresence:
	extends Node

	var kinds: Array = []

	var _kind := "home"

	func set_kind(kind: String) -> void:
		kinds.append(kind)
		_kind = kind

	func current_kind() -> String:
		return _kind


class FakeRadio:
	extends RefCounted

	var applied: Array = []

	func sender_setzen(station_id: String, track_id: String, offset_s: float) -> void:
		applied.append({"station": station_id, "track": track_id, "offset": offset_s})


# ── (a) Couch-Regel pur ──────────────────────────────────────────────────────


func test_couch_regel_matrix() -> void:
	# Zeit × Energien: erst ab 21 Uhr UND beide ≤ 10.
	assert_true(CouchLogic.soll_schlafen(21, 10.0, 10.0), "Schwelle inklusiv, 21 Uhr reicht")
	assert_true(CouchLogic.soll_schlafen(23, 0.0, 5.0))
	assert_false(CouchLogic.soll_schlafen(20, 0.0, 0.0), "20 Uhr ist noch kein Abend")
	assert_false(CouchLogic.soll_schlafen(22, 10.1, 5.0), "Gast zu fit")
	assert_false(CouchLogic.soll_schlafen(22, 5.0, 10.1), "Host-Gooby zu fit")
	assert_false(CouchLogic.soll_schlafen(-1, 5.0, 5.0), "Stunde unbekannt → aus")
	assert_false(CouchLogic.soll_schlafen(22, -1.0, 5.0), "Gast-Energie unbekannt → aus")
	assert_false(CouchLogic.soll_schlafen(22, 5.0, -1.0), "Host-Energie unbekannt → aus")


func test_couch_suchen_findet_wohnzimmer_couch() -> void:
	var couch := CouchLogic.couch_suchen(_snapshot_mit_couch())
	assert_true(couch["ok"])
	assert_eq(couch["cell"], Vector2i(2, 3))
	assert_eq(couch["item_id"], COUCH_ITEM)
	var def := FurnitureCatalog.def(COUCH_ITEM)
	assert_eq(couch["pos"], GridData.world_center(Vector2i(2, 3), def["footprint"], 0))


func test_couch_suchen_fallbacks() -> void:
	assert_false(CouchLogic.couch_suchen({})["ok"], "leerer Snapshot")
	var ohne := {"rooms": {"living": {"items": [{"item": "kaputt", "at": [1, 1], "uid": "x"}]}}}
	assert_false(CouchLogic.couch_suchen(ohne)["ok"], "kein Couch-Item (kaputter Alt-Save)")
	var falscher_raum := {
		"rooms": {"bedroom": {"items": [{"item": COUCH_ITEM, "at": [1, 1], "uid": "c"}]}}
	}
	assert_false(CouchLogic.couch_suchen(falscher_raum)["ok"], "Couch zählt nur im Wohnzimmer")


func test_nap_payload_roundtrip_und_robust() -> void:
	var nap := CouchLogic.parse_nap(CouchLogic.nap_payload(true, Vector2i(4, 5), true))
	assert_true(nap["ok"])
	assert_true(nap["on"])
	assert_true(nap["boden"])
	assert_eq(nap["cell"], Vector2i(4, 5))
	assert_false(CouchLogic.parse_nap(null)["ok"])
	assert_false(CouchLogic.parse_nap({"cell": [1, 2]})["ok"], "on ist Pflicht")


func test_pos_relay_traegt_energie_und_stunde() -> void:
	var body := VisitLogic.pos_payload(Vector3(1, 0, 2), "idle", "living", 7.5, 22)
	var parsed := VisitLogic.parse_pos(body)
	assert_almost(float(parsed["energy"]), 7.5, 0.01)
	assert_eq(parsed["hour"], 22)
	var alt := VisitLogic.pos_payload(Vector3(1, 0, 2), "idle", "living")
	assert_false(alt.has("energy"), "ohne Wert bleibt das W3c-Schema unverändert")
	assert_false(alt.has("hour"))
	var alt_parsed := VisitLogic.parse_pos(alt)
	assert_almost(float(alt_parsed["energy"]), -1.0, 0.01, "Alt-Client → unbekannt")
	assert_eq(alt_parsed["hour"], -1)


# ── (a) Einschlaf-/Aufweck-Flow über FakeLink ────────────────────────────────


func test_nap_flow_gast_geht_zur_couch() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)
	var scene := _make_scene(service, _snapshot_mit_couch())
	scene.my_room_id = "kitchen"
	var manager := _make_manager(scene, 4.0)
	var moves: Array = []
	manager.move_provider = func(ziel: Vector3) -> void: moves.append(ziel)
	var gestartet: Array = []
	manager.nap_gestartet.connect(func(boden: bool) -> void: gestartet.append(boden))

	_push_host_pos(rig, 22, 6.0)
	await wait_frames(2)

	assert_eq(manager.zustand, VisitManager.NapZustand.SCHLAEFT)
	assert_eq(gestartet, [false], "Couch da → kein Boden-Nickerchen")
	assert_eq(scene.raumwechsel, ["living"], "Nickerchen zieht ins Wohnzimmer")
	assert_eq(moves.size(), 1, "Gooby wandert zur Couch")
	assert_eq((scene.my_gooby as FakeGooby).clips, ["sleep"], "sleep-Pose der Rig-API")
	# Übers FakeLink gereist = JSON-normalisiert (Ints → Floats) → parse_nap.
	var nap := CouchLogic.parse_nap(_letzte_nap_nachricht(rig))
	assert_true(bool(nap["on"]))
	assert_false(bool(nap["boden"]))
	assert_eq(nap["cell"], Vector2i(2, 3))
	await _cleanup(rig, service)


func test_nap_fallback_boden_ohne_couch() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)
	var scene := _make_scene(service, {"rooms": {"living": {"items": []}}})
	var manager := _make_manager(scene, 2.0)
	var moves: Array = []
	manager.move_provider = func(ziel: Vector3) -> void: moves.append(ziel)
	var gestartet: Array = []
	manager.nap_gestartet.connect(func(boden: bool) -> void: gestartet.append(boden))

	_push_host_pos(rig, 23, 0.0)
	await wait_frames(2)

	assert_eq(gestartet, [true], "kaputter Alt-Save → Boden-Nickerchen")
	assert_eq(moves.size(), 0, "ohne Couch kein Ziel-Lauf")
	var nap := _letzte_nap_nachricht(rig)
	assert_true(bool(nap["on"]))
	assert_true(bool(nap["boden"]))
	assert_eq((scene.hud as FakeHud).toasts.size(), 1, "witzige Bubble beim Gast")
	await _cleanup(rig, service)


func test_aufweck_flow_und_wiederbewaffnung() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)
	var scene := _make_scene(service, _snapshot_mit_couch())
	var manager := _make_manager(scene, 4.0)
	manager.move_provider = func(_ziel: Vector3) -> void: pass
	_push_host_pos(rig, 22, 6.0)
	await wait_frames(2)
	assert_eq(manager.zustand, VisitManager.NapZustand.SCHLAEFT)

	manager.wecke_auf()
	assert_eq(manager.zustand, VisitManager.NapZustand.WACH)
	var nap := _letzte_nap_nachricht(rig)
	assert_false(bool(nap["on"]), "Aufwecken meldet NAP off an den Host")
	assert_eq((scene.my_gooby as FakeGooby).clips.back(), "idle")
	var toasts: Array = (scene.hud as FakeHud).toasts
	assert_eq(toasts.back(), I18nService.t("social.nap.wake_toast_guest"), "freundlicher Toast")

	# Regel gilt weiter → NICHT sofort wieder einschlafen (erst wenn die
	# Regel einmal aus war, ist sie wieder scharf).
	_push_host_pos(rig, 22, 6.0)
	await wait_frames(2)
	assert_eq(manager.zustand, VisitManager.NapZustand.WACH, "nach Wecken entschärft")
	_push_host_pos(rig, 22, 80.0)
	await wait_frames(2)
	_push_host_pos(rig, 22, 6.0)
	await wait_frames(2)
	assert_eq(manager.zustand, VisitManager.NapZustand.SCHLAEFT, "Regel aus→an bewaffnet neu")
	await _cleanup(rig, service)


func test_host_seite_zeigt_nap_und_wake() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, rig.client.friend_code, PEER)
	var scene := _make_scene(service, _snapshot_mit_couch())
	scene.role = VisitService.ROLE_HOST
	var manager := _make_manager(scene, 90.0)
	var remote := scene.remote as FakeRemote
	var hud := scene.hud as FakeHud

	_push_room_msg(rig, "NAP", CouchLogic.nap_payload(true, Vector2i(2, 3), false))
	await wait_frames(2)
	assert_eq(remote.naps.size(), 1, "Remote-Gooby legt sich hin")
	var def := FurnitureCatalog.def(COUCH_ITEM)
	assert_eq(remote.naps[0], GridData.world_center(Vector2i(2, 3), def["footprint"], 0))
	assert_eq(hud.toasts, [I18nService.t("social.nap.host_bubble")], "knuffige Host-Bubble")

	_push_room_msg(rig, "NAP", CouchLogic.nap_payload(false, Vector2i(2, 3), false))
	await wait_frames(2)
	assert_eq(remote.wakes, 1, "NAP off weckt den Remote-Gooby")
	assert_eq(hud.toasts.back(), I18nService.t("social.nap.host_wake"))
	assert_eq(manager.zustand, VisitManager.NapZustand.WACH, "Host-Seite schläft selbst nie")
	await _cleanup(rig, service)


# ── (b) Coop-Fahrt: drive:-Statemaschine ─────────────────────────────────────


func test_fahrer_startet_fahrt_und_relayt_auto() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var coop := _make_coop(rig)
	var presence := FakePresence.new()
	tree.root.add_child(presence)
	coop.presence_override = presence
	coop.nonce_provider = func() -> int: return 42

	var results: Array = []
	_collect(
		func() -> Dictionary: return await coop.starte_als_fahrer(ROOM, true, "Flauschi"), results
	)
	await wait_frames(1)
	var invite: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(invite["d"]["room"], ROOM, "Einladung reist übers Besuchs-Relay")
	assert_eq(invite["d"]["kind"], "DRIVE")
	assert_eq(invite["d"]["body"]["room"], "drive:%s-42" % rig.client.friend_code)
	assert_true(bool(invite["d"]["body"]["radio"]), "Radio-Gate des Gastgebers reist mit")
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_eq(coop.rolle, CoopDrive.ROLLE_FAHRER)
	assert_eq(presence.kinds, ["drive"], "Presence: fährt durch die Stadt (kind-basiert)")

	assert_true(coop.melde_auto(Vector3(3, 0, 4), 2.5), "1. Auto-POS sofort")
	assert_false(coop.melde_auto(Vector3(3.1, 0, 4), 2.5), "2. Send < 200 ms gedrosselt")
	var auto: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(auto["d"]["kind"], "POS")
	assert_eq(auto["d"]["body"]["anim"], "drive")
	assert_almost(float(auto["d"]["body"]["tempo"]), 2.5, 0.001)

	# Beifahrer steigt aus → der Fahrer fährt einfach weiter.
	var gegangen: Array = []
	coop.peer_gegangen.connect(func(data: Dictionary) -> void: gegangen.append(data))
	rig.link().push_server(
		{"v": 1, "t": "ROOM_PEER_LEFT", "ts": 0, "d": {"room": coop.room_id, "friendCode": PEER}}
	)
	await wait_frames(2)
	assert_eq(gegangen.size(), 1)
	assert_eq(coop.rolle, CoopDrive.ROLLE_FAHRER, "Fahrer degradiert NICHT")
	presence.queue_free()
	await _cleanup_coop(rig, coop)


func test_beifahrer_join_und_fahrer_weg() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var coop := _make_coop(rig)
	var presence := FakePresence.new()
	tree.root.add_child(presence)
	coop.presence_override = presence
	var einladungen: Array = []
	coop.einladung_erhalten.connect(func(data: Dictionary) -> void: einladungen.append(data))

	var drive_room := "drive:%s-7" % PEER
	_push_room_msg(rig, "DRIVE", CoopDriveLogic.einladung_payload(drive_room, true, "Flauschi"))
	await wait_frames(2)
	assert_eq(einladungen.size(), 1)
	assert_eq(einladungen[0]["von"], "Flauschi")

	var results: Array = []
	_collect(func() -> Dictionary: return await coop.beitreten(), results)
	await wait_frames(1)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_eq(coop.rolle, CoopDrive.ROLLE_BEIFAHRER)
	assert_true(coop.host_radio_owned)
	assert_eq(presence.kinds, ["drive"])

	# Mitfahr-Kamera: Auto-Position kommt über das POS-Relay des drive:-Rooms.
	var autos: Array = []
	coop.auto_pos_updated.connect(
		func(pos: Vector3, tempo: float) -> void: autos.append([pos, tempo])
	)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": drive_room, "kind": "POS", "body": {"pos": [9.5, 1.5], "tempo": 3.0}},
			}
		)
	)
	await wait_frames(2)
	assert_eq(autos.size(), 1)
	assert_eq(autos[0][0], Vector3(9.5, 0.0, 1.5))

	# Fahrer weg → sauberes Degradieren: Room verlassen, Presence zurück.
	var enden: Array = []
	coop.fahrt_beendet.connect(func(grund: String) -> void: enden.append(grund))
	rig.link().push_server(
		{"v": 1, "t": "ROOM_PEER_LEFT", "ts": 0, "d": {"room": drive_room, "friendCode": PEER}}
	)
	await wait_frames(2)
	assert_eq(enden, ["fahrer_weg"])
	assert_eq(coop.rolle, CoopDrive.ROLLE_KEINE)
	assert_eq(rig.link().last_sent("ROOM_LEAVE")["d"]["room"], drive_room)
	assert_eq(presence.kinds.back(), "home", "Presence-Kind wird zurückgesetzt")
	presence.queue_free()
	await _cleanup_coop(rig, coop)


func test_radio_sync_beidseitiger_senderwechsel() -> void:
	# Beifahrer-Seite: Aktion wendet lokal an UND reist als Room-Message.
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var coop := _make_coop(rig)
	var radio := FakeRadio.new()
	coop.radio_api = radio
	coop.now_ms_provider = func() -> int: return 100_000
	var drive_room := "drive:%s-7" % PEER
	await _als_beifahrer(rig, coop, drive_room, true)

	var erwartet := CoopDriveLogic.erster_track("gooby-fm")
	assert_false(erwartet.is_empty(), "Registry kennt gooby-fm-Tracks")
	assert_true(coop.radio_sender("gooby-fm"))
	assert_eq(radio.applied.size(), 1, "lokal sofort angewendet (Server echot nicht)")
	assert_eq(radio.applied[0]["station"], "gooby-fm")
	assert_eq(radio.applied[0]["track"], erwartet)
	var msg: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(msg["d"]["kind"], "RADIO")
	assert_eq(msg["d"]["body"]["trackId"], erwartet)
	assert_eq(int(msg["d"]["body"]["atMs"]), 100_000)

	# Skip: deterministisch der nächste Track (zyklisch).
	assert_true(coop.radio_skip())
	assert_eq(radio.applied.back()["track"], CoopDriveLogic.naechster_track("gooby-fm", erwartet))

	# Gegenseite (Fahrer, eigenes Rig): dieselbe Nachricht → derselbe Sender/
	# Track inkl. Startzeit-Offset aus atMs.
	var rig2 := NetTestRig.boot(tree)
	await rig2.go_online(tree, "GOOBY-HOST")
	var coop2 := _make_coop(rig2)
	var radio2 := FakeRadio.new()
	coop2.radio_api = radio2
	coop2.now_ms_provider = func() -> int: return 105_000
	coop2.nonce_provider = func() -> int: return 7
	var results: Array = []
	_collect(
		func() -> Dictionary: return await coop2.starte_als_fahrer(ROOM, true, "Flauschi"), results
	)
	await wait_frames(1)
	rig2.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var body: Dictionary = msg["d"]["body"]
	(
		rig2
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": coop2.room_id, "kind": "RADIO", "body": body},
			}
		)
	)
	await wait_frames(2)
	assert_eq(radio2.applied.size(), 1, "beidseitiger Senderwechsel")
	assert_eq(radio2.applied[0]["station"], "gooby-fm")
	assert_eq(radio2.applied[0]["track"], erwartet)
	assert_almost(float(radio2.applied[0]["offset"]), 5.0, 0.001, "Offset = now − atMs")
	await _cleanup_coop(rig, coop)
	await _cleanup_coop(rig2, coop2)


func test_radio_gate_ohne_gastgeber_radio() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var coop := _make_coop(rig)
	var radio := FakeRadio.new()
	coop.radio_api = radio
	var drive_room := "drive:%s-9" % PEER
	await _als_beifahrer(rig, coop, drive_room, false)

	var vorher := rig.link().count_sent("ROOM_MSG")
	assert_false(coop.radio_sender("gooby-fm"), "ohne Gastgeber-Radio kein Senderwechsel")
	assert_false(coop.radio_skip())
	assert_eq(radio.applied.size(), 0)
	assert_eq(rig.link().count_sent("ROOM_MSG"), vorher, "keine RADIO-Nachricht")

	# Beifahrer-UI: Kaufhinweis statt Regler.
	var ui := BeifahrerUi.new()
	tree.root.add_child(ui)
	ui.setup(coop)
	ui.zeige_beifahrer(false, "Flauschi")
	await wait_frames(1)
	var box: Node = ui.get_node("RadioPanel").find_child("RadioBox", true, false)
	assert_true(box.has_node("Kaufhinweis"), "Kaufhinweis sichtbar")
	assert_false(box.has_node("Sender_gooby-fm"), "keine Sender-Regler")
	assert_false(box.has_node("Skip"))
	ui.zeige_beifahrer(true, "Flauschi")
	await wait_frames(1)
	assert_true(box.has_node("Sender_gooby-fm"), "mit Radio: Sender-Knöpfe da")
	assert_true(box.has_node("Skip"))
	assert_false(box.has_node("Kaufhinweis"))
	ui.queue_free()
	await _cleanup_coop(rig, coop)


func test_coop_drive_logic_helfer() -> void:
	assert_eq(CoopDriveLogic.drive_room_id("GOOBY-X", 5), "drive:GOOBY-X-5")
	assert_false(CoopDriveLogic.parse_drive(null)["ok"])
	assert_false(CoopDriveLogic.parse_drive({"op": "invite", "room": "board:x"})["ok"])
	assert_false(CoopDriveLogic.parse_radio({"op": "set", "station": ""})["ok"])
	assert_almost(CoopDriveLogic.offset_sec(2000, 1000), 0.0, 0.001, "nie negativ")
	assert_almost(CoopDriveLogic.offset_sec(1000, 3500), 2.5, 0.001)
	var tracks := MusicRegistry.station_track_ids("gooby-fm")
	if tracks.size() >= 2:
		var letzter := str(tracks[tracks.size() - 1])
		assert_eq(CoopDriveLogic.naechster_track("gooby-fm", letzter), str(tracks[0]), "zyklisch")


# ── Helfer ───────────────────────────────────────────────────────────────────


func _make_service(rig: NetTestRig) -> VisitService:
	var service := VisitService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	return service


func _make_scene(service: VisitService, snapshot: Dictionary) -> FakeScene:
	var scene := FakeScene.new()
	scene._vs = service
	scene.snapshot = snapshot
	scene.my_gooby = FakeGooby.new()
	scene.remote = FakeRemote.new()
	scene.hud = FakeHud.new()
	scene.add_child(scene.my_gooby)
	scene.add_child(scene.remote)
	scene.add_child(scene.hud)
	tree.root.add_child(scene)
	return scene


func _make_manager(scene: FakeScene, eigene_energie: float) -> VisitManager:
	var manager := VisitManager.new()
	scene.add_child(manager)
	manager.energy_provider = func() -> float: return eigene_energie
	manager.hour_provider = func() -> int: return 22
	manager.setup(scene, false)
	return manager


func _make_coop(rig: NetTestRig) -> CoopDrive:
	var coop := CoopDrive.new()
	tree.root.add_child(coop)
	coop.setup(rig.client)
	return coop


func _als_beifahrer(
	rig: NetTestRig, coop: CoopDrive, drive_room: String, radio_owned: bool
) -> void:
	_push_room_msg(
		rig, "DRIVE", CoopDriveLogic.einladung_payload(drive_room, radio_owned, "Flauschi")
	)
	await wait_frames(2)
	var results: Array = []
	_collect(func() -> Dictionary: return await coop.beitreten(), results)
	await wait_frames(1)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_eq(coop.rolle, CoopDrive.ROLLE_BEIFAHRER)


func _snapshot_mit_couch() -> Dictionary:
	return {
		"v": 1,
		"goobyName": "Flauschi",
		"rooms": {"living": {"items": [{"item": COUCH_ITEM, "at": [2, 3], "rot": 0, "uid": "c1"}]}},
	}


## Host-POS mit Stunde + Energie einspielen (löst die Regel-Prüfung aus).
func _push_host_pos(rig: NetTestRig, stunde: int, energie: float) -> void:
	_push_room_msg(
		rig, "POS", VisitLogic.pos_payload(Vector3(1, 0, 1), "idle", "living", energie, stunde)
	)


func _letzte_nap_nachricht(rig: NetTestRig) -> Dictionary:
	for i in range(rig.link().sent.size() - 1, -1, -1):
		var envelope: Dictionary = rig.link().sent[i]
		if envelope.get("t") == "ROOM_MSG" and envelope["d"].get("kind") == "NAP":
			return envelope["d"]["body"]
	return {}


## VISIT_READY als Push einspielen + den folgenden ROOM_JOIN beantworten.
func _push_ready(rig: NetTestRig, host: String, guest: String) -> void:
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "VISIT_READY",
				"ts": 0,
				"d": {"room": ROOM, "host": host, "guest": guest, "rev": 3},
			}
		)
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)


func _push_room_msg(rig: NetTestRig, kind: String, body: Dictionary) -> void:
	rig.link().push_server(
		{"v": 1, "t": "ROOM_MSG", "ts": 0, "d": {"room": ROOM, "kind": kind, "body": body}}
	)


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, service: VisitService) -> void:
	service.queue_free()
	await rig.shutdown(tree)


func _cleanup_coop(rig: NetTestRig, coop: CoopDrive) -> void:
	coop.queue_free()
	await rig.shutdown(tree)
