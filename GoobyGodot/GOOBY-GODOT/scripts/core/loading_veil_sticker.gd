class_name LoadingVeilSticker
extends Control
## W16/VEIL — Runder Motiv-Sticker der Veil-Karte (Web-Parität: POLISH-D
## `.mg-loading-motif` + V6 `acui-veil-bounce`, GOOBY/src/ui/styles.css
## Z. 5100-5112 und loadingVeil.js Z. 343-354): weiß umrandeter Kreis
## (72 Design-px, 3-px-Rand, Fond #FDF6E3, weicher Pop-Schatten), der die
## Cover-Unterkante der Karte überlappt. Das Motiv-Bild wird wie
## `object-fit: cover` + `border-radius: 50%` rund beschnitten.
##
## Im Veil hüpft der Sticker mit Squash & Stretch — die Keyframes sind 1:1
## die CSS-`acui-veil-bounce`-Posen (1,3 s, cubic-bezier(0.45,0,0.55,1) je
## Segment ≈ Sinus-Glättung). `set_animated(false)` = Reduced Motion:
## eingefrorene Ruhepose, kein _process (gleiche API wie der frühere
## LoadingVeilGooby am %Gooby-Knoten — W1a-Contract).

const FOND := Color("#FDF6E3")  # Web .mg-loading-motif background
## Web-Referenzmaße (Design-px): Durchmesser 4.5rem, Rand 0.1875rem.
const DURCHMESSER := 72.0
const RAND := 3.0
const BOUNCE_S := 1.3
## CSS-Keyframes acui-veil-bounce: [Zeitanteil, translateY(px), sx, sy].
const KEYFRAMES: Array[Array] = [
	[0.0, 0.0, 1.0, 1.0],
	[0.32, -12.0, 0.94, 1.08],
	[0.52, 1.0, 1.08, 0.9],
	[0.7, -5.0, 0.98, 1.03],
	[0.84, 0.0, 1.02, 0.98],
	[1.0, 0.0, 1.0, 1.0],
]

var _t := 0.0
var _animated := true
var _motiv_rund: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_animated)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Reduced Motion: false = eingefrorene Ruhepose (Keyframe 0).
func set_animated(animated: bool) -> void:
	_animated = animated
	set_process(animated)
	if not animated:
		_t = 0.0
	queue_redraw()


func is_animated() -> bool:
	return _animated


## Motiv setzen — wird einmalig rund beschnitten (Web: object-fit cover
## in einem border-radius-50%-Kreis).
func set_motiv(textur: Texture2D) -> void:
	_motiv_rund = _runde_textur(textur)
	queue_redraw()


func _draw() -> void:
	var d := minf(size.x, size.y)
	if d <= 0.0:
		return
	var r := d / 2.0
	var mitte := size / 2.0
	var pose := _pose()
	var versatz := Vector2(0.0, pose.x * (d / DURCHMESSER))
	draw_set_transform_matrix(Transform2D(0.0, Vector2(pose.y, pose.z), 0.0, mitte + versatz))
	# Weicher Pop-Schatten (Web --shadow-soft) — wandert wie im CSS mit.
	draw_circle(Vector2(0.0, r * 0.12), r * 1.02, AcTokens.SHADOW_SOFT_COLOR)
	draw_circle(Vector2.ZERO, r, AcTokens.WHITE)
	var innen := r - RAND * (d / DURCHMESSER)
	draw_circle(Vector2.ZERO, innen, FOND)
	if _motiv_rund != null:
		draw_texture_rect(_motiv_rund, Rect2(-innen, -innen, innen * 2.0, innen * 2.0), false)
	draw_set_transform_matrix(Transform2D())


## Bounce-Pose zum aktuellen Zeitpunkt: (translateY, sx, sy) — Segmente
## der CSS-Keyframes mit Smoothstep geglättet.
func _pose() -> Vector3:
	if not _animated:
		return Vector3(0.0, 1.0, 1.0)
	var u := fmod(_t / BOUNCE_S, 1.0)
	for i in KEYFRAMES.size() - 1:
		var a: Array = KEYFRAMES[i]
		var b: Array = KEYFRAMES[i + 1]
		if u > float(b[0]):
			continue
		var spanne := maxf(float(b[0]) - float(a[0]), 0.0001)
		var k := clampf((u - float(a[0])) / spanne, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		return Vector3(
			lerpf(float(a[1]), float(b[1]), k),
			lerpf(float(a[2]), float(b[2]), k),
			lerpf(float(a[3]), float(b[3]), k)
		)
	return Vector3(0.0, 1.0, 1.0)


## Quadratisch beschneiden (cover) + Kreis-Alphamaske — einmalig beim
## Setzen; komprimierte Texturen werden vorher dekomprimiert. Schlägt die
## Bildbearbeitung fehl, bleibt das Original (Motive haben Alpha-Ränder).
static func _runde_textur(textur: Texture2D) -> Texture2D:
	if textur == null:
		return null
	var bild := textur.get_image()
	if bild == null:
		return textur
	if bild.is_compressed() and bild.decompress() != OK:
		return textur
	bild.convert(Image.FORMAT_RGBA8)
	var seite := mini(bild.get_width(), bild.get_height())
	var quelle := Rect2i(
		(bild.get_width() - seite) / 2, (bild.get_height() - seite) / 2, seite, seite
	)
	var quad := bild.get_region(quelle)
	var r := seite / 2.0
	for y in seite:
		for x in seite:
			var abstand := Vector2(x - r + 0.5, y - r + 0.5).length()
			if abstand <= r:
				continue
			var pixel := quad.get_pixel(x, y)
			pixel.a *= clampf(r - abstand + 1.0, 0.0, 1.0)
			quad.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(quad)
