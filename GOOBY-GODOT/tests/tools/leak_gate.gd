extends SceneTree
## W13C/B4 — Leak-Gate über ALLE registrierten Minigames (KEIN Test, gehört
## zum Fehlerjagd-Werkzeugkasten wie bughunt_walkthrough.gd): startet jedes
## spielbare Spiel regulär über den echten MinigameHost, lässt es PLAY_SEC
## laufen, beendet regulär über den Quit-Pfad (ctx-/Refund-/end()-Vertrag)
## und misst danach Waisen:
##   - Orphan-Nodes  (Performance.OBJECT_ORPHAN_NODE_COUNT — Nodes außerhalb
##     des Baums, der klassische queue_free-Vergesser),
##   - Node-Drift    (rekursive get_tree-Zählung ab root, vor/nach),
##   - ObjectDB      (OBJECT_COUNT/OBJECT_RESOURCE_COUNT — nur REPORT, kein
##     Gate: der Godot-Resource-Cache behält beim ERSTEN Laden eines Spiels
##     dessen Szenen/Texturen/Shader legitim im Speicher).
##
## GATE (hart): pro Spiel Orphan-Zuwachs == 0 UND Node-Drift == 0. Gemessen
## wird nach SETTLE_SEC + FLUSH_FRAMES Idle-Frames, damit queue_free-Flush,
## Audio-Fades (stop_loop blendet 150 ms aus) und deferred-Aufräumer durch
## sind. Ein UNGEMESSENER Warm-up-Lauf (erstes Spiel der Liste) baut vorher
## den lazy Framework-Zustand auf (Results-Overlay, Theme-/String-Caches,
## Musik-Player), damit Spiel 1 keine False-Positives sieht — das ist die
## EINZIGE einkalkulierte Toleranz, sie steht bewusst VOR der Baseline.
##
## Aufruf (siehe tools/ci/README.md):
##   bash tools/ci/run_godot_isolated.sh godot --headless --path GOOBY-GODOT \
##     --script res://tests/tools/leak_gate.gd
## Exit-Code 0 = alles dicht, 1 = mindestens ein LEAK (Zeilen "LEAK <spiel>").

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
## Sekunden Laufzeit pro Spiel (nach dem GO; Countdown steht auf 0).
const PLAY_SEC := 2.0
## Fester Seed: deterministische Runden, reproduzierbare Messwerte.
const RUN_SEED := 20260731
## Ausklingzeit nach dem Quit (Audio-Fade 150 ms, Musik-Crossfade, deferred
## queue_free-Ketten), DANN erst der Idle-Frame-Flush + die Messung.
const SETTLE_SEC := 0.5
const FLUSH_FRAMES := 4
## Timeout bis zum GO (Host: Pause-Knopf wird beim Rundenstart freigegeben).
const GO_TIMEOUT_MS := 15_000

var _gs: Node
var _leaks: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_gs = root.get_node("/root/GameState")
	_gs.initialize("user://leak_gate_%d.json" % Time.get_ticks_usec())
	var games := MinigameRegistry.playable()
	_log("Leak-Gate über %d Spiele (je %.1f s, Seed %d)" % [games.size(), PLAY_SEC, RUN_SEED])
	if games.is_empty():
		_log("FEHLER: keine Spiele registriert")
		quit(1)
		return

	_log("Warm-up (ungemessen): %s" % str(games[0]["id"]))
	await _run_once(str(games[0]["id"]))

	for game in games:
		var id := str(game["id"])
		await _flush()
		var before := _snapshot()
		var go := await _run_once(id)
		await _flush()
		var after := _snapshot()
		var orphans := int(after["orphans"]) - int(before["orphans"])
		var nodes := int(after["nodes"]) - int(before["nodes"])
		var objects := int(after["objects"]) - int(before["objects"])
		var resources := int(after["resources"]) - int(before["resources"])
		var clean := orphans == 0 and nodes == 0
		if not clean:
			_leaks.append("%s: +%d orphans, %+d nodes" % [id, orphans, nodes])
			print("LEAK %s: +%d orphans, %+d nodes im Baum" % [id, orphans, nodes])
		_log(
			(
				"%-18s %s  orphans %+d  nodes %+d  objectdb %+d (resources %+d)%s"
				% [
					id,
					"OK  " if clean else "LEAK",
					orphans,
					nodes,
					objects,
					resources,
					"" if go else "  [WARNUNG: GO-Timeout]",
				]
			)
		)

	if _leaks.is_empty():
		_log("GATE PASS — %d Spiele, 0 Orphans, 0 Node-Drift" % games.size())
		quit(0)
	else:
		_log("GATE FAIL — %d Leck(e):" % _leaks.size())
		for leak in _leaks:
			_log("  LEAK %s" % leak)
		quit(1)


## Ein Spiel regulär durchfahren: Host mounten → GO abwarten → PLAY_SEC
## laufen lassen → Quit-Pfad (wie der Pause-Dialog-„Beenden“-Knopf) → frei.
func _run_once(id: String) -> bool:
	_refill_energy()
	var host: Node = (load(HOST_SCENE) as PackedScene).instantiate()
	host.set("auto_navigate", false)
	host.set("countdown_step_sec", 0.0)
	host.set("resume_step_sec", 0.0)
	host.receive_params({"game_id": id, "difficulty": "normal", "seed": RUN_SEED})
	root.add_child(host)
	var go := await _wait_go(host)
	await create_timer(PLAY_SEC).timeout
	if is_instance_valid(host):
		host._on_quit_pressed()
		host.queue_free()
	return go


## GO erreicht, sobald der Host den Pause-Knopf freigibt (Rundenstart) —
## ODER die Runde schon vorbei ist (Blitz-Spiele/verweigerter Start).
func _wait_go(host: Node) -> bool:
	var deadline := Time.get_ticks_msec() + GO_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(host):
			return true
		if bool(host.get("_round_over")):
			return true
		var button: Button = host.get("_pause_button")
		if button != null and not button.disabled:
			return true
		await process_frame
	return false


## Jede Runde kostet Energie (§C6) — ohne Refill verweigert der Host den
## Start nach ~12 Spielen („Gooby erschöpft“) und das Gate misst nichts mehr.
func _refill_energy() -> void:
	_gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)


## Ausklingen + queue_free-Flush, damit die Messung stabile Werte sieht.
func _flush() -> void:
	await create_timer(SETTLE_SEC).timeout
	for _i in FLUSH_FRAMES:
		await process_frame


func _snapshot() -> Dictionary:
	return {
		"nodes": _count_nodes(root),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _count_nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count_nodes(child)
	return n


func _log(msg: String) -> void:
	print("[LEAKGATE] %s" % msg)
