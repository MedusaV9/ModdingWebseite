class_name WardrobeScreen
extends Control
## Garderobe (CONTENT-A): Kategorie-Tabs, Item-Grid mit gebackenen 3D-Vorschauen
## und links ein LEBENDER Gooby, der sofort trägt, was man antippt — drehbar
## per Ziehen.
##
## AC-Look wie überall: `AcWallpaper` (Drift-Shader) als Hintergrund, alle
## Farben aus `AcTokens`/dem Projekt-Theme, keine hartkodierten Hex-Werte im
## Layout. Die Vorschau bekommt Glow über ihr eigenes `WorldEnvironment` —
## sie rendert in einem SubViewport, das Postprocessing stört den Rest der UI
## also nicht.
##
## Kauf/Besitz läuft komplett über `CosmeticsState` (pur, getestet) auf dem
## bestehenden `cosmetics`-Slice; Münzen über `Economy`. Fellfarben sind laut
## User-Regel NUR im Shop kaufbar — hier ist der Shop, also geht es hier.
##
## HUD-Verdrahtung (Muster ArcadeScreen/AlbumScreen): der Home-Besitzer
## verbindet `hud.action_pressed.connect(WardrobeScreen.handle_hud_action)`.
## Request an den Orchestrator: /tmp/gooby-godot/handoffs/CONTENTA-hud-request.md

signal ready_for_reveal
## Feuert nach jedem Anlegen/Ablegen/Kauf (Tests, Achievements).
signal garderobe_geaendert(kategorie: String, id: String)

const ROUTE_WARDROBE := &"wardrobe"
const ROUTES := {ROUTE_WARDROBE: "res://scripts/cosmetics/wardrobe_screen.tscn"}
const KARTE := Vector2(184.0, 214.0)
## Inhaltsspalte W16: eigene Grid-Basis (Bühne + Regal brauchen mehr als die
## 660er-Standardspalte — Entwurf ui-architektur §6.2 / Scout ui-spalte2 §2).
const SPALTE_BASIS := 920.0
## Gesperrte Karten bleiben sichtbar, aber ausgegraut.
const GESPERRT_TOENUNG := Color(0.72, 0.7, 0.7, 1.0)
## W20/P3: Karten-Wachstum beim Spalten-Füllen deckeln (sonst würden 2
## Rest-Spalten im Leitformat zu Riesen-Kacheln aufgeblasen).
const KARTE_WACHSTUM_MAX := 1.3
## Empfindlichkeit des Dreh-Ziehens (rad pro Pixel).
const DREH_PRO_PIXEL := 0.011
## G7: Scrollbar-Abstand zum Spalten-/Display-Rand (Design-px, × f).
const GRID_RAND := 10.0

## Tests/Screenshots: eigener Spielstand statt /root/GameState.
var game_state_override: Object = null
## Tests: Zurück-Knopf soll nicht wirklich navigieren.
var auto_navigate := true

var _gs: Object = null
var _tab := "hut"
var _grid: GridContainer
var _tab_box: HBoxContainer
var _muenz_label: Label
var _titel: Label
var _hinweis: Label
var _preview: CosmeticPreview
var _rig: GoobyRig
var _attach: CosmeticAttach
var _buehne: Node3D
var _viewport: SubViewport
var _dreht := false
var _karten: Dictionary = {}  # id -> TextureRect der Vorschau
## id -> {karte, rahmen, status} für gezielte In-place-Updates (kein Rebuild).
var _karten_ui: Dictionary = {}
## FB3: Metrik-Pass (Safe-Area, Touch-Floor, UiScale) bei jedem Resize.
var _rows: VBoxContainer
var _back: Button
var _split: BoxContainer
var _saeule_links: VBoxContainer
var _buehne_container: SubViewportContainer
var _tab_scroll: ScrollContainer
var _grid_scroll: ScrollContainer
## G7: Fade-Kanten-Affordance (Grid unten, Chips seitlich) + Boden-Polster.
var _grid_fade: ScrollFade
var _grid_polster: MarginContainer
var _tab_fade: ScrollFade
var _tile := KARTE


## Garderoben-Route am SceneRouter anmelden (idempotent).
static func register_routes() -> void:
	var router := _router()
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


## EIN Verdrahtungspunkt für den HUD-Garderoben-Button.
static func handle_hud_action(action: StringName) -> bool:
	if action != &"wardrobe":
		return false
	register_routes()
	var router := _router()
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE_WARDROBE, {})
	return true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_gs = (
		game_state_override if game_state_override != null else get_node_or_null("/root/GameState")
	)
	_preview = CosmeticPreview.new()
	add_child(_preview)
	_preview.fertig.connect(_on_vorschau_fertig)
	_build_ui()
	# ERST wenn der ganze Baum hängt: GoobyRig lädt sein GLB in `_ready`, vorher
	# gibt es kein Skelett, an das sich `CosmeticAttach` hängen könnte.
	_attach = CosmeticAttach.fuer_rig(_rig)
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	tab_waehlen(_tab)
	_rig_aktualisieren()
	ready_for_reveal.emit()


## FB3/W16: Safe-Area + zentrale Skalierung + Touch-Floor + Inhaltsspalte
## (zentriert + breiten-gedeckelt, Galerie-Muster) — hochkant stapelt der
## Split (Bühne oben, Grid unten), quer bleibt es die Zwei-Spalten-Teilung.
func _apply_metrics() -> void:
	if _rows == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var canvas: Vector2 = m["canvas"]
	# Inhaltsspalte W16: Hintergrund bleibt vollflächig, Inhalt rückt mittig.
	ScreenShell.content_frame(_rows, m, SPALTE_BASIS)
	var spalte := ScreenShell.content_width(m, SPALTE_BASIS)
	if _back != null:
		ScreenShell.touch_target(_back, m)
	# Tabs: Floor auf BEIDEN Achsen (kurze Texte wie „Fell“ unterschreiten
	# sonst die Breite); die Leiste selbst reserviert ihre Zeilenhöhe.
	for chip: Node in _tab_box.get_children():
		if chip is Control:
			(chip as Control).custom_minimum_size = Vector2(m["floor_px"], m["floor_px"])
	if _tab_scroll != null:
		_tab_scroll.custom_minimum_size = Vector2(0.0, m["floor_px"] + 4.0)
	# G7: Scrollbar-Abstand + Fade-Kanten skalieren; das Boden-Polster hält
	# die letzte Reihe am Scroll-Ende frei über der Fade-Kante.
	var rand := roundi(GRID_RAND * f)
	if _grid_fade != null:
		_grid_fade.rand_inset(rand)
		_grid_fade.kanten_hoehe(ScrollFade.KANTE * f)
		_grid_polster.add_theme_constant_override("margin_bottom", roundi(ScrollFade.KANTE * f))
	# Hochformat-Stapel (G3): Bühne oben mit festem Höhenbudget (~38 % der
	# Safe-Höhe), Grid darunter in voller Spaltenbreite.
	var hochkant := canvas.y > canvas.x
	_split.vertical = hochkant
	var insets: Dictionary = m["insets"]
	var avail := spalte - 12.0 - float(rand)
	if hochkant:
		var safe_h := canvas.y - float(insets["top"]) - float(insets["bottom"])
		var buehne_h := clampf(safe_h * 0.38, 320.0, maxf(safe_h - 320.0, 320.0))
		_saeule_links.custom_minimum_size = Vector2(0.0, buehne_h)
		# Die feste Stapelhöhe regiert — das 300×380-Viewport-Minimum würde
		# sie auf kleinen Hochkant-Canvases sprengen.
		_buehne_container.custom_minimum_size = Vector2.ZERO
	else:
		_saeule_links.custom_minimum_size = Vector2(minf(AcTokens.px(328.0, f), spalte * 0.32), 0.0)
		# Bühnen-Minimum NUR in der Höhe: die Breite bekommt der Container
		# von der Säule (VBox füllt, stretch=true skaliert den SubViewport
		# mit). Ein fixes 300er-Breiten-Minimum drückte die Säule samt
		# AcCard-Rändern sonst auf 336 px und sprengte die Inhaltsspalte —
		# rows klemmt an der Kinder-Mindestbreite (936 statt 920, Mitte 648
		# statt 640 auf 1280×720; W16-Befund der G3-Integration).
		_buehne_container.custom_minimum_size = Vector2(0.0, 380.0)
		avail = spalte - _saeule_links.custom_minimum_size.x - 16.0 - 12.0 - float(rand)
	# Karten: Wunschgröße × f, Spaltenzahl aus der SPALTEN-Restbreite (statt
	# der vollen Canvas-Breite); hochkant mindestens 3 Spalten.
	# W20/P3 (Befund B9/D3 „tote Fläche rechts“): RUNDEN statt abschneiden
	# und die Kacheln anschließend auf die Restbreite FÜLLEN — Geräte-
	# Metriken ließen sonst ~20-30 % Leerraum zwischen Grid und Scrollbar.
	_tile = KARTE * f
	var cols := clampi(roundi((avail + 12.0) / (_tile.x + 12.0)), 1, 5)
	if hochkant and cols < 3:
		cols = 3
	var breite := clampf((avail + 12.0) / float(cols) - 12.0, 64.0, _tile.x * KARTE_WACHSTUM_MAX)
	_tile = Vector2(breite, breite * KARTE.y / KARTE.x)
	_grid.columns = cols
	for karte in _grid.get_children():
		if karte is Control:
			(karte as Control).custom_minimum_size = _tile
	ScreenShell.scale_fonts(self, f)


## Kategorie-Tab anwählen (auch für Screenshots/Tests).
func tab_waehlen(kategorie: String) -> void:
	if not CosmeticsCatalog.KATEGORIEN.has(kategorie):
		return
	_tab = kategorie
	if _titel != null:
		_titel.text = I18nService.t("wardrobe.kat.%s" % kategorie)
	if _hinweis != null:
		_hinweis.text = (
			I18nService.t("wardrobe.fell_hinweis") if kategorie == CosmeticsCatalog.FELL else ""
		)
		_hinweis.visible = not _hinweis.text.is_empty()
	for chip: Node in _tab_box.get_children():
		var aktiv := chip.name == StringName("Tab_%s" % kategorie)
		(chip as Button).button_pressed = aktiv
		# G7: aktiver Chip DEUTLICH (Leaf-Füllung wie im Gestalten-Screen)
		# und in den sichtbaren Bereich der swipebaren Leiste holen.
		(chip as Button).theme_type_variation = &"ChipLeaf" if aktiv else &"AcChip"
		if aktiv and _tab_scroll != null and is_inside_tree():
			_tab_scroll.ensure_control_visible(chip as Control)
	_grid_neu_bauen()


## Ein Item antippen: besitzt man es, wird an-/abgelegt, sonst gekauft und
## direkt angezogen. Rückgabe wie `CosmeticsState` ({ok, grund, ...}).
func item_tippen(id: String) -> Dictionary:
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty() or _gs == null:
		return {"ok": false, "grund": "unbekannt"}
	var kategorie := str(def["kategorie"])
	var vorher := CosmeticsState.equipped(_slice(), kategorie)
	var ergebnis: Dictionary = CosmeticsState.apply_to_state(
		_gs,
		func(slice: Dictionary, econ: Dictionary) -> Variant:
			if CosmeticsState.is_owned(slice, id):
				return CosmeticsState.toggle(slice, id)
			var kauf := CosmeticsState.buy(slice, econ, id, _level())
			if bool(kauf["ok"]):
				CosmeticsState.equip(slice, id)
			return kauf
	)
	_muenzen_aktualisieren()
	# Scroll-Sprung-Fix (G3): nur die betroffenen Karten in-place auffrischen
	# — der komplette Grid-Rebuild warf die Scroll-Position auf den Anfang.
	_karte_aktualisieren(id)
	if not vorher.is_empty() and vorher != id:
		_karte_aktualisieren(vorher)
	_rig_aktualisieren()
	garderobe_geaendert.emit(kategorie, id)
	return ergebnis


## Aktuell angelegte Ids je Kategorie (Tests).
func getragen() -> Dictionary:
	return CosmeticsState.equipped_map(_slice())


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	# W21/P3 (d): Garderoben-Stimmung (Rosa-Wash + Wardrobe-Kacheln) statt
	# manuellem Dots-Pattern — Mood-Kontexte sind die EINE Quelle.
	var wallpaper := AcWallpaper.for_context("garderobe")
	add_child(wallpaper)

	_rows = VBoxContainer.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows.add_theme_constant_override("separation", 12)
	add_child(_rows)
	_rows.add_child(_build_header())

	# BoxContainer statt fester HBox: `_apply_metrics` schaltet die Achse
	# (quer = nebeneinander, hochkant = Bühne oben / Grid unten).
	_split = BoxContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_theme_constant_override("separation", 16)
	_rows.add_child(_split)
	_split.add_child(_build_buehne())
	_split.add_child(_build_regal())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_back = SquishButton.new()
	_back.theme_type_variation = &"BtnGhost"
	_back.text = I18nService.t("wardrobe.zurueck")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_on_back_pressed)
	header.add_child(_back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("wardrobe.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsule"
	_muenz_label = Label.new()
	_muenz_label.theme_type_variation = &"SoftLabel"
	chip.add_child(_muenz_label)
	header.add_child(chip)
	_muenzen_aktualisieren()
	return header


## Linke Spalte: der lebende Gooby im eigenen 3D-Viewport (mit Glow).
func _build_buehne() -> Control:
	_saeule_links = VBoxContainer.new()
	_saeule_links.custom_minimum_size = Vector2(330.0, 0.0)
	_saeule_links.add_theme_constant_override("separation", 8)
	var saeule := _saeule_links

	var rahmen := PanelContainer.new()
	rahmen.theme_type_variation = &"AcCard"
	rahmen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saeule.add_child(rahmen)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(300.0, 380.0)
	container.gui_input.connect(_on_buehne_input)
	rahmen.add_child(container)
	_buehne_container = container
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	_buehne = Node3D.new()
	_buehne.name = "Drehteller"
	_viewport.add_child(_buehne)
	_rig = GoobyRig.new()
	_rig.name = "Gooby"
	_buehne.add_child(_rig)

	var kamera := Camera3D.new()
	kamera.fov = 38.0
	_viewport.add_child(kamera)
	kamera.look_at_from_position(Vector3(0.0, 0.66, 2.1), Vector3(0.0, 0.5, 0.0), Vector3.UP)
	kamera.current = true
	var sonne := DirectionalLight3D.new()
	sonne.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sonne.light_energy = 1.15
	_viewport.add_child(sonne)
	var fuell := DirectionalLight3D.new()
	fuell.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fuell.light_energy = 0.5
	_viewport.add_child(fuell)
	_viewport.add_child(_glow_environment())

	var tipp := Label.new()
	tipp.theme_type_variation = &"SoftLabel"
	tipp.text = I18nService.t("wardrobe.drehen")
	tipp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saeule.add_child(tipp)
	return saeule


## Weicher Glow auf der Vorschau — das ist das einzige Postprocessing im
## Screen und lebt bewusst im SubViewport (die UI selbst bleibt unberührt).
func _glow_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AcTokens.PAPER
	env.ambient_light_energy = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# bloom 0 + Schwelle über Weiß: sonst blüht Goobys heller Bauch zu einem
	# einzigen Lichtklumpen auf (in gl_compatibility besonders heftig).
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	var node := WorldEnvironment.new()
	node.environment = env
	return node


## Rechte Spalte: Tabs + Grid.
func _build_regal() -> Control:
	var saeule := VBoxContainer.new()
	saeule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saeule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saeule.add_theme_constant_override("separation", 8)

	# FB3: Tab-Leiste scrollt horizontal (Touch-Pan = swipebar) — im
	# Hochformat liefen die letzten Tabs sonst rechts aus dem Canvas.
	# G7: Seiten-Fades zeigen an, WENN die Chips überlaufen.
	var tab_scroll := ScrollContainer.new()
	tab_scroll.name = "TabScroll"
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_fade = ScrollFade.um(tab_scroll)
	_tab_fade.name = "TabFade"
	saeule.add_child(_tab_fade)
	# W20/P3 (Befund F2): Maus-/Finger-Drags über den Chips pannen die
	# Leiste (Chips selbst stehen auf MOUSE_FILTER_PASS).
	WischPan.an(tab_scroll)
	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 8)
	for kategorie in CosmeticsCatalog.KATEGORIEN:
		_tab_box.add_child(_build_tab(kategorie))
	tab_scroll.add_child(_tab_box)
	_tab_scroll = tab_scroll

	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 10)
	_titel = Label.new()
	_titel.theme_type_variation = &"HeadlineLabel"
	kopf.add_child(_titel)
	_hinweis = Label.new()
	_hinweis.theme_type_variation = &"SoftLabel"
	_hinweis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(_hinweis)
	saeule.add_child(kopf)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# G7: Fade-Kante = Scroll-Einladung (die angeschnittene zweite Reihe
	# wirkte im User-Screenshot wie ein Fehler); rand_inset löst zugleich
	# die am Display-Rand klebende Scrollbar (_apply_metrics skaliert).
	_grid_fade = ScrollFade.um(scroll)
	_grid_fade.name = "GridFade"
	saeule.add_child(_grid_fade)
	_grid_scroll = scroll
	# W20/P3: Wisch-Pan auch fürs Grid (Karten stehen auf PASS).
	WischPan.an(scroll)
	# Boden-Polster: am Scroll-Ende steht die letzte Reihe frei über der
	# Fade-Kante statt hart am Rand (Höhe zieht _apply_metrics nach).
	_grid_polster = MarginContainer.new()
	_grid_polster.name = "GridPolster"
	_grid_polster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_polster.add_theme_constant_override("margin_bottom", int(ScrollFade.KANTE))
	scroll.add_child(_grid_polster)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid_polster.add_child(_grid)
	return saeule


func _build_tab(kategorie: String) -> Control:
	var chip := SquishButton.new()
	chip.name = "Tab_%s" % kategorie
	chip.theme_type_variation = &"AcChip"
	chip.toggle_mode = true
	chip.text = I18nService.t("wardrobe.kat.%s" % kategorie)
	chip.focus_mode = Control.FOCUS_NONE
	# PASS statt Button-Default STOP: Drags erreichen den WischPan der
	# Leiste, der Tap bleibt beim Chip (W18-B5-Muster).
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.pressed.connect(_on_tab_gedrueckt.bind(kategorie))
	return chip


func _grid_neu_bauen() -> void:
	if _grid == null:
		return
	_karten.clear()
	_karten_ui.clear()
	for child in _grid.get_children():
		child.queue_free()
		_grid.remove_child(child)
	var slice := _slice()
	var angelegt := CosmeticsState.equipped(slice, _tab)
	var karten: Array = []
	for def: Dictionary in CosmeticsCatalog.by_kategorie(_tab):
		var karte := _build_karte(def, slice, angelegt)
		_grid.add_child(karte)
		karten.append(karte)
	if is_inside_tree():
		ScreenShell.scale_fonts(_grid, UiScale.for_viewport(get_viewport()))
	# FB3-Polish: Kacheln blenden gestaffelt ein (Web-Stagger).
	UiMotion.stagger_in(karten, 0.02)


func _build_karte(def: Dictionary, slice: Dictionary, angelegt: String) -> Control:
	var id: String = def["id"]
	var besitzt := CosmeticsState.is_owned(slice, id)
	var gesperrt := not besitzt and _level() < int(def["min_level"])
	var karte := SquishButton.new()
	karte.name = "Item_%s" % id
	# W20/P3 (Befund A10): `AcCard` ist eine PanelContainer-Variation — auf
	# einem Button griff der Default-Pill-Stil und die Namens-/Preis-Zeilen
	# hingen als Kreis-Ausbuchtung in die Kartenreihe darunter.
	karte.theme_type_variation = &"AcCardButton"
	karte.custom_minimum_size = _tile
	karte.focus_mode = Control.FOCUS_NONE
	karte.mouse_filter = Control.MOUSE_FILTER_PASS
	karte.tooltip_text = CosmeticsCatalog.desc_of(def)
	karte.disabled = gesperrt
	# Gesperrt heißt SICHTBAR, aber grau — man soll sehen, worauf man spart.
	karte.modulate = GESPERRT_TOENUNG if gesperrt else Color.WHITE
	karte.pressed.connect(_on_karte_gedrueckt.bind(id))
	_karten_ui[id] = {"karte": karte}

	var inhalt := VBoxContainer.new()
	inhalt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inhalt.offset_left = 10.0
	inhalt.offset_right = -10.0
	inhalt.offset_top = 10.0
	inhalt.offset_bottom = -8.0
	inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inhalt.add_theme_constant_override("separation", 4)
	karte.add_child(inhalt)
	inhalt.add_child(_build_bild(def, id == angelegt))
	inhalt.add_child(_build_band(def, besitzt, id == angelegt, gesperrt))
	return karte


## Rahmen-Stil des Vorschaubilds: Angelegt = Leaf-Border, sonst neutrale
## Haarlinie. W20/P3 (Befund E5): die Rarity-Farbmischung (grün/gold/pink
## nebeneinander) hatte keine erkennbare Semantik — EIN Signal (angelegt)
## bleibt, der Rest folgt den Theme-Tokens.
func _bild_stil(_def: Dictionary, angelegt: bool) -> StyleBoxFlat:
	var stil := StyleBoxFlat.new()
	stil.bg_color = AcTokens.PAPER_SHADE
	stil.set_corner_radius_all(AcTokens.RADIUS_ROW)
	stil.border_color = AcTokens.LEAF if angelegt else AcTokens.OUTLINE_SOFT
	stil.set_border_width_all(4 if angelegt else 2)
	return stil


func _build_bild(def: Dictionary, angelegt: bool) -> Control:
	var rahmen := PanelContainer.new()
	rahmen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rahmen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rahmen.add_theme_stylebox_override("panel", _bild_stil(def, angelegt))
	var bild := TextureRect.new()
	bild.name = "Vorschau"
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bild.custom_minimum_size = Vector2(0.0, 108.0 * _tile.x / KARTE.x)
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bild.texture = _preview.hole(str(def["id"]))
	rahmen.add_child(bild)
	_karten[str(def["id"])] = bild
	if _karten_ui.get(str(def["id"])) is Dictionary:
		_karten_ui[str(def["id"])]["rahmen"] = rahmen
	return rahmen


func _status_text(def: Dictionary, besitzt: bool, angelegt: bool, gesperrt: bool) -> String:
	if gesperrt:
		return I18nService.t("wardrobe.level", {"n": int(def["min_level"])})
	if angelegt:
		return I18nService.t("wardrobe.angelegt")
	if besitzt:
		return I18nService.t("wardrobe.besessen")
	return I18nService.t("wardrobe.preis", {"n": int(def["preis"])})


func _build_band(def: Dictionary, besitzt: bool, angelegt: bool, gesperrt: bool) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	var name_label := Label.new()
	name_label.text = CosmeticsCatalog.name_of(def)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var status := Label.new()
	status.theme_type_variation = &"SoftLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.clip_text = true
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.text = _status_text(def, besitzt, angelegt, gesperrt)
	box.add_child(status)
	if _karten_ui.get(str(def["id"])) is Dictionary:
		_karten_ui[str(def["id"])]["status"] = status
	return box


## Eine Karte in-place auffrischen (Sperre/Border/Status) — der komplette
## Grid-Rebuild beim Antippen warf die Scroll-Position auf den Anfang.
func _karte_aktualisieren(id: String) -> void:
	var eintrag: Variant = _karten_ui.get(id)
	var def := CosmeticsCatalog.by_id(id)
	if not (eintrag is Dictionary) or def.is_empty():
		return
	var slice := _slice()
	var besitzt := CosmeticsState.is_owned(slice, id)
	var angelegt := CosmeticsState.equipped(slice, str(def["kategorie"])) == id
	var gesperrt := not besitzt and _level() < int(def["min_level"])
	var karte: Variant = (eintrag as Dictionary).get("karte")
	if karte is Button:
		(karte as Button).disabled = gesperrt
		(karte as Button).modulate = GESPERRT_TOENUNG if gesperrt else Color.WHITE
	var rahmen: Variant = (eintrag as Dictionary).get("rahmen")
	if rahmen is PanelContainer:
		(rahmen as PanelContainer).add_theme_stylebox_override("panel", _bild_stil(def, angelegt))
	var status: Variant = (eintrag as Dictionary).get("status")
	if status is Label:
		(status as Label).text = _status_text(def, besitzt, angelegt, gesperrt)


# ── Reaktionen ───────────────────────────────────────────────────────────────


## Audio-Grammatik: Outcome schlägt Press — ob Kauf, An-/Ablegen oder Fehler
## steht erst nach der Prüfung fest, also klingt das ERGEBNIS (genau 1 Id).
## G7-Feedback obendrauf: Kauf = Gold-Sparkle auf der Karte, Fehler
## („zu teuer“) = sanftes Kopfschütteln — beides Reduced-Motion-gated.
func _on_karte_gedrueckt(id: String) -> void:
	var ergebnis := item_tippen(id)
	var karte := _karte_von(id)
	if bool(ergebnis.get("gekauft", false)):
		AudioDirector.try_play(self, "ui_buy")
		Haptics.success(self)
		if karte != null:
			UiMotion.sparkle(karte)
	elif bool(ergebnis.get("ok", false)) or str(ergebnis.get("grund", "")) == "unveraendert":
		AudioDirector.try_play(self, "ui_click")
	else:
		AudioDirector.try_play(self, "ui_error")
		Haptics.warn(self)
		_kopfschuetteln(karte)


func _karte_von(id: String) -> Control:
	var eintrag: Variant = _karten_ui.get(id)
	if eintrag is Dictionary and (eintrag as Dictionary).get("karte") is Control:
		return (eintrag as Dictionary)["karte"]
	return null


## Sanftes Nein-Schütteln der Karte (zu teuer). RM = ohne Bewegung; ein
## laufendes Schütteln stapelt nicht (die Ruhelage bliebe sonst schief).
func _kopfschuetteln(karte: Control) -> void:
	if karte == null or not karte.is_inside_tree() or UiMotion.reduced(karte):
		return
	if karte.has_meta(&"g7_schuettel"):
		var alt: Variant = karte.get_meta(&"g7_schuettel")
		if alt is Tween and (alt as Tween).is_valid():
			return
	var rast := karte.position.x
	var tween := karte.create_tween()
	karte.set_meta(&"g7_schuettel", tween)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for versatz: float in [-7.0, 6.0, -4.0, 0.0]:
		tween.tween_property(karte, "position:x", rast + versatz, 0.055)


func _on_tab_gedrueckt(kategorie: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	tab_waehlen(kategorie)


func _on_vorschau_fertig(id: String, textur: Texture2D) -> void:
	var bild: Variant = _karten.get(id)
	if bild is TextureRect and is_instance_valid(bild):
		(bild as TextureRect).texture = textur


## Ziehen dreht den Gooby (Maus wie Finger — dieselbe Geste).
func _on_buehne_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var taste := event as InputEventMouseButton
		if taste.button_index == MOUSE_BUTTON_LEFT:
			_dreht = taste.pressed
	elif event is InputEventMouseMotion and _dreht and _buehne != null:
		_buehne.rotation.y -= (event as InputEventMouseMotion).relative.x * DREH_PRO_PIXEL
	elif event is InputEventScreenDrag and _buehne != null:
		_buehne.rotation.y -= (event as InputEventScreenDrag).relative.x * DREH_PRO_PIXEL


func _rig_aktualisieren() -> void:
	if _attach == null:
		return
	if _gs != null:
		_attach.apply_from_state(_gs)
	else:
		_attach.apply_equipped(CosmeticsState.equipped_map(_slice()))


func _muenzen_aktualisieren() -> void:
	if _muenz_label == null:
		return
	_muenz_label.text = I18nService.t("wardrobe.muenzen", {"n": _coins()})


func _slice() -> Dictionary:
	if _gs == null or not _gs.has_method("get_value"):
		return CosmeticsState.default_slice()
	var slice: Variant = _gs.get_value("cosmetics", null)
	if not (slice is Dictionary):
		return CosmeticsState.default_slice()
	return CosmeticsState.normalize(slice)


func _coins() -> int:
	if _gs == null or not _gs.has_method("get_value"):
		return 0
	return int(_gs.get_value("economy.coins", 0))


func _level() -> int:
	if _gs == null or not _gs.has_method("get_value"):
		return 1
	return maxi(1, int(_gs.get_value("progression.level", 1)))


func _on_back_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	if not auto_navigate:
		return
	var router := _router()
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


static func _router() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
