extends SceneTree
## W3c-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## VISIT-Deliverables als Review-Artefakte: Besuchs-Szene mit ZWEI Goobys
## (+ Spitznamen-Label), Battleship-Tisch First-Person, Tomaten-Splat-Moment,
## Emote-Rad und GoobyPal-Sheet.
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w3c.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W3c"
const SETTLE_FRAMES := 24


## NetClient-Attrappe fürs GoobyPal-Sheet (online-Optik ohne Server).
class FakeNet:
	extends Node
	signal pushed(type: String, data: Dictionary)
	signal welcome_received(data: Dictionary)
	var welcome_data: Dictionary = {}
	var friend_code := "GOOBY-ME"

	func is_online() -> bool:
		return true

	func request(_type: String, _data: Dictionary = {}) -> Dictionary:
		await get_tree().process_frame
		return {"ok": false, "code": "TIMEOUT", "t": "", "d": {}}

	func send(_type: String, _data: Dictionary = {}) -> int:
		return -1

	## Signale nur referenzieren, damit der Analyzer sie als benutzt sieht.
	func _unused() -> void:
		pushed.emit("", {})
		welcome_received.emit({})


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_besuch()
	await _shot_battleship()
	await _shot_goobypal()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _snapshot_haus() -> Dictionary:
	return {
		"v": 1,
		"goobyName": "Flauschi",
		"rooms":
		{
			"living":
			{
				"items":
				[
					{"uid": "s1", "item": "loungeSofa", "at": [4, 2], "rot": 0},
					{"uid": "t1", "item": "tableCoffee", "at": [5, 5], "rot": 0},
					{"uid": "c1", "item": "loungeChair", "at": [9, 3], "rot": 3},
					{"uid": "b1", "item": "bookcaseOpen", "at": [1, 1], "rot": 0},
				]
			},
			"kitchen": {"items": []},
			"bedroom": {"items": [{"uid": "b2", "item": "bedSingle", "at": [3, 2], "rot": 0}]},
		},
	}


## 1) Besuchs-Szene: eigener Gooby + Gast-Gooby (RemoteGooby mit Label).
func _shot_besuch() -> void:
	var social := SocialServices.new()
	root.add_child(social)
	social.visit.peer_gooby_name = "Flauschi"
	social.visit.peer_room_id = "living"

	var scene := VisitScene.new()
	scene.services_override = social
	scene.relay_enabled = false
	scene.receive_params({"snapshot": _snapshot_haus(), "role": VisitService.ROLE_GUEST})
	root.add_child(scene)
	for _i in 30:
		await process_frame
	if scene.my_gooby.has_method("set_wander_enabled"):
		scene.my_gooby.set_wander_enabled(false)
	# Peer-Position wie aus dem POS-Relay: neben dem eigenen Gooby.
	var base: Vector3 = scene.my_gooby.global_position
	social.visit.peer_pos.emit(base + Vector3(1.1, 0.0, -0.6), "idle", "living")
	for _i in 40:
		await process_frame
	social.visit.peer_pos.emit(base + Vector3(1.1, 0.0, -0.6), "idle", "living")
	await _snap("besuch_zwei_goobys.png")
	scene.queue_free()
	social.queue_free()
	await process_frame
	await process_frame


## 2–4) Battleship: Tisch First-Person, Emote-Rad, Tomaten-Splat.
func _shot_battleship() -> void:
	var social := SocialServices.new()
	root.add_child(social)
	social.board.opponent_gooby_name = "Flauschi"
	social.board.turn = BattleshipLogic.Turn.new("", ["", "GOOBY-PEER"])

	var scene := BattleshipScene.new()
	scene.services_override = social
	root.add_child(scene)
	for _i in 30:
		await process_frame
	# Mid-Game-Optik: Bereit drücken + ein paar Marker beider Bretter.
	scene._on_ready_pressed()
	scene.opp_board_view.set_marker(Vector2i(2, 3), "hit")
	scene.opp_board_view.set_marker(Vector2i(3, 3), "hit")
	scene.opp_board_view.set_marker(Vector2i(6, 6), "miss")
	scene.opp_board_view.set_marker(Vector2i(4, 3), "sunk")
	scene.my_board_view.set_marker(Vector2i(1, 1), "miss")
	scene.my_board_view.set_marker(Vector2i(5, 4), "hit")
	for _i in 20:
		await process_frame
	await _snap("battleship_tisch.png")

	# Emote-Rad offen.
	scene.wheel.toggle()
	for _i in 10:
		await process_frame
	await _snap("emote_rad.png")
	scene.wheel.toggle()

	# Tomate: Gegner wirft auf UNS — Bogen (0,55 s), dann Splat auf die Kamera.
	scene._play_tomato_arc(scene.opp_gooby, scene.my_gooby, true)
	await create_timer(0.35).timeout
	await _snap("tomate_wurf_bogen.png", 0)
	await create_timer(0.6).timeout
	await _snap("tomaten_splat.png", 6)
	scene.queue_free()
	social.queue_free()
	await process_frame
	await process_frame


## 5) GoobyPal-Sheet (Betrag-Wahl + Tageslimit-Anzeige).
func _shot_goobypal() -> void:
	var net := FakeNet.new()
	root.add_child(net)
	var pal := GoobyPalService.new()
	root.add_child(pal)
	pal.setup(net, null)
	pal.sent_today = 60

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#F6E3C5")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(backdrop)
	var sheet := GoobyPalSheet.new()
	sheet.setup(pal, {"friendCode": "GOOBY-PEER", "name": "Mia", "goobyName": "Flauschi"})
	host.add_child(sheet)
	for _i in 30:
		await process_frame
	await _snap("goobypal_sheet.png")
	host.queue_free()
	pal.queue_free()
	net.queue_free()
	await process_frame
	await process_frame


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
