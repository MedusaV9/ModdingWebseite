class_name DialogBubble
extends Control
## Text-Bubble für Gooby-Sprüche (DEUTSCH über strings/). Zeigt eine
## Zeilen-Sequenz; JEDER Tap auf die Bubble blättert weiter („Weiter-Tap“).
## Signale: `advanced(index)` pro Blättern, `finished` nach der letzten Zeile.
##
## W14/UISCREENS-B (User-Bug „Notifications und Goobys Bubble überschneiden
## sich unten"): Die Bubble reserviert die BOTTOM-Zone über den UIKERN-
## Vertrag (`UiAnchors.reserve("bottom", kapsel)`) und weicht Top-Belegungen
## (Notify-Banner, Toasts) per `UiAnchors.dodge` aus; Toasts wiederum
## rutschen NIE in Bottom-Rects hinein (toast.gd) — Überschneidung ist
## damit strukturell unmöglich. Dazu Buchstaben-Typewriter im Gebrabbel-
## Tempo (DialogTypewriter, wie die Stadt-Dialoge): erster Tap zeigt die
## Zeile komplett, zweiter blättert weiter.

signal advanced(index: int)
signal finished

## Breiten-Deckel in Design-px (skaliert mit UiScale) — Web-Karten ≤ 600.
const MAX_WIDTH_PX := 600.0
## Luft zwischen Blase und HUD-Bodenzeile bzw. Safe-Area-Unterkante.
const BOTTOM_GAP := 10.0

## Test-Hook: -1 = Settings/Reduced-Motion fragen, 0/1 = sofort erzwingen.
var sofort_override := -1

var _lines: Array[String] = []
var _index := -1
var _hud_ref: Control
var _typewriter := DialogTypewriter.new()
## Szenen-Oberkante der Kapsel (tscn) — Basis für den Höhen-Pass pro Zeile.
var _szenen_offset_top := 0.0

@onready var _bubble: PanelContainer = %Bubble
@onready var _text: Label = %BubbleText
@onready var _hint: Label = %BubbleHint


func _ready() -> void:
	visible = false
	_hint.text = I18nService.t("dialog.weiter_hinweis")
	# G7-P51: Höhen-Messung immer auf dem VOLLEN Text — Godots Default
	# VC_CHARS_BEFORE_SHAPING shapt nur die getippten Zeichen, _fit_height
	# sah damit 0–2 Zeichen und lange Zeilen verloren unten ganze Zeilen
	# (Label zeichnet abgeschnittene Zeilen gar nicht). Das Zeichnen selbst
	# folgt weiter visible_characters (Typewriter unverändert).
	_text.visible_characters_behavior = TextServer.VC_GLYPHS_LTR
	_szenen_offset_top = _bubble.offset_top
	_bubble.gui_input.connect(_on_bubble_input)
	get_viewport().size_changed.connect(_relayout)
	set_process(false)
	_relayout()


func _exit_tree() -> void:
	if _bubble != null:
		UiAnchors.release(UiAnchors.ZONE_BOTTOM, _bubble)


## Sequenz anzeigen (ersetzt eine laufende Sequenz).
func show_lines(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_lines = lines.duplicate()
	_index = -1
	visible = true
	UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, _bubble)
	_relayout()
	_advance()


## UIFINAL: Im Home-HUD-Kontext lag die Blase HINTER der Boden-Zeile (Auge/
## „Wo ist mein Gooby?“-Chip schnitten in den Text) und ignorierte Safe-Area
## + UiScale. Läuft ein HUD mit, weicht die Blase dessen Boden-Zeile aus und
## skaliert ihre Schriften; ohne HUD (Stadt-Dialoge) bleibt die Szenen-
## Geometrie unangetastet — deren Options-Stapel rechnet mit ihr.
func _relayout() -> void:
	if _bubble == null or not is_inside_tree():
		return
	var hud := _find_hud()
	if hud == null or not hud.is_visible_in_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_text.add_theme_font_size_override("font_size", int(maxf(AcTokens.FONT_SIZE_BODY * f, 12.0)))
	_hint.add_theme_font_size_override("font_size", int(maxf(AcTokens.FONT_SIZE_CAPTION * f, 10.0)))
	var safe_w := canvas.x - float(insets["left"]) - float(insets["right"])
	var width := minf(MAX_WIDTH_PX * f, safe_w - 24.0 * f)
	var lane_top: float = canvas.y - float(insets["bottom"])
	if hud is Hud:
		var lane: Dictionary = (hud as Hud).bubble_lane()
		lane_top = float(lane["top"])
		width = minf(width, float(lane["width"]))
	_bubble.offset_left = -width / 2.0
	_bubble.offset_right = width / 2.0
	_bubble.offset_bottom = -(canvas.y - lane_top) - BOTTOM_GAP * f
	# Höhe folgt dem Inhalt (Autowrap braucht die finale Breite — deshalb
	# nach einem Frame nachziehen, s. whats_next_hint._relayout_settled).
	_fit_height()
	_fit_height_settled()


func _fit_height() -> void:
	# W20 P1 (Befund-Top-9): die Unterkante rutscht ÜBER das offene
	# Bau-Dock (P2-Schnittstelle BuildUiDock.aktive_zone), statt dass der
	# Text auf Drehen/Platzieren/Abbrechen liegt.
	_weiche_bau_dock_aus()
	var needed := _benoetigte_hoehe()
	_bubble.offset_top = _bubble.offset_bottom - maxf(needed, 96.0)
	# W14-Zonen-Regel (UIKERN-Vertrag): Top-Belegungen (Banner/Toasts) nie
	# überdecken — schneidet die Blase ein Top-Rect, rückt `dodge` sie
	# darunter; wir übernehmen nur die abgesenkte OBERkante (Unterkante
	# bleibt in der Boden-Lane verankert, die Blase wird schlicht flacher).
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var rect := Rect2(
		Vector2(canvas.x / 2.0 + _bubble.offset_left, canvas.y + _bubble.offset_top),
		Vector2(
			_bubble.offset_right - _bubble.offset_left, _bubble.offset_bottom - _bubble.offset_top
		)
	)
	var gedodgt := UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_TOP, _bubble), UiAnchors.ZONE_TOP
	)
	_bubble.offset_top = maxf(_bubble.offset_top, gedodgt.position.y - canvas.y)


## W20 P1 — Wortbruch-Wache: Container-Minima sind im Aufruf-Frame stale
## (W18-Lehre; bei Breite 0 misst Autowrap Zeichen-für-Zeile) — die Höhe
## wird deshalb DETERMINISTISCH über die Schrift gemessen (Muster
## AcBubble._wrap_hoehe) und mit dem Container-Minimum verodert: die Blase
## reserviert IMMER genug Höhe für den ganzen Text, nichts endet mitten
## im Wort oder in einer verschluckten Zeile.
func _benoetigte_hoehe() -> float:
	var kombi := _bubble.get_combined_minimum_size()
	var chrome := kombi.y - _text.get_combined_minimum_size().y
	var rand_x := 0.0
	var sb := _bubble.get_theme_stylebox("panel")
	if sb != null:
		rand_x = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	var wrap_w := (_bubble.offset_right - _bubble.offset_left) - rand_x
	return maxf(kombi.y, chrome + _text_hoehe(wrap_w))


## Volle Zeilenhöhe des an WORT-Grenzen gewickelten Textes bei `wrap_w`
## (Spiegel von AUTOWRAP_WORD) inkl. Label-Zeilenabstand; Zeilenzahl wird
## AUFgerundet, Breite ≤ 0 ist verboten (W19-Lehre).
func _text_hoehe(wrap_w: float) -> float:
	var font := _text.get_theme_font("font")
	var font_size := _text.get_theme_font_size("font_size")
	if font == null or font_size <= 0 or wrap_w <= 0.0:
		return 0.0
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	var gemessen := font.get_multiline_string_size(
		_text.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, font_size, -1, brk
	)
	var zeilen := maxi(1, ceili(gemessen.y / maxf(font.get_height(font_size), 1.0) - 0.05))
	return gemessen.y + float((zeilen - 1) * _text.get_theme_constant("line_spacing"))


## W20 P1: liegt die Blase horizontal über dem OFFENEN Bau-Dock, rutscht
## ihre Unterkante über dessen Sperrzone (Rect2() = kein Dock → No-op).
func _weiche_bau_dock_aus() -> void:
	var dock := BuildUiDock.aktive_zone()
	if dock.size.y <= 0.0 or not is_inside_tree():
		return
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var links := canvas.x / 2.0 + _bubble.offset_left
	var rechts := canvas.x / 2.0 + _bubble.offset_right
	if rechts <= dock.position.x or links >= dock.end.x:
		return
	_bubble.offset_bottom = minf(_bubble.offset_bottom, dock.position.y - BOTTOM_GAP - canvas.y)


func _fit_height_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if is_instance_valid(self) and _bubble != null and is_instance_valid(_bubble):
		_fit_height()


## G7-P51: Höhen-Pass für die AKTUELLE Zeile. Mit HUD (Home) macht _relayout
## den vollen Pass; ohne HUD (Stadt-Dialoge) wächst nur die Oberkante nach
## oben, wenn der Text mehr Platz braucht — Breite/Unterkante der Szenen-
## Geometrie bleiben unangetastet (deren Options-Stapel rechnet mit ihnen).
func _zeilen_fit() -> void:
	if _bubble == null or not is_inside_tree():
		return
	var hud := _find_hud()
	if hud != null and hud.is_visible_in_tree():
		_fit_height()
		_fit_height_settled()
		return
	# W20 P1: deterministische Text-Messung auch im Stadt-Pfad — das
	# Container-Minimum allein untertreibt im Aufruf-Frame (W18-Lehre).
	var needed := _benoetigte_hoehe()
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	var deckel := -(canvas.y - float(insets["top"]) - 8.0)
	# Pro Zeile frisch von der Szenen-Höhe aus rechnen — nach einer langen
	# Zeile schrumpft die Blase für kurze Folge-Zeilen wieder zurück.
	_bubble.offset_top = maxf(minf(_szenen_offset_top, _bubble.offset_bottom - needed), deckel)


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
	return _hud_ref


func is_active() -> bool:
	return visible and _index >= 0


func current_line() -> String:
	return _text.text


## Buchstaben-Typewriter (W14): Zeichen erscheinen im Gebrabbel-Tempo.
func _process(delta: float) -> void:
	if not _typewriter.laeuft():
		set_process(false)
		return
	_typewriter.tick(delta)
	_zeige_zeichen()
	if _typewriter.ist_fertig():
		set_process(false)


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		visible = false
		UiAnchors.release(UiAnchors.ZONE_BOTTOM, _bubble)
		finished.emit()
		return
	_text.text = _lines[_index]
	_typewriter.start(_lines[_index], _sofort_modus())
	_zeige_zeichen()
	set_process(_typewriter.laeuft())
	_hint.visible = _index < _lines.size() - 1
	# G7-P51: Höhe pro ZEILE nachziehen — _relayout lief nur bei show_lines/
	# Resize und maß noch den ALTEN (bzw. leeren) Text.
	_zeilen_fit()
	advanced.emit(_index)
	_pop()


func _zeige_zeichen() -> void:
	if _typewriter.ist_fertig():
		_text.visible_characters = -1
		return
	# EVAL-2026-08 Befund 18 (wie AcBubble): WORT-weise enthüllen — kein
	# Standbild zeigt je ein angerissenes Wort mitten im Satz.
	_text.visible_characters = AcBubble.wort_grenze(_text.text, _typewriter.sichtbar)


## Sofort-Modus wie die Stadt-Dialoge: Reduced Motion oder die Einstellung
## „Schnelle Dialoge“ zeigen die Zeile ohne Ticks komplett.
func _sofort_modus() -> bool:
	if sofort_override >= 0:
		return sofort_override == 1
	if ThemeService.is_reduced_motion(self):
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("get_setting", "game.schnelle_dialoge", false))


func _pop() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	_bubble.pivot_offset = _bubble.size / 2.0
	_bubble.scale = Vector2.ONE * 0.92
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bubble, "scale", Vector2.ONE, AcTokens.DUR_POP)


func _on_bubble_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Erster Tap: laufende Zeile sofort komplett; zweiter blättert.
		if _typewriter.laeuft():
			_typewriter.skip()
			_zeige_zeichen()
			set_process(false)
			return
		_advance()
