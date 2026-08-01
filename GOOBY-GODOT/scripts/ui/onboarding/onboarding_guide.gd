class_name OnboardingGuide
extends Node
## Handlungsgeführtes Onboarding (REST-2): die warme erste Viertelstunde
## NACH dem W1c-Dialog+Editor. Gooby zieht ein (Ankunfts-Moment), dann
## werden die Grundbedürfnisse erklärt, indem man sie TUT (streicheln,
## füttern — es gibt einen Kühlschrank!, waschen), erste Münzen, erstes
## Minispiel, erster Möbelkauf, erster Sticker, Ausblick auf Stadt/Arcade/
## Ranch. Jeder Schritt: sanfte Hinweis-Karte oben mittig (kein Zwang —
## „Überspringen“ pro Schritt, „Tour beenden“ jederzeit), Erfolgserlebnis
## beim Erfüllen (Häkchen-Karte + Funkeln + Ton).
##
## Kein neues Mechanik-Silo: Erfüllung läuft über die vorhandenen Save-
## Zähler (OnboardingGuideLogic), gefeiert wird mit UiMotion/RewardFx, die
## Stimme ist das vorhandene GoobyVoice-Gebrabbel. Fortschritt liegt
## ADDITIV in onboarding.guide (Resume nach App-Neustart inklusive).
## Bestands-Spielstände (nicht mehr „frisch“) markieren die Tour still als
## erledigt — niemand wird nachträglich betutort.

const GROUP := &"onboarding_guide"
## Anzeige-Verzögerung der Geschafft-Karte, dann kommt der nächste Schritt.
const FEIER_S := 1.6
## Erfüllungs-Puls (Sicherheitsnetz neben den GameState-Signalen).
const POLL_S := 1.0
const MAX_WIDTH_PX := 420.0
## Physisches Tippflächen-Minimum in pt (44 + Luft, wie whats_next_hint).
const TOUCH_MIN_PT := 46.0

var _gs: Object = null
var _hud_ref: Control
var _layer: CanvasLayer
var _card: PanelContainer
var _step_caption: Label
var _title: Label
var _text: Label
var _next_btn: Button
var _skip_btn: Button
var _close_btn: Button
var _timer: Timer
var _voice: GoobyVoice
var _step_index := 0
var _celebrating := false


## Tour anhängen, wenn sie für diesen Spielstand dran ist (idempotent).
## Alt-Saves werden still als erledigt markiert; Rückgabe null = keine Tour.
static func attach_to(parent: Node, gs: Object) -> OnboardingGuide:
	if gs == null or not gs.has_method("state"):
		return null
	var tree := parent.get_tree()
	if tree != null:
		var existing := tree.get_first_node_in_group(GROUP)
		if existing is OnboardingGuide:
			return existing
	var state: Dictionary = gs.state()
	var slice := OnboardingGuideLogic.slice_of(state)
	if bool(slice.get("done", false)) or bool(slice.get("skipped", false)):
		return null
	# Eine ANGEFANGENE Tour läuft immer weiter (Resume), auch wenn der Save
	# inzwischen nicht mehr „frisch“ ist — nur der Erststart ist gegated.
	var started: bool = (
		int(slice.get("step", 0)) > 0
		or (slice.get("base") is Dictionary and not (slice["base"] as Dictionary).is_empty())
	)
	if not started and not OnboardingGuideLogic.should_start(state):
		# Bestands-Save: Tour still abhaken, damit sie nie aufpoppt.
		if bool(state.get("onboarding", {}).get("done", false)):
			_write_slice(gs, {"done": true, "skipped": true, "step": 0, "base": {}})
		return null
	var guide := OnboardingGuide.new()
	guide.name = "OnboardingGuide"
	guide._gs = gs
	parent.add_child(guide)
	return guide


func _ready() -> void:
	add_to_group(GROUP)
	_layer = CanvasLayer.new()
	_layer.name = "GuideLayer"
	_layer.layer = 70
	add_child(_layer)
	_build_card()
	_setup_voice()
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(_evaluate)
	add_child(_timer)
	_timer.start()
	if _gs != null:
		if _gs.has_signal("slice_changed"):
			_gs.slice_changed.connect(func(_id: String, _data: Variant) -> void: _evaluate())
		if _gs.has_signal("coins_changed"):
			_gs.coins_changed.connect(func(_coins: int) -> void: _evaluate())
		if _gs.has_signal("stats_changed"):
			_gs.stats_changed.connect(func(_stats: Dictionary) -> void: _evaluate())
	_wire_router()
	get_viewport().size_changed.connect(_relayout)
	_resume()


func current_step_id() -> String:
	return str(OnboardingGuideLogic.step_at(_step_index).get("id", ""))


func is_celebrating() -> bool:
	return _celebrating


## --- Ablauf ------------------------------------------------------------------


func _resume() -> void:
	var slice := OnboardingGuideLogic.slice_of(_gs.state())
	_step_index = clampi(int(slice.get("step", 0)), 0, OnboardingGuideLogic.step_count() - 1)
	var fresh_entry: bool = not (slice.get("base") is Dictionary) or slice["base"].is_empty()
	_enter_step(_step_index, fresh_entry)
	if _step_index == 0:
		_arrival_moment()


func _enter_step(index: int, write_base := true) -> void:
	_step_index = index
	_celebrating = false
	if write_base:
		var base := OnboardingGuideLogic.snapshot(_gs.state())
		_persist(
			func(slice: Dictionary) -> void:
				slice["step"] = index
				slice["base"] = base
		)
	var step_id := current_step_id()
	_step_caption.text = I18nService.t(
		"onboarding.guide.schritt", {"n": index + 1, "gesamt": OnboardingGuideLogic.step_count()}
	)
	_title.text = I18nService.t("onboarding.guide.s.%s.titel" % step_id, _text_args())
	_text.text = I18nService.t("onboarding.guide.s.%s.text" % step_id, _text_args())
	var manual := str(OnboardingGuideLogic.step_at(index).get("art", "")) == "manuell"
	_next_btn.visible = manual
	_next_btn.text = I18nService.t(
		"onboarding.guide.los" if step_id == "ankunft" else "onboarding.guide.alles_klar"
	)
	_skip_btn.visible = not manual
	_relayout()
	_relayout_settled()
	UiMotion.pop_in(_card)
	_speak(_text.text)
	# Schon erfüllt (z. B. Sticker gab es früher)? Dann direkt feiern.
	_evaluate.call_deferred()


func _evaluate() -> void:
	if _celebrating or _gs == null:
		return
	var step := OnboardingGuideLogic.step_at(_step_index)
	if str(step.get("art", "")) != "auto":
		return
	var slice := OnboardingGuideLogic.slice_of(_gs.state())
	var base: Dictionary = slice.get("base") if slice.get("base") is Dictionary else {}
	if OnboardingGuideLogic.satisfied(current_step_id(), base, _gs.state()):
		_celebrate_then_advance()


## Erfolgserlebnis: Karte wird zur Geschafft-Karte (Funkeln + Ton), dann
## kommt sanft der nächste Schritt.
func _celebrate_then_advance() -> void:
	_celebrating = true
	AudioDirector.try_play(self, "ui_confirm")
	_step_caption.text = I18nService.t(
		"onboarding.guide.schritt",
		{"n": _step_index + 1, "gesamt": OnboardingGuideLogic.step_count()}
	)
	_title.text = I18nService.t("onboarding.guide.geschafft")
	_text.text = I18nService.t("onboarding.guide.s.%s.feier" % current_step_id(), _text_args())
	_next_btn.visible = false
	_skip_btn.visible = false
	UiMotion.sparkle(_card, AcTokens.GOLD)
	UiMotion.bounce(_card)
	_speak(_text.text)
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(FEIER_S).timeout
	if is_instance_valid(self) and _celebrating:
		_advance()


func _advance() -> void:
	_celebrating = false
	if _step_index + 1 >= OnboardingGuideLogic.step_count():
		_finish()
		return
	_enter_step(_step_index + 1)


func _finish() -> void:
	remove_from_group(GROUP)
	_persist(
		func(slice: Dictionary) -> void:
			slice["done"] = true
			slice["step"] = OnboardingGuideLogic.step_count()
	)
	AudioDirector.try_play(self, "mg_win")
	var breite := 640.0
	var viewport := get_viewport()
	if viewport != null:
		breite = viewport.get_visible_rect().size.x
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(host)
	RewardFx.konfetti_2d(host, 48, breite)
	_card.visible = false
	_poke_quest_hint()
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(2.0).timeout
	queue_free()


## Tour komplett beenden (×) — merken, nie wieder zeigen.
func _end_tour() -> void:
	remove_from_group(GROUP)
	AudioDirector.try_play(self, "ui_back")
	_persist(
		func(slice: Dictionary) -> void:
			slice["skipped"] = true
			slice["done"] = true
	)
	_poke_quest_hint()
	queue_free()


func _on_skip_step() -> void:
	AudioDirector.try_play(self, "ui_back")
	if not _celebrating:
		_advance()


func _on_next_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	if not _celebrating:
		_advance()


## --- Inszenierung ------------------------------------------------------------


## Kleine Ankunfts-Inszenierung: Konfetti-Regen überm Raum + Einzugs-Ton.
func _arrival_moment() -> void:
	AudioDirector.try_play(self, "ui_open")
	if RewardFx.reduced_motion(self):
		return
	var breite := 640.0
	var viewport := get_viewport()
	if viewport != null:
		breite = viewport.get_visible_rect().size.x
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(host)
	RewardFx.konfetti_2d(host, 32, breite)


func _setup_voice() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_voice = GoobyVoice.new()
	_voice.name = "GuideVoice"
	add_child(_voice)


func _speak(text: String) -> void:
	if _voice != null:
		_voice.sagt(text, "happy")


func _text_args() -> Dictionary:
	var nickname := "Gooby"
	if _gs != null:
		nickname = str(_gs.get_value("meta.goobyNickname", "Gooby"))
	return {"nickname": nickname}


## --- Karte -------------------------------------------------------------------


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "GuideKarte"
	_card.theme_type_variation = "AcCard"
	_layer.add_child(_card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	box.add_child(top_row)
	_step_caption = Label.new()
	_step_caption.name = "GuideSchritt"
	_step_caption.theme_type_variation = "CaptionLabel"
	_step_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_step_caption)
	_close_btn = SquishButton.new()
	_close_btn.name = "GuideBeenden"
	_close_btn.theme_type_variation = "GhostButton"
	_close_btn.icon = load("res://assets/ui/icons/close.svg")
	_close_btn.tooltip_text = I18nService.t("onboarding.guide.beenden")
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(_end_tour)
	top_row.add_child(_close_btn)
	_title = Label.new()
	_title.name = "GuideTitel"
	_title.theme_type_variation = "HeadlineLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_text = Label.new()
	_text.name = "GuideText"
	_text.theme_type_variation = "SoftLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 8)
	box.add_child(button_row)
	_skip_btn = SquishButton.new()
	_skip_btn.name = "GuideUeberspringen"
	_skip_btn.theme_type_variation = "GhostButton"
	_skip_btn.text = I18nService.t("ui.ueberspringen")
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.pressed.connect(_on_skip_step)
	button_row.add_child(_skip_btn)
	_next_btn = SquishButton.new()
	_next_btn.name = "GuideWeiter"
	_next_btn.theme_type_variation = "BtnLeaf"
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_on_next_pressed)
	button_row.add_child(_next_btn)


## Autowrap-Minima stehen erst NACH dem ersten Layout-Pass — beim
## allerersten Einblenden fror reset_size() sonst eine viel zu hohe Karte
## ein (Label-Minimum wird vor dem Container-Sort mit Breite 0 gemessen).
## Fire-and-forget: zwei Frames warten, dann die echte Größe nachziehen.
func _relayout_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(self) and _card != null and is_instance_valid(_card):
		_relayout()


## Oben mittig unter der Statuszeile, Breite gedeckelt (Safe-Area-bewusst).
## W14 (FB3-Audit): Tippflächen physisch ≥ 44 pt (GuideWeiter/GuideBeenden
## lagen bei 14–33 pt) und die Karte bleibt in der freien HUD-Kopf-Zone
## (hint_lane) — im Querformat lief sie sonst in die Cockpit-Spalte
## (BtnProfil/BtnIgohbie). Muster: whats_next_hint._relayout.
func _relayout() -> void:
	if _card == null:
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport(), Rect2())
	var touch_floor := UiScale.touch_px_per_pt(get_viewport()) * TOUCH_MIN_PT
	_close_btn.custom_minimum_size = Vector2.ONE * touch_floor
	_close_btn.add_theme_constant_override("icon_max_width", int(maxf(16.0 * f, 14.0)))
	_next_btn.custom_minimum_size = Vector2(touch_floor, touch_floor)
	_skip_btn.custom_minimum_size = Vector2(touch_floor, touch_floor)
	var lane := {"left": 12.0, "right": canvas.x - 12.0, "top": float(insets["top"]) + 76.0 * f}
	var hud := _find_hud()
	if hud is Hud and hud.is_visible_in_tree():
		lane = (hud as Hud).hint_lane()
	var lane_left := float(lane["left"])
	var lane_right := float(lane["right"])
	var width := minf(MAX_WIDTH_PX * f, lane_right - lane_left)
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.reset_size()
	var size_now := _card.get_combined_minimum_size()
	var x := (lane_left + lane_right - size_now.x) / 2.0
	_card.position = Vector2(maxf(x, lane_left), float(lane["top"]))


func _find_hud() -> Control:
	if _hud_ref != null and is_instance_valid(_hud_ref):
		return _hud_ref
	_hud_ref = null
	var tree := get_tree()
	if tree == null:
		return null
	# G4/P21 (QW #18): Gruppen-Lookup statt Iteration über JEDEN Control.
	for node: Node in tree.get_nodes_in_group(&"hud"):
		if node is Hud:
			_hud_ref = node
			break
	if _hud_ref != null:
		_hud_ref.visibility_changed.connect(_sync_card_visible)
	return _hud_ref


## W16 (FB3-Audit content_mitte): über Einstellungen/Patchnotes versteckt
## home_entry das HUD OHNE Router-Travel — die Tour-Karte duckt sich dann
## ebenfalls (WhatsNextHint-W14-Regel), statt über der zentrierten
## Settings-Spalte zu schweben (Overlap GuideWeiter × Sprachzeile).
func _sync_card_visible() -> void:
	if _card == null:
		return
	if _hud_ref != null and is_instance_valid(_hud_ref) and not _hud_ref.visible:
		_card.visible = false
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		_card.visible = true
		return
	_card.visible = router.get_current_scene() is RoomBase


## Über Vollbild-Screens (Arcade/Album/...) hält die Karte den Mund; die
## Erfüllung läuft weiter (z. B. „spiel ein Minispiel“ IM Spiel).
func _wire_router() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_signal("travel_started"):
		router.travel_started.connect(_on_travel_started)
	if router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


func _on_travel_started(_target: StringName = &"", _travel_type: int = 0) -> void:
	_card.visible = false


func _on_travel_finished(_target: Variant = null) -> void:
	_sync_card_visible()


## --- Save --------------------------------------------------------------------


func _persist(mutator: Callable) -> void:
	if _gs == null:
		return
	_gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("onboarding") is Dictionary):
				state["onboarding"] = {"done": true, "whatsNew5Seen": false}
			var onboarding: Dictionary = state["onboarding"]
			if not (onboarding.get("guide") is Dictionary):
				onboarding["guide"] = OnboardingGuideLogic.default_slice()
			mutator.call(onboarding["guide"])
	)
	_gs.notify_slice_changed("onboarding")


static func _write_slice(gs: Object, slice: Dictionary) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("onboarding") is Dictionary):
				state["onboarding"] = {"done": true, "whatsNew5Seen": false}
			state["onboarding"]["guide"] = slice
	)
	gs.notify_slice_changed("onboarding")


## Nach Tour-Ende darf der „Was nun?“-Hinweis sofort übernehmen.
func _poke_quest_hint() -> void:
	var service := DailyQuestService.find_service()
	if service != null:
		# Erst NACH dem Freigeben dieses Nodes zeigen (Gruppe leert sich).
		service.refresh_hint.call_deferred()
