extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow (b) „Baumodus“: Boot → Onboarding → Baumodus über den HUD-Knopf
## öffnen → Kuschelbett aus der Lager-Karte nehmen (Umzugstag-Startlager)
## → GÜLTIGE freie Zelle antippen (Ghost springt zum Finger; ein Drag vom
## Ghost weg scheitert, weil der Spawn hinter der Aktions-Knopfleiste
## liegen kann — Pionier-Befund) → „Platzieren“ → prüfen, dass das Bett
## wirklich im Save liegt → „Fertig“ (Baumodus zu).
## Aufruf: tools/ci/run_playtest.sh flow_baumodus


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				{
					"name": "baumodus_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnBau",
					"erwarte": {"text": "Fertig"},
					"timeout_s": 45.0,
				},
				{"name": "bau_dock_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "bett_aus_lager_nehmen",
					"aktion": "tipp_falls_da",
					"text": "Kuschelbett",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{
					"name": "ghost_aktiv",
					"aktion": "warte_bis",
					"text": "Platzieren",
					"timeout_s": 20.0,
				},
				{
					"name": "ghost_auf_freie_zelle_tippen",
					"aktion": "tipp_pos",
					"pos_funktion": ziel_canvas_pos,
					"erwarte": {"bedingung": ghost_platzierbar},
					"timeout_s": 15.0,
				},
				{"name": "ghost_liegt", "aktion": "warte", "sekunden": 1.0},
				{
					"name": "platzieren",
					"aktion": "tipp_text",
					"text": "Platzieren",
					"timeout_s": 15.0,
				},
				{
					"name": "bett_im_save",
					"aktion": "warte_bis",
					"bedingung": bett_platziert,
					"timeout_s": 25.0,
				},
				{
					"name": "baumodus_fertig",
					"aktion": "tipp_text",
					"text": "Fertig",
					"erwarte": {"bedingung": bau_modus_zu},
					"timeout_s": 30.0,
				},
				{"name": "abschluss_wohnzimmer", "aktion": "warte", "sekunden": 2.0},
			]
		)
	)
	return liste


## BuildMode-Node des aktuellen Raums (RoomBase hängt ihn als "BuildMode" an).
func _build_mode() -> Node:
	var szene := aktuelle_szene()
	return szene.get_node_or_null("BuildMode") if szene != null else null


## Zielpunkt: gültige freie Zelle möglichst nah an der Raummitte (leicht
## außermittig, damit Gooby nicht verdeckt), deren Bildschirmpunkt NICHT
## von klick-schluckender UI (Dock-Knöpfe, Quest-Banner) verdeckt ist —
## der Tap muss als _unhandled_input beim Baumodus ankommen, dann springt
## der Ghost mit der Footprint-Mitte auf die getippte Zelle.
func ziel_canvas_pos() -> Vector2:
	var bm := _build_mode()
	var szene := aktuelle_szene()
	if bm == null or szene == null:
		return Vector2(1280, 720) * 0.5
	var ghost: Variant = bm.get("_ghost_state")
	if not (ghost is Dictionary) or (ghost as Dictionary).is_empty():
		return Vector2(1280, 720) * 0.5
	var def: Dictionary = ghost["def"]
	var grid: Object = szene.get("grid")
	var fp: Vector2i = def["footprint"]
	var mitte := Vector2(grid.size) * 0.5
	var beste_punkt := Vector2(-1.0, -1.0)
	var beste_d := 1.0e9
	for y in int(grid.size.y):
		for x in int(grid.size.x):
			var at := Vector2i(x, y)
			var d: float = Vector2(at).distance_to(mitte)
			if d <= 1.5 or d >= beste_d:
				continue
			if not bool(grid.can_place(def, at, 0, "")["ok"]):
				continue
			var punkt := _zelle_canvas(szene, at + fp / 2)
			if _ui_verdeckt(punkt):
				continue
			beste_d = d
			beste_punkt = punkt
	if beste_punkt.x < 0.0:
		return Vector2(1280, 720) * 0.5
	return beste_punkt


## Kann der Ghost an seiner AKTUELLEN Zelle wirklich platziert werden?
## (Nachbedingung des Zellen-Taps — sonst bleibt „Platzieren“ ausgegraut.)
func ghost_platzierbar() -> bool:
	var bm := _build_mode()
	var szene := aktuelle_szene()
	if bm == null or szene == null:
		return false
	var ghost: Variant = bm.get("_ghost_state")
	if not (ghost is Dictionary) or (ghost as Dictionary).is_empty():
		return false
	var g := ghost as Dictionary
	var grid: Object = szene.get("grid")
	var pruefung: Variant = grid.can_place(g["def"], g["at"], int(g["rot"]), str(g.get("uid", "")))
	return pruefung is Dictionary and bool((pruefung as Dictionary)["ok"])


## Schluckt an dieser Canvas-Position ein sichtbares Control den Klick?
## (mouse_filter STOP — Knöpfe, Karten-Panels; Labels/Container sind
## IGNORE und stören nicht.)
func _ui_verdeckt(pos: Vector2) -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control:
			var control := aktuell as Control
			if (
				control.is_visible_in_tree()
				and control.mouse_filter == Control.MOUSE_FILTER_STOP
				and control.get_global_rect().has_point(pos)
			):
				return true
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false


## Zellmitte (Boden) → Canvas-Pixel über die aktive (Bau-)Kamera.
func _zelle_canvas(szene: Node, zelle: Vector2i) -> Vector2:
	var lokal: Vector3 = GridData.world_center(zelle, Vector2i.ONE, 0)
	var mount: Node3D = szene.call("grid_mount")
	var welt := mount.to_global(lokal)
	var kamera := harness.root.get_camera_3d()
	if kamera == null:
		return Vector2(1280, 720) * 0.5
	return kamera.unproject_position(welt)


## Liegt das Kuschelbett nach dem Platzieren wirklich im Wohnzimmer-Save?
## (Format Doc D §1.4: home.rooms.<id>.items = [{"uid","item","at","rot"}].)
func bett_platziert() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	var eintraege: Variant = gs.get_value("home.rooms.living.items", [])
	if not (eintraege is Array):
		return false
	for eintrag: Variant in eintraege:
		if eintrag is Dictionary and str((eintrag as Dictionary).get("item", "")) == "bedSingle":
			return true
	return false


func bau_modus_zu() -> bool:
	var szene := aktuelle_szene()
	if szene == null or not szene.has_method("is_build_mode_active"):
		return false
	return not bool(szene.call("is_build_mode_active"))
