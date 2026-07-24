extends TestCase
## FriendsScreen (UI): Offline-Zustand (Hinweis sichtbar, Code leer), Online-
## Zustand (Chip/Code), Live-Pflege der Listen über die Service-Signale und
## das Absenden einer Anfrage aus dem Eingabefeld.


func test_offline_zeigt_hinweis_und_leeren_code() -> void:
	var rig := NetTestRig.boot(tree)
	var screen := _attach_screen(rig)
	assert_true(screen._offline_hint.visible, "Offline-Hinweis sichtbar")
	assert_eq(screen._code_value.text, "—")
	assert_eq(screen._status_chip.text, I18nService.t("net.status.offline"))
	await _teardown(rig, screen)


func test_online_zeigt_code_und_versteckt_hinweis() -> void:
	var rig := NetTestRig.boot(tree)
	var screen := _attach_screen(rig)
	await rig.go_online(tree, "GOOBY-UI42")
	assert_false(screen._offline_hint.visible)
	assert_eq(screen._code_value.text, "GOOBY-UI42")
	assert_eq(screen._status_chip.text, I18nService.t("net.status.online"))
	await _teardown(rig, screen)


func test_pushes_fuellen_listen_live() -> void:
	var rig := NetTestRig.boot(tree)
	var screen := _attach_screen(rig)
	await rig.go_online(tree)

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_ADDED",
				"ts": 0,
				"d":
				{
					"friendCode": "GOOBY-9ZML",
					"name": "Lena",
					"goobyName": "Knöpfchen",
					"online": true,
					"coins": 842,
				},
			}
		)
	)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_REQUEST_INCOMING",
				"ts": 0,
				"d": {"from": "GOOBY-BBBB", "name": "Ali", "goobyName": "Gooby", "at": 2},
			}
		)
	)
	await wait_frames(3)
	assert_eq(screen._friends_box.get_child_count(), 1, "Freundeszeile da")
	assert_true(screen._requests_title.visible, "Anfragen-Sektion sichtbar")
	assert_eq(screen._requests_box.get_child_count(), 1)
	await _teardown(rig, screen)


func test_add_input_sendet_friend_request() -> void:
	var rig := NetTestRig.boot(tree)
	var screen := _attach_screen(rig)
	await rig.go_online(tree)

	screen._add_input.text = "GOOBY-ZIEL"
	screen._on_add_pressed()
	await wait_frames(1)
	var sent := rig.link().last_sent("FRIEND_REQUEST")
	assert_eq((sent.get("d", {}) as Dictionary).get("target"), "GOOBY-ZIEL")
	rig.link().respond_to("FRIEND_REQUEST", "OK", {})
	var done := await wait_until(func() -> bool: return screen._add_feedback.visible, 3000)
	assert_true(done, "Feedback erscheint")
	assert_eq(screen._add_feedback.text, I18nService.t("net.friends.add_sent"))
	assert_eq(screen._add_input.text, "", "Eingabe geleert nach Erfolg")
	await _teardown(rig, screen)


func _attach_screen(rig: NetTestRig) -> FriendsScreen:
	var friends := FriendsService.new()
	rig.client.add_child(friends)
	friends.setup(rig.client)
	rig.client.friends = friends
	var screen: FriendsScreen = (
		(load("res://scripts/ui/friends/friends_screen.tscn") as PackedScene).instantiate()
	)
	screen.net_override = rig.client
	screen.auto_navigate = false
	tree.root.add_child(screen)
	return screen


func _teardown(rig: NetTestRig, screen: FriendsScreen) -> void:
	screen.queue_free()
	await rig.shutdown(tree)
