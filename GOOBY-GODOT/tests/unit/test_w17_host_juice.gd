extends TestCase
## W17/INTEGRATE (Q1 aus mg-audit-b §0) — Wächter für die Juice-Ebene des
## MinigameHost: Spiele reichen Viewport-Pixel aus _stage.to_screen() in
## float_text/overlay_burst/overlay_ring. Der Host muss diese Ebene deshalb
## DECKUNGSGLEICH über den letterboxten SubViewportContainer legen — vorher
## hing sie als FULL-RECT im Fenster-Raum, und „+2“-Texte/Ringe klebten im
## Creme-Rand statt am Treffer (Beleg: lantern_float_quer.png, Audit B).

const HOST_SCENE := preload("res://scripts/minigames/minigame_host.tscn")


func _mount_host(window: Vector2i) -> MinigameHost:
	# Energie auffüllen (Muster screenshot_mg1): der Host verweigert den
	# Start für erschöpfte Goobys — Vorläufer-Tests dürfen uns nicht kippen.
	var gs := tree.root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
	tree.root.size = window
	tree.root.size_changed.emit()
	await wait_frames(2)
	var host: MinigameHost = HOST_SCENE.instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.0
	host.receive_params({"game_id": "bubblePop", "difficulty": "normal", "seed": 4242})
	tree.root.add_child(host)
	await wait_frames(4)
	return host


func _unmount(host: MinigameHost) -> void:
	host.queue_free()
	await wait_frames(1)


func test_juice_ebene_deckt_das_letterbox_feld() -> void:
	# Quer-Fenster + Portrait-Spiel → deutliche Pillarbox links und rechts.
	var host := await _mount_host(Vector2i(1200, 700))
	var container: SubViewportContainer = host._viewport_container
	assert_ne(container, null, "Host hat das Spiel gemountet (Energie/Registry ok)")
	if container == null:
		await _unmount(host)
		return
	var layer := host.juice.float_text_parent as Control
	assert_ne(layer, null, "float_text_parent ist eine Control-Ebene")
	assert_true(
		container.position.x > 40.0,
		"Testaufbau hat wirklich Pillarbox (links sind es %.0f px)" % container.position.x
	)
	assert_true(layer != host._overlay, "Juice-Ebene ist NICHT mehr das Fenster-Overlay (Q1)")
	assert_almost(layer.global_position.x, container.global_position.x, 0.5, "x deckungsgleich")
	assert_almost(layer.global_position.y, container.global_position.y, 0.5, "y deckungsgleich")
	assert_almost(layer.size.x, container.size.x, 0.5, "Breite deckungsgleich")
	assert_almost(layer.size.y, container.size.y, 0.5, "Höhe deckungsgleich")
	await _unmount(host)


func test_float_text_landet_am_gemeinten_punkt() -> void:
	var host := await _mount_host(Vector2i(1200, 700))
	var container: SubViewportContainer = host._viewport_container
	assert_ne(container, null, "Host hat das Spiel gemountet (Energie/Registry ok)")
	if container == null:
		await _unmount(host)
		return
	var layer := host.juice.float_text_parent as Control
	var before := layer.get_child_count()
	# Spiel-Sicht: Punkt in Viewport-Pixeln (Mitte des Spielfelds) — genau
	# die Koordinatenwelt, die _stage.to_screen()/unproject_position liefert.
	var viewport_mitte := Vector2(host._viewport.size) * 0.5
	host.juice.float_text(viewport_mitte, "+2")
	assert_eq(layer.get_child_count(), before + 1, "float_text hängt im JuiceLayer")
	var label := layer.get_child(layer.get_child_count() - 1) as Label
	var soll := container.global_position + container.size * 0.5
	# Seit G8/FIX-7 (B3) ankert float_text ZENTRIERT am Ereignispunkt (und
	# klemmt in die Elternfläche) — gemessen wird deshalb die Label-MITTE.
	var mitte := label.global_position + label.size * 0.5
	assert_almost(mitte.x, soll.x, 1.0, "Float-Text-Mitte sitzt horizontal am Treffer")
	assert_almost(mitte.y, soll.y, 1.0, "Float-Text-Mitte sitzt vertikal am Treffer")
	await _unmount(host)


func test_juice_ebene_folgt_dem_resize() -> void:
	var host := await _mount_host(Vector2i(1200, 700))
	var container: SubViewportContainer = host._viewport_container
	assert_ne(container, null, "Host hat das Spiel gemountet (Energie/Registry ok)")
	if container == null:
		await _unmount(host)
		return
	tree.root.size = Vector2i(700, 1100)
	tree.root.size_changed.emit()
	# Genug Frames, damit Relayout UND ein etwaiger GO-Shake (rebase_shake)
	# ihre Ruhelage gefunden haben.
	await wait_frames(12)
	var layer := host.juice.float_text_parent as Control
	assert_almost(layer.position.x, container.position.x, 0.5, "x folgt dem Resize")
	assert_almost(layer.position.y, container.position.y, 0.5, "y folgt dem Resize")
	assert_almost(layer.size.x, container.size.x, 0.5, "Breite folgt dem Resize")
	assert_almost(layer.size.y, container.size.y, 0.5, "Höhe folgt dem Resize")
	await _unmount(host)
