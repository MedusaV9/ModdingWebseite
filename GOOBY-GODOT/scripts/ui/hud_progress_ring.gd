class_name HudProgressRing
extends Control
## Level-Ring fürs HUD (W4/POLISH-4, Doc H §1.3 „(Lv◔12)“): gezeichneter
## XP-Fortschritts-Ring statt Text-Pill. Der Ring füllt sich im
## Uhrzeigersinn ab 12 Uhr; die Level-Zahl legt das HUD als Label-Kind
## mittig hinein (Node-Name „LevelValue“ bleibt Vertrag der HUD-Tests).

const TRACK_WIDTH := 4.0
const FILL_WIDTH := 5.0
const ARC_POINTS := 40

## XP-Fortschritt 0..1 (geclampt).
var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - FILL_WIDTH / 2.0
	if radius <= 0.0:
		return
	draw_arc(center, radius, 0.0, TAU, ARC_POINTS, AcTokens.TRACK_SOFT, TRACK_WIDTH, true)
	if ratio <= 0.0:
		return
	var start := -PI / 2.0
	draw_arc(
		center, radius, start, start + TAU * ratio, ARC_POINTS, AcTokens.LEAF, FILL_WIDTH, true
	)
