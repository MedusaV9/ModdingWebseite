class_name LoadingVeilSweep
extends Control
## W16/VEIL — Indeterminate-Sweep der Veil-Karte (Web-Parität: POLISH-D
## `.mg-loading-bar-indet`, GOOBY/src/ui/styles.css Z. 5152-5166): solange
## KEIN echter Ladefortschritt gemeldet wird, wischt eine 45 % breite
## Verlaufs-Füllung in 1,2 s (ease-in-out, endlos) über den Pill-Track —
## translateX(-100 % → 320 %) der Füllbreite wie im CSS.
##
## Nachfolger der W14-Punkte mit derselben Regel: der Sweep WEICHT dem
## echten Balken (das Veil blendet ihn aus, sobald %Progress sichtbar
## wird — nie zwei Ladeanzeigen gleichzeitig). `set_animated(false)` =
## Reduced Motion: die Füllung ruht am linken Rand (CSS `animation: none`).

const SWEEP_S := 1.2
const FUELL_ANTEIL := 0.45
## CSS translateX: von -100 % bis +320 % der Füllbreite.
const X_VON := -1.0
const X_BIS := 3.2

var _t := 0.0
var _animated := true
var _track: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track = StyleBoxFlat.new()
	_track.bg_color = LoadingVeilBalken.track_farbe()
	_track.set_corner_radius_all(AcTokens.RADIUS_PILL)
	set_process(_animated)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Reduced Motion: false = Füllung ruht links, kein _process.
func set_animated(animated: bool) -> void:
	_animated = animated
	set_process(animated)
	if not animated:
		_t = 0.0
	queue_redraw()


func is_animated() -> bool:
	return _animated


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _track != null:
		draw_style_box(_track, Rect2(Vector2.ZERO, size))
	var fuell_b := size.x * FUELL_ANTEIL
	var u := 0.0
	if _animated:
		u = fmod(_t / SWEEP_S, 1.0)
		u = u * u * (3.0 - 2.0 * u)
	var x := fuell_b * lerpf(X_VON, X_BIS, u)
	if not _animated:
		x = 0.0
	var links := maxf(x, 0.0)
	var rechts := minf(x + fuell_b, size.x)
	if rechts - links < 0.5:
		return
	LoadingVeilBalken.zeichne_gradient_pill(
		self, Rect2(links, 0.0, rechts - links, size.y), Rect2(x, 0.0, fuell_b, size.y)
	)
