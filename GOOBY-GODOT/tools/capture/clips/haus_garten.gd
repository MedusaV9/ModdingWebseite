extends "res://tools/capture/clip_driver.gd"
## Clip: HAUS-SICHT — das eigene Haus steht jetzt im Garten (GartenHaus:
## Außenmodell im gewählten Gestalten-Stil mit Dach, Schornstein, Briefkasten
## an der Fassade). Gooby läuft durch den Garten zur Haustür und winkt;
## die Kino-Kamera hebt sich langsam vom Beet zur Dachkante — man sieht,
## dass Garten und Haus EINE zusammenhängende Welt sind.
## Regie-Detail: Goobys Einzugs-/Wander-Skript läuft direkt nach dem Spawn —
## erst cancel_walk()+Wander aus, DANN (einen Tick später) der eigene Lauf,
## sonst stoppt das fremde walk_to-Await unseren Lauf gleich wieder.

var room: Node3D
var _tuer_x := 3.0


func _setup() -> void:
	duration = 9.0
	var packed: PackedScene = load("res://scenes/home/garten.tscn")
	room = packed.instantiate()
	room.stunde_override = 16.5
	add_child(room)
	schedule(0.2, _hud_aus)
	schedule(0.6, _regie)
	schedule(1.0, _lauf_zur_tuer)
	schedule(6.6, _winken)


func _hud_aus() -> void:
	for child in room.get_children():
		if child is CanvasLayer:
			child.visible = false


func _regie() -> void:
	var haus := room.get_node_or_null("GartenHaus")
	if haus != null and haus.has_method("tuer_welt_x"):
		_tuer_x = haus.tuer_welt_x()
	# Garten-Maße aus dem Grid (Zellen à 0,5 m); Fallback 8 m.
	var tiefe := 8.0
	var breite := 8.0
	var grid: Object = room.get("grid")
	if grid != null:
		tiefe = float(grid.size.y) * 0.5
		breite = float(grid.size.x) * 0.5
	var gooby: Node3D = room._gooby
	if gooby != null:
		gooby.set_wander_enabled(false)
		gooby.cancel_walk()
		gooby.global_position = Vector3(_tuer_x - 1.2, 0.0, tiefe * 0.7)
	# Kranfahrt: tief im Garten starten, langsam hoch — Dach + Schornstein
	# kommen ins Bild.
	var mitte_x := breite * 0.5
	cine_camera(
		Vector3(mitte_x - breite * 0.42, 0.9, tiefe + 1.6),
		Vector3(_tuer_x, 1.1, 0.0),
		52.0
	)
	move_camera(
		Vector3(mitte_x + breite * 0.34, 3.4, tiefe + 2.6),
		Vector3(_tuer_x - 0.5, 2.0, -2.4),
		duration - 1.2
	)


## Zur Tür laufen — bzw. zur ERREICHBAREN freien Zelle, die der Tür am
## nächsten liegt (die Beet-Zone kann den direkten Weg abschneiden; ein
## walk_to auf eine unerreichbare Zelle stoppt sonst sofort am Beetrand).
func _lauf_zur_tuer() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	var ziel := Vector3(_tuer_x, 0.0, 2.4)
	var grid: Object = room.get("grid")
	if grid != null:
		var von: Vector2i = gooby.current_cell()
		var ziel_zelle: Vector2i = GridData.cell_of(ziel)
		var beste := Vector2i(-1, -1)
		var beste_d := 1e9
		for cell: Vector2i in grid.free_cells():
			if not grid.is_reachable(von, cell):
				continue
			var d := Vector2(cell - ziel_zelle).length()
			if d < beste_d:
				beste_d = d
				beste = cell
		if beste.x >= 0:
			ziel = GridData.world_center(beste, Vector2i.ONE, 0)
			if room.has_method("grid_mount") and room.grid_mount() != null:
				ziel = room.grid_mount().to_global(ziel)
	print("[haus_garten] Lauf zu %s von %s" % [str(ziel), str(gooby.global_position)])
	# NICHT walk_to(): dessen Timeout ist WANDUHR-basiert (get_ticks_msec)
	# und läuft im Movie-Maker (1–6 fps Wandzeit) nach wenigen Frames ab.
	# _start_walking läuft ohne Timeout bis zur Ankunft (Wander ist aus).
	gooby.call("_start_walking", ziel)


func _winken() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	gooby.cancel_walk()
	if gooby.rig == null:
		return
	# Zur Kamera drehen (Rig-Vorwärts ist +Z bei rotation.y = 0).
	if _cine_cam != null:
		var richtung := _cine_cam.global_position - gooby.global_position
		var tween := create_tween()
		tween.tween_property(
			gooby.rig, "rotation:y", atan2(richtung.x, richtung.z), 0.35
		)
	gooby.rig.play_clip("wave")
	gooby.rig.set_emotion("happy")
