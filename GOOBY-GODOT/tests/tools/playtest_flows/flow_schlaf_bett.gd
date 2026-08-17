extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Schlaf/Bett“: Auf einem frischen Save liegt das Kuschelbett im
## Umzugs-Lager — wie ein Spieler erst über den Baumodus ins Wohnzimmer
## stellen (Schrittfolge aus flow_baumodus), dann das Bett antippen: die
## Nachtkarte („Bettzeit“) muss aufgehen. Mit vollen Start-Stats
## (Energie 90) müssen „Schlafen gehen“ AUSGEGRAUT sein + der Hinweis
## „…viel zu wach“ stehen; der Nickerchen-Eintrag muss KONSISTENT zu
## Sleep.can_nap sein (Energie sinkt live — bei Panel-Öffnung nach ~2 min
## steht sie schon bei ~89,6 < 90, der Eintrag ist dann ZU RECHT da; ein
## starrer „nie da“-Check scheiterte in Lauf schlaf03). Danach Gute-
## Nacht-Geschichte öffnen (Bücherregal), wieder zu, Nachtkarte über
## „Später“ schließen.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_schlaf_bett

const Sleep := preload("res://scripts/logic/sleep.gd")


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	(
		liste
		. append_array(
			[
				# „Was nun?"-Karte wegtippen (Befund heim01: Tap-Dieb).
				{
					"name": "was_nun_wegtippen",
					"aktion": "tipp_falls_da",
					"node": "WasNunSchliessen",
					"timeout_s": 8.0,
					"pflicht": false,
				},
				# ── Bett aus dem Lager platzieren (wie flow_baumodus) ──
				{
					"name": "baumodus_oeffnen",
					"aktion": "tipp_name",
					"node": "BtnBau",
					"erwarte": {"text": "Fertig"},
					"timeout_s": 45.0,
				},
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
				# Lauf schlaf01: die Bett-Quest-Sprechblase (AcBubble-Kapsel,
				# mouse_filter=STOP, höherer Layer) lag über dem „Platzieren"-
				# Knopf und FRASS den Tap — Bett blieb im Lager, alles danach
				# kaskadierte. Erst warten, bis die Kapsel weggeblendet ist.
				{
					"name": "platzieren_knopf_frei",
					"aktion": "warte_bis",
					"bedingung": platzieren_frei,
					"timeout_s": 30.0,
				},
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
				{"name": "raum_beruhigen", "aktion": "warte", "sekunden": 3.0},
				# ── Nachtkarte am Bett ──
				# Lauf schlaf02: die Kamera folgt dem wandernden Gooby — das
				# Bett rutschte an den unteren Bildrand HINTER den „Wo ist
				# mein Gooby?"-Chip, der Tap traf den Chip statt des Betts.
				# Erst warten, bis der projizierte Bett-Punkt frei liegt.
				{
					"name": "bett_frei_im_bild",
					"aktion": "warte_bis",
					"bedingung": bett_tapbar,
					"timeout_s": 90.0,
				},
				{
					"name": "bett_antippen",
					"aktion": "tipp_3d",
					"finder": finde_moebel.bind("bedSingle"),
					"offset": Vector3(0.0, 0.5, 0.0),
					"erwarte": {"text": "Bettzeit"},
					"timeout_s": 45.0,
				},
				{"name": "nachtkarte_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "schlafen_ausgegraut",
					"aktion": "tue",
					"funktion": schlafen_knopf_gesperrt,
					"erwartung": "'Schlafen gehen' disabled bei Energie 90 (can_sleep < 70)",
				},
				{
					"name": "wach_hinweis_da",
					"aktion": "warte_bis",
					"text": "viel zu wach",
					"timeout_s": 10.0,
				},
				{
					"name": "nickerchen_konsistent",
					"aktion": "tue",
					"funktion": nickerchen_konsistent,
					"erwartung":
					"Nickerchen-Eintrag genau dann da, wenn Sleep.can_nap (Energie < 90)",
				},
				# ── Geschichten-Stunde ──
				{
					"name": "geschichte_oeffnen",
					"aktion": "tipp_text",
					"text": "Gute-Nacht-Geschichte",
					"erwarte": {"text": "Bücherregal"},
					"timeout_s": 30.0,
				},
				{"name": "buecherregal_ansehen", "aktion": "warte", "sekunden": 2.0},
				{
					"name": "geschichte_schliessen",
					"aktion": "taste",
					"keycode": KEY_ESCAPE,
					"erwarte": {"weg_text": "Bücherregal"},
					"timeout_s": 20.0,
				},
				# Zurück auf der Nachtkarte? Dann über „Später" schließen.
				{
					"name": "nachtkarte_schliessen",
					"aktion": "tipp_falls_da",
					"text": "Später",
					"timeout_s": 10.0,
					"pflicht": false,
				},
				{
					"name": "nachtkarte_weg",
					"aktion": "warte_bis",
					"weg_text": "Bettzeit",
					"timeout_s": 20.0,
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


## Zielpunkt: gültige freie Zelle nahe der Raummitte, nicht UI-verdeckt
## (übernommen aus flow_baumodus — dort ausführlich dokumentiert).
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


func _zelle_canvas(szene: Node, zelle: Vector2i) -> Vector2:
	var lokal: Vector3 = GridData.world_center(zelle, Vector2i.ONE, 0)
	var mount: Node3D = szene.call("grid_mount")
	var welt := mount.to_global(lokal)
	var kamera := harness.root.get_camera_3d()
	if kamera == null:
		return Vector2(1280, 720) * 0.5
	return kamera.unproject_position(welt)


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


## true, sobald der projizierte Bett-Mittelpunkt (+0,5 hoch) mit Rand im
## Bild liegt und kein STOP-Control (Chip/Karte/Blase) ihn überdeckt —
## sonst frisst z. B. der „Wo ist mein Gooby?"-Chip den Tap (Lauf schlaf02).
func bett_tapbar() -> bool:
	var bett: Variant = finde_moebel("bedSingle")
	if not (bett is Node3D):
		return false
	var kamera := harness.root.get_camera_3d()
	if kamera == null:
		return false
	var welt: Vector3 = (bett as Node3D).global_position + Vector3(0.0, 0.5, 0.0)
	if kamera.is_position_behind(welt):
		return false
	var punkt := kamera.unproject_position(welt)
	var groesse := Vector2(harness.root.get_visible_rect().size)
	var rand := 48.0
	if punkt.x < rand or punkt.y < rand or punkt.x > groesse.x - rand or punkt.y > groesse.y - rand:
		return false
	return not _ui_verdeckt(punkt)


## true, sobald der „Platzieren"-Knopf sichtbar ist und KEINE Sprechblasen-
## Kapsel (AcBubble, mouse_filter=STOP auf höherem CanvasLayer) seine Mitte
## überdeckt — sonst frisst die Kapsel den synthetischen Tap (Lauf schlaf01).
func platzieren_frei() -> bool:
	var knopf := _finde_knopf_mit_text(harness.root, "Platzieren")
	return knopf != null and not _blase_ueber(knopf.get_global_rect().get_center())


## Liegt eine sichtbare AcBubble-Kapsel über dem Punkt? (Nur Blasen zählen —
## _ui_verdeckt würde auch den Zielknopf selbst treffen.)
func _blase_ueber(pos: Vector2) -> bool:
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is AcBubble and (aktuell as Control).is_visible_in_tree():
			var unter: Array[Node] = [aktuell]
			while not unter.is_empty():
				var teil: Node = unter.pop_back()
				if (
					teil is Control
					and (teil as Control).mouse_filter == Control.MOUSE_FILTER_STOP
					and (teil as Control).get_global_rect().has_point(pos)
				):
					return true
				for kind in teil.get_children():
					unter.append(kind)
			continue
		for kind in aktuell.get_children():
			stapel.append(kind)
	return false


## „Schlafen gehen" muss bei voller Energie sichtbar, aber gesperrt sein.
func schlafen_knopf_gesperrt() -> bool:
	var knopf := _finde_knopf_mit_text(harness.root, "Schlafen gehen")
	return knopf != null and knopf.disabled


## REST-3-Konsistenz: der Nickerchen-Eintrag muss GENAU dann sichtbar sein,
## wenn Sleep.can_nap es erlaubt — Energie fällt live unter die 90er-Marke.
func nickerchen_konsistent() -> bool:
	var gs := game_state()
	if gs == null or not gs.has_method("state"):
		return false
	var flat: Dictionary = Sleep.flat_of(gs.call("state"))
	var knopf := _finde_knopf_mit_text(harness.root, "Nickerchen")
	return (knopf != null) == Sleep.can_nap(flat)


func _finde_knopf_mit_text(node: Node, text: String) -> BaseButton:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is BaseButton:
			if str(aktuell.get("text")).to_lower().contains(nadel):
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null
