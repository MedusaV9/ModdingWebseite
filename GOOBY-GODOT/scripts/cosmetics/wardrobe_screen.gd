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
const RARITY_FARBE := {
	"haeufig": AcTokens.WHITE,
	"selten": AcTokens.SKY_SOFT,
	"episch": AcTokens.GOLD,
	"legendaer": AcTokens.PINK,
}
## Empfindlichkeit des Dreh-Ziehens (rad pro Pixel).
const DREH_PRO_PIXEL := 0.011

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
	tab_waehlen(_tab)
	_rig_aktualisieren()
	ready_for_reveal.emit()


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
		(chip as Button).button_pressed = chip.name == StringName("Tab_%s" % kategorie)
	_grid_neu_bauen()


## Ein Item antippen: besitzt man es, wird an-/abgelegt, sonst gekauft und
## direkt angezogen. Rückgabe wie `CosmeticsState` ({ok, grund, ...}).
func item_tippen(id: String) -> Dictionary:
	var def := CosmeticsCatalog.by_id(id)
	if def.is_empty() or _gs == null:
		return {"ok": false, "grund": "unbekannt"}
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
	_grid_neu_bauen()
	_rig_aktualisieren()
	garderobe_geaendert.emit(str(def["kategorie"]), id)
	return ergebnis


## Aktuell angelegte Ids je Kategorie (Tests).
func getragen() -> Dictionary:
	return CosmeticsState.equipped_map(_slice())


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.pattern = "dots"
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 24.0
	rows.offset_right = -24.0
	rows.offset_top = 16.0
	rows.offset_bottom = -16.0
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)
	rows.add_child(_build_header())

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	rows.add_child(split)
	split.add_child(_build_buehne())
	split.add_child(_build_regal())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var back := SquishButton.new()
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("wardrobe.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
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
	var saeule := VBoxContainer.new()
	saeule.custom_minimum_size = Vector2(330.0, 0.0)
	saeule.add_theme_constant_override("separation", 8)

	var rahmen := PanelContainer.new()
	rahmen.theme_type_variation = &"AcCard"
	rahmen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saeule.add_child(rahmen)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(300.0, 380.0)
	container.gui_input.connect(_on_buehne_input)
	rahmen.add_child(container)
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

	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 8)
	for kategorie in CosmeticsCatalog.KATEGORIEN:
		_tab_box.add_child(_build_tab(kategorie))
	saeule.add_child(_tab_box)

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
	saeule.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	return saeule


func _build_tab(kategorie: String) -> Control:
	var chip := SquishButton.new()
	chip.name = "Tab_%s" % kategorie
	chip.theme_type_variation = &"AcChip"
	chip.toggle_mode = true
	chip.text = I18nService.t("wardrobe.kat.%s" % kategorie)
	chip.focus_mode = Control.FOCUS_NONE
	chip.pressed.connect(tab_waehlen.bind(kategorie))
	return chip


func _grid_neu_bauen() -> void:
	if _grid == null:
		return
	_karten.clear()
	for child in _grid.get_children():
		child.queue_free()
		_grid.remove_child(child)
	var slice := _slice()
	var angelegt := CosmeticsState.equipped(slice, _tab)
	for def: Dictionary in CosmeticsCatalog.by_kategorie(_tab):
		_grid.add_child(_build_karte(def, slice, angelegt))


func _build_karte(def: Dictionary, slice: Dictionary, angelegt: String) -> Control:
	var id: String = def["id"]
	var besitzt := CosmeticsState.is_owned(slice, id)
	var gesperrt := not besitzt and _level() < int(def["min_level"])
	var karte := SquishButton.new()
	karte.name = "Item_%s" % id
	karte.theme_type_variation = &"AcCard"
	karte.custom_minimum_size = KARTE
	karte.focus_mode = Control.FOCUS_NONE
	karte.tooltip_text = CosmeticsCatalog.desc_of(def)
	karte.disabled = gesperrt
	# Gesperrt heißt SICHTBAR, aber grau — man soll sehen, worauf man spart.
	karte.modulate = Color(0.72, 0.7, 0.7, 1.0) if gesperrt else Color.WHITE
	karte.pressed.connect(_on_karte_gedrueckt.bind(id))

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


func _build_bild(def: Dictionary, angelegt: bool) -> Control:
	var rahmen := PanelContainer.new()
	rahmen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rahmen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stil := StyleBoxFlat.new()
	stil.bg_color = AcTokens.PAPER_SHADE
	stil.set_corner_radius_all(AcTokens.RADIUS_ROW)
	stil.border_color = (
		AcTokens.LEAF if angelegt else RARITY_FARBE.get(str(def["rarity"]), AcTokens.WHITE)
	)
	stil.set_border_width_all(4 if angelegt else 3)
	rahmen.add_theme_stylebox_override("panel", stil)
	var bild := TextureRect.new()
	bild.name = "Vorschau"
	bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bild.custom_minimum_size = Vector2(0.0, 108.0)
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bild.texture = _preview.hole(str(def["id"]))
	rahmen.add_child(bild)
	_karten[str(def["id"])] = bild
	return rahmen


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
	if gesperrt:
		status.text = I18nService.t("wardrobe.level", {"n": int(def["min_level"])})
	elif angelegt:
		status.text = I18nService.t("wardrobe.angelegt")
	elif besitzt:
		status.text = I18nService.t("wardrobe.besessen")
	else:
		status.text = I18nService.t("wardrobe.preis", {"n": int(def["preis"])})
	box.add_child(status)
	return box


# ── Reaktionen ───────────────────────────────────────────────────────────────


func _on_karte_gedrueckt(id: String) -> void:
	item_tippen(id)


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
