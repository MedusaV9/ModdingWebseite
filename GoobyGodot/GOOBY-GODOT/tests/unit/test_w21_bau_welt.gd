extends TestCase
## W21 P2 „Welt zuerst“ — Abnahme-Wächter des Baumodus-Umbaus (der wörtliche
## User-Frust: „beim bauen sieht man nichts außer die Knöpfe“, nur 59,1 %
## Welt beim Platzieren im Quer-Leitformat):
##
## 1. WELT-SICHTBARKEITS-BUDGET pro Bau-Zustand (Messmethode der W21-
##    Playtest-Welle nachgebaut: Raster-Union aller sichtbaren MALENDEN
##    Control-Rects über dem Canvas, 6-px-Raster ≙ ±0,2 %): quer ≥ 75 %
##    Welt in ALLEN Zuständen, beim Zielen (Ghost/Move/Girlande) ≥ 80 %.
##    Transiente Sprechblasen/Toasts sind P1-Fläche mit eigenen Wächtern
##    und werden vor der Messung abgeräumt — hier zählt die PERSISTENTE
##    Bau-UI.
## 2. DOCK-KLAPP-CHOREOGRAPHIE frame-genau (W20-P2d-Muster): das Lager
##    startet EINGEKLAPPT, klappt beim Werkzeug-Start (Ghost/Girlande)
##    zu und nach Platzieren/Einlagern/Abbrechen wieder auf — über N
##    Frames nach jedem Übergang ohne Flacker-Fenster; das offene Blatt
##    und die Action-Bar stapeln sich nie.
## 3. PLATZIER-PUFF-VERTRAG (Reduced-Motion-gated): _confirm_ghost baut
##    einen transienten IGNORE-Host „PlatzierPuff“ mit PUFF_TEILE
##    Flöckchen (RNG injiziert) + Kamera-Nick; unter Reduced Motion
##    entstehen weder Puff noch Nick. Dazu die pure Nick-Kurve
##    (BuildCamera.nick_versatz: Enden 0, Mitte volle Tiefe, nie > 0).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Leitformat quer [Fenster-px, screen_scale, Insets in Punkten [l,t,r,b]]
## — Werte wie test_w20_bau_layout.LEIT_QUER.
const LEIT_QUER: Array = [Vector2i(2868, 1320), 3.0, [59.0, 0.0, 59.0, 21.0]]
## Abnahme-Budgets (Welt-Anteil in Prozent, Quer-Leitformat).
const BUDGET_ALLE := 75.0
const BUDGET_ZIELEN := 80.0
## Raster-Schrittweite (Canvas-px) der Union-Messung (Playtest-Welle).
const RASTER := 6.0
## Control-Klassen, die wirklich MALEN (Playtest-Welle: Container/plain
## Controls sind unsichtbares Layout über der Welt und zählen nicht).
const MALER: Array[String] = [
	"Button",
	"TextureButton",
	"LinkButton",
	"CheckBox",
	"CheckButton",
	"OptionButton",
	"Label",
	"RichTextLabel",
	"PanelContainer",
	"Panel",
	"TextureRect",
	"ColorRect",
	"NinePatchRect",
	"ProgressBar",
	"TextureProgressBar",
	"LineEdit",
	"TextEdit",
	"HSlider",
	"VSlider",
	"ItemList",
	"Tree",
]

var _seq := 0
var _fenster_vorher := Vector2i.ZERO
var _canvas := Vector2.ZERO

# ── Aufbau-/Abbau-Helfer (Muster test_w20_bau_layout) ────────────────────────


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w21_tests/bau_welt_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	# Deterministische Bau-Zustände: Bett-Quest aus, Umzugs-Blase aus.
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	gs.set_value("home.movingDay", false)
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
	var px_pt := minf(_canvas.x, _canvas.y) / pt_kurz
	var insets_pt: Array = format[2]
	var l := float(insets_pt[0]) * px_pt
	var t := float(insets_pt[1]) * px_pt
	var r := float(insets_pt[2]) * px_pt
	var b := float(insets_pt[3]) * px_pt
	UiScale.insets_override = Rect2(l, t, _canvas.x - l - r, _canvas.y - t - b)
	await wait_frames(1)


func _unpin_format() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _fenster_vorher != Vector2i.ZERO:
		tree.root.size = _fenster_vorher
		DisplayServer.window_set_size(_fenster_vorher)
		_fenster_vorher = Vector2i.ZERO
	await wait_frames(2)


## Reduced Motion global setzen; gibt den vorherigen Zustand zurück
## (Muster test_g7_hud_dynamik).
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


# ── Welt-Sichtbarkeits-Messung (Spiegel der Playtest-Welle) ──────────────────


## Welt-Anteil (Prozent) des aktuellen Frames unter `wurzel`: Canvas-Fläche
## minus Raster-Union aller sichtbaren malenden Control-Rects.
func _welt_anteil(wurzel: Node) -> float:
	var flaechen: Array[Rect2] = []
	_sammle_maler_rects(wurzel, flaechen)
	var bedeckt := _raster_union(flaechen, _canvas)
	return (1.0 - bedeckt / maxf(_canvas.x * _canvas.y, 1.0)) * 100.0


func _sammle_maler_rects(node: Node, out: Array[Rect2]) -> void:
	var stapel: Array[Node] = [node]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		for kind in aktuell.get_children():
			stapel.append(kind)
		if not (aktuell is Control):
			continue
		var control := aktuell as Control
		if not control.is_visible_in_tree() or not _malt(control):
			continue
		if control.modulate.a * control.self_modulate.a < 0.05:
			continue
		var rect := control.get_global_rect().intersection(Rect2(Vector2.ZERO, _canvas))
		if rect.get_area() > 0.0:
			out.append(rect)


func _malt(control: Control) -> bool:
	# Shader-ColorRects (PostFx) sind Welt-Effekte, keine UI-Fläche.
	if control is ColorRect:
		if control.material != null or (control as ColorRect).color.a < 0.05:
			return false
	for klasse in MALER:
		if control.is_class(klasse):
			return true
	return false


## Raster-Union in px² (Zeilenband-Vorfilter wie in der Playtest-Welle).
func _raster_union(flaechen: Array[Rect2], canvas: Vector2) -> float:
	var nx := int(ceil(canvas.x / RASTER))
	var ny := int(ceil(canvas.y / RASTER))
	var treffer := 0
	for iy in ny:
		var y := (float(iy) + 0.5) * RASTER
		var band: Array[Rect2] = []
		for r in flaechen:
			if y >= r.position.y and y <= r.end.y:
				band.append(r)
		if band.is_empty():
			continue
		for ix in nx:
			var x := (float(ix) + 0.5) * RASTER
			for r in band:
				if x >= r.position.x and x <= r.end.x:
					treffer += 1
					break
	return float(treffer) * RASTER * RASTER


## Transiente Blasen abräumen (P1-Fläche mit eigenen Wächtern) — die
## Budget-Messung zählt die PERSISTENTE Bau-UI. is_instance_valid ZUERST:
## room hält nach dem ersten queue_free eine tote Referenz, `is` auf ihr
## wäre ein Freed-Instance-Fehler.
func _blasen_weg(room: Node) -> void:
	var blase: Variant = room.get("_bubble")
	if is_instance_valid(blase) and blase is Node:
		(blase as Node).queue_free()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	await wait_frames(1)


func _budget_pruefen(room: Node, budget: float, kontext: String) -> void:
	await _blasen_weg(room)
	var welt := _welt_anteil(room)
	assert_true(
		welt >= budget, "%s: Welt-Anteil %.1f %% >= Budget %.0f %%" % [kontext, welt, budget]
	)
	print("[W21-BUDGET] %s: %.1f %% Welt (Budget %.0f %%)" % [kontext, welt, budget])


# ── 1. Welt-Sichtbarkeits-Budget pro Zustand (quer, Abnahme-Zahlen) ──────────


func test_welt_budget_quer_alle_bau_zustaende() -> void:
	await _pin_format(LEIT_QUER)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(4)
	# Basis: Lager eingeklappt (startet so — Welt zuerst).
	assert_true(build._dock_ui.lager_eingeklappt(), "Basis: Lager startet eingeklappt")
	await _budget_pruefen(room, BUDGET_ALLE, "basis_eingeklappt")
	# Stöbern: Blatt manuell aufgeklappt — auch offen bleibt die Welt frei.
	# Erst den Blatt-Einflug (MotionKit) ausschwingen lassen: die Messung
	# überspringt Controls mit Alpha < 0,05 und würde sonst zu wenig zählen.
	build._dock_ui.klappe_lager(false)
	var blatt: Control = build._dock_ui.kontext.inhalt
	var ruhig := await wait_until(func() -> bool: return blatt.modulate.a >= 0.99, 5_000)
	assert_true(ruhig, "Blatt-Einflug schwingt aus")
	await wait_frames(2)
	await _budget_pruefen(room, BUDGET_ALLE, "blatt_offen")
	# Zielen 1: neuer Ghost — der frühere 59,1-%-Tiefpunkt.
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await wait_frames(3)
	assert_true(build._action_bar.visible, "Geist: Action-Bar sichtbar")
	await _budget_pruefen(room, BUDGET_ZIELEN, "geist_zielen")
	build._cancel_ghost()
	await wait_frames(2)
	# Zielen 2: bestehendes Möbel aufgenommen (volle Action-Bar).
	var items := room.grid.to_items_array()
	assert_true(items.size() > 0, "Standard-Einrichtung vorhanden")
	build._begin_move(str(items[0]["uid"]))
	await wait_frames(3)
	await _budget_pruefen(room, BUDGET_ZIELEN, "moebel_move")
	build._cancel_ghost()
	await wait_frames(2)
	# Zielen 3: Girlanden-Spann-Flow (Decken-Ebene).
	build._begin_new(FurnitureCatalog.def("girlande_wimpel"))
	await wait_frames(3)
	await _budget_pruefen(room, BUDGET_ZIELEN, "girlande_spann")
	build._on_abbrechen()
	await wait_frames(2)
	build.close()
	await _cleanup(room, gs)


# ── 2. Dock-Klapp-Choreographie frame-genau (W20-P2d-Muster) ─────────────────


## Über N Frames: Klapp-Zustand stabil UND nie (offenes Blatt + Action-Bar)
## gleichzeitig — exakt die Frame-Probe des W20-Flacker-Reviews.
func _klapp_frames(build: BuildMode, frames: int, zu: bool, kontext: String) -> void:
	var dock_ui: BuildUiDock = build._dock_ui
	for i in frames:
		await tree.process_frame
		assert_eq(
			dock_ui.lager_eingeklappt(),
			zu,
			"%s: Frame %d — Lager %s" % [kontext, i, "eingeklappt" if zu else "aufgeklappt"]
		)
		assert_false(
			dock_ui.kontext.inhalt.is_visible_in_tree() and dock_ui.action_bar.is_visible_in_tree(),
			"%s: Frame %d — offenes Blatt UND Action-Bar (Stapel)" % [kontext, i]
		)


func test_klapp_choreographie_frame_genau() -> void:
	await _pin_format(LEIT_QUER)
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	# Öffnen: eingeklappt HERSTELLEN (nicht erben), ohne Flacker-Fenster.
	await _klapp_frames(build, 10, true, "open")
	# Werkzeug an (Ghost): bleibt zu — beim Zielen zählt die Welt.
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await _klapp_frames(build, 8, true, "geist_neu")
	# Werkzeug endet (Abbrechen): Blatt klappt auf (Stöber-Einladung).
	build._on_abbrechen()
	await _klapp_frames(build, 8, false, "abbrechen")
	# Nächstes Werkzeug (Möbel-Move): klappt wieder zu …
	var items := room.grid.to_items_array()
	assert_true(items.size() > 0, "Standard-Einrichtung vorhanden")
	build._begin_move(str(items[0]["uid"]))
	await _klapp_frames(build, 8, true, "moebel_move")
	# … und nach dem Ende wieder auf.
	build._cancel_ghost()
	await _klapp_frames(build, 8, false, "move_ende")
	# Girlanden-Spann-Flow zählt als Werkzeug (gleiche Choreographie).
	build._begin_new(FurnitureCatalog.def("girlande_wimpel"))
	await _klapp_frames(build, 8, true, "girlande")
	build._on_abbrechen()
	await _klapp_frames(build, 8, false, "girlande_ende")
	# Manueller Griff-Tap: zu → wieder auf (User-Hoheit bleibt).
	build._dock_ui.kontext.griff.pressed.emit()
	await _klapp_frames(build, 4, true, "griff_tap_zu")
	build._dock_ui.kontext.griff.pressed.emit()
	await _klapp_frames(build, 4, false, "griff_tap_auf")
	# Sperrzonen-Vertrag: die Zone springt beim Klapp-Wechsel NICHT
	# (P1-Lanes verlassen sich auf die VOLLE Ausbaustufe).
	var zone_offen := build._dock_ui.dock_zone()
	build._dock_ui.klappe_lager(true)
	await wait_frames(2)
	var zone_zu := build._dock_ui.dock_zone()
	assert_true(
		(
			zone_offen.position.distance_to(zone_zu.position) < 1.0
			and zone_offen.size.distance_to(zone_zu.size) < 1.0
		),
		"dock_zone() bleibt beim Klapp-Wechsel stabil (%s vs %s)" % [zone_offen, zone_zu]
	)
	build.close()
	await _cleanup(room, gs)


# ── 3. Platzier-Puff-Vertrag (Reduced-Motion-gated) ──────────────────────────


## Freie Zelle für die Def suchen (Scan ab 0,0 — deterministisch).
func _freie_zelle(grid: GridData, def: Dictionary) -> Vector2i:
	for y in int(grid.size.y):
		for x in int(grid.size.x):
			var at := Vector2i(x, y)
			if bool(grid.can_place(def, at, 0, "")["ok"]):
				return at
	return Vector2i(-1, -1)


## Ghost starten, auf eine freie Zelle legen und platzieren.
func _platziere_bett(build: BuildMode, room: RoomBase) -> void:
	build._begin_new(FurnitureCatalog.def("bedSingle"))
	await wait_frames(2)
	var at := _freie_zelle(room.grid, FurnitureCatalog.def("bedSingle"))
	assert_true(at.x >= 0, "freie Zelle für das Bett gefunden")
	build._ghost_state["at"] = at
	build._rebuild_ghost()
	await wait_frames(1)
	build._confirm_ghost()


func test_platzier_puff_und_nick_rm_gated() -> void:
	await _pin_format(LEIT_QUER)
	var rm_vorher := _set_reduced_motion(false)
	var gs := _fresh_gs()
	# Zwei Betten ins Lager — der Vertrag platziert einmal je RM-Zustand.
	HomeState.store_item(gs, "bedSingle")
	HomeState.store_item(gs, "bedSingle")
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	# RNG injizieren (Zeit/RNG-Regel) — der Puff streut deterministisch.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	build.puff_rng = rng
	build.open()
	await wait_frames(3)
	# OHNE Reduced Motion: Puff-Host mit Flöckchen + Kamera-Nick. Die
	# Proben laufen im SELBEN Frame wie _confirm_ghost — ein einziger
	# VM-Last-Frame könnte den 0,22-s-Nick sonst schon aufbrauchen.
	await _platziere_bett(build, room)
	var puff := build._ui.find_child("PlatzierPuff", false, false) as Control
	assert_true(puff != null, "Platzieren baut den PlatzierPuff-Host")
	if puff != null:
		assert_eq(
			puff.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Puff-Host frisst keine Taps (IGNORE)"
		)
		assert_eq(puff.get_child_count(), MotionKit.PUFF_TEILE, "Puff streut PUFF_TEILE Flöckchen")
	assert_true(build.build_camera().nickt(), "Platzieren nickt die Kamera an")
	# Der transiente Host räumt sich selbst ab (PUFF_HOST_S). Über die
	# Instanz-ID prüfen — eine direkte `puff`-Capture wäre nach dem Free
	# ein Lambda-Capture-Fehler im Log.
	var puff_id := puff.get_instance_id() if puff != null else 0
	var weg := await wait_until(func() -> bool: return instance_from_id(puff_id) == null, 5_000)
	assert_true(weg, "Puff-Host räumt sich nach PUFF_HOST_S selbst ab")
	# MIT Reduced Motion: weder Puff noch Nick (der Klopf-Sound bleibt).
	_set_reduced_motion(true)
	await _platziere_bett(build, room)
	assert_true(
		build._ui.find_child("PlatzierPuff", false, false) == null, "Reduced Motion: kein Puff-Host"
	)
	assert_false(build.build_camera().nickt(), "Reduced Motion: kein Kamera-Nick")
	_set_reduced_motion(rm_vorher)
	build.close()
	await _cleanup(room, gs)


## Pure Nick-Kurve: Enden bei 0, Mitte = volle Tiefe (Dip, nie > 0);
## außerhalb des Fensters (rest > dauer, rest <= 0) kein Versatz.
func test_nick_versatz_kurve_pur() -> void:
	var s := BuildCamera.NICK_S
	var t := BuildCamera.NICK_TIEFE
	assert_almost(BuildCamera.nick_versatz(s, s, t), 0.0, 0.0001, "Start: kein Versatz")
	assert_almost(BuildCamera.nick_versatz(0.0, s, t), 0.0, 0.0001, "Ende: kein Versatz")
	assert_almost(BuildCamera.nick_versatz(s * 0.5, s, t), -t, 0.0001, "Mitte: volle Tiefe")
	assert_almost(BuildCamera.nick_versatz(s * 2.0, s, t), 0.0, 0.0001, "rest > dauer: 0")
	assert_almost(BuildCamera.nick_versatz(-0.1, s, t), 0.0, 0.0001, "rest < 0: 0")
	for i in 9:
		var rest := s * float(i + 1) / 10.0
		assert_true(
			BuildCamera.nick_versatz(rest, s, t) <= 0.0001,
			"Dip zeigt nie nach oben (rest=%.3f)" % rest
		)
