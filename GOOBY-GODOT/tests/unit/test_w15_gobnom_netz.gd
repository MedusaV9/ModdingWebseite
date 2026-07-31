extends TestCase
## W15 GOB-NOM-Netz-Coop (Doc C §3.8 / Doc G §5.4 M2): Lockstep-Kern mit
## ZWEI Sim-Instanzen (Handshake → Server-Seed → Input-Relay → identischer
## State-Hash), Input-Delay-Fenster, Desync-Wächter (höflicher Abbruch),
## Rejoin-Replay aus dem Frame-Puffer und das „nur online + Freund“-Gate.
## Session-Protokoll (GobnomNetSession) läuft über das FakeLink-Rig — exakt
## die Pushes/Antworten, die gobnommp.js serverseitig produziert.

const ROOM := "gobnom:test-w15-1234"


func _balance() -> Dictionary:
	return GobnomData.load_balance(null)


## Coop-Level wie in test_gobnom_logic: Split bei x=480, Seil 0 gehört a
## (links), Seil 1 gehört b (rechts) — beide halten das Bonbon.
func _coop_level() -> Dictionary:
	return {
		"id": 1,
		"kind": "coop",
		"split": {"axis": "x", "at": 480},
		"candy": {"x": 480, "y": 200},
		"mouth": {"x": 480, "y": 470},
		"ropes":
		[
			{"x": 200, "y": 120, "rest": 80, "owner": "a"},
			{"x": 700, "y": 120, "rest": 80, "owner": "b"},
		],
		"jars": [{"x": 480, "y": 300}, {"x": 480, "y": 360}, {"x": 480, "y": 420}],
	}


## Beide Sims einen Wand-Tick weiterdrehen und fällige Frames/Hashes
## kreuzweise zustellen (das „Netz“ des Tests — verlustfrei, in Ordnung).
## `frames` sammelt optional die komplette Historie (Rejoin-Puffer des
## Servers), `hash_by_tick` die Hash-Spur von Sim a fürs Replay-Urteil.
func _pump(
	sim_a: GobnomLockstep, sim_b: GobnomLockstep, wall_ticks: int, frames := {}, hash_by_tick := {}
) -> void:
	for _i in wall_ticks:
		var res_a := sim_a.advance()
		if bool(res_a["stepped"]):
			hash_by_tick[int(sim_a.state["tick"])] = GobnomLogic.state_hash(sim_a.state)
		sim_b.advance()
		var frame_a := sim_a.take_frame()
		if not frame_a.is_empty():
			if frames.has("a"):
				(frames["a"] as Array).append(frame_a.duplicate(true))
			sim_b.receive_frame(frame_a)
		var frame_b := sim_b.take_frame()
		if not frame_b.is_empty():
			if frames.has("b"):
				(frames["b"] as Array).append(frame_b.duplicate(true))
			sim_a.receive_frame(frame_b)
		for entry: Dictionary in sim_a.take_hashes():
			sim_b.receive_hash(int(entry["t"]), str(entry["h"]))
		for entry: Dictionary in sim_b.take_hashes():
			sim_a.receive_hash(int(entry["t"]), str(entry["h"]))


func _rope_cut(sim: GobnomLockstep, rope_id: int) -> bool:
	return bool(((sim.state["ropes"] as Array)[rope_id] as Dictionary)["cut"])


## ── Lockstep: zwei Sims, ein Input-Strom ─────────────────────────────────


func test_zwei_sims_identischer_hash_nach_input_relay() -> void:
	var seed_vom_server := 987_654_321
	var sim_a := GobnomLockstep.new()
	var sim_b := GobnomLockstep.new()
	sim_a.start(_coop_level(), _balance(), seed_vom_server, GobnomLogic.PLAYER_A)
	sim_b.start(_coop_level(), _balance(), seed_vom_server, GobnomLogic.PLAYER_B)
	# Start-Fence wie im Spiel: erster Frame sofort raus (take_frame(true)).
	sim_b.receive_frame(sim_a.take_frame(true))
	sim_a.receive_frame(sim_b.take_frame(true))

	_pump(sim_a, sim_b, 10)
	# a schneidet SEIN Seil, b später seins — beides reist als Input-Frame.
	sim_a.schedule("cut", 0)
	_pump(sim_a, sim_b, 40)
	sim_b.schedule("cut", 1)
	# Weit über Tick 60 hinaus: mindestens ein Hash-Austausch passiert.
	_pump(sim_a, sim_b, 100)

	assert_true(int(sim_a.state["tick"]) > 60, "Sims müssen echt gelaufen sein")
	assert_eq(int(sim_a.state["tick"]), int(sim_b.state["tick"]), "gleicher Tick")
	assert_eq(
		GobnomLogic.state_hash(sim_a.state),
		GobnomLogic.state_hash(sim_b.state),
		"identischer State-Hash nach Relay beider Input-Ströme"
	)
	assert_true(_rope_cut(sim_a, 0) and _rope_cut(sim_b, 0), "a-Schnitt auf BEIDEN Sims")
	assert_true(_rope_cut(sim_a, 1) and _rope_cut(sim_b, 1), "b-Schnitt auf BEIDEN Sims")
	assert_false(sim_a.desynced or sim_b.desynced, "Hash-Wächter blieb still")


func test_input_delay_fenster() -> void:
	var sim := GobnomLockstep.new()
	sim.start(_coop_level(), _balance(), 7, GobnomLogic.PLAYER_A)
	# Ohne Partner-Fence rechnet die Sim keinen einzigen Tick (Lockstep!).
	assert_false(bool(sim.advance()["stepped"]), "ohne Fence kein Schritt")
	assert_eq(int(sim.state["tick"]), 0)

	var sim2 := GobnomLockstep.new()
	sim2.start(_coop_level(), _balance(), 7, GobnomLogic.PLAYER_A)
	var action := sim2.schedule("cut", 0)
	var t := int(action["t"])
	assert_eq(t, sim2.input_delay, "frische Sim: Aktion läuft bei Tick 0 + Delay")
	assert_true(t >= 3 and t <= 5, "Delay-Fenster 3–5 Ticks (C §3.8)")
	sim2.receive_frame({"n": 1, "upTo": 100_000, "a": []})
	while int(sim2.state["tick"]) < t:
		assert_false(_rope_cut(sim2, 0), "VOR dem geplanten Tick bleibt das Seil ganz")
		sim2.advance()
	assert_false(_rope_cut(sim2, 0), "bei Tick t ist die Aktion noch nicht dran")
	sim2.advance()
	assert_true(_rope_cut(sim2, 0), "IM Tick t wird geschnitten — auf beiden Geräten")


func test_desync_abbruch_statt_weiterspielen() -> void:
	var sim := GobnomLockstep.new()
	sim.start(_coop_level(), _balance(), 11, GobnomLogic.PLAYER_A)
	sim.receive_frame({"n": 1, "upTo": 100_000, "a": []})
	while int(sim.state["tick"]) <= GobnomLockstep.HASH_TICKS:
		sim.advance()
	assert_false(GobnomLogic.is_over(sim.state), "Testlevel darf nicht vorzeitig enden")
	var reports := sim.take_hashes()
	assert_eq(reports.size(), 1, "genau ein Hash-Report bei Tick 60")
	assert_eq(int((reports[0] as Dictionary)["t"]), GobnomLockstep.HASH_TICKS)

	# Partner meldet für denselben Tick einen ANDEREN Hash → Desync-Flag.
	sim.receive_hash(GobnomLockstep.HASH_TICKS, "kaputt-vom-anderen-stern")
	assert_true(sim.desynced, "Hash-Abweichung setzt desynced")
	assert_eq(sim.desync_tick, GobnomLockstep.HASH_TICKS)
	assert_false(bool(sim.advance()["stepped"]), "nach Desync rechnet nichts mehr")

	# Umgekehrte Ankunftsordnung: Partner-Hash liegt VOR dem eigenen Tick.
	var sim2 := GobnomLockstep.new()
	sim2.start(_coop_level(), _balance(), 11, GobnomLogic.PLAYER_B)
	sim2.receive_frame({"n": 1, "upTo": 100_000, "a": []})
	sim2.receive_hash(GobnomLockstep.HASH_TICKS, "falsch")
	while not sim2.desynced and int(sim2.state["tick"]) <= GobnomLockstep.HASH_TICKS + 1:
		sim2.advance()
	assert_true(sim2.desynced, "auch früh eingetroffene Fremd-Hashes zünden den Wächter")


func test_rejoin_replay_aus_frame_puffer() -> void:
	var seed_vom_server := 424_242
	var sim_a := GobnomLockstep.new()
	var sim_b := GobnomLockstep.new()
	sim_a.start(_coop_level(), _balance(), seed_vom_server, GobnomLogic.PLAYER_A)
	sim_b.start(_coop_level(), _balance(), seed_vom_server, GobnomLogic.PLAYER_B)
	# Der „Server-Puffer“: ALLE Frames beider Seiten in Sende-Reihenfolge.
	var frames := {"a": [], "b": []}
	var hash_by_tick := {}
	var start_a := sim_a.take_frame(true)
	(frames["a"] as Array).append(start_a.duplicate(true))
	sim_b.receive_frame(start_a)
	var start_b := sim_b.take_frame(true)
	(frames["b"] as Array).append(start_b.duplicate(true))
	sim_a.receive_frame(start_b)
	_pump(sim_a, sim_b, 10, frames, hash_by_tick)
	sim_a.schedule("cut", 0)
	_pump(sim_a, sim_b, 60, frames, hash_by_tick)
	# Live-Sim a bis an ihren Fence auslaufen lassen: das Replay darf bis
	# min(beider Fences) vorspulen — die Hash-Spur muss so weit reichen.
	var drain := sim_a.advance()
	while bool(drain["stepped"]):
		hash_by_tick[int(sim_a.state["tick"])] = GobnomLogic.state_hash(sim_a.state)
		drain = sim_a.advance()

	# b's Gerät stürzt ab → neue Sim, GOBNOM_SNAPSHOT liefert frames.
	var rejoined := GobnomLockstep.new()
	rejoined.resume(_coop_level(), _balance(), seed_vom_server, GobnomLogic.PLAYER_B, frames)
	var replay_tick := int(rejoined.state["tick"])
	assert_true(replay_tick > 20, "Replay muss echt vorspulen (Tick %d)" % replay_tick)
	assert_true(_rope_cut(rejoined, 0), "der a-Schnitt aus der Historie ist nachgespielt")
	assert_true(hash_by_tick.has(replay_tick), "Vergleichs-Hash der Live-Sim liegt vor")
	assert_eq(
		GobnomLogic.state_hash(rejoined.state),
		int(hash_by_tick[replay_tick]),
		"Rejoin-Replay landet exakt auf dem Live-Zustand von Tick %d" % replay_tick
	)
	assert_false(rejoined.desynced)


## ── Gate: „Mit Freund spielen“ nur online + Freund online ────────────────


func test_gate_nur_online_und_freund() -> void:
	assert_eq(GobnomNetzPanel.gate_key(false, 0), "gobnom.netz.offline")
	assert_eq(GobnomNetzPanel.gate_key(false, 3), "gobnom.netz.offline", "offline schlägt alles")
	assert_eq(GobnomNetzPanel.gate_key(true, 0), "gobnom.netz.keine_freunde")
	assert_eq(GobnomNetzPanel.gate_key(true, 1), "", "online + Freund online = spielbereit")

	# Offline-Session: keine Freunde, kein Invite — Hot-Seat bleibt der Weg.
	var session := GobnomNetSession.new()
	assert_false(session.is_online())
	assert_eq(session.online_friends().size(), 0)
	var res: Dictionary = await session.invite("GOOBY-HOST")
	assert_false(bool(res["ok"]))
	assert_eq(str(res["code"]), "OFFLINE")
	session.free()


## ── Session-Protokoll über FakeLink (Pushes exakt wie gobnommp.js) ────────


func _ready_payload() -> Dictionary:
	return {
		"room": ROOM,
		"players":
		[
			{"friendCode": "GOOBY-HOST", "side": "a", "name": "Timo", "goobyName": "Flauschi"},
			{"friendCode": "GOOBY-TEST", "side": "b", "name": "Ich", "goobyName": "Gooby"},
		],
		"inputDelay": 4,
		"hashEveryTicks": 60,
		"rejoinMs": 120_000,
	}


func _push(rig: NetTestRig, type: String, data: Dictionary) -> void:
	rig.link().push_server({"v": 1, "t": type, "ts": 0, "d": data})


func _accept_async(session: GobnomNetSession, from: String, out: Array) -> void:
	out.append(await session.accept(from))


func _level_async(session: GobnomNetSession, level: int, out: Array) -> void:
	out.append(await session.choose_level(level))


func test_session_handshake_und_start_seed() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := GobnomNetSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)

	# Einladung trifft ein (Freunde-Flow, Battleship-Muster).
	var invites: Array = []
	session.invite_incoming.connect(func(d: Dictionary) -> void: invites.append(d))
	_push(
		rig,
		"GOBNOM_INVITED",
		{"from": "GOOBY-HOST", "name": "Timo", "goobyName": "Flauschi", "expiresInMs": 30000}
	)
	assert_true(await wait_until(func() -> bool: return invites.size() == 1, 3000))
	assert_eq(str((invites[0] as Dictionary)["from"]), "GOOBY-HOST")

	# Annehmen → GOBNOM_READY → Session tritt dem Raum bei (ROOM_JOIN).
	var ready_events: Array = []
	session.session_ready.connect(func(d: Dictionary) -> void: ready_events.append(d))
	var accept_out: Array = []
	_accept_async(session, "GOOBY-HOST", accept_out)
	await wait_frames(2)
	assert_false(rig.link().last_sent("GOBNOM_ACCEPT").is_empty())
	rig.link().respond_to("GOBNOM_ACCEPT", "GOBNOM_READY", _ready_payload())
	var joined := await wait_until(
		func() -> bool: return not rig.link().last_sent("ROOM_JOIN").is_empty(), 3000
	)
	assert_true(joined, "nach GOBNOM_READY folgt der Raum-Beitritt")
	rig.link().respond_to("ROOM_JOIN", "OK", {"room": ROOM})
	assert_true(await wait_until(func() -> bool: return accept_out.size() == 1, 5000))
	assert_true(await wait_until(func() -> bool: return ready_events.size() == 1, 3000))
	assert_true(session.is_paired())
	assert_eq(session.my_side, "b", "der Annehmende spielt Seite b")
	assert_eq(session.partner_code, "GOOBY-HOST")
	assert_eq(session.partner_gooby_name, "Flauschi")

	# Level-Handshake: eigene Wahl geht raus, Partner-Vote kommt als Push.
	var votes_seen: Array = []
	session.level_votes_changed.connect(func(v: Dictionary) -> void: votes_seen.append(v))
	var level_out: Array = []
	_level_async(session, 3, level_out)
	await wait_frames(2)
	var level_req := rig.link().last_sent("GOBNOM_LEVEL")
	assert_eq(int((level_req["d"] as Dictionary)["level"]), 3)
	assert_eq(str((level_req["d"] as Dictionary)["room"]), ROOM)
	rig.link().respond_to("GOBNOM_LEVEL", "OK", {"level": 3, "votes": {"GOOBY-TEST": 3}})
	_push(rig, "GOBNOM_LEVEL_STATE", {"room": ROOM, "votes": {"GOOBY-HOST": 3, "GOOBY-TEST": 3}})
	assert_true(await wait_until(func() -> bool: return votes_seen.size() == 1, 3000))

	# Beide einig → Server startet mit SEINEM Seed.
	var starts: Array = []
	session.game_started.connect(func(d: Dictionary) -> void: starts.append(d))
	var start_data := _ready_payload()
	start_data["level"] = 3
	start_data["seed"] = 123_456_789
	start_data["serverNow"] = 1000
	_push(rig, "GOBNOM_START", start_data)
	assert_true(await wait_until(func() -> bool: return starts.size() == 1, 3000))
	assert_true(session.is_running())
	assert_eq(session.level, 3)
	assert_eq(session.seed_value, 123_456_789, "Start-Seed kommt VOM SERVER")
	assert_eq(session.input_delay, 4)
	assert_eq(session.hash_every_ticks, 60)

	session.queue_free()
	await rig.shutdown(tree)


func test_session_relay_ergebnis_und_abbruch() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := GobnomNetSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)

	# Der Einladende bekommt GOBNOM_READY als Push (kein re) → auto-Join.
	var payload := _ready_payload()
	payload["players"] = [
		{"friendCode": "GOOBY-TEST", "side": "a", "name": "Ich", "goobyName": "Gooby"},
		{"friendCode": "GOOBY-GAST", "side": "b", "name": "Timo", "goobyName": "Flauschi"},
	]
	_push(rig, "GOBNOM_READY", payload)
	var joined := await wait_until(
		func() -> bool: return not rig.link().last_sent("ROOM_JOIN").is_empty(), 3000
	)
	assert_true(joined)
	rig.link().respond_to("ROOM_JOIN", "OK", {"room": ROOM})
	assert_true(await wait_until(func() -> bool: return session.is_paired(), 3000))
	assert_eq(session.my_side, "a", "der Einladende spielt Seite a")
	var start_data := payload.duplicate(true)
	start_data["level"] = 1
	start_data["seed"] = 77
	_push(rig, "GOBNOM_START", start_data)
	assert_true(await wait_until(func() -> bool: return session.is_running(), 3000))

	# Eigener Frame geht als ROOM_MSG/GN_INPUT raus …
	session.send_frame({"n": 1, "upTo": 3, "a": [{"t": 4, "do": "cut", "id": 0}]})
	await wait_frames(1)
	var sent := rig.link().last_sent("ROOM_MSG")
	assert_eq(str((sent["d"] as Dictionary)["kind"]), "GN_INPUT")
	assert_eq(str((sent["d"] as Dictionary)["room"]), ROOM)

	# … Partner-Frames/Cursor kommen als ROOM_MSG-Push rein.
	var frames: Array = []
	session.frame_received.connect(func(b: Dictionary) -> void: frames.append(b))
	var cursors: Array = []
	session.cursor_received.connect(func(p: Vector2) -> void: cursors.append(p))
	_push(
		rig,
		"ROOM_MSG",
		{
			"room": ROOM,
			"from": "GOOBY-GAST",
			"kind": "GN_INPUT",
			"body": {"n": 1, "upTo": 9, "a": [{"t": 5, "do": "pop", "id": 0}]},
		}
	)
	_push(
		rig,
		"ROOM_MSG",
		{"room": ROOM, "from": "GOOBY-GAST", "kind": "GN_CURSOR", "body": {"x": 640, "y": 260}}
	)
	assert_true(await wait_until(func() -> bool: return frames.size() == 1, 3000))
	assert_eq(int((frames[0] as Dictionary)["n"]), 1)
	assert_true(await wait_until(func() -> bool: return cursors.size() == 1, 3000))
	assert_eq(cursors[0], Vector2(640, 260))

	# Ergebnis-Push wird bestätigt (idempotent per rewardId) und geACKt.
	var results: Array = []
	session.result_confirmed.connect(func(d: Dictionary) -> void: results.append(d))
	_push(
		rig,
		"GOBNOM_RESULT",
		{
			"room": ROOM,
			"rewardId": "gnom-test-w15-GOOBY-TEST",
			"outcome": "won",
			"jars": 3,
			"stars": 3,
			"level": 1,
			"tick": 480,
		}
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var acked := await wait_until(
		func() -> bool: return not rig.link().last_sent("GOBNOM_RESULT_ACK").is_empty(), 3000
	)
	assert_true(acked, "Ergebnis wird automatisch geACKt")
	var ack := rig.link().last_sent("GOBNOM_RESULT_ACK")
	assert_eq(str((ack["d"] as Dictionary)["rewardId"]), "gnom-test-w15-GOOBY-TEST")
	assert_false(session.is_running(), "nach dem Ergebnis läuft nichts mehr")

	# Desync- und Abbruch-Pushes: höflich raus statt weiterspielen.
	var desyncs: Array = []
	session.desync_reported.connect(func(t: int) -> void: desyncs.append(t))
	_push(rig, "GOBNOM_DESYNC", {"room": ROOM, "tick": 120})
	assert_true(await wait_until(func() -> bool: return desyncs.size() == 1, 3000))
	assert_eq(int(desyncs[0]), 120)
	var aborts: Array = []
	session.session_aborted.connect(func(r: String, b: String) -> void: aborts.append([r, b]))
	_push(rig, "GOBNOM_ABORTED", {"room": ROOM, "reason": "left", "by": "GOOBY-GAST"})
	assert_true(await wait_until(func() -> bool: return aborts.size() == 1, 3000))
	assert_false(session.is_paired(), "Abbruch räumt die Session — Panel wieder frei")

	session.queue_free()
	await rig.shutdown(tree)
