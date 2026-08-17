class_name PhoneShell
extends Control
## IGohbie — die Handy-Shell (Doc E §5.1): Vollbild-Overlay im AC-Look mit
## Statusleiste (Uhr, Münzen, Akku = Goobys Energie), App-Grid aus der
## `PhoneApps`-Registry und Zurück-Geste (Wisch nach unten auf dem Gerät,
## Home-Balken oder ESC). Ein Tipp aufs Grid ersetzt den Inhalt durch die
## App, der Home-Balken geht zurück — zweimal schließt das Handy.
##
## W16/G4 P18: Das Gerät ist KEINE 380×640-Fixkarte mehr — es skaliert mit
## `ScreenShell.metrics()` (×f, `card_width`/`card_max_height`-Deckel),
## Kacheln/Geste/Schriften ziehen mit, und bei Canvas-Änderung (Rotation)
## baut die Shell die aktive Ansicht mit frischen Metriken neu. Apps koppeln
## ihre Breiten über `inhalt_breite()`/`app_label()` an die REALE
## Gerätebreite statt an die 420er-City-Bausteine (G1 ui-post §3/§4).
##
## HUD-Anbindung (Orchestrator): `hud.action_pressed` mit &"igohbie" →
## `PhoneShell.handle_hud_action(action, host, gs)` — GLEICHE Signatur wie
## `GooberandoApp.handle_hud_action`, der Aufruf lässt sich also 1:1 tauschen.
##
## G7/P52 TELEFON-REWORK (User-Screenshot vom echten iPhone, Querformat):
## (1) Gesperrte Apps sind KEIN dunkler Blob mehr (das INK_FAINT-Modulate
## multiplizierte die ganze Kachel dunkel) — Icon bleibt blass erkennbar,
## ein Schloss-Badge sagt „noch zu“. (2) Querformat bekommt eine BREITE
## Geräte-Basis (GERAET_QUER) mit dynamischen Grid-Spalten (3–5), damit
## alle Labels über dem Scroll-Falz bleiben. (3) Öffnen poppt federnd
## (RM = sofort), Grid staffelt, Apps gleiten rein. (4) Zusätzliche
## Zurück-Geste: Wisch VON LINKS in einer App führt zurück aufs Grid.

signal app_geoeffnet(app_id: String)
signal geschlossen

const HUD_ACTION := &"igohbie"
## Wischweg (Design-px, ×f), ab dem die Zurück-Geste auslöst.
const GESTE_PX := 90.0
## Startzone der Links-Wisch-Geste (Design-px ×f vom linken Geräterand).
const GESTE_RAND_PX := 64.0
## Design-Basis des Geräts — die echte Größe liefert `geraet_groesse()`.
## G7/P52: im Querformat eine BREITE Basis (Leitformat iPhone 2868×1320),
## damit das Grid die Breite nutzt statt als schmale Hochkant-Karte im
## Höhen-Deckel zu verhungern (User: „Modal wirkt klein/leer im Querformat“).
const GERAET_GROESSE := Vector2(380.0, 640.0)
const GERAET_QUER := Vector2(640.0, 480.0)
## Kachelbreite (Design-px): „GOOBERANDO" ist das längste Label und muss
## in eine Spalte passen (Beschriftung = Caption-Stufe der Typo-Skala).
const KACHEL_BREITE := 112.0
## Kachel-Knopf-Höhe (Design-px): Querformat flacher, damit 2 Grid-Reihen
## MIT Labels unter den card_max_height-Deckel passen (Touch-Floor bleibt).
const KACHEL_HOEHE := 84.0
const KACHEL_HOEHE_QUER := 72.0
## Grid-Lücken (Design-px, W21: auf dem 4er-Raster) und Spaltenfenster:
## hoch 3 Spalten wie gehabt, quer so viele wie hineinpassen (max 5).
const GRID_LUECKE := 4.0
const GRID_V_LUECKE := 12.0
const GRID_V_LUECKE_QUER := 8.0
const GRID_SPALTEN_MIN := 3
const GRID_SPALTEN_MAX := 5
## Gesperrte App: Kachel bleibt ERKENNBAR blass (nur Alpha, kein dunkles
## Multiplikations-Modulate — das war der „Blob“ im User-Screenshot).
const GESPERRT_ALPHA := 0.55
const SCHLOSS_ICON := "res://assets/ui/icons/lock.svg"
## AcCard-Innenrand (Theme `_card`: content_margin 18 je Seite).
const KARTEN_RAND := 18.0
## Reserve für den vertikalen Scrollbalken des Inhalts-Scrolls.
const SCROLL_RESERVE := 16.0
## W18/4 B2: Wisch-Deadzone des Inhalts-Scrolls (px) — darunter bleibt die
## Geste ein Tap, darüber gehört sie dem Scroll (F6-Arcade-Muster).
const SCROLL_DEADZONE := 24

var gs: Object
## Host für Vollbild-Kinder (Fotomodus) — Default: der Szenenbaum-Wurzelknoten.
var host: Node

var aktive_app := ""

var _geraet: PanelContainer
var _inhalt: VBoxContainer
var _scroll: ScrollContainer
## W18/4 B2 (IKEA-Muster W18/F6): gepinnter CTA-Bereich UNTER dem Scroll.
var _fuss: VBoxContainer
var _titel: Label
var _uhr: Label
var _muenzen: Label
var _akku: ProgressBar
var _home: Button
var _status_icons: Array[TextureRect] = []
var _geste_x := 0.0
var _geste_y := 0.0
var _geste_aktiv := false
var _geste_von_links := false
## W18/4 B2: Zustand des eigenen Wisch-Pans (s. _on_scroll_gui_input).
var _pan_druck := false
var _pan_aktiv := false
var _pan_summe := 0.0
var _pan_start := 0.0
## Zuletzt angewandte ScreenShell-Metriken (f, canvas, insets, floor_px).
var _m: Dictionary = {}


## Handy über der laufenden Szene öffnen (eigener CanvasLayer, Theme gesetzt).
static func oeffne(scene_host: Node, game_state: Object) -> PhoneShell:
	var layer := CanvasLayer.new()
	layer.name = "IGohbieLayer"
	layer.layer = 30
	scene_host.add_child(layer)
	var shell := PhoneShell.new()
	shell.name = "PhoneShell"
	shell.gs = game_state
	shell.host = scene_host
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	shell.theme = ThemeService.theme()
	shell.geschlossen.connect(func() -> void: layer.queue_free())
	layer.add_child(shell)
	return shell


## HUD-Aktions-Handler — identische Signatur wie GooberandoApp.
static func handle_hud_action(action: StringName, scene_host: Node, game_state: Object) -> bool:
	if action != HUD_ACTION:
		return false
	oeffne(scene_host, game_state)
	return true


## ------------------------------------------ geteilte Geometrie (Apps)


## Haupt-Viewport — auch für Builder benutzbar, die VOR add_child laufen.
static func _haupt_viewport() -> Viewport:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root if loop is SceneTree else null


## Querformat? (Canvas breiter als hoch — Leitformat iPhone 2868×1320.)
static func ist_querformat(m: Dictionary) -> bool:
	var canvas: Vector2 = m["canvas"]
	return canvas.x > canvas.y


## Design-Basis je Orientierung (G7/P52): hoch die 380×640-Telefonkarte,
## quer die breite 640×480-Karte — der Höhen-Deckel würde ein Hochkant-
## Gerät im Querformat sonst auf eine leere Briefmarke stauchen.
static func basis_groesse(m: Dictionary) -> Vector2:
	return GERAET_QUER if ist_querformat(m) else GERAET_GROESSE


## Gerätegröße aus den Metriken: Basis ×f, gedeckelt auf die Safe-Breite
## (`card_width`) und den Karten-Höhen-Deckel — das Gerät wächst und
## schrumpft mit dem Canvas, statt fix zu kleben (G1 ui-post §3).
static func geraet_groesse(m: Dictionary) -> Vector2:
	var f: float = m["f"]
	var basis := basis_groesse(m)
	return Vector2(
		ScreenShell.card_width(m, basis.x), minf(basis.y * f, ScreenShell.card_max_height(m))
	)


## Spaltenzahl des App-Grids für eine Innenbreite (pur, für Tests): so
## viele 112er-Kacheln wie hineinpassen, gefenstert auf 3–5 Spalten.
static func grid_spalten(innen: float, f: float) -> int:
	var schritt := (KACHEL_BREITE + GRID_LUECKE) * f
	if schritt <= 0.0:
		return GRID_SPALTEN_MIN
	var nutzbar := innen + GRID_LUECKE * f
	var passt := int(floorf(nutzbar / schritt))
	return clampi(passt, GRID_SPALTEN_MIN, GRID_SPALTEN_MAX)


## Reale Innenbreite des Geräts für App-Inhalte (Canvas-px): Gerätebreite
## minus AcCard-Rand und Scroll-Reserve. Apps koppeln ihre Text-/Karten-
## breiten HIERAN statt an die 420er-City-Bausteine — das behebt die
## Breiten-Kollision aus G1 ui-post §4.
static func inhalt_breite() -> float:
	var vp := _haupt_viewport()
	if vp == null:
		return GERAET_GROESSE.x - 2.0 * KARTEN_RAND - SCROLL_RESERVE
	var m := ScreenShell.metrics(vp)
	var f: float = m["f"]
	return geraet_groesse(m).x - 2.0 * KARTEN_RAND - SCROLL_RESERVE * f


## Breite für Fließtext IN einer App-Karte (zieht den Karten-Rand ab).
static func text_breite() -> float:
	return maxf(inhalt_breite() - 2.0 * KARTEN_RAND, 120.0)


## Wurzel-Box einer Phone-App einrichten: füllt die Gerätebreite (statt
## `CitySheetBausteine.richte_box_ein` mit 420er-Fixbreite).
static func richte_app_box_ein(box: VBoxContainer) -> void:
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)


## Autowrap-Label in Gerätebreite (W3a-GOTCHA: Breite VOR add_child setzen).
static func app_label(box: Control, text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var breite := text_breite()
	l.custom_minimum_size = Vector2(breite, 0.0)
	l.size = Vector2(breite, 0.0)
	if not variation.is_empty():
		l.theme_type_variation = variation
	box.add_child(l)
	return l


## Karten-Panel (AcCard) in Gerätebreite mit eigener VBox.
static func app_karte(box: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AcCard"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 6)
	panel.add_child(inhalt)
	return inhalt


## Scroll-Bereich mit innerer VBox — Höhe in Design-px, ×f skaliert und
## auf ~60 % der Gerätehöhe gedeckelt (mehr Inhalt scrollt außen mit).
static func app_scroll_liste(box: Control, hoehe_design: float) -> VBoxContainer:
	var hoehe := hoehe_design
	var vp := _haupt_viewport()
	if vp != null:
		var m := ScreenShell.metrics(vp)
		var f: float = m["f"]
		hoehe = minf(hoehe_design * f, geraet_groesse(m).y * 0.6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, hoehe)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var liste := VBoxContainer.new()
	liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	liste.add_theme_constant_override("separation", 8)
	scroll.add_child(liste)
	return liste


## W18/4 B2 (IKEA-Muster W18/F6): gepinnter CTA-Bereich der Telefon-Shell —
## GESCHWISTER des Inhalts-Scrolls, nicht Kind. Kauf-/Bestell-Knöpfe, die
## hier landen, bleiben in beiden Formaten im Bild statt (wie GOOBERANDOs
## „Bestellen“) ~2 Viewports unter die Falz zu rutschen. Liefert null,
## wenn die App ohne PhoneShell läuft (Standalone-Sheet) — dann bauen
## Apps ihren CTA wie bisher in den eigenen Fluss.
static func app_fuss_bereich(app: Control) -> VBoxContainer:
	var knoten: Node = app
	while knoten != null and not (knoten is PhoneShell):
		knoten = knoten.get_parent()
	if knoten == null:
		return null
	return (knoten as PhoneShell)._fuss


## Kind in den gepinnten Fuß hängen (macht ihn sichtbar). Liefert false,
## wenn die App ohne PhoneShell läuft — der Aufrufer baut dann inline.
static func pinne_in_fuss(app: Control, ctl: Control) -> bool:
	var fuss := app_fuss_bereich(app)
	if fuss == null:
		return false
	fuss.add_child(ctl)
	fuss.visible = true
	return true


## Fuß leeren + verstecken — Apps rufen das am Anfang JEDES Re-Renders
## (die Shell selbst räumt nur beim Ansichtswechsel via _leere_inhalt).
static func leere_app_fuss(app: Control) -> void:
	var fuss := app_fuss_bereich(app)
	if fuss == null:
		return
	for kind in fuss.get_children():
		fuss.remove_child(kind)
		kind.queue_free()
	fuss.visible = false


## Schriften eines App-Teilbaums auf den aktuellen ×f-Faktor heben —
## Apps rufen das nach JEDEM (Neu-)Bau ihrer Kinder auf.
static func app_fonts_skalieren(box: Control) -> void:
	if box == null or not box.is_inside_tree():
		return
	var m := ScreenShell.metrics(box.get_viewport())
	ScreenShell.scale_fonts(box, m["f"])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# W20 P1 (Verdeckungs-Vertrag, 1-Zeilen-Hook): solange das Telefon
	# sichtbar ist, weicht das HUD (HudSichtbarkeit beobachtet die Gruppe).
	add_to_group(HudSichtbarkeit.VERDECKER_GROUP)
	if host == null:
		host = get_tree().root
	_m = ScreenShell.metrics(get_viewport())
	_baue_scrim()
	_baue_geraet()
	zeige_grid()
	get_viewport().size_changed.connect(_on_canvas_geaendert)
	_anim_geraet_auf()


func _process(_delta: float) -> void:
	if _uhr != null:
		_uhr.text = Time.get_time_string_from_system().substr(0, 5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		zurueck()
		get_viewport().set_input_as_handled()


## Wischweg in Canvas-px (Design 90 ×f) — öffentlich für Tests.
func geste_schwelle() -> float:
	return GESTE_PX * float(_m.get("f", 1.0))


## Breite der Links-Wisch-Startzone in Canvas-px (Design 64 ×f).
func geste_rand() -> float:
	return GESTE_RAND_PX * float(_m.get("f", 1.0))


## App-Grid zeigen (Startbildschirm). G7/P52: Spaltenzahl folgt der realen
## Gerätebreite (quer 4–5 statt 3), Kacheln staffeln federnd ein (RM = sofort).
func zeige_grid() -> void:
	aktive_app = ""
	_titel.text = I18nService.t("phone.titel")
	# G7/P52: im Querformat frisst der große Titel die (vom Höhen-Deckel)
	# knappe Gerätehöhe — der Grid-Startbildschirm kommt ohne ihn aus wie
	# ein echter Homescreen; App-Ansichten behalten ihre Überschrift.
	_titel.visible = not PhoneShell.ist_querformat(_m)
	_leere_inhalt()
	# W20/P3 (Befund B6 „riesige Leerfläche unterm Grid"): der Homescreen
	# zentriert vertikal im Scroll-Fenster; App-Ansichten stapeln oben.
	_inhalt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inhalt.alignment = BoxContainer.ALIGNMENT_CENTER
	var f: float = _m.get("f", 1.0)
	var innen := _geraet.custom_minimum_size.x - 2.0 * KARTEN_RAND
	var spalten := PhoneShell.grid_spalten(innen, f)
	var kachel_breite := minf(
		KACHEL_BREITE * f, (innen - float(spalten - 1) * GRID_LUECKE * f) / float(spalten)
	)
	var grid := GridContainer.new()
	grid.name = "AppGrid"
	grid.columns = spalten
	grid.add_theme_constant_override("h_separation", AcTokens.px(GRID_LUECKE, f))
	var v_luecke := GRID_V_LUECKE_QUER if PhoneShell.ist_querformat(_m) else GRID_V_LUECKE
	grid.add_theme_constant_override("v_separation", AcTokens.px(v_luecke, f))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_inhalt.add_child(grid)
	var kacheln: Array = []
	for app: Dictionary in PhoneApps.grid(gs):
		var kachel := _baue_kachel(app, kachel_breite)
		grid.add_child(kachel)
		kacheln.append(kachel)
	if Fahrdienst.ist_rettungsweg(gs):
		PhoneShell.app_label(_inhalt, I18nService.t("phone.fahrdienst.rettung"), "CaptionLabel")
	ScreenShell.scale_fonts(_geraet, f)
	_anim_grid_rein(kacheln)


## Eine App öffnen (id aus PhoneApps.ids()). Outcome klingt: gesperrt =
## ui_error, Ansichtswechsel ins App-UI = ui_chip (Grammatik W16 §3).
func oeffne_app(app_id: String) -> void:
	if not PhoneApps.ist_offen(app_id, gs):
		AudioDirector.try_play(self, "ui_error")
		_zeige_toast(I18nService.t(PhoneApps.gesperrt_key(app_id, gs)))
		return
	if aktive_app != app_id:
		AudioDirector.try_play(self, "ui_chip")
	aktive_app = app_id
	_titel.text = I18nService.t(str(PhoneApps.app(app_id).get("name_key", "phone.titel")))
	_titel.visible = true
	_leere_inhalt()
	# App-Ansichten stapeln oben (B6-Zentrierung gilt nur dem Homescreen).
	_inhalt.size_flags_vertical = Control.SIZE_FILL
	_inhalt.alignment = BoxContainer.ALIGNMENT_BEGIN
	var inhalt := _baue_app(app_id)
	if inhalt != null:
		_inhalt.add_child(inhalt)
		_anim_inhalt_rein(inhalt)
	ScreenShell.scale_fonts(_geraet, _m.get("f", 1.0))
	app_geoeffnet.emit(app_id)


## Zurück-Geste: aus der App aufs Grid, vom Grid aus schließt das Handy.
func zurueck() -> void:
	if aktive_app.is_empty():
		schliesse()
		return
	zeige_grid()


func schliesse() -> void:
	geschlossen.emit()


## Fotomodus starten: Handy zu, Sucher über die laufende Szene.
func starte_fotomodus() -> FotoModus:
	var modus := FotoModus.oeffne(host, gs)
	schliesse()
	return modus


## ---------------------------------------------------------------- Aufbau


func _baue_scrim() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = AcTokens.VEIL_DEEP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)


func _baue_geraet() -> void:
	_geraet = PanelContainer.new()
	_geraet.name = "Geraet"
	_geraet.theme_type_variation = "AcCard"
	_geraet.set_anchors_preset(Control.PRESET_CENTER)
	_geraet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_geraet.grow_vertical = Control.GROW_DIRECTION_BOTH
	_geraet.gui_input.connect(_on_geraet_input)
	add_child(_geraet)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 12)
	_geraet.add_child(spalte)
	spalte.add_child(_baue_statusleiste())
	_titel = Label.new()
	_titel.theme_type_variation = "TitleLabel"
	_titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spalte.add_child(_titel)
	_scroll = ScrollContainer.new()
	_scroll.name = "InhaltScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# W18/4 B2: Maus-Wisch scrollt jetzt auch (eigener Pan im gui_input-
	# Signal, s. _on_scroll_gui_input) — die Deadzone trennt Tap von Wisch.
	_scroll.scroll_deadzone = SCROLL_DEADZONE
	_scroll.gui_input.connect(_on_scroll_gui_input)
	spalte.add_child(_scroll)
	_inhalt = VBoxContainer.new()
	_inhalt.name = "Inhalt"
	_inhalt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inhalt.add_theme_constant_override("separation", 12)
	_scroll.add_child(_inhalt)
	# W18/4 B2: Fuß-Bereich für gepinnte App-CTAs (Geschwister des Scrolls,
	# s. app_fuss_bereich) — unsichtbar solange leer (kein Phantom-Abstand).
	_fuss = VBoxContainer.new()
	_fuss.name = "AppFuss"
	_fuss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuss.add_theme_constant_override("separation", 8)
	_fuss.visible = false
	spalte.add_child(_fuss)
	spalte.add_child(_baue_home_balken())
	_wende_metrik_an()


## Metriken einsammeln und aufs Gerät anwenden (Größe + Schriften).
func _wende_metrik_an() -> void:
	_m = ScreenShell.metrics(get_viewport())
	_geraet.custom_minimum_size = PhoneShell.geraet_groesse(_m)
	_geraet.set_anchors_preset(Control.PRESET_CENTER)
	var f: float = _m["f"]
	if _akku != null:
		_akku.custom_minimum_size = Vector2(52.0, 12.0) * f
	# G7/P52: Statusleisten-Icons ziehen bei Rotation mit (quer nicht quetschen).
	for icon: TextureRect in _status_icons:
		icon.custom_minimum_size = Vector2(18.0, 18.0) * f
	# FB3-Altbefund: HomeBalken-Tippfläche lag bei 40,2 pt — der physische
	# Touch-Floor (≥ 44 pt) wird bei JEDER Metrik-Anwendung frisch gesetzt.
	# W20/P3 B6: Basisbreite der Zurück-Pill zieht ×f mit (statt Vollbreite).
	if _home != null:
		_home.custom_minimum_size = Vector2(AcTokens.px(180.0, f), 0.0)
		ScreenShell.touch_target(_home, _m)
	ScreenShell.scale_fonts(_geraet, f)


## Canvas geändert (Rotation/Resize): Gerät neu vermessen und die aktive
## Ansicht mit frischen Metriken neu bauen (Muster RadioSheet W17/G4).
func _on_canvas_geaendert() -> void:
	if _geraet == null or not is_inside_tree():
		return
	_wende_metrik_an()
	if aktive_app.is_empty():
		zeige_grid()
	else:
		oeffne_app(aktive_app)


## ------------------------------------------------- Animationen (G7/P52)


## Öffnen-Moment: das Telefon poppt federnd auf (DUR_SHEET = 240 ms, Web
## --ease-spring); Reduced Motion springt sofort in den Endzustand. Pivot
## aus der Metrik-Größe — die Layout-Größe steht im _ready noch nicht.
func _anim_geraet_auf() -> void:
	if UiMotion.reduced(self):
		return
	_geraet.pivot_offset = PhoneShell.geraet_groesse(_m) / 2.0
	_geraet.scale = Vector2.ONE * 0.9
	_geraet.modulate.a = 0.0
	var tween := _geraet.create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_geraet, "scale", Vector2.ONE, AcTokens.DUR_SHEET)
	tween.tween_property(_geraet, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0).set_trans(
		Tween.TRANS_LINEAR
	)


## Grid-Kacheln staffeln federnd ein (RM: sofort sichtbar). Der Start läuft
## deferred, damit die Kacheln beim pop_in ihre Layout-Größe (Pivot) haben.
func _anim_grid_rein(kacheln: Array) -> void:
	if kacheln.is_empty() or UiMotion.reduced(self):
		return
	for kachel: Control in kacheln:
		kachel.modulate.a = 0.0
	_starte_grid_stagger.call_deferred(kacheln)


func _starte_grid_stagger(kacheln: Array) -> void:
	var lebendig: Array = []
	for kachel: Control in kacheln:
		if is_instance_valid(kachel) and kachel.is_inside_tree():
			lebendig.append(kachel)
	UiMotion.stagger_in(lebendig)


## App-Inhalt gleitet nach dem Kachel-Squish ins Gerät (RM: sofort da).
## Deferred, damit die VBox den Inhalt erst einsortiert (Ruhelage-y).
func _anim_inhalt_rein(ctl: Control) -> void:
	if UiMotion.reduced(self):
		return
	ctl.modulate.a = 0.0
	_starte_inhalt_slide.call_deferred(ctl)


func _starte_inhalt_slide(ctl: Control) -> void:
	if not is_instance_valid(ctl) or not ctl.is_inside_tree():
		return
	ctl.modulate.a = 1.0
	UiMotion.slide_up_in(ctl, AcTokens.DUR_SHEET)


func _baue_statusleiste() -> Control:
	var zeile := HBoxContainer.new()
	zeile.name = "Statusleiste"
	zeile.add_theme_constant_override("separation", 10)
	_uhr = Label.new()
	_uhr.theme_type_variation = "CaptionLabel"
	_uhr.text = Time.get_time_string_from_system().substr(0, 5)
	zeile.add_child(_uhr)
	var luecke := Control.new()
	luecke.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(luecke)
	_status_icons.clear()
	zeile.add_child(_icon("res://assets/ui/icons/coin.svg"))
	_muenzen = Label.new()
	_muenzen.theme_type_variation = "CaptionLabel"
	zeile.add_child(_muenzen)
	zeile.add_child(_icon("res://assets/ui/icons/energy.svg"))
	_akku = ProgressBar.new()
	_akku.theme_type_variation = "StatEnergy"
	_akku.show_percentage = false
	_akku.max_value = 100.0
	_akku.custom_minimum_size = Vector2(52.0, 12.0)
	_akku.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(_akku)
	_aktualisiere_status()
	return zeile


func _baue_home_balken() -> Control:
	var btn := SquishButton.new()
	btn.name = "HomeBalken"
	btn.theme_type_variation = "GhostButton"
	btn.text = I18nService.t("phone.zurueck")
	btn.focus_mode = Control.FOCUS_NONE
	# W20/P3 (Befund B6 „Zurück als 884-px-Vollbreite-Balken"): zentrierte
	# Pill in natürlicher Breite statt Balken über die ganze Gerätekarte.
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(180.0 * float(_m.get("f", 1.0)), 0.0)
	# FB3-Altbefund (40,2 pt): der Balken hebt sich auf den Touch-Floor.
	ScreenShell.touch_target(btn, _m)
	# W16 F12: der meistgenutzte Knopf der Shell — Zurück klingt als ui_back.
	btn.pressed.connect(
		func() -> void:
			AudioDirector.try_play(btn, "ui_back")
			zurueck()
	)
	_home = btn
	return btn


func _baue_kachel(app: Dictionary, kachel_breite: float) -> Control:
	var f: float = _m.get("f", 1.0)
	var app_id := str(app["id"])
	var kachel := VBoxContainer.new()
	kachel.name = "Kachel%s" % app_id.capitalize()
	kachel.add_theme_constant_override("separation", AcTokens.px(AcTokens.SPACE_XS, f))
	kachel.custom_minimum_size = Vector2(kachel_breite, 0.0)
	var btn := SquishButton.new()
	btn.theme_type_variation = "HudIconButton"
	var hoehe := KACHEL_HOEHE_QUER if PhoneShell.ist_querformat(_m) else KACHEL_HOEHE
	btn.custom_minimum_size = Vector2(minf(hoehe * f, kachel_breite), hoehe * f)
	ScreenShell.touch_target(btn, _m)
	btn.expand_icon = false
	btn.focus_mode = Control.FOCUS_NONE
	# G7/P52: der Theme-Deckel (44 px) hielt die Icons auf iPhone-Kacheln
	# briefmarkenklein — er skaliert jetzt ×f mit der Kachel.
	btn.add_theme_constant_override("icon_max_width", AcTokens.px(44.0, f))
	btn.tooltip_text = I18nService.t(str(app["text_key"]))
	var pfad := PhoneApps.icon_pfad(app_id)
	if ResourceLoader.exists(pfad):
		btn.icon = load(pfad)
	if not bool(app["offen"]):
		# G7/P52: NUR blasser machen (self_modulate-Alpha) statt dunkel zu
		# multiplizieren — das INK_FAINT-Modulate machte die gesperrte
		# Kamera zum „dunklen Blob“ (User-Screenshot). Das Schloss-Badge
		# erklärt den Zustand, ohne das Icon zu verstecken.
		btn.self_modulate = Color(1.0, 1.0, 1.0, GESPERRT_ALPHA)
		btn.add_child(_schloss_badge(f))
	if app_id == Fahrdienst.TAXI and Fahrdienst.ist_rettungsweg(gs):
		btn.modulate = AcTokens.GOLD
	btn.pressed.connect(func() -> void: oeffne_app(app_id))
	# W13C INSTANT: Ungelesen-Badge am App-Icon (nur InstantGooby, nur > 0).
	var badge := InstantGoobyApp.unread_badge(app_id)
	if badge != null:
		btn.add_child(badge)
	kachel.add_child(btn)
	var name_label := Label.new()
	name_label.theme_type_variation = "CaptionLabel"
	name_label.text = I18nService.t(str(app["name_key"]))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(kachel_breite, 0.0)
	name_label.size = Vector2(kachel_breite, 0.0)
	kachel.add_child(name_label)
	return kachel


## Schloss-Badge einer gesperrten App (oben rechts auf dem Kachel-Knopf).
func _schloss_badge(f: float) -> TextureRect:
	var badge := TextureRect.new()
	badge.name = "SchlossBadge"
	if ResourceLoader.exists(SCHLOSS_ICON):
		badge.texture = load(SCHLOSS_ICON)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.self_modulate = AcTokens.INK_SOFT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -AcTokens.px(24.0, f)
	badge.offset_top = AcTokens.px(AcTokens.SPACE_XS, f)
	badge.offset_right = -AcTokens.px(AcTokens.SPACE_XS, f)
	badge.offset_bottom = AcTokens.px(24.0, f)
	return badge


## App-Inhalt bauen — EINE Stelle, an der Id auf UI trifft.
func _baue_app(app_id: String) -> Control:
	# W13C INSTANT: Variable statt 7. return (gdlint max-returns).
	var inhalt: Control = null
	match app_id:
		Fahrdienst.TAXI, Fahrdienst.GUBER:
			var fahrt := FahrdienstApp.new()
			fahrt.gs = gs
			fahrt.dienst = app_id
			fahrt.eingestiegen.connect(func(_d: String) -> void: schliesse())
			return fahrt
		"gooberando":
			var essen := GooberandoApp.new()
			essen.gs = gs
			return essen
		"kamera":
			var kamera := PhoneKameraApp.new()
			kamera.gs = gs
			kamera.fotomodus_gewuenscht.connect(starte_fotomodus)
			return kamera
		"freunde":
			# G5/P34 (P18-Request): echtes Telefon-Layout statt eingebettetem
			# Vollbild-Screen — Vollbild-Sozialweg ist SocialScreen
			# (der alte FriendsScreen wurde in W22/Tech entfernt).
			return PhoneFriendsApp.new()
		"goobypal":
			return PhoneSocialApps.goobypal(gs, _on_pal_freund)
		InstantGoobyApp.APP_ID:
			var feed := InstantGoobyApp.new()
			feed.gs = gs
			inhalt = feed
	return inhalt


## --------------------------------------------------------------- Actions


func _on_pal_freund(freund: Dictionary) -> void:
	_leere_inhalt()
	var sheet := PhoneSocialApps.pal_sheet(self, freund)
	if sheet == null:
		return
	if sheet is GoobyPalSheet:
		(sheet as GoobyPalSheet).closed.connect(func() -> void: oeffne_app("goobypal"))
		(sheet as GoobyPalSheet).toast_requested.connect(_zeige_toast)
	_inhalt.add_child(sheet)
	ScreenShell.scale_fonts(_geraet, _m.get("f", 1.0))


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		schliesse()


## W18/4 B2 „Maus-Wisch scrollt das Telefon nicht“ — F6-Arcade-Muster
## (s. ArcadeScreen._on_scroll_gui_input, W18 B5): (1) der eingebaute
## ScrollContainer-Pan startet nur bei DisplayServer.is_touchscreen_
## available() — unter Desktop/xvfb nie; (2) App-Knöpfe auf STOP brechen
## das Bubbling ab (Apps stellen ihre Knöpfe auf PASS, s. GooberandoApp).
## Deshalb dieser eigene Pan im gui_input-SIGNAL des Scrolls (feuert VOR
## der eingebauten Verarbeitung; accept_event() verhindert Doppel-Pan auf
## echten Touch-Geräten). Ab scroll_deadzone gehört die Geste dem Scroll
## (NOTIFICATION_SCROLL_BEGIN löst den Press-Versuch des Knopfs), Taps
## darunter feuern normal weiter. Der Pan greift NUR, wenn der Inhalt
## wirklich überläuft — sonst blieben die Geräte-Zurück-Gesten (Wisch nach
## unten übers Grid) auf nicht scrollenden Ansichten ohne Funktion.
func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pan_druck = true
			_pan_aktiv = false
			_pan_summe = 0.0
			_pan_start = float(_scroll.scroll_vertical)
		else:
			if _pan_aktiv:
				_scroll.propagate_notification(NOTIFICATION_SCROLL_END)
				_scroll.accept_event()
			_pan_druck = false
			_pan_aktiv = false
		return
	if not (event is InputEventMouseMotion) or not _pan_druck:
		return
	var mm := event as InputEventMouseMotion
	if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	_pan_summe += mm.relative.y
	var kann := _inhalt != null and _inhalt.get_combined_minimum_size().y > _scroll.size.y + 1.0
	if not _pan_aktiv and kann and absf(_pan_summe) > float(_scroll.scroll_deadzone):
		_pan_aktiv = true
		_scroll.propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		# Weicher Einstieg: ab der Deadzone zählt nur der weitere Weg.
		_pan_start = float(_scroll.scroll_vertical)
		_pan_summe = mm.relative.y
	if _pan_aktiv:
		_scroll.scroll_vertical = int(roundf(_pan_start - _pan_summe))
		_scroll.accept_event()


## Zurück-Gesten (G7/P52): Wisch nach UNTEN = zurück (vom Grid: schließen),
## Wisch VON LINKS nach rechts IN einer App = zurück aufs Grid (wie am
## echten Telefon). Maus-Drags zählen auch; Schwellwerte skalieren ×f —
## 90 Design-px wären auf dem iPhone sonst ein ~28-pt-Mini-Wisch (G1 §3).
func _on_geraet_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_geste_schritt(drag.position, drag.relative)
		return
	if event is InputEventMouseMotion:
		var maus: InputEventMouseMotion = event
		if maus.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_geste_schritt(maus.position, maus.relative)
		else:
			_geste_reset()
		return
	_geste_reset()


## Einen Wisch-Schritt verbuchen: beim ERSTEN Schritt entscheidet die
## Startposition, ob es ein Links-Rand-Wisch ist; danach zählen die Wege.
func _geste_schritt(pos: Vector2, rel: Vector2) -> void:
	if not _geste_aktiv:
		_geste_aktiv = true
		_geste_von_links = (pos.x - rel.x) <= geste_rand()
		_geste_x = 0.0
		_geste_y = 0.0
	_geste_x += rel.x
	_geste_y += rel.y
	var von_links_zurueck := (
		_geste_von_links and not aktive_app.is_empty() and _geste_x > geste_schwelle()
	)
	if von_links_zurueck or _geste_y > geste_schwelle():
		_geste_reset()
		# Gesten-Zurück klingt wie der HomeBalken (W16-Grammatik: ui_back).
		AudioDirector.try_play(self, "ui_back")
		zurueck()


func _geste_reset() -> void:
	_geste_aktiv = false
	_geste_von_links = false
	_geste_x = 0.0
	_geste_y = 0.0


func _aktualisiere_status() -> void:
	if gs == null:
		return
	_muenzen.text = str(int(gs.get_value("economy.coins", 0)))
	_akku.value = float(gs.get_value("gooby.stats.energy", 100.0))


func _leere_inhalt() -> void:
	for kind in _inhalt.get_children():
		_inhalt.remove_child(kind)
		kind.queue_free()
	# W18/4 B2: gepinnte CTAs der alten Ansicht räumen (kein Geister-Fuß).
	if _fuss != null:
		for kind in _fuss.get_children():
			_fuss.remove_child(kind)
			kind.queue_free()
		_fuss.visible = false
	_aktualisiere_status()


func _icon(pfad: String) -> TextureRect:
	var rect := TextureRect.new()
	if ResourceLoader.exists(pfad):
		rect.texture = load(pfad)
	rect.custom_minimum_size = Vector2(18.0, 18.0) * float(_m.get("f", 1.0))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.self_modulate = AcTokens.INK_SOFT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_icons.append(rect)
	return rect


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
