class_name AcBubble
extends Control
## W14/UIKERN — DIE ACNH-Sprechblase (User-Feedback: „animierte runde süße
## Sprechblasen“). Weiche runde Paper-Kapsel (Web `.toast`: Radius 22,
## Outline-Ring + Shadow-Pop) mit:
##
##  - wackligem Pop-In (Scale-Bounce + Mini-Rotation, --ease-spring),
##  - leichtem Atmen (Sinus-Skalierung ±1,5 %),
##  - Buchstaben-Typewriter über die BESTEHENDE DialogTypewriter-Logik
##    (Gebrabbel-Tempo; Reduced Motion / „Schnelle Dialoge“ = sofort),
##  - kleinem Sprech-Schwanz Richtung Sprecher (`speaker_3d` folgt dem
##    Kopf im Screen-Space),
##  - Auto-Hide mit Shrink-Pop nach `dauer_s`,
##  - Queue: max. 2 Blasen gleichzeitig, weitere warten (pure Logik in
##    der inneren Klasse `Warteschlange`, headless getestet).
##
## API (FROZEN für W14-Screen-Agents):
##   AcBubble.show_bubble(layer, text, opts) -> AcBubble
##   opts: "speaker_3d": Node3D, "dauer_s": float (3.5), "tail": bool,
##         "stil": "gooby" | "system" | "witz"
##   bubble.ersetze_text(text) -> bool   (lebende Blase wiederverwenden —
##   Dauersprecher wie RoomBase.say stauen so keine Nodes auf)
##
## Anker-Deconflict: die Kapsel reserviert die UiAnchors-Zone "bottom";
## belegte Bottom-Rects (zweite Blase) werden ÜBERsprungen (+8 px), die
## top-Zone (Notify-Banner) wird nie überdeckt.

## Umbenannt von `hidden` — kollidierte mit dem nativen CanvasItem-Signal
## (Parse-Fehler, s. >> VOICE→UIKERN).
signal ausgeblendet

const STIL_GOOBY := "gooby"
const STIL_SYSTEM := "system"
const STIL_WITZ := "witz"

const MAX_AKTIV := 2
const DAUER_DEFAULT_S := 3.5
## Web .toast: border-radius 1.375rem = 22 px.
const RADIUS := 22
const MAX_WIDTH_PX := 460.0
const ATEM_AMPLITUDE := 0.015
const ATEM_PERIODE_S := 2.6
const POP_SCALE_START := 0.7
const POP_ROT_START_DEG := 3.5
const HIDE_SCALE := 0.75
const TAIL_W := 26.0
const TAIL_H := 14.0
const KOPF_OFFSET_M := 0.95
const RAND_GAP := 8.0

## EINE globale Queue für alle Blasen (max. 2 sichtbar, Rest wartet).
static var warteschlange := Warteschlange.new()

var stil := STIL_GOOBY
var dauer_s := DAUER_DEFAULT_S
var tail_an := true
var speaker_3d: Node3D = null
## Tests: false setzen und `advance_time(delta)` von Hand füttern
## (AGENTS.md-Regel „Zeit injizieren“ — kein OS-Takt im Testpfad).
var auto_zeit := true

var _voller_text := ""
var _typewriter := DialogTypewriter.new()
var _kapsel: PanelContainer
var _label: Label
var _tail: Control
var _zeit := 0.0
var _steh_zeit := 0.0
var _wartet := false
var _versteckt_sich := false
var _pop_fertig := false
var _pop_tween: Tween


## PURE Queue-Logik (headless testbar, tests/unit/test_w14_uikern.gd):
## max. `max_aktiv` Einträge gleichzeitig aktiv, weitere warten in
## Reihenfolge; `abmelden()` liefert den nachrückenden Kandidaten.
class Warteschlange:
	extends RefCounted

	var max_aktiv := MAX_AKTIV
	var aktiv: Array = []
	var wartend: Array = []

	## true = Eintrag darf sofort zeigen; false = eingereiht.
	func anmelden(eintrag: Variant) -> bool:
		_putzen()
		if aktiv.size() < max_aktiv:
			aktiv.append(eintrag)
			return true
		wartend.append(eintrag)
		return false

	## Eintrag austragen; gibt den NACHRÜCKER zurück (oder null).
	func abmelden(eintrag: Variant) -> Variant:
		_putzen()
		aktiv.erase(eintrag)
		wartend.erase(eintrag)
		if aktiv.size() >= max_aktiv or wartend.is_empty():
			return null
		var naechster: Variant = wartend.pop_front()
		aktiv.append(naechster)
		return naechster

	func _putzen() -> void:
		for liste: Array in [aktiv, wartend]:
			for i in range(liste.size() - 1, -1, -1):
				var eintrag: Variant = liste[i]
				if eintrag is Object and not is_instance_valid(eintrag):
					liste.remove_at(i)


## Fabrik + Queue-Eintritt. `layer` = CanvasLayer ODER Control; die Blase
## hängt sich als Kind hinein und verwaltet sich selbst (Auto-Hide).
static func show_bubble(layer: Node, text: String, opts: Dictionary = {}) -> AcBubble:
	var bubble := AcBubble.new()
	bubble.name = "AcBubble"
	bubble.stil = str(opts.get("stil", STIL_GOOBY))
	bubble.dauer_s = maxf(0.1, float(opts.get("dauer_s", DAUER_DEFAULT_S)))
	bubble.tail_an = bool(opts.get("tail", true))
	var speaker: Variant = opts.get("speaker_3d")
	if speaker is Node3D:
		bubble.speaker_3d = speaker
	bubble._voller_text = text
	bubble._wartet = not warteschlange.anmelden(bubble)
	layer.add_child(bubble)
	if not bubble._wartet:
		bubble._starten()
	return bubble


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bauen()
	visible = not _wartet


func _process(delta: float) -> void:
	if auto_zeit:
		advance_time(delta)


func _exit_tree() -> void:
	# Sicherheitsnetz: auch bei hartem queue_free von außen Queue + Anker
	# freigeben und den Nachrücker starten (regulär macht das _ausblenden;
	# abmelden ist idempotent — doppeltes Austragen fördert nie zu viel).
	if _kapsel != null:
		UiAnchors.release(UiAnchors.ZONE_BOTTOM, _kapsel)
	_nachruecker_starten()


## Zeit hereinreichen (vom _process ODER von Tests): Typewriter, Atmen,
## Position am Sprecher-Kopf und Auto-Hide laufen alle über DIESEN Takt.
func advance_time(delta: float) -> void:
	if _wartet or _versteckt_sich or not is_inside_tree():
		return
	_zeit += delta
	if _typewriter.laeuft():
		_typewriter.tick(delta)
		_zeige_zeichen()
	else:
		_steh_zeit += delta
	_atmen()
	_positionieren()
	if _steh_zeit >= dauer_s:
		_ausblenden()


## Kompat-API (wie DialogBubble): sichtbar und noch nicht am Ausblenden?
func is_active() -> bool:
	return visible and not _wartet and not _versteckt_sich


## Kompat-API: der VOLLE Text der Blase (auch während des Typewriters).
func current_line() -> String:
	return _voller_text


## Blase vorzeitig schließen (mit Shrink-Pop).
func dismiss() -> void:
	if not _versteckt_sich:
		_ausblenden()


## Text der LEBENDEN Blase ersetzen (Raum-Politik: Gooby hat EINE Blase,
## neue Sprüche ersetzen die alte mit frischem Pop statt sich aufzustauen —
## sonst sammelt der UI-Layer Nodes an, s. test_build_reliability).
## false = Blase blendet schon aus → Aufrufer erzeugt eine neue.
func ersetze_text(text: String) -> bool:
	if _versteckt_sich or not is_inside_tree() or text.is_empty():
		return false
	_voller_text = text
	_steh_zeit = 0.0
	if _label != null:
		_label.text = text
	if _wartet:
		return true
	_typewriter.start(text, _sofort_modus())
	_zeige_zeichen()
	_layout_messen()
	_positionieren()
	_pop_in()
	# Wie _starten: Container-Sortierung einmal nachziehen (Sicherheitsnetz,
	# falls Theme-Fonts die Wrap-Höhe minimal anders shapen).
	_nachmessen.call_deferred()
	return true


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _bauen() -> void:
	_kapsel = PanelContainer.new()
	_kapsel.name = "Kapsel"
	_kapsel.add_theme_stylebox_override("panel", _stylebox_fuer(stil))
	_kapsel.mouse_filter = Control.MOUSE_FILTER_STOP
	_kapsel.gui_input.connect(_on_kapsel_input)
	add_child(_kapsel)
	_label = Label.new()
	_label.name = "BubbleText"
	_label.text = _voller_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# G7-P51 (User-Screenshots „Ohh, wird das sch“): Godots Default
	# VC_CHARS_BEFORE_SHAPING shapt NUR die sichtbaren Typewriter-Zeichen —
	# _layout_messen lief direkt nach _typewriter.start (0 Zeichen) und sah
	# eine Mini-Blase: der MAX_WIDTH-Zweig griff nie (kein Wort-Umbruch,
	# lange Sprüche liefen als EINE Zeile aus dem Bild) und die Kapsel
	# ruckelte pro Buchstabe nach. VC_GLYPHS_LTR layoutet IMMER den vollen
	# Text (Endgröße steht vorab fest), nur das Zeichnen folgt dem Tippen.
	_label.visible_characters_behavior = TextServer.VC_GLYPHS_LTR
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", AcTokens.INK)
	if ThemeService.font(700) != null:
		_label.add_theme_font_override("font", ThemeService.font(700))
	_kapsel.add_child(_label)
	_tail = Control.new()
	_tail.name = "Tail"
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.draw.connect(_on_tail_draw)
	_tail.visible = tail_an
	_kapsel.add_child(_tail)


## Kapsel-Optik je Stil — Werte aus der Web-Referenz (.toast/--frost).
static func _stylebox_fuer(stil_name: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(RADIUS)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.set_border_width_all(2)
	sb.border_color = AcTokens.OUTLINE_SOFT
	sb.shadow_color = AcTokens.SHADOW_COLOR
	sb.shadow_size = AcTokens.SHADOW_SIZE
	sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_OFFSET_Y)
	match stil_name:
		STIL_SYSTEM:
			sb.bg_color = AcTokens.FROST
			sb.shadow_color = AcTokens.SHADOW_SOFT_COLOR
			sb.shadow_size = AcTokens.SHADOW_SOFT_SIZE
			sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_SOFT_OFFSET_Y)
		STIL_WITZ:
			sb.bg_color = AcTokens.PAPER.lerp(AcTokens.YELLOW, 0.14)
			sb.border_color = Color(AcTokens.YELLOW_DARK, 0.55)
		_:
			sb.bg_color = AcTokens.PAPER
	return sb


func _hintergrund_farbe() -> Color:
	var sb := _kapsel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		return sb.bg_color
	return AcTokens.PAPER


# ── Lebenszyklus ─────────────────────────────────────────────────────────────


func _starten() -> void:
	if _versteckt_sich or not is_instance_valid(self) or not is_inside_tree():
		return
	_wartet = false
	visible = true
	UiAnchors.reserve(UiAnchors.ZONE_BOTTOM, _kapsel)
	_typewriter.start(_voller_text, _sofort_modus())
	_zeige_zeichen()
	_layout_messen()
	_positionieren()
	_pop_in()
	# Autowrap-Höhe steht erst nach einem Frame fest — einmal nachziehen.
	_nachmessen.call_deferred()


func _nachmessen() -> void:
	if is_instance_valid(self) and _kapsel != null and not _versteckt_sich:
		_layout_messen()
		_positionieren()


func _ausblenden() -> void:
	if _versteckt_sich:
		return
	_versteckt_sich = true
	UiAnchors.release(UiAnchors.ZONE_BOTTOM, _kapsel)
	# Nachrücker SOFORT starten (nicht erst nach dem Shrink-Tween) — die
	# Queue hängt damit nie an Tween-Echtzeit (Tests injizieren Zeit).
	_nachruecker_starten()
	if _reduced_motion():
		_fertig()
		return
	_kill_pop()
	_pop_tween = create_tween().set_parallel()
	_pop_tween.tween_property(_kapsel, "scale", Vector2.ONE * HIDE_SCALE, AcTokens.DUR_POP * 0.8)
	_pop_tween.tween_property(_kapsel, "modulate:a", 0.0, AcTokens.DUR_POP * 0.8)
	_pop_tween.chain().tween_callback(_fertig)


func _fertig() -> void:
	ausgeblendet.emit()
	queue_free()


func _nachruecker_starten() -> void:
	var naechster: Variant = warteschlange.abmelden(self)
	if naechster is AcBubble and is_instance_valid(naechster):
		(naechster as AcBubble)._starten()


func _pop_in() -> void:
	if _reduced_motion():
		_pop_fertig = true
		return
	_kill_pop()
	_kapsel.scale = Vector2.ONE * POP_SCALE_START
	_kapsel.rotation_degrees = -POP_ROT_START_DEG
	_kapsel.modulate.a = 0.0
	_pop_tween = create_tween().set_parallel()
	_pop_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_kapsel, "scale", Vector2.ONE, AcTokens.DUR_POP)
	_pop_tween.tween_property(_kapsel, "rotation_degrees", 0.0, AcTokens.DUR_POP)
	_pop_tween.tween_property(_kapsel, "modulate:a", 1.0, AcTokens.DUR_POP / 2.0).set_trans(
		Tween.TRANS_LINEAR
	)
	_pop_tween.chain().tween_callback(func() -> void: _pop_fertig = true)


func _kill_pop() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()


## Leichtes Atmen (±1,5 % Sinus) — erst NACH dem Pop-In, nie bei
## Reduced Motion (dann bleibt die Blase statisch).
func _atmen() -> void:
	if not _pop_fertig or _versteckt_sich or _reduced_motion():
		return
	var puls := 1.0 + ATEM_AMPLITUDE * sin(TAU * _zeit / ATEM_PERIODE_S)
	_kapsel.scale = Vector2.ONE * puls


# ── Typewriter ───────────────────────────────────────────────────────────────


func _zeige_zeichen() -> void:
	if _label == null:
		return
	_label.visible_characters = -1 if _typewriter.ist_fertig() else _typewriter.sichtbar


## Sofort-Modus wie dialog_view: Reduced Motion ODER „Schnelle Dialoge“.
func _sofort_modus() -> bool:
	if _reduced_motion():
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("get_setting", "game.schnelle_dialoge", false))


func _on_kapsel_input(event: InputEvent) -> void:
	var tippbar := event is InputEventMouseButton or event is InputEventScreenTouch
	if not tippbar or not event.is_pressed():
		return
	if not _typewriter.ist_fertig():
		_typewriter.skip()
		_zeige_zeichen()
		return
	_ausblenden()


# ── Layout / Position ────────────────────────────────────────────────────────


func _layout_messen() -> void:
	var f := UiScale.for_viewport(get_viewport())
	var tf := UiScale.font_scale(get_viewport())
	_label.add_theme_font_size_override("font_size", int(maxf(AcTokens.FONT_SIZE_BODY * tf, 12.0)))
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2.ZERO
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	# G7-P51: Deckel gegen die SAFE-Fläche rechnen (nicht die volle Canvas),
	# sonst klemmt die Blase auf Notch-Geräten am Rand statt zu wickeln.
	var safe_w := canvas.x - float(insets["left"]) - float(insets["right"])
	var natural := _kapsel.get_combined_minimum_size()
	var max_w := minf(safe_w - 2.0 * RAND_GAP * f, MAX_WIDTH_PX * f)
	if natural.x > max_w:
		var chrome := natural.x - _label.get_combined_minimum_size().x
		var wrap_w := maxf(max_w - chrome, 60.0)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Wrap-Höhe SOFORT über die Schrift messen — das Label shapt erst im
		# nächsten Frame, die Kapsel reserviert die Endgröße aber VORAB
		# (kein Nachruckeln, Text-Rect immer in der Blase).
		_label.custom_minimum_size = Vector2(wrap_w, _wrap_hoehe(wrap_w))
		natural = _kapsel.get_combined_minimum_size()
	_kapsel.size = natural
	# Pivot unten Mitte: Pop/Atmen wachsen aus dem Sprech-Schwanz heraus.
	_kapsel.pivot_offset = Vector2(natural.x / 2.0, natural.y)
	_tail_layouten(natural.x / 2.0)


## Höhe des an WORT-Grenzen gewickelten Textes bei `wrap_w` Breite (Spiegel
## von AUTOWRAP_WORD_SMART: Wort-Umbruch, Adaptive nur für Überlänge-Wörter)
## inkl. Label-Zeilenabstand — liefert die ENDhöhe ohne Frame-Wartezeit.
func _wrap_hoehe(wrap_w: float) -> float:
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return 0.0
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var gemessen := font.get_multiline_string_size(
		_voller_text, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, font_size, -1, brk
	)
	var zeilen := maxi(1, roundi(gemessen.y / maxf(font.get_height(font_size), 1.0)))
	var abstand := _label.get_theme_constant("line_spacing")
	return gemessen.y + float((zeilen - 1) * abstand)


func _positionieren() -> void:
	if _kapsel == null or not is_inside_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	var groesse := _kapsel.size
	var ziel: Vector2
	var sprecher_punkt := Vector2(-1.0, -1.0)
	var kamera := get_viewport().get_camera_3d()
	if speaker_3d != null and is_instance_valid(speaker_3d) and kamera != null:
		var kopf := speaker_3d.global_position + Vector3(0.0, KOPF_OFFSET_M, 0.0)
		if not kamera.is_position_behind(kopf):
			sprecher_punkt = kamera.unproject_position(kopf)
	if sprecher_punkt.x >= 0.0:
		# Blase überm Kopf, Schwanz zeigt zum Sprecher.
		ziel = sprecher_punkt - Vector2(groesse.x / 2.0, groesse.y + TAIL_H + 6.0 * f)
	else:
		# Ohne Sprecher: unten mittig (Gooby-/System-Zeile).
		var unten := canvas.y - float(insets["bottom"]) - RAND_GAP * f
		ziel = Vector2((canvas.x - groesse.x) / 2.0, unten - groesse.y)
	var rect := Rect2(ziel, groesse)
	# Deconflict: über belegte Bottom-Rects rutschen, unter Top-Belegungen
	# (Notify-Banner) bleiben — nie überlappen (User-Feedback W14).
	rect = UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_BOTTOM, _kapsel), UiAnchors.ZONE_BOTTOM
	)
	rect = UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_TOP, _kapsel), UiAnchors.ZONE_TOP
	)
	# G7-P51: Rand-Luft skaliert mit f (wie die Breiten-Rechnung in
	# _layout_messen) — die Blase klemmt sonst auf Retina an der Notch.
	rect.position.x = clampf(
		rect.position.x,
		float(insets["left"]) + RAND_GAP * f,
		canvas.x - float(insets["right"]) - RAND_GAP * f - groesse.x
	)
	rect.position.y = clampf(
		rect.position.y,
		float(insets["top"]) + RAND_GAP * f,
		canvas.y - float(insets["bottom"]) - RAND_GAP * f - groesse.y
	)
	_kapsel.position = rect.position
	_tail_ausrichten(sprecher_punkt)


func _tail_layouten(mitte_x: float) -> void:
	if _tail == null:
		return
	_tail.position = Vector2(mitte_x - TAIL_W / 2.0, _kapsel.size.y - 1.0)
	_tail.size = Vector2(TAIL_W, TAIL_H)
	_tail.queue_redraw()


## Schwanz-Spitze Richtung Sprecher schieben (in Kapsel-Grenzen geklemmt).
func _tail_ausrichten(sprecher_punkt: Vector2) -> void:
	if _tail == null or not tail_an:
		return
	var mitte_x := _kapsel.size.x / 2.0
	if sprecher_punkt.x >= 0.0:
		var lokal_x := sprecher_punkt.x - _kapsel.position.x
		mitte_x = clampf(lokal_x, RADIUS + TAIL_W / 2.0, _kapsel.size.x - RADIUS - TAIL_W / 2.0)
	_tail_layouten(mitte_x)


func _on_tail_draw() -> void:
	# Weicher Sprech-Schwanz: abgerundetes Dreieck in Kapsel-Farbe.
	var farbe := _hintergrund_farbe()
	var punkte := PackedVector2Array(
		[
			Vector2(0.0, 0.0),
			Vector2(TAIL_W, 0.0),
			Vector2(TAIL_W * 0.62, TAIL_H * 0.86),
			Vector2(TAIL_W * 0.44, TAIL_H),
		]
	)
	_tail.draw_colored_polygon(punkte, farbe)


func _reduced_motion() -> bool:
	return ThemeService.is_reduced_motion(self)
