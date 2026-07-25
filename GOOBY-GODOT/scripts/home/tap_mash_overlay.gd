class_name TapMashOverlay
extends Control
## Tap-Mash-Overlay für den Tür-Steckenbleib-Gag (W2a HOUSE, Doc A §5):
## Vollbild-Tapfläche + Fortschrittsbalken mit Decay. Wird von
## door_transition.gd erzeugt und mit dessen DoorLogic verdrahtet.

signal mashed
signal completed

var logic: DoorLogic

var _bar: ProgressBar
var _label: Label


func _ready() -> void:
	# _and_offsets: im _ready (bereits im Baum) setzt die Kurzform nur die
	# Anker — die Offsets blieben 0×0 und das Overlay wäre unsichtbar.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Karten-Backdrop — weißer Hint-Text wäre auf hellem Raumboden unlesbar.
	var card := PanelContainer.new()
	card.theme_type_variation = "AcCard"
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.position.y -= 150.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(card)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	_label = Label.new()
	_label.text = I18nService.t("home.tuer.mash_hint")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(320, 26)
	box.add_child(_bar)


func _process(delta: float) -> void:
	if logic == null:
		return
	logic.mash_decay(delta)
	_bar.value = logic.mash_ratio()


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not tapped or logic == null:
		return
	accept_event()
	var war_letzter: bool = logic.ist_letzter_tap()
	# W4P1-sfx-wiring: Klopfen pro Tap, Pitch zieht mit der Kurve an.
	AudioDirector.try_play(self, "door_knock", 1.0 + 0.5 * logic.mash_ratio())
	if logic.tap_mash() == DoorLogic.State.POPPING:
		_punch(1.35)
		completed.emit()
	else:
		# Widerstandskurve (POLISH-7): Punches wachsen mit dem Fortschritt,
		# der (angekündigte) letzte Tap ploppt am größten.
		_punch(1.08 + 0.12 * logic.mash_ratio() + (0.1 if war_letzter else 0.0))
	mashed.emit()


func _punch(staerke := 1.12) -> void:
	if ThemeService.is_reduced_motion(self):
		return
	_bar.pivot_offset = _bar.size / 2.0
	_bar.scale = Vector2(staerke, maxf(0.8, 2.0 - staerke))
	var tween := create_tween()
	tween.tween_property(_bar, "scale", Vector2.ONE, 0.12)
