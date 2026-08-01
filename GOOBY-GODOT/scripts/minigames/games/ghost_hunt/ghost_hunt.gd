extends MinigameBase
## Geisterjagd (ghostHunt) — Spiel-Szene. Alle MECHANIK-Zahlen kommen aus
## GhostHuntLogic (zahlengleich zum Web): 90-s-Runde, Sichtfenster 2.2 s → 0.9 s,
## Fang +3 mit Kettenbonus (max. +5), Kürbis-Attrappe −2, alle 25 s eine
## Buh-Welle mit 5 Geistern (≥ 4 Fänge = +10) sowie Laterne/Netz als Aufsammler.
##
## ECHTES 3D (Agent 3D-A, Rückbau): ein Friedhofsgarten in der Abenddämmerung.
## Die zwölf Verstecke aus `GhostHuntLogic.SPOTS` sind echte Grabsteine, Kürbisse
## und eine Gruft auf ihren Weltkoordinaten (x, z). Getippt wird auf Bildschirm-
## punkte: `Stage3D.to_screen()` liefert sie, der Daumenradius bleibt.
##
## G5/P31-SPLIT (die Datei stand bei 999/1000 Zeilen): der Weltbau wohnt in
## ghost_hunt_scenery.gd, HUD/Banner in ghost_hunt_hud.gd — HIER bleiben
## Sim-Anbindung, Sync je Frame, Tippen und die Ereignis-Übersetzung.
## G5-Politur (Audit A §2.10): Intro-Beat mit Gruft-Schwenk (M1/Q4),
## _ui-HUD-Skalierung (M9/Q5), Hint-Fade (Q3), Creme-Banner-Plate (M7),
## Reduced-Motion-Gate an der Funken-Call-Site (Q2), Eis-Ton fürs Fang-"+n".
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter, HUD/Banner sind CanvasItems obenauf.

const Logic := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

## Höhe eines Laken-Geistes in Metern.
const GHOST_H := 1.05
## Mindest-Tippfläche in Pixeln (Daumenregel — wie in der 2D-Fassung).
const TAP_MIN_PX := 34.0
## Tippradius eines Ziels in Weltmetern (wird auf den Schirm projiziert).
const TAP_WORLD_R := 0.46

## Farb-Kontrakt der Sync-Schicht — ghost_hunt_scenery.gd baut mit DENSELBEN
## Werten (liest sie über die view-Referenz), damit nichts auseinanderdriftet.
const GHOST_TINT := Color(0.93, 0.94, 1.0)
const WAVE_TINT := Color(0.85, 0.78, 1.0)
const LANTERN_TINT := Color(1.0, 0.694, 0.302)
const NET_TINT := Color(0.608, 0.878, 0.784)

## W17 M9 (Q5): Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (G4-Muster).
const DESIGN_SHORT := 390.0
## W17 M1 (Q4): Intro-Beat (s) — Kamera schwenkt von der Gruft zum Tor in die
## Spielpose, die Sim wartet (zahlengleicher Lauf, Crosscheck unberührt).
const INTRO_S := 1.5
## Blickpunkt der Spielpose (Mitte des Hofs — fit()-Zentrum in _frame_yard).
const YARD_CENTER := Vector3(0.0, 0.5, -3.1)

var state: Dictionary = {}
var view_size := Vector2(390.0, 844.0)
var landscape := false
var finished := false

## HUD/Banner-Helfer (G5/P31-Split — Labels, Pillen, Ereignisband).
var hud: GhostHuntHud

var _bob := 0.0
## W17 M9: HUD-Skalenfaktor (Kurzkante/390, geklemmt 0.75..3.0).
var _ui := 1.0
## W17 M1: Rest-Sekunden des Intro-Beats (0 = Spielbetrieb).
var _intro_left := 0.0
## Kameraposition der Spielpose (von _frame_yard gemerkt — der Intro-Schwenk
## fährt exakt dorthin, kein Ruck beim Übergang in den Spielbetrieb).
var _play_from := Vector3.ZERO

var _stage: Stage3D
var _gooby: GoobyActor
var _sparks: Spark3D
var _ghosts: Array[Dictionary] = []
var _decoys: Array[Dictionary] = []
var _tokens: Array[Dictionary] = []
var _lantern_light: OmniLight3D
var _sky: Node3D
var _mist: Array[Dictionary] = []


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	var tune := Logic.apply_difficulty(Logic.HUNT, ctx.difficulty)
	state = Logic.create_hunt(ctx.run_seed, tune)
	GhostHuntScenery.new(self).build_world()
	hud = GhostHuntHud.new(self)
	hud.build()
	_fit_viewport()
	# W17 M1: Intro-Beat — die Kamera hängt an der Gruft und schwenkt zum
	# Tor in die Spielpose; die Sim (Spawner/Uhr) wartet, der Lauf bleibt
	# danach zahlengleich (Crosscheck-Vertrag unberührt).
	_intro_left = INTRO_S
	hud.show_banner(I18nService.t("mg.ghostHunt.intro"), INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## Hochkant blickt die Kamera STEILER auf den Friedhof — sonst schiebt sich das
## schmale Bild voll Himmel und die hinteren Gräber liegen übereinander.
## W17 M9: der _ui-Faktor (Kurzkante/390, 0.75..3.0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.set_fov(44.0 if landscape else 40.0)
		_frame_yard()
		# Dreht das Gerät mitten im Intro, fährt der Schwenk aus der frisch
		# gerahmten Spielpose weiter (Reduced Motion hält sie direkt).
		if _intro_left > 0.0:
			_intro_camera(1.0 if _reduced_motion() else _intro_progress())
	if hud != null:
		hud.layout()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_bob += delta
	_stage.tick(delta)
	_gooby.tick(delta)
	_drift_mist()
	# W17 M1: Intro-Beat — Bühne und Gooby leben schon, aber die Sim-Uhr
	# (Spawner, Buh-Wellen, Aufsammler) wartet; Reduced Motion überspringt
	# die Kamerafahrt (Call-Site-Gate) und hält nur den Banner-Beat.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		hud.tick(delta, false)
		_intro_camera(1.0 if _reduced_motion() else _intro_progress())
		hud.update()
		queue_redraw()
		return
	hud.tick(delta, true)
	Logic.step_hunt(state, delta)
	_drain_events()
	_sync_ghosts()
	_sync_decoys()
	_sync_tokens()
	_sync_lantern()
	ctx.report_score(Logic.hunt_score(state), 0)
	hud.update()
	queue_redraw()
	if bool(state["ended"]):
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0:
		return
	if event is InputEventScreenTouch and event.pressed:
		_tap_at(event.position)


## Steht gerade ein sichtbarer Geist im Bild? (Screenshot-Treiber.)
func has_visible_ghost() -> bool:
	for rig: Dictionary in _ghosts:
		if (rig["root"] as Node3D).visible:
			return true
	return false


## Bildschirmpunkt des ersten sichtbaren Geistes (Screenshot-Treiber).
func first_ghost_screen() -> Vector2:
	for rig: Dictionary in _ghosts:
		var root: Node3D = rig["root"]
		if root.visible:
			return _stage.to_screen(root.position + Vector3(0.0, GHOST_H * 0.6, 0.0))
	return view_size * 0.5


# ------------------------------------------------------------------ Kamera


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Kamera vor dem Tor, erhöht über dem Hof — alle zwölf Verstecke und Gooby
## müssen ins Bild, sonst kann man nicht auf sie tippen.
func _frame_yard() -> void:
	if _stage == null or _gooby == null:
		return
	var points: Array = [
		Vector3(-2.9, 0.0, -1.3),
		Vector3(2.9, 0.0, -1.3),
		Vector3(-2.9, 1.4, -6.9),
		Vector3(2.9, 1.4, -6.9),
		Vector3(0.0, 2.4, -6.4),
		_gooby.position + Vector3(0.0, 1.15, 0.3),
		# Goobys FÜSSE gehören mit in den Kader — sonst schneidet ihn das
		# Querformat unten ab und der Spieler steht nur halb im Bild.
		_gooby.position + Vector3(0.0, 0.0, 0.75),
	]
	_stage.fit(points, YARD_CENTER, 30.0 if landscape else 38.0, 0.0, 0.9)
	_play_from = _stage.camera.position
	if _sky != null and _stage.camera != null:
		_sky.transform = _stage.camera.transform


## Fortschritt des Intro-Schwenks (0 = an der Gruft, 1 = Spielpose am Tor).
func _intro_progress() -> float:
	return 1.0 - _intro_left / INTRO_S


## W17 M1 (Q4): Kamera des Intro-Beats — sie hängt tief über dem Trampelpfad
## und blickt die Grabreihen entlang zur GRUFT (Nahaufnahmen verbietet das
## schmale Hochformat: KEEP_HEIGHT + fov 40 lassen horizontal nur ~2 m zu),
## dann steigt sie rückwärts zum TOR in die von _frame_yard gemerkte
## Spielpose. Bei progress = 1 ist sie EXAKT die fit()-Pose (kein Ruck).
func _intro_camera(progress: float) -> void:
	if _stage == null or _stage.camera == null:
		return
	var eased: float = smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	var crypt := _crypt_anchor()
	var from := (crypt + Vector3(-0.1, 1.3, 6.2)).lerp(_play_from, eased)
	var look := (crypt + Vector3(0.0, 0.9, 0.0)).lerp(YARD_CENTER, eased)
	_stage.aim(from, look)
	if _sky != null:
		_sky.transform = _stage.camera.transform


## Weltanker der Gruft aus den Logik-Verstecken (Startpunkt des Schwenks).
func _crypt_anchor() -> Vector3:
	for spot: Dictionary in Logic.SPOTS:
		if str(spot["kind"]) == "crypt":
			return Vector3(float(spot["x"]), 0.0, float(spot["z"]))
	return Vector3(0.0, 0.0, -6.4)


# ------------------------------------------------------------------ Abgleich


## Geister-Pool an die Logik hängen: Position, Hebekurve, Deckkraft, Aura.
func _sync_ghosts() -> void:
	var live: Array = state["ghosts"]
	var dt := get_process_delta_time()
	for i in _ghosts.size():
		var rig: Dictionary = _ghosts[i]
		var root: Node3D = rig["root"]
		if i >= live.size():
			root.visible = false
			continue
		var ghost: Dictionary = live[i]
		var lift := _ghost_lift(ghost)
		if lift <= 0.01:
			root.visible = false
			continue
		var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
		# ENTDECKUNGSMOMENT: taucht ein Geist NEU auf, blitzt seine Aura kurz
		# auf und ein leiser Tick lockt das Ohr — das Auge findet ihn, bevor
		# das Sichtfenster wieder zugeht.
		if not root.visible:
			rig["flash"] = 0.45
			AudioDirector.try_play(self, "ui_tick", 0.8)
		var flash := maxf(0.0, float(rig.get("flash", 0.0)) - dt)
		rig["flash"] = flash
		root.visible = true
		root.position = _ghost_world(ghost, spot)
		root.scale = Vector3.ONE * (GHOST_H * (0.72 + 0.28 * lift))
		root.rotation.y = sin(_bob * 1.6 + float(ghost["id"])) * 0.28
		var tint: Color = WAVE_TINT if ghost["wave"] != null else GHOST_TINT
		var mat: StandardMaterial3D = rig["mat"]
		mat.albedo_color = Color(tint, 0.62 + 0.34 * lift)
		mat.emission = tint
		mat.emission_energy_multiplier = (
			0.4 + (0.9 if bool(ghost["revealed"]) else 0.0) + flash * 2.2
		)
		var halo: MeshInstance3D = rig["halo"]
		var glow := 0.16 * lift + (0.2 if bool(ghost["revealed"]) else 0.0) + flash * 0.5
		_set_halo(halo, Color(LANTERN_TINT if bool(ghost["revealed"]) else tint, glow))


## Attrappen: nur im Flackerfenster glühen Gesicht und Aura auf.
func _sync_decoys() -> void:
	var active := {}
	for flick: Dictionary in state["flickers"]:
		active[int(flick["decoy"])] = float(state["t"]) - float(flick["startT"])
	for i in _decoys.size():
		var rig: Dictionary = _decoys[i]
		var mat: StandardMaterial3D = rig["face"]
		var halo: MeshInstance3D = rig["halo"]
		if not active.has(i):
			mat.emission_energy_multiplier = 0.0
			mat.albedo_color = Color(0.28, 0.18, 0.12)
			_set_halo(halo, Color(LANTERN_TINT, 0.0))
			continue
		var f := 0.55 + 0.45 * sin(float(active[i]) * 22.0)
		mat.emission_energy_multiplier = 2.2 * f
		mat.albedo_color = LANTERN_TINT
		_set_halo(halo, Color(LANTERN_TINT, 0.3 * f))


func _sync_tokens() -> void:
	var live := {}
	for token: Dictionary in state["tokens"]:
		live[str(token["kind"])] = int(token["window"])
	for rig: Dictionary in _tokens:
		var root: Node3D = rig["root"]
		var kind := str(rig["kind"])
		if not live.has(kind):
			root.visible = false
			continue
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(live[kind])]
		root.visible = true
		root.position = Vector3(
			float(anchor["x"]), 1.05 + sin(_bob * 2.4) * 0.09, float(anchor["z"])
		)
		root.rotation.y = _bob * 1.1


## Nebelschwaden träge treiben lassen (jede in eigener Phase um ihren Anker).
func _drift_mist() -> void:
	for i in _mist.size():
		var wisp: Dictionary = _mist[i]
		var node: Node3D = wisp["node"]
		var home: Vector3 = wisp["home"]
		var t := _bob * 0.16 + float(i) * 1.7
		node.position = home + Vector3(sin(t) * 0.8, sin(t * 1.7) * 0.06, cos(t * 0.8) * 0.5)


## Der Laternen-Aufsammler taucht den ganzen Hof kurz in warmes Licht.
func _sync_lantern() -> void:
	if _lantern_light == null:
		return
	var left := float(state["lanternT"])
	var boost := clampf(left / float(Logic.HUNT["LANTERN_SEC"]), 0.0, 1.0)
	_lantern_light.light_energy = 1.5 + 5.0 * boost
	_lantern_light.omni_range = 4.6 + 14.0 * boost


func _set_halo(node: MeshInstance3D, color: Color) -> void:
	var mat := node.get_active_material(0)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = color


## Weltposition eines Geistes: er steigt aus seinem Versteck auf.
func _ghost_world(ghost: Dictionary, spot: Dictionary) -> Vector3:
	var base := 0.34 if str(spot["kind"]) == "pumpkin" else 0.62
	if str(spot["kind"]) == "crypt":
		base = 1.5
	return Vector3(float(spot["x"]), base + _ghost_lift(ghost) * 0.72, float(spot["z"]) + 0.18)


## Aufsteig-/Absink-Kurve eines Geistes (RISE_FRAC/SINK_FRAC aus der Logik).
func _ghost_lift(ghost: Dictionary) -> float:
	var age := float(state["t"]) - float(ghost["spawnT"])
	var dur := maxf(0.001, float(ghost["dur"]))
	var f := clampf(age / dur, 0.0, 1.0)
	var rise := float(Logic.HUNT["RISE_FRAC"])
	var sink := float(Logic.HUNT["SINK_FRAC"])
	if f < rise:
		return _ease_out_back(f / rise)
	if f > 1.0 - sink:
		return maxf(0.0, (1.0 - f) / sink)
	return 1.0


func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ------------------------------------------------------------------ Tippen


## Tippradius eines Weltziels in Pixeln. Perspektive statt Handrechnung: der
## Radius wird als echte Strecke projiziert und bleibt mindestens daumengroß.
func _tap_radius(world: Vector3) -> float:
	var right := _stage.camera.global_transform.basis.x * TAP_WORLD_R
	var span := _stage.to_screen(world + right).distance_to(_stage.to_screen(world))
	return maxf(TAP_MIN_PX, span)


## Nächstliegendes Ziel unter dem Finger; Aufsammler haben Vorrang.
func _tap_at(pos: Vector2) -> void:
	var best := {}
	var best_d := INF
	for token: Dictionary in state["tokens"]:
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(token["window"])]
		var at := Vector3(float(anchor["x"]), 1.05, float(anchor["z"]))
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) * 1.2 and d < best_d:
			best_d = d
			best = {"kind": "token", "window": int(token["window"])}
	if best.is_empty():
		best = _pick_target(pos)
	Logic.tap_hunt(state, best)
	_drain_events()


## Geister und Attrappen unter dem Finger prüfen (getrennt, damit `_tap_at`
## kurz bleibt und die Vorrangregel oben lesbar steht).
func _pick_target(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for ghost: Dictionary in state["ghosts"]:
		if _ghost_lift(ghost) <= 0.01:
			continue
		var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
		var at := _ghost_world(ghost, spot) + Vector3(0.0, GHOST_H * 0.4, 0.0)
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) and d < best_d:
			best_d = d
			best = {"kind": "ghost", "id": int(ghost["id"])}
	for flick: Dictionary in state["flickers"]:
		var spot: Dictionary = Logic.DECOY_SPOTS[int(flick["decoy"])]
		var at := Vector3(float(spot["x"]), 0.3, float(spot["z"]))
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) and d < best_d:
			best_d = d
			best = {"kind": "decoy", "decoy": int(flick["decoy"])}
	return best


# ---------------------------------------------------------------- Ereignisse


## Logik-Ereignisse in SFX, Juice und Banner übersetzen.
func _drain_events() -> void:
	var events: Array = state["events"]
	for e: Dictionary in events:
		_handle_event(e)
	events.clear()


func _handle_event(e: Dictionary) -> void:
	match str(e["type"]):
		"catch":
			_on_catch(e)
		"decoy":
			_on_decoy()
		"booWave":
			hud.show_banner(I18nService.t("mg.ghostHunt.boo"))
			AudioDirector.try_play(self, "mg_combo")
			_stage.pulse_glow(0.9)
			_gooby.emote("scared", 1.2)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.7)
		"booBonus":
			hud.show_banner(I18nService.t("mg.ghostHunt.booBonus", {"n": int(e["bonus"])}))
			AudioDirector.try_play(self, "mg_golden")
			_stage.pulse_glow(1.4)
			_gooby.play_for("celebrate", 1.2)
			_gooby.emote("ecstatic", 1.6)
			if ctx.juice != null:
				# Alle Buh-Geister erwischt: kleiner Feier-Moment.
				ctx.juice.hit_freeze(90)
				ctx.juice.confetti(46)
				ctx.juice.edge_glow(0.7, Color(0.75, 0.95, 1.0))
		"booEnd":
			hud.show_banner(I18nService.t("mg.ghostHunt.booMiss", {"n": int(e["caught"])}))
			AudioDirector.try_play(self, "mg_lose")
			_gooby.emote("sad", 1.4)
		"powerup":
			hud.show_banner(I18nService.t("mg.ghostHunt.%s" % str(e["kind"])))
			AudioDirector.try_play(self, "mg_golden")
			_stage.pulse_glow(1.1)
			_gooby.play_for("wave", 0.7)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
		"ghostGone":
			AudioDirector.try_play(self, "mg_spill")


func _on_catch(e: Dictionary) -> void:
	var spot: Dictionary = Logic.SPOTS[int(e["spot"])]
	var world := Vector3(float(spot["x"]), 1.05, float(spot["z"]))
	# Q2: Reduced-Motion-Gate an der eigenen Partikel-Call-Site — das
	# _3da-Kit gatet burst() nicht selbst (shake/JuiceKit gaten intern).
	if not _reduced_motion():
		_sparks.burst(world)
	_stage.pulse_glow(0.5 + 0.2 * float(e["chain"]))
	_stage.shake(0.03, 0.18)
	# Gooby dreht sich zum Fang und jubelt — er JAGT mit, er schaut nicht zu.
	_gooby.face(atan2(world.x - _gooby.position.x, world.z - _gooby.position.z))
	_gooby.play_for("wave", 0.5)
	_gooby.swing(0.32, 24.0, Vector3.FORWARD)
	_gooby.emote("ecstatic", 0.9)
	var chain := int(e["chain"])
	# Fang-Kette klettert hörbar (Halbton pro Kettenglied).
	AudioDirector.try_play(
		self, "mg_perfect" if chain > 1 else "mg_good", FeelSfx.combo_pitch(chain)
	)
	if ctx.juice == null:
		return
	# Eis-Ton statt Blassgelb (Audit A §2.10 P2): das "+n" stand über dem
	# Zaun im warmen Laternenschein und soff ab — kühles Geister-Weiß hebt
	# sich von Kürbisglühen UND Nachthimmel ab, der Kit-Saum bleibt dunkel.
	ctx.juice.float_text(_stage.to_screen(world), "+%d" % int(e["points"]), Color(0.88, 0.97, 1.0))
	ctx.juice.overlay_ring(_stage.to_screen(world), Color(0.75, 0.95, 1.0), 60.0)
	if chain >= 2:
		ctx.juice.show_combo(chain)
	if chain >= 3:
		ctx.juice.bloom_pulse(0.4)


func _on_decoy() -> void:
	AudioDirector.try_play(self, "mg_junk")
	hud.show_banner(I18nService.t("mg.ghostHunt.decoy"))
	_gooby.emote("dizzy", 1.2)
	_stage.shake(0.1, 0.32)
	if ctx.juice != null:
		ctx.juice.shake(0.4)
		ctx.juice.hit_flash(Color(0.75, 0.5, 0.95, 0.16), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	var result := Logic.run_meta(state)
	result["score"] = Logic.hunt_score(state)
	ctx.report_end(result)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


# ---------------------------------------------------------------- HUD 2D


## Nur noch das Ereignisband (gezeichnet vom HUD-Helfer) — die Szene ist 3D.
func _draw() -> void:
	if hud != null:
		hud.draw_banner()
