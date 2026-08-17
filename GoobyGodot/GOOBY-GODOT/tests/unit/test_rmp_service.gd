extends TestCase
## RanchMultiplayerService gegen NetClient+FakeWsLink (RW-6): Offline-
## Degradierung, Einladung→RANCH_READY (Antwort und Push) inkl. ROOM_JOIN,
## MG_READY mit Kurs-Hash, 10-Hz-Pose-Drossel, Peer-Posen/Reaktionen als
## Signale, MG_START-Zeitsync, MG_RESULT + idempotenter ACK, Pending aus
## WELCOME, Rejoin-Snapshot und Revanche.

const ROOM := "mg:test-1"
const PEER := "GOOBY-PEER"


func test_offline_alles_degradiert_sofort() -> void:
	var rig := NetTestRig.boot(tree)
	var service := _make_service(rig)
	assert_false(service.is_online())
	assert_eq((await service.invite(PEER, "rennen"))["code"], "OFFLINE")
	assert_eq((await service.accept(PEER))["code"], "OFFLINE")
	assert_eq((await service.set_ready())["code"], "OFFLINE")
	assert_eq((await service.rematch())["code"], "OFFLINE")
	assert_eq((await service.rest.fetch_leaderboard("grasbahn"))["code"], "OFFLINE")
	assert_eq((await service.rest.upload_ranch_meta(null))["code"], "OFFLINE")
	assert_false(service.send_pose(Vector3.ZERO, 0.0, 0.0, 0), "ohne Session keine Pose")
	await _cleanup(rig, service)


func test_ready_push_uebernimmt_session_und_joint_room() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	var ready: Array = []
	service.session_ready.connect(func(d: Dictionary) -> void: ready.append(d))
	await _push_ready(rig)
	assert_eq(service.room_id, ROOM)
	assert_eq(service.mode, "rennen")
	assert_eq(service.kurs, "grasbahn")
	assert_eq(service.host_code, PEER)
	assert_eq(service.players.size(), 2)
	assert_eq(ready.size(), 1)
	assert_eq(rig.link().count_sent("ROOM_JOIN"), 1)
	assert_eq(rig.link().last_sent("ROOM_JOIN")["d"]["room"], ROOM)
	await _cleanup(rig, service)


func test_mg_ready_schickt_kurs_hash() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig)
	var results: Array = []
	_collect(func() -> Dictionary: return await service.set_ready(), results)
	await wait_frames(1)
	assert_eq(
		rig.link().last_sent("MG_READY")["d"]["kursHash"],
		"grasbahn:v1:8",
		"Sync-Kontrakt mit dem Server"
	)
	rig.link().respond_to("MG_READY", "OK", {"ready": [rig.client.friend_code]})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	await _cleanup(rig, service)


func test_pose_drossel_10hz_und_force() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig)
	assert_true(service.send_pose(Vector3(1, 0, 2), 0.5, 3.0, 1), "1. Pose sofort")
	assert_false(service.send_pose(Vector3(1, 0, 2), 0.5, 3.0, 1), "2. Pose < 100 ms")
	assert_true(
		service.send_pose(Vector3(2, 0, 2), 0.5, 3.0, 1, "", true, true), "force umgeht Takt"
	)
	var posen := 0
	for envelope in rig.link().sent:
		if envelope.get("t") == "MG_POSE":
			posen += 1
	assert_eq(posen, 2)
	var letzte: Dictionary = rig.link().last_sent("MG_POSE")["d"]
	assert_eq(letzte["room"], ROOM)
	assert_eq(int(letzte["poseSeq"]), 2, "poseSeq zählt monoton")
	assert_true(bool(letzte["jump"]))
	await _cleanup(rig, service)


func test_peer_pose_und_reaktionen_als_signale() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig)
	var posen: Array = []
	var reaktionen: Array = []
	service.peer_pose.connect(func(code: String, d: Dictionary) -> void: posen.append([code, d]))
	service.reaction_received.connect(
		func(kind: String, from: String, body: Dictionary) -> void:
			reaktionen.append([kind, from, body])
	)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MG_PEER_POSE",
				"ts": 0,
				"d": {"room": ROOM, "from": PEER, "p": [1.0, 0.0, 2.0], "gait": 2, "poseSeq": 1},
			}
		)
	)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": ROOM, "from": PEER, "kind": "HERZ", "body": {}},
			}
		)
	)
	# Fremder Raum wird ignoriert.
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MG_PEER_POSE",
				"ts": 0,
				"d": {"room": "mg:fremd", "from": PEER, "p": [9.0, 9.0, 9.0], "poseSeq": 2},
			}
		)
	)
	await wait_frames(3)
	assert_eq(posen.size(), 1)
	assert_eq(posen[0][0], PEER)
	assert_eq(reaktionen.size(), 1)
	assert_eq(reaktionen[0][0], "HERZ")
	assert_true(service.send_reaction("GESTE", {"id": "streicheln"}))
	assert_eq(rig.link().last_sent("ROOM_MSG")["d"]["kind"], "GESTE")
	assert_false(service.send_reaction("HACK", {}), "nur erlaubte Reaktions-Kinds")
	await _cleanup(rig, service)


func test_mg_start_synct_serverzeit() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig)
	var starts: Array = []
	service.match_started.connect(func(d: Dictionary) -> void: starts.append(d))
	var jetzt := int(Time.get_unix_time_from_system() * 1000.0)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MG_START",
				"ts": 0,
				"d":
				{
					"room": ROOM,
					"mode": "rennen",
					"kurs": "grasbahn",
					"seed": 7,
					"startAt": jetzt + 99_000,
					"serverNow": jetzt + 95_000,
					"players": [],
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(starts.size(), 1)
	assert_eq(service.phase, "countdown")
	assert_eq(service.seed, 7)
	var countdown := service.countdown_ms()
	assert_true(countdown > 3_000 and countdown < 4_500, "Offset-Sync: ~4 s, got %d" % countdown)
	await _cleanup(rig, service)


func test_result_ack_idempotent_und_pending_aus_welcome() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	var results: Array = []
	service.result_received.connect(func(d: Dictionary) -> void: results.append(d))
	var gs := FakeGs.new()
	var result := {
		"rewardId": "rmp-x-ME",
		"mode": "rennen",
		"kurs": "grasbahn",
		"rank": 1,
		"zeitMs": 61_000,
		"ranked": true,
		"dnf": false,
		"room": ROOM,
	}
	rig.link().push_server({"v": 1, "t": "MG_RESULT", "ts": 0, "d": result})
	await wait_frames(2)
	assert_eq(results.size(), 1)
	service.ack_result(result, gs)
	assert_eq(rig.link().last_sent("MG_RESULT_ACK")["d"]["rewardId"], "rmp-x-ME")
	assert_eq(RmpState.statistik(gs, "rennen"), {"teilnahmen": 1, "siege": 1})
	service.ack_result(result, gs)
	assert_eq(
		RmpState.statistik(gs, "rennen"),
		{"teilnahmen": 1, "siege": 1},
		"doppelter ACK zählt nicht doppelt"
	)
	# Unbestätigte Ergebnisse kommen beim nächsten WELCOME als Pending.
	rig.client._on_welcome({"friendCode": rig.client.friend_code, "rmpPending": [result]})
	await wait_frames(1)
	assert_eq(service.pending_results.size(), 1)
	assert_eq(results.size(), 2, "Pending wird erneut signalisiert")
	await _cleanup(rig, service)


func test_resume_holt_snapshot() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	var snapshots: Array = []
	service.snapshot_received.connect(func(d: Dictionary) -> void: snapshots.append(d))
	var results: Array = []
	_collect(func() -> Dictionary: return await service.resume(ROOM), results)
	await wait_frames(1)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)
	(
		rig
		. link()
		. respond_to(
			"MG_RESUME",
			"MG_SNAPSHOT",
			{
				"room": ROOM,
				"mode": "rennen",
				"kurs": "grasbahn",
				"phase": "run",
				"startAt": 1000,
				"serverNow": 2000,
				"players": [{"friendCode": PEER, "name": "Mia"}],
				"progress": {PEER: 3},
			}
		)
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	assert_eq(snapshots.size(), 1)
	assert_eq(service.phase, "run")
	assert_eq(service.kurs, "grasbahn")
	await _cleanup(rig, service)


func test_revanche_und_ranch_ended() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig)
	var waits: Array = []
	var ended: Array = []
	service.rematch_wait.connect(func(d: Dictionary) -> void: waits.append(d))
	service.session_ended.connect(func(d: Dictionary) -> void: ended.append(d))
	rig.link().push_server(
		{"v": 1, "t": "RMP_REMATCH_WAIT", "ts": 0, "d": {"room": ROOM, "friendCode": PEER}}
	)
	await wait_frames(2)
	assert_eq(waits.size(), 1)
	# Frische Revanche-Session ersetzt den Raum (RANCH_READY mit neuem Room).
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "RANCH_READY",
				"ts": 0,
				"d":
				{
					"room": "mg:test-2",
					"mode": "rennen",
					"kurs": "grasbahn",
					"host": PEER,
					"players": [],
					"rematch": true,
				},
			}
		)
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)
	assert_eq(service.room_id, "mg:test-2")
	assert_eq(service.phase, "lobby")
	rig.link().push_server(
		{"v": 1, "t": "RANCH_ENDED", "ts": 0, "d": {"room": "mg:test-2", "by": PEER}}
	)
	await wait_frames(2)
	assert_eq(ended.size(), 1)
	assert_false(service.is_active(), "Reset nach RANCH_ENDED")
	await _cleanup(rig, service)


func test_fehler_texte_deutsch() -> void:
	assert_eq(
		RanchMultiplayerService.fehler_text("ROOM_FULL"), I18nService.t("ranch_mp.fehler.room_full")
	)
	var unbekannt := RanchMultiplayerService.fehler_text("XYZ_42")
	assert_true(unbekannt.contains("XYZ_42"), "unbekannte Codes bleiben sichtbar")


func _make_service(rig: NetTestRig) -> RanchMultiplayerService:
	var service := RanchMultiplayerService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	return service


## RANCH_READY als Push einspielen + den folgenden ROOM_JOIN beantworten.
func _push_ready(rig: NetTestRig) -> void:
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "RANCH_READY",
				"ts": 0,
				"d":
				{
					"room": ROOM,
					"mode": "rennen",
					"kurs": "grasbahn",
					"host": PEER,
					"players":
					[
						{"friendCode": PEER, "name": "Mia", "goobyName": "Flauschi"},
						{"friendCode": rig.client.friend_code, "name": "Ich", "goobyName": "Gooby"},
					],
				},
			}
		)
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, service: RanchMultiplayerService) -> void:
	service.queue_free()
	await rig.shutdown(tree)


class FakeGs:
	var daten: Dictionary = {}

	func get_value(key: String, fallback: Variant = null) -> Variant:
		return daten.get(key, fallback)

	func set_value(key: String, value: Variant) -> void:
		daten[key] = value
