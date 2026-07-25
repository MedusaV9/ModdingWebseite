extends SceneTree
## W4-P4-Screenshot-Tool (KEIN Test): rendert den Freunde-Screen nach dem
## Polish — 1) offline (grauer Chip + Hinweis + Leerzustand), 2) online mit
## Presence-Icons/Server-Labels + Anfrage, 3) Freundes-Code kopiert
## (Copy-Button-Feedback). Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w4p4.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W4P4"
const SETTLE_FRAMES := 24


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(720, 1160))
	root.size = Vector2i(720, 1160)

	var rig := NetTestRig.boot(self)
	var friends := FriendsService.new()
	rig.client.add_child(friends)
	friends.setup(rig.client)
	rig.client.friends = friends

	var screen: FriendsScreen = (
		(load("res://scripts/ui/friends/friends_screen.tscn") as PackedScene).instantiate()
	)
	screen.net_override = rig.client
	screen.auto_navigate = false
	root.add_child(screen)
	await _snap("freunde_offline.png")

	await rig.go_online(self, "GOOBY-MIA7")
	friends.friends = [
		{
			"friendCode": "GOOBY-9ZML",
			"name": "Lena",
			"goobyName": "Knöpfchen",
			"online": true,
			"coins": 842,
			"activity": {"kind": "home", "label": "ist mit Knöpfchen zuhause"},
		},
		{
			"friendCode": "GOOBY-AL1X",
			"name": "Ali",
			"goobyName": "Hoppel",
			"online": true,
			"coins": 1310,
			"activity": {"kind": "board", "label": "spielt eine Runde Schiffe versenken"},
		},
		{
			"friendCode": "GOOBY-MI44",
			"name": "Mia",
			"goobyName": "Flauschi",
			"online": true,
			"coins": 77,
			"activity": {"kind": "vacation", "label": "ist mit Flauschi im Urlaub"},
		},
		{
			"friendCode": "GOOBY-TOM2",
			"name": "Tom",
			"goobyName": "Wuschel",
			"online": false,
			"coins": 12,
		},
	]
	friends.friends_changed.emit(friends.friends)
	friends.requests = [{"from": "GOOBY-BBBB", "name": "Paula", "goobyName": "Gooby", "at": 2}]
	friends.requests_changed.emit(friends.requests)
	await _snap("freunde_online_presence_icons.png")

	screen._on_copy_pressed()
	await _snap("freunde_code_kopiert.png", 6)
	print("Clipboard: %s" % DisplayServer.clipboard_get())

	screen.queue_free()
	await rig.shutdown(self)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
