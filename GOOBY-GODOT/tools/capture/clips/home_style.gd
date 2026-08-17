extends "res://tools/capture/clip_driver.gd"
## Clip: Gestalten-Modus (HAUS-CUSTOM) — der echte Customize-Screen mit
## 3D-Haus-Vorschau: Fassaden-Farben durchprobieren, dann Dach- und
## Tür-Farbe wechseln. Farbflächen sind immer im Besitz → jede Wahl
## wirkt sofort sichtbar auf die Vorschau (kein Kauf nötig).

var screen: Control


func _setup() -> void:
	duration = 8.0
	var packed: PackedScene = load("res://scripts/home/customize/customize_screen.tscn")
	screen = packed.instantiate()
	add_child(screen)
	# Nur kräftige Palettenfarben — die Pastelle (himmel/rose/mint) sind auf
	# Kameradistanz von Weiß kaum zu unterscheiden (Erkenntnis aus der
	# Einzelbild-Kontrolle der ersten Aufnahme).
	schedule(0.8, func() -> void: screen.set_kategorie("fassade"))
	schedule(1.6, func() -> void: screen.select_farbe("terracotta"))
	schedule(2.6, func() -> void: screen.select_farbe("schiefer"))
	schedule(3.6, func() -> void: screen.select_farbe("ocker"))
	schedule(4.6, func() -> void: screen.set_kategorie("dach"))
	schedule(5.4, func() -> void: screen.select_farbe("anthrazit"))
	schedule(6.2, func() -> void: screen.set_kategorie("tuer"))
	schedule(6.8, func() -> void: screen.select_farbe("teal"))
	schedule(7.4, func() -> void: screen.select_farbe("pink"))
