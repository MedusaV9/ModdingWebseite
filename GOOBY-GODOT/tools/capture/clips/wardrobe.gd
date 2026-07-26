extends "res://tools/capture/clip_driver.gd"
## Clip: Garderobe — lebender Gooby links, Item-Karten rechts. Wir schenken
## uns auffällige Outfits (Demo-Spielstand), tippen sie GEZIELT an (Gooby
## trägt sofort, Slots stapeln sich: Hut + Brille + Rucksack), wechseln
## den Tab und drehen den Gooby per Zug.

const GESCHENKE: Array[String] = [
	"partyHat", "wizardHat", "flowerCrown", "hut_frosch",
	"roundGlasses", "starGlasses", "scarfRed", "propellerPack",
]

var screen: Control


func _setup() -> void:
	duration = 13.0
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		for id in GESCHENKE:
			CosmeticsState.apply_to_state(gs, func(slice: Dictionary, _econ: Dictionary) -> Dictionary:
				return CosmeticsState.grant(slice, id, "trailer"))
	var packed: PackedScene = load("res://scripts/cosmetics/wardrobe_screen.tscn")
	screen = packed.instantiate()
	screen.auto_navigate = false
	add_child(screen)
	schedule(1.0, func() -> void: _tap_item("partyHat"))
	schedule(2.4, func() -> void: _dreh_gooby())
	schedule(4.6, func() -> void: _tap_item("flowerCrown"))
	schedule(6.0, func() -> void: _tap_tab("brille"))
	schedule(6.8, func() -> void: _tap_item("starGlasses"))
	schedule(8.2, func() -> void: _tap_tab("ruecken"))
	schedule(9.0, func() -> void: _tap_item("propellerPack"))
	schedule(10.4, func() -> void: _dreh_gooby())


## Tippt die Karte eines bestimmten Items an (Node-Name „Item_<id>“).
func _tap_item(id: String) -> void:
	var grid: Node = screen._grid
	if grid == null:
		return
	var karte := grid.get_node_or_null("Item_%s" % id) as Control
	if karte == null:
		push_warning("[wardrobe] Karte %s nicht gefunden" % id)
		return
	tap(ui(karte.get_global_rect().get_center()))


func _tap_tab(kategorie: String) -> void:
	var box: Node = screen._tab_box
	if box == null:
		return
	var chip := box.get_node_or_null("Tab_%s" % kategorie) as Control
	if chip == null and box.get_child_count() > 0:
		chip = box.get_child(0) as Control
	if chip != null:
		tap(ui(chip.get_global_rect().get_center()))


## Dreh-Zug über die linke Vorschau-Hälfte.
func _dreh_gooby() -> void:
	var win := window_size()
	drag(Vector2(win.x * 0.16, win.y * 0.5), Vector2(win.x * 0.34, win.y * 0.52), 1.4)
