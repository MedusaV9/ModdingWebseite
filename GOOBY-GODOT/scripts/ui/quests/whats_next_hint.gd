class_name WhatsNextHint
extends Control
## Dezenter „Was nun?“-Hinweis (REST-2, roter Faden): eine kleine AC-Karte
## oben mittig, die den nächsten sinnvollen Schritt vorschlägt (Vorschlag
## kommt vom WhatsNextAdvisor über den DailyQuestService). Bewusst leise:
## blendet nach ein paar Sekunden von selbst aus, ist pro Vorschlag+Tag nur
## einmal wegdrückbar (×) und tippbar (öffnet z. B. das Quest-Panel).
##
## UIFINAL-Neuaufbau (FB3-Regression „Riesen-X / Mini-Text“):
## - Klare Hierarchie: Funken-Icon im weichen Gelb-Well, Überschrift als
##   kleine 800er-Zeile, der VORSCHLAG ist die Hauptsache (Ink, größer).
## - Alles skaliert über die zentrale UiScale-Regel (vorher Design-px pur —
##   auf Retina winzig neben dem ungedeckelten 96-px-Schließen-Icon).
## - Schließen-Knopf: physische Tippfläche ≥ 44 pt, Icon gedeckelt.
## - Die Karte DUCKT sich, solange ein Panel/Sheet offen ist (PanelStack)
##   oder das HUD versteckt wurde (Einstellungen/Patchnotes) — vorher
##   schwebte sie über fremden Screens (17 Audit-Befunde).

signal tapped(suggestion: Dictionary)
signal dismissed(suggestion: Dictionary)

const ICON_DIR := "res://assets/ui/icons/"
## Gruppe der sichtbaren Karte — der Toast-Layer weicht ihr aus (toast.gd).
const CARD_GROUP := &"wasnun_karte"
## Nach so vielen Sekunden räumt sich der Hinweis selbst weg (kein Nerven).
const AUTO_HIDE_S := 14.0
const MAX_WIDTH_PX := 380.0
## Physisches Tippflächen-Minimum (44 pt + Layout-Reserve, s. hud.gd).
const TOUCH_MIN_PT := 46.0
## Unter dieser Lane-Breite (Design-px) fliegt der Icon-Well raus: im engen
## Telefon-Querformat (Status-Spalte links, Cockpit rechts) braucht der TEXT
## jede Spalte — sonst bricht er wortweise um (Runde-2-Befund, 2556×1179).
const WELL_MIN_LANE_PX := 300.0

var _suggestion: Dictionary = {}
var _card: PanelContainer
var _margin: MarginContainer
var _row: HBoxContainer
var _icon_well: PanelContainer
var _icon: TextureRect
var _title: Label
var _text: Label
var _close: Button
var _timer: Timer
## true, solange ein Panel/Sheet offen ist oder das HUD versteckt wurde.
var _suppressed := false
var _hud_ref: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_hint)
	add_child(_timer)
	_build_card()
	get_viewport().size_changed.connect(_relayout)


func _process(_delta: float) -> void:
	if not visible:
		return
	var suppress := _should_suppress()
	if suppress == _suppressed:
		return
	_suppressed = suppress
	_card.visible = not suppress
	# Auto-Hide pausiert, solange die Karte geduckt ist — nach dem Schließen
	# des Panels bekommt der Hinweis wieder seine volle Lesezeit.
	if suppress:
		_timer.stop()
	else:
		_timer.start(AUTO_HIDE_S)


func show_suggestion(suggestion: Dictionary) -> void:
	var was_same := str(suggestion.get("id", "")) == str(_suggestion.get("id", ""))
	_suggestion = suggestion.duplicate(true)
	_title.text = I18nService.t("quests.wasnun.titel")
	_text.text = _resolve_text(suggestion)
	_relayout()
	if visible and was_same:
		return
	visible = true
	_suppressed = _should_suppress()
	_card.visible = not _suppressed
	_relayout_settled()
	if not _suppressed:
		UiMotion.pop_in(_card)
	_timer.start(AUTO_HIDE_S)


func hide_hint() -> void:
	visible = false
	_timer.stop()


## Vorschlagstext auflösen — `titel_key` in den Args wird zuerst übersetzt
## (z. B. quests.wasnun.quest mit dem Titel der offenen Quest).
func _resolve_text(suggestion: Dictionary) -> String:
	var args: Dictionary = {}
	var raw: Variant = suggestion.get("args", {})
	if raw is Dictionary:
		args = (raw as Dictionary).duplicate()
	if args.has("titel_key"):
		args["titel"] = I18nService.t(str(args["titel_key"]))
		args.erase("titel_key")
	return I18nService.t(str(suggestion.get("text_key", "")), args)


## Der Hinweis gehört zum Home-HUD: sobald ein Panel/Sheet offen ist oder
## das HUD ausgeblendet wurde (Einstellungen liegen als Overlay darüber),
## hat er im Bild nichts verloren.
func _should_suppress() -> bool:
	if PanelStack.count() > 0:
		return true
	var hud := _find_hud()
	return hud != null and not hud.is_visible_in_tree()


func _find_hud() -> Control:
	if _hud_ref != null and is_instance_valid(_hud_ref):
		return _hud_ref
	_hud_ref = null
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.root.find_children("*", "Control", true, false):
		if node is Hud:
			_hud_ref = node
			break
	return _hud_ref


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "WasNunKarte"
	_card.theme_type_variation = "AcCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	_card.add_to_group(CARD_GROUP)
	add_child(_card)
	_margin = MarginContainer.new()
	_card.add_child(_margin)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_row)
	# Funken-Icon im weichen Gelb-Well — ein ruhiger Blickfang links.
	_icon_well = PanelContainer.new()
	_icon_well.name = "WasNunIconWell"
	var well := StyleBoxFlat.new()
	well.bg_color = Color(AcTokens.YELLOW, 0.28)
	well.set_corner_radius_all(AcTokens.RADIUS_PILL)
	_icon_well.add_theme_stylebox_override("panel", well)
	_icon_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_icon_well)
	_icon = TextureRect.new()
	_icon.texture = load(ICON_DIR + "sparkle.svg")
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.self_modulate = AcTokens.YELLOW_DARK
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_well.add_child(_icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(text_box)
	# Kleine 800er-Überschrift — der VORSCHLAG darunter ist die Hauptsache.
	_title = Label.new()
	_title.theme_type_variation = "CaptionLabel"
	_title.add_theme_font_override("font", ThemeService.font(800))
	_title.add_theme_color_override("font_color", AcTokens.YELLOW_DARK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_title)
	_text = Label.new()
	_text.add_theme_font_override("font", ThemeService.font(700))
	_text.add_theme_color_override("font_color", AcTokens.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_text)
	_close = SquishButton.new()
	_close.name = "WasNunSchliessen"
	_close.theme_type_variation = "GhostButton"
	_close.icon = load(ICON_DIR + "close.svg")
	_close.focus_mode = Control.FOCUS_NONE
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void: dismissed.emit(_suggestion))
	_row.add_child(_close)


## Autowrap-Minima stehen erst NACH dem ersten Layout-Pass — beim ersten
## Einblenden fror reset_size() sonst eine zu hohe Karte ein. Zwei Frames
## warten, dann die echte Größe nachziehen (fire-and-forget).
func _relayout_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(self) and _card != null and is_instance_valid(_card):
		_relayout()


## Oben mittig unter der Statuszeile — schmal gedeckelt, Safe-Area-bewusst.
## Alle Maße/Schriften skalieren über die zentrale UiScale-Regel (FIX1).
func _relayout() -> void:
	if _card == null:
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport(), Rect2())
	_margin.add_theme_constant_override("margin_left", int(14.0 * f))
	_margin.add_theme_constant_override("margin_right", int(10.0 * f))
	_margin.add_theme_constant_override("margin_top", int(10.0 * f))
	_margin.add_theme_constant_override("margin_bottom", int(10.0 * f))
	_row.add_theme_constant_override("separation", int(12.0 * f))
	_icon_well.custom_minimum_size = Vector2.ONE * roundf(36.0 * f)
	_icon.custom_minimum_size = Vector2.ONE * roundf(20.0 * f)
	_title.add_theme_font_size_override("font_size", int(maxf(13.0 * f, 10.0)))
	_text.add_theme_font_size_override("font_size", int(maxf(17.0 * f, 12.0)))
	# Schließen: physische Tippfläche ≥ 44 pt, Icon gedeckelt (das rohe SVG
	# ist 96 px groß und sprengte vorher den Knopf).
	var touch_floor := UiScale.touch_px_per_pt(get_viewport()) * TOUCH_MIN_PT
	_close.custom_minimum_size = Vector2.ONE * touch_floor
	_close.add_theme_constant_override("icon_max_width", int(maxf(16.0 * f, 14.0)))
	# Freie Kopf-Zone vom HUD erfragen (Querformat: zwischen Status-Spalte
	# und Zahnrad — nie über der Cockpit-Spalte); ohne HUD: unter der
	# gedachten Statuszeile, mittig.
	var lane := {"left": 12.0, "right": canvas.x - 12.0, "top": float(insets["top"]) + 76.0 * f}
	var hud := _find_hud()
	if hud is Hud and hud.is_visible_in_tree():
		lane = (hud as Hud).hint_lane()
	var lane_left := float(lane["left"])
	var lane_right := float(lane["right"])
	var width := minf(MAX_WIDTH_PX * f, lane_right - lane_left)
	# Enge Lane (Telefon quer): Icon-Well opfern, damit der Vorschlagstext
	# ordentlich zweizeilig läuft statt Wort für Wort zu tröpfeln.
	_icon_well.visible = (lane_right - lane_left) >= WELL_MIN_LANE_PX * f
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.reset_size()
	var size_now := _card.get_combined_minimum_size()
	var x := (lane_left + lane_right - size_now.x) / 2.0
	_card.position = Vector2(maxf(x, lane_left), float(lane["top"]))


func _on_card_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		AudioDirector.try_play(self, "ui_chip")
		tapped.emit(_suggestion)
