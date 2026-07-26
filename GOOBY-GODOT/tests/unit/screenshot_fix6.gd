extends SceneTree
## FIX6-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Save-Transfer- und Multiplayer-Deliverables als Review-Artefakte:
## Transfer-Screen (leer / Auto-Fund / Vorschau / Erfolg) und den
## Schiffe-versenken-Tisch (Partie mit Verbindungsanzeige, Peer-Down,
## Revanche-Angebot nach GAME_OVER).
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_fix6.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FIX6"
const SETTLE_FRAMES := 24
const NOW_MS := 1768478400000

const TransferScreenScene := preload("res://scripts/state/import/transfer_screen.tscn")
const BattleshipScene := preload("res://scripts/social/boardgame/battleship_scene.tscn")


## GameState-Double für den Transfer-Screen.
class FakeGameState:
	extends RefCounted
	var imported: Dictionary = {}

	func import_state(new_state: Dictionary) -> void:
		imported = new_state

	func state() -> Dictionary:
		return {"v": 5}

	func get_value(_path: String, default: Variant = null) -> Variant:
		return default


## Netz-Double für die Battleship-Szene (Status "Online", schluckt Sends).
class FakeNet:
	extends Node
	signal status_changed(status: int)
	signal pushed(type: String, data: Dictionary)
	signal message_received(envelope: Dictionary)
	var status := 2
	var friend_code := "GOOBY-WH6W"
	var _seq := 0

	func is_online() -> bool:
		return true

	func send(_type: String, _data: Dictionary = {}) -> int:
		_seq += 1
		return _seq

	func request(_type: String, _data: Dictionary = {}) -> Dictionary:
		return {"ok": true, "t": "OK", "d": {}}


class FakeServices:
	extends Node
	var board: BoardSession


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await _shots_transfer()
	await _shots_battleship()
	print("FIX6-Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _fixture_text(file_name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/" + file_name)


# ── Transfer-Screen ──────────────────────────────────────────────────────────


func _make_transfer(plist := "") -> TransferScreen:
	var screen: TransferScreen = TransferScreenScene.instantiate()
	screen.gs_override = FakeGameState.new()
	screen.now_override = NOW_MS
	if plist.is_empty():
		screen.auto_probe = false
	else:
		screen.plist_override = plist
	root.add_child(screen)
	return screen


func _shots_transfer() -> void:
	# 1. Leerer Screen (Einfüge-Phase).
	var screen := _make_transfer()
	await _snap("transfer_01_leer.png")
	screen.queue_free()
	await process_frame

	# 2. Auto-Fund (iOS-Simulation: NSUserDefaults-Plist mit Alt-Save).
	var plist_path := _write_demo_plist()
	screen = _make_transfer(plist_path)
	await _snap("transfer_02_auto_gefunden.png")

	# 3. Vorschau: echtes v4-Fixture eingefügt und geprüft.
	screen.set_input_text(_fixture_text("v4_midgame.json"))
	screen.check_now()
	await _snap("transfer_03_vorschau.png")

	# 4. Erfolg: übernommen (Vorsicherung + Import über das GameState-Double).
	screen.apply_now()
	await _snap("transfer_04_erfolg.png")
	screen.queue_free()
	await process_frame


## Mini-bplist00-Writer (nur 1 ASCII-Key + 1 ASCII-Wert) für den Auto-Fund.
func _write_demo_plist() -> String:
	var key := "CapacitorStorage.gooby.save"
	var value := _fixture_text("v4_fresh.json")
	var objects: Array[PackedByteArray] = [
		PackedByteArray([0xD1, 0x01, 0x02]), _ascii_obj(key), _ascii_obj(value)
	]
	var out := "bplist00".to_ascii_buffer()
	var offsets: Array[int] = []
	for obj in objects:
		offsets.append(out.size())
		out.append_array(obj)
	var table := out.size()
	for off in offsets:
		out.append((off >> 8) & 0xFF)
		out.append(off & 0xFF)
	out.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 2, 1]))
	for value64: int in [objects.size(), 0, table]:
		for i in 8:
			out.append((value64 >> ((7 - i) * 8)) & 0xFF)
	var path := OUT_DIR + "/demo.plist"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(out)
	file.flush()
	return path


func _ascii_obj(text: String) -> PackedByteArray:
	var bytes := text.to_ascii_buffer()
	var out := PackedByteArray()
	if bytes.size() < 15:
		out.append(0x50 | bytes.size())
	elif bytes.size() < 256:
		out.append_array(PackedByteArray([0x5F, 0x10, bytes.size()]))
	else:
		out.append_array(
			PackedByteArray([0x5F, 0x11, (bytes.size() >> 8) & 0xFF, bytes.size() & 0xFF])
		)
	out.append_array(bytes)
	return out


# ── Battleship-Tisch ─────────────────────────────────────────────────────────


func _shots_battleship() -> void:
	var net := FakeNet.new()
	root.add_child(net)
	var session := BoardSession.new()
	root.add_child(session)
	session.setup(net)
	await (
		session
		. _on_board_start(
			{
				"room": "board:demo",
				"game": "battleship",
				"seed": 1962674142,
				"first": net.friend_code,
				"players":
				[
					{"friendCode": net.friend_code, "name": "Alice", "goobyName": "Flausch"},
					{"friendCode": "GOOBY-554E", "name": "Bob", "goobyName": "Knöpfchen"},
				],
			}
		)
	)
	var services := FakeServices.new()
	services.board = session
	root.add_child(services)
	var scene: BattleshipScene = BattleshipScene.instantiate()
	scene.services_override = services
	root.add_child(scene)
	await process_frame
	_wire_indicator(scene, net)
	scene._on_ready_pressed()

	# Ein paar Züge simulieren: eigener Treffer + Gegner-Schuss.
	session.shoot(Vector2i(1, 3))
	session._on_room_msg("SHOT_RESULT", {"n": 1, "hit": true, "sunk": false}, {})
	session._on_room_msg("SHOT", {"n": 2, "cell": "C5"}, {})
	session.shoot(Vector2i(4, 6))
	session._on_room_msg("SHOT_RESULT", {"n": 3, "hit": false, "sunk": false}, {})
	await _snap("battleship_05_partie_verbindungsanzeige.png")

	# Gegner verliert die Verbindung → Peer-Down-Anzeige.
	session._on_push(
		"BOARD_PEER_DOWN", {"room": "board:demo", "friendCode": "GOOBY-554E", "waitMs": 120000}
	)
	await _snap("battleship_06_peer_down.png", 6)
	session._on_push("BOARD_PEER_UP", {"room": "board:demo", "friendCode": "GOOBY-554E"})

	# Sieg → Revanche-Angebot (Knopf mittig, „Verlassen“ statt „Aufgeben“).
	session._on_room_msg("GAME_OVER", {"winner": net.friend_code}, {})
	await _snap("battleship_07_revanche_angebot.png")

	scene.queue_free()
	services.queue_free()
	session.queue_free()
	net.queue_free()
	await process_frame


## Verbindungsanzeige der Szene nachträglich mit dem Fake-Netz verdrahten
## (im --script-Modus gibt es kein /root/Net-Autoload).
func _wire_indicator(node: Node, net: Node) -> void:
	if node is NetStatusIndicator:
		(node as NetStatusIndicator).setup(net)
		return
	for child in node.get_children():
		_wire_indicator(child, net)


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
