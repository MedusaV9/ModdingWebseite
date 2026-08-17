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
## W20/P4: Pillar-Kulisse + Spielfeld-Rahmen + Top-Bar-Layout (Doku dort).
const StageChrome := preload("res://scripts/minigames/host_stage_chrome.gd")
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
## POLISH-E/W13B: so lange steht die Teleport-Cutscene (Veil + Text über dem
## eingefrorenen letzten Spielbild samt Gooby-Grimasse), bevor der Host die
## Runde regulär beendet (Echtzeit — Zeitlupen dehnen nichts).
const STRIKE_CUTSCENE_SEC := 1.8

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
## W20/P4: Paper-Rahmen-Karte hinter dem letterboxten Spielfeld — folgt
## _layout_stage und verankert den Pillar-Streifen optisch im Raum.
var _stage_frame: Panel
var _overlay: Control
## W17/INTEGRATE (Q1): eigene Juice-Ebene, die exakt dem letterboxten
## Viewport-Container folgt — Spiele reichen Viewport-Pixel aus
## _stage.to_screen() in float_text/overlay_burst/overlay_ring, und die
## landeten vorher im Fenster-Raum (Texte/Ringe klebten im Creme-Rand).
var _float_layer: Control
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
## POLISH-E/W13B: Strikes der laufenden Runde (ctx.strike() zählt über
## MinigameFrameworkLogic.apply_strike) + Flags/Overlay der Teleport-
## Cutscene ab dem 3. Strike. Spiele OHNE strike()-Aufrufe (die 36
## Bestandsspiele) berühren diesen Pfad nie.
var _strikes := 0
var _strike_out := false
var _strike_veil: Control
## W19/GEIST: Rekord-Geist der Runde — Rekorder samt Referenzkurve (pure
## Logik geist_rekord.gd; null = kein Tracking, z. B. vor dem GO) und der
## dezente ±Delta-Chip in der Top-Bar (nur sichtbar mit Bestlauf-Kurve UND
## Live-Score-Fluss — Spiele ohne Score-Meldungen bleiben chip-frei).
var _geist: GeistRekord
var _geist_chip: GeistChip
## W21/P4: Bühnen-Deko (Schild + Gooby-Silhouette + Backdrop-Referenz für
## die Resize-Nachführung), Zeit-Chip der Top-Bar und der ±Delta-Float.
var _backdrop: ColorRect
var _stage_schild: PanelContainer
var _stage_gooby: TextureRect
var _score_kapsel: PanelContainer
var _zeit_chip: ZeitChip
var _score_float: Label


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
	# W20/P4 Pillar-Behandlung + W21/P4 „Bühne statt Farbnebel“: Themen-
	# Kulisse + Spielname-Schild + Gooby-Silhouette + Paper-Rahmen-Karte —
	# Aufbau und Layout-Regeln leben in host_stage_chrome.gd (Doku dort).
	_backdrop = StageChrome.baue_backdrop(game_id)
	add_child(_backdrop)
	_stage_schild = StageChrome.baue_schild(
		I18nService.t(str(_meta.get("title_key", game_id))), game_id
	)
	add_child(_stage_schild)
	_stage_gooby = StageChrome.baue_gooby_silhouette()
	add_child(_stage_gooby)
	_stage_frame = StageChrome.baue_stage_frame()
	add_child(_stage_frame)

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

	# Q1: Juice-Ebene deckungsgleich zum Spielfeld (Sync in _layout_stage) —
	# Float-Texte/Bursts treffen so den Punkt, den das Spiel meinte, und
	# Flashes/Konfetti rahmen das Feld statt der Letterbox-Flächen.
	_float_layer = Control.new()
	_float_layer.name = "JuiceLayer"
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)
	juice.float_text_parent = _float_layer

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# W21/P4 (b): EIN Host-Chrome oben — Score-Frost-Kapsel, Geist-Chip,
	# Zeit-Chip, Pause aus EINER Fabrik (StageChrome.baue_top_bar; der
	# Geist-Chip lebt weiter in der Top-Bar, NICHT im Juice-Layer — W19).
	var teile := StageChrome.baue_top_bar(_on_pause_pressed)
	_top_bar = teile["bar"] as HBoxContainer
	_score_kapsel = teile["score_kapsel"] as PanelContainer
	_score_label = teile["score"] as Label
	_geist_chip = teile["geist"] as GeistChip
	_zeit_chip = teile["zeit"] as ZeitChip
	_pause_button = teile["pause"] as Button
	_overlay.add_child(_top_bar)

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
	_results.back_pressed.connect(_on_results_back)
	# G7-P56: dritter Rahmen-Knopf (Nochmal/Arcade/Home) — beide Ausgänge
	# laufen über _exit_to und damit über DENSELBEN Router-Wipe.
	_results.home_pressed.connect(_on_results_home)
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
	_ctx.on_strike = _on_game_strike
	_apply_car_context()
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
	if _geist_chip != null:
		_geist_chip.skaliere(f)
	if _zeit_chip != null:
		_zeit_chip.skaliere(f)
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
	# W20/P4: Rahmen-Karte + Top-Bar folgen dem SPIELFELD statt den
	# Canvas-Ecken (Befunde B1 + C6) — Regeln in host_stage_chrome.gd.
	var f := UiScale.for_viewport(get_viewport())
	StageChrome.layout(_stage_frame, _top_bar, _viewport_container, size, fitted, f, insets)
	# W21/P4 (a): Schild + Silhouette in die freien Bühnen-Bänder legen und
	# die Muster-Kachelung der Kulisse nachführen (Regeln im Chrome).
	StageChrome.layout_deko(
		_stage_schild, _stage_gooby, _viewport_container, size, fitted, f, insets
	)
	StageChrome.aktualisiere_backdrop(_backdrop, size, f)
	if _float_layer != null:
		# Q1: _stage ist FULL_RECT am Host-Ursprung, darum ist die Container-
		# Position direkt Host-Raum — die Juice-Ebene spiegelt sie 1:1.
		_float_layer.position = _viewport_container.position
		_float_layer.size = fitted
	# W21: Countdown über der SPIELFELD-Mitte statt der Canvas-Mitte
	# (Pillar-/Letterbox-Befund) — Regel in host_stage_chrome.gd.
	StageChrome.zentriere_countdown(_countdown_label, _viewport_container.position, fitted, size)
	if juice != null:
		# Läuft gerade ein Shake, würde er die ALTE Container-Ruhelage
		# zurückschreiben — Re-Zuweisung lässt ihn die Basis neu lernen
		# (Setter-Vertrag am shake_target des JuiceKit).
		juice.shake_target = _viewport_container


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
		# W19/GEIST: der Rekorder startet GENAU mit dem Spiel (t=0 = GO —
		# dieselbe Zeitbasis wie die gespeicherte Bestlauf-Kurve).
		_geist_start()
		_game.start()


## W19/GEIST: Geist-Zeit ist Framework-Zeit — sie läuft NUR, solange auch
## das Spiel wirklich tickt (nach dem GO, Runde offen, kein Pause-/Strike-
## Freeze des SubViewports, keine spielinterne Pause). Zeitlupen dehnen den
## _process-Delta wie das Spiel selbst — Geist und Spieler bleiben synchron.
func _process(delta: float) -> void:
	if _geist == null or _round_over or _game == null or not is_instance_valid(_game):
		return
	if _viewport_container == null:
		return
	if _viewport_container.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	if not _game.is_active():
		return
	_geist.tick(delta, score)
	_aktualisiere_geist_chip()
	# W21/P4 (b): der Zeit-Chip zeigt DIESELBE Framework-Zeit — er steht in
	# Pause/Freeze und dehnt in Zeitlupen exakt wie das Spiel selbst.
	if _zeit_chip != null:
		_zeit_chip.zeige_zeit(_geist.zeit())


## W19/GEIST: Rekorder frisch aufsetzen — Referenz ist der gespeicherte
## Bestlauf dieses Spiels (leer → der Chip bleibt die ganze Runde weg).
func _geist_start() -> void:
	_geist = GeistRekord.new()
	var referenz: Dictionary = {}
	var gs := _resolve_state()
	if gs != null and gs.has_method("state"):
		referenz = GeistRekord.rekord_von(gs.state(), game_id)
	_geist.starte(referenz)
	if _geist_chip != null:
		_geist_chip.setze_zurueck()


## Chip-Gating (W19/GEIST): sichtbar nur mit Referenzkurve UND Live-Score-
## Fluss in einer offenen Runde — sonst konsequent versteckt.
func _aktualisiere_geist_chip() -> void:
	if _geist_chip == null:
		return
	if _geist == null or _round_over or not _geist.hat_referenz() or not _geist.hat_live_score():
		_geist_chip.hide()
		return
	_geist_chip.zeige_delta(_geist.delta_aktuell(score))
	_geist_chip.show()


func _on_game_score(total: int, delta: int) -> void:
	score = total
	_score_label.text = I18nService.t("mg.host.score", {"score": total})
	# W19/GEIST: jede Live-Meldung öffnet das Geist-Gate (Spiele, die nie
	# report_score rufen, bekommen weder Chip noch Kurve).
	if _geist != null and not _round_over:
		_geist.melde_live_score()
		_aktualisiere_geist_chip()
	# W21/P4 (b): dezenter ±Delta-Float unter der Score-Kapsel (Regeln im
	# Chrome, MotionKit-Grammatik — Reduced Motion überspringt die Tweens).
	if not _round_over and _top_bar != null and _top_bar.visible:
		_score_float = StageChrome.score_float(
			_score_float, _overlay, _score_kapsel, delta, UiScale.for_viewport(get_viewport())
		)


func _on_game_end(result: Dictionary) -> void:
	if _round_over:
		return
	_round_over = true
	score = int(result.get("score", score))
	_pause_button.disabled = true
	# W18 B2: Juice-Reste der Runde (Combo-„×N“, Edge-Glow, Float-Texte)
	# räumt der HOST beim Rundenende deterministisch ab — vorher überlagerte
	# das Combo-Label den Results-Titel und schwebte in die Folgerunde. Der
	# End-Moment (_schedule_end_moment) feiert DANACH mit frischen Effekten.
	if juice != null:
		juice.clear_overlays()
	var breakdown := _award(score, result)
	# W19/GEIST: „Geist geschlagen“ (Bestlauf am Rundenende überholt) feiert
	# die Results-Karte einmalig; die Kurven-Ablösung selbst passiert im
	# _award-Update (EIN Save-Umlauf). Danach Chip abbauen + Tracking aus.
	breakdown["geistGeschlagen"] = _geist != null and _geist.geschlagen(score)
	if _geist_chip != null:
		_geist_chip.hide()
	_geist = null
	_unlock_orientation()
	round_finished.emit(breakdown)
	# POLISH-A: dem Siegmoment im Spiel (Zeitlupe, Konfetti, Jubel-Text) eine
	# Atempause lassen, bevor der Results-Screen ihn zudeckt. Echtzeit-Timer
	# (ignore_time_scale), damit die Zeitlupe die Pause nicht dehnt; unter
	# Reduced Motion erscheint der Screen sofort.
	var delay := 0.0 if _reduced_motion() else 0.9
	if delay <= 0.0 or get_tree() == null:
		_zeige_results(breakdown)
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
		_zeige_results(breakdown)


## Gemeinsamer Einblende-Pfad beider Results-Wege (sofort/verzögert).
## W18 B7: die Top-Bar verschwindet mit — ihr fertiger Punktestand spoilerte
## sonst den Score-Count-Up der Karte („★ 60“ neben hochzählenden „9 Punkte“).
func _zeige_results(breakdown: Dictionary) -> void:
	if _top_bar != null:
		_top_bar.hide()
	# W21/P4: der ±Delta-Float lebt im Overlay (nicht in der Bar) — er darf
	# den Count-Up der Karte genauso wenig spoilern wie der Punktestand.
	if _score_float != null and is_instance_valid(_score_float):
		_score_float.hide()
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
	# W13B: nach 3 Strikes IST die Teleport-Cutscene der End-Moment — kein
	# Sieg-Konfetti über dem „nach Hause teleportiert“-Veil.
	if _strike_out:
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
## ohne State) gibt es ein reines Anzeige-Breakdown ohne Buchung. `result` =
## report_end-Dictionary des Spiels (optionale Sammlungs-Funde, W13/SAMMLUNG).
func _award(final_score: int, result: Dictionary = {}) -> Dictionary:
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
	# W19/GEIST: Bestlauf-Kandidat der Runde ({} ohne Live-Score-Fluss) —
	# die Ablösung ersetzt die Kurve GENAU beim neuen Rekord (roher Score).
	var geist_id := game_id
	var geist_snap: Dictionary = _geist.snapshot(final_score) if _geist != null else {}
	# FERTIG-1: Runde regulär beendet — der Refund-Snapshot verfällt.
	_modifier_snapshot = {}
	gs.update(
		func(state: Dictionary) -> void:
			holder.append(MinigameAward.award(state, meta, final_score, mode, today, chunks, mod))
			# W13/SAMMLUNG: organische Sticker-Funde der Runde (fish/landmarks).
			CollectionsLogic.award_report(state, result)
			GeistRekord.uebernehme_rekord(state, geist_id, geist_snap)
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
	# W18 B2: Juice-Ebene mit einfrieren/verstecken — das Combo-„×N“ (z_index
	# 96) lag sonst ÜBER dem Pause-Modal („P×2e“ im Pause-Titel). Beim
	# Weiterspielen blendet _run_resume_countdown sie wieder ein.
	if _float_layer != null:
		_float_layer.hide()
	_pause_modal.open()


## Fortsetzen (Modal-Knopf/Backdrop/Back-Geste): Modal ist schon zu —
## erst der 3-2-1-Countdown, dann läuft das Spiel weiter.
func _on_resume_requested() -> void:
	if _game == null or _round_over:
		_set_game_frozen(false)
		if _float_layer != null:
			_float_layer.show()
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
	# W18 B2: Juice-Ebene wieder einblenden (bei Pause versteckt) — eine
	# laufende Combo-Anzeige gehört zur weiterlaufenden Runde.
	if _float_layer != null:
		_float_layer.show()
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
	# W18 B2: kein Overlay-Rest (Combo/Glow) über dem Aus-Wipe zur Arcade.
	if juice != null:
		juice.clear_overlays()
	# W19/GEIST: Abbruch zeichnet keinen Bestlauf auf — Tracking + Chip weg.
	_geist = null
	if _geist_chip != null:
		_geist_chip.hide()
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


## Results „Zur Arcade“ — gebundene Methode statt Lambda (Rahmen-Ausgang).
func _on_results_back() -> void:
	_exit_to(&"arcade", {})


## Results „Nach Hause“ (G7-P56): der Router löst &"home" auf den zuletzt
## besuchten Raum auf (FIX1-Alias) — gleicher Aus-Wipe wie der Arcade-Weg.
func _on_results_home() -> void:
	_exit_to(&"home", {})


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
	# W18 B2/B7: Feier-/Combo-Reste der Vorrunde abräumen und die bei Pause
	# versteckte Juice-Ebene sowie die bei Results versteckte Top-Bar wieder
	# einblenden — die Folgerunde startet mit sauberem Overlay + HUD.
	if juice != null:
		juice.clear_overlays()
	if _float_layer != null:
		_float_layer.show()
	if _top_bar != null:
		_top_bar.show()
	_round_over = false
	score = 0
	_coin_chunks = []
	# W19/GEIST: Tracking der Vorrunde weg — der frische Rekorder kommt beim
	# GO (_geist_start liest dann auch eine eben abgelöste Kurve neu ein).
	_geist = null
	if _geist_chip != null:
		_geist_chip.setze_zurueck()
	# W21/P4: Zeit-Chip auf 0:00, Float-Rest der Vorrunde weg.
	if _zeit_chip != null:
		_zeit_chip.setze_zurueck()
	if _score_float != null and is_instance_valid(_score_float):
		_score_float.hide()
	# W13B: Strike-Zustand + Cutscene-Reste der Vorrunde aufräumen.
	_strikes = 0
	_strike_out = false
	if _strike_veil != null:
		_strike_veil.hide()
	_set_game_frozen(false)
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


## POLISH-E/W13B: ctx.strike()-Callback — zählt über apply_strike und zündet
## AB dem 3. Strike die Teleport-Cutscene. Rückgabe ans Spiel wie
## apply_strike ({"strikes": n, "teleport": bool}).
func _on_game_strike() -> Dictionary:
	var result := MinigameFrameworkLogic.apply_strike(_strikes)
	_strikes = int(result["strikes"])
	if bool(result["teleport"]) and not _round_over and not _strike_out:
		_strike_out = true
		_run_strike_cutscene()
	return result


## Mini-Cutscene nach dem Results-/Pause-Overlay-Muster (KEIN neues
## Cinematic-System): die Spielzeit friert ein (das letzte Bild mit Goobys
## Grimasse bleibt unter dem Veil stehen — die „Emotion“ liefert das Spiel
## selbst, z. B. City Drives dizzy-Emote beim 3. Crash), darüber Veil +
## „nach Hause teleportiert“-Text. Nach STRIKE_CUTSCENE_SEC endet die Runde
## regulär mit dem aktuellen Score — der Award bleibt unverändert korrekt.
func _run_strike_cutscene() -> void:
	_pause_button.disabled = true
	if _game != null:
		_game.pause()
	_set_game_frozen(true)
	_zeige_strike_veil()
	FeelSfx.play(self, "game_lose")
	if juice != null:
		juice.hit_flash(Color(0.9, 0.4, 0.25, 0.18), 260)
	if get_tree() == null:
		_ende_strike_runde()
		return
	# Echtzeit-Timer + gebundene Methode (REST5, B2): stirbt der Host vorher,
	# trennt Godot die Verbindung automatisch.
	get_tree().create_timer(STRIKE_CUTSCENE_SEC, true, false, true).timeout.connect(
		_ende_strike_runde
	)


func _ende_strike_runde() -> void:
	if not _strike_out or _round_over:
		return
	if _game != null:
		_game.end()
	_on_game_end({"score": score})


func _zeige_strike_veil() -> void:
	if _strike_veil == null:
		# Aufbau lebt im StageChrome (Chrome-Baukasten, Host-Zeilen-Deckel).
		_strike_veil = StageChrome.baue_strike_veil(_strikes)
		add_child(_strike_veil)
		# UNTER dem Results-Screen einsortieren: der Rundenreport deckt die
		# Cutscene nachher ab, nicht umgekehrt.
		if _results != null:
			move_child(_strike_veil, _results.get_index())
	_strike_veil.show()
	if juice != null:
		var title := _strike_veil.get_node_or_null("Rows/StrikeTitle")
		if title != null:
			juice.scale_pop(title, 1.35, 320)


## W13B/DRIVE (Doc G §6): bei Fahr-Spielen (FrameworkLogic.CAR_GAMES) das
## AUSGEWÄHLTE Autohaus-Auto in den Kontext legen und den BESTEHENDEN
## `car_speed_mult`-Hook des Spiels bedienen (deliveryRush deklariert ihn
## seit 3D-B als „Autohaus-Hook“; cityDrive liest ctx.car direkt). Ohne
## GameState (Tests) bleibt ctx.car {} — Neutralbasis, alles fährt wie
## bisher. toyRacer/shoppingSurf sind KEINE CAR_GAMES (Spielzeug/Wagen).
func _apply_car_context() -> void:
	if not MinigameFrameworkLogic.CAR_GAMES.has(game_id):
		return
	var gs := _resolve_state()
	if gs == null or not gs.has_method("get_value"):
		return
	var auto := AutoKatalog.aktives_auto(gs)
	if auto.is_empty():
		return
	auto["mults"] = CarStatsLogic.multipliers(auto.get("stats", {}))
	_ctx.car = auto
	if _game != null and "car_speed_mult" in _game:
		_game.set("car_speed_mult", float((auto["mults"] as Dictionary)["speed"]))


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


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
