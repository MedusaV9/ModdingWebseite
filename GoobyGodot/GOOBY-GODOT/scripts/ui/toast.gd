class_name ToastLayer
extends Control
## Sichtbarer Toast-Layer: genau EIN Toast gleichzeitig (Queue in
## `ToastQueue`, pure Logik). In eine Screen-Szene legen (Full-Rect,
## oberste UI-Ebene) und `show_toast("…")` rufen.
##
## W21/ACNH P1 — Blatt-Sprache (UI-DESIGN-ACNH §8 P1):
## - ToastBubble-Rolle rundet mit RADIUS_CARD (22er-Web-Ausnahme gestrichen),
##   Blatt-Glyphe in ICON_S, Text SIZE_CAPTION, Lücke SPACE_S.
## - EINE Toast-Höhe: einzeilige Toasts sind exakt px(TOAST_H, f) hoch;
##   gewickelte wachsen nur um die gemessenen Zeilen.
## - Bewegung über MotionKit.blatt_slide_in/out (Reduced-Motion-gated).
##
## W21/ACNH P1 — WURZEL-FIX „~894-px-Toast“ (Playtest-Befund P0): Der alte
## Pfad maß das Panel ERST einen Frame nach dem Sichtbarmachen — beim
## Queue-Advance einer Salve stand der neue (lange) Text dadurch 1–2 Frames
## UNGEWICKELT (905 px) auf der Position des Vorgänger-Toasts, ehe der
## Breiten-Deckel griff (unter llvmpipe/Live lang genug für den Screenshot-
## Befund „Toast liegt quer AUF der Cockpit-Spalte“). Jetzt wird SYNCHRON
## über Font-Metriken gemessen (get_string_size/get_multiline_string_size),
## Wickel-Entscheid + Panel-Maß stehen VOR dem ersten sichtbaren Frame —
## es gibt keinen Zwischenzustand mehr, den ein langsamer Frame einfrieren
## könnte. Wächter: test_w21_toast_montage + test_w21_toast_konform.
##
## W21/ACNH P1 — GLOBALE TOAST-LANE (Erstlauf-Serialisierung): Die Services
## (RewardHub, DailyQuestService, Screens) besitzen EIGENE ToastLayer auf
## eigenen CanvasLayers — vorher zeigten zwei Layer parallel zwei Toasts
## übereinander (Salven-Probe: Quest- + Reward-Toast gleichzeitig). Alle
## Instanzen teilen sich jetzt EINE statische Lane: es zeigt immer nur der
## Lane-Inhaber, die anderen warten mit gefüllter Queue, bis er fertig ist
## (FIFO über die Warteliste). Wächter: test_w21_erstlauf_serie.
##
## W14/W20/W21-Ausweich-Verträge unverändert: Toasts reservieren die
## TOP-Zone (UiAnchors), starten unter der freien HUD-Kopf-Zone
## (`Hud.hint_lane()`), untertauchen TabBars + Gruppe `toast_hindernis`,
## enden am Tiefen-Deckel, meiden Bottom-Belegungen (Gooby-Blase) und die
## Bau-Dock-Sperrzone; ein sichtbarer Toast positioniert sich neu, wenn
## sich die Zonen-Belegung während seiner Standzeit ändert (Nach-Dodge).
## W21 P1 Zwickmühlen-Regel (fb3 23_kombi_toast): schiebt eine hohe
## Bottom-Belegung den Toast zurück auf einen OBEN-Zwang („Was nun?“-×),
## rutscht er stattdessen UNTER die Belegung (s. _ziel_position).

const HOLD_SEC := 2.2
## Blatt-Glyphe/Text/Lücke nach ACNH-Skala (Design-px, skaliert mit f).
const FONT_PX := float(AcTokens.SIZE_CAPTION)
const LEAF_PX := float(AcTokens.ICON_S)
const GAP_PX := float(AcTokens.SPACE_S)
## EINE Toast-Höhe (Design-px, ×f): einzeilige Toasts sind exakt so hoch.
const TOAST_H := float(AcTokens.BTN_H_KOMPAKT)
## Breiten-Deckel wie Web (min(86 % Canvas, 22 rem = 352 px), Design-px).
const MAX_WIDTH_PX := 352.0
## Vertikale Ankerhöhe (Anteil der Canvas-Höhe, unter den Status-Pills).
const TOP_SHARE := 0.12
## G4/P21 (QW #17): Gruppen-Name für den zentralen `zeige()`-Helfer —
## ersetzt die 8 kopierten Vollbaum-Scans (`find_children` über root).
const GROUP := &"toast_layer"
## W20 P1: Opt-in-Gruppe für Controls, denen Toasts ausweichen müssen
## (Titel/Kopfzeilen fremder Screens — Vertrag im Datei-Kopf).
const HINDERNIS_GROUP := &"toast_hindernis"
## W20 P1: unterhalb dieses Canvas-Anteils beginnt kein Toast mehr —
## Deckel gegen Dodge-Stürme (nie in Bildmitte/Boden-Lane gedrückt).
const MAX_TIEFE_ANTEIL := 0.6

## Globale Toast-Lane: Inhaber zeigt, alle anderen Layer warten (FIFO).
static var _lane_inhaber: ToastLayer = null
static var _lane_warteliste: Array[ToastLayer] = []

var queue := ToastQueue.new()
## Standzeit injizierbar (AGENTS.md „Zeit injizieren“): Tests verkürzen
## sie, statt Echtzeit-Salven über HOLD_SEC × n auszusitzen.
var hold_sec := HOLD_SEC

var _panel: PanelContainer
var _label: Label
var _leaf: TextureRect
var _hold_timer: Timer
var _in_tween: Tween
## W21: zuletzt berechnete Ruhelage (Animations-Ziel) — der Nach-Dodge
## vergleicht dagegen statt gegen die tweenende Live-Position.
var _ruhelage := Vector2.ZERO
var _nachdodge_geplant := false
## Wächter gegen Selbst-Trigger: das eigene reserve() in der Positions-
## Rechnung meldet einen Zonen-Wechsel — der darf keinen Nach-Dodge starten.
var _positionierung_laeuft := false


## Zentraler Toast-Weg für Nicht-Screen-Code (Sheets, Services): findet den
## nächsten ToastLayer über die Gruppe statt per O(Baum)-`find_children`.
## Ohne Baum/Layer still no-op (headless/Tests: wie die alten Kopien).
static func zeige(von: Node, text: String, error := false) -> void:
	if von == null or not von.is_inside_tree():
		return
	for layer: Node in von.get_tree().get_nodes_in_group(GROUP):
		if layer is ToastLayer and not layer.is_queued_for_deletion():
			(layer as ToastLayer).show_toast(text, error)
			return


func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "ToastPanel"
	_panel.theme_type_variation = "ToastBubble"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.z_index = 100
	add_child(_panel)
	var box := HBoxContainer.new()
	box.name = "ToastBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_leaf = TextureRect.new()
	_leaf.name = "ToastLeaf"
	_leaf.texture = load("res://assets/ui/icons/leaf.svg")
	_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leaf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leaf.self_modulate = AcTokens.LEAF
	_leaf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_leaf)
	_label = Label.new()
	_label.name = "ToastText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Wrap-Entscheid + Maße kommen SYNCHRON aus der Font-Metrik
	# (_masse_setzen) — Autowrap wird nur fürs Rendern des gewickelten
	# Texts eingeschaltet, nie fürs Messen: MIT Autowrap meldet Label seine
	# Minimum-Höhe für die AKTUELLE Breite, und die Container-Sorts laufen
	# deferred auf alten Breiten — der Shape wickelte den neuen Text dann
	# auf Phantom-Zeilen und blähte das Panel (Salven-Probe: 361 statt
	# 104 px hoch). clip_text kollabiert dieses Binnen-Minimum; die WAHRE
	# Höhe (inkl. line_spacing) trägt custom_minimum_size aus der Messung.
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_done)
	add_child(_hold_timer)
	UiAnchors.beobachte(_on_belegung_wechsel)


func _exit_tree() -> void:
	UiAnchors.beobachter_abmelden(_on_belegung_wechsel)
	if _panel != null:
		UiAnchors.release(UiAnchors.ZONE_TOP, _panel)
	_lane_freigeben()


## Toast anfordern; wird ggf. eingereiht (nie gestapelt — auch nicht über
## LAYER-Grenzen hinweg, s. globale Toast-Lane im Datei-Kopf). `error =
## true` spielt den Fehler-Blip (W4P1-SFX: Erfolgs-Toasts bleiben stumm).
func show_toast(text: String, error := false) -> void:
	var accepted := queue.push(text)
	if accepted and error:
		AudioDirector.try_play(self, "ui_error")
	if accepted:
		_lane_anfordern()


func is_showing() -> bool:
	return _panel != null and _panel.visible


## ── Globale Toast-Lane ──────────────────────────────────────────────────────


## Diese Instanz will zeigen: sofort, wenn die Lane frei ist — sonst hinten
## in die Warteliste (FIFO; jede Instanz höchstens einmal).
func _lane_anfordern() -> void:
	_lane_aufraeumen()
	if _lane_inhaber == self:
		return
	if _lane_inhaber == null:
		_lane_inhaber = self
		if queue.current().is_empty():
			_show_next()
		return
	if not _lane_warteliste.has(self):
		_lane_warteliste.append(self)


## Lane abgeben (Queue leer oder Layer verlässt den Baum) und dem nächsten
## wartenden Layer mit gefüllter Queue übergeben.
func _lane_freigeben() -> void:
	_lane_warteliste.erase(self)
	if _lane_inhaber != self:
		return
	_lane_inhaber = null
	_lane_aufraeumen()
	while not _lane_warteliste.is_empty():
		var naechster: ToastLayer = _lane_warteliste.pop_front()
		if naechster.queue.is_idle():
			continue
		_lane_inhaber = naechster
		naechster._show_next()
		return


## Tote/entfernte Instanzen aus Lane + Warteliste austragen.
static func _lane_aufraeumen() -> void:
	if (
		_lane_inhaber != null
		and (not is_instance_valid(_lane_inhaber) or not _lane_inhaber.is_inside_tree())
	):
		_lane_inhaber = null
	for i in range(_lane_warteliste.size() - 1, -1, -1):
		var layer: ToastLayer = _lane_warteliste[i]
		if not is_instance_valid(layer) or not layer.is_inside_tree():
			_lane_warteliste.remove_at(i)


## ── Anzeige ─────────────────────────────────────────────────────────────────


func _show_next() -> void:
	var text := queue.advance()
	if text.is_empty():
		_panel.visible = false
		UiAnchors.release(UiAnchors.ZONE_TOP, _panel)
		_lane_freigeben()
		return
	_apply_scale()
	var f := UiScale.for_viewport(get_viewport())
	var area := _canvas_area()
	_masse_setzen(text, f, area)
	_panel.visible = true
	_panel.size = _panel.get_combined_minimum_size()
	_positionierung_laeuft = true
	var rest := _ziel_position(_panel.size, f, area)
	UiAnchors.reserve(UiAnchors.ZONE_TOP, _panel)
	_positionierung_laeuft = false
	_ruhelage = rest
	_panel.position = rest
	_einblenden(f)
	_hold_timer.start(hold_sec)


## ACNH-Maße auf den Canvas skalieren (zentrale UiScale-Regel, FIX1).
func _apply_scale() -> void:
	var f := UiScale.for_viewport(get_viewport())
	_label.add_theme_font_size_override("font_size", AcTokens.font_px(FONT_PX, f))
	if ThemeService.font(700) != null:
		_label.add_theme_font_override("font", ThemeService.font(700))
	_leaf.custom_minimum_size = Vector2.ONE * float(AcTokens.px(LEAF_PX, f))
	var box := _panel.get_node("ToastBox") as HBoxContainer
	box.add_theme_constant_override("separation", AcTokens.px(GAP_PX, f))


## WURZEL-FIX: Text SYNCHRON über die Font-Metrik messen und Label-/Panel-
## Maße SOFORT setzen — Wickel-Entscheid am Breiten-Deckel (min(86 %
## Canvas, 352·f)), gewickelte Höhe über get_multiline_string_size (gleiche
## BREAK_WORD_BOUND-Semantik wie AUTOWRAP_WORD). EINE Toast-Höhe: das Panel
## ist mindestens px(TOAST_H, f) hoch, einzeilig exakt.
func _masse_setzen(text: String, f: float, area: Vector2) -> void:
	_label.text = text
	var max_w := minf(area.x * 0.86, MAX_WIDTH_PX * f)
	var font := _label.get_theme_font("font")
	var font_px := _label.get_theme_font_size("font_size")
	var chrome := _chrome_breite()
	var text_w := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x)
	if chrome + text_w <= max_w:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size = Vector2(text_w, ceilf(font.get_height(font_px)))
	else:
		var wrap_w := maxf(max_w - chrome, 40.0)
		var mehrzeilig := font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, font_px
		)
		# Label rendert mit line_spacing ZWISCHEN den Zeilen — die Messung
		# liefert nur die Summe der Zeilenhöhen (sonst clippt die letzte).
		var zeilen := maxf(roundf(mehrzeilig.y / font.get_height(font_px)), 1.0)
		var luft := float(_label.get_theme_constant("line_spacing")) * (zeilen - 1.0)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_label.custom_minimum_size = Vector2(wrap_w, ceilf(mehrzeilig.y + luft))
	_panel.custom_minimum_size = Vector2(0.0, float(AcTokens.px(TOAST_H, f)))


## Panel-Chrom neben dem Text: StyleBox-Innenränder + Blatt + Lücke.
func _chrome_breite() -> float:
	var breite := _leaf.custom_minimum_size.x
	var box := _panel.get_node("ToastBox") as HBoxContainer
	breite += float(box.get_theme_constant("separation"))
	var style := _panel.get_theme_stylebox("panel")
	if style != null:
		breite += style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	return breite


func _canvas_area() -> Vector2:
	# Layer kann im ersten Frame noch 0-groß sein (frisch gemountet).
	var area := size
	if area.x <= 1.0:
		area = Vector2(get_viewport().get_visible_rect().size)
	return area


## Ruhelage des Toasts aus Lane, Hindernissen und Zonen-Belegungen — als
## EIGENE Rechnung, damit der W21-Nach-Dodge (Belegungs-Beobachter) sie
## für den bereits sichtbaren Toast wiederverwenden kann.
func _ziel_position(natural: Vector2, f: float, area: Vector2) -> Vector2:
	# FB3: nie hinter die Notch — Ankerhöhe mindestens Safe-Top + Luft.
	var insets := UiScale.safe_insets_canvas(get_viewport())
	var top := maxf(area.y * TOP_SHARE, float(insets["top"]) + 8.0 * f)
	var rest := Vector2((area.x - natural.x) / 2.0, top)
	# W20 P1: Lane-Start unter der freien HUD-Kopf-Zone (Statuszeile/
	# Zahnrad/Status-Spalte) — hochkant lag der Toast sonst mitten AUF
	# den Status-Pillen (Befund-Top-5).
	var hud := _finde_hud()
	if hud is Hud and (hud as Hud).is_visible_in_tree():
		var lane: Dictionary = (hud as Hud).hint_lane()
		rest.y = maxf(rest.y, float(lane["top"]))
		rest.x = clampf(
			rest.x, float(lane["left"]), maxf(float(lane["right"]) - natural.x, float(lane["left"]))
		)
	var rect := _dodge_oben(Rect2(rest, natural), f)
	# W20 P1: Tiefen-Deckel — die Lane endet bei MAX_TIEFE_ANTEIL; ein
	# Dodge-Sturm kann den Toast nie in Bildmitte/Boden-Lane drücken.
	# W21: Deckel VOR dem Bottom-Ausweichen — er drückte den fertig
	# gedodgten Toast sonst wieder zurück IN die Dock-Zone.
	var deckel := maxf(area.y * MAX_TIEFE_ANTEIL, top)
	rect.position.y = minf(rect.position.y, deckel)
	# W21: die Bau-Dock-Sperrzone zählt als eigener Bottom-Blocker (wie
	# ac_bubble.gd) — das Live-Rect des Docks wächst erst nach Layout-
	# Pass/Werkzeug-Wechsel, die Zone ist ab dem ersten Frame voll.
	var blocker: Array = UiAnchors.occupied_rects(UiAnchors.ZONE_BOTTOM, _panel)
	var dock := BuildUiDock.aktive_zone()
	if dock.size.y > 0.0:
		blocker.append(dock)
	# FLUG-KORRIDOR (W1c-Vertrag „Toast schneidet Blase NIE“ — auch nicht
	# im Einflug-Frame): der Blatt-Einflug startet BLATT_OFFSET·f UNTER
	# der Ruhelage, der Abgang gleitet ebenso weit hinunter. Gegen die
	# Bottom-Belegungen wird deshalb das um den Korridor verlängerte Rect
	# gedodgt — vorher tauchte der Slide in eine knapp darunter stehende
	# Blase ein (Repro: run_w1c_tests, Toast-Unterkante 480,0 auf Blasen-
	# Oberkante 480,125 → Einflug-Frame 6 px IN der Blase).
	var flug := Rect2(rect.position, natural + Vector2(0.0, MotionKit.BLATT_OFFSET * f))
	var hoch := UiAnchors.dodge(flug, blocker, UiAnchors.ZONE_BOTTOM, 14.0 * f)
	# W21 P1 ZWICKMÜHLEN-FIX (fb3 23_kombi_toast, Probe tests/tools): steht
	# die Gooby-Blase ungewöhnlich HOCH im Bild (Bottom-Belegung über der
	# Lane), schob das Hochschieben den fertig gedodgten Toast zurück AUF
	# die „Was nun?“-Karte (deren ×). In der Zwickmühle Karte-oben/Blase-
	# unten rutscht der Toast stattdessen UNTER die Blase (Tiefen-Deckel
	# hält). Bleibt auch das versperrt (Dock-Zone bis zum Boden), gewinnt
	# das Hochschieben: Bottom-Zonen sind HARTE Sperren (W21-Bau-Dock-
	# Vertrag in test_w20_overlay_choreo), Oben-Überlappung ist dann das
	# kleinere Übel des unmöglichen Layouts.
	if hoch.position.y < flug.position.y and _schneidet_oben(hoch, f):
		var unter := _dodge_oben(UiAnchors.dodge(flug, blocker, UiAnchors.ZONE_TOP, 14.0 * f), f)
		rect = (
			unter if unter.position.y <= deckel and not _schneidet_rects(unter, blocker) else hoch
		)
	else:
		rect = hoch
	rest.y = maxf(rect.position.y, float(insets["top"]) + 8.0 * f)
	return rest


## Alle OBEN-Zwänge in einem Pass: unter die „Was nun?“-Karte, unter
## fremde Top-Belegungen (W14-Zonen-Regel: Notify-Banner), unter
## interaktive Hindernisse (W20 P1: TabBars + Gruppe toast_hindernis).
func _dodge_oben(rect: Rect2, f: float) -> Rect2:
	rect.position.y = _dodge_hint_card(rect, f)
	rect = UiAnchors.dodge(
		rect, UiAnchors.occupied_rects(UiAnchors.ZONE_TOP, _panel), UiAnchors.ZONE_TOP
	)
	return UiAnchors.dodge(rect, _interaktive_hindernisse(rect), UiAnchors.ZONE_TOP)


## true, wenn das Rect einen der OBEN-Zwänge schneidet — der Dodge bewegt
## nur bei echtem Schnitt, also verrät die Positions-Differenz den Konflikt.
func _schneidet_oben(rect: Rect2, f: float) -> bool:
	return _dodge_oben(rect, f).position.y > rect.position.y + 0.5


func _schneidet_rects(rect: Rect2, blocker: Array) -> bool:
	for hindernis: Variant in blocker:
		if hindernis is Rect2 and rect.intersects(hindernis):
			return true
	return false


## W21: Zonen-Belegung hat sich NACH dem Einblenden geändert (z. B. Bau-
## Dock reserviert die Bottom-Zone mitten in der Toast-Standzeit) — den
## sichtbaren Toast neu ausweichen lassen. Deferred: Layout des Neuan-
## kömmlings steht dann, und Wechsel-Stürme koaleszieren zu EINEM Lauf.
func _on_belegung_wechsel(_zone: String) -> void:
	if _positionierung_laeuft or _nachdodge_geplant or not is_showing():
		return
	_nachdodge_geplant = true
	_nachdodge.call_deferred()


func _nachdodge() -> void:
	_nachdodge_geplant = false
	if not is_showing() or not is_inside_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	var area := _canvas_area()
	_positionierung_laeuft = true
	var rest := _ziel_position(_panel.size, f, area)
	_positionierung_laeuft = false
	if rest.distance_to(_ruhelage) < 1.0:
		return
	_ruhelage = rest
	if _in_tween != null and _in_tween.is_valid():
		_in_tween.kill()
	_panel.scale = Vector2.ONE
	_panel.modulate.a = 1.0
	if ThemeService.is_reduced_motion(self):
		_panel.position = rest
		return
	_in_tween = create_tween()
	_in_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_in_tween.tween_property(_panel, "position", rest, AcTokens.DUR_POP)


## W20 P1: HUD über die Gruppe finden (G4/P21-Muster, kein Vollbaum-Scan).
func _finde_hud() -> Control:
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"hud"):
		if node is Hud:
			return node
	return null


## W20 P1: Global-Rects der sichtbaren interaktiven Hindernisse, die den
## Toast-Kandidaten schneiden: alle `TabBar`s (Gestalten-Raum-Tabs) plus
## die Opt-in-Gruppe `toast_hindernis`. Der TabBar-Scan läuft über den
## Vollbaum — bewusst: Toasts sind seltene Einzel-Ereignisse (kein
## Frame-Pfad), und TabBars tragen keine Gruppe.
func _interaktive_hindernisse(kandidat: Rect2) -> Array:
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	var kandidaten: Array[Node] = []
	kandidaten.append_array(tree.root.find_children("*", "TabBar", true, false))
	kandidaten.append_array(tree.get_nodes_in_group(HINDERNIS_GROUP))
	for node: Node in kandidaten:
		if not (node is Control):
			continue
		var control := node as Control
		if not control.is_inside_tree() or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if kandidat.intersects(rect):
			out.append(rect)
	return out


## UIFINAL Runde 2: Toast und „Was nun?“-Karte teilen sich die Kopf-Zone —
## bei Quest-Erfolg lag die Paper-Bubble mitten AUF der Karte. Steht die
## Karte im Weg, rutscht der Toast unter ihre Unterkante.
func _dodge_hint_card(toast_rect: Rect2, f: float) -> float:
	var tree := get_tree()
	if tree == null:
		return toast_rect.position.y
	for node: Node in tree.get_nodes_in_group(&"wasnun_karte"):
		if node is Control and (node as Control).is_visible_in_tree():
			var card := (node as Control).get_global_rect()
			if toast_rect.intersects(card):
				return card.end.y + 8.0 * f
	return toast_rect.position.y


## W21/ACNH: Blatt-Einflug über die verbindliche Motion-Grammatik
## (MotionKit gated Reduced Motion selbst — dann steht der Toast sofort).
func _einblenden(f: float) -> void:
	if _in_tween != null and _in_tween.is_valid():
		_in_tween.kill()
	_panel.scale = Vector2.ONE
	_panel.modulate.a = 1.0
	_in_tween = MotionKit.blatt_slide_in(_panel, MotionKit.BLATT_OFFSET * f)


## Standzeit vorbei: Blatt-Abgang, dann der nächste aus der Queue. Der
## MotionKit-Abgang verschiebt die Position — _show_next setzt sie für den
## Nachfolger ohnehin frisch, nur die Deckkraft muss zurück.
func _on_hold_done() -> void:
	var f := UiScale.for_viewport(get_viewport())
	var tween := MotionKit.blatt_slide_out(_panel, MotionKit.BLATT_OFFSET * f)
	if tween != null:
		await tween.finished
		if not is_instance_valid(self) or not is_inside_tree():
			return
	_panel.modulate.a = 1.0
	_show_next()
