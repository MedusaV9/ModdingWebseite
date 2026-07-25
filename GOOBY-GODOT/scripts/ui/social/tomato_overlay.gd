class_name TomatoOverlay
extends Control
## Tomaten-Splat auf der „Kamera“/dem Gesicht (W3c VISIT, Auftrag): prozedural
## generierte Splat-Textur (TextureRect), die 3–5 s langsam abrutscht und
## verblasst (Tween — BoardEmotes.SPLAT_SLIDE_SEC). Kein Asset nötig.

const SPLAT_PX := 420

var _texture: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# and_offsets: nur-Anker-Preset behält den (leeren) Ist-Rect, wenn der
	# Parent beim Einhängen schon Größe hat → Splat säße oben links.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture = ImageTexture.create_from_image(_make_splat_image())


## PLATSCH! Splat einblenden und abrutschen lassen. Mehrfach aufrufbar
## (jeder Wurf = eigener TextureRect, räumt sich selbst weg).
func splat(at_ratio := Vector2(0.5, 0.4)) -> void:
	var rect := TextureRect.new()
	rect.texture = _texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(SPLAT_PX, SPLAT_PX)
	rect.position = size * at_ratio - rect.size * 0.5
	rect.pivot_offset = rect.size * 0.5
	rect.rotation = randf_range(-0.35, 0.35)
	add_child(rect)
	rect.scale = Vector2(1.6, 1.6)
	rect.modulate.a = 0.0
	var slide := BoardEmotes.SPLAT_SLIDE_SEC
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, 0.08)
	(
		tween
		. parallel()
		. tween_property(rect, "scale", Vector2.ONE, 0.16)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_interval(0.4)
	(
		tween
		. tween_property(rect, "position:y", rect.position.y + size.y * 0.45, slide)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		tween
		. parallel()
		. tween_property(rect, "modulate:a", 0.0, slide)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	tween.tween_callback(rect.queue_free)


func has_active_splat() -> bool:
	return get_child_count() > 0


## Prozeduraler Splat: großer Kern + Zufalls-Kleckse + Tropfen nach unten.
func _make_splat_image() -> Image:
	var img := Image.create(SPLAT_PX, SPLAT_PX, false, Image.FORMAT_RGBA8)
	var center := Vector2(SPLAT_PX / 2.0, SPLAT_PX / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260725
	var blobs: Array = [[center, SPLAT_PX * 0.26]]
	for _i in 10:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(SPLAT_PX * 0.16, SPLAT_PX * 0.34)
		blobs.append([center + Vector2(cos(angle), sin(angle)) * dist, rng.randf_range(14.0, 44.0)])
	for _i in 4:
		var x := center.x + rng.randf_range(-SPLAT_PX * 0.2, SPLAT_PX * 0.2)
		var y := center.y + rng.randf_range(SPLAT_PX * 0.2, SPLAT_PX * 0.42)
		blobs.append([Vector2(x, y), rng.randf_range(8.0, 18.0)])
	for y in SPLAT_PX:
		for x in SPLAT_PX:
			var pos := Vector2(x, y)
			var alpha := 0.0
			for blob: Array in blobs:
				var d: float = pos.distance_to(blob[0])
				var r: float = blob[1]
				if d < r:
					alpha = maxf(alpha, clampf(1.0 - d / r * 0.55, 0.0, 1.0))
			if alpha > 0.0:
				var shade := 0.75 + 0.2 * alpha
				img.set_pixel(x, y, Color(0.82 * shade, 0.12 * shade, 0.08 * shade, alpha))
	return img
