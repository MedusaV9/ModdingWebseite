extends TestCase
## W20 P2 „Baumodus-Cockpit“ — Wächter für die UI-Rework-Befunde A1/D5/E7
## (befunde.md Welle 2): Lager-Karte/„Fertig“ überlappten die Kamera-Chips
## „⟲90°/90°⟳“ im Leitformat MIT Geräte-Metriken (4 maschinelle
## Overlap-Paare des FB3-Audits — die Playtest-Screenshots ohne
## screen_scale/Insets untertrieben die Geräte-Enge um ~40 %).
##
## Matrix: BEIDE Leitformate (iPhone 17 Pro Max quer/hoch, screen_scale
## 3,0 + Dynamic-Island-Insets via UiScale-Overrides) × alle Bau-Zustände
## (Basis ohne Werkzeug / neuer Ghost / Möbel aufgenommen / Girlanden-
## Spann-Flow). Pro Zelle: paarweise Knopf-Disjunktheit (Spiegel der
## FB3-overlap-Messung), Kamera-Spalte × Dock disjunkt, Safe-Area,
## Tippziel-Floor ≥ 44 pt physisch. Dazu der dock_zone()/aktive_zone()-
## Vertrag (Sperrzonen-Schnittstelle für die P1-Lanes, Datei-Kopf von
## build_ui_dock.gd) und die pure Flow-Umbruch-Schätzung.
##
## BLOCKER-Nachfix (Live-Desktop-Demo 1434x660, „Fertig reagiert nicht“):
## Die Rechteck-Matrix prüft Disjunktheit, aber nicht die HIT-Reihenfolge —
## deshalb zusätzlich pro Canvas-Größe (Leitformate + Desktop-Demo-Format):
## Fertig/Platzieren/Abbrechen sind am eigenen Mittelpunkt das OBERSTE
## Control (synthetische Maus + gui_get_hovered_control — ein fremdes
## STOP-Control darüber würde den Klick fressen), plus Klick-Gegenprobe
## end-zu-end. Dazu die beiden Demo-Wurzeln: close() verweigert bei
## aktiver Bett-Quest SICHTBAR (Bett-Geist startet neu statt „toter
## Knopf“, build_mode.gd) und eine offene Tür-/Blockade-Karte (_choice)
## räumt beim Baumodus-Öffnen weg (room_base.gd — sie fraß bei 1434x660
## die Platzieren-Klicks der Action-Bar).
##
## VIDEO-REVIEW-Nachfix (P2c, Live-Demo 1434x660@1x, 0:23–0:28): Action-Bar
## und Ebenen-Zeile stapelten sich als ZWEI gleichzeitige Knopf-Zeilen
## (Repro-Rects Action y 390–454 direkt über Ebenen y 464–516). Die Matrix
## prüft deshalb zusätzlich pro Zelle: die Dock-Zeilen (Action-Bar /
## Ebenen-Zeile / Lager-Karte / Kamera-Spalte) sind als GANZE Flächen
## paarweise disjunkt UND Action-Bar/Ebenen-Zeile sind nie gleichzeitig
## sichtbar (Choreographie: die Ebenen-Zeile duckt sich, solange die
## Action-Bar offen ist, und kommt danach zurück — set_action_bar_offen
## in build_ui_dock.gd). 1434x660@1x läuft als DRITTE Matrix-Größe mit.
##
## FLACKER-Nachfix (P2d, Video-Review 00:43/01:16): die Matrix prüft den
## EINGESCHWUNGENEN Zustand — ein transientes Stapel-Fenster rutschte
## durch. Wurzel: open() STELLTE den Zeilen-Zustand nicht her, sondern
## erbte ihn (ohne Quest-Geist lief nie _update_action_bar — hing der
## Bau-Default an, stapelten beide Zeilen bis zur ersten Werkzeug-Aktion).
## Deshalb frame-genaue Stapel-Wache: über N Frames nach JEDEM
## Zustands-Wechsel (öffnen ohne/mit Bett-Quest, Drawer-Chip, Abbrechen,
## Move, Girlande, Verweigerungs-Neustart) sind NIE beide Zeilen sichtbar.
##
## W21 P2 „Welt zuerst“: das Lager ist jetzt ein KontextDock (startet
## eingeklappt, Action-Bar lebt IN der Lager-Karte statt als eigene
## Dock-Zeile) — die Zeilen-Disjunktheit überspringt deshalb Ahnen-Paare,
## und nach Abbrechen klappt das BLATT auf (Stöber-Einladung; die
## Ebenen-Zeile duckt sich unter dem offenen Blatt — Choreographie-Wache
## in test_w21_bau_welt.gd). Schutzintention unverändert: nie zwei
## konkurrierende Knopf-Zeilen gleichzeitig.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Leitformate [Fenster-px, screen_scale, Insets in PUNKTEN [l, t, r, b]]
## — Werte wie fb3_ui_audit.SIZES (Dynamic-Island-Klasse).
const LEIT_QUER: Array = [Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]]
const LEIT_HOCH: Array = [Vector2i(1320, 2868), 3.0, [0.0, 59.0, 0.0, 34.0]]
## Desktop-Demo-Format des Blocker-Reports: kleines Fenster, f≈1, ohne
## Insets (PLAYTEST_DEVICE_METRICS=0-Situation).
const DESKTOP_KLEIN: Array = [Vector2i(1434, 660), 1.0, [0.0, 0.0, 0.0, 0.0]]
const MIN_TAP_PT := 44.0
const TAP_TOLERANZ_PT := 0.5
## Wie fb3_ui_audit._run_checks: Schnittflächen > 4×4 px zählen als Overlap.
const OVERLAP_TOLERANZ := 4.0

var _seq := 0
var _fenster_vorher := Vector2i.ZERO
var _canvas := Vector2.ZERO
var _safe_rect := Rect2()
var _px_per_pt := 1.0

# ── Aufbau-/Abbau-Helfer (Muster test_w18_bau_fixes + uiscale_conformance) ───


func _fresh_gs(mit_bett_quest := false) -> Node:
	_seq += 1
	var dir := "user://w20_tests/bau_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	# Bett-Quest default aus: die Zustands-Matrix steuert Ghost/Girlande
	# selbst, und close() darf am Testende nicht verweigern. Der
	# Verweigerungs-Test (Blocker-Nachfix) lässt die Quest bewusst AN.
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
	if room != null:
		room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	await _unpin_format()


## Fenster + Geräte-Metriken deterministisch pinnen (Muster
## test_fb3_uiscale_conformance._pin_format) — VOR dem Szenen-Bau.
func _pin_format(format: Array) -> void:
	if _fenster_vorher == Vector2i.ZERO:
		_fenster_vorher = tree.root.size
	var win: Vector2i = format[0]
	var scale := float(format[1])
	UiScale.screen_scale_override = scale
	DisplayServer.window_set_size(win)
	tree.root.size = win
	await wait_frames(2)
	_canvas = Vector2(tree.root.get_visible_rect().size)
	var pt_kurz := minf(float(win.x), float(win.y)) / scale
	_px_per_pt = minf(_canvas.x, _canvas.y) / pt_kurz
	var insets_pt: Array = format[2]
	var l := float(insets_pt[0]) * _px_per_pt
	var t := float(insets_pt[1]) * _px_per_pt
	var r := float(insets_pt[2]) * _px_per_pt
	var b := float(insets_pt[3]) * _px_per_pt
	_safe_rect = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	UiScale.insets_override = Rect2(_safe_rect)
	await wait_frames(1)


func _unpin_format() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		DisplayServer.window_set_size(_fenster_vorher)
		_fenster_vorher = Vector2i.ZERO
	await wait_frames(2)


# ── Mess-Helfer (Spiegel von fb3_ui_audit) ───────────────────────────────────


## Sichtbare Knöpfe des Bau-UIs (Dock + Kamera-Spalte + Action-Bar).
func _sichtbare_knoepfe(bau_ui: Control) -> Array[Control]:
	var out: Array[Control] = []
	for node in bau_ui.find_children("*", "Button", true, false):
		var knopf := node as Control
		if knopf.is_visible_in_tree():
			out.append(knopf)
	return out


## Rect nach Clipping durch Ahnen (ScrollContainer/clip_contents) —
## gescrollte Lager-Chips zählen nur mit ihrem sichtbaren Teil.
func _effective_rect(ctl: Control) -> Rect2:
	var rect := ctl.get_global_rect()
	var node: Node = ctl.get_parent()
	while node != null and node is Control:
		var parent := node as Control
		if parent.clip_contents or parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return Rect2()
		node = parent.get_parent()
	return rect


## Alle Disjunktheits-/Safe-/Tap-Proben EINER Matrix-Zelle.
func _pruefe_zustand(build: BuildMode, kontext: String) -> void:
	var dock_ui: BuildUiDock = build._dock_ui
	var knoepfe := _sichtbare_knoepfe(build._ui)
	assert_true(knoepfe.size() >= 8, "%s: Bau-Knöpfe gefunden (%d)" % [kontext, knoepfe.size()])
	var canvas_rect := Rect2(Vector2.ZERO, _canvas)
	for knopf in knoepfe:
		var rect := _effective_rect(knopf)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		assert_true(
			canvas_rect.grow(1.0).encloses(rect),
			"%s: %s läuft aus dem Canvas: %s" % [kontext, knopf.name, rect]
		)
		assert_true(
			_safe_rect.grow(2.0).encloses(rect),
			"%s: %s ragt aus dem sicheren Bereich: %s" % [kontext, knopf.name, rect]
		)
		if knopf is Button and not (knopf as Button).disabled:
			var eigen := knopf.get_global_rect()
			var kurz_pt := minf(eigen.size.x, eigen.size.y) / _px_per_pt
			assert_true(
				kurz_pt >= MIN_TAP_PT - TAP_TOLERANZ_PT,
				"%s: %s Tippfläche %.1f pt < %d pt" % [kontext, knopf.name, kurz_pt, MIN_TAP_PT]
			)
	for i in knoepfe.size():
		for j in range(i + 1, knoepfe.size()):
			if knoepfe[i].is_ancestor_of(knoepfe[j]) or knoepfe[j].is_ancestor_of(knoepfe[i]):
				continue
			var schnitt := _effective_rect(knoepfe[i]).intersection(_effective_rect(knoepfe[j]))
			assert_false(
				schnitt.size.x > OVERLAP_TOLERANZ and schnitt.size.y > OVERLAP_TOLERANZ,
				(
					"%s: Overlap %s(%s) × %s(%s): %s"
					% [
						kontext,
						knoepfe[i].name,
						(knoepfe[i] as Button).text,
						knoepfe[j].name,
						(knoepfe[j] as Button).text,
						schnitt,
					]
				)
			)
	# Kamera-Spalte × Dock als GANZE Flächen (Befund A1: die Rotations-
	# Chips verschwanden HINTER der Lager-Karte — Panels sind keine Knöpfe).
	var kamera_rect := dock_ui.kamera_leiste.get_global_rect()
	var dock_rect := dock_ui.dock.get_global_rect()
	var flaechen_schnitt := kamera_rect.intersection(dock_rect)
	assert_false(
		flaechen_schnitt.size.x > 1.0 and flaechen_schnitt.size.y > 1.0,
		(
			"%s: Kamera-Spalte überlappt das Dock (Kamera %s, Dock %s)"
			% [kontext, kamera_rect, dock_rect]
		)
	)
	# P2c (Video-Review): ALLE Dock-Zeilen paarweise flächen-disjunkt —
	# Action-Bar × Ebenen-Zeile × Lager-Karte × Kamera-Spalte. W21: die
	# Action-Bar lebt jetzt IN der Lager-Karte (KontextDock-Zeile) —
	# Ahnen-Paare sind Verschachtelung, kein Overlap-Befund.
	var zeilen: Array[Control] = [
		dock_ui.action_bar, dock_ui.ebenen_leiste, dock_ui.drawer, dock_ui.kamera_leiste
	]
	for i in zeilen.size():
		for j in range(i + 1, zeilen.size()):
			if not zeilen[i].is_visible_in_tree() or not zeilen[j].is_visible_in_tree():
				continue
			if zeilen[i].is_ancestor_of(zeilen[j]) or zeilen[j].is_ancestor_of(zeilen[i]):
				continue
			var zs := zeilen[i].get_global_rect().intersection(zeilen[j].get_global_rect())
			assert_false(
				zs.size.x > 1.0 and zs.size.y > 1.0,
				"%s: Zeilen-Overlap %s × %s: %s" % [kontext, zeilen[i].name, zeilen[j].name, zs]
			)
	# P2c-Choreographie: Action-Bar und Ebenen-Zeile stapeln sich NIE —
	# genau der Video-Befund (beide Zeilen gleichzeitig sichtbar).
	assert_false(
		dock_ui.action_bar.is_visible_in_tree() and dock_ui.ebenen_leiste.is_visible_in_tree(),
		"%s: Action-Bar und Ebenen-Zeile gleichzeitig sichtbar (Stapel)" % kontext
	)


# ── 1. Disjunktheits-Matrix: Bau-Zustände × Leitformate (Geräte-Metriken) ────


func test_disjunkt_matrix_leitformat_quer() -> void:
	await _matrix_pruefen(LEIT_QUER, "quer_2868x1320")


func test_disjunkt_matrix_leitformat_hoch() -> void:
	await _matrix_pruefen(LEIT_HOCH, "hoch_1320x2868")


## P2c: das Video-Format der Live-Demo als DRITTE Matrix-Größe — die
## Zwischen-Größe fing den Action-Bar×Ebenen-Stapel, den die Leitformate
## nicht zeigten.
func test_disjunkt_matrix_desktop_klein() -> void:
	await _matrix_pruefen(DESKTOP_KLEIN, "desktop_1434x660")


func _matrix_pruefen(format: Array, label: String) -> void:
	await _pin_format(format)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(3)
	var dock_ui: BuildUiDock = build._dock_ui
	# Zustand 1: Basis (kein Werkzeug — Action-Bar versteckt).
	assert_true(dock_ui.ebenen_leiste.visible, "%s: Basis zeigt die Ebenen-Zeile" % label)
	_pruefe_zustand(build, "%s/basis" % label)
	# Zustand 2: neues Werkzeug aus dem Lager (Ghost, „mode: new“ —
	# Drehen/Platzieren/Abbrechen sichtbar, Ebenen-Zeile duckt sich).
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await wait_frames(3)
	assert_true(build._action_bar.visible, "%s: Action-Bar sichtbar (Ghost)" % label)
	_pruefe_zustand(build, "%s/geist_neu" % label)
	build._cancel_ghost()
	await wait_frames(2)
	# P2c→W21: nach Abbrechen kommt die Griff-Zeile zurück und das Blatt
	# klappt auf (Stöber-Einladung) — die Ebenen-Zeile duckt sich unterm
	# offenen Blatt (Choreographie-Detail in test_w21_bau_welt.gd).
	assert_true(dock_ui.griff_zeile.visible, "%s: Griff-Zeile kehrt zurück" % label)
	assert_false(dock_ui.lager_eingeklappt(), "%s: Blatt klappt nach Abbrechen auf" % label)
	# Zustand 3: bestehendes Möbel aufgenommen („mode: move“ — volle
	# Action-Bar inkl. Einlagern).
	var items := room.grid.to_items_array()
	assert_true(items.size() > 0, "%s: Standard-Einrichtung vorhanden" % label)
	if items.size() > 0:
		build._begin_move(str(items[0]["uid"]))
		await wait_frames(3)
		_pruefe_zustand(build, "%s/geist_move" % label)
		build._cancel_ghost()
		await wait_frames(2)
	# Zustand 4: Girlanden-Spann-Flow (Decken-Ebene, nur Abbrechen).
	build._begin_new(FurnitureCatalog.def("girlande_wimpel"))
	await wait_frames(3)
	_pruefe_zustand(build, "%s/girlande" % label)
	build._on_abbrechen()
	await wait_frames(2)
	build.close()
	await _cleanup(room, gs)


# ── 2. dock_zone()/aktive_zone()-Vertrag (P1-Sperrzonen-Schnittstelle) ───────


func test_dock_zone_vertrag_fuer_p1_lanes() -> void:
	await _pin_format(LEIT_QUER)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	# Vor dem Öffnen: Dock unsichtbar → keine Sperrzone.
	assert_eq(BuildUiDock.aktive_zone(), Rect2(), "zu: aktive_zone() ist leer")
	build.open()
	await wait_frames(3)
	var dock_ui: BuildUiDock = build._dock_ui
	var zone := dock_ui.dock_zone()
	assert_true(zone.size.y > 0.0, "offen: dock_zone() liefert eine Zone")
	assert_eq(BuildUiDock.aktive_zone(), zone, "offen: aktive_zone() == dock_zone()")
	var dock_rect := dock_ui.dock.get_global_rect()
	assert_true(
		zone.grow(1.0).encloses(dock_rect),
		"Zone umfasst das Live-Dock (Zone %s, Dock %s)" % [zone, dock_rect]
	)
	assert_true(
		zone.end.y <= _canvas.y - _safe_rect.position.y + 0.5,
		"Zone endet über dem Home-Indicator (%.1f)" % zone.end.y
	)
	# VOLLE Ausbaustufe: Ghost einblenden — die Action-Bar muss schon in
	# der vorab gemeldeten Zone liegen (W18 Befund 2, kein Zonen-Sprung).
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await wait_frames(3)
	var action_rect: Rect2 = build._action_bar.get_global_rect()
	assert_true(
		zone.grow(1.0).encloses(action_rect),
		"Action-Bar liegt in der VOLLEN Zone (Zone %s, Bar %s)" % [zone, action_rect]
	)
	build._cancel_ghost()
	await wait_frames(1)
	build.close()
	await wait_frames(1)
	assert_eq(BuildUiDock.aktive_zone(), Rect2(), "geschlossen: aktive_zone() wieder leer")
	await _cleanup(room, gs)


# ── 3. Pure Flow-Umbruch-Schätzung (Basis der Kamera-Klemme) ─────────────────


func test_flow_umbruch_hoehe_pur() -> void:
	var minima: Array[Vector2] = [Vector2(100, 50), Vector2(100, 50), Vector2(100, 50)]
	assert_almost(
		BuildUiDock.flow_umbruch_hoehe(minima, 400.0, 10.0, 6.0),
		50.0,
		0.001,
		"alles passt in eine Zeile"
	)
	assert_almost(
		BuildUiDock.flow_umbruch_hoehe(minima, 220.0, 10.0, 6.0),
		106.0,
		0.001,
		"Umbruch nach 2 Kindern: 50 + 6 + 50"
	)
	assert_almost(
		BuildUiDock.flow_umbruch_hoehe(minima, 90.0, 10.0, 6.0),
		162.0,
		0.001,
		"jedes Kind eine eigene Zeile"
	)
	assert_almost(
		BuildUiDock.flow_umbruch_hoehe([] as Array[Vector2], 400.0, 10.0, 6.0),
		0.0,
		0.001,
		"leerer Flow = 0"
	)
	var gemischt: Array[Vector2] = [Vector2(60, 80), Vector2(200, 40)]
	assert_almost(
		BuildUiDock.flow_umbruch_hoehe(gemischt, 300.0, 10.0, 6.0),
		80.0,
		0.001,
		"Zeilenhöhe = höchstes Kind"
	)


# ── 4. Hit-Reihenfolge (Blocker-Nachfix): Knöpfe sind an ihrem Punkt oben ────
# Synthetische Maus wie die Playtest-Harness (_tippe_canvas): Events tragen
# FENSTER-px, GUI-Rects liegen im Canvas-Raum.


func _fenster_px(canvas_pos: Vector2) -> Vector2:
	return canvas_pos * (Vector2(tree.root.size) / _canvas)


## Maus auf den Canvas-Punkt bewegen und das oberste GUI-Ziel dort melden
## (Godots ECHTE Hit-Reihenfolge inkl. CanvasLayer/Clipping/mouse_filter).
func _oberstes_control(canvas_pos: Vector2) -> Control:
	var px := _fenster_px(canvas_pos)
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	Input.parse_input_event(ev)
	await wait_frames(2)
	return tree.root.gui_get_hovered_control()


## Voller synthetischer Klick (runter + hoch) auf einen Canvas-Punkt.
func _klick(canvas_pos: Vector2) -> void:
	var px := _fenster_px(canvas_pos)
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = px
	runter.global_position = px
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	await wait_frames(2)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = px
	hoch.global_position = px
	Input.parse_input_event(hoch)
	await wait_frames(2)


## Kern-Assertion: der Knopf ist an seinem Mittelpunkt das OBERSTE Control —
## läge ein fremdes STOP-Control darüber, wäre ES das Hover-Ziel und würde
## den Klick fressen (genau der Blocker-Verdacht der Live-Demo).
func _knopf_obenauf(knopf: Button, kontext: String) -> void:
	var mitte := knopf.get_global_rect().get_center()
	var oben := await _oberstes_control(mitte)
	var ok := oben == knopf or (oben != null and knopf.is_ancestor_of(oben))
	var oben_pfad := str(oben.get_path()) if oben != null else "<nichts>"
	assert_true(
		ok,
		(
			"%s: oberstes Control an %s ist %s statt %s(%s)"
			% [kontext, mitte, oben_pfad, knopf.name, knopf.text]
		)
	)


func test_hit_reihenfolge_leitformat_quer() -> void:
	await _hit_reihenfolge_pruefen(LEIT_QUER, "quer_2868x1320@3x")


func test_hit_reihenfolge_desktop_klein() -> void:
	await _hit_reihenfolge_pruefen(DESKTOP_KLEIN, "desktop_1434x660@1x")


func test_hit_reihenfolge_leitformat_hoch() -> void:
	await _hit_reihenfolge_pruefen(LEIT_HOCH, "hoch_1320x2868@3x")


func _hit_reihenfolge_pruefen(format: Array, label: String) -> void:
	await _pin_format(format)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(3)
	var dock_ui: BuildUiDock = build._dock_ui
	# Basis (ohne Werkzeug): Fertig obenauf.
	await _knopf_obenauf(dock_ui.done_button, "%s/basis Fertig" % label)
	# Ghost aktiv (Action-Bar sichtbar): Platzieren/Abbrechen + Fertig.
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await wait_frames(3)
	await _knopf_obenauf(dock_ui.action_buttons[1] as Button, "%s/geist Platzieren" % label)
	await _knopf_obenauf(dock_ui.action_buttons[3] as Button, "%s/geist Abbrechen" % label)
	await _knopf_obenauf(dock_ui.done_button, "%s/geist Fertig" % label)
	build._cancel_ghost()
	await wait_frames(2)
	# Klick-Gegenprobe end-zu-end: der synthetische Klick auf die
	# Fertig-Mitte schließt den Baumodus wirklich (Quest-Flag ist gesetzt).
	await _klick(dock_ui.done_button.get_global_rect().get_center())
	await wait_frames(2)
	assert_false(build.is_active(), "%s: Klick auf Fertig-Mitte schließt den Baumodus" % label)
	await _cleanup(room, gs)


# ── 5. Demo-Wurzeln des Blocker-Nachfixes ────────────────────────────────────


## Live-Demo-Wurzel 1: „Fertig“ verweigert bei aktiver Bett-Quest (Design,
## Doc D §3.1) — aber ab jetzt SICHTBAR: der Bett-Geist springt wieder an
## und die Action-Bar erscheint, statt dass der Knopf „tot“ wirkt.
func test_fertig_verweigerung_reagiert_sichtbar_bett_quest() -> void:
	await _pin_format(DESKTOP_KLEIN)
	var gs := _fresh_gs(true)
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(3)
	# Wie die Demo: den Auto-Bett-Geist erst abbrechen …
	build._cancel_ghost()
	await wait_frames(2)
	assert_false(build._action_bar.visible, "Abbrechen versteckt die Action-Bar")
	# … dann Fertig per synthetischem Klick auf die Knopf-Mitte.
	var dock_ui: BuildUiDock = build._dock_ui
	await _klick(dock_ui.done_button.get_global_rect().get_center())
	await wait_frames(2)
	assert_true(build.is_active(), "Bett-Quest: der Baumodus bleibt offen (Design)")
	assert_false(
		(build._ghost_state as Dictionary).is_empty(),
		"Verweigerung reagiert SICHTBAR: der Bett-Geist startet neu"
	)
	assert_true(build._action_bar.visible, "Action-Bar ist mit dem Geist wieder sichtbar")
	# Aufräumen: Quest erfüllen, damit close() nicht verweigert.
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	build._cancel_ghost()
	await wait_frames(1)
	build.close()
	await _cleanup(room, gs)


# ── 6. Frame-genaue Stapel-Wache (P2d, Video-Flacker-Review) ─────────────────


## Über N Frames nach einem Zustands-Wechsel: NIE beide Zeilen sichtbar —
## exakt die Frame-Probe, mit der der Video-Flash reproduziert wurde.
func _keine_stapel_frames(build: BuildMode, frames: int, kontext: String) -> void:
	var dock_ui: BuildUiDock = build._dock_ui
	for i in frames:
		await tree.process_frame
		assert_false(
			dock_ui.action_bar.is_visible_in_tree() and dock_ui.ebenen_leiste.is_visible_in_tree(),
			"%s: Stapel-Frame %d (Action-Bar UND Ebenen-Zeile sichtbar)" % [kontext, i]
		)


func test_zeilen_stapeln_nie_frame_genau() -> void:
	await _pin_format(DESKTOP_KLEIN)
	# Öffnen OHNE Quest-Geist — die Video-Wurzel: open() muss den
	# Zeilen-Zustand HERSTELLEN, nicht vom UI-Bau/Vor-Zustand erben.
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await _keine_stapel_frames(build, 12, "open_ohne_quest")
	var chip := build._drawer_items.get_child(0) as Button
	chip.pressed.emit()
	await _keine_stapel_frames(build, 8, "drawer_chip")
	build._on_abbrechen()
	await _keine_stapel_frames(build, 8, "abbrechen")
	var items := room.grid.to_items_array()
	if items.size() > 0:
		build._begin_move(str(items[0]["uid"]))
		await _keine_stapel_frames(build, 8, "moebel_move")
		build._cancel_ghost()
		await _keine_stapel_frames(build, 6, "move_ende")
	build._begin_new(FurnitureCatalog.def("girlande_wimpel"))
	await _keine_stapel_frames(build, 8, "girlande")
	build._on_abbrechen()
	await _keine_stapel_frames(build, 8, "girlande_abbruch")
	build.close()
	await _cleanup(room, gs)
	# Bett-Quest-Pfad: Auto-Geist beim Öffnen + Verweigerungs-Neustart.
	await _pin_format(DESKTOP_KLEIN)
	var gs2 := _fresh_gs(true)
	var room2 := _make_room(gs2)
	await wait_frames(6)
	var build2: BuildMode = room2.get_node("BuildMode")
	build2.open()
	await _keine_stapel_frames(build2, 12, "open_bett_quest")
	build2._cancel_ghost()
	await _keine_stapel_frames(build2, 8, "quest_geist_abbruch")
	build2.close()
	await _keine_stapel_frames(build2, 8, "close_verweigert_neustart")
	HomeState.set_flag(gs2, HomeState.FLAG_BED_PLACED, true)
	build2._cancel_ghost()
	build2.close()
	await _cleanup(room2, gs2)


# ── 7. Demo-Wurzeln des Blocker-Nachfixes (Fortsetzung) ──────────────────────


## Repro-Wurzel 2 (flow_baumodus 1434x660): eine offene Tür-/Blockade-
## Karte (RoomBase._choice, zentriert) lag ÜBER der Action-Bar und fraß
## deren Klicks — beim Baumodus-Öffnen muss sie wegräumen (room_base.gd).
func test_tuer_karte_raeumt_beim_baumodus_oeffnen() -> void:
	await _pin_format(DESKTOP_KLEIN)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var karte := PanelContainer.new()
	karte.name = "TuerConfirm"
	karte.set_anchors_preset(Control.PRESET_CENTER)
	room.ui_layer().add_child(karte)
	room._choice = karte
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(3)
	assert_true(room._choice == null, "Baumodus-Öffnen leert den _choice-Slot")
	assert_false(is_instance_valid(karte), "die Karte selbst ist abgebaut")
	build.close()
	await _cleanup(room, gs)
