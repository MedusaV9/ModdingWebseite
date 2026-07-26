extends TestCase
## RW-6-UI: Lobby-Panel (Spielerliste → Ergebnis → Revanche), Bestenliste
## (Zeit-/Punkte-Richtung, eigene Zeile), Besuchs-Panel (Ranch-Meta +
## Reaktionen), Menü (offline höflich deaktiviert) und die DE/EN-Paritaet
## der ranch_mp-Strings.


func test_strings_de_en_paritaet() -> void:
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var de_keys: Array[String] = []
	for key: String in de:
		if key.begins_with("ranch_mp."):
			de_keys.append(key)
	assert_true(de_keys.size() >= 60, "Domain vorhanden (%d Keys)" % de_keys.size())
	for key in de_keys:
		assert_true(en.has(key), "EN fehlt: %s" % key)
	for key: String in en:
		if key.begins_with("ranch_mp."):
			assert_true(de.has(key), "DE fehlt: %s" % key)


func test_lobby_panel_zeigt_spieler_und_ergebnis() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := RanchMultiplayerService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	var panel := RmpLobbyPanel.new()
	tree.root.add_child(panel)
	panel.setup(service)
	await wait_frames(1)

	service.room_id = "mg:ui"
	service.mode = "rennen"
	service.kurs = "grasbahn"
	service.players = [
		{"friendCode": "GOOBY-TEST", "name": "Ich"},
		{"friendCode": "GOOBY-PEER", "name": "Mia"},
	]
	panel._zeige_lobby()
	await wait_frames(2)
	var texte := _alle_labels(panel)
	assert_true(_enthaelt(texte, "Mia"), "Spielerzeile sichtbar")
	assert_true(_enthaelt(texte, "Lobby"), "Lobby-Titel")

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MG_RESULT",
				"ts": 0,
				"d":
				{
					"room": "mg:ui",
					"rewardId": "r-1",
					"results":
					[
						{
							"friendCode": "GOOBY-PEER",
							"rank": 1,
							"zeitMs": 61_500,
							"dnf": false,
							"ranked": true
						},
						{
							"friendCode": "GOOBY-TEST",
							"rank": 2,
							"zeitMs": 0,
							"dnf": true,
							"ranked": false
						},
					],
				},
			}
		)
	)
	await wait_frames(3)
	texte = _alle_labels(panel)
	assert_true(_enthaelt(texte, "1. Mia"), "Ergebniszeile mit Platz")
	assert_true(_enthaelt(texte, I18nService.t("ranch_mp.ergebnis.dnf")), "DNF wird fair angezeigt")
	assert_true(_knopf_sichtbar(panel, I18nService.t("ranch_mp.ergebnis.revanche")))
	panel.queue_free()
	service.queue_free()
	await rig.shutdown(tree)


func test_leaderboard_panel_richtung_und_eigene_zeile() -> void:
	var panel := RmpLeaderboardPanel.new()
	tree.root.add_child(panel)
	await wait_frames(1)
	# Standard-Auswahl = grasbahn (Zeit): Sekunden-Format + (du)-Markierung.
	(
		panel
		. zeige_eintraege(
			[
				{"friendCode": "GOOBY-PEER", "name": "Mia", "wert": 59_400, "hatGhost": true},
				{"friendCode": "GOOBY-TEST", "name": "Ich", "wert": 61_000, "hatGhost": false},
			],
			"GOOBY-TEST"
		)
	)
	await wait_frames(2)
	var texte := _alle_labels(panel)
	assert_true(_enthaelt(texte, "59.4"), "Zeit in Sekunden")
	assert_true(_enthaelt(texte, I18nService.t("ranch_mp.besten.du")), "eigene Zeile markiert")
	assert_true(
		_knopf_sichtbar(panel, I18nService.t("ranch_mp.besten.geist_laden")),
		"Geist-Knopf nur bei hatGhost"
	)
	var angefragt: Array = []
	panel.ghost_requested.connect(
		func(kurs: String, code: String) -> void: angefragt.append([kurs, code])
	)
	_druecke_knopf(panel, I18nService.t("ranch_mp.besten.geist_laden"))
	await wait_frames(1)
	assert_eq(angefragt.size(), 1)
	assert_eq(angefragt[0][1], "GOOBY-PEER")
	panel.zeige_eintraege([], "GOOBY-TEST")
	await wait_frames(2)
	assert_true(
		_enthaelt(_alle_labels(panel), I18nService.t("ranch_mp.besten.leer")),
		"leere Liste erklärt sich"
	)
	panel.queue_free()


func test_besuch_panel_meta_und_reaktionen() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := RanchMultiplayerService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	service.room_id = "mg:besuch"
	service.mode = "besuch"
	service.players = [{"friendCode": "GOOBY-PEER", "name": "Mia"}]
	var panel := RmpBesuchPanel.new()
	tree.root.add_child(panel)
	panel.setup(service)
	await wait_frames(1)
	(
		panel
		. zeige_ranch(
			(
				RmpRanchMeta
				. normalize(
					{
						"name": "Mia",
						"goobyName": "Flauschi",
						"ausbau": {"boxen": 2, "reitplatz": true},
						"pferde": [{"name": "Wolke", "rasse": "toelter", "level": 7}],
						"trophaeen": ["pokal_holz"],
						"schleifen": 3,
					}
				)
			)
		)
	)
	await wait_frames(1)
	var texte := _alle_labels(panel)
	assert_true(_enthaelt(texte, "Wolke"), "Pferd mit Name")
	assert_true(_enthaelt(texte, "Level 7"), "…und Level")
	assert_true(_enthaelt(texte, "Reitplatz"), "Ausbau sichtbar")
	# Gast streichelt → GESTE geht raus; Herz vom Peer → Toast.
	_druecke_knopf(panel, I18nService.t("ranch_mp.besuch.streicheln"))
	await wait_frames(1)
	assert_eq(rig.link().last_sent("ROOM_MSG")["d"]["kind"], "GESTE")
	assert_eq(rig.link().last_sent("ROOM_MSG")["d"]["body"]["id"], "streicheln")
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": "mg:besuch", "from": "GOOBY-PEER", "kind": "HERZ", "body": {}},
			}
		)
	)
	await wait_frames(3)
	assert_true(
		_enthaelt(_alle_labels(panel), I18nService.t("ranch_mp.besuch.herz_von", {"name": "Mia"}))
	)
	panel.queue_free()
	service.queue_free()
	await rig.shutdown(tree)


func test_menu_offline_hoeflich_deaktiviert() -> void:
	var rig := NetTestRig.boot(tree)
	var service := RanchMultiplayerService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	var panel := RmpMenuPanel.new()
	tree.root.add_child(panel)
	panel.setup(service)
	await wait_frames(2)
	assert_true(
		_enthaelt(_alle_labels(panel), I18nService.t("ranch_mp.menu.offline_hint")),
		"Offline-Hinweis statt Fehlermeldung"
	)
	assert_true(panel._modus_wahl.disabled, "Modus-Wahl höflich deaktiviert")
	# Online gehen → Menü wird nutzbar.
	await rig.go_online(tree)
	await wait_frames(2)
	assert_false(panel._modus_wahl.disabled)
	panel.queue_free()
	service.queue_free()
	await rig.shutdown(tree)


## ---------------------------------------------------------------- Helfer


func _alle_labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node is Label:
		out.append((node as Label).text)
	for kind in node.get_children():
		out.append_array(_alle_labels(kind))
	return out


func _enthaelt(texte: Array[String], teil: String) -> bool:
	for text in texte:
		if text.contains(teil):
			return true
	return false


func _knopf_sichtbar(node: Node, text: String) -> bool:
	return _finde_knopf(node, text) != null


func _druecke_knopf(node: Node, text: String) -> void:
	var knopf := _finde_knopf(node, text)
	if knopf != null:
		knopf.pressed.emit()


func _finde_knopf(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).visible:
		return node
	for kind in node.get_children():
		var gefunden := _finde_knopf(kind, text)
		if gefunden != null:
			return gefunden
	return null
