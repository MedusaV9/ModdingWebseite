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
##
## W20 (Top-10 #4 „Arcade-Kacheln erzählen Fortschritt“): die Einheitswand
## ist jetzt in beschriftete KATEGORIEN-REIHEN gegliedert (je Reihe ein
## eigenes Grid unter einem Header — Zuordnung/Regeln: ArcadeFortschritt),
## jede Kachel trägt eine stille 3-Sterne-Zeile unter dem Cover (Save-Daten
## plays/beaten/best) und die Kopfzeile zeigt „n/38 gespielt · m Sterne“.
## Der W18-Wisch-Pan bleibt unverändert: EIN ScrollContainer, alle Reihen
## in einer VBox, Kacheln weiter auf MOUSE_FILTER_PASS.

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

## W20: erstes Reihen-Grid — Vertrags-Feld für die Playtest-Flows
## (flow_arcade_wisch liest `_grid` für den Kachel-Wisch-Start).
var _grid: GridContainer
## W20: ALLE Reihen-Grids (eines je Kategorien-Reihe, Reihenfolge = Wand).
var _grids: Array[GridContainer] = []
var _rows: VBoxContainer
var _scroll: ScrollContainer
## W21/P4 (e): EIN Blatt-Kopf (AcnhKit.blatt_kopf) statt handgebauter
## Kopfzeile — _title/_back zeigen auf seine Slots (Bestands-Verträge).
var _header: AcScreenHeader
var _title: Label
var _back: Button
## W20: Gesamt-Fortschritts-Kopfzeile („n/38 gespielt · m Sterne“).
var _fortschritt: Label
## W18 Befund B5 (eigener Wisch-Pan, s. _on_scroll_gui_input): Gesten-Status.
var _pan_druck := false
var _pan_aktiv := false
var _pan_summe := 0.0
var _pan_start := 0.0
## W19/SPOTLIGHT: das „Spiel des Tages“ dieses Aufbaus + sein Gold-Rahmen.
var _spotlight_id := ""
var _spotlight_glow: Control = null


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

	# W21/P4 (e) Hierarchie: der Screen-TITEL führt — die EINE Kopfzeilen-
	# Grammatik (AcnhKit.blatt_kopf: Zurück-Pill links, Titel zentriert,
	# Zähler-Kapsel rechts) statt der handgebauten W14-Kopfzeile.
	_header = AcnhKit.blatt_kopf(I18nService.t("mg.arcade.title"), _on_back_pressed)
	_rows.add_child(_header)
	_back = _header.back_button
	_back.focus_mode = Control.FOCUS_NONE
	_title = _header.title_label
	_header.add_chip(_build_count_capsule())

	# W20 (c): kleine Gesamt-Fortschritts-Zeile unter der Kopfzeile —
	# aggregiert aus denselben Save-Feldern wie die Kachel-Sterne.
	_fortschritt = Label.new()
	_fortschritt.name = "FortschrittZeile"
	_fortschritt.theme_type_variation = &"SoftLabel"
	_fortschritt.text = _fortschritt_text()
	_fortschritt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(_fortschritt)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# FIX1: nie quer scrollen — das Grid passt sich der Breite an; und
	# Touch-Deadzone, damit Wischen nicht sofort als Tile-Tap zählt.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 24
	# W18 Befund B5: eigener Wisch-Pan im gui_input-SIGNAL (feuert VOR der
	# eingebauten ScrollContainer-Verarbeitung, s. _on_scroll_gui_input).
	_scroll.gui_input.connect(_on_scroll_gui_input)
	_rows.add_child(_scroll)
	# W20 (b): EINE Spalte aus Kategorien-Reihen (Header + eigenes Grid je
	# Reihe) statt der Einheitswand. Der Scroll bleibt derselbe — der
	# W18-Wisch-Pan (s. o.) sieht weiter alle Gesten.
	var spalte := VBoxContainer.new()
	spalte.name = "ReihenSpalte"
	spalte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spalte.add_theme_constant_override("separation", 12)
	_scroll.add_child(spalte)
	# W19/SPOTLIGHT: „Spiel des Tages“ EINMAL pro Aufbau bestimmen (über die
	# injizierte GameState-Uhr) — die Kacheln markieren sich damit selbst.
	_spotlight_id = _spotlight_heute()
	# MG-3: all_games() statt GAMES — sonst fehlen alle per game.json-Manifest
	# entdeckten Spiele (W6-Registry) im Grid.
	var state := _lies_state()
	var tiles: Array = []
	_grids = []
	for reihe: Dictionary in ArcadeFortschritt.reihen(MinigameRegistry.all_games()):
		var kopf := Label.new()
		kopf.name = "ReihenHeader_%s" % reihe["key"]
		# W21/P4 (e): Reihen-Header EINE Skalen-Stufe UNTER dem Screen-Titel
		# (SIZE_TITLE 28 → SIZE_BUTTON 22, Soft-Ink) — vorher stand er als
		# HeadlineLabel (34) ÜBER dem Titel: Hierarchie invertiert.
		kopf.theme_type_variation = &"SoftLabel"
		kopf.add_theme_font_size_override("font_size", AcTokens.SIZE_BUTTON)
		kopf.text = I18nService.t(str(reihe["titel_key"]))
		spalte.add_child(kopf)
		var grid := GridContainer.new()
		grid.name = "ReihenGrid_%s" % reihe["key"]
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# B5: Drags aus den Kachel-Lücken müssen ebenfalls bis zum Scroll
		# durchbubblen (PASS ist Container-Default — explizit als Vertrag).
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		spalte.add_child(grid)
		for game: Dictionary in reihe["games"]:
			var tile := _build_tile(game, state)
			grid.add_child(tile)
			tiles.append(tile)
		_grids.append(grid)
	_grid = _grids[0] if not _grids.is_empty() else null
	# FB3-Polish: Kacheln federn gestaffelt ein (Web-Stagger) statt zu ploppen.
	UiMotion.stagger_in(tiles, 0.03)
	_starte_spotlight_puls()


## W18 Befund B5 „Arcade-Grid scrollt nicht per Touch-Wisch“: die Wurzel
## ist doppelt. (1) Die Kachel-Buttons stehen auf dem Button-Default
## MOUSE_FILTER_STOP — der Viewport bricht das Event-Bubbling an STOP ab
## (viewport.cpp _gui_call_input), Press UND Drag enden an der Kachel, der
## eingebaute ScrollContainer-Pan sieht die Geste NIE; `scroll_deadzone`
## kam also gar nicht erst zum Zug. (2) Der eingebaute Pan startet
## überhaupt nur bei DisplayServer.is_touchscreen_available() — unter
## xvfb/Desktop (Playtest-Harness) nie. Deshalb: Kacheln auf PASS (Events
## erreichen den Scroll, Taps bleiben beim Button) + DIESER Pan im
## gui_input-SIGNAL des Scrolls (das Signal feuert VOR der eingebauten
## Verarbeitung; accept_event() verhindert Doppel-Pan auf echten
## Touch-Geräten — PanelSheet-Muster). Ab scroll_deadzone gehört die Geste
## dem Scroll: NOTIFICATION_SCROLL_BEGIN löst den Press-Versuch der Kachel
## (BaseButton-Standard), Taps unter der Deadzone feuern weiter normal.
func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pan_druck = true
			_pan_aktiv = false
			_pan_summe = 0.0
			_pan_start = float(_scroll.scroll_vertical)
		else:
			if _pan_aktiv:
				_scroll.propagate_notification(NOTIFICATION_SCROLL_END)
			_pan_druck = false
			_pan_aktiv = false
		_scroll.accept_event()
		return
	if not (event is InputEventMouseMotion) or not _pan_druck:
		return
	var mm := event as InputEventMouseMotion
	if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	_pan_summe += mm.relative.y
	if not _pan_aktiv and absf(_pan_summe) > float(_scroll.scroll_deadzone):
		_pan_aktiv = true
		_scroll.propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		# Weicher Einstieg: ab der Deadzone zählt nur der weitere Weg.
		_pan_start = float(_scroll.scroll_vertical)
		_pan_summe = mm.relative.y
	if _pan_aktiv:
		_scroll.scroll_vertical = int(roundf(_pan_start - _pan_summe))
		_scroll.accept_event()


## W14: Zähler-Kapsel rechts in der Kopfzeile („n Spiele“) — StatusCapsule
## wie im Album; hält der Kopfzeile zugleich die Mitte (Titel bleibt mittig).
func _build_count_capsule() -> Control:
	var capsule := PanelContainer.new()
	capsule.name = "CountCapsule"
	capsule.theme_type_variation = &"StatusCapsule"
	capsule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.name = "CountLabel"
	label.theme_type_variation = &"SoftLabel"
	var playable := 0
	for game: Dictionary in MinigameRegistry.all_games():
		if not bool(game.get("coming_soon", false)):
			playable += 1
	label.text = I18nService.t("mg.arcade.zaehler", {"n": playable})
	capsule.add_child(label)
	return capsule


## W20: Save-State fürs Sterne-Rechnen — ohne GameState (reine UI-Tests)
## leer, dann zeigen alle Kacheln 0 Sterne (Muster _add_modifier_badge).
func _lies_state() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("state"):
		return {}
	return gs.state()


## W20 (c): Text der Gesamt-Fortschritts-Zeile („n/38 gespielt · m Sterne“
## — Einzahl-Key gegen „1 Sterne“). Aggregation: ArcadeFortschritt.gesamt.
func _fortschritt_text() -> String:
	var g := ArcadeFortschritt.gesamt(_lies_state(), MinigameRegistry.all_games())
	var key := "mg.arcade.fortschritt.kopf"
	if int(g["sterne"]) == 1:
		key = "mg.arcade.fortschritt.kopf_einzahl"
	return I18nService.t(
		key, {"n": int(g["gespielt"]), "total": int(g["total"]), "sterne": int(g["sterne"])}
	)


## Responsive Metriken (FIX1): Safe-Area-Ränder, UiScale-Faktor,
## Spaltenzahl aus der Breite — läuft bei Resize/Rotation erneut.
## W16-Inhaltsspalte (Galerie-Muster): _rows liegt als zentrierte,
## breiten-gedeckelte Spalte (eigene Basis CONTENT_BASE_WIDTH) im
## Safe-Rechteck; die Spaltenzahl rechnet mit der SPALTEN-Breite statt
## der vollen Canvas-Breite. Der Wallpaper bleibt vollflächig.
func _apply_metrics() -> void:
	if _rows == null or _grids.is_empty():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var m := ScreenShell.metrics(vp)
	var f: float = m["f"]
	ScreenShell.content_frame(_rows, m, CONTENT_BASE_WIDTH)
	var gap := int(GRID_GAP * f)
	# W20: alle Reihen-Grids teilen dieselbe Spaltenzahl/Gaps — die Wand
	# bleibt ein durchgehendes Raster, nur eben mit Header-Zeilen.
	var cols := grid_columns(ScreenShell.content_width(m, CONTENT_BASE_WIDTH), f)
	for grid in _grids:
		grid.add_theme_constant_override("h_separation", gap)
		grid.add_theme_constant_override("v_separation", gap)
		grid.columns = cols
		for tile in grid.get_children():
			(tile as Control).custom_minimum_size = Vector2(0.0, TILE_HEIGHT * f)
	# FB3: Touch-Floor auf BEIDEN Achsen + Schriften über die zentrale
	# Regel (vorher skalierte nur der Titel, Kachel-Labels blieben klein).
	# W21/P4 (e): der Blatt-Kopf hält seine Slots selbst symmetrisch.
	_header.apply_metrics(m)
	ScreenShell.scale_fonts(self, f)


func _build_tile(game: Dictionary, state: Dictionary) -> Control:
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
	# W18 B5: PASS statt Button-Default STOP — Drags über der Kachel
	# erreichen so den ScrollContainer (s. _on_scroll_gui_input); der Tap
	# bleibt beim Button (unter der Deadzone feuert pressed wie bisher).
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.disabled = coming_soon
	if not coming_soon:
		tile.pressed.connect(_on_tile_pressed.bind(id))
		# W21/P4 (e): Hover-Lift (Maus/Trackpad) — den Press-Squish macht
		# SquishButton zentral, der Lift kommt aus der MotionKit-Grammatik.
		tile.mouse_entered.connect(_on_tile_hover.bind(tile, true))
		tile.mouse_exited.connect(_on_tile_hover.bind(tile, false))
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
	# W19/SPOTLIGHT: das Spiel des Tages hebt sich sichtbar heraus.
	if not coming_soon and id == _spotlight_id:
		_add_spotlight_markierung(tile, cover)
	# W20 (a): stille Sterne-Zeile UNTER dem Cover (in-flow, vor dem Titel)
	# — kollidiert konstruktiv nie mit dem Spotlight-Banner (Cover-
	# UNTERkante) oder dem Modifier-Badge (Cover-OBERkante), die beide als
	# Overlays IM Cover-Frame darüber leben. Regel: ArcadeFortschritt.
	if not coming_soon:
		content.add_child(SterneZeile.new(ArcadeFortschritt.sterne(state, game)))
	var label := Label.new()
	label.text = I18nService.t(str(game.get("title_key", id)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# FIX1: lange Titel werden mit „…“ gekürzt statt hart abgeschnitten.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(label)
	return tile


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


## W19/SPOTLIGHT: das „Spiel des Tages“ — deterministisch über die
## INJIZIERTE GameState-Uhr (Clock-Muster wie _add_modifier_badge, nie die
## OS-Uhr direkt). Ohne GameState (reine UI-Tests) gibt es kein Spotlight.
func _spotlight_heute() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.get("clock") == null:
		return ""
	return ArcadeSpotlight.spotlight_id(MinigameRegistry.all_games(), gs.clock.local_day())


## Spotlight-Kachel sichtbar herausheben: Gold-Rahmen (Glow) über der
## ganzen Kachel + „Spiel des Tages“-Banner an der Cover-Unterkante. Beides
## sind reine Anker-Overlays (Muster ModifierBadge oben am Cover) — sie
## melden KEINE Min-Größe ans Grid, das Layout bleibt in quer wie hochkant
## unverändert (die Zentrier-/UI-Wache sieht dieselbe Geometrie).
func _add_spotlight_markierung(tile: Control, cover: Control) -> void:
	var glow := Panel.new()
	glow.name = "SpotlightGlow"
	var rahmen := StyleBoxFlat.new()
	rahmen.draw_center = false
	rahmen.border_color = AcTokens.GOLD
	rahmen.set_border_width_all(4)
	rahmen.set_corner_radius_all(22)
	glow.add_theme_stylebox_override("panel", rahmen)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(glow)
	_spotlight_glow = glow
	var badge := Label.new()
	badge.name = "SpotlightBadge"
	badge.text = I18nService.t("mg.spotlight.badge")
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Dunkles Braun auf Gold: lesbar auf hellem wie dunklem Cover.
	badge.add_theme_color_override("font_color", Color(0.33, 0.22, 0.05))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(AcTokens.GOLD.r, AcTokens.GOLD.g, AcTokens.GOLD.b, 0.94)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	badge.add_theme_stylebox_override("normal", style)
	# Unterkante des Covers (das ModifierBadge sitzt oben — nie Überlappung).
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(badge)


## Dezenter Puls des Gold-Rahmens (Atmen statt Blinken). Reduced-Motion-
## fair nach dem UiMotion-Muster: reduziert bleibt der Rahmen STATISCH
## voll sichtbar — die Hervorhebung bleibt, nur die Bewegung entfällt.
func _starte_spotlight_puls() -> void:
	if _spotlight_glow == null or not _spotlight_glow.is_inside_tree():
		return
	if UiMotion.reduced(self):
		_spotlight_glow.modulate.a = 1.0
		return
	var tween := _spotlight_glow.create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_spotlight_glow, "modulate:a", 0.45, 0.9)
	tween.tween_property(_spotlight_glow, "modulate:a", 1.0, 0.9)


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


## W21/P4 (e): dezenter Hover-Lift der Kacheln — Skala/Dauer aus der
## MotionKit-Grammatik (PULS_SCALE 1.03 / PULS_S, keine eigenen Zahlen);
## Reduced Motion steht still. Der vorige Lift-Tween wird gekillt, damit
## schnelles Rein/Raus nicht flackert (Tween via Meta statt Feld — je Kachel).
func _on_tile_hover(tile: Control, rein: bool) -> void:
	if MotionKit.reduced(tile) or not tile.is_inside_tree():
		return
	if tile.has_meta(&"hover_tween"):
		var alt: Variant = tile.get_meta(&"hover_tween")
		if alt is Tween and (alt as Tween).is_valid():
			(alt as Tween).kill()
	tile.pivot_offset = tile.size / 2.0
	var ziel := MotionKit.PULS_SCALE if rein else 1.0
	var tween := tile.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(tile, "scale", Vector2.ONE * ziel, MotionKit.PULS_S)
	tile.set_meta(&"hover_tween", tween)


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


## W20 (a): stille Mini-Sterne-Zeile der Kachel — dieselbe Bildsprache wie
## FeelStarRow im Results (Vektor-Stern, Gold-/Leer-Töne), aber bewusst
## OHNE SFX/Tween (38 Kacheln dürfen beim Aufbau nicht klingeln) und
## Kachel-klein. Skaliert sich selbst mit dem zentralen UiScale-Faktor.
class SterneZeile:
	extends Control

	const SLOTS := 3
	## W21/P4 (e): Maße aus dem zentralen Token-Set statt Freihand —
	## Stern-Durchmesser = ICON_S (Inline-Glyphen-Stufe), Lücke = SPACE_XS,
	## Zeilenhöhe = ICON_S + SPACE_XS Luft (BAR_H-Klasse der stillen Zeilen).
	const RADIUS := AcTokens.ICON_S / 2.0
	const GAP := float(AcTokens.SPACE_XS)
	## Farbtöne wie FeelStarRow (FILL/RIM/EMPTY) — EIN Sterne-Look im Spiel.
	const FUELLUNG := Color(1.0, 0.8, 0.2)
	const RAND_TON := Color(0.85, 0.55, 0.1)
	const LEER := Color(0.55, 0.48, 0.42, 0.35)

	var sterne := 0
	var _f := 1.0

	func _init(anzahl: int = 0) -> void:
		name = "SterneZeile"
		sterne = clampi(anzahl, 0, SLOTS)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	func _ready() -> void:
		_apply_metrics()
		get_viewport().size_changed.connect(_apply_metrics)

	func _apply_metrics() -> void:
		if not is_inside_tree():
			return
		_f = UiScale.for_viewport(get_viewport())
		var breite := (SLOTS * RADIUS * 2.0 + (SLOTS - 1) * GAP) * _f
		custom_minimum_size = Vector2(breite, (RADIUS * 2.0 + AcTokens.SPACE_XS) * _f)
		queue_redraw()

	func _draw() -> void:
		var radius := RADIUS * _f
		var gap := GAP * _f
		var total := SLOTS * radius * 2.0 + (SLOTS - 1) * gap
		var start_x := (size.x - total) * 0.5 + radius
		var cy := size.y * 0.5
		for i in SLOTS:
			var mitte := Vector2(start_x + i * (radius * 2.0 + gap), cy)
			if i < sterne:
				_stern(mitte, radius, FUELLUNG, RAND_TON)
			else:
				_stern(mitte, radius * 0.82, Color(0, 0, 0, 0), LEER)

	## 10-Punkte-Sternpolygon (Mathe wie FeelStarRow._draw_star).
	func _stern(mitte: Vector2, radius: float, fuellung: Color, rand_ton: Color) -> void:
		var punkte := PackedVector2Array()
		for i in 10:
			var winkel := -PI * 0.5 + TAU * i / 10.0
			var dist := radius if i % 2 == 0 else radius * 0.45
			punkte.append(mitte + Vector2(cos(winkel), sin(winkel)) * dist)
		if fuellung.a > 0.0:
			draw_colored_polygon(punkte, fuellung)
		draw_polyline(punkte + PackedVector2Array([punkte[0]]), rand_ton, 1.4 * _f)
