class_name SquishButton
extends Button
## EIN Press-Feedback-Skript für alle AC-Buttons (H §1.1): Scale-Tween auf
## 0.96 beim Drücken, federnd zurück (TRANS_BACK/EASE_OUT = --ease-spring).
## Respektiert Reduced Motion (via ThemeService-Duck-Typing).

var _tween: Tween


func _ready() -> void:
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	resized.connect(_center_pivot)
	_center_pivot()


func _center_pivot() -> void:
	pivot_offset = size / 2.0


func _on_down() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * AcTokens.PRESS_SCALE, AcTokens.DUR_POP / 2.0)


func _on_up() -> void:
	if ThemeService.is_reduced_motion(self):
		scale = Vector2.ONE
		return
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, AcTokens.DUR_POP)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
