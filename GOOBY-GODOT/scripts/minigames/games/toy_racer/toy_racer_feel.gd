extends Node
## Fahrgefühl- und HUD-Schicht des Spielzeug-Rennens (G5 P35, Audit C §7).
## Reines VIEW-Gefühl nach dem delivery_rush_feel-Muster — keine Spielzahl
## wird angefasst:
##   - Motor-Loop aus ranch_ambience_wind (G4-ROCKET-Muster: eigener Player,
##     play()-Gate, Spool-Fade, Pitch folgt dem Tempo; RM/Pause stoppt sauber).
##   - Banner auf Creme-Plate + Kontur mit Umbruch (M7) — vorher stand der
##     Creme-Text direkt auf der warmweißen Kinderzimmerwand.
##   - Item-Chip auf der HUD-Plate (das zweite Kern-Verb „Tippen = Item"
##     bekommt eine lesbare Zustandsanzeige statt reiner Textzeile).

## G4-ROCKET-Muster: bestes vorhandenes Loop-Material als Motor-Rauschen —
## nur MOTOR_SFX_ID tauschen, falls ein echtes Motor-SFX kommt.
const MOTOR_SFX_ID := "ranch_ambience_wind"
## Chip-Farben je Item-Art (passend zu den Banner-Momenten des Spiels).
const ITEM_TINTS := {
	"turbo": Color(1.0, 0.66, 0.3),
	"shield": Color(0.45, 0.75, 0.98),
	"block": Color(0.9, 0.5, 0.42),
}

var _motor: AudioStreamPlayer
var _motor_spool := 0.0
var _banner_plate := StyleBoxFlat.new()
var _chip_plate := StyleBoxFlat.new()


## Motor-Loop bauen — eigener Player, weil AudioDirector-One-Shots keinen
## Live-Pitch können. Bus "Sfx" ⇒ Nutzer-Regler/Limiter gelten weiter.
func build_motor() -> void:
	var path := SfxMap.path(MOTOR_SFX_ID)
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = (load(path) as AudioStream).duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_motor = AudioStreamPlayer.new()
	_motor.bus = &"Sfx"
	_motor.stream = stream
	_motor.volume_db = -30.0
	add_child(_motor)


## Godot-Gotcha (rocket-Muster): stream_paused wirkt nur auf LAUFENDE
## Playbacks — play() zündet erst bei der ERSTEN Fahrt, danach pausiert/weckt
## der Loop. `driving` = aktiv, kein Intro/Ende, kein Reduced Motion;
## `band01` = Tempoband 0..1 mit Leerlauf-Sockel 0,3 (das Kart „surrt" auch
## im Stand), Pitch/Volumen folgen ihm über den Spool: langsam rein (Fade
## statt Schalter), schnell raus (Pause/RM stoppt hörbar sofort).
func sync_motor(delta: float, driving: bool, band01: float) -> void:
	if _motor == null:
		return
	var target := maxf(0.3, clampf(band01, 0.0, 1.0)) if driving else 0.0
	_motor_spool = move_toward(_motor_spool, target, (0.9 if driving else 4.0) * delta)
	var audible := driving and _motor_spool > 0.01
	if audible and not _motor.playing:
		_motor.play()
	_motor.stream_paused = not audible
	_motor.pitch_scale = 0.78 + 0.6 * _motor_spool
	_motor.volume_db = lerpf(-27.0, -12.0, _motor_spool)


func stop_motor() -> void:
	if _motor != null:
		_motor.stop()


## M7 (Audit C §7): Banner auf Creme-Plate mit Kontur und Umbruch
## (G4-Muster tea_party) statt nacktem Creme-Text vor der hellen Zimmerwand.
func draw_banner(canvas: CanvasItem, text: String, t: float, view: Vector2, ui: float) -> void:
	if t <= 0.0 or text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(t * 1.4, 0.0, 1.0)
	var font_size := maxi(18, int(26.0 * ui))
	var w := minf(view.x - 24.0, 440.0 * ui)
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size)
	var top := view.y * 0.17
	var pad := Vector2(18.0, 10.0) * ui
	_banner_plate.set_corner_radius_all(int(12.0 * ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.76 * alpha)
	var plate_pos := Vector2((view.x - text_size.x) * 0.5, top) - pad
	canvas.draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.42, 0.28, 0.18, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((view.x - w) * 0.5, top + font.get_ascent(font_size))
	canvas.draw_multiline_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * ui), rim
	)
	canvas.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)


## Item-Chip auf der HUD-Plate (Audit C §7 P4): getönte Pille + Farbpunkt,
## solange ein Item einliegt; leer = gedeckter „—"-Platzhalter. Nutzt NUR
## bestehende Strings (mg.toyRacer.item_*_short / item_none).
func draw_item_chip(canvas: CanvasItem, origin: Vector2, item: String, ui: float) -> void:
	var h := 24.0 * ui
	var dot_r := 5.0 * ui
	var font := ThemeService.font(700)
	var font_size := maxi(11, int(14.0 * ui))
	var text := (
		I18nService.t("mg.toyRacer.item_none")
		if item.is_empty()
		else I18nService.t("mg.toyRacer.item_%s_short" % item)
	)
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var w := text_w + dot_r * 2.0 + 26.0 * ui
	var tint: Color = ITEM_TINTS.get(item, Color(0.6, 0.52, 0.46))
	_chip_plate.set_corner_radius_all(int(h * 0.5))
	_chip_plate.bg_color = (
		Color(0.45, 0.36, 0.3, 0.16)
		if item.is_empty()
		else Color(tint.lerp(Color.WHITE, 0.62), 0.95)
	)
	canvas.draw_style_box(_chip_plate, Rect2(origin, Vector2(w, h)))
	var dot := origin + Vector2(9.0 * ui + dot_r, h * 0.5)
	canvas.draw_circle(dot, dot_r + 1.5 * ui, Color(0.4, 0.3, 0.24, 0.4))
	canvas.draw_circle(dot, dot_r, tint if not item.is_empty() else Color(0.7, 0.62, 0.56))
	canvas.draw_string(
		font,
		Vector2(dot.x + dot_r + 7.0 * ui, origin.y + h * 0.5 + font_size * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(0.4, 0.3, 0.25) if not item.is_empty() else Color(0.52, 0.44, 0.38)
	)
