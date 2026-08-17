extends SceneTree
## RW-6-Screenshot-Tool (KEIN Test): rendert die Review-Artefakte des
## Ranch-Multiplayers — Verbindungs-UX (offline/online), MP-Menü mit
## Einladung, Rennen-Lobby, Ergebnis + Revanche, Bestenliste sowie die
## Welt-Ansichten Besuch (zwei Goobys), gemeinsamer Ausritt (Namensschilder
## + „Folge mir") und Rennen live (HUD an der Grasbahn). Panels laufen
## gegen einen ECHTEN RanchMultiplayerService am NetTestRig (FakeWsLink).
## Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/rw6_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW6"
const SETTLE := 40

var _rig: NetTestRig
var _service: RanchMultiplayerService
var _region: Node3D
var _riders: Array[RmpRemoteRider] = []


class FakeFriends:
	extends Node
	var friends: Array = []


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.theme = ThemeService.theme()
	await process_frame
	_rig = NetTestRig.boot(self)
	_service = RanchMultiplayerService.new()
	root.add_child(_service)
	_service.setup(_rig.client)
	await _menu_shots()
	await _lobby_shots()
	await _bestenliste_shot()
	await _welt_shots()
	print("RW6-Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## ------------------------------------------------------ Menü + Verbindung


func _menu_shots() -> void:
	var freunde := FakeFriends.new()
	freunde.friends = [
		{"friendCode": "GOOBY-MIA", "name": "Mia", "online": true},
		{"friendCode": "GOOBY-BEN", "name": "Ben", "online": true},
		{"friendCode": "GOOBY-ZOE", "name": "Zoe", "online": false},
	]
	root.add_child(freunde)
	var deck := _panel_deck()
	var panel := RmpMenuPanel.new()
	(deck.get_child(1) as CenterContainer).add_child(panel)
	panel.setup(_service, freunde)
	await _settle(8)
	# OFFLINE: Knöpfe höflich deaktiviert, Hinweis erklärt warum.
	await _shot("verbindung_menu_offline.png")
	# ONLINE gehen + eingehende Einladung von Mia (Rennen).
	await _rig.go_online(self)
	(
		_rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "RANCH_INVITED",
				"ts": 0,
				"d":
				{
					"from": "GOOBY-MIA",
					"name": "Mia",
					"mode": "rennen",
					"kurs": "grasbahn",
					"expiresInMs": 30000,
				},
			}
		)
	)
	await _settle(10)
	await _shot("verbindung_menu_online_einladung.png")
	deck.queue_free()
	freunde.queue_free()
	await process_frame


## ------------------------------------------------- Rennen-Lobby + Ergebnis


func _lobby_shots() -> void:
	_service.room_id = "mg:shot"
	_service.mode = "rennen"
	_service.kurs = "grasbahn"
	_service.players = [
		{"friendCode": "GOOBY-TEST", "name": "Ich"},
		{"friendCode": "GOOBY-MIA", "name": "Mia"},
		{"friendCode": "GOOBY-BEN", "name": "Ben"},
	]
	var deck := _panel_deck()
	var panel := RmpLobbyPanel.new()
	(deck.get_child(1) as CenterContainer).add_child(panel)
	panel.setup(_service)
	await _settle(4)
	panel._zeige_lobby()
	panel._on_lobby({"ready": ["GOOBY-TEST", "GOOBY-MIA"]})
	await _settle(8)
	await _shot("rennen_lobby.png")
	# Ergebnis nach dem Lauf: Platzierungen, DNF fair gewertet, Revanche.
	(
		_rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MG_RESULT",
				"ts": 0,
				"d":
				{
					"room": "mg:shot",
					"rewardId": "rmp-shot-1",
					"mode": "rennen",
					"kurs": "grasbahn",
					"rank": 1,
					"ranked": true,
					"results":
					[
						{
							"friendCode": "GOOBY-TEST",
							"rank": 1,
							"zeitMs": 31923,
							"dnf": false,
							"ranked": true
						},
						{
							"friendCode": "GOOBY-MIA",
							"rank": 2,
							"zeitMs": 33938,
							"dnf": false,
							"ranked": true
						},
						{
							"friendCode": "GOOBY-BEN",
							"rank": 3,
							"zeitMs": 0,
							"dnf": true,
							"ranked": false
						},
					],
				},
			}
		)
	)
	await _settle(10)
	await _shot("rennen_ergebnis_revanche.png")
	deck.queue_free()
	await process_frame


## ------------------------------------------------------------ Bestenliste


func _bestenliste_shot() -> void:
	var deck := _panel_deck()
	var panel := RmpLeaderboardPanel.new()
	(deck.get_child(1) as CenterContainer).add_child(panel)
	await _settle(4)
	(
		panel
		. zeige_eintraege(
			[
				{"friendCode": "GOOBY-MIA", "name": "Mia", "wert": 29841, "hatGhost": true},
				{"friendCode": "GOOBY-TEST", "name": "Ich", "wert": 31864, "hatGhost": true},
				{"friendCode": "GOOBY-BEN", "name": "Ben", "wert": 33938, "hatGhost": false},
				{"friendCode": "GOOBY-ZOE", "name": "Zoe", "wert": 4102_2, "hatGhost": false},
			],
			"GOOBY-TEST"
		)
	)
	await _settle(8)
	await _shot("bestenliste_grasbahn.png")
	deck.queue_free()
	await process_frame


## ------------------------------------------------------------ Welt-Szenen


func _welt_shots() -> void:
	var szene: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	_region = szene.instantiate()
	_region.stunde_override = 11.0
	_region.wetter_override = "sonne"
	root.add_child(_region)
	await _settle(30)
	await _besuch_shot()
	await _ausritt_shot()
	await _rennen_live_shot()
	_region.queue_free()
	await process_frame


## Besuch: Gast-Sicht auf dem Hof — BEIDE Goobys sichtbar (das eigene
## abgestiegen, das des Hosts im Sattel), Ranch-Info-Overlay + Herz-Toast.
func _besuch_shot() -> void:
	_service.room_id = "mg:besuch"
	_service.mode = "besuch"
	_service.players = [{"friendCode": "GOOBY-MIA", "name": "Mia"}]
	_teleport(Vector2(0, 172), Vector2(0, 120))
	# Gruppe: eigenes Pferd + eigenes Gooby (abgestiegen) + Mias Gooby im
	# Sattel. Eigene Shot-Kamera von schräg vorn — die Reiter-Kamera würde
	# das eigene Pferd immer in die Bildmitte (hinters Panel) legen.
	_spawn_rider("Mia", Vector2(-4.6, 169.5), 2.2, 0)
	var mein_gooby := GoobyRig.new()
	mein_gooby.scale = Vector3.ONE * 1.1
	mein_gooby.position = RanchKarte.punkt(-1.4, 169.5)
	# GoobyRig schaut lokal nach +Z — für den Blick zur Kamera also -0.74.
	mein_gooby.rotation.y = -0.74
	_region.add_child(mein_gooby)
	mein_gooby.set_emotion("happy")
	# Ziel liegt RECHTS der Gruppe — so landet die Gruppe in der linken
	# Bildhälfte und das Panel (rechts) verdeckt nichts; beide Goobys
	# schauen zur Kamera.
	var shot_cam := Camera3D.new()
	shot_cam.fov = 55.0
	_region.add_child(shot_cam)
	shot_cam.global_position = RanchKarte.punkt(-9.5, 178.0) + Vector3(0.0, 2.6, 0.0)
	shot_cam.look_at(RanchKarte.punkt(0.8, 171.5) + Vector3(0.0, 1.2, 0.0))
	shot_cam.make_current()
	var panel := RmpBesuchPanel.new()
	root.add_child(panel)
	panel.setup(_service)
	await _settle(4)
	(
		panel
		. zeige_ranch(
			(
				RmpRanchMeta
				. normalize(
					{
						"name": "Mia",
						"goobyName": "Flauschi",
						"ausbau": {"boxen": 3, "reitplatz": true},
						"pferde":
						[
							{"name": "Puschel", "rasse": "haflinger", "level": 4},
							{"name": "Sturmwind", "rasse": "araber", "level": 7},
						],
						"trophaeen": ["pokal_gold"],
						"schleifen": 5,
					}
				)
			)
		)
	)
	await _settle_mit_posen(SETTLE)
	# Herz-Reaktion kurz vor dem Shot einspielen (Toast lebt nur 3 s).
	(
		_rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": "mg:besuch", "from": "GOOBY-MIA", "kind": "HERZ", "body": {}},
			}
		)
	)
	await _settle_mit_posen(6)
	var sicht: Vector2 = root.get_visible_rect().size
	panel.position = sicht - panel.size - Vector2(24, 24)
	print("besuch: sicht=%s panel=%s pos=%s" % [sicht, panel.size, panel.position])
	await _shot("besuch_zwei_goobys.png")
	panel.queue_free()
	mein_gooby.queue_free()
	shot_cam.queue_free()
	_region.reiter.cam.make_current()
	_riders_weg()
	await process_frame


## Gemeinsamer Ausritt im Weidetal: drei Freunde mit Namensschildern,
## eines mit „Folge mir"-Marker — Reiter sind Geister (keine Kollision).
func _ausritt_shot() -> void:
	_service.mode = "ausritt"
	_service.players = [
		{"friendCode": "GOOBY-TEST", "name": "Ich"},
		{"friendCode": "GOOBY-MIA", "name": "Mia"},
		{"friendCode": "GOOBY-BEN", "name": "Ben"},
		{"friendCode": "GOOBY-ZOE", "name": "Zoe"},
	]
	var von := Vector2(-380, 90)
	var nach := Vector2(-590, 200)
	_teleport(von, nach)
	_region.reiter.pferd.set_gangart(RanchPferd.GANG_TRAB)
	var richtung := (nach - von).normalized()
	var blick := atan2(-richtung.x, -richtung.y)
	var quer := Vector2(-richtung.y, richtung.x)
	var mia := _spawn_rider("Mia", von + richtung * 7.0 + quer * 2.8, blick, 2)
	mia.set_follow_me(true)
	_spawn_rider("Ben", von + richtung * 4.5 - quer * 3.2, blick + 0.15, 2)
	_spawn_rider("Zoe", von + richtung * 9.5 - quer * 0.6, blick - 0.1, 2)
	await _settle_mit_posen(SETTLE)
	await _shot("ausritt_gemeinsam.png")
	_riders_weg()
	await process_frame


## Rennen live: Grasbahn im Weidetal, HUD mit Checkpoint-Fortschritt,
## Live-Platz und Peer-Hinweis (Verbindungs-UX während des Laufs).
func _rennen_live_shot() -> void:
	_service.room_id = "mg:lauf"
	_service.mode = "rennen"
	_service.kurs = "grasbahn"
	_service.phase = "run"
	_service.players = [
		{"friendCode": "GOOBY-TEST", "name": "Ich"},
		{"friendCode": "GOOBY-MIA", "name": "Mia"},
		{"friendCode": "GOOBY-BEN", "name": "Ben"},
	]
	var von := Vector2(-330, 60)
	var nach := Vector2(-356, 102)
	_teleport(von, nach)
	_region.reiter.pferd.set_gangart(RanchPferd.GANG_GALOPP)
	var richtung := (nach - von).normalized()
	var blick := atan2(-richtung.x, -richtung.y)
	var quer := Vector2(-richtung.y, richtung.x)
	_spawn_rider("Mia", von + richtung * 8.0 + quer * 2.8, blick, 4)
	_spawn_rider("Ben", von + richtung * 4.5 - quer * 3.2, blick, 4)
	var hud := RmpLaufHud.new()
	hud.position = Vector2(24, 24)
	root.add_child(hud)
	hud.setup(_service)
	await _settle(4)
	hud.set_mein_fortschritt(2)
	hud._on_state({"progress": {"GOOBY-MIA": 3, "GOOBY-BEN": 1}})
	await _settle_mit_posen(SETTLE)
	# Peer-Hinweis (Verbindungs-UX) kurz vor dem Shot — er lebt nur 3 s.
	hud._on_peer_down({"friendCode": "GOOBY-BEN"})
	await _settle_mit_posen(6)
	await _shot("rennen_live_hud.png")
	hud.queue_free()
	_riders_weg()
	await process_frame


## ---------------------------------------------------------------- Helfer


## Voll-Hintergrund + CenterContainer für Panel-Shots (Kind 0 = Farbe,
## Kind 1 = Center). Bewusst OHNE Anker: direkte Window-Kinder werden nicht
## automatisch gelayoutet, und außerhalb von get_visible_rect() wird nichts
## gerendert — also explizit auf den sichtbaren Canvas-Bereich setzen.
func _panel_deck() -> Control:
	var area: Vector2 = root.get_visible_rect().size
	var deck := Control.new()
	root.add_child(deck)
	deck.size = area
	var farbe := ColorRect.new()
	farbe.color = Color("#2E4A33")
	farbe.size = area
	deck.add_child(farbe)
	var center := CenterContainer.new()
	center.size = area
	deck.add_child(center)
	return deck


func _teleport(von: Vector2, nach: Vector2) -> void:
	var blick := atan2(-(nach.x - von.x), -(nach.y - von.y))
	_region.reiter.springe_zu(RanchKarte.punkt(von.x, von.y), blick)


func _spawn_rider(wer: String, bei: Vector2, yaw: float, gait: int) -> RmpRemoteRider:
	var rider := RmpRemoteRider.new()
	_region.add_child(rider)
	rider.set_display_name(wer)
	rider.set_meta("shot_pos", bei)
	rider.set_meta("shot_yaw", yaw)
	rider.set_meta("shot_gait", gait)
	_riders.append(rider)
	_pose_fuer(rider)
	return rider


## Pose einspeisen (RmpInterp braucht frische Samples, sonst gilt der Peer
## nach STALE_MS als eingefroren).
func _pose_fuer(rider: RmpRemoteRider) -> void:
	var bei: Vector2 = rider.get_meta("shot_pos")
	var punkt := RanchKarte.punkt(bei.x, bei.y)
	(
		rider
		. apply_pose(
			{
				"p": [punkt.x, punkt.y, punkt.z],
				"yaw": rider.get_meta("shot_yaw"),
				"gait": rider.get_meta("shot_gait"),
				"jump": false,
			}
		)
	)


func _settle_mit_posen(frames: int) -> void:
	for i in frames:
		if i % 6 == 0:
			for rider in _riders:
				_pose_fuer(rider)
		await process_frame


func _riders_weg() -> void:
	for rider in _riders:
		rider.queue_free()
	_riders.clear()


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(datei: String) -> void:
	await process_frame
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var bild := root.get_texture().get_image()
	bild.save_png("%s/%s" % [OUT_DIR, datei])
	print("shot: %s  draw_calls=%d" % [datei, int(calls)])
