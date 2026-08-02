class_name StimmungsHerz
extends Control
## Stimmungs-Herz am „Wo ist mein Gooby?"-Chip (G8/IDEA-SEELE, Idee 2):
## macht die SEELE-2-Laune (SoulMood, träge 0..100 im Soul-Slice) ERST
## sichtbar — als kleines Herz, dessen FARBE dem Laune-Band folgt
## (mint = selig … grau-blau = elend) und dessen FÜLLSTAND dem Wert.
## KEINE nackten Zahlen — nur Farbe, Füllung und (per Tap) warme Worte.
##
## Verhalten:
##  - Pollt die Laune sanft (POLL_S) aus dem Soul-Slice — dieselbe Wahrheit,
##    die SeeleRunner schreibt; kein neuer Zustand, keine Kopplung an den
##    Raum-Runner (das Herz lebt im HUD, der Runner pro Raum).
##  - Übergänge GLEITEN (der Anzeige-Wert nähert sich träge dem Ziel);
##    Reduced Motion = statisch (Snap, kein Hüpfen).
##  - Band-Wechsel = Mikro-Moment: Herz hüpft kurz + leiser Ton — Pflege
##    lohnt sich SICHTBAR (Idee-2-Kern), im ersten Poll aber still.
##  - Tap aufs Herz → „So geht's {gooby}"-Blatt (PanelSheet-Muster, Inhalt
##    aus stimmungs_sheet.gd) — der Chip selbst behält seine Kamera-Aktion.
##
## Anbindung (hud.gd bleibt unter Budget): StimmungsHerz.anbringen(chip, hud)
## hängt das Herz RECHTS in den Chip und richtet den Chip-Text links aus;
## hud.gd registriert das Herz zusätzlich in der HudSichtbarkeit (Eingaben-
## Sperre im Baumodus/unter Blättern) und addiert platz_breite() zur
## Chip-Mindestbreite. Farb-/Füllstand-Mapping ist PUR (headless testbar).

## Herz-Grundmaß in Design-px (skaliert mit f über skaliere()).
const HERZ_PX := 26.0
## Luft zwischen Chip-Text und Herz (Design-px).
const LUFT_PX := 6.0
## Laune-Poll (träge Laune — schneller wäre verschwendet).
const POLL_S := 0.8
## Anzeige-Trägheit: Anteil Restdistanz pro Sekunde (weiches Nachziehen).
const GLEIT_PRO_S := 2.6
## Band → Herzfarbe (Idee 2: mint=selig, creme=zufrieden, grau-blau=mies).
const BAND_FARBEN := {
	"ecstatic": Color("#7FD8B5"),
	"happy": Color("#F2DDA4"),
	"neutral": Color("#E8C89A"),
	"grumpy": Color("#A9B0C3"),
	"miserable": Color("#8E9AB3"),
}
## Leere Herz-Silhouette (Papier-Schatten-Ton, zu allen Bändern neutral).
const LEER_FARBE := Color(0.29, 0.23, 0.21, 0.18)
## Kontur in Ink — das Herz liest sich auch auf hellen Chips.
const KONTUR_FARBE := Color(0.29, 0.23, 0.21, 0.55)

var _gs: Object = null
var _hud: Control = null
var _sheet: PanelSheet = null
var _sheet_inhalt: Control = null
var _faktor := 1.0
var _ziel_wert := SoulMood.DEFAULT_WERT
var _anzeige_wert := SoulMood.DEFAULT_WERT
var _band := ""
var _poll_rest := 0.0
var _huepf_tween: Tween = null


## Herz erzeugen und rechts in den Chip hängen (idempotent). `hud` ist die
## HUD-Wurzel — dort docken die Blätter an (Kind des HUD → die
## HudSichtbarkeit zählt das eigene Blatt nicht, s. hud_sichtbarkeit.gd).
static func anbringen(chip: Button, hud: Control) -> StimmungsHerz:
	var existing := chip.get_node_or_null("StimmungsHerz")
	if existing is StimmungsHerz:
		return existing
	var herz := StimmungsHerz.new()
	herz.name = "StimmungsHerz"
	herz._hud = hud
	# Chip-Text links ausrichten — rechts gehört die Kante dem Herz
	# (zentrierter Text liefe sonst unters Herz).
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.add_child(herz)
	return herz


# ── PURE Mapping (deterministisch, headless testbar) ─────────────────────────


## Herzfarbe fürs Laune-Band (unbekannt → neutral).
static func farbe_fuer_band(band_id: String) -> Color:
	return BAND_FARBEN.get(band_id, BAND_FARBEN["neutral"])


## Füllstand 0..1 aus dem Laune-Wert 0..100 (linear, geklemmt) — der
## Füllstand zeigt den WERT, die Farbe das BAND.
static func fuellstand(wert: float) -> float:
	return clampf(wert / 100.0, 0.0, 1.0)


## Herz-Umriss als Polygon (Einheitsgröße `seite`, Ursprung oben links).
## Parametrische Herzkurve — geschlossen, konvex genug für colored_polygon.
static func herz_punkte(seite: float) -> PackedVector2Array:
	var punkte := PackedVector2Array()
	var mitte := Vector2(seite * 0.5, seite * 0.44)
	var mass := seite * 0.031
	for i in 28:
		var t := TAU * float(i) / 28.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		punkte.append(mitte + Vector2(x, y) * mass)
	return punkte


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = I18nService.t("seele_tag.herz.tooltip")
	_gs = get_node_or_null("/root/GameState")
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	gui_input.connect(_on_gui_input)
	# Erster Stand SOFORT (still — kein Hüpfer beim Aufbau).
	_ziel_wert = _lies_wert()
	_anzeige_wert = _ziel_wert
	_band = SoulMood.band(_ziel_wert)
	skaliere(1.0)


## Vom HUD-Layout-Pass gerufen: Herzgröße folgt dem UI-Faktor des Chips.
func skaliere(f: float) -> void:
	_faktor = f
	var seite := roundf(HERZ_PX * f)
	custom_minimum_size = Vector2(seite, seite)
	size = custom_minimum_size
	offset_right = -roundf(LUFT_PX * f) * 0.5
	offset_left = offset_right - seite
	offset_top = -seite * 0.5
	offset_bottom = seite * 0.5
	pivot_offset = custom_minimum_size * 0.5
	queue_redraw()


## Platzbedarf in der Chip-Mindestbreite (Herz + Luft), Canvas-px.
func platz_breite(f: float) -> float:
	return ceilf((HERZ_PX + LUFT_PX) * f)


func _process(delta: float) -> void:
	_poll_rest -= delta
	if _poll_rest <= 0.0:
		_poll_rest = POLL_S
		_setze_ziel(_lies_wert())
	if is_equal_approx(_anzeige_wert, _ziel_wert):
		return
	if _reduced_motion():
		_anzeige_wert = _ziel_wert
	else:
		var anteil := clampf(GLEIT_PRO_S * delta, 0.0, 1.0)
		_anzeige_wert = lerpf(_anzeige_wert, _ziel_wert, anteil)
		if absf(_anzeige_wert - _ziel_wert) < 0.2:
			_anzeige_wert = _ziel_wert
	queue_redraw()


## Neues Laune-Ziel übernehmen; Band-Wechsel = Mikro-Moment (Hüpfer + Ton).
func _setze_ziel(wert: float) -> void:
	_ziel_wert = wert
	var band_neu := SoulMood.band(wert)
	if band_neu == _band:
		return
	_band = band_neu
	queue_redraw()
	AudioDirector.try_play(self, "ui_tick")
	if _reduced_motion():
		return
	if _huepf_tween != null and _huepf_tween.is_valid():
		_huepf_tween.kill()
	scale = Vector2.ONE
	_huepf_tween = create_tween()
	_huepf_tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.12).set_trans(
		Tween.TRANS_QUAD
	)
	(
		_huepf_tween
		. tween_property(self, "scale", Vector2.ONE, 0.22)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


func _draw() -> void:
	var seite := minf(size.x, size.y)
	var umriss := herz_punkte(seite)
	# Leere Silhouette, darüber der Füllstand (von unten), dann die Kontur.
	draw_colored_polygon(umriss, LEER_FARBE)
	var anteil := fuellstand(_anzeige_wert)
	if anteil > 0.0:
		var kante := seite * (1.0 - anteil)
		var fenster := PackedVector2Array(
			[
				Vector2(-seite, kante),
				Vector2(seite * 2.0, kante),
				Vector2(seite * 2.0, seite * 2.0),
				Vector2(-seite, seite * 2.0),
			]
		)
		for teil in Geometry2D.intersect_polygons(umriss, fenster):
			if teil.size() >= 3:
				draw_colored_polygon(teil, farbe_fuer_band(_band))
	var geschlossen := umriss.duplicate()
	geschlossen.append(umriss[0])
	draw_polyline(geschlossen, KONTUR_FARBE, maxf(1.0, 1.2 * _faktor), true)


# ── Tap → „So geht's Gooby“-Blatt ────────────────────────────────────────────


## Öffnen auf dem LOSLASSEN (Button-Semantik), NICHT auf dem Druck: das
## Projekt emuliert Touch aus Maus — ein Druck-Open ließe das ZWEITE
## Druck-Event desselben Taps auf dem frisch geöffneten Backdrop landen,
## und der schließt oberste Blätter auf pressed → das Blatt ginge im
## selben Tap wieder zu. Releases dagegen laufen zum Druck-Fänger (uns)
## zurück und der Backdrop ignoriert sie — wie bei jedem Button-Sheet.
func _on_gui_input(event: InputEvent) -> void:
	var los := false
	var wo := Vector2.ZERO
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		los = (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		wo = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		los = true
		wo = (event as InputEventScreenTouch).position
	# Wegziehen bricht ab (wie ein echter Button) — nur Loslassen AUF dem
	# Herzen öffnet.
	if not los or not Rect2(Vector2.ZERO, size).has_point(wo):
		return
	accept_event()
	# Das DUPLIZIERTE Release (Maus + emulierter Touch) ist ein No-Op,
	# sobald das Blatt schon offen ist — kein Doppel-Ton, kein Neubau.
	if _sheet != null and is_instance_valid(_sheet) and _sheet.is_open():
		return
	AudioDirector.try_play(self, "ui_chip")
	oeffne_sheet()


## Blatt öffnen (öffentlich — Tests/Flows rufen direkt). Inhalt kommt aus
## StimmungsSheet (pur), das Blatt selbst ist das VORHANDENE PanelSheet.
func oeffne_sheet() -> void:
	if _hud == null:
		return
	if _sheet == null or not is_instance_valid(_sheet):
		_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
		_sheet.name = "StimmungsSheet"
		_hud.add_child(_sheet)
	var state: Dictionary = _gs.state() if _gs != null and _gs.has_method("state") else {}
	var daten := StimmungsSheet.inhalt(state, _now_ms())
	_sheet.set_title(I18nService.t("seele_tag.herz.titel", daten["args"]))
	var vp := get_viewport()
	var f := UiScale.for_viewport(vp)
	var insets := UiScale.safe_insets_canvas(vp, _sheet.safe_area_override)
	var breite := PanelSheetLayout.sheet_width(Vector2(vp.get_visible_rect().size), insets, f)
	_sheet_inhalt = StimmungsSheet.build_content(daten, f, breite - _sheet.chrome_width())
	_sheet.add_content(_sheet_inhalt)
	_sheet.open()


func _lies_wert() -> float:
	if _gs == null:
		return SoulMood.DEFAULT_WERT
	return float(SoulState.slice_of(_gs)["stimmung"]["wert"])


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _reduced_motion() -> bool:
	return ThemeService.is_reduced_motion(self)
