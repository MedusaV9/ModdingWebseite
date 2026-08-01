extends Node
## Fahrgefühl- und HUD-Schicht der Liefer-Hetze (G5 P32, Audit A §2.7).
## Reines VIEW-Gefühl nach dem runner_feel-Muster — keine Spielzahl wird
## angefasst:
##   - Motor-Loop aus ranch_ambience_wind (G4-ROCKET-Muster: eigener Player,
##     play()-Gate, Spool-Fade, Pitch folgt dem Tempo; RM/Pause stoppt sauber).
##   - Wand-Bump: gedrosselte Sound-Wiederholrate + Karosserie-Ruck-Wert +
##     Crash-Staub am Kontaktpunkt (vorher spammte mg_junk jeden Frame).
##   - Banner auf Milchglas-Plate + Kompass-Text mit Kontur (M7) — die
##     draw-Helfer malen auf dem übergebenen CanvasItem des Spiels.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## G4-ROCKET-Muster: bestes vorhandenes Loop-Material als Motor-Rauschen —
## nur MOTOR_SFX_ID tauschen, falls ein echtes Motor-SFX kommt.
const MOTOR_SFX_ID := "ranch_ambience_wind"
## Frühestens alle 0,45 s ein Wand-Bump-Ton (vorher: jeden Frame).
const BUMP_COOLDOWN_SEC := 0.45
## Dunkler Abendstadt-Saum für Banner/Kompass (M7).
const OUTLINE_INK := Color(0.24, 0.16, 0.12, 0.8)

## Karosserie-Ruck 1→0; der Aufrufer mischt ihn als Nick-Winkel in die Pose.
var body_kick := 0.0

var _motor: AudioStreamPlayer
var _motor_spool := 0.0
var _bump_cool := 0.0
var _banner_plate := StyleBoxFlat.new()


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
## der Loop. `driving` = aktiv, kein Intro, kein Reduced Motion; `band01` =
## Tempoband 0..1 mit Leerlauf-Sockel 0,3 (der Wagen „tuckert" auch im Stand),
## Pitch/Volumen folgen ihm über den Spool: langsam rein (Fade statt Schalter),
## schnell raus (Pause/RM stoppt hörbar sofort).
func sync_motor(delta: float, driving: bool, band01: float) -> void:
	if _motor == null:
		return
	var target := maxf(0.3, clampf(band01, 0.0, 1.0)) if driving else 0.0
	_motor_spool = move_toward(_motor_spool, target, (0.9 if driving else 4.0) * delta)
	var audible := driving and _motor_spool > 0.01
	if audible and not _motor.playing:
		_motor.play()
	_motor.stream_paused = not audible
	_motor.pitch_scale = 0.72 + 0.55 * _motor_spool
	_motor.volume_db = lerpf(-26.0, -11.0, _motor_spool)


func stop_motor() -> void:
	if _motor != null:
		_motor.stop()


## Zerfall der Gefühls-Werte — jeden Frame vom Spiel aus ticken.
func tick(delta: float) -> void:
	body_kick = maxf(0.0, body_kick - 4.0 * delta)
	_bump_cool = maxf(0.0, _bump_cool - delta)


## Wand-Bump: EIN gedrosselter Ton + Karosserie-Ruck + Staub am Kontaktpunkt
## (Q2: der Partikel-Burst nur ohne Reduced Motion). `host` spielt den Ton.
func bump(host: Node, reduced: bool, dust: GPUParticles3D, at: Vector3) -> void:
	if _bump_cool > 0.0:
		return
	_bump_cool = BUMP_COOLDOWN_SEC
	kick()
	AudioDirector.try_play(host, "mg_junk", 0.9)
	if not reduced and dust != null:
		Fx.burst(dust, at)


## Karosserie-Ruck anstoßen (auch der Verkehrs-Crash nutzt ihn).
func kick() -> void:
	body_kick = 1.0


## PURE Band-Verschlankung (testbar): unter 22 m zum Ziel wird das
## Wegweiser-Band linear schmaler (bis 55 %) — auf den letzten Metern
## dominierte der volle Läufer das Zielbild (Audit A §2.7).
static func route_slim(dist_m: float) -> float:
	return clampf(dist_m / 22.0, 0.55, 1.0)


## M7 (Audit A §2.7): Banner auf Milchglas-Plate mit Kontur und Umbruch
## (rocket-Muster) statt nackter Goldschrift über dem Pfirsichhimmel.
func draw_banner(canvas: CanvasItem, text: String, t: float, view: Vector2, ui: float) -> void:
	if t <= 0.0 or text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(t * 1.2, 0.0, 1.0)
	var font_size := maxi(18, int(26.0 * ui))
	var w := minf(view.x - 24.0, 420.0 * ui)
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size)
	var top := view.y * 0.2
	var pad := Vector2(18.0, 10.0) * ui
	_banner_plate.set_corner_radius_all(int(12.0 * ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	var plate_pos := Vector2((view.x - text_size.x) * 0.5, top) - pad
	canvas.draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.42, 0.24, 0.16, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((view.x - w) * 0.5, top + font.get_ascent(font_size))
	canvas.draw_multiline_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * ui), rim
	)
	canvas.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)


## Kompass-Pfeil zum Abwurfring (aus delivery_rush._draw_compass hierher
## gezogen; M7: die Meter-Zahl bekommt eine Kontur). Der Pfeil zeigt in
## FAHRZEUG-Koordinaten (oben = geradeaus).
func draw_compass(
	canvas: CanvasItem,
	van_pos: Vector2,
	van_heading: float,
	drop: Vector2,
	view: Vector2,
	ui: float
) -> void:
	var to := drop - van_pos
	if to.length() < 1.0:
		return
	var fwd := Vector2(sin(van_heading), -cos(van_heading))
	var side := Vector2(-fwd.y, fwd.x)
	var local := Vector2(to.dot(side), -to.dot(fwd)).normalized()
	var center := view * 0.5
	var radius := minf(view.x, view.y) * 0.3
	var tip := center + local * radius
	var perp := Vector2(-local.y, local.x)
	var a := 16.0 * ui
	(
		canvas
		. draw_colored_polygon(
			PackedVector2Array(
				[
					tip + local * a,
					tip - local * a * 0.5 + perp * a * 0.62,
					tip - local * a * 0.5 - perp * a * 0.62,
				]
			),
			Color(1.0, 0.8, 0.3, 0.92)
		)
	)
	var font := ThemeService.font(700)
	var w := 110.0 * ui
	var text := "%d m" % int(to.length())
	var at := tip + local * a * 1.5 - Vector2(w * 0.5, 0.0)
	var font_size := maxi(13, int(18.0 * ui))
	canvas.draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, int(4.0 * ui), OUTLINE_INK
	)
	canvas.draw_string(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, Color(1.0, 0.98, 0.92)
	)
