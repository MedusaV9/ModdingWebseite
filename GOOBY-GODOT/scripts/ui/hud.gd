class_name Hud
extends Control
## Haupt-HUD mit BEIDEN Layouts:
## - Hochkant P1 „Daumen-Dock“ (Web .g5-hud-btns): Status-Chips oben,
##   Aktions-Kacheln unten MITTIG als 5+4-Raster mit Label unterm Icon —
##   exakt die Web-Referenz (FB3: der alte 9-Knopf-Bogen überlappte sich
##   ab 44-pt-Tippflächen zwangsläufig, s. styles.css-Kommentar V4/FIX-UI).
## - Querformat L1 „Cockpit“: Stats links vertikal, Button-Spalte rechts.
## Wechselt LIVE bei Rotation (hört auf `Viewport.size_changed` — lose
## Kopplung, bis der OrientationService von W1a verdrahtet ist).
##
## W4/POLISH-4-Feinschliff: Status-Kapsel-Tap öffnet das Stat-Detail-Sheet
## (`hud_status_sheet.gd`), Level-Ring (`hud_progress_ring.gd`) statt
## Text-Pill, Badge-Pulse bei Stat < 25, Safe-Area-Insets (Notch/Home-
## Indicator, `HudLayoutLogic.safe_insets`) und Coins-Zähl-Animation.
##
## FIX1 (P0-Runde nach dem ersten iPhone-Test):
## - Skalierung läuft über die ZENTRALE Regel `UiScale.for_viewport()`
##   (kurze Kante + physischer Retina-Faktor) — vorher skalierte nur
##   Hochkant, in Querformat war alles physisch ~40 % zu klein.
## - Stats/Statuszeile sitzen BÜNDIG an der Kante (nur Safe-Area + 8 px
##   Schattenluft statt 16 px Zusatzrand).
## - Die rechte Knopfleiste (Cockpit-Spalte) trägt deutsche LABELS unter
##   den Icons; beim ersten Mal erklärt ein Coachmark die Knöpfe (merkt
##   sich das über AppSettings `hints.hud_actions_seen`).
##
## UICOZY (Web-Parität, GOOBY/src/ui/hud.js + styles.css):
## - Status-Pills tragen ihre Stat-Icons in BEIDEN Layouts (Web .stat-pill),
##   farbig getönt; Hochkant-Pills flexen über die Zeilenbreite (Web flex:1).
## - Pill-Innenmaße/Schriften skalieren über die ZENTRALE `UiScale`-Regel
##   (Web-CSS-px ≈ physische Punkte) — seit FB3 auch die Dock-Geometrie
##   (die alte `portrait_scale`-Bogen-Ausnahme ist Geschichte).
## - Münzen zählen hoch (UiMotion.count_to) + Wackel-Impuls aufs Icon.
## - Balken gleiten weich (UiMotion.bar_to, Web .stat-fill 300 ms ease).
## - Aktions-Icons in Identitätsfarben (Web .g5-hud-btn svg: pink/teal/gelb).
##
## Keine eigene Spiel-Logik: Anzeigedaten kommen über `set_stats()`,
## `set_coins()`, `set_level()` (W1d-GameState verdrahtet das später,
## siehe handoffs/W1c-needs-from-state.md).

## Ein Haupt-Button wurde gedrückt (reise/arcade/bau/album/profil/igohbie).
signal action_pressed(action: StringName)
## Interaktions-Auge an/aus (schaltet sich nach 8 s selbst aus).
signal eye_toggled(active: bool)
signal settings_pressed
signal where_is_gooby_pressed

const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const ICON_DIR := "res://assets/ui/icons/"
const EYE_AUTO_OFF_SEC := 8.0
## Unter diesem Wert pulsiert die Status-Kapsel (Doc H „Pflege-Alarm“).
const STAT_ALERT_THRESHOLD := 25.0
## FIX1: Randabstand zur Bildschirmkante (nur Schattenluft — Stats sollen
## bündig sitzen, der Rest kommt aus der Safe-Area).
## 44 pt ist das Minimum der UI-Pruefung; mit etwas Reserve, weil das Layout
## die Endgroesse um Bruchteile eines Punktes beschneiden kann.
const TOUCH_MIN_PT := 46.0
const EDGE_PAD := 8.0
## Label unter den Cockpit-Buttons (Design-px, skaliert mit f).
const LABEL_FONT := 12
const LABEL_PAD := 20.0
## Abstand zwischen den Cockpit-Knöpfen (Canvas-px).
const COLUMN_SEP := 10.0
## FB3 — Hochkant-Dock (Web .g5-hud-btn/.g5-hud-btns): 3.375rem-Kachel mit
## 22er-Icon + 9px-Label, 0.375rem Lücke, GENAU 5 Kacheln pro Zeile
## (Web-Kommentar V4/FIX-UI: sonst verwaist der 9. Knopf allein in Zeile 2).
const DOCK_BTN := 54.0
const DOCK_ICON := 22.0
const DOCK_LABEL_FONT := 9
const DOCK_GAP := 6.0
const DOCK_PER_ROW := 5
## AppSettings-Key: Coachmark „Deine Knöpfe“ schon gezeigt?
const COACHMARK_SEEN_KEY := "hints.hud_actions_seen"
## Reihenfolge = Bogen von links (flach) nach oben; Spalte nutzt eigene Liste.
## UICOZY: `tint` = Icon-Identitätsfarbe (Web .g5-hud-btn svg: pink/teal/
## gelb-dunkel im Wechsel — Ink-Monochrom wirkte nüchtern).
const ACTIONS: Array[Dictionary] = [
	{"id": &"igohbie", "icon": "phone", "tint": AcTokens.TEAL},
	{"id": &"bau", "icon": "wrench", "tint": AcTokens.YELLOW_DARK},
	{"id": &"reise", "icon": "suitcase", "tint": AcTokens.PINK},
	{"id": &"arcade", "icon": "gamepad", "tint": AcTokens.TEAL},
	{"id": &"album", "icon": "book", "tint": AcTokens.YELLOW_DARK},
	{"id": &"profil", "icon": "rabbit", "tint": AcTokens.PINK},
	# W6: Garderobe (92 Kosmetik-Teile), IKEA-Ausstellung, Haus gestalten.
	{"id": &"wardrobe", "icon": "shirt", "tint": AcTokens.PINK},
	{"id": &"ikea", "icon": "sofa", "tint": AcTokens.TEAL},
	{"id": &"gestalten", "icon": "brush", "tint": AcTokens.YELLOW_DARK},
	# REST-2: Tagesquests (DailyQuestService) — 10. Kachel macht das Dock 5+5.
	{"id": &"quests", "icon": "check", "tint": AcTokens.LEAF_DARK},
]
# W14/UISCREENS-B: die Reihenfolge beider Layouts liegt als PURE Logik in
# `hud/hud_button_order.gd` (H-Doc §1.3 „Daumen-Bogen"/„Cockpit": Haupt-
# Aktionen in die Daumen-Zeile/-Spalte, Zweitrangiges eine Ebene weiter).
const STATS := [
	{"id": "hunger", "icon": "hunger", "type": "StatHunger", "color": AcTokens.STAT_HUNGER},
	{"id": "energie", "icon": "energy", "type": "StatEnergy", "color": AcTokens.STAT_ENERGY},
	{"id": "hygiene", "icon": "hygiene", "type": "StatHygiene", "color": AcTokens.STAT_HYGIENE},
	{"id": "spass", "icon": "fun", "type": "StatFun", "color": AcTokens.STAT_FUN},
]
## Web-Referenzmaße (Design-px ≈ CSS-px): .stat-pill-Icon 20, Track-Höhe 10,
## Track-Mindestbreite 24 (min-width 1.5rem, flext), .g5-ring 40 (im Chip
## ≈ 3.25rem-Gesamtkreis), Coin-Glyph 22, Coin-Font 17/800, Ring-Font 16/800.
const STAT_ICON_PX := 20.0
const STAT_BAR_H_PX := 10.0
const STAT_BAR_MIN_W_PX := 24.0
## Querformat-Stat-Track: kompakt in der linken Spalte (war 132 — H2 zu breit).
const STAT_BAR_LANDSCAPE_W_PX := 80.0
const RING_PX := 40.0
const COIN_ICON_PX := 22.0
const COIN_FONT_PX := 17
const RING_FONT_PX := 16

var current_layout: HudLayoutLogic.Layout = HudLayoutLogic.Layout.PORTRAIT
## Notch-Simulation für Tests: Safe-Area in CANVAS-Koordinaten
## (Rect2() = aus, dann fragt das HUD den DisplayServer).
var safe_area_override := Rect2()

var _buttons: Dictionary = {}
var _stat_bars: Dictionary = {}
var _stat_icons: Dictionary = {}
var _stat_chips: Dictionary = {}
var _chip_nodes: Array[Control] = []
var _alert_tweens: Dictionary = {}
var _last_stats: Dictionary = {}
var _level_label: Label
var _level_ring: HudProgressRing
var _coin_label: Label
var _coin_icon: TextureRect
var _coin_chip: Control
var _coin_tween: Tween
var _coin_shown := 0
var _status_sheet: PanelSheet
var _eye_timer: Timer
var _coachmark: Control
## Breite der Cockpit-Spalte (setzt apply_layout; refresh_safe_area liest).
var _column_width := 88.0
## Oberkante der Cockpit-Spalte in Canvas-px (unter dem Zahnrad).
var _column_top := 84.0
## FB3: Dock-Kenngrößen (setzt apply_layout; refresh_safe_area liest).
var _dock_btn_px := DOCK_BTN
var _dock_gap_px := DOCK_GAP
## Bodenzeile (Gooby-Chip links, Auge rechts) — das Dock schwebt DARÜBER.
var _dock_clearance := 0.0

@onready var _top_bar: MarginContainer = $TopBar
@onready var _top_spacer: Control = $TopBar/TopBarBox/TopSpacer
@onready var _status_row: HBoxContainer = %StatusRow
@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _bottom_left: VBoxContainer = $BottomLeft
@onready var _portrait_dock: HFlowContainer = %PortraitDock
## FIX1: GridContainer statt VBox — bricht bei großem Retina-Faktor auf
## 2 Spalten um, damit alle 6 beschrifteten Knöpfe in die Höhe passen.
@onready var _landscape_column: GridContainer = %LandscapeColumn
@onready var _settings_button: Button = %SettingsButton
@onready var _eye_button: Button = %EyeButton
@onready var _gooby_chip: Button = %WhereIsGoobyChip


func _ready() -> void:
	_build_action_buttons()
	_build_status_chips()
	_setup_static_buttons()
	_eye_timer = Timer.new()
	_eye_timer.one_shot = true
	_eye_timer.timeout.connect(_on_eye_timeout)
	add_child(_eye_timer)
	get_viewport().size_changed.connect(_on_viewport_resized)
	visibility_changed.connect(_maybe_show_coachmark)
	_on_viewport_resized()
	_maybe_show_coachmark()


## Layout hart setzen (Rotation macht das automatisch; Tests rufen es direkt).
##
## FB3-Skalierungsregel: BEIDE Layouts nutzen die zentrale Regel
## `UiScale.for_viewport()` (kurze Kante + physischer Retina-Faktor). Die
## alte Hochkant-Ausnahme (`portrait_scale`, Deckel 2) existierte nur für
## die getunte Bogen-Geometrie — mit dem Web-Paritäts-Dock entfällt sie,
## und damit auch die 26-pt-Tippflächen auf 3×-Retina-Geräten.
func apply_layout(layout: HudLayoutLogic.Layout) -> void:
	current_layout = layout
	var portrait := layout == HudLayoutLogic.Layout.PORTRAIT
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var f := UiScale.for_viewport(get_viewport())
	var floor_px := maxf(
		HudLayoutLogic.touch_floor_canvas(canvas),
		float(AcTokens.TOUCH_FLOOR) * UiScale.touch_px_per_pt(get_viewport())
	)
	var insets := _safe_insets()
	_portrait_dock.visible = portrait
	_landscape_column.visible = not portrait
	_left_column.visible = not portrait
	_status_row.visible = portrait
	var btn_size := maxf((DOCK_BTN if portrait else HudLayoutLogic.LANDSCAPE_BTN) * f, floor_px)
	# Hochkant: Label sitzt IN der Kachel (Web .g5-btn-label) — kein Anbau.
	var label_h := 0.0 if portrait else LABEL_PAD * f
	_column_top = EDGE_PAD + float(insets["top"]) + maxf(56.0 * f, floor_px) + 12.0
	var button_parent: Container = _portrait_dock if portrait else _landscape_column
	# W14: Daumen-Ordnung (H-Doc §1.3) — Hochkant fix, Cockpit wird nach dem
	# Spalten-Messpass in _fit_landscape_column ggf. verschränkt umgehängt.
	var order: Array[StringName] = (
		HudButtonOrder.portrait_order() if portrait else HudButtonOrder.landscape_order(1)
	)
	var icon_base := DOCK_ICON if portrait else HudLayoutLogic.LANDSCAPE_ICON
	for id: StringName in order:
		var btn: Button = _buttons[id]
		btn.custom_minimum_size = Vector2(btn_size, btn_size + label_h)
		_apply_button_label(btn, id, portrait, f)
		_scale_icon_button(btn, f, icon_base)
		if btn.get_parent() != button_parent:
			if btn.get_parent() != null:
				btn.get_parent().remove_child(btn)
			button_parent.add_child(btn)
		else:
			button_parent.move_child(btn, order.find(id))
	if portrait:
		_column_width = btn_size
		_dock_btn_px = btn_size
		_dock_gap_px = DOCK_GAP * f
		# REST-2: Freihöhe = ECHTE Höhe der Bodenzeile — das Auge ist
		# ACTION_BTN*f hoch (> floor_px); seit die 10. Kachel (Quests) die
		# zweite Dock-Zeile rechts füllt, würde floor_px allein kollidieren.
		_dock_clearance = maxf(HudLayoutLogic.ACTION_BTN * f, floor_px) + EDGE_PAD
		_portrait_dock.add_theme_constant_override("h_separation", int(_dock_gap_px))
		_portrait_dock.add_theme_constant_override("v_separation", int(_dock_gap_px))
	else:
		btn_size = _fit_landscape_column(canvas, insets, btn_size, label_h, floor_px)
	var chip_parent: Container = _status_row if portrait else _left_column
	for chip in _chip_nodes:
		if chip.get_parent() != chip_parent:
			if chip.get_parent() != null:
				chip.get_parent().remove_child(chip)
			chip_parent.add_child(chip)
		# Mini-Kapseln in BEIDEN Layouts (H §1.3 Glance; Quer war zu fett).
		# Tap öffnet weiter das Status-Sheet → Touch-Floor bleibt Minimum.
		chip.theme_type_variation = &"StatusCapsuleMini"
		chip.custom_minimum_size = Vector2.ONE * floor_px
	# UICOZY (Web .g5-topbar): Hochkant flext die Stat-Pillen über die
	# Zeilenbreite (flex:1) — der Spacer weicht, die StatusRow übernimmt.
	_top_spacer.visible = not portrait
	_status_row.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
	)
	var pill_flags := Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
	for info in STATS:
		(_stat_chips[info["id"]] as Control).size_flags_horizontal = pill_flags
		var bar: ProgressBar = _stat_bars[info["id"]]
		# Web .stat-fill-Track: 10 px hoch, Hochkant min 24 px + flext mit,
		# Querformat kompakte feste Breite (Cockpit-Spalte).
		bar.custom_minimum_size = (
			Vector2(roundf(STAT_BAR_MIN_W_PX * f), roundf(STAT_BAR_H_PX * f))
			if portrait
			else Vector2(roundf(STAT_BAR_LANDSCAPE_W_PX * f), roundf(STAT_BAR_H_PX * f))
		)
		bar.size_flags_horizontal = pill_flags
		# Web-Parität: Stat-Icons sitzen in BEIDEN Layouts in der Pille.
		var icon := _stat_icons[info["id"]] as Control
		icon.visible = true
		icon.custom_minimum_size = Vector2.ONE * roundf(STAT_ICON_PX * f)
	_level_ring.custom_minimum_size = Vector2.ONE * roundf(RING_PX * f)
	_coin_icon.custom_minimum_size = Vector2.ONE * roundf(COIN_ICON_PX * f)
	_scale_font(_coin_label, COIN_FONT_PX, f)
	_scale_font(_level_label, RING_FONT_PX, f)
	_scale_font(_gooby_chip, 17, f)
	_settings_button.custom_minimum_size = Vector2.ONE * maxf(56.0 * f, floor_px)
	_eye_button.custom_minimum_size = Vector2.ONE * maxf(HudLayoutLogic.ACTION_BTN * f, floor_px)
	_scale_icon_button(_eye_button, f)
	_gooby_chip.custom_minimum_size = Vector2(0.0, floor_px)
	refresh_safe_area()


## FIX1-Messpass fürs Cockpit (Ursache „Spalte läuft über beide Ränder“):
## Das Theme (Kreis-StyleBox + Icon + Label-Zeile) setzt pro Knopf ein
## IRREDUZIBLES Minimum, das custom_minimum_size nicht unterschreiten kann —
## eine reine btn_size+label_h-Schätzung lief deshalb bei manchen
## Auflösungen (z. B. 2556×1179 @2×: echtes Minimum ≈ 127 px/Knopf bei
## 720 px Canvas-Höhe) oben UND unten über den Rand und überdeckte das
## Zahnrad (Probe-Befund). Hier wird GEMESSEN statt geschätzt: 1 Spalte,
## wenn die echten Minima passen, sonst 2 Spalten à 3 Knöpfe; Knopfgröße
## auf den freien Streifen eindampfen (nie unter den Touch-Floor), Spalte
## vertikal zentrieren und die ECHTE Breite für Offsets/Auge/Coachmark
## festhalten. Gibt die finale Knopfgröße zurück.
func _fit_landscape_column(
	canvas: Vector2, insets: Dictionary, btn_size: float, label_h: float, floor_px: float
) -> float:
	var ids := HudButtonOrder.landscape_order(1)
	var count := ids.size()
	var avail := canvas.y - _column_top - (EDGE_PAD + float(insets["bottom"]))
	# Irreduzible Knopf-Minima messen (ohne custom_minimum_size).
	var theme_min := Vector2.ZERO
	for id: StringName in ids:
		var btn: Button = _buttons[id]
		var saved := btn.custom_minimum_size
		btn.custom_minimum_size = Vector2.ZERO
		theme_min = theme_min.max(btn.get_combined_minimum_size())
		btn.custom_minimum_size = saved
	# FB3: so viele Spalten wie nötig — 9 Knöpfe à ~127 px Theme-Minimum
	# passen auf kurzen Quer-Canvases (720 px hoch) auch zu zweit nicht mehr
	# (5×127+40 = 675 px > freier Streifen) und liefen oben ins Zahnrad.
	var columns := 1
	var rows := count
	while columns < count and float(rows) * theme_min.y + COLUMN_SEP * float(rows - 1) > avail:
		columns += 1
		rows = int(ceilf(float(count) / float(columns)))
	# W14 (H-Doc §1.3 „Cockpit"): jetzt, wo die Spaltenzahl feststeht, die
	# Knöpfe so umhängen, dass die Haupt-Aktionen die rechte Außenspalte
	# (Daumen-Kante) bilden — row-major-Grid braucht dafür Verschränkung.
	ids = HudButtonOrder.landscape_order(columns)
	for i in ids.size():
		_landscape_column.move_child(_buttons[ids[i]], i)
	# Knopfgröße so eindampfen, dass `rows` Zeilen à max(btn+label, Minimum)
	# in den freien Streifen passen — nie unter den Touch-Floor.
	var cap := (avail - COLUMN_SEP * float(rows - 1)) / float(rows) - label_h
	btn_size = maxf(minf(btn_size, cap), floor_px)
	for id: StringName in ids:
		var btn: Button = _buttons[id]
		btn.custom_minimum_size = Vector2(btn_size, btn_size + label_h)
	_landscape_column.columns = columns
	_landscape_column.add_theme_constant_override("h_separation", int(COLUMN_SEP))
	_landscape_column.add_theme_constant_override("v_separation", int(COLUMN_SEP))
	# Spalte vertikal mittig im freien Streifen (Grid hat kein alignment).
	var row_h := maxf(btn_size + label_h, theme_min.y)
	var needed := float(rows) * row_h + COLUMN_SEP * float(rows - 1)
	_column_top += maxf((avail - needed) / 2.0, 0.0)
	_column_width = maxf(btn_size, theme_min.x) * float(columns) + COLUMN_SEP * float(columns - 1)
	return btn_size


## Safe-Area-Insets neu anwenden (Rotation/Resize macht das automatisch;
## Tests setzen `safe_area_override` und rufen es direkt).
## FIX1: Stats/Statuszeile sitzen BÜNDIG an der Kante — nur EDGE_PAD (8)
## Schattenluft plus Safe-Area, statt des alten 16-px-Zusatzrands.
func refresh_safe_area() -> void:
	var insets := _safe_insets()
	var left := float(insets["left"])
	var top := float(insets["top"])
	var right := float(insets["right"])
	var bottom := float(insets["bottom"])
	_top_bar.add_theme_constant_override("margin_left", int(EDGE_PAD + left))
	_top_bar.add_theme_constant_override("margin_top", int(EDGE_PAD + top))
	_top_bar.add_theme_constant_override("margin_right", int(EDGE_PAD + right))
	_left_column.offset_left = EDGE_PAD + left
	_bottom_left.offset_left = EDGE_PAD + left
	_bottom_left.offset_bottom = -EDGE_PAD - bottom
	# Cockpit-Spalte: Breite folgt der Buttongröße (Labels brauchen Platz),
	# Oberkante bleibt unterm Zahnrad (apply_layout setzt _column_top).
	_landscape_column.offset_left = -EDGE_PAD - right - _column_width
	_landscape_column.offset_right = -EDGE_PAD - right
	_landscape_column.offset_top = _column_top
	_landscape_column.offset_bottom = -EDGE_PAD - bottom
	# FB3 — Daumen-Dock (Web .g5-hud-btns): unten MITTIG, gedeckelt auf
	# genau 5 Kacheln Breite (5+4-Raster), und über der Bodenzeile
	# (Gooby-Chip links, Auge rechts) + Home-Indicator.
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var cap := float(DOCK_PER_ROW) * _dock_btn_px + float(DOCK_PER_ROW - 1) * _dock_gap_px
	_portrait_dock.offset_left = maxf((canvas.x - cap) / 2.0, left + EDGE_PAD)
	_portrait_dock.offset_right = -maxf((canvas.x - cap) / 2.0, right + EDGE_PAD)
	var dock_bottom := EDGE_PAD + bottom
	if current_layout == HudLayoutLogic.Layout.PORTRAIT:
		dock_bottom += _dock_clearance
	_portrait_dock.offset_bottom = -dock_bottom
	_portrait_dock.offset_top = -dock_bottom - 10.0
	_place_eye_button(current_layout == HudLayoutLogic.Layout.PORTRAIT, right, bottom)
	_position_coachmark()


## {"hunger":0..100, "energie":.., "hygiene":.., "spass":..}
func set_stats(stats: Dictionary) -> void:
	for key: String in stats:
		if _stat_bars.has(key):
			var value := float(stats[key])
			var bar := _stat_bars[key] as ProgressBar
			# UICOZY: Folge-Updates GLEITEN (Web .stat-fill 300 ms ease);
			# der ERSTE Wert snappt — wie im Web ohne Transition beim Mount.
			if _last_stats.has(key):
				UiMotion.bar_to(bar, value)
			else:
				bar.value = value
			_last_stats[key] = value
	_update_stat_alerts()
	if _status_sheet != null and _status_sheet.is_open():
		_fill_status_sheet()


func set_coins(coins: int) -> void:
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	var from := _coin_shown
	_coin_shown = coins
	# UICOZY: Zähl-Animation + Münz-Wackler + Chip-Hüpfer über die gemeinsame
	# UiMotion-Bibliothek (reduced-motion-gated, W4/POLISH-4 → Web-Parität).
	_coin_tween = UiMotion.count_to(_coin_label, from, coins)
	if from != coins:
		UiMotion.wiggle(_coin_icon)
		UiMotion.bounce(_coin_chip)


func set_level(level: int, xp_ratio: float = 0.0) -> void:
	_level_label.text = str(level)
	_level_ring.ratio = xp_ratio
	(_level_ring.get_parent() as Control).tooltip_text = I18nService.t(
		"hud.level_pill", {"level": level}
	)


func is_eye_active() -> bool:
	return _eye_button.button_pressed


## W13/HUD-WIRES: Auge von außen lautlos setzen/zurücksetzen (Raumwechsel/
## Screen-Öffnen schaltet die Interaktions-Anzeige ab — der Knopf muss
## folgen, OHNE eye_toggled erneut zu feuern).
func set_eye_active(active: bool) -> void:
	if _eye_button.button_pressed == active:
		return
	_eye_button.set_pressed_no_signal(active)
	if active:
		_eye_timer.start(EYE_AUTO_OFF_SEC)
	else:
		_eye_timer.stop()


## UIFINAL — freier Streifen für Sprechblasen/Overlays am unteren Rand:
## `top` = Canvas-y der Oberkante der HUD-Bodenmöblierung (Hochkant: das
## Dock; Querformat: Auge/Gooby-Chip-Zeile), `width` = maximale Breite
## eines MITTIG zentrierten Elements, ohne die Cockpit-Spalte zu schneiden.
## Die DialogBubble fragt das ab, statt hinter Auge/Chip zu liegen.
func bubble_lane() -> Dictionary:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := _safe_insets()
	var portrait := current_layout == HudLayoutLogic.Layout.PORTRAIT
	var lane_top := canvas.y - float(insets["bottom"]) - EDGE_PAD
	var width := canvas.x - float(insets["left"]) - float(insets["right"]) - 2.0 * EDGE_PAD
	if portrait and _portrait_dock.visible:
		lane_top = _portrait_dock.get_global_rect().position.y
	else:
		lane_top -= maxf(_eye_button.size.y, _eye_button.get_combined_minimum_size().y)
		var column_left := canvas.x - float(insets["right"]) - EDGE_PAD - _column_width
		width = minf(width, 2.0 * (column_left - 12.0 - canvas.x / 2.0))
	return {"top": lane_top, "width": maxf(width, 220.0)}


## UIFINAL — freie Kopf-Zone für den „Was nun?“-Hinweis: Hochkant die volle
## Breite UNTER der Statuszeile; Querformat der Streifen ZWISCHEN der
## Status-Spalte links und dem Zahnrad rechts, oben bündig mit der
## Safe-Area (die Cockpit-Spalte beginnt tiefer). Nie über HUD-Knöpfen.
func hint_lane() -> Dictionary:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := _safe_insets()
	var left := float(insets["left"]) + EDGE_PAD
	var right := canvas.x - float(insets["right"]) - EDGE_PAD
	var top := float(insets["top"]) + EDGE_PAD
	if current_layout == HudLayoutLogic.Layout.PORTRAIT:
		if _top_bar != null and _top_bar.visible:
			top = maxf(top, _top_bar.get_global_rect().end.y + 8.0)
	else:
		if _left_column != null and _left_column.visible:
			left = maxf(left, _left_column.get_global_rect().end.x + 12.0)
		if _settings_button != null:
			right = minf(right, _settings_button.get_global_rect().position.x - 12.0)
		# Auch an der Cockpit-Spalte enden: auf kurzen Canvases ragt eine
		# hohe Karte sonst in deren oberste Knopfzeile.
		if _landscape_column != null and _landscape_column.visible:
			right = minf(right, _landscape_column.get_global_rect().position.x - 12.0)
		top += 4.0
	return {"left": left, "right": maxf(right, left + 220.0), "top": top}


## Stat-Detail-Sheet (Tap auf eine Status-Kapsel): 4 Stats groß mit
## Icons + Balken + Buff-Anzeige (`hud_status_sheet.gd`).
func open_status_sheet() -> void:
	if _status_sheet == null:
		_status_sheet = SHEET_SCENE.instantiate()
		add_child(_status_sheet)
	_fill_status_sheet()
	_status_sheet.open()


## Pulsiert die Kapsel dieser Stat gerade? (Badge-Pulse bei Wert < 25.)
func is_stat_alerting(stat_id: String) -> bool:
	return _alert_tweens.has(stat_id)


func _fill_status_sheet() -> void:
	_status_sheet.set_title(HudStatusSheet.title_text())
	var gs := get_node_or_null("/root/GameState")
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var boni := HudStatusSheet.stat_boni(gs, now_ms)
	# W13B/RAUMSTATION: ☀ am Energie-Buff-Chip, solange „erholt“ läuft.
	var sonne := HudStatusSheet.erholt_aktiv(gs, now_ms)
	# FIX1: zentrale Skalierungs-Regel statt Hochkant-Heuristik — das Sheet
	# skaliert jetzt in BEIDEN Orientierungen gleich. Die nutzbare
	# Innenbreite geht mit, damit der Inhalt nie breiter baut als das Blatt
	# (sonst schnitt Hochkant die Wert-Spalte ab).
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var avail := (
		PanelSheetLayout.sheet_width(canvas, _safe_insets(), f) - _status_sheet.chrome_width()
	)
	_status_sheet.add_content(HudStatusSheet.build_content(_last_stats, boni, f, avail, sonne))


func _build_action_buttons() -> void:
	for action in ACTIONS:
		var id: StringName = action["id"]
		var btn := SquishButton.new()
		btn.name = "Btn" + String(id).capitalize()
		btn.theme_type_variation = "HudIconButton"
		btn.icon = load("%s%s.svg" % [ICON_DIR, action["icon"]])
		btn.custom_minimum_size = Vector2.ONE * HudLayoutLogic.ACTION_BTN
		# UICOZY: Identitätsfarbe pro Knopf (Web .g5-hud-btn svg) statt Ink.
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			btn.add_theme_color_override(state, action["tint"])
		btn.tooltip_text = I18nService.t("hud." + String(id))
		btn.expand_icon = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_action_pressed.bind(id))
		_buttons[id] = btn
		_portrait_dock.add_child(btn)


func _build_status_chips() -> void:
	var level_chip := _make_chip("LevelChip")
	_level_ring = HudProgressRing.new()
	_level_ring.name = "LevelRing"
	_level_ring.custom_minimum_size = Vector2(34, 34)
	_level_label = Label.new()
	_level_label.name = "LevelValue"
	_level_label.theme_type_variation = "CaptionLabel"
	# Web .g5-ring b: 800er-Gewicht im Level-Ring.
	_level_label.add_theme_font_override("font", ThemeService.font(800))
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_ring.add_child(_level_label)
	level_chip.add_child(_level_ring)
	_status_row.add_child(level_chip)
	for info in STATS:
		var chip := _make_chip("StatChip" + String(info["id"]).capitalize())
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = load("%s%s.svg" % [ICON_DIR, info["icon"]])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# UICOZY: Icon in der Stat-Farbe (Web .stat-pill svg) statt Ink-Grau.
		icon.self_modulate = info["color"]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		_stat_icons[info["id"]] = icon
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.theme_type_variation = info["type"]
		bar.custom_minimum_size = Vector2(56, 12)
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = 100.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.tooltip_text = I18nService.t("hud.stat_" + String(info["id"]))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bar)
		chip.add_child(box)
		_stat_bars[info["id"]] = bar
		_stat_chips[info["id"]] = chip
		_status_row.add_child(chip)
	var coin_chip := _make_chip("CoinChip")
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 6)
	coin_box.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_icon = TextureRect.new()
	_coin_icon.texture = load("res://assets/ui/coin.png")
	_coin_icon.custom_minimum_size = Vector2(22, 22)
	_coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(_coin_icon)
	_coin_label = Label.new()
	_coin_label.name = "CoinValue"
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Web .g5-coin b: 800er-Gewicht (Zahl soll „münzig“ satt wirken).
	_coin_label.add_theme_font_override("font", ThemeService.font(800))
	coin_box.add_child(_coin_label)
	coin_chip.add_child(coin_box)
	_coin_chip = coin_chip
	_status_row.add_child(coin_chip)
	_chip_nodes = [level_chip]
	for info in STATS:
		_chip_nodes.append(_stat_chips[info["id"]] as Control)
	_chip_nodes.append(coin_chip)
	set_level(1)
	set_coins(0)


func _make_chip(chip_name: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = chip_name
	chip.theme_type_variation = "StatusCapsule"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.gui_input.connect(_on_chip_input)
	return chip


func _setup_static_buttons() -> void:
	_settings_button.icon = load(ICON_DIR + "gear.svg")
	_settings_button.tooltip_text = I18nService.t("hud.einstellungen")
	_settings_button.pressed.connect(_on_settings_pressed)
	_eye_button.icon = load(ICON_DIR + "eye.svg")
	_eye_button.tooltip_text = I18nService.t("hud.auge")
	_eye_button.toggled.connect(_on_eye_toggled)
	_gooby_chip.text = I18nService.t("hud.wo_ist_gooby")
	_gooby_chip.pressed.connect(_on_gooby_chip_pressed)


func _place_eye_button(portrait: bool, inset_right := 0.0, inset_bottom := 0.0) -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	_eye_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_eye_button.reset_size()
	var eye := _eye_button.get_combined_minimum_size()
	if portrait:
		# Bodenzeile rechts unten (FB3): Gooby-Chip links, Auge rechts —
		# das Dock schwebt eine Zeile DARÜBER (_dock_clearance).
		_eye_button.position = Vector2(
			vp.x - inset_right - EDGE_PAD - eye.x, vp.y - inset_bottom - EDGE_PAD - eye.y
		)
	else:
		# Links neben der Button-Spalte, unten (Cockpit) — folgt der echten
		# Spaltenbreite statt fester 96 px (FIX1: Spalte ist jetzt skaliert).
		_eye_button.position = Vector2(
			vp.x - inset_right - EDGE_PAD - _column_width - 12.0 - eye.x,
			vp.y - inset_bottom - EDGE_PAD - eye.y
		)


## Icon-Skalierung für die Frost-Icon-Buttons: das Theme deckelt Icons auf
## 44 px (`HudIconButton/icon_max_width`) — der Deckel wächst mit f, sonst
## wirken die Icons verloren. `base` = Design-Icongröße: Dock + Cockpit
## nutzen die Web-Referenz 22 (kompakte Kachel); Auge bleibt 44.
func _scale_icon_button(btn: Button, f: float, base := 44.0) -> void:
	btn.add_theme_constant_override("icon_max_width", int(maxf(base * f, 16.0)))


## Font-Größe = Web-CSS-px × zentrale Skala (UICOZY: vorher galt das nur
## für f > 1 — bei f = 1 wichen Coin/Ring-Fonts von der Web-Referenz ab).
func _scale_font(ctl: Control, base_px: int, f: float) -> void:
	ctl.add_theme_font_size_override("font_size", int(maxf(base_px * f, 10.0)))


## FIX1 „Die Tasten rechts werden nichtmal erklärt“ + FB3-Web-Parität: der
## Name steht in BEIDEN Layouts unterm Icon (Web .g5-btn-label) — Hochkant
## kompakt (9 px Basis), Cockpit etwas größer (12 px Basis).
func _apply_button_label(btn: Button, id: StringName, portrait: bool, f: float) -> void:
	btn.text = I18nService.t("hud." + String(id))
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.clip_text = true
	var base := DOCK_LABEL_FONT if portrait else LABEL_FONT
	btn.add_theme_font_size_override("font_size", int(maxf(float(base) * f, 10.0)))


## Erststart-Coachmark „Deine Knöpfe“ (FIX1): erklärt die Cockpit-Spalte
## einmalig; merkt sich das über AppSettings `hints.hud_actions_seen`.
func _maybe_show_coachmark() -> void:
	if _coachmark != null or not visible or not is_inside_tree():
		return
	if current_layout == HudLayoutLogic.Layout.PORTRAIT:
		return
	var settings := get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("get_setting"):
		return
	if bool(settings.get_setting(COACHMARK_SEEN_KEY, false)):
		return
	_coachmark = _build_coachmark()
	add_child(_coachmark)
	_position_coachmark()
	_coachmark.minimum_size_changed.connect(_position_coachmark)
	_position_coachmark.call_deferred()
	# UICOZY: Coachmark federt auf (Web --ease-spring) statt hart zu stehen.
	UiMotion.pop_in(_coachmark)


func _build_coachmark() -> Control:
	var f := UiScale.for_viewport(get_viewport())
	var card := PanelContainer.new()
	card.name = "HudCoachmark"
	card.theme_type_variation = &"AcCard"
	card.custom_minimum_size = Vector2(280.0 * f, 0.0)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(12.0 * f))
	card.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(8.0 * f))
	margin.add_child(vbox)
	var title := Label.new()
	title.theme_type_variation = "HeadlineLabel"
	title.text = I18nService.t("hud.coachmark_titel")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)
	var body := Label.new()
	body.name = "CoachmarkText"
	body.theme_type_variation = "CaptionLabel"
	body.text = I18nService.t("hud.coachmark_text")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var ok := SquishButton.new()
	ok.name = "CoachmarkOk"
	ok.theme_type_variation = "BtnLeaf"
	ok.text = I18nService.t("hud.coachmark_ok")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	# FB3-Regel: physische Tippflaeche >= 44 pt (nicht Design-Pixel!).
	# FB3-Regel: physische Tippflaeche >= 44 pt. `touch_floor_canvas` rechnet in
	# DESIGN-Pixeln und unterschreitet das auf dichten Displays — deshalb hier
	# derselbe physische Massstab, den die UI-Pruefung anlegt.
	var touch_floor := UiScale.touch_px_per_pt(get_viewport()) * TOUCH_MIN_PT
	ok.custom_minimum_size = Vector2(maxf(120.0 * f, touch_floor), touch_floor)
	ok.pressed.connect(_on_coachmark_dismissed)
	vbox.add_child(ok)
	return card


## Coachmark links neben die Cockpit-Spalte setzen (vertikal mittig).
func _position_coachmark() -> void:
	if _coachmark == null or not is_instance_valid(_coachmark):
		return
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := _safe_insets()
	var ok_btn := _coachmark.find_child("CoachmarkOk", true, false) as Control
	if ok_btn != null:
		var floor_px := UiScale.touch_px_per_pt(get_viewport()) * TOUCH_MIN_PT
		ok_btn.custom_minimum_size = Vector2(maxf(ok_btn.custom_minimum_size.x, floor_px), floor_px)
	_coachmark.reset_size()
	var size := _coachmark.get_combined_minimum_size()
	# Autowrap-Labels melden im ERSTEN Layout-Pass eine viel zu grosse Hoehe
	# (Godot kennt die Zeilenumbrueche noch nicht). Ungeklemmt schiebt das die
	# Karte weit ueber den Bildrand hinaus — deshalb hart in den sicheren
	# Bereich klemmen und nach dem Settle erneut setzen.
	var top := float(insets["top"]) + EDGE_PAD
	var bottom := canvas.y - float(insets["bottom"]) - EDGE_PAD
	var left := float(insets["left"]) + EDGE_PAD
	var right := canvas.x - float(insets["right"]) - EDGE_PAD
	size.x = minf(size.x, maxf(right - left, 1.0))
	size.y = minf(size.y, maxf(bottom - top, 1.0))
	_coachmark.size = size
	var x := canvas.x - float(insets["right"]) - EDGE_PAD - _column_width - 16.0 - size.x
	var y := (canvas.y - size.y) / 2.0
	_coachmark.position = Vector2(
		clampf(x, left, maxf(right - size.x, left)), clampf(y, top, maxf(bottom - size.y, top))
	)


func _on_coachmark_dismissed() -> void:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.set_setting(COACHMARK_SEEN_KEY, true)
	if _coachmark != null:
		_coachmark.queue_free()
		_coachmark = null


## Insets in Canvas-Koordinaten: Override (Tests/Notch-Simulation) >
## DisplayServer-Safe-Area (auf Canvas skaliert) > 0 (Desktop/Headless).
## FIX1: zentral über UiScale (inkl. Deckel gegen kaputte Safe-Area-Werte).
func _safe_insets() -> Dictionary:
	return UiScale.safe_insets_canvas(get_viewport(), safe_area_override)


func _update_stat_alerts() -> void:
	for info in STATS:
		var id := String(info["id"])
		var alerting := float(_last_stats.get(id, 100.0)) < STAT_ALERT_THRESHOLD
		if alerting == _alert_tweens.has(id):
			continue
		var chip := _stat_chips[id] as Control
		if alerting:
			_start_alert_pulse(id, chip)
		else:
			_stop_alert_pulse(id, chip)


func _start_alert_pulse(id: String, chip: Control) -> void:
	if ThemeService.is_reduced_motion(self):
		# Statischer Alarm-Tint statt Puls (Reduced Motion).
		chip.modulate = Color(1.0, 0.82, 0.82)
		_alert_tweens[id] = null
		return
	chip.pivot_offset = chip.size / 2.0
	var tween := create_tween().set_loops()
	tween.tween_property(chip, "scale", Vector2.ONE * 1.07, 0.42)
	tween.parallel().tween_property(chip, "modulate", Color(1.0, 0.8, 0.8), 0.42)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.42)
	tween.parallel().tween_property(chip, "modulate", Color.WHITE, 0.42)
	_alert_tweens[id] = tween


func _stop_alert_pulse(id: String, chip: Control) -> void:
	var tween: Variant = _alert_tweens[id]
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	_alert_tweens.erase(id)
	chip.scale = Vector2.ONE
	chip.modulate = Color.WHITE


func _on_chip_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		open_status_sheet()


func _on_viewport_resized() -> void:
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	apply_layout(HudLayoutLogic.pick_layout(vp_size))


func _on_action_pressed(id: StringName) -> void:
	AudioDirector.try_play(self, "ui_click")
	action_pressed.emit(id)


func _on_settings_pressed() -> void:
	AudioDirector.try_play(self, "ui_click")
	settings_pressed.emit()


func _on_gooby_chip_pressed() -> void:
	AudioDirector.try_play(self, "ui_chip")
	where_is_gooby_pressed.emit()


func _on_eye_toggled(active: bool) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	eye_toggled.emit(active)
	if active:
		_eye_timer.start(EYE_AUTO_OFF_SEC)
	else:
		_eye_timer.stop()


func _on_eye_timeout() -> void:
	if _eye_button.button_pressed:
		_eye_button.set_pressed_no_signal(false)
		eye_toggled.emit(false)
