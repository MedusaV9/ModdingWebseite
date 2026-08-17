extends "res://tools/capture/clip_driver.gd"
## Clip: GOUHBUS-Möbelausstellung („IKEA“) — Liste links, drehende 3D-Vitrine
## rechts; wir tippen Artikel und Farbmuster an wie ein stöbernder Spieler.

var screen: Control


func _setup() -> void:
	duration = 11.0
	var packed: PackedScene = load("res://scripts/shop/ikea_screen.tscn")
	screen = packed.instantiate()
	screen.auto_navigate = false
	add_child(screen)
	# Gezielt fotogene Möbel in die Vitrine holen (die Alles-Liste beginnt
	# mit Umzugskartons — fürs Schaufenster wäre das zu langweilig).
	schedule(1.2, func() -> void: screen.select_item("loungeSofa"))
	schedule(3.6, func() -> void: _tap_swatch(1))
	schedule(5.0, func() -> void: _tap_swatch(2))
	schedule(6.4, func() -> void: screen.select_item("bedDouble"))
	schedule(8.8, func() -> void: _tap_swatch(1))


func _tap_listeneintrag(n: int) -> void:
	var list: Node = screen._list
	if list == null:
		return
	var eintraege: Array[Control] = []
	for child in list.get_children():
		var c := child as Control
		if c != null and c.visible:
			eintraege.append(c)
	if eintraege.is_empty():
		return
	tap(ui(eintraege[n % eintraege.size()].get_global_rect().get_center()))


func _tap_swatch(n: int) -> void:
	var box: Node = screen._swatches
	if box == null or box.get_child_count() == 0:
		return
	var swatch := box.get_child(n % box.get_child_count()) as Control
	if swatch != null:
		tap(ui(swatch.get_global_rect().get_center()))
