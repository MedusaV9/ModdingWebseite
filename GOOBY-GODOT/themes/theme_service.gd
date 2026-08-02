class_name ThemeService
extends Node
## Laufzeit-Service fürs AC-2.0-Theme. Als Autoload „UiTheme“ gedacht
## (Registrierung macht W1a — siehe handoffs/W1c-autoload-requests.md),
## funktioniert aber auch ohne Autoload über die statischen Methoden.
##
## THEME-ZUSTELLUNG (FIX-A, E7-P0-2/E5-F0): Primärweg ist das
## PROJEKT-DEFAULT-Theme `gui/theme/custom = res://themes/ac_theme.tres`
## in project.godot — nur das erreicht auch Controls unter CanvasLayer und
## SubViewport (Window-Themes propagieren dort NICHT durch). Das
## `apply_to_window()`-Root-Set hier bleibt als Fallback für Läufe ohne
## project.godot-Eintrag (z. B. isolierte Test-SceneTrees). Kein Konflikt:
## beide Wege laden dieselbe .tres-Ressource (Resource-Cache ⇒ selbe
## Instanz), Godots Lookup-Reihenfolge Control→Window→Projekt-Default
## findet so immer denselben Wertesatz.
##
## Aufgaben: Theme auf den Root anwenden, ClearColor = BG_CREAM setzen,
## Token-Zugriff (`color()`, `font()`), Reduced-Motion-Zustand verteilen.

signal reduced_motion_changed(enabled: bool)

const THEME_PATH := "res://themes/ac_theme.tres"

static var _cached_theme: Theme
static var _font_cache: Dictionary = {}

## Globaler Motion-Schalter: Wallpaper-Drift, Squish-Tweens etc. hören darauf.
var reduced_motion := false:
	set(value):
		if reduced_motion == value:
			return
		reduced_motion = value
		reduced_motion_changed.emit(value)


func _ready() -> void:
	apply_to_window(get_tree().root)


## Theme + Cream-ClearColor auf ein Window anwenden (Root oder Popups).
func apply_to_window(window: Window) -> void:
	window.theme = theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)


## Das AC-Theme (aus .tres, sonst live gebaut — z. B. in Tests ohne Import).
static func theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme
	if ResourceLoader.exists(THEME_PATH):
		_cached_theme = load(THEME_PATH)
	if _cached_theme == null:
		var builder := load("res://themes/build_theme.gd") as GDScript
		_cached_theme = builder.build()
	return _cached_theme


## Farb-Token per Name („PINK“, „INK_SOFT“ …); unbekannt → Magenta + Error.
static func color(token: String) -> Color:
	if not AcTokens.COLORS.has(token):
		push_error("Unbekanntes Farb-Token: %s" % token)
		return Color.MAGENTA
	return AcTokens.COLORS[token]


## Baloo-2 in einem bestimmten Gewicht (600 Body / 700 Buttons / 800 Headlines).
static func font(weight: int = 600) -> Font:
	if _font_cache.has(weight):
		return _font_cache[weight]
	var base: Font = load(AcTokens.FONT_PATH)
	if base == null:
		return ThemeDB.fallback_font
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {"wght": weight}
	_font_cache[weight] = v
	return v


## Duck-Typing-Helfer: Reduced-Motion-Zustand, egal ob Autoload existiert.
## BAUM-SICHER (G8-PT4 B8 / PT2 B7): SquishButton._on_up läuft NACH dem
## pressed-Handler — hat der die Ansicht samt Knopf schon abgebaut (z. B.
## PhoneShell._leere_inhalt beim App-Öffnen), ist from_node draußen und
## ein absoluter get_node-Pfad loggt „Can't use get_node() with absolute
## paths from outside the active scene tree“. Dann über den MainLoop-Root
## nachschlagen (Muster Haptics._settings/_tree).
static func is_reduced_motion(from_node: Node) -> bool:
	var svc: Node = null
	if from_node != null and from_node.is_inside_tree():
		svc = from_node.get_node_or_null("/root/UiTheme")
	else:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			svc = (loop as SceneTree).root.get_node_or_null("UiTheme")
	if svc != null and "reduced_motion" in svc:
		return svc.reduced_motion
	return false
