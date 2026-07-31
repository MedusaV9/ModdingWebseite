class_name GoobyPalSheet
extends Control
## GoobyPal-Sheet (W3c VISIT): Coins an EINEN Freund senden — Betrag über
## Schnellwahl + Plus/Minus, Anzeige „Heute noch X Coins“ (Server-Limit 250/
## Tag, server enforced). Fehler kommen als DEUTSCHE Toasts über
## toast_requested (der Parent-Screen zeigt sie an). Online-only: offline
## ist der Senden-Knopf aus.
## W13/NETZ (P3 AP-3): unter dem Sende-Teil rendert das Sheet jetzt den
## PAL_HISTORY-Verlauf (GoobyPalVerlauf) — Daten kommen aus demselben
## fetch_history()-Aufruf, der schon das Tageslimit speist.

signal toast_requested(text: String)
signal closed

const QUICK_AMOUNTS: Array[int] = [10, 50, 100, 250]
const STEP := 10

var amount := 50

var _pal: GoobyPalService
var _friend: Dictionary = {}
var _amount_label: Label
var _remaining_label: Label
var _send_button: Button
var _verlauf_slot: VBoxContainer


func setup(pal_service: GoobyPalService, friend: Dictionary) -> void:
	_pal = pal_service
	_friend = friend


func _ready() -> void:
	# and_offsets: nur-Anker-Presets behalten den leeren Ist-Rect, wenn der
	# Parent beim Einhängen schon Größe hat (Sheet öffnet zur Laufzeit).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(360, 0)
	add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	card.add_child(rows)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("social.pal.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	var to_label := Label.new()
	to_label.theme_type_variation = &"HeadlineLabel"
	to_label.text = I18nService.t(
		"social.pal.to",
		{"name": "%s · %s" % [_friend.get("name", "?"), _friend.get("goobyName", "Gooby")]}
	)
	to_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(to_label)

	var quick := HBoxContainer.new()
	quick.alignment = BoxContainer.ALIGNMENT_CENTER
	quick.add_theme_constant_override("separation", 6)
	rows.add_child(quick)
	for value in QUICK_AMOUNTS:
		var btn := Button.new()
		btn.theme_type_variation = &"GhostButton"
		btn.text = str(value)
		btn.pressed.connect(_set_amount.bind(value))
		quick.add_child(btn)

	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override("separation", 12)
	rows.add_child(stepper)
	var minus := Button.new()
	minus.theme_type_variation = &"GhostButton"
	minus.text = "−"
	minus.pressed.connect(func() -> void: _set_amount(amount - STEP))
	stepper.add_child(minus)
	_amount_label = Label.new()
	_amount_label.theme_type_variation = &"TitleLabel"
	stepper.add_child(_amount_label)
	var plus := Button.new()
	plus.theme_type_variation = &"GhostButton"
	plus.text = "+"
	plus.pressed.connect(func() -> void: _set_amount(amount + STEP))
	stepper.add_child(plus)

	_remaining_label = Label.new()
	_remaining_label.theme_type_variation = &"CaptionLabel"
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_remaining_label)

	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.theme_type_variation = &"PrimaryButton"
	_send_button.text = I18nService.t("social.pal.send")
	_send_button.pressed.connect(_on_send_pressed)
	rows.add_child(_send_button)

	rows.add_child(HSeparator.new())
	_verlauf_slot = VBoxContainer.new()
	_verlauf_slot.name = "VerlaufSlot"
	rows.add_child(_verlauf_slot)

	_set_amount(amount)
	_refresh_remaining()


func _set_amount(value: int) -> void:
	var limit := _pal.daily_limit if _pal != null else GoobyPalService.DEFAULT_DAILY_LIMIT
	amount = clampi(value, 1, limit)
	_amount_label.text = "ᴳ %d" % amount


func _refresh_remaining() -> void:
	if _pal == null:
		return
	var entries: Array = []
	if _pal.is_online():
		var res: Dictionary = await _pal.fetch_history()
		if not is_instance_valid(self):
			return
		if bool(res.get("ok", false)) and res.get("entries") is Array:
			entries = res["entries"]
	_remaining_label.text = I18nService.t("social.pal.remaining", {"rest": _pal.remaining_today()})
	_send_button.disabled = not _pal.is_online()
	_render_verlauf(entries)


## Verlaufs-Sektion neu bauen (P3 AP-3). Der aktuell angeschriebene Freund
## ist immer benannt, alle weiteren Codes löst /root/Net auf (Fallback: Code).
func _render_verlauf(entries: Array) -> void:
	if _verlauf_slot == null:
		return
	for child in _verlauf_slot.get_children():
		child.queue_free()
	var namen := GoobyPalVerlauf.namen_aus_baum(self)
	var friend_code := str(_friend.get("friendCode", ""))
	if not friend_code.is_empty():
		namen[friend_code] = str(_friend.get("name", friend_code))
	_verlauf_slot.add_child(
		GoobyPalVerlauf.build_liste(
			entries,
			namen,
			int(Time.get_unix_time_from_system()),
			GoobyPalVerlauf.lokaler_offset_min()
		)
	)


func _on_send_pressed() -> void:
	if _pal == null:
		return
	_send_button.disabled = true
	var res: Dictionary = await _pal.send_coins(str(_friend.get("friendCode", "")), amount)
	if not is_instance_valid(self):
		return
	_send_button.disabled = not _pal.is_online()
	if res["ok"]:
		toast_requested.emit(
			I18nService.t(
				"social.pal.sent", {"amount": amount, "name": str(_friend.get("goobyName", "?"))}
			)
		)
		# Zieht Limit UND Verlauf frisch — der neue Eintrag erscheint sofort.
		await _refresh_remaining()
	else:
		toast_requested.emit(I18nService.t(str(res["message_key"])))


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		closed.emit()
		queue_free()
