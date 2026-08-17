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
## DEFINIERTE Maximalhöhe der Karte als Canvas-Anteil (W18 Befund 1: die
## Karte fror bei einer Breite-0-Messung als >5400-px-Säule ein und
## verschluckte als mouse_filter-STOP-Fläche das HUD-/Bau-Dock). Der Text
## wickelt in einem Scroll-Fenster, das diesen Deckel nie überschreitet —
## deutlich unter der 45-%-Wächter-Schranke des Playtests.
const MAX_HOEHE_ANTEIL := 0.42
## Physisches Tippflächen-Minimum in pt (44 + Luft, wie whats_next_hint).
const TOUCH_MIN_PT := 46.0

var _gs: Object = null
var _hud_ref: Control
var _router: Node
var _layer: CanvasLayer
var _card: PanelContainer
var _step_caption: Label
var _title: Label
var _text: Label
var _top_row: HBoxContainer
var _scroll: ScrollContainer
var _text_box: VBoxContainer
var _button_row: HBoxContainer
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


## Sichtbarkeit jeden Frame nachziehen (Muster whats_next_hint._process):
## Baumodus/Blätter verdecken das HUD OHNE Travel und ohne Signal an uns —
## die Karte muss sich dann sofort ducken, statt über dem Bau-Dock zu
## schweben (W18 Befund 1, Quer-Fall).
func _process(_delta: float) -> void:
	_sync_card_visible()


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
	_focus_actions.call_deferred()
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
	_relayout()
	_focus_actions.call_deferred()
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
	# Der Frame-Sync würde die Karte übers Konfetti-Fenster wieder einblenden.
	set_process(false)
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
	set_process(false)
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
	# Eingaben schluckt NUR die sichtbare Kartenfläche (Standard-STOP des
	# PanelContainer) — es gibt bewusst keinen Vollflächen-Scrim darunter.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	# W20 P1 Nachfix (FB3 kombi_overlap „Toast×Guide“): Toasts teilen sich
	# die Kopf-Zone mit der Karte — als toast_hindernis rutschen sie unter
	# ihre Unterkante (Vertrag im toast.gd-Kopf), nie auf Weiter/Beenden.
	_card.add_to_group(ToastLayer.HINDERNIS_GROUP)
	_layer.add_child(_card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_top_row = HBoxContainer.new()
	_top_row.add_theme_constant_override("separation", 8)
	box.add_child(_top_row)
	_step_caption = Label.new()
	_step_caption.name = "GuideSchritt"
	_step_caption.theme_type_variation = "CaptionLabel"
	_step_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_row.add_child(_step_caption)
	_close_btn = SquishButton.new()
	_close_btn.name = "GuideBeenden"
	_close_btn.theme_type_variation = "GhostButton"
	_close_btn.icon = load("res://assets/ui/icons/close.svg")
	_close_btn.tooltip_text = I18nService.t("onboarding.guide.beenden")
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(_end_tour)
	_top_row.add_child(_close_btn)
	# Titel + Text wickeln in einem höhen-gedeckelten Scroll-Fenster: die
	# Karte hat damit eine DEFINIERTE Maximalhöhe (MAX_HOEHE_ANTEIL) und
	# kann nie wieder als bildschirmhohe Säule HUD-/Bau-Dock verdecken.
	_scroll = ScrollContainer.new()
	_scroll.name = "GuideTextScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(_scroll)
	_text_box = VBoxContainer.new()
	_text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_text_box)
	_title = Label.new()
	_title.name = "GuideTitel"
	_title.theme_type_variation = "HeadlineLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_box.add_child(_title)
	_text = Label.new()
	_text.name = "GuideText"
	_text.theme_type_variation = "SoftLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_box.add_child(_text)
	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_END
	_button_row.add_theme_constant_override("separation", 8)
	box.add_child(_button_row)
	_skip_btn = SquishButton.new()
	_skip_btn.name = "GuideUeberspringen"
	_skip_btn.theme_type_variation = "GhostButton"
	_skip_btn.text = I18nService.t("ui.ueberspringen")
	_skip_btn.focus_mode = Control.FOCUS_ALL
	_skip_btn.pressed.connect(_on_skip_step)
	_button_row.add_child(_skip_btn)
	_next_btn = SquishButton.new()
	_next_btn.name = "GuideWeiter"
	_next_btn.theme_type_variation = "BtnLeaf"
	_next_btn.focus_mode = Control.FOCUS_ALL
	_next_btn.pressed.connect(_on_next_pressed)
	_button_row.add_child(_next_btn)
	_card.visibility_changed.connect(_on_card_visibility_changed)


## Primäraktion zuerst, Tour-Beenden zuletzt. So landet Gamepad-/Tastatur-
## Fokus nie auf einer unsichtbaren Aktion und Escape bleibt eine Alternative.
func _focus_actions() -> void:
	_sync_card_visible()
	if _card == null or not _card.is_visible_in_tree():
		return
	var actions: Array[Control] = []
	if _next_btn.visible:
		actions.append(_next_btn)
	if _skip_btn.visible:
		actions.append(_skip_btn)
	actions.append(_close_btn)
	FocusNavigation.wire_controls(actions, true)
	if not actions.is_empty():
		actions[0].grab_focus()


## Nachzieh-Pass: zwei Frames nach dem Container-Sort noch einmal messen
## (deckt z. B. die schmalere Textspalte ab, sobald die Scrollbar
## eingeblendet wurde). Fire-and-forget; seit W18 nur noch Feinschliff —
## die Erstmessung ist dank durchgereichter Wrap-Breite bereits korrekt.
func _relayout_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(self) and _card != null and is_instance_valid(_card):
		_relayout()


## Beim Wieder-Einblenden (z. B. nach Router-Travel oder Baumodus-Ende)
## einmal frisch layouten — im versteckten Zustand propagieren Controls
## keine Minimum-Änderungen, eine dort liegengebliebene Messung wäre stale.
func _on_card_visibility_changed() -> void:
	if _card != null and _card.visible and is_inside_tree():
		_relayout()
		_focus_actions.call_deferred()


## Oben mittig unter der Statuszeile, Breite gedeckelt (Safe-Area-bewusst).
## W14 (FB3-Audit): Tippflächen physisch ≥ 44 pt (GuideWeiter/GuideBeenden
## lagen bei 14–33 pt) und die Karte bleibt in der freien HUD-Kopf-Zone
## (hint_lane) — im Querformat lief sie sonst in die Cockpit-Spalte
## (BtnProfil/BtnIgohbie). Muster: whats_next_hint._relayout.
## W18 (Playtest Befund 1): Autowrap-Minima gelten immer nur für die
## AKTUELLE Label-Breite — bei Breite 0 misst WORD_SMART Zeichen-für-Zeile
## (>5400 px Säule) und reset_size() fror das ein; der Zwei-Frame-
## Nachzieher lief ins Leere, weil home_entry direkt nach attach_to einen
## Router-Travel startet und die travel-versteckte Karte nie nachsortiert
## (versteckte Controls propagieren keine Minimum-Änderungen). Deshalb:
## Wrap-Breite VOR jeder Messung direkt auf die Labels legen und die
## Texthöhe über den Scroll-Deckel hart auf MAX_HOEHE_ANTEIL begrenzen.
func _relayout() -> void:
	if _card == null or not is_inside_tree():
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
	# Wrap-Breite durchreichen und die Labels DIREKT messen: set_size formt
	# den Text sofort an der neuen Breite um, get_minimum_size() liefert die
	# frische Umbruch-Höhe. (get_combined_minimum_size über die Container
	# wäre der veraltete Minimum-Cache — genau der fror die Säule ein.)
	var innen := _inhalts_breite(width)
	_title.size = Vector2(innen, 0.0)
	_text.size = Vector2(innen, 0.0)
	var inhalt_h := _title.get_minimum_size().y + 6.0 + _text.get_minimum_size().y
	var budget := maxf(MAX_HOEHE_ANTEIL * canvas.y - _feste_hoehe(), 48.0 * f)
	_scroll.custom_minimum_size = Vector2(0.0, minf(inhalt_h, budget))
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.reset_size()
	var size_now := _card.get_combined_minimum_size()
	var x := (lane_left + lane_right - size_now.x) / 2.0
	var y := minf(float(lane["top"]), canvas.y - float(insets["bottom"]) - size_now.y)
	_card.position = Vector2(maxf(x, lane_left), maxf(y, 0.0))


## Innenbreite der Karte (Wrap-Breite der Labels): Kartenbreite minus
## Panel-Stylebox und Margin-Container (2 × 12 px).
func _inhalts_breite(karten_breite: float) -> float:
	var rand := 24.0
	var stylebox := _card.get_theme_stylebox(&"panel")
	if stylebox != null:
		rand += stylebox.get_margin(SIDE_LEFT) + stylebox.get_margin(SIDE_RIGHT)
	return maxf(karten_breite - rand, 40.0)


## Höhe aller NICHT scrollenden Kartenteile — das Restbudget unter dem
## MAX_HOEHE_ANTEIL-Deckel gehört dem Text-Scroll-Fenster.
func _feste_hoehe() -> float:
	var fest := 24.0 + 2.0 * 6.0
	var stylebox := _card.get_theme_stylebox(&"panel")
	if stylebox != null:
		fest += stylebox.get_margin(SIDE_TOP) + stylebox.get_margin(SIDE_BOTTOM)
	fest += _top_row.get_combined_minimum_size().y
	fest += _button_row.get_combined_minimum_size().y
	return fest


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
## W18 (Playtest Befund 1): dasselbe gilt für Baumodus/offene Blätter
## (HudSichtbarkeit.verdeckt) — die Karte hat über dem Bau-Dock nichts
## verloren und kommt nach dem „Fertig“ von selbst zurück.
func _sync_card_visible() -> void:
	if _card == null:
		return
	_card.visible = _karte_erlaubt()


func _karte_erlaubt() -> bool:
	# W18/J1 (Playtest-Befund E4 „Overlay-Stau“): solange der Overlay-
	# Dirigent ein Willkommens-Overlay zeigt oder Tickets offen hat
	# (Tagesbonus/Coachmark/Geburtstag), duckt sich die Tour-Karte — nie
	# wieder zwei Willkommens-Schichten übereinander. Nach der Sequenz
	# holt der Frame-Sync (_process) die Karte von selbst zurück.
	# W20 P1 (Befund-Top-4 „Guide-Karte ÜBER dem Status-Sheet“): die Lücke
	# im Protokoll war das HUD-EIGENE Status-Sheet — es zählt in
	# HudSichtbarkeit bewusst NICHT als Verdeckung (das HUD würde sich
	# sonst selbst mitsamt Blatt ausblenden) und der Dirigent kennt es
	# nicht (kein Willkommens-Overlay). Deshalb zusätzlich zum Dirigenten-
	# Check direkt: solange IRGENDEIN Panel/Sheet im globalen Stack lebt,
	# duckt sich die Karte (WhatsNextHint-W14-Regel, _should_suppress).
	var dirigent := OverlayDirigent.find(self)
	if (dirigent != null and dirigent.belegt()) or PanelStack.count() > 0:
		return false
	var hud := _find_hud()
	if hud is Hud:
		if not hud.visible:
			return false
		var dynamik := (hud as Hud).sichtbarkeit()
		if dynamik != null and dynamik.verdeckt():
			return false
	if _router == null or not _router.has_method("get_current_scene"):
		return true
	if _router.has_method("is_busy") and _router.is_busy():
		return false
	return _router.get_current_scene() is RoomBase


## Über Vollbild-Screens (Arcade/Album/...) hält die Karte den Mund; die
## Erfüllung läuft weiter (z. B. „spiel ein Minispiel“ IM Spiel).
func _wire_router() -> void:
	_router = get_node_or_null("/root/SceneRouter")
	if _router == null:
		return
	if _router.has_signal("travel_started"):
		_router.travel_started.connect(_on_travel_started)
	if _router.has_signal("travel_finished"):
		_router.travel_finished.connect(_on_travel_finished)


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
