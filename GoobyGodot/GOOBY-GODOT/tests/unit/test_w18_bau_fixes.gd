extends TestCase
## W18 Bau-Fixes (Fix-Agent F4) — Wächter für drei Playtest-Befunde:
##
## 1. Ghost-Spawn (report_bau.md Befund 2): _begin_new spawnte blind in
##    der Grid-Mitte — im Leitformat quer lag der Bildschirmpunkt exakt
##    hinter der Aktions-Knopfleiste des Bau-Docks (Drag ab Spawn
##    verpuffte), hochkant auf belegten Zellen der Standard-Einrichtung.
##    Jetzt (BuildSpawnWahl): freie Zelle ab Raummitte, deren Punkt in
##    der sichtbaren freien Canvas-Zone liegt.
## 2. Sprechblasen (report_home.md E2/E7): AcBubble-Kapseln mit
##    mouse_filter=STOP fraßen Taps auf Primär-Knöpfe („Platzieren").
##    Jetzt: Blase + ALLE Kinder durchgängig IGNORE (reine Anzeige).
## 3. Ausweich-Logik: das Bau-Dock meldet sich als UiAnchors-Bottom-
##    Belegung an — Sprechblasen dodgen die Primär-Aktionszone.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Leitformat-Canvas quer/hochkant (Playtest-Kanvas des 2868x1320-Fensters).
const QUER := Vector2i(1564, 720)
const HOCH := Vector2i(720, 1564)

var _seq := 0
var _fenster_vorher := Vector2i.ZERO


func _fresh_gs(mit_bett_quest: bool) -> Node:
	_seq += 1
	var dir := "user://w18_tests/bau_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	# Ohne Bett-Quest: Flag setzen, sonst verweigert close() (korrekt).
	if not mit_bett_quest:
		HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _make_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	_fenster_ruecksetzen()


func _fenster_pinnen(groesse: Vector2i) -> void:
	if _fenster_vorher == Vector2i.ZERO:
		_fenster_vorher = tree.root.size
	tree.root.size = groesse
	await wait_frames(2)


func _fenster_ruecksetzen() -> void:
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		_fenster_vorher = Vector2i.ZERO


## Schluckt an dieser Canvas-Position ein sichtbares STOP-Control den
## Klick? (Spiegel der Playtest-Messung flow_baumodus._ui_verdeckt.)
func _ui_verdeckt(pos: Vector2) -> bool:
	for rect in BuildSpawnWahl.stop_rects(tree.root):
		if rect.has_point(pos):
			return true
	return false


# ── 1. Ghost-Spawn: freie Zelle, sichtbar, nicht hinterm Dock ────────────────


func test_ghost_spawn_quer_frei_und_nicht_ui_verdeckt() -> void:
	await _spawn_pruefen(QUER, "quer")


func test_ghost_spawn_hochkant_frei_und_nicht_ui_verdeckt() -> void:
	await _spawn_pruefen(HOCH, "hochkant")


## Bett-Quest-Autostart (voller Dock: Ghost + Action-Bar sichtbar) —
## der Spawn muss auf einer FREIEN Zelle liegen und sein Bildschirmpunkt
## (unter der Kamera-ENDPOSE) im Bild, außerhalb des Dock-Rects und von
## keinem STOP-Control verdeckt sein.
func _spawn_pruefen(groesse: Vector2i, kontext: String) -> void:
	await _fenster_pinnen(groesse)
	var gs := _fresh_gs(true)
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	var ghost: Variant = build.get("_ghost_state")
	var ghost_da: bool = ghost is Dictionary and not (ghost as Dictionary).is_empty()
	assert_true(ghost_da, "%s: Bett-Quest-Ghost ist aktiv" % kontext)
	if not ghost_da:
		await _cleanup(room, gs)
		return
	var g := ghost as Dictionary
	var def: Dictionary = g["def"]
	var at: Vector2i = g["at"]
	var frei: Dictionary = room.grid.can_place(def, at, int(g["rot"]), "")
	assert_true(
		bool(frei["ok"]),
		"%s: Spawn auf FREIER Zelle (at=%s, reason=%s)" % [kontext, at, frei.get("reason", "")]
	)
	# Endpose der Bau-Kamera abwarten (sie fliegt nach open() erst hin) —
	# gemessen wird wie im Playtest gegen die LIVE-Kamera.
	var kamera := room.get_viewport().get_camera_3d()
	var ziel: Transform3D = build.build_camera().ziel_transform()
	var angekommen := await wait_until(
		func() -> bool: return kamera.global_position.distance_to(ziel.origin) < 0.01, 15_000
	)
	assert_true(angekommen, "%s: Bau-Kamera erreicht die Endpose" % kontext)
	await wait_frames(2)
	var mount: Node3D = room.grid_mount()
	var welt := mount.to_global(GridData.world_center(at, def["footprint"], int(g["rot"])))
	var punkt := kamera.unproject_position(welt)
	var canvas := room.get_viewport().get_visible_rect()
	assert_true(canvas.has_point(punkt), "%s: Spawnpunkt im Bild (%s)" % [kontext, punkt])
	var dock := room.ui_layer().find_child("BauDock", true, false) as Control
	var action_bar := room.ui_layer().find_child("ActionBar", true, false) as Control
	assert_true(
		dock != null and dock.is_visible_in_tree(), "%s: Bau-Dock sichtbar (volles Dock)" % kontext
	)
	assert_true(
		action_bar != null and action_bar.is_visible_in_tree(),
		"%s: Aktions-Knopfleiste sichtbar (Ghost aktiv)" % kontext
	)
	if dock != null:
		assert_false(
			dock.get_global_rect().has_point(punkt),
			(
				"%s: Spawnpunkt NICHT im Dock-Rect (Punkt %s, Dock %s)"
				% [kontext, punkt, dock.get_global_rect()]
			)
		)
	assert_false(
		_ui_verdeckt(punkt),
		"%s: Spawnpunkt von keinem STOP-Control verdeckt (%s)" % [kontext, punkt]
	)
	await _cleanup(room, gs)


## Pure Kern-Suche: frei+sichtbar gewinnt; ohne sichtbare Kandidaten
## fällt die Wahl auf frei; Ringe wachsen ab der Mitte.
func test_spawn_wahl_pur_bevorzugt_frei_und_sichtbar() -> void:
	var grid_size := Vector2i(12, 10)
	var fp := Vector2i(2, 3)
	var mitte := Vector2i(grid_size.x / 2, grid_size.y / 2) - fp / 2
	var belegt: Dictionary = {mitte: true}
	var frei_check := func(at: Vector2i) -> bool: return not belegt.has(at)
	# Projektion: y-Zellen 0..4 „sichtbar" (Punkt 100), Rest hinterm Dock.
	var punkt_von := func(at: Vector2i) -> Vector2:
		return Vector2(100.0, 100.0) if at.y < 5 else Vector2(100.0, 900.0)
	var sicht := Rect2(0, 0, 1564, 720)
	var blocker: Array[Rect2] = [Rect2(0, 850, 1564, 200)]
	var wahl := BuildSpawnWahl.waehle(grid_size, fp, frei_check, punkt_von, sicht, blocker)
	assert_true(bool(frei_check.call(wahl)), "Wahl liegt auf freier Zelle")
	assert_true(wahl.y < 5, "Wahl liegt in der sichtbaren Zone")
	assert_ne(wahl, mitte, "belegte/verdeckte Mitte wird nicht gewählt")
	# Ohne jeden sichtbaren Kandidaten: nächste freie Zelle ab Mitte.
	var nie := func(_at: Vector2i) -> Vector2: return Vector2(-1.0, -1.0)
	var nur_frei := BuildSpawnWahl.waehle(grid_size, fp, frei_check, nie, sicht, blocker)
	assert_true(bool(frei_check.call(nur_frei)), "Fallback bleibt eine freie Zelle")
	# Ring-Geometrie: Ring 0 = Mitte, Ring 2 = 16 Zellen exakt auf Abstand 2.
	assert_eq(BuildSpawnWahl.ring_zellen(mitte, 0), [mitte] as Array[Vector2i], "Ring 0 = Mitte")
	var ring2 := BuildSpawnWahl.ring_zellen(mitte, 2)
	assert_eq(ring2.size(), 16, "Ring 2 hat 16 Zellen")
	for zelle in ring2:
		var d := zelle - mitte
		assert_eq(maxi(absi(d.x), absi(d.y)), 2, "Zelle %s liegt exakt auf Ring 2" % zelle)


# ── 2. Sprechblasen sind reine Anzeige (kein STOP) ───────────────────────────


func test_ac_bubble_hat_kein_stop_control() -> void:
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	for stil: String in [AcBubble.STIL_GOOBY, AcBubble.STIL_SYSTEM, AcBubble.STIL_WITZ]:
		var bubble := AcBubble.show_bubble(
			layer, "Platzier dein Bett! Gooby will kuscheln!", {"stil": stil, "dauer_s": 60.0}
		)
		await wait_frames(2)
		var stop_namen: Array[String] = []
		var stapel: Array[Node] = [bubble]
		while not stapel.is_empty():
			var aktuell: Node = stapel.pop_back()
			if aktuell is Control:
				if (aktuell as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
					stop_namen.append(str(aktuell.name))
			for kind in aktuell.get_children():
				stapel.append(kind)
		assert_eq(
			stop_namen.size(),
			0,
			"Blase (%s) ist reine Anzeige — STOP-Controls: %s" % [stil, stop_namen]
		)
		bubble.queue_free()
		await wait_frames(1)
	layer.queue_free()
	await wait_frames(1)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


# ── 3. Dock reserviert die Bottom-Zone, Blasen weichen aus ───────────────────


func test_dock_reserviert_bottom_zone_und_blase_weicht_aus() -> void:
	await _fenster_pinnen(QUER)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var gs := _fresh_gs(false)
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	var dock := room.ui_layer().find_child("BauDock", true, false) as Control
	assert_true(dock != null, "BauDock existiert")
	assert_true(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(dock),
		"Bau-Dock reserviert die Bottom-Zone im Baumodus"
	)
	# Blase OHNE Sprecher zielt unten-mittig — exakt auf die Dock-Zone:
	# die bestehende Ausweich-Logik muss sie ÜBER das Dock schieben.
	var bubble := AcBubble.show_bubble(
		room.ui_layer(), "Platzier dein Bett! Gooby will kuscheln!", {"dauer_s": 60.0}
	)
	await wait_frames(4)
	var kapsel := bubble.get_node("Kapsel") as Control
	var kapsel_rect := kapsel.get_global_rect()
	var dock_rect := dock.get_global_rect()
	assert_false(
		kapsel_rect.intersects(dock_rect),
		"Blase überlappt das Bau-Dock nicht (Blase %s, Dock %s)" % [kapsel_rect, dock_rect]
	)
	assert_true(
		kapsel_rect.end.y <= dock_rect.position.y + 0.5,
		(
			"Blase weicht ÜBER das Dock aus (Blase bis %s, Dock ab %s)"
			% [kapsel_rect.end.y, dock_rect.position.y]
		)
	)
	bubble.queue_free()
	await wait_frames(1)
	build.close()
	await wait_frames(1)
	assert_false(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(dock),
		"close() gibt die Bottom-Zone wieder frei"
	)
	await _cleanup(room, gs)
