class_name MinigameHost
extends Control
## Minigame-Host (Doc G): lädt das Spiel in einen SubViewport (Pillar-/
## Letterbox auf die Ziel-Orientierung), fährt den 3-2-1-Countdown, besitzt
## Pause-Overlay + Results-Screen und bucht den Award über GameState
## (MinigameAward — Reason 'minigame'/'endless'). OrientationService wird
## beim Start gelockt (Hochkant/Quer) und beim Verlassen entsperrt.
##
## Router-Params (SceneRouter receive_params-Contract):
##   {game_id: String, difficulty: "easy|normal|hard|endless",
##    orientation: "auto|portrait|landscape", seed: int (optional, Tests)}

signal exit_requested(target: StringName, params: Dictionary)
signal round_finished(breakdown: Dictionary)
## EF-3 F3: der Host hat den zentralen End-Moment gezündet ("win"/"lose").
signal end_moment_fired(kind: String)

const RESULTS_SCENE := preload("res://scripts/minigames/results.tscn")
const Stats := preload("res://scripts/logic/stats.gd")
## Design-Basis wie im Web (CSS-Baseline 390×844).
const DESIGN_PORTRAIT := Vector2(390, 844)
## OrientationService.LockMode (W1a-Contract FROZEN: AUTO/LANDSCAPE/PORTRAIT).
const LOCK_LANDSCAPE := 1
const LOCK_PORTRAIT := 2
## EF-3 F3: so kurz nach report_end prüft der Host, ob das Spiel selbst
## gefeiert hat; danach zündet er den zentralen End-Moment.
const END_MOMENT_DELAY_SEC := 0.12
## Ein spieleigener win_moment() innerhalb dieses Fensters (ms) unterdrückt
## den Auto-Moment (die 5 Selbst-Feierer zünden ihn direkt am Rundenende).
const END_MOMENT_GRACE_MS := 1100

## Sekunden pro Countdown-Schritt (Tests drehen auf ~0).
## EF-3 F4: 0,6 statt 0,8 — der Auftakt bleibt lesbar, wartet aber nicht.
var countdown_step_sec := 0.6
## FB3: Sekunden pro Schritt des 3-2-1-WEITERSPIEL-Countdowns nach Pause.
var resume_step_sec := 0.45
## EF-3 F2: „Nochmal“/Neustart überspringt den 3-2-1 — nur „GO!“ für diese
## Zeit, dann läuft die frische Runde (Erststart behält den vollen Countdown).
var quick_go_sec := 0.5
## Duck-Typing-Overrides für Tests (null → /root/GameState bzw. /root/…).
var state_node: Node = null
var auto_navigate := true

var game_id := ""
var difficulty := "normal"
var orientation_choice := "auto"
var run_seed := 0
var score := 0
var juice: JuiceKit

var _meta: Dictionary = {}
var _game: MinigameBase
var _ctx: MinigameCtx
var _stage: Control
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _overlay: Control
var _top_bar: HBoxContainer
var _score_label: Label
var _countdown_label: Label
var _pause_modal: MinigamePauseModal
var _pause_button: Button
var _results: MinigameResults
var _round_over := false
var _countdown_token := 0
## FB3: Stage-Oberkante in Canvas-px (misst _apply_metrics aus der Top-Bar).
var _stage_top := 56.0
## Coin-würdige Teil-Scores der Session (GvZ meldet pro gewonnenem Level —
## die Coin-Row wird dann PRO Chunk statt auf den Session-Score angewandt).
var _coin_chunks: Array[int] = []
## FERTIG-1 (EVAL Rang 12): beim echten Rundenstart konsumiertes Modifier-
## Event (Snapshot für Refund bei Früh-Abbruch) + dessen Launch-Params
## (coin_mult/score_mult/xp_mult/energy_free/gluecksrolle) für den Award.
var _modifier_snapshot: Dictionary = {}
var _modifier_params: Dictionary = {}


func receive_params(params: Dictionary) -> void:
	game_id = str(params.get("game_id", ""))
	difficulty = str(params.get("difficulty", "normal"))
	orientation_choice = str(params.get("orientation", "auto"))
	run_seed = int(params.get("seed", 0))


func _ready() -> void:
	# E14-P0-2: set_anchors_preset() behält das aktuelle (0×0-)Rect bei —
	# unter dem Router-Mount (Node3D, kein Control-Parent) blieb der Host
	# damit unsichtbar klein. and_offsets füllt den Viewport wirklich.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_meta = MinigameRegistry.get_game(game_id)
	if _meta.is_empty() or not _meta.has("scene"):
		push_warning("[mg_host] unbekanntes Spiel '%s' — zurück zur Arcade" % game_id)
		_exit_to(&"arcade", {})
		return
	if _is_exhausted():
		# §C1 (Web-Parität): erschöpfte Goobys spielen nicht — Pregame blockt
		# das schon, der Guard fängt Direkt-Routen (Deeplinks/Tests) ab.
		push_warning("[mg_host] Gooby erschöpft — Start verweigert")
		_exit_to(&"arcade", {})
		return
	difficulty = MinigameFrameworkLogic.effective_difficulty(
		game_id, {"difficulty": difficulty}, _meta
	)
	if run_seed == 0:
		run_seed = maxi(1, randi() & 0x7FFFFFFF)
	_build_ui()
	_lock_orientation()
	_mount_game()
	resized.connect(_on_host_resized)
	_apply_metrics()
	_layout_stage()
	_run_countdown()


func _exit_tree() -> void:
	_countdown_token += 1
	Engine.time_scale = 1.0
	_unlock_orientation()


## Effektive Lauf-Orientierung: Pregame-Wahl > globale AppSettings-Präferenz
## (orientation_mode) > Spiel-Default aus der Registry.
func effective_orientation() -> String:
	if orientation_choice == "portrait" or orientation_choice == "landscape":
		return orientation_choice
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("orientation_mode"):
		var global_mode: String = settings.orientation_mode()
		if global_mode == "portrait" or global_mode == "landscape":
			return global_mode
	return MinigameFrameworkLogic.normalize_orientation(_meta.get("orientation"))


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# EF-3 F6: die Pillar-/Letterbox-Flächen sind Theme-Creme, aber nackt —
	# eine leise 8%-Vignette gibt ihnen Tiefe und rahmt das Spielfeld,
	# ohne vom Spiel abzulenken (statisch, kein Perf-Kostenpunkt).
	var vignette := ColorRect.new()
	vignette.name = "BarsVignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_mat := ShaderMaterial.new()
	vignette_mat.shader = _vignette_shader()
	vignette.material = vignette_mat
	add_child(vignette)

	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_stage.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = true
	_viewport_container.add_child(_viewport)

	juice = JuiceKit.new()
	juice.shake_target = _viewport_container
	add_child(juice)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	juice.float_text_parent = _overlay

	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 16.0
	_top_bar.offset_right = -16.0
	_top_bar.offset_top = 10.0
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_top_bar)
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	_score_label.text = I18nService.t("mg.host.score", {"score": 0})
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_bar.add_child(_score_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(spacer)
	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.theme_type_variation = &"GhostButton"
	_pause_button.text = I18nService.t("mg.host.pause")
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_button.disabled = true
	_top_bar.add_child(_pause_button)

	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = &"TitleLabel"
	# POLISH-A: der Countdown ist DER Auftakt-Moment aller Spiele — die Ziffer
	# dominiert den Schirm (mit Outline lesbar auf jedem Spielhintergrund).
	_countdown_label.add_theme_font_size_override("font_size", 150)
	_countdown_label.add_theme_color_override("font_outline_color", Color(1.0, 0.98, 0.92, 0.9))
	_countdown_label.add_theme_constant_override("outline_size", 10)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_countdown_label)

	# FB3: kompaktes, mittiges Pause-Modal (scripts/minigames/ui) statt des
	# alten Vollflächen-Overlays — echte Pause + 3-2-1 macht der Host.
	_pause_modal = MinigamePauseModal.new()
	_pause_modal.hint_key = "mg.%s.hint" % game_id
	_pause_modal.resume_requested.connect(_on_resume_requested)
	_pause_modal.restart_requested.connect(_on_restart_requested)
	_pause_modal.quit_requested.connect(_on_quit_pressed)
	add_child(_pause_modal)

	_results = RESULTS_SCENE.instantiate()
	_results.hide()
	_results.again_pressed.connect(_on_again_pressed)
	_results.back_pressed.connect(func() -> void: _exit_to(&"arcade", {}))
	add_child(_results)


func _mount_game() -> void:
	var packed: PackedScene = load(str(_meta["scene"]))
	var node := packed.instantiate()
	if not (node is MinigameBase):
		push_warning("[mg_host] Szene %s ist kein MinigameBase" % _meta["scene"])
		node.queue_free()
		_exit_to(&"arcade", {})
		return
	_game = node
	_ctx = MinigameCtx.new()
	_ctx.game_id = game_id
	_ctx.difficulty = difficulty
	_ctx.orientation = effective_orientation()
	_ctx.run_seed = run_seed
	_ctx.juice = juice
	_ctx.on_score = _on_game_score
	_ctx.on_end = _on_game_end
	_ctx.on_coin_chunk = _on_coin_chunk
	_viewport.add_child(_game)
	_game.setup(_ctx)


func _on_host_resized() -> void:
	_apply_metrics()
	_layout_stage()


## FB3: Top-Bar in die Safe-Area einpassen und mit der ZENTRALEN UiScale-
## Regel skalieren (vorher: feste 16/10-px-Offsets, Pause-Knopf unter dem
## Touch-Floor und hinter der Notch).
func _apply_metrics() -> void:
	if _top_bar == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	_top_bar.offset_left = float(insets["left"]) + 12.0 * f
	_top_bar.offset_right = -float(insets["right"]) - 12.0 * f
	_top_bar.offset_top = float(insets["top"]) + 6.0 * f
	ScreenShell.touch_target(_pause_button, m)
	ScreenShell.scale_fonts(_top_bar, f)
	ScreenShell.scale_fonts(_countdown_label, f)
	_stage_top = _top_bar.offset_top + _top_bar.get_combined_minimum_size().y + 6.0 * f


## Pillar-/Letterbox: Stage auf die Ziel-Orientierung einpassen — unter der
## Top-Bar und INNERHALB der Safe-Area (Notch/Home-Indicator).
func _layout_stage() -> void:
	if _viewport_container == null:
		return
	var insets := UiScale.safe_insets_canvas(get_viewport())
	var left := float(insets["left"])
	var right := float(insets["right"])
	var bottom := float(insets["bottom"])
	var avail := Vector2(size.x - left - right, size.y - _stage_top - bottom)
	if avail.x <= 0 or avail.y <= 0:
		return
	var design := DESIGN_PORTRAIT
	if effective_orientation() == "landscape":
		design = Vector2(DESIGN_PORTRAIT.y, DESIGN_PORTRAIT.x)
	var scale_factor := minf(avail.x / design.x, avail.y / design.y)
	var fitted := design * scale_factor
	_viewport_container.position = Vector2(
		left + (avail.x - fitted.x) * 0.5, _stage_top + (avail.y - fitted.y) * 0.5
	)
	_viewport_container.size = fitted


## Countdown mit Federung und steigender Tonhöhe (POLISH-A): jede Ziffer
## ploppt ein und klingt einen Schritt höher, das GO bekommt Goldblitz +
## großen Pop — derselbe Belohnungsmoment für ALLE Spiele. EF-3 F4: pro
## Tick ein weißer 40-ms-Flash übers Spielfeld, das GO schüttelt kurz.
## quick=true (EF-3 F2, Retry): kein 3-2-1 — „GO!“ steht quick_go_sec, dann
## startet die frische Runde (fairer Bereitmach-Moment statt Warteschleife).
func _run_countdown(quick := false) -> void:
	_countdown_token += 1
	var token := _countdown_token
	_countdown_label.show()
	if not quick:
		for step: int in [3, 2, 1]:
			_countdown_label.text = str(step)
			FeelSfx.play(self, "game_countdown", 0.9 + 0.12 * float(3 - step))
			if juice != null:
				juice.scale_pop(_countdown_label, 1.4, 300)
				juice.hit_flash(Color(1.0, 1.0, 1.0, 0.1), 40)
			await get_tree().create_timer(countdown_step_sec).timeout
			if token != _countdown_token or not is_inside_tree():
				return
	_countdown_label.text = I18nService.t("mg.host.go")
	FeelSfx.play(self, "game_go")
	if juice != null:
		juice.scale_pop(_countdown_label, 1.7, 380)
		juice.hit_flash(Color(1.0, 0.95, 0.7, 0.16), 240)
		juice.shake(0.15)
	_countdown_label.show()
	if quick:
		await get_tree().create_timer(maxf(quick_go_sec, 0.0)).timeout
		if token != _countdown_token or not is_inside_tree():
			return
	# Methoden-Callable statt Lambda (REST5, B2): stirbt das Label vor dem
	# Timeout (Szenenwechsel), trennt Godot die Verbindung automatisch.
	get_tree().create_timer(0.6).timeout.connect(_countdown_label.hide)
	_pause_button.disabled = false
	if _game != null:
		# FERTIG-1 (§C-SYS4.4): läuft für dieses Spiel ein Modifier-Event,
		# wird JETZT (echter Rundenstart) eine Runde konsumiert.
		_consume_modifier()
		if _ctx != null:
			_ctx.modifier = _modifier_params.duplicate(true)
		# Web-Parität §C6 (framework.js:1369-1377): die Energie wird erst
		# beim ECHTEN Rundenstart abgebucht (Abbruch im Countdown ist gratis).
		# FERTIG-1: Federleicht macht genau diese Abbuchung frei.
		if not _modifier_params.get("energy_free", false):
			_charge_energy()
		_game.start()


func _on_game_score(total: int, _delta: int) -> void:
	score = total
	_score_label.text = I18nService.t("mg.host.score", {"score": total})


func _on_game_end(result: Dictionary) -> void:
	if _round_over:
		return
	_round_over = true
	score = int(result.get("score", score))
	_pause_button.disabled = true
	var breakdown := _award(score)
	_unlock_orientation()
	round_finished.emit(breakdown)
	# POLISH-A: dem Siegmoment im Spiel (Zeitlupe, Konfetti, Jubel-Text) eine
	# Atempause lassen, bevor der Results-Screen ihn zudeckt. Echtzeit-Timer
	# (ignore_time_scale), damit die Zeitlupe die Pause nicht dehnt; unter
	# Reduced Motion erscheint der Screen sofort.
	var delay := 0.0 if _reduced_motion() else 0.9
	if delay <= 0.0 or get_tree() == null:
		_results.show_results(breakdown, _meta, juice)
		return
	# EF-3 F3: die Atempause ist nur verdient, wenn sie GEFÜLLT ist — der
	# Host inszeniert das Rundenende zentral für alle Spiele (s. unten).
	_schedule_end_moment(breakdown)
	# Gebundene Methode statt Lambda (REST5, B2): wird der Host vor dem
	# Timeout freigegeben, trennt Godot die Verbindung automatisch.
	get_tree().create_timer(delay, true, false, true).timeout.connect(
		_zeige_results_verzoegert.bind(breakdown)
	)


func _zeige_results_verzoegert(breakdown: Dictionary) -> void:
	if _round_over:
		_results.show_results(breakdown, _meta, juice)


## EF-3 F3 (EVAL-1: „0,9 s toter Standbild-Moment“): nur 5/37 Spiele riefen
## win_moment() selbst — jetzt zündet der HOST kurz nach report_end den
## passenden End-Moment für ALLE Spiele: Sieg = Zeitlupe + Goldblitz +
## Konfetti (JuiceKit.win_moment), Niederlage (0 Punkte) = weicher Trost-
## Moment ohne Konfetti. Spiele, die selbst feiern (JuiceKit merkt sich den
## letzten win_moment), bekommen KEINEN doppelten Effekt.
func _schedule_end_moment(breakdown: Dictionary) -> void:
	if juice == null or get_tree() == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _on_game_end.
	get_tree().create_timer(END_MOMENT_DELAY_SEC, true, false, true).timeout.connect(
		_zuende_end_moment.bind(breakdown)
	)


func _zuende_end_moment(breakdown: Dictionary) -> void:
	if not _round_over or juice == null:
		return
	if Time.get_ticks_msec() - juice.win_moment_msec <= END_MOMENT_GRACE_MS:
		return
	var kind := "win" if int(breakdown.get("score", 0)) > 0 else "lose"
	if kind == "win":
		juice.win_moment()
	else:
		juice.lose_moment()
	end_moment_fired.emit(kind)


## Award über GameState.update (Signale + Autosave); ohne GameState (Tests
## ohne State) gibt es ein reines Anzeige-Breakdown ohne Buchung.
func _award(final_score: int) -> Dictionary:
	var gs := _resolve_state()
	if gs == null:
		return {
			"gameId": game_id,
			"score": final_score,
			"coins": 0,
			"difficulty": difficulty,
			"firstToday": false,
			"newBest": false,
			"best": final_score,
			"xp": 0,
			"levelsGained": 0,
			"coinsFromLevels": 0,
			"dayCapReached": false,
			"beatTarget": false,
		}
	var today: String = gs.clock.local_day()
	var holder: Array[Dictionary] = []
	var meta := _meta
	var mode := difficulty
	var chunks := _coin_chunks.duplicate()
	var mod := _modifier_params.duplicate(true)
	# FERTIG-1: Runde regulär beendet — der Refund-Snapshot verfällt.
	_modifier_snapshot = {}
	gs.update(
		func(state: Dictionary) -> void:
			holder.append(MinigameAward.award(state, meta, final_score, mode, today, chunks, mod))
	)
	return holder[0] if holder.size() > 0 else {}


func _on_pause_pressed() -> void:
	if _game == null or _round_over or _pause_modal.is_open():
		return
	AudioDirector.try_play(self, "ui_open")
	_game.pause()
	# FB3 „pausiert WIRKLICH“: der SubViewport hört auf zu ticken (Zeit,
	# Timer, Tweens, Physik) — nicht nur das game_paused-Flag; Eingaben
	# frisst der Modal-Backdrop.
	_set_game_frozen(true)
	_pause_modal.open()


## Fortsetzen (Modal-Knopf/Backdrop/Back-Geste): Modal ist schon zu —
## erst der 3-2-1-Countdown, dann läuft das Spiel weiter.
func _on_resume_requested() -> void:
	if _game == null or _round_over:
		_set_game_frozen(false)
		return
	_run_resume_countdown()


## Alt-Pfad (bughunt_walkthrough ruft das direkt): wie Modal-Fortsetzen.
func _on_resume_pressed() -> void:
	if _pause_modal.is_open():
		_pause_modal.hide_modal()
	_on_resume_requested()


## FB3: 3-2-1 vor dem Weiterspielen — Echtzeit-Timer (das Spiel bleibt
## eingefroren, Zeitlupen-time_scale dehnt nichts), dann Freeze lösen.
func _run_resume_countdown() -> void:
	_countdown_token += 1
	var token := _countdown_token
	_pause_button.disabled = true
	_countdown_label.show()
	for step: int in [3, 2, 1]:
		_countdown_label.text = str(step)
		FeelSfx.play(self, "game_countdown", 0.9 + 0.12 * float(3 - step))
		if juice != null:
			juice.scale_pop(_countdown_label, 1.3, 240)
		await get_tree().create_timer(maxf(resume_step_sec, 0.0), true, false, true).timeout
		if token != _countdown_token or not is_inside_tree():
			return
	_countdown_label.hide()
	_set_game_frozen(false)
	if _game != null:
		_game.resume()
	_pause_button.disabled = _round_over


func _on_restart_requested() -> void:
	_set_game_frozen(false)
	_restart_round()


func _on_quit_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	if _pause_modal.is_open():
		_pause_modal.hide_modal()
	_set_game_frozen(false)
	# FERTIG-1: Früh-Abbruch erstattet die konsumierte Modifier-Runde
	# (max. einmal pro Event — Engine-Regel, Anti-Farming §C-SYS4.4).
	if not _round_over:
		_refund_modifier()
	if _game != null:
		_game.end()
	_exit_to(&"arcade", {})


## Zeit + Eingaben des Spiels wirklich anhalten/freigeben: process aus für
## den SubViewport-Ast (Timer/Tweens/Physik stehen), letztes Bild bleibt
## unter der Abdunkelung sichtbar stehen.
func _set_game_frozen(frozen: bool) -> void:
	if _viewport_container == null:
		return
	_viewport_container.process_mode = (
		Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	)


func _on_again_pressed() -> void:
	_restart_round()


## Interner Neustart (gleiche Difficulty/Orientierung, frischer Seed) —
## gemeinsamer Pfad für Results-„Nochmal“ UND Pause-„Neustart“ (FB3).
## EF-3 F2: Der Neustart nutzt den Quick-GO (kein 3-2-1) — der Spielzustand
## ist trotzdem KOMPLETT frisch (neue Spielinstanz, Score/Chunks/Seed reset,
## Energie wird wie immer erst beim echten Start abgebucht).
func _restart_round() -> void:
	if _is_exhausted():
		# Jede Runde kostet Energie (§C6) — erschöpft geht es zurück zur
		# Arcade statt in eine Gratis-Runde.
		_exit_to(&"arcade", {})
		return
	# FERTIG-1: Neustart MITTEN in der Runde (Pause-Modal) bricht die
	# laufende Runde ab → Refund; der Neustart konsumiert dann regulär neu.
	if not _round_over:
		_refund_modifier()
	_results.hide()
	_round_over = false
	score = 0
	_coin_chunks = []
	run_seed = maxi(1, randi() & 0x7FFFFFFF)
	_score_label.text = I18nService.t("mg.host.score", {"score": 0})
	_pause_button.disabled = true
	if _game != null:
		_game.queue_free()
		_game = null
	_lock_orientation()
	_mount_game()
	_run_countdown(true)


func _exit_to(target: StringName, params: Dictionary) -> void:
	_unlock_orientation()
	exit_requested.emit(target, params)
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(target, params)


func _lock_orientation() -> void:
	var svc := get_node_or_null("/root/OrientationService")
	if svc == null or not svc.has_method("lock"):
		return
	var mode := LOCK_LANDSCAPE if effective_orientation() == "landscape" else LOCK_PORTRAIT
	svc.lock(mode)


func _unlock_orientation() -> void:
	var svc := get_node_or_null("/root/OrientationService")
	if svc != null and svc.has_method("unlock"):
		svc.unlock()


func _resolve_state() -> Node:
	if state_node != null:
		return state_node
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("update") and gs.get("clock") != null:
		return gs
	return null


## Coin-würdiger Teil-Score (GvZ: pro gewonnenem Level) — die Coin-Row wird
## im Award PRO Chunk angewandt statt einmal auf den Session-Score (E10-P1-3).
func _on_coin_chunk(amount: int) -> void:
	if amount > 0:
		_coin_chunks.append(amount)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


## Warme, sehr leise Rand-Vignette für die Letterbox-Balken (EF-3 F6).
static func _vignette_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.35, 0.85, length(d) * 1.35);
	COLOR = vec4(0.35, 0.22, 0.12, edge * 0.08);
}
"""
	return shader


## §C1 Web-Parität: Energie <= 15 → Minigames verweigern den Start.
func _is_exhausted() -> bool:
	var gs := _resolve_state()
	if gs == null or not gs.has_method("state"):
		return false
	var state: Dictionary = gs.state()
	var gooby: Variant = state.get("gooby")
	if not (gooby is Dictionary):
		return false
	var stats: Variant = (gooby as Dictionary).get("stats")
	if not (stats is Dictionary):
		return false
	return Stats.is_exhausted(stats)


## §C6 Web-Parität (E10-P1-2): jeder Rundenstart kostet meta.energy_cost
## (Default 8 = MINIGAME.ENERGY_COST) — DIE Bremse gegen den Coin-Hahn.
func _charge_energy() -> void:
	var gs := _resolve_state()
	if gs == null:
		return
	var cost := int(_meta.get("energy_cost", MinigameRegistry.DEFAULT_ENERGY_COST))
	if cost <= 0:
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if not (gooby is Dictionary):
				return
			var stats: Variant = (gooby as Dictionary).get("stats")
			if not (stats is Dictionary):
				return
			stats["energy"] = Stats.clamp_stat(
				float((stats as Dictionary).get("energy", 0.0)) - float(cost)
			)
	)


## FERTIG-1 (EVAL Rang 12): beim ECHTEN Rundenstart eine Modifier-Runde
## konsumieren (Engine prüft Spiel/Fenster/Budget selbst). Merkt sich den
## Snapshot (Refund bei Abbruch) und die Launch-Params (Award/ctx).
func _consume_modifier() -> void:
	_modifier_snapshot = {}
	_modifier_params = {}
	var gs := _resolve_state()
	if gs == null:
		return
	var id := game_id
	var now := int(gs.clock.now_ms())
	var holder: Array[Dictionary] = []
	gs.update(
		func(state: Dictionary) -> void: holder.append(ModifierEngine.consume(state, id, now))
	)
	var res: Dictionary = holder[0] if holder.size() > 0 else {}
	if res.get("ok", false):
		_modifier_snapshot = res.get("modifier", {})
		_modifier_params = ModifierEngine.launch_params(_modifier_snapshot)


## FERTIG-1: Früh-Abbruch-Erstattung (Engine erstattet max. 1×/Event).
func _refund_modifier() -> void:
	if _modifier_snapshot.is_empty():
		return
	var snap := _modifier_snapshot.duplicate(true)
	_modifier_snapshot = {}
	_modifier_params = {}
	var gs := _resolve_state()
	if gs == null:
		return
	var now := int(gs.clock.now_ms())
	gs.update(func(state: Dictionary) -> void: ModifierEngine.refund(state, snap, now))
