extends TestCase
## W16/G4 P20 UI-GAMESELECT — Geometrie der Level-Auswahlen, Brettspiele und
## GvZ/GOB-NOM-HUDs gegen die USER-Designlinie (Touch-Floor, Fonts ×f,
## Bedienelemente mittig/Daumenzone, Safe-Area):
## (1) Level-Select-Familie (gvz/gobnom/comp): Kacheln + Fertig halten den
##     Touch-Floor, Footer mittig; gobnom/comp pinnen den Footer AUS der
##     Scroll-Spalte (bleibt bei Überlauf sichtbar).
## (2) GOB-NOM-Netz-Panel: alle Knöpfe (Aktion/Annehmen/Ablehnen) >= 48 px.
## (3) Schach: board_square_px (PURE) skaliert dynamisch, klemmt auf
##     [Touch-Floor, 96×f]; hochkant kippt _main auf VBox (Panel unters Brett).
## (4) Battleship: „Verlassen“ verankert (TOP_LEFT + Insets), Aktions-Cluster
##     an der Unterkante in der Daumenzone, Knöpfe >= Touch-Floor.
## (5) GvZ: Kartenleiste an der UNTERKANTE, Karten >= Touch-Floor, Feld endet
##     über der Leiste; End-Overlay als Arcade-Plate (AcCardLg) mittig.
## (6) QW #21: gobnom.editor.*-Keys existieren DE+EN (Editor-Strings i18n).
## Geometrie-Tests pinnen das Fenster VOR dem Screen-Bau auf 1280×720 und
## setzen es danach zurück (Metrics bleiben deterministisch).

const GvzGameScript := preload("res://scripts/minigames/games/gvz/gvz_game.gd")
const ChessSceneScript := preload("res://scripts/social/boardgame/chess_scene.gd")

const WIN := Vector2i(1280, 720)
const WIN_PORTRAIT := Vector2i(720, 1280)
const EDITOR_KEYS := [
	"gobnom.editor.loesbar",
	"gobnom.editor.nicht_loesbar",
	"gobnom.editor.nichts_gewaehlt",
	"gobnom.editor.hint_f6",
	"gobnom.editor.snap_raster",
]


class GameStateDouble:
	extends RefCounted

	var state := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


class FakeServices:
	extends Node

	var chess: ChessSession = null
	var game_state_override: Object = null


func _pin_window(size := WIN) -> Vector2i:
	var prev: Vector2i = tree.root.size
	tree.root.size = size
	return prev


func _buttons_in(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Button:
			out.append(node)
	return out


func _inside_scroll(node: Node) -> bool:
	var cursor := node.get_parent()
	while cursor != null:
		if cursor is ScrollContainer:
			return true
		cursor = cursor.get_parent()
	return false


## Gemeinsame Prüfung der Select-Familie: Kacheln/Fertig >= Touch-Floor,
## Fertig als SquishButton in einem MITTIG ausgerichteten Footer.
func _assert_select_floor_und_footer(select: Control, tiles: Array, name: String) -> void:
	var m := ScreenShell.metrics(select.get_viewport())
	var floor_px: float = m["floor_px"]
	for tile: Button in tiles:
		assert_true(tile is SquishButton, "%s: Kachel ist SquishButton" % name)
		assert_true(tile.custom_minimum_size.y >= floor_px, "%s: Kachel-Höhe >= Floor" % name)
		assert_true(tile.custom_minimum_size.x >= floor_px, "%s: Kachel-Breite >= Floor" % name)
	var done: Button = select.get("_done")
	assert_true(done is SquishButton, "%s: Fertig ist SquishButton" % name)
	assert_true(done.custom_minimum_size.y >= floor_px, "%s: Fertig >= Touch-Floor" % name)
	var footer := done.get_parent() as BoxContainer
	assert_true(footer != null, "%s: Footer ist ein BoxContainer" % name)
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_CENTER, "%s: Footer mittig" % name)


func test_gvz_select_touch_floor_und_footer_mittig() -> void:
	var prev := _pin_window()
	var select := GvzLevelSelect.new()
	select.game_state = GameStateDouble.new()
	tree.root.add_child(select)
	await wait_frames(2)
	var buttons: Dictionary = select.get("_buttons")
	assert_eq(buttons.size(), 15, "gvz: 15 Kacheln")
	_assert_select_floor_und_footer(select, buttons.values(), "gvz")
	select.free()
	tree.root.size = prev


func test_gobnom_select_footer_gepinnt_und_touch_floor() -> void:
	var prev := _pin_window()
	var select := GobnomLevelSelect.new()
	select.game_state = GameStateDouble.new()
	tree.root.add_child(select)
	await wait_frames(2)
	var buttons: Dictionary = select.get("_buttons")
	assert_eq(buttons.size(), 25, "gobnom: 15 Kampagne + 10 Coop")
	_assert_select_floor_und_footer(select, buttons.values(), "gobnom")
	# G4-Kern: Kacheln scrollen, der Footer ist AUS der Scroll-Spalte gepinnt.
	var grids: Dictionary = select.get("_grids")
	for track: String in grids:
		assert_true(_inside_scroll(grids[track]), "gobnom: Gitter %s liegt im Scroll" % track)
	assert_false(_inside_scroll(select.get("_done")), "gobnom: Footer NICHT im Scroll (gepinnt)")
	select.free()
	tree.root.size = prev


func test_comp_select_footer_gepinnt_und_touch_floor() -> void:
	var prev := _pin_window()
	var select := RcompLevelSelect.new()
	select.game_state = GameStateDouble.new()
	tree.root.add_child(select)
	await wait_frames(2)
	var buttons: Array = select.get("_buttons")
	assert_eq(buttons.size(), RanchCompState.ARCADE_LEVEL, "comp: alle Lauf-Kacheln")
	_assert_select_floor_und_footer(select, buttons, "comp")
	assert_true(_inside_scroll(select.get("_grid")), "comp: Gitter liegt im Scroll")
	assert_false(_inside_scroll(select.get("_done")), "comp: Footer NICHT im Scroll (gepinnt)")
	select.free()
	tree.root.size = prev


func test_gobnom_netz_panel_knoepfe_auf_touch_floor() -> void:
	var panel := GobnomNetzPanel.new()
	tree.root.add_child(panel)
	await wait_frames(1)
	var action: Button = panel.get("_action")
	assert_true(action is SquishButton, "netz: Aktions-Knopf ist SquishButton")
	assert_true(
		action.custom_minimum_size.y >= AcTokens.TOUCH_FLOOR, "netz: Aktion >= 48 px (statt 40)"
	)
	# Einladungszeile (Annehmen/Ablehnen) entsteht ohne Session — nur UI.
	panel._on_invite_incoming({"from": "F1", "goobyName": "Tester"})
	var found := 0
	for btn: Button in _buttons_in(panel.get("_invites_box")):
		found += 1
		assert_true(btn is SquishButton, "netz: Einladungs-Knopf ist SquishButton")
		assert_true(btn.custom_minimum_size.y >= AcTokens.TOUCH_FLOOR, "netz: Einladung >= 48 px")
	assert_eq(found, 2, "netz: Annehmen + Ablehnen")
	panel.free()


func test_chess_feldgroesse_pur_skaliert_und_klemmt() -> void:
	var insets := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	# Quer 1280×720: Höhe limitiert — (720−78−60)/8 = 72,75 (im Fenster).
	var quer: float = ChessSceneScript.board_square_px(Vector2(1280, 720), insets, 1.0, 48.0, false)
	assert_almost(quer, 72.75, 0.01, "quer: Höhe limitiert das Brett")
	# Hochkant 720×1280: Breite limitiert — (720−78)/8 = 80,25.
	var hoch: float = ChessSceneScript.board_square_px(Vector2(720, 1280), insets, 1.0, 48.0, true)
	assert_almost(hoch, 80.25, 0.01, "hochkant: Breite limitiert das Brett")
	# Winziger Canvas: NIE unter den Touch-Floor.
	var mini: float = ChessSceneScript.board_square_px(Vector2(360, 360), insets, 1.0, 48.0, false)
	assert_almost(mini, 48.0, 0.01, "klemmt auf den Touch-Floor")
	# Riesiger Canvas: Optik-Deckel 96×f.
	var gross: float = ChessSceneScript.board_square_px(
		Vector2(4000, 4000), insets, 1.0, 48.0, false
	)
	assert_almost(gross, 96.0, 0.01, "klemmt auf den 96er-Deckel")


func test_chess_hochkant_kippt_auf_vbox() -> void:
	var prev := _pin_window()
	var services := FakeServices.new()
	tree.root.add_child(services)
	var scene := ChessScene.new()
	scene.services_override = services
	tree.root.add_child(scene)
	await wait_frames(1)
	var main: BoxContainer = scene.get("_main")
	assert_false(main.vertical, "quer: Seitenpanel NEBEN dem Brett")
	var m := ScreenShell.metrics(scene.get_viewport())
	assert_true(float(scene.get("_square_px")) >= float(m["floor_px"]), "Feld >= Touch-Floor")
	# Hochkant: _apply_metrics kippt die Hauptachse (Panel UNTER das Brett).
	tree.root.size = WIN_PORTRAIT
	await wait_frames(2)
	scene.call("_apply_metrics")
	assert_true(main.vertical, "hochkant: Seitenpanel UNTER dem Brett")
	scene.queue_free()
	services.queue_free()
	await wait_frames(2)
	tree.root.size = prev


func test_battleship_verlassen_verankert_und_daumenzone() -> void:
	var prev := _pin_window()
	var social := SocialServices.new()
	tree.root.add_child(social)
	social.board.opponent_gooby_name = "Flauschi"
	social.board.turn = BattleshipLogic.Turn.new("", ["", "GOOBY-PEER"])
	var scene := BattleshipScene.new()
	scene.services_override = social
	tree.root.add_child(scene)
	await wait_frames(5)
	var m := ScreenShell.metrics(scene.get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var leave: Button = scene.get("_leave_button")
	assert_true(leave is SquishButton, "battleship: Verlassen ist SquishButton")
	assert_almost(leave.anchor_left, 0.0, 1e-4, "battleship: Verlassen TOP_LEFT-verankert")
	assert_almost(leave.anchor_top, 0.0, 1e-4, "battleship: Verlassen TOP_LEFT-verankert (y)")
	assert_almost(
		leave.position.x, float(insets["left"]) + 16.0 * f, 0.5, "battleship: Insets-Position"
	)
	assert_true(
		leave.custom_minimum_size.y >= float(m["floor_px"]), "battleship: Verlassen >= Floor"
	)
	var actions: BoxContainer = scene.get("_actions")
	assert_almost(actions.anchor_bottom, 1.0, 1e-4, "battleship: Aktionen an der Unterkante")
	assert_almost(actions.anchor_left, 0.75, 1e-4, "battleship: Aktionen in der Daumenzone rechts")
	for btn: Button in _buttons_in(actions):
		assert_true(
			btn.custom_minimum_size.y >= float(m["floor_px"]), "battleship: Aktion >= Floor"
		)
	scene.queue_free()
	social.queue_free()
	await wait_frames(2)
	tree.root.size = prev


func test_gvz_kartenleiste_an_der_unterkante() -> void:
	var prev := _pin_window()
	var game: Node2D = GvzGameScript.new()
	tree.root.add_child(game)
	await wait_frames(1)
	var m := ScreenShell.metrics(game.get_viewport())
	var dims: Vector2 = game.call("_card_dims")
	assert_true(dims.x >= float(m["floor_px"]), "gvz: Karten-Breite >= Touch-Floor")
	assert_true(dims.y >= float(m["floor_px"]), "gvz: Karten-Höhe >= Touch-Floor")
	var vp: Vector2 = game.call("_view_size")
	var rect: Rect2 = game.call("_card_rect", 0)
	assert_almost(
		rect.position.y + dims.y, vp.y - GvzGameScript.TOP_PAD, 0.5, "gvz: Leiste an der Unterkante"
	)
	assert_true(rect.position.y > vp.y * 0.6, "gvz: Karten in der Daumenzone (unteres Drittel)")
	var field: Rect2 = game.call("_field_rect")
	assert_true(
		field.position.y + field.size.y <= rect.position.y, "gvz: Feld endet über der Leiste"
	)
	game.free()
	tree.root.size = prev


func test_gvz_end_overlay_als_arcade_plate() -> void:
	var prev := _pin_window()
	var game: Node2D = GvzGameScript.new()
	tree.root.add_child(game)
	await wait_frames(1)
	game.call("_build_end_overlay", false, 0, 0, false)
	var overlay: Control = game.get("_overlay")
	assert_true(overlay != null, "gvz: End-Overlay steht")
	var dim := overlay.get_child(0) as ColorRect
	var panel := overlay.get_child(1) as PanelContainer
	assert_true(dim != null, "gvz: Dim-Schicht (modal)")
	assert_true(panel != null, "gvz: Plate ist ein PanelContainer")
	assert_eq(String(panel.theme_type_variation), "AcCardLg", "gvz: Arcade-Karte (results-Muster)")
	var vp: Vector2 = game.call("_view_size")
	assert_almost(dim.size.x, vp.x, 0.5, "gvz: Dim deckt den Viewport (x)")
	assert_almost(dim.size.y, vp.y, 0.5, "gvz: Dim deckt den Viewport (y)")
	assert_almost(panel.position.x + panel.size.x / 2.0, vp.x / 2.0, 1.0, "gvz: Plate mittig (x)")
	assert_almost(panel.position.y + panel.size.y / 2.0, vp.y / 2.0, 1.0, "gvz: Plate mittig (y)")
	var m := ScreenShell.metrics(game.get_viewport())
	var found := 0
	for btn: Button in _buttons_in(panel):
		found += 1
		assert_true(btn is SquishButton, "gvz: Overlay-Knopf ist SquishButton")
		assert_true(
			btn.custom_minimum_size.y >= float(m["floor_px"]), "gvz: Overlay-Knopf >= Floor"
		)
	assert_eq(found, 2, "gvz: Niederlage bietet Nochmal + Zur Auswahl")
	game.free()
	tree.root.size = prev


func test_gobnom_editor_strings_de_en() -> void:
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in EDITOR_KEYS:
		assert_true(de.has(key), "DE fehlt %s" % key)
		assert_true(en.has(key), "EN fehlt %s" % key)
		assert_ne(str(de[key]), "", "DE-Wert leer: %s" % key)
		assert_ne(str(en[key]), "", "EN-Wert leer: %s" % key)
