class_name GobtyTvStage
extends SubViewport
## GOB.TY-Studio (W13C/GOBTY): das LIVE-Fernsehbild als SubViewport —
## Muster des geteilten Cosmetics-Icon-Renderers (cosmetic_preview.gd),
## nur mit eigener 3D-Welt, die dauerhaft rendert statt einmal zu backen.
## Die Textur landet über fernseher.gd auf der TV-Bildschirmfläche.
##
## Inhalt: kleine Bühne mit 2 Mini-Goobys (das bestehende GoobyRig-Modell,
## klein skaliert) vor buntem Studio-Hintergrund, dazu prozedurale
## Requisiten (Pult, Topf, Ball, Wetter-Symbole — keine neuen Assets) und
## ein 2D-Overlay (GOB.TY-Logo, Bauchbinden-Banner, Testbild).
##
## Die Bühne ist bewusst DUMM: WAS wann passiert, entscheidet der pure
## GobtyClipPlayer — hier wird nur inszeniert (`zeige_clip` baut die
## Kulisse, `wende_schritt_an` spielt einen Schritt an).

const BILD := Vector2i(512, 288)
const MINI_SCALE := 0.55
## Studio-Palette (Theme-Tokens, warm & pastellig).
const STUDIO_HINTEN := Color("#FFD9E8")
const STUDIO_SEITE := Color("#BDEDE6")
const STUDIO_BODEN := Color("#F6EAD8")
const BANNER_GRUND := Color(0.29, 0.23, 0.21, 0.92)
const LOGO_PINK := Color("#FF7BA9")
## Testbild-Balken (Mitte halbtransparent — der schlafende Gooby lugt durch).
const TESTBILD_FARBEN: Array[Color] = [
	Color("#FF7BA9"),
	Color("#FFD34D"),
	Color("#59C9B9"),
	Color(0.98, 0.96, 0.9, 0.35),
	Color("#8AC5FF"),
	Color("#C9A0E8"),
	Color("#4A3B36"),
]
const WETTER_SONNE := Color("#FFD34D")
const WETTER_WOLKE := Color(0.92, 0.92, 0.95)
const WETTER_TROPFEN := Color("#8AC5FF")
const WETTER_BLITZ := Color("#FFE066")

var _welt: Node3D
var _goobys: Array[GoobyRig] = []
var _props: Node3D
var _symbol_halter: Node3D
var _banner: PanelContainer
var _banner_label: Label
var _testbild: Control
var _tweens: Array[Tween] = []


func _init() -> void:
	size = BILD
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ready() -> void:
	_baue_studio()
	_baue_overlay()


## Rendern an/aus (aus = TV aus, kein GPU-Budget verbrennen).
func set_live(an: bool) -> void:
	render_target_update_mode = (SubViewport.UPDATE_ALWAYS if an else SubViewport.UPDATE_DISABLED)


## Kulisse für einen Clip aufbauen (Requisiten, Gooby-Aufstellung).
func zeige_clip(clip: Dictionary) -> void:
	_stoppe_tweens()
	for kind in _props.get_children():
		kind.queue_free()
	_symbol_halter = null
	set_banner("")
	_testbild.visible = false
	_stelle_goobys_auf(str(clip.get("id", "")))
	match str(clip.get("id", "")):
		"news":
			_props.add_child(_prop_pult())
		"kochen":
			_props.add_child(_prop_herd())
		"sport":
			_props.add_child(_prop_ball())
		"wetter":
			_symbol_halter = Node3D.new()
			_symbol_halter.name = "SymbolHalter"
			_symbol_halter.position = Vector3(0.62, 0.78, -0.25)
			_props.add_child(_symbol_halter)


## Einen Player-Schritt inszenieren (Emotion/Clip/Gag) — der Banner-Text
## kommt fertig übersetzt vom Fernseher.
func wende_schritt_an(schritt: Dictionary, banner_text: String) -> void:
	var akteur := _gooby(int(schritt.get("sprecher", 0)))
	if akteur != null:
		var emotion := str(schritt.get("emotion", ""))
		if emotion != "":
			akteur.set_emotion(emotion)
		var clip := str(schritt.get("clip", ""))
		if clip != "":
			akteur.play_clip(clip)
	if banner_text != "":
		set_banner(banner_text)
	_spiele_fx(str(schritt.get("fx", "")), schritt, akteur)


func set_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = not text.is_empty()


func banner_text() -> String:
	return _banner_label.text


func testbild_sichtbar() -> bool:
	return _testbild.visible


# ── Studio-Aufbau ─────────────────────────────────────────────────────────────


func _baue_studio() -> void:
	_welt = Node3D.new()
	_welt.name = "Studio"
	add_child(_welt)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = STUDIO_HINTEN
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.92)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_welt.add_child(world_env)
	_welt.add_child(_studio_kulisse())
	var sonne := DirectionalLight3D.new()
	sonne.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
	sonne.light_energy = 1.15
	_welt.add_child(sonne)
	var kamera := Camera3D.new()
	kamera.position = Vector3(0.0, 0.72, 2.35)
	kamera.fov = 42.0
	_welt.add_child(kamera)
	kamera.look_at_from_position(kamera.position, Vector3(0.0, 0.42, 0.0), Vector3.UP)
	kamera.current = true
	for i in 2:
		var mini := GoobyRig.new()
		mini.name = "MiniGooby%d" % i
		mini.scale = Vector3.ONE * MINI_SCALE
		_welt.add_child(mini)
		_goobys.append(mini)
	_props = Node3D.new()
	_props.name = "Props"
	_welt.add_child(_props)


## Bunter Studio-Hintergrund: Rückwand + Seitenpaneele + Bodenscheibe.
func _studio_kulisse() -> Node3D:
	var kulisse := Node3D.new()
	kulisse.name = "Kulisse"
	kulisse.add_child(_panel(Vector2(4.4, 2.4), STUDIO_HINTEN, Vector3(0.0, 1.2, -1.3), 0.0))
	kulisse.add_child(_panel(Vector2(2.6, 2.4), STUDIO_SEITE, Vector3(-1.9, 1.2, -0.6), 55.0))
	kulisse.add_child(_panel(Vector2(2.6, 2.4), STUDIO_SEITE, Vector3(1.9, 1.2, -0.6), -55.0))
	var boden := MeshInstance3D.new()
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 2.2
	scheibe.bottom_radius = 2.2
	scheibe.height = 0.04
	boden.mesh = scheibe
	boden.position = Vector3(0.0, -0.02, 0.0)
	boden.material_override = _flat(STUDIO_BODEN)
	kulisse.add_child(boden)
	return kulisse


func _panel(groesse: Vector2, farbe: Color, pos: Vector3, dreh_grad: float) -> MeshInstance3D:
	var wand := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = groesse
	wand.mesh = quad
	wand.position = pos
	wand.rotation_degrees = Vector3(0.0, dreh_grad, 0.0)
	wand.material_override = _flat(farbe)
	return wand


func _baue_overlay() -> void:
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.theme = ThemeService.theme()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_testbild = _baue_testbild()
	overlay.add_child(_testbild)
	var logo := PanelContainer.new()
	logo.name = "Logo"
	logo.self_modulate = Color(1, 1, 1, 0.0)  # Panel unsichtbar, eigener Grund:
	var logo_grund := ColorRect.new()
	logo_grund.color = LOGO_PINK
	logo.add_child(logo_grund)
	var logo_label := Label.new()
	logo_label.text = "GOB.TY"
	logo_label.add_theme_color_override("font_color", Color.WHITE)
	logo.add_child(logo_label)
	logo.position = Vector2(10, 8)
	overlay.add_child(logo)
	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.self_modulate = Color(1, 1, 1, 0.0)
	var grund := ColorRect.new()
	grund.color = BANNER_GRUND
	_banner.add_child(grund)
	_banner_label = Label.new()
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.9))
	_banner.add_child(_banner_label)
	_banner.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_banner.offset_top = -54.0
	_banner.offset_left = 8.0
	_banner.offset_right = -8.0
	_banner.offset_bottom = -8.0
	_banner.visible = false
	overlay.add_child(_banner)


## Testbild: Pastell-Balken, Mitte halbtransparent — dahinter schläft Gooby.
func _baue_testbild() -> Control:
	var bild := HBoxContainer.new()
	bild.name = "Testbild"
	bild.set_anchors_preset(Control.PRESET_FULL_RECT)
	bild.add_theme_constant_override("separation", 0)
	bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for farbe: Color in TESTBILD_FARBEN:
		var balken := ColorRect.new()
		balken.color = farbe
		balken.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bild.add_child(balken)
	bild.visible = false
	return bild


# ── Aufstellung + Requisiten ──────────────────────────────────────────────────


func _stelle_goobys_auf(clip_id: String) -> void:
	for mini in _goobys:
		mini.visible = true
		mini.rotation = Vector3.ZERO
		mini.set_emotion("neutral")
		mini.play_clip("idle")
	match clip_id:
		"news":
			_gooby(0).position = Vector3(0.0, 0.0, -0.35)
			_gooby(1).visible = false
		"kochen":
			_gooby(0).position = Vector3(-0.12, 0.0, -0.25)
			_gooby(1).visible = false
		"sport":
			_gooby(0).position = Vector3(-0.55, 0.0, -0.1)
			_gooby(1).position = Vector3(0.55, 0.0, -0.1)
		"wetter":
			_gooby(0).position = Vector3(-0.45, 0.0, -0.15)
			_gooby(1).visible = false
		_:
			_gooby(0).position = Vector3(0.0, 0.0, -0.1)
			_gooby(1).visible = false


func _gooby(i: int) -> GoobyRig:
	return _goobys[clampi(i, 0, _goobys.size() - 1)] if not _goobys.is_empty() else null


## Nachrichten-Pult vor Sprecher-Gooby.
func _prop_pult() -> Node3D:
	var pult := MeshInstance3D.new()
	pult.name = "Pult"
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.42, 0.34)
	pult.mesh = box
	pult.position = Vector3(0.0, 0.21, 0.18)
	pult.material_override = _flat(Color("#A9744B"))
	var blende := MeshInstance3D.new()
	var front := QuadMesh.new()
	front.size = Vector2(0.66, 0.24)
	blende.mesh = front
	blende.position = Vector3(0.0, 0.0, 0.176)
	blende.material_override = _flat(LOGO_PINK)
	pult.add_child(blende)
	return pult


## Küchen-Herd mit Topf (der Puff-Gag steigt hier auf).
func _prop_herd() -> Node3D:
	var herd := MeshInstance3D.new()
	herd.name = "Herd"
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.34, 0.4)
	herd.mesh = box
	herd.position = Vector3(0.28, 0.17, 0.12)
	herd.material_override = _flat(Color(0.85, 0.87, 0.9))
	var topf := MeshInstance3D.new()
	topf.name = "Topf"
	var zylinder := CylinderMesh.new()
	zylinder.top_radius = 0.14
	zylinder.bottom_radius = 0.12
	zylinder.height = 0.16
	topf.mesh = zylinder
	topf.position = Vector3(0.0, 0.25, 0.0)
	topf.material_override = _flat(Color(0.45, 0.45, 0.5))
	herd.add_child(topf)
	return herd


## Sport-Ball zwischen den beiden Hüpf-Goobys.
func _prop_ball() -> Node3D:
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var kugel := SphereMesh.new()
	kugel.radius = 0.11
	kugel.height = 0.22
	ball.mesh = kugel
	ball.position = Vector3(0.0, 0.11, 0.05)
	ball.material_override = _flat(Color("#FF9A5C"))
	return ball


## Wetter-Symbol (prozedural) für einen SoulWetter-Typ.
func _symbol(typ: String) -> Node3D:
	var halter := Node3D.new()
	halter.name = "Symbol_%s" % typ
	match typ:
		"sonne":
			halter.add_child(_kugel(0.14, WETTER_SONNE, Vector3.ZERO))
		"gewitter":
			halter.add_child(_wolke())
			var blitz := MeshInstance3D.new()
			var zacke := PrismMesh.new()
			zacke.size = Vector3(0.1, 0.18, 0.04)
			blitz.mesh = zacke
			blitz.position = Vector3(0.02, -0.2, 0.0)
			blitz.rotation_degrees = Vector3(0.0, 0.0, 180.0)
			blitz.material_override = _flat(WETTER_BLITZ)
			halter.add_child(blitz)
		"niesel", "regen":
			halter.add_child(_wolke())
			for i in 3:
				halter.add_child(
					_kugel(0.03, WETTER_TROPFEN, Vector3(-0.08 + 0.08 * i, -0.16 - 0.03 * i, 0.0))
				)
		"schnee":
			halter.add_child(_wolke())
			for i in 3:
				halter.add_child(_kugel(0.035, Color.WHITE, Vector3(-0.09 + 0.09 * i, -0.17, 0.0)))
		"nebel":
			for i in 3:
				var schwade := _kugel(0.1, Color(0.9, 0.9, 0.92, 0.8), Vector3(0.0, -0.08 * i, 0.0))
				schwade.scale = Vector3(1.6, 0.45, 0.8)
				halter.add_child(schwade)
		_:
			halter.add_child(_wolke())
	return halter


func _wolke() -> Node3D:
	var wolke := Node3D.new()
	wolke.name = "Wolke"
	wolke.add_child(_kugel(0.1, WETTER_WOLKE, Vector3(-0.08, 0.0, 0.0)))
	wolke.add_child(_kugel(0.12, WETTER_WOLKE, Vector3(0.02, 0.04, 0.0)))
	wolke.add_child(_kugel(0.09, WETTER_WOLKE, Vector3(0.12, 0.0, 0.0)))
	return wolke


func _kugel(radius: float, farbe: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = radius
	kugel.height = radius * 2.0
	mesh.mesh = kugel
	mesh.position = pos
	mesh.material_override = _flat(farbe)
	return mesh


# ── Gags (fx) ─────────────────────────────────────────────────────────────────


func _spiele_fx(fx: String, schritt: Dictionary, akteur: GoobyRig) -> void:
	match fx:
		"puff":
			_fx_puff()
		"umfallen":
			_fx_umfallen(akteur, true)
		"aufstehen":
			_fx_umfallen(_gooby(1), false)
		"testbild":
			_testbild.visible = true
		"symbol":
			_fx_symbol(schritt.get("wetter", {}) as Dictionary)


## Puff überm Topf: Rauchkugeln steigen auf und verblassen (Tween).
## Reduced Motion: nur der rußige Blick (Emotion setzt der Schritt).
func _fx_puff() -> void:
	if RewardFx.reduced_motion(self):
		return
	for i in 4:
		var rauch := _kugel(0.06 + 0.02 * i, Color(0.35, 0.3, 0.28, 0.85), Vector3(0.28, 0.5, 0.12))
		_props.add_child(rauch)
		var tween := rauch.create_tween()
		_tweens.append(tween)
		tween.tween_property(
			rauch, "position", rauch.position + Vector3(0.1 - 0.07 * i, 0.5, 0.0), 0.9
		)
		tween.parallel().tween_property(rauch, "transparency", 1.0, 0.9)
		tween.tween_callback(rauch.queue_free)


## Sport-Gag: Gooby B kippt zur Seite (und rappelt sich später wieder auf).
func _fx_umfallen(akteur: GoobyRig, hinlegen: bool) -> void:
	if akteur == null:
		return
	var ziel := Vector3(0.0, 0.0, deg_to_rad(80.0)) if hinlegen else Vector3.ZERO
	if RewardFx.reduced_motion(self):
		akteur.rotation = ziel
		return
	var tween := akteur.create_tween()
	_tweens.append(tween)
	tween.tween_property(akteur, "rotation", ziel, 0.45).set_trans(Tween.TRANS_BOUNCE)


func _fx_symbol(wetter: Dictionary) -> void:
	if _symbol_halter == null:
		return
	for kind in _symbol_halter.get_children():
		kind.queue_free()
	_symbol_halter.add_child(_symbol(str(wetter.get("typ", "sonne"))))


func _stoppe_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


static func _flat(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.9
	if farbe.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
