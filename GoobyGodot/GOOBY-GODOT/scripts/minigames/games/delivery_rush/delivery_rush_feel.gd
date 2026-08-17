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
## W19 Kulissen-Klemme: so viel Luft (m) hält der Kamera-Boom zu Hauswänden.
const CAM_CLEAR_M := 1.2
## W19 Erste-Lieferung-Beat (s): so lange steht der Erklär-Banner — deckt den
## Anfahrts-Median (~9 s reine Fahrzeit, Probe Seeds 1..40) zusammen mit dem
## Intro-Banner gut ab.
const FIRST_LEG_BANNER_S := 4.5
## Nach so vielen Sim-Sekunden blendet der Steuer-Hinweis aus (M6-Kanon).
const HINT_FADE_SEC := 7.0

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


## PURE Kulissen-Klemme für den Kamera-Boom (W19, Live-Demo-Befund: dunkle
## Hauswände füllten die obere Bildhälfte, sobald der Verfolger-Boom beim
## Spurwechsel in einen Häuserblock schwenkte). Liefert den Anteil 0..1 der
## XZ-Strecke Wagen→Wunsch-Kamera, der VOR der ersten (um `margin` erweiterten)
## Gebäude-AABB-Wand liegt — 1,0 = ganz frei, 0,0 = Start klebt an der Wand.
static func cam_free_t(from: Vector2, to: Vector2, boxes: Array, margin := 1.2) -> float:
	var best := 1.0
	for box: Dictionary in boxes:
		var lo := Vector2(float(box["minX"]) - margin, float(box["minZ"]) - margin)
		var hi := Vector2(float(box["maxX"]) + margin, float(box["maxZ"]) + margin)
		best = minf(best, _entry_t(from, to - from, lo, hi))
	return best


## Slab-Test (Liang-Barsky): Eintritts-Parameter der Strecke `from + t·d` in
## das AABB [lo, hi], geklemmt auf 0..1 — oder 1,0, wenn die Strecke verfehlt.
static func _entry_t(from: Vector2, d: Vector2, lo: Vector2, hi: Vector2) -> float:
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		if absf(d[axis]) < 1e-9:
			if from[axis] < lo[axis] or from[axis] > hi[axis]:
				return 1.0
			continue
		var ta := (lo[axis] - from[axis]) / d[axis]
		var tb := (hi[axis] - from[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1 or t1 < 0.0 or t0 > 1.0:
		return 1.0
	return maxf(0.0, t0)


## Kappt die GEGLÄTTETE Kamera-Pose in der XZ-Ebene vor der ersten Hauswand
## (der Lerp schwenkt beim Abbiegen sonst durch Blockecken) — der gekappte
## Wert wird zurückgeschrieben, damit die Kamera weich wieder ausfedert.
static func clamp_cam(pos: Vector3, van: Vector2, boxes: Array) -> Vector3:
	var boom := Vector2(pos.x, pos.z)
	var free_t := cam_free_t(van, boom, boxes, CAM_CLEAR_M)
	if free_t >= 1.0:
		return pos
	var safe := van.lerp(boom, free_t)
	return Vector3(safe.x, pos.y, safe.y)


## Sichtbarkeit des Steuer-Hinweises (1 → 0 über 1,2 s ab HINT_FADE_SEC).
static func hint_alpha(elapsed: float) -> float:
	return clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


## W19: Steuer-Hinweis als Tinte auf Milchglas (Banner-Muster) — die nackte
## Konturschrift lag unlesbar über Asphalt und rosa Routenband (Live-Demo).
## Stylt Label UND Plate zusammen; positioniert wird im Spiel (_layout_hud).
func make_hint(plate: StyleBoxFlat) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SoftLabel"
	label.text = I18nService.t("mg.deliveryRush.hint")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.42, 0.24, 0.16))
	label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	plate.set_corner_radius_all(12)
	return label


## W19: Milchglas-Plate hinter dem Steuer-Hinweis — unter dem Label gemalt
## (Kinder-Canvas-Items liegen über dem Eltern-_draw des Spiels).
func draw_hint_plate(canvas: CanvasItem, plate: StyleBoxFlat, label: Label, alpha: float) -> void:
	if alpha <= 0.0 or label == null:
		return
	plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * alpha)
	canvas.draw_style_box(plate, Rect2(label.position - Vector2(0.0, 2.0), label.size))


## W19 Erste-Lieferung-Beat: benennt das erste Ziel, sobald das Intro-Banner
## gefallen ist — leer, wenn schon zugestellt wurde (dann erklärt sich das
## Feld von selbst). Reine View-Schicht, die Sim-Zahlen bleiben unangetastet.
func first_leg_text(drops: int, parcel: int, targets: Array) -> String:
	if drops != 0 or parcel >= targets.size():
		return ""
	var name := I18nService.t("mg.deliveryRush.spot.%s" % targets[parcel])
	return I18nService.t("mg.deliveryRush.first_leg", {"name": name})


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
