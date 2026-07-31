class_name BootCoverScreen
extends CanvasLayer
## W14/LOADING — der Boot-Cover-Screen des allerersten Ladens (User-Wunsch:
## „Querformat-Coverartwork mit Ladebalken unten und dann eine Animation
## wenn's ins Spiel geht“). Komplett in Code gebaut (kein tscn), Layer 120 —
## liegt ÜBER dem LoadingVeil (100), damit die erste Router-Reise dahinter
## unsichtbar abläuft.
##
## - Vollbild-Artwork (assets/boot/boot_cover.png, 16:9): Querformat füllt,
##   Hochkant croppt sanft mit Fokus auf Gooby (BootPhasen.cover_layout);
##   greift der Zoom-Deckel, füllt die Randfarbe AUS dem Bild (nie schwarz).
## - Unten: Möhren-Ladebalken (BootLadebalken) mit ECHTEM Phasen-Fortschritt
##   (main.gd meldet BootPhasen-Prozente) + rotierende knuffige Lade-Sprüche
##   (loading.boot.sprueche, deterministische Rotation je Seed).
## - oeffne(): Übergangs-Animation ins Spiel — weiches Aufzoomen + Kreis-Wipe
##   auf Gooby zentriert + Konfetti-Puff; Reduced Motion: schlichter Fade.

signal geoeffnet

const COVER_PFAD := "res://assets/boot/boot_cover.png"
const SPRUCH_ROTATE_SEC := 2.6
const SPRUECHE_KEY := "loading.boot.sprueche"
const ZOOM_ZIEL := 1.07
const WIPE_S := 0.55
const FADE_S := 0.18
const WIPE_KANTE := 0.09
const KONFETTI_MENGE := 36

## Deterministische Spruch-Rotation: Tests/Screenshots pinnen den Seed;
## -1 = beim _ready aus der Uhr würfeln (jeder Boot fühlt sich frisch an).
var spruch_seed := -1

var _root: Control
var _hintergrund: ColorRect
var _artwork: TextureRect
var _unten: VBoxContainer
var _spruch_label: Label
var _balken: BootLadebalken
var _spruch_timer: Timer
var _wipe_material: ShaderMaterial
var _spruch_schritt := 0
var _oeffnet := false


func _ready() -> void:
	layer = 120
	if spruch_seed < 0:
		spruch_seed = int(Time.get_ticks_usec()) % 100_000 + 1
	_build()
	_layout_anwenden()
	_naechster_spruch()
	_spruch_timer = Timer.new()
	_spruch_timer.wait_time = SPRUCH_ROTATE_SEC
	_spruch_timer.timeout.connect(_naechster_spruch)
	add_child(_spruch_timer)
	_spruch_timer.start()


## ECHTER Boot-Fortschritt 0..1 (BootPhasen.prozent-Werte aus main.gd).
func set_progress(ratio: float) -> void:
	if _balken != null:
		_balken.set_progress(ratio)


func get_progress() -> float:
	return _balken.get_progress() if _balken != null else 0.0


## Fokuspunkt (Gooby) in Viewport-Pixeln — Zentrum des Kreis-Wipes.
func fokus_px() -> Vector2:
	var layout := _layout()
	return layout["fokus_px"]


func spruch_text() -> String:
	return _spruch_label.text if _spruch_label != null else ""


## Übergangs-Animation ins Spiel (awaitbar; feuert `geoeffnet`).
## Reduced Motion: schlichter Fade statt Zoom+Kreis-Wipe+Konfetti.
func oeffne(reduced_motion := false) -> void:
	if _oeffnet:
		return
	_oeffnet = true
	if _spruch_timer != null:
		_spruch_timer.stop()
	AudioDirector.try_play(self, "travel_whoosh_auf")
	if reduced_motion or BootPhasen.wipe_variante(reduced_motion) == "fade":
		var fade := create_tween()
		fade.tween_property(_root, "modulate:a", 0.0, FADE_S)
		await fade.finished
		visible = false
		geoeffnet.emit()
		return
	await _oeffne_kreis()
	visible = false
	geoeffnet.emit()


func _oeffne_kreis() -> void:
	var groesse := _viewport_groesse()
	var layout := _layout()
	var fokus: Vector2 = layout["fokus_px"]
	_konfetti_puff(fokus)
	# Balken + Spruch zuerst weich weg — sie sollen nicht mitzoomen.
	var weg := create_tween()
	weg.tween_property(_unten, "modulate:a", 0.0, 0.12)
	# Weiches Aufzoomen aufs Artwork (Pivot = Gooby) …
	_artwork.pivot_offset = fokus - _artwork.position
	var tween := create_tween().set_parallel()
	(
		tween
		. tween_property(_artwork, "scale", Vector2.ONE * ZOOM_ZIEL, WIPE_S + 0.1)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	# … plus Kreis-Wipe: wachsende transparente Iris um Gooby (beide
	# Deck-Flächen teilen EIN Material — ein Uniform treibt beide).
	var aspekt := Vector2(groesse.x / maxf(groesse.y, 1.0), 1.0)
	var zentrum := fokus / groesse
	_wipe_material.set_shader_parameter("zentrum", zentrum)
	_wipe_material.set_shader_parameter("aspekt", aspekt)
	var max_r := 0.0
	for ecke in [Vector2(0, 0), Vector2(aspekt.x, 0), Vector2(0, 1), Vector2(aspekt.x, 1)]:
		max_r = maxf(max_r, (zentrum * aspekt).distance_to(ecke))
	var radius_setter := func(r: float) -> void: _wipe_material.set_shader_parameter("radius", r)
	(
		tween
		. tween_method(radius_setter, 0.0, max_r + WIPE_KANTE, WIPE_S)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)
	await tween.finished


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Blinde Taps schlucken, solange das Cover deckt (wie das Web-Veil).
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# CanvasLayer-Gotcha (W3d-Handoff): Window-Theme kommt hier nicht an.
	_root.theme = ThemeService.theme()
	add_child(_root)
	_wipe_material = ShaderMaterial.new()
	_wipe_material.shader = _wipe_shader()
	_wipe_material.set_shader_parameter("radius", -1.0)
	_wipe_material.set_shader_parameter("kante", WIPE_KANTE)
	_hintergrund = ColorRect.new()
	_hintergrund.name = "Hintergrund"
	_hintergrund.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hintergrund.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hintergrund.material = _wipe_material
	_root.add_child(_hintergrund)
	_artwork = TextureRect.new()
	_artwork.name = "Artwork"
	_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork.stretch_mode = TextureRect.STRETCH_SCALE
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_artwork.material = _wipe_material
	if ResourceLoader.exists(COVER_PFAD):
		_artwork.texture = load(COVER_PFAD)
	_hintergrund.color = _randfarbe_aus_textur()
	_root.add_child(_artwork)
	_build_unten()
	_root.resized.connect(_layout_anwenden)


func _build_unten() -> void:
	_unten = VBoxContainer.new()
	_unten.name = "Unten"
	_unten.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_unten.offset_top = -132.0
	_unten.offset_bottom = -26.0
	_unten.alignment = BoxContainer.ALIGNMENT_END
	_unten.add_theme_constant_override("separation", 10)
	_unten.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_unten)
	_spruch_label = Label.new()
	_spruch_label.name = "Spruch"
	_spruch_label.theme_type_variation = &"TitleLabel"
	_spruch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spruch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spruch_label.add_theme_color_override("font_color", Color(1.0, 0.985, 0.95))
	_spruch_label.add_theme_color_override("font_outline_color", Color(0.29, 0.23, 0.21, 0.9))
	_spruch_label.add_theme_constant_override("outline_size", 7)
	_unten.add_child(_spruch_label)
	_balken = BootLadebalken.new()
	_balken.name = "Balken"
	_balken.custom_minimum_size = Vector2(420.0, 26.0)
	_balken.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unten.add_child(_balken)


## Artwork nach der Crop-Mathe platzieren (auch bei Rotation/Resize).
func _layout_anwenden() -> void:
	if _artwork == null:
		return
	var layout := _layout()
	var rect: Rect2 = layout["rect"]
	_artwork.position = rect.position
	_artwork.size = rect.size
	_artwork.scale = Vector2.ONE
	if _balken != null:
		var breite := clampf(_viewport_groesse().x * 0.56, 260.0, 520.0)
		_balken.custom_minimum_size = Vector2(breite, 26.0)


func _layout() -> Dictionary:
	var bild := Vector2(1920.0, 1080.0)
	if _artwork != null and _artwork.texture != null:
		bild = Vector2(_artwork.texture.get_size())
	return BootPhasen.cover_layout(_viewport_groesse(), bild)


func _viewport_groesse() -> Vector2:
	if _root != null and _root.size.x > 0.0:
		return _root.size
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1280, 720)


func _naechster_spruch() -> void:
	var sprueche := I18nService.items(SPRUECHE_KEY)
	var index := BootPhasen.spruch_index(_spruch_schritt, sprueche.size(), spruch_seed)
	_spruch_schritt += 1
	if index >= 0 and _spruch_label != null:
		_spruch_label.text = str(sprueche[index])


## Randfarbe aus dem geladenen Artwork messen; nicht lesbare Textur
## (VRAM-komprimiert) → gebackener Fallback (ebenfalls aus dem Bild gemittelt).
func _randfarbe_aus_textur() -> Color:
	if _artwork == null or _artwork.texture == null:
		return BootPhasen.RANDFARBE_FALLBACK
	var img := _artwork.texture.get_image()
	if img != null and img.is_compressed():
		if img.decompress() != OK:
			return BootPhasen.RANDFARBE_FALLBACK
	return BootPhasen.randfarbe(img)


## Kleiner Konfetti-Puff auf Gooby zentriert (nur im animierten Pfad —
## der Reduced-Motion-Fade ruft ihn gar nicht erst auf).
func _konfetti_puff(fokus: Vector2) -> void:
	var puff := CPUParticles2D.new()
	puff.name = "KonfettiPuff"
	puff.position = fokus
	puff.one_shot = true
	puff.emitting = true
	puff.amount = KONFETTI_MENGE
	puff.lifetime = 0.9
	puff.explosiveness = 1.0
	puff.direction = Vector2.UP
	puff.spread = 180.0
	puff.gravity = Vector2(0.0, 420.0)
	puff.initial_velocity_min = 140.0
	puff.initial_velocity_max = 340.0
	puff.angular_velocity_min = -260.0
	puff.angular_velocity_max = 260.0
	puff.scale_amount_min = 3.0
	puff.scale_amount_max = 6.0
	puff.hue_variation_min = -0.5
	puff.hue_variation_max = 0.5
	puff.color = Color("#FFD166")
	_root.add_child(puff)


static func _wipe_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 zentrum = vec2(0.5, 0.5);
uniform vec2 aspekt = vec2(1.777, 1.0);
uniform float radius = -1.0;
uniform float kante = 0.09;
void fragment() {
	float d = distance(SCREEN_UV * aspekt, zentrum * aspekt);
	COLOR.a *= smoothstep(radius - kante, radius, d);
}
"""
	return shader
