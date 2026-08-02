extends TestCase
## G8/FIX-5 — Wachen für drei Playtest-Befunde aus
## docs/playtest/G8-PT1-home-bau.md:
##
## B1 HOCH „Garten-Deko verschwindet“: GardenView.rebuild() leerte den
##   GETEILTEN blockers()-Mount des Raums und zerstörte die dort von
##   RoomBase._spawn_furniture geparkten blocks_movement-Möbel
##   (treeDefault/treeFat/gardenBench/potLarge) — die Grid-Zellen blieben
##   unsichtbar belegt. Seit dem Ownership-Fix gibt rebuild() nur noch
##   GardenView-EIGENE Bauten frei (interne Bauten-Liste).
## B3 MITTEL „Sprechblase schluckt Action-Bar-Taps“: die Kapsel steht auf
##   mouse_filter IGNORE (Knöpfe darunter gewinnen), Skip/Schließen läuft
##   über _unhandled_input mit Treffertest; das Bau-Dock reserviert die
##   W14-Bottom-Zone, damit die kopf-folgende Blase ÜBER die Action-Bar
##   dodgt statt „Drehen“ zu überdecken.
## B4 MITTEL „TV-Aus-Knopf unter der HUD-Spalte“: aus_knopf_rechts() rückt
##   die rechte Knopfkante links an der sichtbaren Cockpit-Spalte
##   (hud.tscn %LandscapeColumn) vorbei.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

## Die vier blocks_movement-Defaults des Garten-Layouts (B1-Befund).
const GARTEN_DEFAULTS: Array[String] = ["treeDefault", "treeFat", "gardenBench", "potLarge"]
## Fenstergröße des Original-Befunds (Playtest-Lauf pt1_rundgang, B4).
const BEFUND_FENSTER := Vector2i(1024, 471)

var _seq := 0
var _prev_size := Vector2i()
var _prev_insets := Rect2()


## GameState-Double (Muster test_g8_fix2): dotted get_value + update() —
## reicht GardenState/GardenView (lesen den home.garden-Slice, schreiben
## über update). Der Garten-Slice ist vorab gesät (save_grid indiziert ihn).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)
		s["home"]["garden"] = GardenState.default_garden()

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


# ── B1: GardenView-Rebuild-Ownership ─────────────────────────────────────────


## KERN-WACHE: rebuild() darf im geteilten Mount nur die EIGENEN Bauten
## freigeben — fremde Kinder (die Möbel des Raums) bleiben unangetastet,
## eigene Bauten bleiben DIREKTE Mount-Kinder (RoomNavmesh.bake macht aus
## jedem Kind genau eine Obstruction) und stauen sich nicht auf.
func test_b1_rebuild_verschont_fremde_mount_kinder() -> void:
	var gs := FakeGameState.new()
	var mount := Node3D.new()
	mount.name = "Blockers"
	tree.root.add_child(mount)
	var fremd := Node3D.new()
	fremd.name = "MoebelVomRaum"
	mount.add_child(fremd)
	var grid := GardenState.grid(gs)
	assert_true(bool(grid.place_structure("baum", Vector2i(1, 1))["ok"]), "Baum platzierbar")
	GardenState.save_grid(gs, grid)
	var view := GardenView.new()
	tree.root.add_child(view)
	view.setup(gs, Vector2(14.0, 12.0), mount)
	var baeume := _lebende_eigene(mount, fremd)
	assert_eq(baeume.size(), 1, "Setup: eigener Bau hängt im Mount")
	var baum_alt: Node = baeume[0] if not baeume.is_empty() else null
	# DER Regressionsfall: Rebuilds wie nach jeder Garten-Aktion.
	view.rebuild(Vector2(14.0, 12.0))
	view.rebuild(Vector2(14.0, 12.0))
	await wait_frames(2)
	assert_true(
		is_instance_valid(fremd) and not fremd.is_queued_for_deletion(),
		"fremdes Mount-Kind (Raum-Möbel) überlebt rebuild()"
	)
	assert_true(
		is_instance_valid(fremd) and fremd.get_parent() == mount,
		"fremdes Mount-Kind hängt weiter im Mount"
	)
	assert_false(is_instance_valid(baum_alt), "alter eigener Bau wurde freigegeben")
	baeume = _lebende_eigene(mount, fremd)
	assert_eq(baeume.size(), 1, "genau EIN eigener Bau nach Doppel-Rebuild (kein Leak)")
	if not baeume.is_empty():
		assert_eq(baeume[0].get_parent(), mount, "eigener Bau bleibt DIREKTES Mount-Kind (Navmesh)")
	assert_eq(GardenState.grid(gs).structures.size(), 1, "Garten-Grid unverändert (View liest nur)")
	view.queue_free()
	mount.queue_free()
	await wait_frames(2)


## INTEGRATION am ECHTEN Garten-Raum: schon die Ankunft ist der
## Regressionsfall (GardenHost.setup() lässt EINEN rebuild() über den
## geteilten Mount laufen), obendrauf der Spieler-Pfad select_cell →
## _refresh → rebuild. Danach: alle 4 Defaults leben im Blockers-Mount
## und JEDER Grid-Eintrag hat einen lebenden Möbel-Node (Grid konsistent —
## vorher blieben Zellen unsichtbar belegt).
func test_b1_garten_defaults_ueberleben_rebuilds() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, "garden")
	await wait_frames(6)
	var blockers: Node3D = room.blockers()
	for id: String in GARTEN_DEFAULTS:
		var node := _moebel_im(room, id)
		assert_true(node != null, "%s lebt nach dem Setup-Rebuild" % id)
		if node != null:
			assert_eq(node.get_parent(), blockers, "%s hängt im Blockers-Mount" % id)
	var host: GardenHost = room.get_node("GardenHost")
	host.select_cell(Vector2i(0, 0))
	await wait_frames(3)
	for id: String in GARTEN_DEFAULTS:
		var node := _moebel_im(room, id)
		assert_true(node != null, "%s überlebt den select_cell-Rebuild" % id)
		if node != null:
			assert_eq(node.get_parent(), blockers, "%s bleibt im Blockers-Mount" % id)
	var furniture: Dictionary = room.get("_furniture")
	for entry: Dictionary in room.grid.to_items_array():
		var uid := str(entry["uid"])
		var node: Variant = furniture.get(uid)
		assert_true(
			(
				node is Node
				and is_instance_valid(node)
				and not (node as Node).is_queued_for_deletion()
			),
			"Grid-Eintrag %s (%s) hat einen lebenden Möbel-Node" % [str(entry.get("item")), uid]
		)
	await _cleanup_room(room, gs)


# ── B3: Sprechblasen-Tap-Vertrag ─────────────────────────────────────────────


## Die Kapsel (und alle Blasen-Teile) schlucken keine GUI-Eingaben mehr —
## Knöpfe unter der Blase gewinnen; die Bottom-Zone bleibt reserviert
## (Deconflict zweiter Blasen/Banner wie gehabt).
func test_b3_kapsel_laesst_gui_durch_und_reserviert_bottom() -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	var bubble := AcBubble.show_bubble(layer, "Du hast neue Quests!", {"dauer_s": 600.0})
	bubble.auto_zeit = false
	await wait_frames(1)
	var kapsel := bubble.get_node("Kapsel") as PanelContainer
	assert_eq(bubble.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Blasen-Wurzel: IGNORE")
	assert_eq(kapsel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Kapsel: IGNORE (B3-Kern)")
	for kind: Node in kapsel.get_children():
		if kind is Control:
			assert_eq(
				(kind as Control).mouse_filter,
				Control.MOUSE_FILTER_IGNORE,
				"Kapsel-Kind %s: IGNORE" % kind.name
			)
	assert_true(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(kapsel),
		"Kapsel bleibt als Bottom-Belegung angemeldet (W14-Deconflict)"
	)
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


## Tap-Verhalten über _unhandled_input: daneben = nichts, auf der Kapsel =
## Typewriter-Skip, nochmal = schließen (wie der alte gui_input-Pfad, nur
## NACH der GUI-Phase).
func test_b3_unhandled_tap_skippt_dann_schliesst() -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var rm_vorher := _set_reduced_motion(false)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	var text := "Ohh, wird das schön hier! Ich such mir mal ein Plätzchen zum Träumen."
	var bubble := AcBubble.show_bubble(layer, text, {"dauer_s": 600.0})
	bubble.auto_zeit = false
	await wait_frames(1)
	var kapsel := bubble.get_node("Kapsel") as PanelContainer
	assert_false(bubble._typewriter.ist_fertig(), "Vorbedingung: Typewriter läuft noch")
	# Tap DANEBEN (oben links): Blase reagiert nicht.
	bubble._unhandled_input(_tap_bei(Vector2(2.0, 2.0)))
	assert_true(bubble.is_active(), "Tap daneben lässt die Blase stehen")
	assert_false(bubble._typewriter.ist_fertig(), "Tap daneben skippt nicht")
	# Tap AUF die Kapsel: Typewriter-Skip, Blase bleibt.
	var mitte: Vector2 = kapsel.get_global_rect().get_center()
	bubble._unhandled_input(_tap_bei(mitte))
	assert_true(bubble._typewriter.ist_fertig(), "1. Kapsel-Tap skippt den Typewriter")
	assert_true(bubble.is_active(), "… und die Blase bleibt stehen")
	# Zweiter Tap AUF die Kapsel: Blase schließt.
	bubble._unhandled_input(_tap_bei(mitte))
	assert_false(bubble.is_active(), "2. Kapsel-Tap schließt die Blase")
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	_set_reduced_motion(rm_vorher)


## Das Bau-Dock meldet sich als Bottom-Belegung an (B3-Fix in
## build_ui_dock.gd) — die Blase dodgt dann ÜBER Action-Bar/Ebenen/Lager
## statt die Knöpfe zu überdecken (Bett-Quest-Befund).
func test_b3_bau_dock_reserviert_bottom_und_blase_dodgt() -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	UiAnchors.reset_for_tests()
	var rm_vorher := _set_reduced_motion(true)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(layer)
	var dock_ui := BuildUiDock.new()
	dock_ui.build(layer, BuildMode.EBENEN_KEYS)
	assert_true(
		UiAnchors.occupants(UiAnchors.ZONE_BOTTOM).has(dock_ui.dock),
		"Bau-Dock ist als Bottom-Belegung angemeldet"
	)
	# Baumodus „offen“: Dock sichtbar machen und layouten lassen.
	dock_ui.ui.visible = true
	await wait_frames(2)
	var dock_rect: Rect2 = dock_ui.dock.get_global_rect()
	assert_true(dock_rect.size.y > 0.0, "Dock hat eine Layout-Höhe")
	var bubble := AcBubble.show_bubble(layer, "Zeit für dein Bett!", {"dauer_s": 600.0})
	bubble.auto_zeit = false
	await wait_frames(1)
	bubble.advance_time(0.05)
	var kapsel := bubble.get_node("Kapsel") as PanelContainer
	var kapsel_rect := Rect2(kapsel.position, kapsel.size)
	assert_false(
		kapsel_rect.intersects(dock_rect),
		"Blase überlappt das Bau-Dock nicht (kapsel=%s dock=%s)" % [kapsel_rect, dock_rect]
	)
	assert_true(
		kapsel_rect.end.y <= dock_rect.position.y + 0.5,
		"Blase dodgt ÜBER das Dock (Action-Bar bleibt frei)"
	)
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	_set_reduced_motion(rm_vorher)


# ── B4: TV-Aus-Knopf vs. Cockpit-Spalte ──────────────────────────────────────


## PURE Anker-Rechnung: ohne Spalte gilt der Grundabstand (Safe-Area +
## 16·f); ragt die Spalte ins Bild, wandert die rechte Kante mit 12·f Luft
## links neben die Spalte — nie weiter rechts als der Grundanker.
func test_b4_aus_knopf_rechts_pur() -> void:
	# Ohne Spalte (INF, Hochkant/HUD weg): Grundabstand.
	assert_almost(Fernseher.aus_knopf_rechts(1024.0, 0.0, 1.0, INF), -16.0, 0.001, "ohne Spalte")
	assert_almost(
		Fernseher.aus_knopf_rechts(1024.0, 20.0, 2.0, INF), -52.0, 0.001, "Safe-Area + f skalieren"
	)
	# Spalte ragt rein (Befund: 1024 breit, Spalte ab x=880): Kante rückt
	# auf spalte_links − 12·f.
	var kante := Fernseher.aus_knopf_rechts(1024.0, 0.0, 1.0, 880.0)
	assert_almost(1024.0 + kante, 868.0, 0.001, "rechte Kante = Spalte − 12·f")
	# Auch eine Spalte KNAPP am Grundanker erzwingt die 12·f-Luft.
	var kante_knapp := Fernseher.aus_knopf_rechts(1024.0, 0.0, 1.0, 1010.0)
	assert_almost(1024.0 + kante_knapp, 998.0, 0.001, "knappe Spalte: Luft bleibt")
	# Spalte hinter dem Grundanker (weit genug weg): Grundanker gewinnt.
	var kante_frei := Fernseher.aus_knopf_rechts(1024.0, 0.0, 1.0, 1030.0)
	assert_almost(kante_frei, -16.0, 0.001, "ferne Spalte lässt den Grundanker stehen")


## INTEGRATION mit dem ECHTEN HUD in Befund-Größe 1024×471 (Querformat):
## _hud_spalte_links() findet die linke Kante der sichtbaren Cockpit-
## Spalte, und die Anker-Rechnung hält den Knopf links davon; ohne
## sichtbares HUD gilt wieder der Grundanker (INF).
func test_b4_hud_spalte_links_liefert_cockpit_kante() -> void:
	await _pin_window(BEFUND_FENSTER)
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await wait_frames(3)
	var spalte_node := hud.find_child("LandscapeColumn", true, false) as Control
	assert_true(
		spalte_node != null and spalte_node.is_visible_in_tree(),
		"Vorbedingung: Cockpit-Spalte sichtbar im Querformat"
	)
	var fernseher := Fernseher.new()
	tree.root.add_child(fernseher)
	# Ohne setup() liefe _process auf _host == null (Node-Wache reicht hier).
	fernseher.set_process(false)
	var spalte := fernseher._hud_spalte_links()
	assert_true(spalte < INF, "Spalte gefunden (nicht INF)")
	assert_almost(
		spalte, spalte_node.get_global_rect().position.x, 0.5, "Spalten-Kante = Control-Rect"
	)
	var m := ScreenShell.metrics(tree.root)
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var kante := Fernseher.aus_knopf_rechts(
		float(BEFUND_FENSTER.x), float(insets["right"]), f, spalte
	)
	assert_true(
		float(BEFUND_FENSTER.x) + kante <= spalte - 12.0 * f + 0.5,
		"Knopf-Rechtskante bleibt links der Cockpit-Spalte"
	)
	# HUD weg (P50-Verdeckung/Hochkant): Grundanker bleibt unangetastet.
	hud.visible = false
	assert_eq(fernseher._hud_spalte_links(), INF, "verstecktes HUD: keine Spalte (INF)")
	fernseher.free()
	hud.free()
	await _unpin_window()


# ── Helfer ───────────────────────────────────────────────────────────────────


## Frisches, ECHTES GameState mit eigenem user://-Ordner (Muster
## test_haussicht_garten_haus) — der Garten-Raum braucht den vollen
## HomeState-Slice inkl. Default-Layouts.
func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://g8fix5_tests/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _make_room(gs: Node, room_id: String) -> RoomBase:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	return room


func _cleanup_room(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Lebender Möbel-Node mit Katalog-Id im Raum (Muster flow_basis).
func _moebel_im(wurzel: Node, item_id: String) -> FurnitureNode:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is FurnitureNode and not aktuell.is_queued_for_deletion():
			var def: Variant = aktuell.get("item_def")
			if def is Dictionary and str((def as Dictionary).get("id", "")) == item_id:
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## Lebende Mount-Kinder AUSSER dem fremden Möbel-Double — bewusst NICHT über
## Namen gematcht: kollidiert ein neuer Bau mit einem queue_free-Zombie
## gleichen Namens, benennt Godot ihn zur LAUFZEIT in "@Node3D@<id>" um
## (die Basis "Baum" geht verloren; nur der Editor uniquift lesbar).
func _lebende_eigene(mount: Node, fremd: Node) -> Array[Node]:
	var out: Array[Node] = []
	for kind: Node in mount.get_children():
		if kind != fremd and not kind.is_queued_for_deletion():
			out.append(kind)
	return out


func _tap_bei(punkt: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = punkt
	return ev


## Reduced Motion global setzen; gibt den vorherigen Zustand zurück
## (Muster test_g8_fix2 — deterministische Tween-/Typewriter-Zustände).
func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


## Fenster VOR der Instanziierung pinnen (Geometrie-Tests, W17-Konvention).
func _pin_window(size: Vector2i) -> void:
	_prev_size = tree.root.size
	_prev_insets = UiScale.insets_override
	UiScale.insets_override = Rect2()
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin_window() -> void:
	tree.root.size = _prev_size
	UiScale.insets_override = _prev_insets
	tree.root.size_changed.emit()
	await wait_frames(2)
