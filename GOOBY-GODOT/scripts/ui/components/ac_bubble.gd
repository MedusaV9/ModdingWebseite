class_name AcBubble
extends Control
## W14/UIKERN — DIE ACNH-Sprechblase (User-Feedback: „animierte runde süße
## Sprechblasen“). Weiche runde Paper-Kapsel (Web `.toast`: Radius 22,
## Outline-Ring + Shadow-Pop) mit:
##
##  - wackligem Pop-In (Scale-Bounce + Mini-Rotation, --ease-spring),
##  - leichtem Atmen (Sinus-Skalierung ±1,5 %),
##  - Typewriter über die BESTEHENDE DialogTypewriter-Logik (Gebrabbel-
##    Tempo; Reduced Motion / „Schnelle Dialoge“ = sofort). EVAL-2026-08
##    Befund 18: die Blase poppt mit KOMPLETTER erster Zeile und enthüllt
##    danach WORT-weise — kein Standbild zeigt je ein angerissenes Wort,
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
## belegte Bottom-Rects (zweite Blase, Bau-Dock, HUD-Bodenmöblierung via
## Hud.bubble_lane — hochkant das 10-Kachel-Dock) werden ÜBERsprungen
## (+8 px), die top-Zone (Notify-Banner) wird nie überdeckt.
##
## W18 E2/E7: Blasen sind REINE ANZEIGE — mouse_filter ist auf Kapsel UND
## allen Kindern durchgängig IGNORE. Eine STOP-Kapsel fraß Taps auf
## darunterliegende Primär-Knöpfe (Bett-Quest: „Platzieren" unklickbar).
## Klickbare Antwort-Chips leben NICHT in der Blase (gooby_gespraech.gd);
## wer je Chips IN eine Blase hängt, setzt NUR die Chips selbst auf STOP.

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
## GANZTEXT-VERTRAG (W20 P1c, Video-Review „ICH FINDE SIE NICHT U…“):
## Sprüche bis zu dieser Länge zeigt die Blase IMMER komplett — sie wickelt
## und wächst in die Höhe, nie Ellipsis/Clipping (der Label-Overrun bleibt
## OVERRUN_NO_TRIMMING). Längere Texte gehören in die DialogBubble-Ansicht.
const GANZTEXT_MAX_ZEICHEN := 220
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
var _hud_ref: Control
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
	_layout_messen()
	_erste_zeile_setzen()
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
	# W18 E2/E7: NIE STOP — die Kapsel liegt auf einem hohen Layer und
	# fraß sonst Taps auf Knöpfe darunter (Baumodus „Platzieren").
	_kapsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_layout_messen()
	_erste_zeile_setzen()
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
	if _typewriter.ist_fertig():
		_label.visible_characters = -1
		return
	# EVAL-2026-08 Lens B Befund 18 (Shot 17 „Kannst du kurz be“): WORT-weise
	# enthüllen — ein Standbild zeigt nie ein angerissenes Wort, sondern
	# endet immer an der letzten vollständig getippten Wortgrenze.
	_label.visible_characters = wort_grenze(_voller_text, _typewriter.sichtbar)


## PURE (Wache: test_hud_bubble_formate): größte Zeichenzahl ≤ n, die NICHT
## mitten in einem Wort endet — sonst zurück bis hinter den letzten Trenner.
static func wort_grenze(text: String, n: int) -> int:
	var m := clampi(n, 0, text.length())
	if m <= 0 or m >= text.length():
		return m
	if _wort_trenner(text[m]) or _wort_trenner(text[m - 1]):
		return m
	for i in range(m - 1, 0, -1):
		if _wort_trenner(text[i - 1]):
			return i
	return 0


static func _wort_trenner(zeichen: String) -> bool:
	return zeichen == " " or zeichen == "\n" or zeichen == "\t"


## Befund 18: die Blase poppt NIE mit angerissener Zeile — Zeile 1 steht
## komplett, BEVOR die Kapsel erscheint; der Typewriter tippt ab Zeile 2
## weiter (Einzeiler stehen damit sofort ganz da). Vorspulen über die
## öffentliche tick-API (Zeit injizieren, AGENTS.md-Regel).
func _erste_zeile_setzen() -> void:
	if not _typewriter.ist_fertig():
		var ziel := _erste_zeile_zeichen()
		if ziel > _typewriter.sichtbar:
			_typewriter.tick(float(ziel - _typewriter.sichtbar) / DialogTypewriter.ZEICHEN_PRO_SEK)
	_zeige_zeichen()


## Zeichenzahl der ERSTEN gewickelten Zeile — TextParagraph spiegelt den
## Label-Umbruch (WORD_SMART-Flags + Wrap-Breite aus _layout_messen);
## ohne Wickeln ist der ganze Text die erste Zeile.
func _erste_zeile_zeichen() -> int:
	if _label == null or _label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		return _voller_text.length()
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return _voller_text.length()
	var absatz := TextParagraph.new()
	absatz.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	absatz.width = maxf(_label.custom_minimum_size.x, 1.0)
	absatz.add_string(_voller_text, font, font_size)
	if absatz.get_line_count() <= 0:
		return _voller_text.length()
	return absatz.get_line_range(0).y


## Sofort-Modus wie dialog_view: Reduced Motion ODER „Schnelle Dialoge“.
func _sofort_modus() -> bool:
	if _reduced_motion():
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("get_setting", "game.schnelle_dialoge", false))


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
	# Befund 18: Breite zusätzlich gegen die HUD-Lane klemmen — quer endet
	# die Blase damit VOR der Cockpit-Spalte statt unter deren Kacheln.
	var lane_w := _lane_breite()
	if lane_w > 0.0:
		max_w = minf(max_w, lane_w)
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
## W20 P1 (Wortbruch-Wache): Breite-0-Messungen sind verboten (W19-Lehre:
## Autowrap misst bei Breite 0 Zeichen-für-Zeile) und die Zeilenzahl wird
## AUFgerundet — roundi konnte um eine Zeile untertreiben, die Kapsel
## reservierte dann zu wenig Höhe und der Text endete mitten im Wort.
func _wrap_hoehe(wrap_w: float) -> float:
	var font := _label.get_theme_font("font")
	var font_size := _label.get_theme_font_size("font_size")
	if font == null or font_size <= 0 or wrap_w <= 0.0:
		return 0.0
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var gemessen := font.get_multiline_string_size(
		_voller_text, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, font_size, -1, brk
	)
	var zeilen := maxi(1, ceili(gemessen.y / maxf(font.get_height(font_size), 1.0) - 0.05))
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
	# W20 P1c (Video-Review 0:27 „Blase klebt auf Drehen/Platzieren“): der
	# Sprech-Schwanz hängt TAIL_H unter der Kapsel — TIEFER als die 8-px-
	# dodge-Luft. Ausweichen/Klemmen rechnen deshalb mit dem GANZEN
	# Fußabdruck (Kapsel + Schwanz), sonst ragt die Schwanzspitze ~6 px in
	# Bau-Action-Bar/Dock-Knöpfe (Wache: test_w20_overlay_choreo).
	var schwanz := TAIL_H if tail_an else 0.0
	var rect := Rect2(ziel, groesse + Vector2(0.0, schwanz))
	# Deconflict: über belegte Bottom-Rects rutschen, unter Top-Belegungen
	# (Notify-Banner) bleiben — nie überlappen (User-Feedback W14).
	# W20 P1 (Befund-Top-9 „Blase auf der Bau-Aktionsleiste“): die
	# Sperrzone des offenen Bau-Docks (P2-Schnittstelle
	# BuildUiDock.aktive_zone, VOLL ausgebaut inkl. Action-Bar) zählt als
	# zusätzlicher Bottom-Blocker — die Blase springt beim
	# Werkzeug-Wechsel damit auch nicht.
	var blocker: Array = UiAnchors.occupied_rects(UiAnchors.ZONE_BOTTOM, _kapsel)
	var dock := BuildUiDock.aktive_zone()
	if dock.size.y > 0.0:
		blocker.append(dock)
	# W20 P1 Nachfix (FB3 kombi_overlap „Blase×Dock hochkant“): auch die
	# HUD-Bodenmöblierung ist Sperrzone — hochkant das 10-Kachel-Dock,
	# quer die Auge/Chip-Zeile. Hud.bubble_lane() liefert die Oberkante
	# (dieselbe Quelle, die die DialogBubble verankert).
	var hud := _finde_hud()
	if hud is Hud and (hud as Hud).is_visible_in_tree():
		var lane_top := float((hud as Hud).bubble_lane()["top"])
		if lane_top < canvas.y:
			blocker.append(Rect2(Vector2(0.0, lane_top), Vector2(canvas.x, canvas.y - lane_top)))
	rect = UiAnchors.dodge(rect, blocker, UiAnchors.ZONE_BOTTOM)
	rect = UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_TOP, _kapsel), UiAnchors.ZONE_TOP
	)
	# G7-P51: Rand-Luft skaliert mit f (wie die Breiten-Rechnung in
	# _layout_messen) — die Blase klemmt sonst auf Retina an der Notch.
	# Befund 18: rechts zusätzlich an der HUD-Lane enden (Cockpit-Spalte) —
	# die Lane ist ZENTRIERT, ihre rechte Kante liegt bei (canvas+w)/2.
	var rechts_max := canvas.x - float(insets["right"]) - RAND_GAP * f - groesse.x
	var lane_w := _lane_breite()
	if lane_w > 0.0:
		rechts_max = minf(rechts_max, (canvas.x + lane_w) / 2.0 - groesse.x)
	rect.position.x = clampf(rect.position.x, float(insets["left"]) + RAND_GAP * f, rechts_max)
	rect.position.y = clampf(
		rect.position.y,
		float(insets["top"]) + RAND_GAP * f,
		canvas.y - float(insets["bottom"]) - RAND_GAP * f - groesse.y
	)
	_kapsel.position = rect.position
	_tail_ausrichten(sprecher_punkt)


## Freie Blasen-Breite der HUD-Lane (0 = kein sichtbares HUD) — dieselbe
## Quelle, an der die DialogBubble ihre Breite klemmt (Hud.bubble_lane).
func _lane_breite() -> float:
	var hud := _finde_hud()
	if hud is Hud and (hud as Hud).is_visible_in_tree():
		return float((hud as Hud).bubble_lane()["width"])
	return 0.0


## HUD über die Gruppe finden (G4/P21-Muster wie DialogBubble._find_hud) —
## gecacht, weil _positionieren im advance_time-Takt läuft.
func _finde_hud() -> Control:
	if _hud_ref != null and is_instance_valid(_hud_ref):
		return _hud_ref
	_hud_ref = null
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"hud"):
		if node is Hud:
			_hud_ref = node
			break
	return _hud_ref


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
