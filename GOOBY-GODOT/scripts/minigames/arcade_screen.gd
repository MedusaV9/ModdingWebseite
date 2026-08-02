class_name ArcadeScreen
extends Control
## Arcade-Grid: Cover-Kacheln aller Spiele (+ „Bald!“-Platzhalter). Die
## Cover der spielbaren Spiele sind via preload() COMPILE-ZEITIG geladen —
## der Web-Bug „alte Icons flackern beim Öffnen“ kann so nicht wiederkehren.
## Tap → Pregame → Host. HUD-Verdrahtung (W1c-API): der Home-Besitzer
## verbindet hud.action_pressed mit ArcadeScreen.handle_hud_action.
##
## FIX1 (P0 „Arcade sieht komisch/buggy aus, Cover ohne Smoothing“):
## - Cover-Kacheln filtern mit LINEAR_WITH_MIPMAPS (Import der Cover-PNGs
##   generiert jetzt Mipmaps) — kein Kanten-Flimmern beim Herunterskalieren.
## - Das Grid ist RESPONSIV: Spaltenzahl aus der verfügbaren Breite
##   (`grid_columns`, pure), Kacheln füllen die Zeile statt links zu kleben.
## - Safe-Area-Ränder + zentrale `UiScale`-Skalierung; kein Quer-Scrollen.

signal game_selected(game_id: String)
signal back_requested

## Compile-zeitige Cover (Konvention: res://assets/covers/<id>.png).
## Neue Spiele: Zeile ergänzen — ResourceLoader-Fallback unten fängt
## vergessene Einträge ab (lädt synchron, KEIN Flackern, nur langsamer).
## Auch „Bald!“-Kacheln (gobnom) preloaden: echtes Cover statt „?“-Karte.
const COVERS := {
	"teaParty": preload("res://assets/covers/teaParty.png"),
	"carrotCatch": preload("res://assets/covers/carrotCatch.png"),
	"gvz": preload("res://assets/covers/gvz.png"),
	"gobnom": preload("res://assets/covers/gobnom.png"),
}

const ROUTE_ARCADE := &"arcade"
const ROUTE_PREGAME := &"mg_pregame"
const ROUTE_HOST := &"mg_host"

const ROUTES := {
	ROUTE_ARCADE: "res://scripts/minigames/arcade_screen.tscn",
	ROUTE_PREGAME: "res://scripts/minigames/pregame.tscn",
	ROUTE_HOST: "res://scripts/minigames/minigame_host.tscn",
}

## FIX1-Grid-Geometrie (Design-px, skalieren mit dem UiScale-Faktor).
const TILE_MIN_WIDTH := 230.0
const TILE_HEIGHT := 240.0
const GRID_GAP := 16.0
const MIN_COLUMNS := 2
const MAX_COLUMNS := 5
## Inhaltsspalte W16: eigene Grid-Basis (breiter als die 660er Standard-
## Spalte, damit das Cover-Raster nicht ausdünnt) — auf iPad/Quer rücken
## die Kacheln damit zur Mitte, der Wallpaper bleibt vollflächig.
const CONTENT_BASE_WIDTH := 880.0

## Tests: Navigation abschaltbar.
var auto_navigate := true

var _grid: GridContainer
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _back: Button


## Arcade-Routen am SceneRouter anmelden (idempotent). Der Home-Besitzer /
## Orchestrator ruft das einmal beim Boot (oder via handle_hud_action).
static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("register_routes"):
		return
	router.register_routes(ROUTES)
	# G7-Playtest Befund 1: Pregame/Host sind Durchgangs-Stationen und
	# dürfen nie in der Router-History liegen — sonst startet der Arcade-
	# Zurück-Knopf (back()) eine frische Runde statt nach Hause zu führen.
	if router.has_method("markiere_fluechtig"):
		router.markiere_fluechtig([ROUTE_PREGAME, ROUTE_HOST])


## EIN Verdrahtungspunkt für den HUD-Arcade-Button (W1c action_pressed):
##   hud.action_pressed.connect(ArcadeScreen.handle_hud_action)
## Liefert true, wenn die Action konsumiert wurde.
static func handle_hud_action(action: StringName) -> bool:
	if action != &"arcade":
		return false
	register_routes()
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return false
	router.goto(ROUTE_ARCADE, {})
	return true


func _ready() -> void:
	# E14-P0: and_offsets — nur Anker setzen behält unter dem Router-Mount
	# das 0×0-Rect (Offsets werden aufs aktuelle Rect zurückgerechnet).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_build_ui()
	get_viewport().size_changed.connect(_apply_metrics)
	_apply_metrics()
	# A1 Sternenbuch: fällige Meilensteine rückwirkend claimen und feiern —
	# idempotent (beim zweiten Öffnen passiert nichts mehr). Deferred, damit
	# Layout/Toast-Layer der Ankunft schon stehen.
	_claim_sternenbuch_meilensteine.call_deferred()


## Spaltenzahl aus verfügbarer Breite (pure, FIX1-Test): so viele Kacheln
## mit Mindestbreite TILE_MIN_WIDTH×f passen nebeneinander, 2..5 Spalten.
static func grid_columns(avail_width: float, f: float) -> int:
	var tile := TILE_MIN_WIDTH * maxf(f, 0.01)
	var gap := GRID_GAP * maxf(f, 0.01)
	if avail_width <= 0.0:
		return MIN_COLUMNS
	var cols := int(floorf((avail_width + gap) / (tile + gap)))
	return clampi(cols, MIN_COLUMNS, MAX_COLUMNS)


func _build_ui() -> void:
	# W14: AC-Wallpaper mit Arcade-Stimmung (Web-V6-Themenblock) statt
	# nacktem ColorRect — derselbe Drift-Hintergrund wie Profil/Album.
	add_child(AcWallpaper.for_context("arcade"))
	_rows = VBoxContainer.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rows.offset_left = 24.0
	_rows.offset_right = -24.0
	_rows.offset_top = 16.0
	_rows.offset_bottom = -16.0
	# W14: 8er-Raster (12 war rasterfremd).
	_rows.add_theme_constant_override("separation", 16)
	add_child(_rows)

	# W14: Kopfzeilen-Konsistenz — Zurück links (GhostButton), Titel mittig,
	# rechts die Zähler-Kapsel (spielbare Spiele) wie die Album-Kopfzeile.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_rows.add_child(header)
	# QW #3: SquishButton statt nacktem Button — Press-Squish + Haptik
	# laufen zentral, Theme-Variation/Signale bleiben identisch.
	_back = SquishButton.new()
	_back.theme_type_variation = &"GhostButton"
	_back.text = I18nService.t("mg.arcade.back")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_on_back_pressed)
	header.add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.text = I18nService.t("mg.arcade.title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_title)
	header.add_child(_build_count_capsule())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# FIX1: nie quer scrollen — das Grid passt sich der Breite an; und
	# Touch-Deadzone, damit Wischen nicht sofort als Tile-Tap zählt.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 24
	# B1 (G8-PT3): Kachel-Buttons fressen den Touch-Drag — der zentrale
	# DragScroll-Helfer pannt ab der Schwelle selbst (Taps unverändert).
	DragScroll.anbinden(_scroll)
	_rows.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	_scroll.add_child(_grid)
	# MG-3: all_games() statt GAMES — sonst fehlen alle per game.json-Manifest
	# entdeckten Spiele (W6-Registry) im Grid.
	var tiles: Array = []
	for game in MinigameRegistry.all_games():
		var tile := _build_tile(game)
		_grid.add_child(tile)
		tiles.append(tile)
	# FB3-Polish: Kacheln federn gestaffelt ein (Web-Stagger) statt zu ploppen.
	UiMotion.stagger_in(tiles, 0.03)


## W14: Zähler-Kapsel rechts in der Kopfzeile — StatusCapsule wie im Album;
## hält der Kopfzeile zugleich die Mitte (Titel bleibt mittig).
## A1 Sternenbuch: die Kapsel ist jetzt der Sammel-Zähler — Spielezahl
## bleibt (flow_pt3_rahmen prüft sie), dazu der Sterne-Stand „n/114 ★“.
func _build_count_capsule() -> Control:
	var capsule := PanelContainer.new()
	capsule.name = "CountCapsule"
	capsule.theme_type_variation = &"StatusCapsule"
	capsule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.name = "CountLabel"
	label.theme_type_variation = &"SoftLabel"
	var playable := 0
	var games := MinigameRegistry.all_games()
	for game: Dictionary in games:
		if not bool(game.get("coming_soon", false)):
			playable += 1
	label.text = (
		I18nService
		. t(
			"mg.arcade.zaehler_sterne",
			{
				"n": playable,
				"sterne": ArcadeSternenbuch.gesamt_sterne(_lese_state(), games),
				"max": ArcadeSternenbuch.max_sterne(games),
			}
		)
	)
	capsule.add_child(label)
	return capsule


## Responsive Metriken (FIX1): Safe-Area-Ränder, UiScale-Faktor,
## Spaltenzahl aus der Breite — läuft bei Resize/Rotation erneut.
## W16-Inhaltsspalte (Galerie-Muster): _rows liegt als zentrierte,
## breiten-gedeckelte Spalte (eigene Basis CONTENT_BASE_WIDTH) im
## Safe-Rechteck; die Spaltenzahl rechnet mit der SPALTEN-Breite statt
## der vollen Canvas-Breite. Der Wallpaper bleibt vollflächig.
func _apply_metrics() -> void:
	if _rows == null or _grid == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var m := ScreenShell.metrics(vp)
	var f: float = m["f"]
	ScreenShell.content_frame(_rows, m, CONTENT_BASE_WIDTH)
	var gap := int(GRID_GAP * f)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	_grid.columns = grid_columns(ScreenShell.content_width(m, CONTENT_BASE_WIDTH), f)
	# FB3: Touch-Floor auf BEIDEN Achsen + Schriften über die zentrale
	# Regel (vorher skalierte nur der Titel, Kachel-Labels blieben klein).
	ScreenShell.touch_target(_back, m)
	ScreenShell.scale_fonts(self, f)
	for tile in _grid.get_children():
		(tile as Control).custom_minimum_size = Vector2(0.0, TILE_HEIGHT * f)


func _build_tile(game: Dictionary) -> Control:
	var id: String = game["id"]
	var coming_soon: bool = game.get("coming_soon", false)
	# QW #3: Kacheln squishen + vibrieren wie alle AC-Buttons.
	var tile: Button = SquishButton.new()
	tile.name = "Tile_%s" % id
	# E7-P0-3: FIX-As Button-taugliche Karten-Variation. `AcCard` ist eine
	# PanelContainer-Variation — auf einem Button fiel sie still auf die
	# Pill-Basis zurück (Radius 999 → weiße Ellipsen).
	tile.theme_type_variation = &"AcCardButton"
	# FIX1: Kacheln füllen die Zeile (Spaltenzahl macht _apply_metrics) —
	# feste Höhe, Breite kommt vom Grid.
	tile.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.disabled = coming_soon
	if not coming_soon:
		tile.pressed.connect(_on_tile_pressed.bind(id))
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# W14: Kachel-Innenabstand aufs 4er-Subraster (vorher 10 — rasterfremd).
	content.offset_left = 12.0
	content.offset_right = -12.0
	content.offset_top = 12.0
	content.offset_bottom = -12.0
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(content)
	var cover := _build_cover(id, coming_soon)
	content.add_child(cover)
	# FERTIG-1 (EVAL Rang 12): läuft ein Modifier-Event für dieses Spiel,
	# trägt die Kachel ein sichtbares Bonus-Badge (Name · Restzeit).
	if not coming_soon:
		_add_modifier_badge(cover, id)
	var label := Label.new()
	label.text = I18nService.t(str(game.get("title_key", id)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# FIX1: lange Titel werden mit „…“ gekürzt statt hart abgeschnitten.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(label)
	# A1 Sternenbuch: Sterne-Pips + Bestwert-Zeile aus minigames.legacy —
	# reines Lesen, füllt sich rückwirkend aus dem vorhandenen Save.
	if not coming_soon:
		content.add_child(_build_sternenzeile(id))
	return tile


## A1 Kachel-Zeile: Pips links (0..3 Sterne), Bestwert rechts — der
## Bestwert erscheint erst, wenn es einen gibt (Endlos zählt nicht mit).
func _build_sternenzeile(id: String) -> Control:
	var state := _lese_state()
	var zeile := HBoxContainer.new()
	zeile.name = "Sternenzeile"
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips := ArcadeSternenbuch.SternPips.new()
	pips.name = "SternPips"
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.setup(ArcadeSternenbuch.sterne_fuer(state, id))
	zeile.add_child(pips)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(spacer)
	var best := ArcadeSternenbuch.bestwert_fuer(state, id)
	if best > 0:
		var best_label := Label.new()
		best_label.name = "BestwertLabel"
		best_label.theme_type_variation = &"SoftLabel"
		best_label.text = I18nService.t("mg.arcade.bestwert", {"best": best})
		# BEWUSST ohne Ellipsis-Trim: der kollabiert die Mindestbreite auf 0
		# und der EXPAND-Spacer links quetscht das Label unsichtbar (Befund
		# flow_arcade/017). Bestwerte sind kurze Zahlen — natürliche Breite.
		best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zeile.add_child(best_label)
	return zeile


## Save-Stand für die Sternenbuch-Anzeigen ({} ohne GameState — Tests).
func _lese_state() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("state"):
		return gs.state()
	return {}


## A1: fällige Meilensteine claimen (idempotent über
## minigames.sternenbuch.claimed) und im Gooby-Look feiern — Toast über die
## RewardHub-ToastLayer (Gruppe toast_layer), Konfetti + Levelup-Pluck.
func _claim_sternenbuch_meilensteine() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update") or gs.get("clock") == null:
		return
	var games := MinigameRegistry.all_games()
	var now := int(gs.clock.now_ms())
	var holder: Array[Dictionary] = []
	gs.update(
		func(state: Dictionary) -> void:
			holder.append(ArcadeSternenbuch.claim_meilensteine(state, games, now))
	)
	var folge: Dictionary = holder[0] if holder.size() > 0 else {}
	var neu: Array = folge.get("neu", [])
	if neu.is_empty():
		return
	ToastLayer.zeige(
		self,
		I18nService.t(
			"mg.arcade.meilenstein_toast",
			{"n": int(neu.back()), "coins": int(folge.get("coins", 0))}
		)
	)
	AudioDirector.try_play(self, "ui_levelup")
	RewardFx.konfetti_2d(self, 40, size.x)


## FERTIG-1 (EVAL Rang 12): Bonus-Badge auf der Ziel-Kachel des aktiven
## Modifier-Events ("Doppel-Gold · 42:10") — die Web-Arcade-Bubble.
func _add_modifier_badge(cover: Control, id: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("state") or gs.get("clock") == null:
		return
	var now := int(gs.clock.now_ms())
	var active := ModifierEngine.get_active_for(gs.state(), id, now)
	if active.is_empty():
		return
	var badge := Label.new()
	badge.name = "ModifierBadge"
	badge.text = (
		I18nService
		. t(
			"modifier.badge",
			{
				"name": I18nService.t(str(active["name_key"])),
				"rest": ModifierEngine.countdown_text(int(active["endsAt"]), now),
			}
		)
	)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	var style := StyleBoxFlat.new()
	var badge_color: Color = active.get("color", Color(1.0, 0.83, 0.3))
	style.bg_color = Color(badge_color.r, badge_color.g, badge_color.b, 0.92)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	badge.add_theme_stylebox_override("normal", style)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(badge)


## Dieselbe Textur-Instanz für Kachel UND LoadingVeil-Cover-Karte
## (W4/POLISH-17: kein Doppel-Load, kein Flackern).
static func cover_texture(id: String) -> Texture2D:
	var texture: Texture2D = COVERS.get(id)
	if texture == null:
		# Fallback-Konvention: assets/covers/<id>.png — synchron geladen.
		var path := MinigameRegistry.cover_path(id)
		if ResourceLoader.exists(path):
			texture = load(path)
	return texture


func _build_cover(id: String, coming_soon: bool) -> Control:
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := cover_texture(id)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# FIX1 „kein Smoothing“: Cover werden stark herunterskaliert —
		# ohne Mipmaps flimmern die Kanten (Import generiert sie jetzt).
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if coming_soon:
			rect.modulate = Color(0.6, 0.6, 0.6)
		frame.add_child(rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.87, 0.8, 0.72)
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(placeholder)
		var mark := Label.new()
		mark.text = "?"
		mark.theme_type_variation = &"TitleLabel"
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
		mark.grow_vertical = Control.GROW_DIRECTION_BOTH
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(mark)
	if coming_soon:
		var badge := Label.new()
		badge.text = I18nService.t("mg.arcade.coming_soon")
		badge.theme_type_variation = &"HeadlineLabel"
		badge.add_theme_color_override("font_color", Color(0.95, 0.45, 0.66))
		badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
		badge.grow_vertical = Control.GROW_DIRECTION_BOTH
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.rotation_degrees = -8.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(badge)
	return frame


func _on_tile_pressed(id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	game_selected.emit(id)
	if not auto_navigate:
		return
	# Veil-Kontext für die ganze Kette Arcade→Pregame→Host: Cover-Karte mit
	# Titel + Tipps statt Standard-Gooby (W4/POLISH-3+17). Der Hint räumt
	# sich beim nächsten Nicht-Minigame-Ziel selbst auf.
	var game := MinigameRegistry.get_game(id)
	var hint := {
		"game_id": id,
		"title": I18nService.t(str(game.get("title_key", id))),
		"cover": cover_texture(id),
		"targets": [ROUTE_PREGAME, ROUTE_HOST],
	}
	LoadingVeil.set_travel_hint(hint)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(ROUTE_PREGAME, {"game_id": id})


func _on_back_pressed() -> void:
	back_requested.emit()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	# Sheet zuerst (eine Geste = ein Panel). Danach IMMER die Arcade
	# verlassen — handle_back_request() darf das NICHT schlucken, weil es
	# bei Router._busy true zurückgibt ohne zu navigieren (H4-Befund).
	if PanelStack.count() > 0:
		PanelStack.close_top()
		return
	var used_history := false
	if router.has_method("can_go_back") and router.can_go_back() and router.has_method("back"):
		used_history = bool(router.back())
	if used_history:
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
