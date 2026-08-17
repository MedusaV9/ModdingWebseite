class_name HudStatKapseln
extends RefCounted
## W21/ACNH Referenz-Umsetzung (UI-DESIGN-ACNH §7): die linke Stats-Spalte
## des Quer-HUD als EINE kompakte StatKapsel-Gruppe statt sechs fetter
## Einzel-Pillen (Vorher: 6× 190×78,5 Canvas-px = 7,95 % gemalte Fläche).
## Hochkant bleibt die Status-Zeile aus Mini-Pillen (Web-Parität) —
## dieselben Chip-Nodes wechseln nur die Rolle (Wächter test_ui_layout
## erwartet die Chips als DIREKTE Kinder von LeftColumn/StatusRow).
##
## API (statisch, von hud.gd gerufen):
##   stil_anwenden(...) -> float   # Rollen/Maße pro Layout; gibt ring_px zurück
##   einblenden(chips)             # gestaffelter Pop-In beim Layout-Wechsel
##   wert_puls(chip, alt, neu, alarm)  # sanfter Puls bei spürbarer Änderung

## Mini-Balken-Breite der Quer-Kapsel (Design-px, ×f) — kompakt statt 80.
const BAR_W_KOMPAKT := 44.0
## Balken-Breite der Hochkant-Pillen (Web min-width 1.5rem, flext mit).
const BAR_W_PORTRAIT := 24.0
## Level-Ring in der Kapsel-Gruppe (Design-px) — kompakter als die 40er-Pille.
const RING_KOMPAKT := 36.0
## Ab dieser Wert-Änderung pulsiert die Kapsel (Ticker-Rauschen pulst nie).
const PULS_DELTA := 2.0
## Halbe Periodendauer des Alarm-Pulses (Stat < 25) — konstant > 0, sonst
## meldet der Loop-Tween „Infinite loop detected“ (W19-Wächter).
const ALERT_PULS_S := 0.42
## VBox-Separation Hochkant (Szene-Wert) — quer 0 (Segmente stoßen aneinander).
const SEP_PORTRAIT := 8


## Rollen + Maße pro Layout anwenden. Quer: Segment-Rollen (Kopf/Mitte/Fuss),
## kompakte Zeilen, EINE Gruppenbreite. Hochkant: Mini-Pillen (Touch-Floor,
## Balken flexen). Gibt die Ring-Größe (Canvas-px) für den Level-Ring zurück.
static func stil_anwenden(
	chips: Array[Control],
	stat_chips: Dictionary,
	bars: Dictionary,
	icons: Dictionary,
	spalte: VBoxContainer,
	portrait: bool,
	f: float,
	floor_px: float,
	ring_voll: float
) -> float:
	spalte.add_theme_constant_override("separation", SEP_PORTRAIT if portrait else 0)
	# Quer schmiegt sich die Gruppe an ihre Inhaltsbreite (SHRINK_BEGIN) —
	# die Szenen-Spalte ist breiter (offset 240), FILL würde die Segmente
	# auf Spaltenbreite aufblasen (Headless-Befund: 232 statt 135 px).
	var chip_flags := Control.SIZE_FILL if portrait else Control.SIZE_SHRINK_BEGIN
	if portrait:
		for chip in chips:
			chip.theme_type_variation = &"StatusCapsuleMini"
			chip.custom_minimum_size = Vector2.ONE * floor_px
			chip.size_flags_horizontal = chip_flags
	else:
		AcnhKit.segment_rollen(chips)
		for chip in chips:
			chip.custom_minimum_size = Vector2.ZERO
			chip.size_flags_horizontal = chip_flags
	var pill_flags := Control.SIZE_EXPAND_FILL if portrait else chip_flags
	for id: String in bars:
		var bar := bars[id] as ProgressBar
		var bar_w := BAR_W_PORTRAIT if portrait else BAR_W_KOMPAKT
		bar.custom_minimum_size = Vector2(AcTokens.px(bar_w, f), AcTokens.px(AcTokens.BAR_H, f))
		bar.size_flags_horizontal = pill_flags
		(stat_chips[id] as Control).size_flags_horizontal = pill_flags
		var icon := icons[id] as Control
		icon.visible = true
		icon.custom_minimum_size = Vector2.ONE * AcTokens.px(AcTokens.ICON_M, f)
	if not portrait:
		AcnhKit.gruppen_breite_angleichen(chips)
		return float(AcTokens.px(RING_KOMPAKT, f))
	# Hochkant: Ring füllt die Touch-Pille aus (W20/B8, unverändert).
	return maxf(roundf(ring_voll * f), floor_px - HudMehrCluster.innenrand_x(chips[0]))


## Gestaffelter Pop-In der Kapsel-Gruppe (Layout-Wechsel/Erstauftritt) —
## Reduced Motion: sofort da (MotionKit-Gate).
static func einblenden(chips: Array[Control]) -> void:
	var sichtbar: Array = []
	for chip in chips:
		if chip.is_visible_in_tree():
			sichtbar.append(chip)
	MotionKit.stagger_ein(sichtbar)


## Sanfter Puls bei spürbarer Wert-Änderung (≥ PULS_DELTA). Nie während der
## Alarm-Puls läuft oder gleich starten wird (der übernimmt die Bühne).
static func wert_puls(chip: Control, alt: float, neu: float, alarm: bool) -> void:
	if alarm or absf(neu - alt) < PULS_DELTA:
		return
	MotionKit.puls(chip)


## Alarm-Puls (Stat < 25) starten: Loop-Tween am CHIP (W19-Lehre: stirbt
## der Chip zuerst, stirbt der Tween lautlos mit — nie „Target object
## freed“ am langlebigen HUD). Reduced Motion: statischer Alarm-Tint,
## Rückgabe null (der Aufrufer bucht den Alarm trotzdem als aktiv).
static func alarm_puls_start(chip: Control, reduced_motion: bool) -> Variant:
	if reduced_motion:
		chip.modulate = Color(1.0, 0.82, 0.82)
		return null
	chip.pivot_offset = chip.size / 2.0
	var tween := chip.create_tween().set_loops()
	tween.tween_property(chip, "scale", Vector2.ONE * 1.07, ALERT_PULS_S)
	tween.parallel().tween_property(chip, "modulate", Color(1.0, 0.8, 0.8), ALERT_PULS_S)
	tween.tween_property(chip, "scale", Vector2.ONE, ALERT_PULS_S)
	tween.parallel().tween_property(chip, "modulate", Color.WHITE, ALERT_PULS_S)
	return tween


## Alarm-Puls stoppen und den Chip in die Ruhelage zurücksetzen.
static func alarm_puls_stop(chip: Control, tween: Variant) -> void:
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	chip.scale = Vector2.ONE
	chip.modulate = Color.WHITE
