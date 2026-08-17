class_name PanelSheet
extends Control
## Bottom-Sheet im AC-2.0-Look: Veil-Backdrop + Paper-Karte (Radius 36),
## die von unten hereinfedert. Backdrop-Dismiss-Policy wie im Web:
## ein Tap auf den Backdrop schließt NUR das oberste Sheet (`PanelStack`).
##
## FIX1-Umbau (P0 „Panels überdecken alles / Patchnotes broken“):
## - Das Blatt ist ein ZENTRIERTES, breiten-gedeckeltes Sheet über der
##   Abdunkelung — HUD bleibt sichtbar, aber der Backdrop frisst Input.
## - Geometrie kommt aus der puren `PanelSheetLayout` (Safe-Area-Klemmung,
##   Höhen-Deckel); längerer Inhalt scrollt in `%SheetScroll` statt aus dem
##   Bildschirm zu wachsen (das war der Patchnotes-Totalausfall).
## - Schrift/Ränder skalieren mit `UiScale.for_viewport()` (kurze Kante).
## - Escape/Back-Geste schließt das oberste Sheet (SceneRouter → PanelStack).
##
## G7/P53 („Modal-Menüs und Swipen/Wischen muss gefixt werden“): die Basis
## kann jetzt zusätzlich RUNTERWISCHEN-ZUM-SCHLIESSEN — alle Blatt-Nutzer
## erben das automatisch:
## - Geste am Griff-/Kopfbereich (GrabHandle + Sheet-Chrome) zieht das
##   Blatt direkt mit dem Finger mit.
## - Im Scroll-Inhalt zieht die Geste NUR, wenn der innere Scroller ganz
##   oben steht UND die Bewegung nach unten geht — sonst gehört sie dem
##   Scroller (Entscheidung über SWIPE_CLAIM-Schwelle, s. _on_scroll_input).
## - Loslassen über der Schwelle (Weg ODER Schwung) schließt mit
##   Restschwung; darunter schnappt das Blatt federnd zurück.
## - Dim-Tap schließt weiterhin nur das oberste Blatt (Maus UND Touch).
## Reduced Motion: der Finger-Zug bleibt (direkte Manipulation, keine
## Animation), aber Zurückschnappen/Schließen springen sofort.
##
## Nutzung: Szene `panel_sheet.tscn` instanzieren, `add_content(node)`,
## dann `open()`. `closed`-Signal abonnieren.

signal opened
signal closed

## Woher eine aktive Wisch-Geste stammt (Griff-/Kopfbereich oder Scroller).
enum ZugQuelle { KEINE, GRIFF, SCROLLER }

## Innenabstand des Sheet-Bodys (Design-px, skaliert mit UiScale).
const BODY_MARGIN := 8.0
## W20 E1 („Blätter wirken halbtransparent“): der Token-VEIL (α 0.35) lässt
## den Raum samt halbtransparent gefadeter Deckenbalken so deutlich stehen,
## dass es wie ein Render-Bug liest. Sheets dunkeln deshalb KRÄFTIGER ab —
## gleiche Veil-Farbe (INK), nur tieferes Alpha. Token bleibt unberührt
## (Toasts/HUD nutzen VEIL weiter in Web-Referenzstärke).
const VEIL_ALPHA := 0.5
## Bewegung (Design-px), ab der eine Scroll-Geste als Blatt-Zug zählt —
## darunter bleibt sie mehrdeutig und der Scroller behält sie.
const SWIPE_CLAIM := 12.0
## Loslass-Schwelle: so viel Anteil der Blatthöhe gezogen = schließen.
const SWIPE_CLOSE_ANTEIL := 0.25
## Mindest-Schließdistanz (Design-px) für sehr kleine Blätter.
const SWIPE_CLOSE_MIN := 48.0
## Schwung-Schwelle (Design-px/s nach unten): Flick schließt auch früher.
const SWIPE_FLICK_PXPS := 900.0
## Wie stark der Dim beim Zug aufhellt (0.6 = bei voller Strecke 40 % Rest).
const SWIPE_DIM_ANTEIL := 0.6
## Grabber-Pill (Web .panel::before 2.75rem × 0.3125rem = 44×5 Design-px —
## Web-Paritäts-Pin, bewusst außerhalb des 4er-Grids).
const GRIFF_W := 44.0
const GRIFF_H := 5.0

## Notch-Simulation für Tests (Rect2() = aus → DisplayServer fragen).
var safe_area_override := Rect2()

var _open := false
## G4/P21 (QW #23): GENAU EIN Open-/Close-Tween zur Zeit (_fresh_tween-
## Muster aus ui_motion.gd) — schnelles close/open stapelte sonst Tweens
## und das Blatt „wanderte“ pro Zyklus um +60 px nach unten.
var _motion_tween: Tween
## Vollflächiger Input-Schlucker NUR während der Ausblend-Animation:
## das Sheet ist logisch schon zu (_open=false), sichtbare Rest-Buttons
## dürfen im Fade-Fenster nichts mehr auslösen (Muster PauseModal QW #6).
var _fade_blocker: Control
## Ruhelage der Blatt-Oberkante aus dem letzten _relayout (Canvas-px) —
## Zug/Snapback/Close rechnen IMMER von hier, nie von der Momentanposition.
var _rest_y := 0.0
## Zustand der Runterwisch-Geste (genau EINE Geste zur Zeit).
var _zug_aktiv := false
var _zug_quelle := ZugQuelle.KEINE
var _zug_offset := 0.0
var _zug_tempo := 0.0
## Finger-Index der laufenden Geste (-1 = keiner) — zweite Finger stören
## eine aktive Geste nicht (Multi-Touch-Schutz).
var _zug_finger := -1
## Entscheidungsphase einer Scroll-Geste: aufgelaufene Y-Bewegung seit dem
## Auflegen; erst über ±SWIPE_CLAIM fällt die Entscheidung Blatt/Scroller.
var _scroll_druck := false
var _scroll_summe := 0.0
var _scroll_abgelehnt := false
## Fokus-Rückgabe: wer VOR dem Öffnen den Tastatur-Fokus hatte.
var _fokus_vorher: WeakRef
## W18/4 Befund B4: gepinnter Blatt-Fuß UNTER dem Scroll (lazy erzeugt,
## s. add_footer) — CTA-Leisten leben hier statt am Scroll-Ende.
var _footer: MarginContainer
## W20 (a) Fold-Vertrag: ScrollFade-Hülle um %SheetScroll — angeschnittene
## Zeilen lesen sich als Einladung zum Scrollen statt als Layout-Fehler
## (Befund B3 „3. Quest-Karte angeschnitten, kein Scroll-Hinweis“).
var _scroll_huelle: ScrollFade
## Spalten-Container des Blatts (GrabHandle/Titel/Scroll/Fuß) — add_footer
## hängt den Fuß HIER ein; seit der ScrollFade-Hülle wäre
## `_scroll.get_parent()` die Hülle statt der Spalte.
var _sheet_vbox: Container
## Nachmess-Pass pendent? (GENAU EIN Nachpass pro Relayout, s. _nachpass.)
var _nachpass_pendent := false
## Läuft gerade der Nachpass? (verhindert Nachpass-auf-Nachpass-Schleifen)
var _im_nachpass := false

@onready var _backdrop: ColorRect = %Backdrop
@onready var _sheet: PanelContainer = %Sheet
@onready var _title_label: Label = %SheetTitle
@onready var _scroll: ScrollContainer = %SheetScroll
@onready var _body: MarginContainer = %SheetBody
@onready var _grab_handle: Panel = %GrabHandle


func _ready() -> void:
	visible = false
	_backdrop.color = Color(AcTokens.VEIL, VEIL_ALPHA)
	_backdrop.gui_input.connect(_on_backdrop_input)
	_style_grab_handle()
	_erzwinge_opakes_blatt()
	_baue_scroll_huelle()
	_fade_blocker = Control.new()
	_fade_blocker.name = "FadeBlocker"
	_fade_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_blocker.visible = false
	add_child(_fade_blocker)
	get_viewport().size_changed.connect(_on_viewport_resized)
	# G7/P53 Runterwisch-Verdrahtung. Die drei Zonen sind DISJUNKT:
	# Griff (STOP) schluckt seine Events, der Scroller steht explizit auf
	# STOP (Container-Default wäre PASS — dann kämen Scroll-Drags per
	# Bubbling AUCH beim Sheet-Chrome an und würden doppelt gezählt).
	_grab_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_grab_handle.gui_input.connect(_on_griff_input)
	_sheet.gui_input.connect(_on_griff_input)
	_scroll.gui_input.connect(_on_scroll_input)


## UICOZY: Grabber-Pill wie Web .panel::before (44×5 px, Radius 999,
## rgba(74,59,54,.16)) — vorher ein eckiges ColorRect.
func _style_grab_handle() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(AcTokens.INK, 0.16)
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	_grab_handle.add_theme_stylebox_override("panel", sb)


## W20 E1 — Opazitäts-Vertrag: das Blatt selbst ist IMMER voll deckend.
## Die Theme-Karte (AcCardLg) ist heute schon opakes Paper; sollte eine
## künftige Theme-Änderung Alpha < 1 liefern, klemmt der Override das hier
## defensiv fest, statt dass 3D-Raum durch den Blatt-Inhalt scheint.
func _erzwinge_opakes_blatt() -> void:
	var flat := _sheet.get_theme_stylebox("panel") as StyleBoxFlat
	if flat == null or flat.bg_color.a >= 1.0:
		return
	var opak := flat.duplicate() as StyleBoxFlat
	opak.bg_color = Color(flat.bg_color, 1.0)
	_sheet.add_theme_stylebox_override("panel", opak)


## W20 (a) Fold-Vertrag: %SheetScroll in eine ScrollFade-Hülle stecken —
## die Unten-Kante signalisiert „hier geht es weiter“, sobald Inhalt unter
## der Falz liegt. Owner werden nach dem Umhängen restauriert, damit
## `%SheetScroll`/`%SheetBody`-Lookups (Tests, Nutzer) weiter auflösen.
func _baue_scroll_huelle() -> void:
	_sheet_vbox = _scroll.get_parent() as Container
	var idx := _scroll.get_index()
	_sheet_vbox.remove_child(_scroll)
	_scroll_huelle = ScrollFade.um(_scroll)
	_scroll_huelle.name = "SheetScrollFade"
	_sheet_vbox.add_child(_scroll_huelle)
	_sheet_vbox.move_child(_scroll_huelle, idx)
	_scroll.owner = self
	_body.owner = self


## Titel setzen ("" blendet die Titelzeile aus).
func set_title(text: String) -> void:
	_title_label.text = text
	_title_label.visible = not text.is_empty()


## Inhalt einhängen (ersetzt vorherigen Inhalt).
## G4/P21 (P17-Befund): Alt-Inhalt wird SOFORT abgehängt statt nur
## queue_free-pendent zu bleiben — ein pendentes Kind zählt sonst weiter in
## die Min-Size des Blatts (Container-Messung), und ein einmal aufgeblähter
## PanelContainer schrumpft von selbst nicht zurück (Sheet ragte rechts
## aus dem Bild, s. news_50_panel/story_time in G4/P17).
## W18/B1 (Playtest-Blocker „Tagesquests-Blatt dauerhaft leer“): wird
## DERSELBE Node erneut übergeben (Wiederverwendungs-Muster des
## DailyQuestService), darf er NICHT durch die Aufräum-Schleife laufen —
## vorher wurde er queue_free-markiert, wieder eingehängt und am Frame-Ende
## trotzdem GELÖSCHT (ab dem 3. Öffnen hing er als tote Referenz fest).
## add_content ist damit idempotent: Wiedereinhängen zerstört nie Inhalt.
func add_content(node: Control) -> void:
	for child in _body.get_children():
		if child == node:
			continue
		_body.remove_child(child)
		child.queue_free()
	if node.get_parent() != _body:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_body.add_child(node)
	if _open:
		_relayout()


## W18/4 Befund B4 („Aktionsknopf unter der Falz“): GEPINNTER Blatt-Fuß
## nach dem IKEA-Muster aus W18/F6 — der Inhalt scrollt in %SheetScroll,
## der Fuß (CTA-Leiste) sitzt als Geschwister DARUNTER im Sheet-Chrome und
## ist damit in jedem Leitformat ohne Scrollen sichtbar. _relayout zählt
## ihn automatisch zur Chrome-Höhe (Pass 1 misst das Blatt ohne
## Scroll-Inhalt), der Scroll-Innenraum schrumpft entsprechend.
## Idempotent wie add_content: Wiedereinhängen zerstört nie Inhalt.
func add_footer(node: Control) -> void:
	if _footer == null:
		_footer = MarginContainer.new()
		_footer.name = "SheetFooter"
		_apply_footer_margins(UiScale.for_viewport(get_viewport()))
		_sheet_vbox.add_child(_footer)
	for child in _footer.get_children():
		if child == node:
			continue
		_footer.remove_child(child)
		child.queue_free()
	if node.get_parent() != _footer:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_footer.add_child(node)
	if _open:
		_relayout()


func open() -> void:
	if _open:
		return
	AudioDirector.try_play(self, "ui_open")
	_open = true
	visible = true
	PanelStack.push(self)
	_merke_fokus()
	# Läuft noch ein Close-Fade, wird er hier gekappt (QW #23) — danach
	# setzt _relayout die Ruhelage frisch aus dem Layout (nie relativ).
	_kill_motion_tween()
	_zug_reset()
	_fade_blocker.visible = false
	_relayout()
	opened.emit()
	if ThemeService.is_reduced_motion(self):
		_backdrop.modulate.a = 1.0
		_sheet.modulate.a = 1.0
		return
	# W21/ACNH Blatt-Slide-Grammatik (MotionKit.BLATT_*): 280 ms Quint-Out,
	# 24-px-Offset × f. Der Tween bleibt sheet-eigen (Offset-Positionierung
	# + Wisch-Geste), aber Zeiten/Kurve/Weg kommen aus der EINEN Grammatik.
	_backdrop.modulate.a = 0.0
	_sheet.position.y = _rest_y + _blatt_offset()
	_sheet.modulate.a = 0.0
	var tween := _fresh_motion_tween().set_parallel()
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", _rest_y, MotionKit.BLATT_S)
	tween.tween_property(_sheet, "modulate:a", 1.0, MotionKit.BLATT_S * 0.5).set_trans(
		Tween.TRANS_LINEAR
	)
	tween.tween_property(_backdrop, "modulate:a", 1.0, MotionKit.BLATT_S * 0.5).set_trans(
		Tween.TRANS_LINEAR
	)


## Schließen mit Ausblend-Animation (QW #5: Web hat panel-up UND panel-down).
## VERTRAG (Signal-Audit G4/P21): `closed` feuert weiterhin SOFORT — mehrere
## Bestandsnutzer machen `close()` + direktes `queue_free()` (ranch_offer,
## dlc_screen, ranch_fahrt_scene) oder hängen `queue_free` ans Signal
## (rmp_hub, radio_geraet, gooberando/reise_app) — ein spätes Emit würde
## deren Aufräum-/Unfreeze-Pfade verlieren. Nur das AUSBLENDEN ist animiert;
## wird das Sheet direkt nach close() freigegeben, entfällt der Fade schlicht.
## G7/P53: der Ausfahr-Tween startet an der AKTUELLEN Blatt-Position — nach
## einem Runterwisch fährt das Blatt mit Restschwung von dort weiter.
func close() -> void:
	if not _open:
		return
	AudioDirector.try_play(self, "ui_close")
	_open = false
	PanelStack.remove(self)
	_zug_reset()
	closed.emit()
	_gib_fokus_zurueck()
	if not is_inside_tree() or is_queued_for_deletion() or ThemeService.is_reduced_motion(self):
		visible = false
		return
	_fade_blocker.visible = true
	# Blatt-Abgang nach MotionKit.blatt_slide_out-Grammatik (Quint-Out,
	# BLATT_S, Fade 0.7×) — startet an der AKTUELLEN Position (Restschwung).
	var ziel_y := _sheet.position.y + _blatt_offset()
	var tween := _fresh_motion_tween().set_parallel()
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", ziel_y, MotionKit.BLATT_S)
	tween.tween_property(_sheet, "modulate:a", 0.0, MotionKit.BLATT_S * 0.7).set_trans(
		Tween.TRANS_LINEAR
	)
	tween.tween_property(_backdrop, "modulate:a", 0.0, MotionKit.BLATT_S * 0.7).set_trans(
		Tween.TRANS_LINEAR
	)
	tween.chain().tween_callback(_finish_close)


## Ende des Close-Fades: verstecken + Ruhelage/Deckkraft für den nächsten
## open() wiederherstellen (open() relayoutet ohnehin, aber so bleibt der
## versteckte Zustand identisch zum Vor-Animations-Verhalten).
func _finish_close() -> void:
	visible = false
	_fade_blocker.visible = false
	_sheet.position.y = _rest_y
	_sheet.modulate.a = 1.0
	_backdrop.modulate.a = 1.0


## Ein-/Ausfahrweg des Blatts in Canvas-px (MotionKit-Blatt-Grammatik:
## BLATT_OFFSET Design-px × f — der Aufrufer skaliert, wie im Kit-Vertrag).
func _blatt_offset() -> float:
	return MotionKit.BLATT_OFFSET * UiScale.for_viewport(get_viewport())


## _fresh_tween-Muster (ui_motion.gd): vorherigen Bewegungs-Tween killen,
## damit open/close nie parallel auf position/modulate arbeiten.
func _fresh_motion_tween() -> Tween:
	_kill_motion_tween()
	_motion_tween = create_tween()
	return _motion_tween


func _kill_motion_tween() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null


func is_open() -> bool:
	return _open


## Breite des Sheet-Chromes (Karten-StyleBox + Body-Ränder) in Canvas-px:
## Inhalt darf höchstens `PanelSheetLayout.sheet_width() - chrome_width()`
## breit bauen, sonst wird er rechts abgeschnitten (SheetScroll scrollt
## bewusst NUR vertikal). FIX1: Content-Builder (z. B. Status-Sheet) fragen
## das ab, statt feste Breiten zu erzwingen.
func chrome_width() -> float:
	var f := UiScale.for_viewport(get_viewport())
	var chrome := 2.0 * BODY_MARGIN * f
	var style := _sheet.get_theme_stylebox("panel")
	if style != null:
		chrome += style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	return chrome


## Geometrie neu anwenden (open/resize; Tests rufen es direkt).
## Zwei-Pass: erst Wunschhöhe aus dem Inhalt messen, dann per
## `PanelSheetLayout.sheet_rect` klemmen — Überschuss scrollt.
func _relayout() -> void:
	var vp := get_viewport()
	if vp == null or _sheet == null:
		return
	var canvas := Vector2(vp.get_visible_rect().size)
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp, safe_area_override)
	_apply_scale(f)
	# Pass 1: Chrome (Karte + Handle + Titel) ohne Scroll-Inhalt messen.
	_scroll.custom_minimum_size = Vector2.ZERO
	var chrome_h := _sheet.get_combined_minimum_size().y
	var content_min := _body_min_ohne_pendente()
	var desired_h := chrome_h + content_min.y
	var rect := PanelSheetLayout.sheet_rect(canvas, insets, f, desired_h)
	# Pass 2: Scroll-Fenster IMMER = verfuegbarer Innenraum.
	# Frueher: min(content, inner) — wenn content≈inner nach Layout-Pass,
	# kollabiert die Scrollrange (Symptom: Scroll geht 1×, danach tot).
	var inner_h := maxf(rect.size.y - chrome_h, 0.0)
	_scroll.custom_minimum_size = Vector2(0.0, inner_h)
	_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sheet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sheet.offset_left = rect.position.x
	_sheet.offset_top = rect.position.y
	_sheet.offset_right = rect.position.x + rect.size.x
	_sheet.offset_bottom = rect.position.y + rect.size.y
	# G7/P53: Ruhelage merken — Zug/Snapback/Close rechnen von hier.
	_rest_y = rect.position.y
	if _zug_aktiv:
		_sheet.position.y = _rest_y + _zug_offset
	_nachpass_planen()


## W18/4 B4-Nachpass: frisch eingehängte Autowrap-Inhalte (Fuß-Hinweis,
## Body-Labels) melden VOR ihrem ersten Layout-Pass Fantasie-Minima
## (Breite 0 → jede Silbe eine eigene Zeile). Der Chrome-Messwert aus
## Pass 1 kann dadurch ÜBER dem Höhen-Deckel liegen — das Blatt bläht
## sich über seinen geklemmten Rect hinaus und schiebt den gepinnten Fuß
## unter die Falz (in kurzen Canvases, z. B. quer, exakt Befund B4).
## Einen Frame später stehen die echten Breiten: einmal nachmessen und,
## falls die Ruhelage wanderte, eine laufende Einfahr-/Snap-Animation auf
## das frische Ziel umlenken (ihr Endwert war beim Start eingefroren).
func _nachpass_planen() -> void:
	if _nachpass_pendent or _im_nachpass or not is_inside_tree():
		return
	_nachpass_pendent = true
	_nachpass()


func _nachpass() -> void:
	await get_tree().process_frame
	_nachpass_pendent = false
	if not _open or not is_inside_tree():
		return
	var rest_vorher := _rest_y
	_im_nachpass = true
	_relayout()
	_im_nachpass = false
	if absf(_rest_y - rest_vorher) <= 0.5:
		return
	if _motion_tween != null and _motion_tween.is_valid() and _motion_tween.is_running():
		var tween := _fresh_motion_tween().set_parallel()
		tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tween.tween_property(_sheet, "position:y", _rest_y, MotionKit.BLATT_S)
		tween.tween_property(_sheet, "modulate:a", 1.0, MotionKit.BLATT_S * 0.5).set_trans(
			Tween.TRANS_LINEAR
		)
		tween.tween_property(_backdrop, "modulate:a", 1.0, MotionKit.BLATT_S * 0.5).set_trans(
			Tween.TRANS_LINEAR
		)


## Body-Wunschgröße wie MarginContainer.get_minimum_size(), aber OHNE
## queue_free-PENDENTE Kinder (G4/P21, P17-Befund): Inhalte, die per
## queue_free ersetzt werden, blähten sonst bis zum echten Freigabe-Frame
## die gemessene Wunschhöhe auf.
func _body_min_ohne_pendente() -> Vector2:
	var innen := Vector2.ZERO
	for child in _body.get_children():
		var ctl := child as Control
		if ctl == null or ctl.is_queued_for_deletion() or not ctl.visible or ctl.top_level:
			continue
		innen = innen.max(ctl.get_combined_minimum_size())
	var rand := Vector2(
		float(_body.get_theme_constant("margin_left") + _body.get_theme_constant("margin_right")),
		float(_body.get_theme_constant("margin_top") + _body.get_theme_constant("margin_bottom"))
	)
	return (innen + rand).max(_body.get_custom_minimum_size())


func _apply_scale(f: float) -> void:
	_title_label.add_theme_font_size_override("font_size", AcTokens.font_px(AcTokens.SIZE_TITLE, f))
	# Grabber-Pill skaliert mit (Web-Paritäts-Pin GRIFF_W×GRIFF_H).
	_grab_handle.custom_minimum_size = Vector2(
		float(AcTokens.px(GRIFF_W, f)), maxf(float(AcTokens.px(GRIFF_H, f)), 4.0)
	)
	var pad := AcTokens.px(BODY_MARGIN, f)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		_body.add_theme_constant_override(side, pad)
	if _scroll_huelle != null:
		_scroll_huelle.kanten_hoehe(ScrollFade.KANTE * f)
	_apply_footer_margins(f)


## Fuß-Ränder wie der Body (B4) — nur seitlich/unten; oben hält der
## SheetVBox-Abstand den Fuß vom Scroll-Inhalt frei.
func _apply_footer_margins(f: float) -> void:
	if _footer == null:
		return
	var pad := AcTokens.px(BODY_MARGIN, f)
	for side in ["margin_left", "margin_right", "margin_bottom"]:
		_footer.add_theme_constant_override(side, pad)


func _on_viewport_resized() -> void:
	if _open:
		_relayout()


## Dim-Tap schließt NUR das oberste Blatt — Maus UND Touch (G7/P53: auf
## Geräten ohne Maus-Emulation kam vorher kein MouseButton-Event an).
func _on_backdrop_input(event: InputEvent) -> void:
	var tipp := false
	if event is InputEventMouseButton and event.pressed:
		tipp = true
	elif event is InputEventScreenTouch and event.pressed:
		tipp = true
	if tipp and _open and PanelStack.is_top(self):
		close()


## ------------------------------------------------ G7/P53 Runterwischen


## Griff-/Kopfbereich (GrabHandle + Sheet-Chrome): jede aufgelegte
## Touch-Geste zieht das Blatt sofort mit — hier gibt es keinen
## Scroll-Konflikt. Maus läuft über die projektweite Touch-Emulation.
func _on_griff_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _open and not _zug_aktiv and _zug_finger < 0:
				_zug_finger = touch.index
				_zug_start(ZugQuelle.GRIFF)
		elif touch.index == _zug_finger:
			_zug_ende()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _zug_aktiv and _zug_quelle == ZugQuelle.GRIFF and drag.index == _zug_finger:
			_zug_bewege(drag.relative.y, drag.velocity.y)


## Scroll-Bereich: die Geste gehört ERST dem Scroller. Läuft schon ein
## Blatt-Zug, schluckt accept_event() die Drags, damit der Scroller nicht
## gleichzeitig weiterscrollt (das Signal feuert VOR der eingebauten
## ScrollContainer-Verarbeitung).
func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_scroll_touch(event as InputEventScreenTouch)
		return
	if not (event is InputEventScreenDrag):
		return
	var drag := event as InputEventScreenDrag
	if drag.index != _zug_finger:
		return
	if _zug_aktiv:
		if _zug_quelle == ZugQuelle.SCROLLER:
			_zug_bewege(drag.relative.y, drag.velocity.y)
			_scroll.scroll_vertical = 0
			_scroll.accept_event()
		return
	if _scroll_druck and not _scroll_abgelehnt:
		_scroll_entscheide(drag)


## Entscheidungsphase (DER knifflige Teil): gehört die Geste dem Blatt
## oder dem Scroller? Blatt nur, wenn der innere Scroller GANZ OBEN steht
## und die Bewegung klar nach unten geht (> SWIPE_CLAIM). Ein
## Aufwärts-Start lehnt bis zum Loslassen ab — kein Umspringen mitten im
## Scrollen, Scroll-Inhalte ziehen das Blatt nie fälschlich mit.
func _scroll_entscheide(drag: InputEventScreenDrag) -> void:
	if _scroll.scroll_vertical > 0:
		_scroll_abgelehnt = true
		return
	_scroll_summe += drag.relative.y
	var claim := SWIPE_CLAIM * UiScale.for_viewport(get_viewport())
	if _scroll_summe <= -claim:
		_scroll_abgelehnt = true
	elif _scroll_summe >= claim:
		_zug_start(ZugQuelle.SCROLLER)
		_zug_bewege(_scroll_summe, drag.velocity.y)
		_scroll.accept_event()


## Auflegen/Loslassen im Scroll-Bereich (Entscheidungsphase starten/enden).
func _on_scroll_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _open and not _zug_aktiv and _zug_finger < 0:
			_zug_finger = touch.index
			_scroll_druck = true
			_scroll_summe = 0.0
			_scroll_abgelehnt = false
	elif touch.index == _zug_finger:
		_zug_ende()


func _zug_start(quelle: ZugQuelle) -> void:
	# Ein evtl. laufender Open-Tween wird gekappt — der Finger übernimmt.
	_kill_motion_tween()
	_sheet.modulate.a = 1.0
	_zug_aktiv = true
	_zug_quelle = quelle
	_zug_offset = maxf(_sheet.position.y - _rest_y, 0.0)
	_zug_tempo = 0.0


## Blatt folgt dem Finger (nur nach unten; der Dim hellt mit dem Zug auf).
## Bewusst OHNE Reduced-Motion-Gate: direkte Manipulation ist keine
## Animation — RM greift beim Loslassen (sofort schließen/zurücksetzen).
func _zug_bewege(dy: float, tempo_y: float) -> void:
	_zug_offset = maxf(_zug_offset + dy, 0.0)
	_zug_tempo = tempo_y
	_sheet.position.y = _rest_y + _zug_offset
	var anteil := clampf(_zug_offset / _schliess_distanz(), 0.0, 1.0)
	_backdrop.modulate.a = 1.0 - SWIPE_DIM_ANTEIL * anteil


## Loslassen: über der Weg- ODER Schwung-Schwelle schließen (close()
## fährt mit Restschwung von der aktuellen Position weiter), sonst
## federnd zurückschnappen. Haptik: leichter Tipp NUR beim Schließen.
func _zug_ende() -> void:
	var war_aktiv := _zug_aktiv
	var offset := _zug_offset
	var tempo := _zug_tempo
	_zug_reset()
	if not war_aktiv:
		return
	var f := UiScale.for_viewport(get_viewport())
	if offset >= _schliess_distanz() or tempo >= SWIPE_FLICK_PXPS * f:
		Haptics.tap(self)
		close()
		return
	_snap_zurueck(offset)


## Zurückschnappen in die Ruhelage (Kurz-Wisch) — RM: sofort, kein Slide.
func _snap_zurueck(offset: float) -> void:
	if offset <= 0.5 or ThemeService.is_reduced_motion(self):
		_sheet.position.y = _rest_y
		_backdrop.modulate.a = 1.0
		return
	var tween := _fresh_motion_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", _rest_y, AcTokens.DUR_POP)
	tween.tween_property(_backdrop, "modulate:a", 1.0, AcTokens.DUR_POP).set_trans(
		Tween.TRANS_LINEAR
	)


## Gesten-Zustand vollständig löschen (open/close/Loslassen).
func _zug_reset() -> void:
	_zug_aktiv = false
	_zug_quelle = ZugQuelle.KEINE
	_zug_offset = 0.0
	_zug_tempo = 0.0
	_zug_finger = -1
	_scroll_druck = false
	_scroll_summe = 0.0
	_scroll_abgelehnt = false


## Loslass-Schwelle in Canvas-px: Anteil der Blatthöhe, mindestens
## SWIPE_CLOSE_MIN×f (sehr kleine Blätter schließen sonst beim Antippen).
func _schliess_distanz() -> float:
	var f := UiScale.for_viewport(get_viewport())
	return maxf(SWIPE_CLOSE_ANTEIL * _sheet.size.y, SWIPE_CLOSE_MIN * f)


## ------------------------------------------------ G7/P53 Fokus-Rückgabe


## Beim Öffnen merken, wer den Tastatur-Fokus hatte (WeakRef — der
## Eigner darf zwischenzeitlich sterben, ohne dass wir daran hängen).
func _merke_fokus() -> void:
	_fokus_vorher = null
	var vp := get_viewport()
	if vp == null:
		return
	var eigner := vp.gui_get_focus_owner()
	if eigner != null:
		_fokus_vorher = weakref(eigner)


## Beim Schließen: Fokus, der im Blatt hängt, freigeben und dem
## Vorher-Eigner zurückgeben (sofern er noch lebt und sichtbar ist).
func _gib_fokus_zurueck() -> void:
	var vp := get_viewport()
	if vp != null:
		var eigner := vp.gui_get_focus_owner()
		if eigner != null and is_ancestor_of(eigner):
			eigner.release_focus()
	if _fokus_vorher == null:
		return
	var ziel := _fokus_vorher.get_ref() as Control
	_fokus_vorher = null
	if ziel != null and is_instance_valid(ziel) and ziel.is_inside_tree():
		if ziel.is_visible_in_tree():
			ziel.grab_focus()
