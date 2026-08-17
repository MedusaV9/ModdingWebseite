class_name GvzStageFeed
extends RefCounted
## Bühnen-Feed der GvZ-Spielszene (G5/P26-Split, Muster gvz_hud.gd):
## übersetzt den PUREN Sim-State (GvzLogic) jeden Frame in Canvas-Pixel-
## Anker für die 3D-Bühne (gvz_stage3d.gd). Reines MAPPING ohne eigenen
## Zustand — deshalb statisch; `view` ist gvz_game.gd (Duck-Typing wie im
## HUD: liefert Layout-Helfer, state und die Netz-Ghost-Vorprüfung).


## Jeden Frame: den kompletten Sim-Zustand als Canvas-Pixel-Anker zur Bühne.
static func sync(view, delta: float) -> void:
	var stage: Node3D = view._stage
	if stage == null or not stage.visible or (view.state as Dictionary).is_empty():
		return
	var state: Dictionary = view.state
	var field: Rect2 = view._field_rect()
	var cell: Vector2 = view._cell_size()
	var tick := int(state["tick"])
	var fog_mm: int = (
		view._fog_start_mm() if int(view._fog_cols()) > 0 else GvzLogic.COLS * GvzLogic.CELL_MM * 2
	)
	var towers: Array = []
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		towers.append(
			{"key": key, "type": tower["type"], "lane": tower["lane"], "col": tower["col"]}
		)
	var zombies: Array = []
	for zombie: Dictionary in state["zombies"]:
		if bool(zombie["dead"]):
			continue
		(
			zombies
			. append(
				{
					"id": zombie["id"],
					"type": zombie["type"],
					"lane": zombie["lane"],
					"px": _lane_px(view, int(zombie["lane"]), int(zombie["x"]), field, cell),
					"hidden": int(zombie["x"]) >= fog_mm,
					"dig": str(zombie.get("state", "walk")) == "dig",
					"flying": bool(zombie.get("flying", false)),
					"armor": int(zombie.get("armor_hp", 0)) > 0,
					"raged": bool(zombie.get("raged", false)),
					"slow": int(zombie.get("slow_until", 0)) > tick,
					# HP für den Trefferblitz der Bühne (Abfall = Treffer).
					"hp": int(zombie["hp"]) + int(zombie.get("armor_hp", 0)),
				}
			)
		)
	var boss_data := {}
	var boss: Dictionary = state["boss"]
	if not boss.is_empty() and int(boss["hp"]) > 0 and int(boss["x"]) < fog_mm:
		boss_data = {
			"px": _lane_px(view, int(boss["lane"]), int(boss["x"]), field, cell),
			"lane": boss["lane"],
			"phase": boss.get("phase", 1),
		}
	var projectiles: Array = []
	for proj: Dictionary in state["projectiles"]:
		if int(proj["x"]) >= fog_mm:
			continue
		(
			projectiles
			. append(
				{
					"kind": proj["kind"],
					"lane": proj["lane"],
					"px": _lane_px(view, int(proj["lane"]), int(proj["x"]), field, cell),
				}
			)
		)
	var drops: Array = []
	for drop: Dictionary in state["drops"]:
		(
			drops
			. append(
				{
					"id": drop["id"],
					"lane": drop["lane"],
					"px": view._cell_center(int(drop["lane"]), int(drop["col"])),
				}
			)
		)
	var mowers: Array = []
	for lane: Variant in state["mowers"]:
		var mower: Dictionary = state["mowers"][lane]
		var px := Vector2(view.MOWER_GUTTER * 0.5, field.position.y + (int(lane) + 0.5) * cell.y)
		if bool(mower["active"]):
			px.x = view._x_to_px(int(mower["x"]))
		(
			mowers
			. append(
				{
					"lane": int(lane),
					"active": mower["active"],
					"used": mower["used"],
					"px": px,
				}
			)
		)
	(
		stage
		. sync(
			{
				"tick": tick,
				"towers": towers,
				"zombies": zombies,
				"boss": boss_data,
				"projectiles": projectiles,
				"drops": drops,
				"mowers": mowers,
				"ghost": _ghost(view),
			},
			delta
		)
	)


## Drag-Ghost fürs Zellen-Highlight: grün = Aktion erlaubt (lokal can_place,
## Netz-Zombie-Seite can_spawn — die Sim-Gates entscheiden endgültig).
static func _ghost(view) -> Dictionary:
	if not bool(view.dragging) or view.selected_card == "" or view.selected_card == "shovel":
		return {}
	var at: Vector2i = view._cell_at(view.drag_pos)
	if at.x < 0:
		return {}
	var card := str(view.selected_card)
	var ok := true
	if bool(view._netz_zombie()):
		ok = bool(view._netz.can_spawn(card, at.y)["ok"])
	else:
		ok = bool(GvzLogic.can_place(view.state, card, at.y, at.x)["ok"])
	return {"lane": at.y, "col": at.x, "ok": ok}


## Boden-Anker (Canvas-Pixel) eines Sim-x auf der Bahnmitte.
static func _lane_px(view, lane: int, x_mm: int, field: Rect2, cell: Vector2) -> Vector2:
	return Vector2(view._x_to_px(x_mm), field.position.y + (float(lane) + 0.5) * cell.y)
