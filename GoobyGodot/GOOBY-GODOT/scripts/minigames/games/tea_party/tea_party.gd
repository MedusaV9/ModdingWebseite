extends MinigameBase
## Teestube (teaParty) — Spiel-Szene. Die MECHANIK-Zahlen kommen 1:1 aus
## TeaPartyLogic (zahlengleich zum Web, Bot-zertifiziert): Halten gießt
## (FILL_RATE), Loslassen im Band punktet (perfect +6 / good +3), Überlauf/
## daneben = Spill, jeder 3. Perfect in Folge +2, Kadenz zieht an. 60 s
## (Endlos: bis 3 Spills). JuiceKit (float_text, hit_freeze/bloom bei Perfect,
## shake/hit_freeze bei Spill) + SFX über AudioDirector.
##
## ECHTE 3D-STUBE (FB-4, TeaPartyStage3D): Gooby steht als Gastgeber am Tisch,
## die Kanne kippt beim Gießen, der Tee steigt als echter Zylinder in der
## Glastasse und das Zielband liegt als Glasring UM die Tasse. Die 3D-Welt
## hängt unter der Node2D-Wurzel (Godot rendert 3D hinter den CanvasItems),
## der MinigameBase-Vertrag bleibt unberührt.
##
## W17/G4-Generalkur (NUR Präsentation, Audit g4 §3.1): Intro-Beat 1,5 s
## gatet die Sim (M1), 2D-Füllmeter neben der Tasse zeigt Level/Band der
## Logik (M4/M6), Banner mit Plate+Kontur für Serie/Spill/Ergebnis (M7),
## Gieß-Loop mit Füllstands-Pitch + Endton mg_win/mg_lose (M3/M8/M10),
## _ui-skaliertes HUD + Hint-Fade (M9/M6). TeaPartyLogic bleibt unangetastet.

const Stage := preload("res://scripts/minigames/games/tea_party/tea_party_stage3d.gd")

## M1: Intro-Beat (s) — Kamera-Totale + Ziel-Banner, die Sim wartet (W14-Kanon).
const INTRO_S := 1.5
## M6: nach so vielen Sim-Sekunden blendet der Hinweis aus (Fade ~1,5 s).
const HINT_FADE_AT_S := 5.0
## M3/M10: Gieß-Loop aus VORHANDENEM Wasser-Foley (kein neues Audio-File);
## eigener Player statt AudioDirector-Loop, weil nur so der Pitch live dem
## Füllstand folgen kann (cityDrive-Wind-Muster d9dc66a9).
const POUR_SFX_ID := "care_wasser"
## Füllmeter-Farben: Tee-Säule, Good-Band, Perfect-Kern, Überlauf-Deckel.
const METER_TEA := Color(0.72, 0.45, 0.18, 0.95)
const METER_BAND := Color(0.36, 0.74, 0.42, 0.78)
const METER_PERFECT := Color(1.0, 0.68, 0.16, 0.92)
const METER_RIM := Color(0.85, 0.32, 0.25, 0.9)
const METER_EMPTY := Color(1.0, 0.99, 0.94, 0.30)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var cups := 0
var spills := 0
var streak := 0
var elapsed := 0.0
var level := 0.0
var band: Dictionary = {}
var holding := false
var serving := true
var serve_left := 0.6
var cup_slide := 1.0
var finished := false
var view_size := Vector2(390.0, 844.0)

var _time_label: Label
var _streak_label: Label
var _hint_label: Label
var _stage: Node3D
var _ui := 1.0
var _intro_left := 0.0
var _banner := ""
var _banner_t := 0.0
var _banner_gold := false
var _banner_plate := StyleBoxFlat.new()
var _hud_plate := StyleBoxFlat.new()
var _hint_plate := StyleBoxFlat.new()
var _meter_plate := StyleBoxFlat.new()
var _pour: AudioStreamPlayer


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = TeaPartyLogic.apply_difficulty(TeaPartyLogic.TEA, ctx.difficulty)
	rng = ctx.rng()
	band = TeaPartyLogic.roll_band(rng, tune)
	_stage = Stage.new()
	_stage.name = "Stube3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_labels()
	_build_pour()
	_fit_viewport()
	# M1: Intro-Beat — Kamera-Totale der Stube + Ziel-Banner; die Sim
	# (elapsed/Servier-Uhr/Eingabe) wartet, der Lauf bleibt zahlengleich.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.teaParty.intro"), false, INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func start() -> void:
	super.start()
	serving = true
	serve_left = 0.5


func end() -> void:
	super.end()
	finished = true
	if _pour != null:
		_pour.stop()


func _build_labels() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	add_child(_streak_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.teaParty.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	# W21/P5: Zeit/Serie als Kit-Chip (Frost-Pille), Hinweis-Plate im
	# Milchglas-Kanon — die Stube zog sonst direkt durch die Ziffern.
	_hint_plate.set_corner_radius_all(12)
	_meter_plate.bg_color = Color(0.32, 0.24, 0.2, 0.35)
	_meter_plate.set_corner_radius_all(8)
	_update_labels()


## M3/M10: Gieß-Loop-Player — leise Wasser-Foley aus der SfxMap, Bus „Sfx"
## (Nutzer-Regler + Limiter gelten). play() startet erst beim ersten Gießen;
## danach schaltet stream_paused (wirkt in Godot nur auf LAUFENDE Playbacks)
## und _sync_pour hebt Pitch/Volume mit dem Füllstand.
func _build_pour() -> void:
	var path := SfxMap.path(POUR_SFX_ID)
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = (load(path) as AudioStream).duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_pour = AudioStreamPlayer.new()
	_pour.bus = &"Sfx"
	_pour.stream = stream
	_pour.volume_db = -26.0
	add_child(_pour)


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## W21/P5: der _ui-Faktor kommt aus dem MgHudKit (EINE Quelle statt sechs).
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	_ui = MgHudKit.ui_scale(view_size)
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
	_layout_hud()
	_update_labels()
	queue_redraw()


## Bedienleiste im Kit-Standard (W21/P5): Zeit/Serie als Chip oben links,
## Hinweis mit Typo-MINIMUM (der 9-px-Befund TP-1 — MgHudKit.font_px
## bodenlos nie unter 14 px effektiv).
func _layout_hud() -> void:
	if _time_label == null:
		return
	MgHudKit.style_chip(_time_label, _streak_label, _ui)
	MgHudKit.layout_chip(_time_label, _streak_label, _ui)
	var pad := 16.0 * _ui
	var hint_w := minf(view_size.x - pad * 2.0, 360.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", MgHudKit.font_px(15.0, _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 48.0 * _ui)
	_hint_label.size = Vector2(hint_w, 42.0 * _ui)


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	_sync_pour()
	if not is_active() or finished:
		return
	# M1: Intro-Beat — die Kamera schwebt aus der Stuben-Totale in die
	# Spielpose, das Ziel steht als Banner; elapsed/Servier-Uhr warten so
	# lange (der Lauf bleibt zahlengleich, test_mg_tea_logic unberührt).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_stage.sync(level, band, false, cup_slide, delta, _reduced_motion())
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if serving:
		serve_left -= delta
		cup_slide = clampf(serve_left / 0.4, 0.0, 1.0)
		if serve_left <= 0.0:
			serving = false
			cup_slide = 0.0
	elif holding:
		level = TeaPartyLogic.fill_after(level, delta, tune)
		if level >= float(tune["OVERFLOW_LEVEL"]):
			_release()
	_stage.sync(level, band, holding, cup_slide, delta, _reduced_motion())
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or serving or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			holding = true
		elif holding:
			_release()


func _release() -> void:
	holding = false
	var res := TeaPartyLogic.pour_result(level, band, tune)
	var points := int(res["points"])
	score = TeaPartyLogic.apply_score(score, points)
	var cup_pos: Vector2 = _stage.cup_screen()
	if res["result"] == "perfect":
		streak += 1
		var bonus := TeaPartyLogic.streak_bonus_at(streak, tune)
		score = TeaPartyLogic.apply_score(score, bonus)
		_stage.celebrate(_reduced_motion())
		# Steigende Tonhöhe belohnt die Serie hörbar (ab 8er-Kette gedeckelt).
		AudioDirector.try_play(self, "mg_perfect", 1.0 + 0.06 * minf(streak - 1, 7.0))
		if ctx.juice != null:
			ctx.juice.float_text(cup_pos, "+%d" % (points + bonus), Color(1.0, 0.72, 0.2))
			ctx.juice.hit_freeze(45)
			ctx.juice.bloom_pulse(0.6)
		if bonus > 0:
			# W21/P5 Feier-Beat: die volle Serie feiert als Kit-Beat
			# (Gold-Pille + Sparkle, MotionKit/RM-gated), dazu der Combo-Ton.
			AudioDirector.try_play(self, "mg_combo")
			MgHudKit.feier_beat(
				self, view_size, _ui, I18nService.t("mg.teaParty.streak_banner", {"n": streak})
			)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
	elif res["result"] == "good":
		streak = 0
		_stage.cheer()
		AudioDirector.try_play(self, "mg_good")
		if ctx.juice != null:
			ctx.juice.float_text(cup_pos, "+%d" % points, Color(0.42, 0.6, 0.36))
	else:
		streak = 0
		spills += 1
		_stage.groan(_reduced_motion())
		AudioDirector.try_play(self, "mg_spill")
		# M7: Spill als zentriertes Banner mit Plate+Kontur — der kleine
		# float_text ging vor der Stube unter.
		_set_banner(I18nService.t("mg.teaParty.spill"), false)
		if ctx.juice != null:
			ctx.juice.shake(0.35)
			ctx.juice.hit_freeze(70)
	ctx.report_score(score, points)
	if TeaPartyLogic.endless_should_end(spills, tune):
		_finish()
		return
	# Servierte Tasse rutscht SICHTBAR nach links raus (nur Optik).
	if res["result"] != "spill":
		_stage.serve_ghost(level)
	# Nächste Tasse: Band neu würfeln, Kadenz aus der Logik.
	level = 0.0
	band = TeaPartyLogic.roll_band(rng, tune)
	cups += 1
	serving = true
	serve_left = TeaPartyLogic.serve_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	if _pour != null:
		_pour.stop()
	# M8: die Runde endete vorher STUMM (nur report_end) — jetzt Endton +
	# Ergebnis-Banner als hörbarer/sichtbarer Schlusspunkt.
	AudioDirector.try_play(self, end_sfx_for(score))
	if bool(tune["ENDLESS"]):
		_set_banner(I18nService.t("mg.teaParty.ende_spills"), false, 2.2)
	else:
		_set_banner(I18nService.t("mg.teaParty.ende_zeit", {"cups": cups}), score > 0, 2.2)
	queue_redraw()
	ctx.report_end({"score": score, "cups": cups, "spills": spills})


## Endton-Wahl (PUR für Tests, M8): eine gepunktete Runde klingt nach
## mg_win, eine Null-Runde nach mg_lose.
static func end_sfx_for(score_now: int) -> String:
	return "mg_win" if score_now > 0 else "mg_lose"


func _update_labels() -> void:
	if _time_label == null:
		return
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.teaParty.spills", {"spills": spills, "max": int(tune["ENDLESS_MAX_SPILLS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if streak > 0:
		_streak_label.text = I18nService.t("mg.game.streak", {"n": streak})
	else:
		_streak_label.text = ""
	_hint_label.modulate.a = _hint_alpha()


## M6: der Hinweis blendet nach ein paar Sim-Sekunden aus — die Stube gehört
## dann ganz der Kanne (elapsed wartet im Intro, der Fade startet also fair).
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - HINT_FADE_AT_S) / 1.5, 0.0, 1.0)


func _set_banner(text: String, gold := false, sec := 1.4) -> void:
	_banner = text
	_banner_gold = gold
	_banner_t = sec


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


## M3/M10: Gieß-Loop folgt dem Füllstand — voller = höher + etwas lauter.
## stream_paused statt stop hält die Loop-Position; Pause/Host-Ende gaten
## über is_active()/finished (cityDrive-Wind-Muster).
func _sync_pour() -> void:
	if _pour == null:
		return
	var pouring := is_active() and not finished and _intro_left <= 0.0 and holding and not serving
	_pour.stream_paused = not pouring
	if not pouring:
		return
	if not _pour.playing:
		_pour.play()
	var band01 := clampf(level / float(tune["OVERFLOW_LEVEL"]), 0.0, 1.0)
	_pour.pitch_scale = 0.9 + 0.5 * band01
	_pour.volume_db = lerpf(-26.0, -16.0, band01)


## 2D-Overlay über der Stube: Kit-Chip hinter Zeit/Serie, Milchglas hinter
## dem Hinweis (M6), Füllmeter neben der Tasse (M4) und die Banner-Ebene.
func _draw() -> void:
	if _time_label == null:
		return
	MgHudKit.draw_chip(self, _hud_plate, _time_label, _streak_label, _ui)
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = MgHudKit.plate_color(MgHudKit.PLATE_ALPHA * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)
	_draw_meter()
	_draw_banner()


## M4/M6: 2D-Füllmeter NEBEN der Tasse — reine ANZEIGE der Logik-Werte
## (level/band aus TeaPartyLogic): Good-Band grün, Perfect-Kern gold,
## Überlauf-Deckel rot; der Marker färbt sich mit der Zone. Die Höhe kommt
## aus den 3D-Ankern der Tasse (Meter sitzt AM Geschehen), Breite/Ränder
## skalieren mit _ui (M9).
func _draw_meter() -> void:
	if _stage == null or band.is_empty():
		return
	var anchors: Dictionary = _stage.fill_screen_anchors()
	var top: Vector2 = anchors["top"]
	var bottom: Vector2 = anchors["bottom"]
	if not top.is_finite() or not bottom.is_finite() or bottom.y - top.y < 12.0:
		return
	var w := 14.0 * _ui
	var rect := Rect2(Vector2(maxf(top.x, bottom.x), top.y), Vector2(w, bottom.y - top.y))
	draw_style_box(_meter_plate, rect.grow(3.0 * _ui))
	draw_rect(rect, METER_EMPTY)
	var center := float(band.get("center", 0.7))
	var half := float(band.get("half", 0.075))
	var perfect_half := float(band.get("perfectHalf", 0.028))
	draw_rect(meter_band_rect(rect, center, half), METER_BAND)
	draw_rect(meter_band_rect(rect, center, perfect_half), METER_PERFECT)
	draw_rect(Rect2(rect.position - Vector2(0.0, 3.0 * _ui), Vector2(w, 3.0 * _ui)), METER_RIM)
	var fill_y := meter_level_y(level, rect)
	if level > 0.001:
		draw_rect(
			Rect2(Vector2(rect.position.x, fill_y), Vector2(w, rect.end.y - fill_y)), METER_TEA
		)
	var marker := Color(1.0, 0.99, 0.94, 0.95)
	if absf(level - center) <= perfect_half:
		marker = METER_PERFECT
	elif absf(level - center) <= half:
		marker = Color(0.55, 0.95, 0.58)
	draw_rect(
		Rect2(
			Vector2(rect.position.x - 3.0 * _ui, fill_y - 1.5 * _ui),
			Vector2(w + 6.0 * _ui, 3.0 * _ui)
		),
		marker
	)


## Y-Pixel eines Füllstands im Meter-Rechteck (PUR für Tests): Level 0 =
## Unterkante, Level 1 (= OVERFLOW_LEVEL) = Oberkante, darüber geklemmt.
static func meter_level_y(level_now: float, rect: Rect2) -> float:
	return rect.end.y - clampf(level_now, 0.0, 1.0) * rect.size.y


## Zonen-Rechteck [center−half … center+half] im Meter-Rechteck (PUR für
## Tests) — Grundlage für Good-Band und Perfect-Kern.
static func meter_band_rect(rect: Rect2, center: float, half: float) -> Rect2:
	var top_y := meter_level_y(center + half, rect)
	return Rect2(
		Vector2(rect.position.x, top_y),
		Vector2(rect.size.x, meter_level_y(center - half, rect) - top_y)
	)


## Banner im Kit-Standard (W21/P5): EINE Größe/Optik über alle Spiele —
## Intro-Ziel, Spill und Ergebnis; lange Texte brechen um.
func _draw_banner() -> void:
	MgHudKit.draw_banner(self, _banner_plate, view_size, _ui, _banner, _banner_t, _banner_gold)
