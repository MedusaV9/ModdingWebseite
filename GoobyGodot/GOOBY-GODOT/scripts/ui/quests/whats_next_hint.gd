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
##
## E1/W18 (Playtest „Karte stiehlt Tür-Taps“): Eingaben schluckt NUR die
## fertig gesettelte Kartenfläche (STOP auf _card + ×; alle Container
## PASS/IGNORE). Solange die Autowrap-Minima stale sind, ist die Karte
## entschärft (modulate 0 + IGNORE) — reset_size fror sonst eine bis zu
## 11 000 px hohe STOP-Fläche ein, die Taps auf 3D-Objekte dahinter fraß.
##
## W21/ACNH P1 (fb3-Befund 23_kombi_toast „Toast × WasNunSchliessen“): die
## SCHARFE Karte reserviert die TOP-Zone (UiAnchors) — ein bereits
## stehender Toast bekommt den Belegungs-Wechsel gemeldet und dodgt sich
## unter die Karte (toast.gd-Nach-Dodge), statt auf dem × zu liegen. Die
## alte Lücke: der Toast wich der Karte nur beim EIGENEN Platzieren aus
## (Gruppe wasnun_karte), nicht wenn die Karte NACH ihm scharf wurde.

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
## Zonen-Ausweich: tiefer als dieser Canvas-Anteil rutscht die Karte nie —
## darunter duckt sie sich weg, statt in die Bildmitte zu wandern.
const ZONEN_TIEFE_ANTEIL := 0.55

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
## Laufender Settle-Token: nur die JÜNGSTE _nachsetteln-Coroutine wendet
## ihr Ergebnis an (Vorschlags-/Resize-Stürme stapeln sich sonst).
var _settle_lauf := 0
## true, wenn der letzte Layout-Pass eine tap-zonenfreie Lage fand — sonst
## bleibt die Karte entschärft: sie duckt sich weg, statt je eine sichtbare
## TapArea zu verdecken (W20-P1-Nachfix, flow_home_basis-Lehre).
var _zonen_frei := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_hint)
	add_child(_timer)
	_build_card()
	get_viewport().size_changed.connect(_on_viewport_geaendert)


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
		UiAnchors.release(UiAnchors.ZONE_TOP, _card)
		_timer.stop()
	else:
		_timer.start(AUTO_HIDE_S)
		# E1/W18: geduckt (unsichtbar) settelt der Container NIE — beim
		# Ent-Ducken die Geometrie frisch setteln, sonst käme eine ggf.
		# stale (kilometerhohe) STOP-Fläche zurück ins Bild.
		_nachsetteln()


func show_suggestion(suggestion: Dictionary) -> void:
	var was_same := str(suggestion.get("id", "")) == str(_suggestion.get("id", ""))
	_suggestion = suggestion.duplicate(true)
	_title.text = I18nService.t("quests.wasnun.titel")
	var neuer_text := _resolve_text(suggestion)
	var text_geaendert := neuer_text != _text.text
	_text.text = neuer_text
	# E1/W18: KEIN sofortiges _relayout mehr — Autowrap-Minima sind im
	# Aufruf-Frame stale (das Label misst erst nach dem Layout-Pass), und
	# reset_size fror damit eine kilometerhohe Karte ein (gemessen: bis
	# 11 000 px), deren STOP-Fläche Taps auf 3D-Objekte (Küchentür!) weit
	# außerhalb der sichtbaren Karte schluckte. Layout + Scharfschalten
	# passieren jetzt IMMER erst im gesettelten Pass (_nachsetteln).
	if visible and was_same:
		if text_geaendert:
			_nachsetteln()
		return
	visible = true
	_suppressed = _should_suppress()
	_card.visible = not _suppressed
	_nachsetteln()
	_timer.start(AUTO_HIDE_S)


func hide_hint() -> void:
	visible = false
	_timer.stop()
	UiAnchors.release(UiAnchors.ZONE_TOP, _card)


func _exit_tree() -> void:
	if _card != null:
		UiAnchors.release(UiAnchors.ZONE_TOP, _card)


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
## W20 P1 (Befunde C2/C3 „Karte überlebt Baumodus/Telefon“): auch ein nur
## GEDUCKTES HUD (HudSichtbarkeit.verdeckt — Baumodus, Telefon, fremde
## Modals) zählt: die Karte gehört zum HUD-Chrome und weicht mit.
func _should_suppress() -> bool:
	if PanelStack.count() > 0:
		return true
	var hud := _find_hud()
	if hud == null:
		return false
	if not hud.is_visible_in_tree():
		return true
	if hud is Hud:
		var dynamik := (hud as Hud).sichtbarkeit()
		if dynamik != null and dynamik.verdeckt():
			return true
	return false


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


## Autowrap-Minima stehen erst NACH dem Layout-Pass — bis dahin ist die
## Karte ENTSCHÄRFT (durchsichtig + Eingaben laufen durch). Zwei Pässe:
## Pass 1 setzt die Ziel-BREITE (_relayout), erst der Folgeframe misst die
## Autowrap-HÖHE mit dieser Breite neu, Pass 2 wendet die echte Geometrie
## an und schaltet die Karte scharf. Grund (Playtest E1/W18): die stale
## gemessene STOP-Fläche (bis 11 000 px hoch) stahl sonst Taps auf alles,
## was hinter der Karte liegt. Die Karte muss dabei SICHTBAR bleiben
## (visible=true, nur modulate 0), sonst settelt der Container nie.
func _nachsetteln() -> void:
	_entschaerfen()
	_settle_lauf += 1
	var lauf := _settle_lauf
	var tree := get_tree()
	if tree == null:
		return
	_relayout()
	await tree.process_frame
	if lauf != _settle_lauf or not is_instance_valid(self):
		return
	if _card == null or not is_instance_valid(_card):
		return
	_relayout()
	await tree.process_frame
	if lauf != _settle_lauf or not is_instance_valid(self):
		return
	if _card == null or not is_instance_valid(_card):
		return
	_relayout()
	# W20 P1 Nachfix: OHNE zonenfreie Lage bleibt die Karte entschärft
	# (modulate 0 + IGNORE) — sie verdeckt NIE eine sichtbare TapArea.
	if _zonen_frei:
		_scharf_schalten()


## Eingabe + Deckkraft der Karte aus, solange ihre Geometrie stale ist.
## Entschärft belegt sie auch KEINE Zone — ein Toast muss ihr erst wieder
## ausweichen, wenn sie scharf (sichtbar + tippbar) ist.
func _entschaerfen() -> void:
	_card.modulate.a = 0.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAnchors.release(UiAnchors.ZONE_TOP, _card)


## Gesettelte Karte einblenden und wieder Eingaben annehmen lassen —
## NUR die Kartenfläche selbst (STOP) und ihr ×; alles andere bleibt
## PASS/IGNORE (mouse_filter-Disziplin, Wächter in test_w18_home_fixes).
## W21 P1: die scharfe Karte reserviert die TOP-Zone — ein stehender Toast
## zieht per Nach-Dodge unter ihre Unterkante (fb3 23_kombi_toast).
func _scharf_schalten() -> void:
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.modulate.a = 1.0
	if visible and not _suppressed:
		UiAnchors.reserve(UiAnchors.ZONE_TOP, _card)
		UiMotion.pop_in(_card)


func _on_viewport_geaendert() -> void:
	# Auch nach einem Resize sind die Autowrap-Minima erst im Folgeframe
	# frisch — gleiche Entschärfen-then-Settle-Route wie beim Einblenden.
	if visible:
		_nachsetteln()


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
	var pos := Vector2(maxf(x, lane_left), float(lane["top"]))
	_card.position = _weiche_tap_zonen_aus(pos, size_now, lane_left, lane_right)


## W20 P1 (Funktions-Befund F „Kühlschrank-Tap öffnet kein Fütter-Grid“):
## Die Karte lag in der Küche GENAU über der 3D-Tap-Zone des Kühlschranks —
## ihre STOP-Fläche schluckte den Möbel-Tap und öffnete stattdessen das
## Quest-Blatt (das dann als Modal alle Folge-Taps fraß → 46-s-Timeout).
## Die Karte weicht deshalb den PROJIZIERTEN Tap-Zonen (Area3D „TapArea“
## der Interactables) aus: erst mittig, sonst links-/rechtsbündig in der
## Lane, dann unter der tiefsten schneidenden Zone (mit Tiefen-Deckel und
## ERNEUTER Prüfung). Bleibt keine zonenfreie Lage, meldet _zonen_frei
## false — die Karte duckt sich weg (Nachfix: flow_home_basis, die Karte
## fing den Küchentür-Tap und öffnete stattdessen das Quest-Blatt).
func _weiche_tap_zonen_aus(
	pos: Vector2, size_now: Vector2, lane_left: float, lane_right: float
) -> Vector2:
	_zonen_frei = true
	var zonen := _tap_zonen_rects()
	if zonen.is_empty():
		return pos
	var spalten: Array[float] = [pos.x, lane_left, maxf(lane_right - size_now.x, lane_left)]
	for x: float in spalten:
		if not _schneidet_zone(Rect2(Vector2(x, pos.y), size_now), zonen):
			return Vector2(x, pos.y)
	# Kaskaden-Stufe 2: unter die tiefste Zone rutschen, die IRGENDEINEN
	# Spalten-Kandidaten schneidet — und dort erneut alle Spalten prüfen.
	var unten := pos.y
	for zone: Rect2 in zonen:
		for x: float in spalten:
			if Rect2(Vector2(x, pos.y), size_now).intersects(zone):
				unten = maxf(unten, zone.end.y + 8.0)
				break
	var canvas_h := Vector2(get_viewport().get_visible_rect().size).y
	if unten + size_now.y <= canvas_h * ZONEN_TIEFE_ANTEIL:
		for x: float in spalten:
			if not _schneidet_zone(Rect2(Vector2(x, unten), size_now), zonen):
				return Vector2(x, unten)
	_zonen_frei = false
	return pos


func _schneidet_zone(rect: Rect2, zonen: Array[Rect2]) -> bool:
	for zone: Rect2 in zonen:
		if rect.intersects(zone):
			return true
	return false


## Screen-Rects der sichtbaren 3D-Tap-Zonen (Box-Ecken der TapArea-Shapes
## über die aktive Kamera projiziert). Der find_children-Scan läuft nur in
## Settle-Pässen der Karte (kein Frame-Pfad).
## W20 P1 Nachfix (flow_home_basis rot): Playtest-Harness und FB3-Audit
## hängen das Spiel DIREKT unter root — tree.current_scene ist dort null
## und der alte Scan lief leer (die Karte wich NIE aus). Basis ist jetzt
## der oberste Vorfahre der AKTIVEN Kamera: deckt normale Boots, Router-
## Szenen und Harness-Mounts gleichermaßen.
func _tap_zonen_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var tree := get_tree()
	var kamera := get_viewport().get_camera_3d()
	if tree == null or kamera == null or not kamera.is_inside_tree():
		return out
	var basis: Node = kamera
	while basis.get_parent() != null and basis.get_parent() != tree.root:
		basis = basis.get_parent()
	for area: Node in basis.find_children("TapArea", "Area3D", true, false):
		if not (area as Area3D).is_visible_in_tree():
			continue
		var rect := _projiziere_area(area as Area3D, kamera)
		if rect.size.x > 0.0:
			out.append(rect)
	return out


func _projiziere_area(area: Area3D, kamera: Camera3D) -> Rect2:
	var shape_node: CollisionShape3D = null
	for child: Node in area.get_children():
		if child is CollisionShape3D:
			shape_node = child
			break
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return Rect2()
	var box := shape_node.shape as BoxShape3D
	var punkte := PackedVector2Array()
	for sx: float in [-0.5, 0.5]:
		for sy: float in [-0.5, 0.5]:
			for sz: float in [-0.5, 0.5]:
				var ecke := Vector3(sx * box.size.x, sy * box.size.y, sz * box.size.z)
				var welt := shape_node.global_transform * ecke
				if kamera.is_position_behind(welt):
					return Rect2()
				punkte.append(kamera.unproject_position(welt))
	var rect := Rect2(punkte[0], Vector2.ZERO)
	for punkt: Vector2 in punkte:
		rect = rect.expand(punkt)
	return rect


func _on_card_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		AudioDirector.try_play(self, "ui_chip")
		tapped.emit(_suggestion)
