extends CanvasLayer
## LoadingVeil — Transition-Fläche des SceneRouters (W1a).
##
## Optik in W1 bewusst schlicht: Cream-Fläche + Spinner-Platzhalter.
## W1c liefert später Theme/Muster/Cover-Karte/Gooby-Motiv (W4/POLISH-3).
##
## Contract (nach W1 FROZEN): cover(reduced_motion) / reveal(reduced_motion)
## sind awaitbare Coroutinen (Router: `await veil.cover(rm)`); die Signale
## covered/revealed feuern zusätzlich für Beobachter. set_progress(0..1)
## bekommt den threaded-Load-Fortschritt vom Router.

signal covered
signal revealed

const COVER_DURATION := 0.25
const REVEAL_DURATION := 0.3
const SPINNER_SPEED := TAU

var _progress := 0.0

@onready var _root: Control = $Root
@onready var _spinner: ColorRect = $Root/Spinner


func _ready() -> void:
	layer = 100
	visible = false
	_root.modulate.a = 0.0
	_spinner.pivot_offset = _spinner.size / 2.0
	set_process(false)


func _process(delta: float) -> void:
	_spinner.rotation += SPINNER_SPEED * delta


## Deckt den Bildschirm ab; kehrt zurück, sobald das Veil voll deckt.
func cover(reduced_motion := false) -> void:
	visible = true
	set_process(not reduced_motion)
	if reduced_motion:
		_root.modulate.a = 1.0
	else:
		var tween := create_tween()
		tween.tween_property(_root, "modulate:a", 1.0, COVER_DURATION)
		await tween.finished
	covered.emit()


## Öffnet das Veil wieder; kehrt zurück, sobald es voll transparent ist.
func reveal(reduced_motion := false) -> void:
	if reduced_motion:
		_root.modulate.a = 0.0
	else:
		var tween := create_tween()
		tween.tween_property(_root, "modulate:a", 0.0, REVEAL_DURATION)
		await tween.finished
	visible = false
	set_process(false)
	revealed.emit()


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)


func get_progress() -> float:
	return _progress
