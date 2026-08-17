extends TestCase
## G5/P26 GvZ-Netz-PvP (Doc G §4.5, Vorlage test_w15_gobnom_netz): Lockstep-
## Kern mit ZWEI Sim-Instanzen (Server-Seed → Input-Relay → identischer
## state_hash), Input-Delay-Fenster + Seiten-Gate, Matsch-Ökonomie mit
## Spawn-Gates, Desync-Wächter, Sieg über Timer UND Haus-Durchbruch,
## „nur online + Freund“-Gate, Panel-Mount headless, Session-Protokoll
## über das FakeLink-Rig und der komplette View-Flow (GVZ_READY → START →
## Fence → Sim tickt). Plus HUD-Split-Regression (gvz_game.gd < 1000).

const ROOM := "gvz:test-p26-1234"
const GAME_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"


class GameStateDouble:
	extends RefCounted
	var state := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func _balance() -> Dictionary:
	return GvzData.load_balance(null)


func _pvp() -> Dictionary:
	return GvzPvpLockstep.load_pvp()


## Beide Sims einen Wand-Tick weiterdrehen und fällige Frames/Hashes
## kreuzweise zustellen (das „Netz“ des Tests — verlustfrei, in Ordnung).
func _pump(sim_a: GvzPvpLockstep, sim_b: GvzPvpLockstep, wall_ticks: int) -> void:
	for _i in wall_ticks:
		sim_a.advance()
		sim_b.advance()
		var frame_a := sim_a.take_frame()
		if not frame_a.is_empty():
			sim_b.receive_frame(frame_a)
		var frame_b := sim_b.take_frame()
		if not frame_b.is_empty():
			sim_a.receive_frame(frame_b)
		for entry: Dictionary in sim_a.take_hashes():
			sim_b.receive_hash(int(entry["t"]), str(entry["h"]))
		for entry: Dictionary in sim_b.take_hashes():
			sim_a.receive_hash(int(entry["t"]), str(entry["h"]))


## Sim mit offenem Partner-Fence (Solo-Betrieb für Gate-/Timer-Tests).
func _solo(side: String, seed_value := 7) -> GvzPvpLockstep:
	var sim := GvzPvpLockstep.new()
	sim.start(_balance(), _pvp(), seed_value, side)
	sim.receive_frame({"n": 1, "upTo": 1_000_000, "a": []})
	return sim


func _zombie_count(sim: GvzPvpLockstep) -> int:
	var count := 0
	for zombie: Dictionary in sim.state["zombies"]:
		if not bool(zombie["dead"]):
			count += 1
	return count


## ── Lockstep: zwei Sims, ein Input-Strom ─────────────────────────────────


func test_zwei_sims_identischer_hash_nach_input_relay() -> void:
	var seed_vom_server := 987_654_321
	var sim_a := GvzPvpLockstep.new()
	var sim_b := GvzPvpLockstep.new()
	sim_a.start(_balance(), _pvp(), seed_vom_server, GvzPvpLockstep.SIDE_GOOBY)
	sim_b.start(_balance(), _pvp(), seed_vom_server, GvzPvpLockstep.SIDE_ZOMBIE)
	# Start-Fence wie im Spiel: erster Frame sofort raus (take_frame(true)).
	sim_b.receive_frame(sim_a.take_frame(true))
	sim_a.receive_frame(sim_b.take_frame(true))

	_pump(sim_a, sim_b, 10)
	# Gooby pflanzt eine Schnarch-Knolle (25 ≤ 50 Start-Nutella) — reist als Frame zu b.
	sim_a.schedule_place("schnarch_knolle", 2, 1)
	_pump(sim_a, sim_b, 40)
	# Zombie-Seite: nach 2 Tropf-Intervallen reicht der Matsch für Schlurfi.
	var drip_ticks := 10 * 20 * 2 + 20
	_pump(sim_a, sim_b, drip_ticks)
	assert_true(bool(sim_b.can_spawn("schlurfi", 2)["ok"]), "Matsch getropft → Spawn frei")
	sim_b.schedule_spawn("schlurfi", 2)
	_pump(sim_a, sim_b, 100)

	assert_true(int(sim_a.state["tick"]) > 120, "Sims müssen echt gelaufen sein")
	assert_eq(int(sim_a.state["tick"]), int(sim_b.state["tick"]), "gleicher Tick")
	assert_eq(
		sim_a.state_hash_text(),
		sim_b.state_hash_text(),
		"identischer Drift-Hash (Sim + Matsch/Cooldowns) nach Relay"
	)
	assert_eq((sim_a.state["towers"] as Dictionary).size(), 1, "Knolle steht auf Sim a")
	assert_eq((sim_b.state["towers"] as Dictionary).size(), 1, "Knolle steht auf Sim b")
	assert_true(_zombie_count(sim_a) >= 1, "beschworener Schlurfi läuft auf Sim a")
	assert_true(_zombie_count(sim_b) >= 1, "beschworener Schlurfi läuft auf Sim b")
	assert_eq(sim_a.matsch, sim_b.matsch, "Matsch-Konto identisch")
	assert_false(sim_a.desynced or sim_b.desynced, "Hash-Wächter blieb still")


func test_input_delay_fenster_und_seiten_gate() -> void:
	var sim := GvzPvpLockstep.new()
	sim.start(_balance(), _pvp(), 7, GvzPvpLockstep.SIDE_GOOBY)
	# Ohne Partner-Fence rechnet die Sim keinen einzigen Tick (Lockstep!).
	assert_false(bool(sim.advance()["stepped"]), "ohne Fence kein Schritt")
	assert_eq(int(sim.state["tick"]), 0)

	var sim2 := _solo(GvzPvpLockstep.SIDE_GOOBY)
	var action := sim2.schedule_place("schnarch_knolle", 1, 0)
	var t := int(action["t"])
	assert_eq(t, sim2.input_delay, "frische Sim: Aktion läuft bei Tick 0 + Delay")
	assert_true(t >= 3 and t <= 5, "Delay-Fenster 3–5 Ticks (C §3.8)")
	while int(sim2.state["tick"]) < t:
		assert_eq((sim2.state["towers"] as Dictionary).size(), 0, "VOR Tick t steht nichts")
		sim2.advance()
	sim2.advance()
	assert_eq((sim2.state["towers"] as Dictionary).size(), 1, "IM Tick t wird gepflanzt")

	# Seiten-Gate: eine „spawn“-Aktion der GOOBY-Seite wird still verworfen —
	# nur die Zombie-Seite darf beschwören (deterministisch auf beiden Sims).
	var sim3 := _solo(GvzPvpLockstep.SIDE_ZOMBIE)
	sim3.matsch = 1000
	sim3.receive_frame(
		{"n": 2, "upTo": 1_000_000, "a": [{"t": 6, "do": "spawn", "type": "schlurfi", "lane": 0}]}
	)
	for _i in 12:
		sim3.advance()
	assert_eq(_zombie_count(sim3), 0, "Gooby-seitiger spawn wird im Dispatch verworfen")


## ── Matsch-Ökonomie + Spawn-Gates (Doc G §4.5, gvz_pvp.json) ──────────────


func test_matsch_oekonomie_und_spawn_gates() -> void:
	var sim := _solo(GvzPvpLockstep.SIDE_ZOMBIE)
	var rules: Dictionary = _pvp()
	assert_eq(sim.matsch, int(rules["matsch"]["start"]), "Start-Matsch aus den Daten")
	assert_eq(str(sim.can_spawn("schlurfi", 2)["reason"]), "matsch", "ohne Matsch kein Spawn")
	assert_eq(str(sim.can_spawn("ufo", 2)["reason"]), "unknown_zombie")
	assert_eq(str(sim.can_spawn("schlurfi", 9)["reason"]), "lane")

	# Tropf: 15 alle 10 s (20 Hz) — nach 2 Intervallen reichen 30 für Kosten 25.
	var tps := 20
	var interval := int(rules["matsch"]["drip_interval_sec"]) * tps
	for _i in interval:
		sim.advance()
	assert_eq(sim.matsch, int(rules["matsch"]["drip_amount"]), "1. Tropf gebucht")
	for _i in interval:
		sim.advance()
	assert_true(bool(sim.can_spawn("schlurfi", 2)["ok"]), "30 Matsch ≥ 25 Kosten")

	var before := sim.matsch
	sim.schedule_spawn("schlurfi", 2)
	for _i in sim.input_delay + 2:
		sim.advance()
	assert_eq(_zombie_count(sim), 1, "Schlurfi beschworen")
	assert_eq(sim.matsch, before - sim.zombie_cost("schlurfi"), "Kosten abgebucht")
	assert_eq(str(sim.can_spawn("schlurfi", 2)["reason"]), "cooldown", "Cooldown greift")
	assert_true(sim.zombie_cooldown_left("schlurfi") > 0)

	# Mäher sind im PvP aus (mowers_enabled=false → als verbraucht markiert).
	for lane: Variant in sim.state["mowers"]:
		assert_true(bool(sim.state["mowers"][lane]["used"]), "PvP ohne Dampfwalzen")


## ── Desync-Wächter ────────────────────────────────────────────────────────


func test_drift_erkennung_meldet() -> void:
	var sim := _solo(GvzPvpLockstep.SIDE_GOOBY, 11)
	while int(sim.state["tick"]) <= GvzPvpLockstep.HASH_TICKS:
		sim.advance()
	var reports := sim.take_hashes()
	assert_eq(reports.size(), 1, "genau ein Hash-Report bei Tick 60")
	assert_eq(int((reports[0] as Dictionary)["t"]), GvzPvpLockstep.HASH_TICKS)

	# Partner meldet für denselben Tick einen ANDEREN Hash → Desync-Flag.
	sim.receive_hash(GvzPvpLockstep.HASH_TICKS, "kaputt-vom-anderen-stern")
	assert_true(sim.desynced, "Hash-Abweichung setzt desynced")
	assert_eq(sim.desync_tick, GvzPvpLockstep.HASH_TICKS)
	assert_false(bool(sim.advance()["stepped"]), "nach Desync rechnet nichts mehr")

	# Umgekehrte Ankunftsordnung: Partner-Hash liegt VOR dem eigenen Tick.
	var sim2 := _solo(GvzPvpLockstep.SIDE_ZOMBIE, 11)
	sim2.receive_hash(GvzPvpLockstep.HASH_TICKS, "falsch")
	while not sim2.desynced and int(sim2.state["tick"]) <= GvzPvpLockstep.HASH_TICKS + 1:
		sim2.advance()
	assert_true(sim2.desynced, "auch früh eingetroffene Fremd-Hashes zünden den Wächter")


## ── Match-Ende: Überlebens-Timer + Haus-Durchbruch ────────────────────────


func test_sieg_timer_gooby_und_durchbruch_zombie() -> void:
	var sim := _solo(GvzPvpLockstep.SIDE_GOOBY, 5)
	sim.survive_ticks = 50
	for _i in 60:
		sim.advance()
	assert_eq(sim.winner, GvzPvpLockstep.SIDE_GOOBY, "Timer abgelaufen → Gooby-Sieg")
	assert_true(sim.is_match_over())
	assert_false(bool(sim.advance()["stepped"]), "nach Matchende rechnet nichts mehr")
	assert_eq(sim.seconds_left(), 0)

	# Durchbruch: viel Matsch, keine Türme — der Schlurfi erreicht das Haus.
	var sim2 := _solo(GvzPvpLockstep.SIDE_ZOMBIE, 5)
	sim2.matsch = 10_000
	sim2.schedule_spawn("schlurfi", 0)
	sim2.schedule_spawn("sprinter", 0)
	var guard := 0
	while not sim2.is_match_over() and guard < 20_000:
		sim2.advance()
		guard += 1
	assert_true(guard < 20_000, "Durchbruch muss in endlicher Zeit passieren")
	assert_eq(sim2.winner, GvzPvpLockstep.SIDE_ZOMBIE, "Haus-Durchbruch → Zombie-Sieg")
	assert_eq(str(sim2.state["outcome"]), "lost", "Sim-Outcome trägt den Durchbruch")


## ── Gate + Panel headless ─────────────────────────────────────────────────


func test_gate_nur_online_und_freund() -> void:
	assert_eq(GvzNetzPanel.gate_key(false, 0), "gvz.netz.offline")
	assert_eq(GvzNetzPanel.gate_key(false, 3), "gvz.netz.offline", "offline schlägt alles")
	assert_eq(GvzNetzPanel.gate_key(true, 0), "gvz.netz.keine_freunde")
	assert_eq(GvzNetzPanel.gate_key(true, 1), "", "online + Freund online = spielbereit")

	# Offline-Session: keine Freunde, kein Invite — Kampagne bleibt der Weg.
	var session := GvzNetSession.new()
	assert_false(session.is_online())
	assert_eq(session.online_friends().size(), 0)
	var res: Dictionary = await session.invite("GOOBY-HOST")
	assert_false(bool(res["ok"]))
	assert_eq(str(res["code"]), "OFFLINE")
	session.free()


func test_panel_mountet_headless() -> void:
	var session := GvzNetSession.new()
	tree.root.add_child(session)
	var panel := GvzNetzPanel.new()
	panel.setup(session)
	tree.root.add_child(panel)
	await wait_frames(2)
	var status: Label = panel.get("_status")
	assert_true(status != null, "Status-Label gebaut")
	assert_eq(status.text, I18nService.t("gvz.netz.offline"), "offline-Gate im Status")
	var action: Button = panel.get("_action")
	assert_true(action.disabled, "Aktions-Knopf offline gesperrt")
	assert_true(action.custom_minimum_size.y >= AcTokens.TOUCH_FLOOR, "Knopf hält den Touch-Floor")
	panel.free()
	session.free()


## ── Session-Protokoll über FakeLink (GVZ_*-Vertrag wie gobnommp.js) ───────


func _ready_payload() -> Dictionary:
	return {
		"room": ROOM,
		"players":
		[
			{"friendCode": "GOOBY-HOST", "side": "gooby", "name": "Timo", "goobyName": "Flauschi"},
			{"friendCode": "GOOBY-TEST", "side": "zombie", "name": "Ich", "goobyName": "Gooby"},
		],
		"inputDelay": 4,
		"hashEveryTicks": 60,
	}


func _push(rig: NetTestRig, type: String, data: Dictionary) -> void:
	rig.link().push_server({"v": 1, "t": type, "ts": 0, "d": data})


func _accept_async(session: GvzNetSession, from: String, out: Array) -> void:
	out.append(await session.accept(from))


func test_session_handshake_start_und_relay() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := GvzNetSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)

	# Herausforderung trifft ein (Freunde-Flow, GOB-NOM-Muster).
	var invites: Array = []
	session.invite_incoming.connect(func(d: Dictionary) -> void: invites.append(d))
	_push(
		rig,
		"GVZ_INVITED",
		{"from": "GOOBY-HOST", "name": "Timo", "goobyName": "Flauschi", "expiresInMs": 30000}
	)
	assert_true(await wait_until(func() -> bool: return invites.size() == 1, 3000))
	assert_eq(str((invites[0] as Dictionary)["from"]), "GOOBY-HOST")

	# Annehmen → GVZ_READY → Session tritt dem Raum bei (ROOM_JOIN).
	var ready_events: Array = []
	session.session_ready.connect(func(d: Dictionary) -> void: ready_events.append(d))
	var accept_out: Array = []
	_accept_async(session, "GOOBY-HOST", accept_out)
	await wait_frames(2)
	assert_false(rig.link().last_sent("GVZ_ACCEPT").is_empty())
	rig.link().respond_to("GVZ_ACCEPT", "GVZ_READY", _ready_payload())
	var joined := await wait_until(
		func() -> bool: return not rig.link().last_sent("ROOM_JOIN").is_empty(), 3000
	)
	assert_true(joined, "nach GVZ_READY folgt der Raum-Beitritt")
	rig.link().respond_to("ROOM_JOIN", "OK", {"room": ROOM})
	assert_true(await wait_until(func() -> bool: return accept_out.size() == 1, 5000))
	assert_true(await wait_until(func() -> bool: return ready_events.size() == 1, 3000))
	assert_true(session.is_paired())
	assert_eq(session.my_side, "zombie", "Seite kommt aus dem players-Payload")
	assert_eq(session.partner_code, "GOOBY-HOST")
	assert_eq(session.partner_gooby_name, "Flauschi")

	# Start-Handshake: eigener Wunsch geht raus, Server pusht GVZ_START.
	session.request_start()
	await wait_frames(2)
	var start_req := rig.link().last_sent("GVZ_START_REQ")
	assert_eq(str((start_req["d"] as Dictionary)["room"]), ROOM)
	rig.link().respond_to("GVZ_START_REQ", "OK", {"room": ROOM})
	var starts: Array = []
	session.game_started.connect(func(d: Dictionary) -> void: starts.append(d))
	var start_data := _ready_payload()
	start_data["seed"] = 123_456_789
	_push(rig, "GVZ_START", start_data)
	assert_true(await wait_until(func() -> bool: return starts.size() == 1, 3000))
	assert_true(session.is_running())
	assert_eq(session.seed_value, 123_456_789, "Start-Seed kommt VOM SERVER")
	assert_eq(session.input_delay, 4)
	assert_eq(session.hash_every_ticks, 60)

	# Eigener Frame geht als ROOM_MSG/GP_INPUT raus …
	session.send_frame(
		{"n": 1, "upTo": 3, "a": [{"t": 4, "do": "spawn", "type": "schlurfi", "lane": 0}]}
	)
	await wait_frames(1)
	var sent := rig.link().last_sent("ROOM_MSG")
	assert_eq(str((sent["d"] as Dictionary)["kind"]), "GP_INPUT")
	assert_eq(str((sent["d"] as Dictionary)["room"]), ROOM)

	# … Partner-Frames kommen als ROOM_MSG-Push rein.
	var frames: Array = []
	session.frame_received.connect(func(b: Dictionary) -> void: frames.append(b))
	_push(
		rig,
		"ROOM_MSG",
		{
			"room": ROOM,
			"from": "GOOBY-HOST",
			"kind": "GP_INPUT",
			"body":
			{
				"n": 1,
				"upTo": 9,
				"a": [{"t": 5, "do": "place", "type": "schnarch_knolle", "lane": 1, "col": 0}]
			},
		}
	)
	assert_true(await wait_until(func() -> bool: return frames.size() == 1, 3000))
	assert_eq(int((frames[0] as Dictionary)["n"]), 1)

	# Ergebnis-Push wird bestätigt (idempotent per rewardId) und geACKt.
	var results: Array = []
	session.result_confirmed.connect(func(d: Dictionary) -> void: results.append(d))
	_push(
		rig,
		"GVZ_RESULT",
		{"room": ROOM, "rewardId": "gvz-test-p26", "winner": "zombie", "tick": 480}
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var acked := await wait_until(
		func() -> bool: return not rig.link().last_sent("GVZ_RESULT_ACK").is_empty(), 3000
	)
	assert_true(acked, "Ergebnis wird automatisch geACKt")
	assert_false(session.is_running(), "nach dem Ergebnis läuft nichts mehr")

	# Abbruch-Push: Session räumt sich — Panel wieder frei.
	var aborts: Array = []
	session.session_aborted.connect(func(r: String, b: String) -> void: aborts.append([r, b]))
	_push(rig, "GVZ_ABORTED", {"room": ROOM, "reason": "left", "by": "GOOBY-HOST"})
	assert_true(await wait_until(func() -> bool: return aborts.size() == 1, 3000))
	assert_false(session.is_paired(), "Abbruch räumt die Session")

	session.queue_free()
	await rig.shutdown(tree)


## ── View-Flow: GVZ_READY → GVZ_START → Fence → Sim tickt ─────────────────


func test_view_netz_flow_headless() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", GameStateDouble.new())
	game.set("net_override", rig.client)
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()

	# Der Einladende bekommt GVZ_READY als Push → auto-Join, Panel gepaart.
	var payload := _ready_payload()
	payload["players"] = [
		{"friendCode": "GOOBY-TEST", "side": "zombie", "name": "Ich", "goobyName": "Gooby"},
		{"friendCode": "GOOBY-HOST", "side": "gooby", "name": "Timo", "goobyName": "Flauschi"},
	]
	_push(rig, "GVZ_READY", payload)
	var joined := await wait_until(
		func() -> bool: return not rig.link().last_sent("ROOM_JOIN").is_empty(), 3000
	)
	assert_true(joined)
	rig.link().respond_to("ROOM_JOIN", "OK", {"room": ROOM})
	var session: GvzNetSession = game.get("netz_session")
	assert_true(session != null, "Session hängt an der Szene (net_override)")
	assert_true(await wait_until(func() -> bool: return session.is_paired(), 3000))

	# Server startet mit SEINEM Seed → beide bauen die identische PvP-Sim.
	var start_data := payload.duplicate(true)
	start_data["seed"] = 424_242
	_push(rig, "GVZ_START", start_data)
	assert_true(await wait_until(func() -> bool: return bool(game.get("_netz_active")), 3000))
	assert_eq(str(game.get("phase")), "battle", "Netz-Start öffnet das Gefecht")
	var state: Dictionary = game.get("state")
	assert_eq(int(state["seed"]), 424_242, "Sim-Seed kommt vom Server")

	# Zombie-Seite: Karten sind Beschwör-Karten (keine Schaufel), HUD-Timer an.
	var cards: Array = game.call("_card_list")
	assert_true(cards.size() >= 5, "Zombie-Karten aus gvz_pvp.json")
	assert_false(cards.has("shovel"), "Zombie-Seite hat keine Schaufel")
	var hud_info: Dictionary = game.call("netz_hud_info")
	assert_true(bool(hud_info["active"]), "Netz-HUD aktiv")
	assert_true(int(hud_info["seconds_left"]) > 0, "Überlebens-Timer läuft")

	# Partner-Fence öffnen → die Sim rechnet echte Ticks im Lockstep.
	_push(
		rig,
		"ROOM_MSG",
		{
			"room": ROOM,
			"from": "GOOBY-HOST",
			"kind": "GP_INPUT",
			"body": {"n": 1, "upTo": 240, "a": []},
		}
	)
	await wait_frames(2)
	game.set_process(false)
	for _i in 30:
		game._process(0.05)
	assert_true(int((game.get("state") as Dictionary)["tick"]) > 0, "Lockstep-Sim tickt")

	game.free()
	await rig.shutdown(tree)


## ── HUD-Split-Regression (P26-Vorab-Entflechtung) ─────────────────────────


func test_hud_split_gvz_game_unter_limit() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/minigames/games/gvz/gvz_game.gd")
	assert_false(source.is_empty(), "gvz_game.gd lesbar")
	var line_count := source.split("\n").size()
	assert_true(line_count < 950, "gvz_game.gd deutlich unter dem 1000er-Limit (%d)" % line_count)
	assert_true(source.contains("GvzHud.new(self)"), "HUD-Split aktiv (gvz_hud.gd)")
	for helper in ["gvz_hud.gd", "gvz_overlay.gd", "gvz_stage_feed.gd"]:
		assert_true(
			ResourceLoader.exists("res://scripts/minigames/games/gvz/%s" % helper),
			"Helfer existiert: %s" % helper
		)
	# Neue Netz-Strings sind DE+EN vorhanden (Parität testet test_gvz_game).
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in [
		"gvz.netz.button",
		"gvz.netz.warte_partner",
		"gvz.netz.start_banner",
		"gvz.end.netz_win",
		"gvz.end.netz_lose",
		"gvz.hud.reason_matsch",
	]:
		assert_true(de.has(key), "DE fehlt Key: %s" % key)
		assert_true(en.has(key), "EN fehlt Key: %s" % key)
