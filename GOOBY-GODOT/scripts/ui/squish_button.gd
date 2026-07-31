class_name SquishButton
extends Button
## EIN Press-Feedback-Skript für alle AC-Buttons (H §1.1). W14/UIKERN:
## satterer „Squish“ nach Web-Vorbild (`.btn:active` + --ease-spring):
## Press = Scale auf PRESS_SCALE (0.94, der Schatten wird über die
## pressed-StyleBox gleichzeitig kürzer), Release = kurzer Overshoot ÜBER
## die Ruhelage (SQUISH_OVERSHOOT) und federnd (TRANS_BACK/EASE_OUT =
## --ease-spring) zurück. Respektiert Reduced Motion (ThemeService).
##
## Haptik läuft ZENTRAL hier: jeder Knopfdruck feuert Haptics.tap() —
## Screens verdrahten nichts selbst (Gate `game.haptik` sitzt in Haptics).

var _tween: Tween


func _ready() -> void:
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	resized.connect(_center_pivot)
	_center_pivot()


func _center_pivot() -> void:
	pivot_offset = size / 2.0


func _on_down() -> void:
	# Haptik ist KEINE Motion — sie feuert auch bei Reduced Motion.
	Haptics.tap(self)
	if ThemeService.is_reduced_motion(self):
		return
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * AcTokens.PRESS_SCALE, AcTokens.DUR_POP / 2.0)


func _on_up() -> void:
	if ThemeService.is_reduced_motion(self):
		scale = Vector2.ONE
		return
	_kill_tween()
	_tween = create_tween()
	# Overshoot-Bounce: erst über die Ruhelage hinaus, dann federnd zurück.
	(
		_tween
		. tween_property(
			self, "scale", Vector2.ONE * AcTokens.SQUISH_OVERSHOOT, AcTokens.DUR_POP * 0.5
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween
		. tween_property(self, "scale", Vector2.ONE, AcTokens.DUR_POP * 0.7)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
