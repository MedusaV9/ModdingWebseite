extends TestCase
## W19 Liefer-Hetze-Politur — Wächter für drei Live-Demo-Befunde (Video-Review):
## (1) KAMERA: dunkle Hauswände füllten die obere Bildhälfte, sobald der
##     Verfolger-Boom beim Spurwechsel in einen Häuserblock schwenkte (vor dem
##     Fix: 54/2640 Straßen-Posen je Format mit Kulisse ZWISCHEN Kamera und
##     Wagen) — jetzt kappt die pure Kulissen-Klemme (Feel.cam_free_t) den
##     Boom in der XZ-Ebene vor der ersten Wand, auch die GEGLÄTTETE Pose.
## (2) LESBARKEIT: der Steuer-Hinweis lag als nackte Konturschrift über
##     Straße + rosa Routenband — jetzt Tinte auf Milchglas-Plate.
## (3) EINSTIEG: bis zum ersten Ring vergehen KONSTRUKTIV 4,6–10,8 s reine
##     Fahrzeit (Web-paritätische Zielwahl, Probe Seeds 1..40, Median 9,2 s) —
##     die Parität bleibt (test_pick_deliveries_matches_web!), stattdessen
##     ERKLÄRT der Erste-Lieferung-Beat die Wartezeit, sobald das Intro-Banner
##     gefallen ist. Die Sim-Zahlen bleiben unangetastet (View-Schicht).

const Logic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")
const Feel := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_feel.gd")
const Delivery := preload("res://scripts/minigames/games/delivery_rush/delivery_rush.gd")
const DELIVERY_SCENE := "res://scripts/minigames/games/delivery_rush/delivery_rush.tscn"

## Beide Leitformate (quer + hochkant) — die Kamera-Pose hängt am Format.
const FORMATE: Array[Vector2] = [Vector2(2868.0, 1320.0), Vector2(1320.0, 2868.0)]


func _mount(seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "deliveryRush"
	ctx.difficulty = "normal"
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(DELIVERY_SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


## Unabhängige Gegenprobe (eigenes Liang-Barsky, NICHT Feel.cam_free_t):
## schneidet die 2D-Strecke a→b das AABB `box`?
func _segment_hits_box(a: Vector2, b: Vector2, box: Dictionary) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var lo := float(box["minX"] if axis == 0 else box["minZ"])
		var hi := float(box["maxX"] if axis == 0 else box["maxZ"])
		if absf(d[axis]) < 1e-9:
			if a[axis] < lo or a[axis] > hi:
				return false
			continue
		var ta := (lo - a[axis]) / d[axis]
		var tb := (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return t0 <= t1


func _boom_frei(game: MinigameBase, cam: Camera3D) -> bool:
	var van: Vector2 = game.get("van_pos")
	var boom := Vector2(cam.position.x, cam.position.z)
	for box: Dictionary in game.get("_colliders"):
		if _segment_hits_box(van, boom, box):
			return false
	return true


# ── Befund 1: Kamera-Sichtfeld frei von Kulissen-Blockern ────────────────────


func test_cam_free_t_pure() -> void:
	var box := [{"minX": -5.0, "maxX": 5.0, "minZ": -5.0, "maxZ": 5.0}]
	assert_almost(Feel.cam_free_t(Vector2(0, 20), Vector2(0, 10), box), 1.0, 1e-9, "freier Boom")
	assert_almost(
		Feel.cam_free_t(Vector2(0, 20), Vector2(0, 10), []), 1.0, 1e-9, "keine Kollider = frei"
	)
	# Strecke von z=20 auf z=0 trifft die (um margin 1,2 erweiterte) Wand bei
	# z=6,2 → Eintritt bei t = (20−6,2)/20 = 0,69.
	assert_almost(
		Feel.cam_free_t(Vector2(0, 20), Vector2(0, 0), box), 0.69, 1e-6, "Klemme VOR der Wand"
	)
	# Start schon in der erweiterten Box: nichts vom Boom ist frei.
	assert_almost(
		Feel.cam_free_t(Vector2(0, 5.5), Vector2(0, -20), box), 0.0, 1e-9, "Start an der Wand"
	)
	# Wand liegt HINTER dem Boom-Ende: ganz frei.
	assert_almost(
		Feel.cam_free_t(Vector2(0, 30), Vector2(0, 12), box), 1.0, 1e-9, "Wand hinter dem Ende"
	)
	# Boom zeigt von der Wand weg: ebenfalls frei.
	assert_almost(
		Feel.cam_free_t(Vector2(0, 20), Vector2(0, 40), box), 1.0, 1e-9, "Boom von der Wand weg"
	)


func test_kamera_boom_bleibt_vor_kulissen() -> void:
	# Szenen-analytischer Sweep (Vorbild orientation_audit): alle Straßen-
	# kacheln × 5 Fahrbahn-Offsets × 16 Richtungen × beide Formate — die
	# Ziel-Pose der Kamera (Snap via _cam_ready=false) darf NIE eine Kulisse
	# zwischen sich und den Wagen lassen. VOR der Klemme: 54 rote Posen je
	# Format (Beweis-Probe, z. B. van=(-20,-56) heading=0 → cam in Block 2,3).
	var game := _mount()
	game.set("_intro_left", 0.0)
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	var offsets: Array[Vector2] = [
		Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)
	]
	for format in FORMATE:
		game.call("apply_view", format)
		var blockiert := 0
		var erste := ""
		for r in Logic.GRID:
			for c in Logic.GRID:
				if not Logic.is_road(r, c):
					continue
				for off in offsets:
					var pos := Logic.tile_to_world(r, c) + off
					for i in 16:
						game.set("van_pos", pos)
						game.set("van_heading", TAU * float(i) / 16.0)
						game.set("_cam_ready", false)
						game.call("_sync_camera", 0.016)
						if not _boom_frei(game, cam):
							blockiert += 1
							if erste.is_empty():
								erste = "van=%s heading=%.2f" % [pos, TAU * float(i) / 16.0]
		assert_eq(
			blockiert,
			0,
			"%s: %d Posen mit Kulisse vorm Wagen (z. B. %s)" % [format, blockiert, erste]
		)
	game.free()


func test_kamera_klemme_auch_beim_schwenk() -> void:
	# Der GEGLÄTTETE Boom (Lerp) schwenkt beim Abbiegen durch Blockecken —
	# genau der Live-Demo-Moment (~s 35-37). Worst-Case-Pose aus der Probe:
	# Ringstraße innen (z=-56), Wagen dreht einmal durch — JEDER Frame muss
	# frei bleiben, nicht nur die Ziel-Pose.
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.call("apply_view", FORMATE[0])
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	game.set("van_pos", Vector2(-20.0, -56.0))
	game.set("van_heading", PI)
	game.set("_cam_ready", false)
	game.call("_sync_camera", 0.016)
	for step in 90:
		game.set("van_heading", PI + TAU * float(step) / 90.0)
		game.call("_sync_camera", 0.033)
		assert_true(_boom_frei(game, cam), "Schwenk-Frame %d: Kulisse vorm Wagen" % step)
	game.free()


func test_kamera_klemme_laesst_freie_fahrt_unangetastet() -> void:
	# Gegenprobe: auf gerader Ringstraße (Boom liegt über der Fahrbahn) bleibt
	# die Verfolger-Pose EXAKT die alte — die Klemme greift nur im Blockfall.
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.call("apply_view", FORMATE[0])
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	game.set("van_pos", Vector2(0.0, -60.0))
	game.set("van_heading", PI * 0.5)
	game.set("_cam_ready", false)
	game.call("_sync_camera", 0.016)
	var back := float(Delivery.CAM_BACK)
	assert_almost(cam.position.x, -back, 1e-3, "voller Boom auf freier Strecke")
	assert_almost(cam.position.z, -60.0, 1e-3, "Boom bleibt auf der Fahrbahnachse")
	assert_almost(cam.position.y, float(Delivery.CAM_LIFT), 1e-3, "Hub unverändert")
	game.free()


func test_spawn_boom_frei_von_stelen() -> void:
	# Playtest-Fund derselben Kategorie (Beleg 022_erste_lieferung_beat.png):
	# die Shop-Stele stand EXAKT auf dem Van-Spawn (46,5 | −20) — jede Runde
	# begann mit einem orangen Mast quer durch die Verfolgerkamera. Regel:
	# KEINE Stele näher als 1,5 m am Start-Boom (Wagen→Kamera), beide Formate.
	var game := _mount()
	game.set("_intro_left", 0.0)
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	var steles: Array = (game.get("_world") as Node3D).get("stele_punkte")
	assert_eq(steles.size(), (Logic.LANDMARKS as Array).size(), "je Landmarke ein Stelen-Punkt")
	for format in FORMATE:
		game.call("apply_view", format)
		game.set("_cam_ready", false)
		game.call("_sync_camera", 0.016)
		var van: Vector2 = game.get("van_pos")
		var boom := Vector2(cam.position.x, cam.position.z)
		for punkt: Vector2 in steles:
			var d := _punkt_strecken_abstand(punkt, van, boom)
			assert_true(d > 1.5, "%s: Stele %s nur %.2f m vom Start-Boom" % [format, punkt, d])
	game.free()


func _punkt_strecken_abstand(punkt: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	if d.length_squared() < 1e-9:
		return punkt.distance_to(a)
	var t := clampf((punkt - a).dot(d) / d.length_squared(), 0.0, 1.0)
	return punkt.distance_to(a + d * t)


# ── Befund 2: Steuer-Hinweis mit Backing ─────────────────────────────────────


func test_hint_hat_milchglas_backing() -> void:
	var game := _mount()
	assert_true(game.get("_hint_plate") is StyleBoxFlat, "Milchglas-Plate vorhanden")
	var plate: StyleBoxFlat = game.get("_hint_plate")
	assert_true(plate.corner_radius_top_left > 0, "weiche Ecken (Banner-Muster)")
	var hint: Label = game.get("_hint_label")
	var ink := hint.get_theme_color("font_color")
	assert_true(ink.r > ink.b and ink.r < 0.6, "Tinte statt Weiß (lesbar auf Milchglas)")
	assert_true(hint.has_theme_color_override("font_outline_color"), "heller Saum")
	# Fade-Vertrag: Label UND Plate hängen am selben Alpha (tea_party-Muster).
	assert_almost(Feel.hint_alpha(0.0), 1.0, 1e-6, "Start: voll sichtbar")
	game.set("elapsed", float(Feel.HINT_FADE_SEC) + 1.3)
	assert_almost(Feel.hint_alpha(float(game.get("elapsed"))), 0.0, 1e-6, "nach Fade unsichtbar")
	game.call("_fade_hint")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "Label folgt dem Alpha")
	game.free()


# ── Befund 3: Erste-Lieferung-Beat erklärt die Wartezeit ─────────────────────


func test_erste_lieferung_beat_erklaert_wartezeit() -> void:
	var game := _mount()
	# Intro-Beat: Ziel-Banner steht (Bestandsvertrag test_g5_express1).
	assert_eq(str(game.get("_banner")), I18nService.t("mg.deliveryRush.intro"), "Intro-Banner")
	for _i in 4:
		game._process(0.4)
	# Intro vorbei, Intro-Banner (2,2 s) noch nicht gefallen.
	assert_false(bool(game.get("_first_leg_shown")), "Beat wartet, bis das Intro-Banner fällt")
	for _i in 16:
		game._process(0.1)
	var targets: Array = game.get("_targets")
	var name := I18nService.t("mg.deliveryRush.spot.%s" % str(targets[0]))
	var want := I18nService.t("mg.deliveryRush.first_leg", {"name": name})
	assert_eq(str(game.get("_banner")), want, "Beat benennt das ERSTE Ziel")
	assert_true(float(game.get("_banner_t")) > 3.0, "Beat steht mehrere Sekunden")
	assert_true(bool(game.get("_first_leg_shown")), "Beat ist verbucht")
	# Lücken-Vertrag: zwischen Intro-Banner und Beat bleibt das Feld nie
	# unerklärt (der Beat feuert im selben Frame, in dem das Banner fällt).
	assert_true(
		float(Feel.FIRST_LEG_BANNER_S) >= 4.0, "Beat deckt den Anfahrts-Median (~9 s) mit ab"
	)
	# Erste Zustellung ersetzt den Beat — und er feuert NIE wieder.
	var drop: Vector2 = game.call("current_drop")
	game.set("van_pos", drop)
	game.call("_check_drop", drop + Vector2(6.0, 0.0))
	assert_true(int(game.get("drops")) >= 1, "Zustellung passiert")
	assert_ne(str(game.get("_banner")), want, "Zustell-Banner löst den Beat ab")
	game.set("_banner_t", 0.0)
	game._process(0.1)
	assert_ne(str(game.get("_banner")), want, "kein zweiter Erste-Lieferung-Beat")
	game.free()


func test_erste_lieferung_beat_laesst_sim_zahlengleich() -> void:
	# Der Beat ist reine View-Schicht: gleicher Seed, gleiche Frames —
	# Fahrweg und Uhr bleiben bit-gleich zu einer Referenz ohne Banner-Beat.
	var with_beat := _mount(5)
	var reference := _mount(5)
	reference.set("_first_leg_shown", true)
	for game: MinigameBase in [with_beat, reference]:
		game.set("_intro_left", 0.0)
		game.set("steer", 0.4)
	for _i in 40:
		with_beat._process(0.05)
		reference._process(0.05)
	assert_eq(with_beat.get("van_pos"), reference.get("van_pos"), "Fahrweg bit-gleich")
	assert_almost(
		float(with_beat.get("elapsed")), float(reference.get("elapsed")), 0.0, "Uhr bit-gleich"
	)
	assert_eq(int(with_beat.get("score")), int(reference.get("score")), "Score gleich")
	with_beat.free()
	reference.free()
