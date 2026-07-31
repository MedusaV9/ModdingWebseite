class_name AcWallpaper
extends ColorRect
## Der AC-Look für ALLE Screens: warmer Farb-Wash + langsam schräg driftendes
## Pattern (Web-acui-Kacheln, kopiert nach `assets/ui/patterns/`).
## Einfach als unterstes Kind in jede Screen-Szene legen, Full-Rect-Anchors.
##
## UICOZY: `AcWallpaper.for_context("shop")` liefert den fertig gestimmten
## Hintergrund pro Spielbereich (Farb-Stimmung + Pattern + Drift-Richtung/-Tempo
## 1:1 aus dem Web-V6/A2-Themenblock, styles.css „THEMES“). Eine Zeile pro
## Screen — Handoff: /tmp/gooby-godot/handoffs/UICOZY-bg-api.md.
##
## Reduced Motion: hört auf `UiTheme.reduced_motion_changed` (Duck-Typing,
## kein harter Autoload-Zwang) und friert den Drift über den Shader-Uniform ein.

const SHADER := preload("res://scripts/ui/wallpaper_drift.gdshader")
const PATTERN_DIR := "res://assets/ui/patterns/"
## Kachel-Periode in Design-px (Web --thm-pattern-size: 24rem = 384 px) —
## vorher zeigte der Shader fix 3 Kacheln über die Breite (≈ ⅓ der Web-Größe).
const TILE_DESIGN_PX := 384.0

## Kontext-Stimmungen — Werte 1:1 aus GOOBY/src/ui/styles.css (V6/A2):
## wash = --thm-bg, pattern = --thm-pattern, opacity = --thm-pattern-opacity,
## dur = --thm-drift-dur (Sekunden pro Kachel), dir = Drift-Richtung
## (Web: ↖︎ = (-1,-1); Arcade bewusst ↗︎ = (+1,-1)). accent/accent_dark/soft
## spiegeln das --thm-Akzent-Trio für Screen-Bausteine (Tabs/Ribbons/CTAs).
const CONTEXTS := {
	"default":
	{
		"wash": Color("#FFF6EC"),
		"pattern": "leaves",
		"opacity": AcTokens.PATTERN_OPACITY_SCREEN,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#8FD06C"),
		"accent_dark": Color("#6DB54E"),
		"soft": Color(0.4275, 0.7098, 0.3059, 0.3),
	},
	"shop":
	{
		"wash": Color("#EEF4FB"),
		"pattern": "shop",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 96.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#6F9BD6"),
		"accent_dark": Color("#557FB8"),
		"soft": Color(0.4353, 0.6078, 0.8392, 0.3),
	},
	"wardrobe":
	{
		"wash": Color("#FDF0F4"),
		"pattern": "wardrobe",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 104.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#E78FB3"),
		"accent_dark": Color("#C9709A"),
		"soft": Color(0.9059, 0.5608, 0.7020, 0.3),
	},
	"arcade":
	{
		"wash": Color("#F3EFFA"),
		"pattern": "arcade",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 84.0,
		"dir": Vector2(1.0, -1.0),
		"accent": Color("#9B7FD6"),
		"accent_dark": Color("#7E63B8"),
		"soft": Color(0.6078, 0.4980, 0.8392, 0.3),
	},
	"quest":
	{
		"wash": Color("#F8EFE2"),
		"pattern": "quest",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 108.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#C98D5F"),
		"accent_dark": Color("#A97144"),
		"soft": Color(0.7882, 0.5529, 0.3725, 0.3),
	},
	"album":
	{
		"wash": Color("#F9F3E7"),
		"pattern": "album",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 112.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#D6A35F"),
		"accent_dark": Color("#B58445"),
		"soft": Color(0.8392, 0.6392, 0.3725, 0.3),
	},
	"passport":
	{
		"wash": Color("#EFF6F4"),
		"pattern": "passport",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#4FA8A0"),
		"accent_dark": Color("#3D8A83"),
		"soft": Color(0.3098, 0.6588, 0.6275, 0.3),
	},
	"clinic":
	{
		"wash": Color("#EFFAF5"),
		"pattern": "clinic",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#59C9B9"),
		"accent_dark": Color("#3FA89A"),
		"soft": Color(0.3490, 0.7882, 0.7255, 0.3),
	},
	"settings":
	{
		"wash": Color("#FFF6EC"),
		"pattern": "leaves",
		"opacity": AcTokens.PATTERN_OPACITY_SCREEN,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#8FD06C"),
		"accent_dark": Color("#6DB54E"),
		"soft": Color(0.4275, 0.7098, 0.3059, 0.3),
	},
	"blueprint":
	{
		"wash": Color("#F0F4F7"),
		"pattern": "blueprint",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 120.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#7FA3B8"),
		"accent_dark": Color("#64879C"),
		"soft": Color(0.4980, 0.6392, 0.7216, 0.3),
	},
	"radio":
	{
		"wash": Color("#FDF3E3"),
		"pattern": "radio",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 92.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#E8A13F"),
		"accent_dark": Color("#C78527"),
		"soft": Color(0.9098, 0.6314, 0.2471, 0.3),
	},
	"trophy":
	{
		"wash": Color("#FBF4E4"),
		"pattern": "trophy",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 108.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#E0B04A"),
		"accent_dark": Color("#C29736"),
		"soft": Color(0.8784, 0.6902, 0.2902, 0.3),
	},
	"credits":
	{
		"wash": Color("#F5F0EC"),
		"pattern": "credits",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 116.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#FF7BA9"),
		"accent_dark": Color("#E05F8D"),
		"soft": Color(1.0, 0.4824, 0.6627, 0.28),
	},
	# Godot-eigene Bereiche ohne Web-Screen — Stimmungen nach Web-Formel
	# (Wash aus den V6/A2-Panel-Tints, Akzent passend zum Bereich):
	# Garten = Grün (Web .panel-gardenSeeds #F4FAEE), Ranch = Honig
	# (Web .panel-foodTray #FDF7EC), Stadt = Reise-Blau (.panel-airport).
	"garten":
	{
		"wash": Color("#F4FAEE"),
		"pattern": "leaves",
		"opacity": AcTokens.PATTERN_OPACITY_SCREEN,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#8FD06C"),
		"accent_dark": Color("#6DB54E"),
		"soft": Color(0.4275, 0.7098, 0.3059, 0.3),
	},
	"ranch":
	{
		"wash": Color("#FDF7EC"),
		"pattern": "quest",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 108.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#E0B04A"),
		"accent_dark": Color("#C29736"),
		"soft": Color(0.8784, 0.6902, 0.2902, 0.3),
	},
	"city":
	{
		"wash": Color("#EFF4FB"),
		"pattern": "passport",
		"opacity": AcTokens.PATTERN_OPACITY_THEMED,
		"dur": 100.0,
		"dir": Vector2(-1.0, -1.0),
		"accent": Color("#6F9BD6"),
		"accent_dark": Color("#557FB8"),
		"soft": Color(0.4353, 0.6078, 0.8392, 0.3),
	},
}

## Deutsche/alternative Bereichs-Namen → Kontext-Key (1-Zeilen-Einbau für
## fremde Screens: `AcWallpaper.for_context("laden")` funktioniert auch).
const ALIASES := {
	"home": "default",
	"daheim": "default",
	"laden": "shop",
	"ikea": "shop",
	"baumarkt": "shop",
	"kleiderschrank": "wardrobe",
	"garderobe": "wardrobe",
	"spielhalle": "arcade",
	"minigame": "arcade",
	"pregame": "arcade",
	"results": "arcade",
	"quests": "quest",
	"aufgaben": "quest",
	"sticker": "album",
	"reise": "passport",
	"profil": "passport",
	"flughafen": "passport",
	"klinik": "clinic",
	"vet": "clinic",
	"tierarzt": "clinic",
	"einstellungen": "settings",
	"bau": "blueprint",
	"werkstatt": "blueprint",
	"musik": "radio",
	"trophaeen": "trophy",
	"achievements": "trophy",
	"erfolge": "trophy",
	"stadt": "city",
	"garden": "garten",
	"farm": "ranch",
}

## Pattern-Name ohne Präfix/Endung, z. B. "leaves", "dots", "arcade".
@export var pattern: String = "leaves":
	set(value):
		pattern = value
		_apply_pattern()

## Grundfarbe unter dem Pattern (Screen-Wash).
@export var wash: Color = AcTokens.BG_CREAM:
	set(value):
		wash = value
		_set_uniform("wash", wash)

## Layer-Deckkraft des Patterns — Web-Parität: 0.45 (Leaf-Standard) bzw.
## 0.85 (Themen-Kacheln, die ≤ 6 % Luminanz-Delta einbacken).
@export_range(0.0, 1.0) var pattern_opacity: float = AcTokens.PATTERN_OPACITY_SCREEN:
	set(value):
		pattern_opacity = value
		_set_uniform("opacity", pattern_opacity)

## Drift-Vektor in Kacheln/Sekunde (Reduced Motion nullt ihn im Shader).
@export var drift: Vector2 = AcTokens.DRIFT_TILES_PER_SEC:
	set(value):
		drift = value
		_set_uniform("drift", drift)

## Gesetzter Kontext-Key (leer = manuell konfiguriert).
var context := ""

var _mat: ShaderMaterial
## W13-C: Kachel-Zahl gemerkt für die px→UV-Umrechnung des Parallax-Schubs.
var _tile_count := 3.0


## DIE Ein-Zeilen-API für alle Screens: fertig gestimmter Hintergrund pro
## Bereich. Unbekannte Namen fallen weich auf "default" (Cream + Leaves).
static func for_context(ctx: String) -> AcWallpaper:
	var wallpaper: AcWallpaper = new()
	wallpaper.apply_context(ctx)
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	return wallpaper


## Kontext-Key auflösen (Aliasse + unbekannt → "default").
static func resolve_context(ctx: String) -> String:
	var key := ctx.strip_edges().to_lower()
	if ALIASES.has(key):
		key = ALIASES[key]
	if not CONTEXTS.has(key):
		key = "default"
	return key


## Akzent-Trio eines Bereichs (Web --thm-accent/-dark/-soft) für Screen-
## Bausteine, die zur Wand passen sollen (Tabs, Ribbons, CTAs).
static func context_accent(ctx: String) -> Dictionary:
	var info: Dictionary = CONTEXTS[resolve_context(ctx)]
	return {
		"accent": info["accent"],
		"accent_dark": info["accent_dark"],
		"soft": info["soft"],
	}


## Stimmung eines Kontexts auf DIESE Instanz anwenden (auch nachträglich —
## z. B. Recap-Stationen, die pro Station umfärben).
func apply_context(ctx: String) -> void:
	var key := resolve_context(ctx)
	context = key
	var info: Dictionary = CONTEXTS[key]
	wash = info["wash"]
	pattern_opacity = info["opacity"]
	var dur := maxf(float(info["dur"]), 1.0)
	drift = Vector2(info["dir"]) / dur
	pattern = info["pattern"]


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	color = wash
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_uniform("drift", drift)
	_set_uniform("wash", wash)
	_set_uniform("opacity", pattern_opacity)
	_apply_pattern()
	_update_rect_size()
	resized.connect(_update_rect_size)
	_hook_reduced_motion()
	# W13-C: sanfter Gyro-/Pointer-Parallax auf dem Pattern (gyro_parallax.gd).
	GyroParallax.registriere(self)


func set_pattern_by_name(name_without_prefix: String) -> void:
	pattern = name_without_prefix


## W13-C Parallax-Senke (GyroParallax): px → Kachel-UV, in den Shader.
func set_parallax_offset(offset_px: Vector2) -> void:
	_set_uniform("parallax_uv", offset_px * (_tile_count / maxf(size.x, 1.0)))


func _apply_pattern() -> void:
	if _mat == null:
		return
	var path := "%spattern_%s.png" % [PATTERN_DIR, pattern]
	if not ResourceLoader.exists(path):
		push_warning("Wallpaper-Pattern fehlt: %s" % path)
		return
	_set_uniform("tile", load(path))


func _update_rect_size() -> void:
	_set_uniform("rect_size", size)
	# Kachelgröße Web-treu: 384 Design-px pro Kachel — Design-px → Canvas-px
	# über die ZENTRALE UiScale-Regel (FIX1), nie eigene Pixelwerte.
	if not is_inside_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	_tile_count = maxf(size.x / (TILE_DESIGN_PX * f), 0.5)
	_set_uniform("tile_count", _tile_count)


func _set_uniform(uniform: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(uniform, value)


func _hook_reduced_motion() -> void:
	var svc := get_node_or_null("/root/UiTheme")
	if svc == null:
		return
	if svc.has_signal("reduced_motion_changed"):
		svc.reduced_motion_changed.connect(_on_reduced_motion_changed)
	if "reduced_motion" in svc:
		_on_reduced_motion_changed(svc.reduced_motion)


func _on_reduced_motion_changed(enabled: bool) -> void:
	_set_uniform("motion_scale", 0.0 if enabled else 1.0)
