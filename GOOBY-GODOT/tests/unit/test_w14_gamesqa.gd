extends TestCase
## W14/GAMESQA — Politur-Logik der Qualitätsrunde (nur Präsentation/Input):
## (1) Intro-Beat-Timing: alle sechs polierten Spiele teilen den 1,5-s-Beat;
##     starHopper GATET die Sim (Lauf bleibt zahlengleich), gvz läuft bewusst
##     ungebremst weiter (1. Welle kommt spät — Bestandstests bauen darauf).
## (2) starHopper-Wisch-Forgiveness: Zwei-Bahn-Schwelle skaliert mit der
##     Screenbreite (8 %), fällt aber nie unter den Web-Kontrakt von 40 px.
## (3) deliveryRush-Landmarken-Regel: die Leuchtkugel MUSS über der
##     Hochkant-Kamerahöhe schweben (7,5 m lag exakt drauf und fraß das Bild).

const Star := preload("res://scripts/minigames/games/star_hopper/star_hopper.gd")
const MemoryScene := preload("res://scripts/minigames/games/memory_match/memory_match.gd")
const HintFeel := preload("res://scripts/minigames/hint_feel.gd")
const Delivery := preload("res://scripts/minigames/games/delivery_rush/delivery_rush.gd")
const DeliveryWorld := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_world.gd")
const DeliveryLogic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")
const STAR_SCENE := "res://scripts/minigames/games/star_hopper/star_hopper.tscn"
const GVZ_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"

## Alle W14-polierten Spiele mit Intro-Beat (Skriptpfade).
const INTRO_SCRIPTS := {
	"starHopper": "res://scripts/minigames/games/star_hopper/star_hopper.gd",
	"gvz": "res://scripts/minigames/games/gvz/gvz_game.gd",
	"runner": "res://scripts/minigames/games/runner/runner.gd",
	"ranchZeit": "res://scripts/minigames/games/ranch_zeit/zeit_game.gd",
	"ranchTonnen": "res://scripts/minigames/games/ranch_tonnen/tonnen_game.gd",
	"ranchTurnier": "res://scripts/minigames/games/ranch_turnier/turnier_game.gd",
}


class GameStateDouble:
	extends RefCounted
	var state := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func test_intro_beat_timing_shared() -> void:
	for id: String in INTRO_SCRIPTS:
		var script: GDScript = load(INTRO_SCRIPTS[id])
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "%s hat INTRO_S" % id)
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "%s Intro-Beat = 1,5 s" % id)


func test_star_swipe_threshold_floor_and_scale() -> void:
	# Auf Phone-Breiten greift weiter der Web-Kontrakt (40 px Mindest-Wisch) …
	assert_almost(Star.swipe_threshold_px(390.0), 40.0, 1e-6, "iPhone-Breite: Web-Minimum")
	assert_almost(Star.swipe_threshold_px(500.0), 40.0, 1e-6, "Grenzbereich bleibt 40 px")
	# … auf breiten/Retina-Screens skaliert die Schwelle mit 8 % der Breite.
	assert_almost(Star.swipe_threshold_px(720.0), 57.6, 1e-6, "720 px → 8 % Breite")
	assert_almost(Star.swipe_threshold_px(1170.0), 93.6, 1e-6, "Retina → 8 % Breite")


func test_star_swipe_threshold_monotonic_and_bounded() -> void:
	var prev := 0.0
	for width: float in [320.0, 390.0, 430.0, 500.0, 640.0, 720.0, 900.0, 1170.0, 1290.0]:
		var got := Star.swipe_threshold_px(width)
		assert_true(got >= 40.0, "nie unter dem Web-Minimum (%.0f px)" % width)
		assert_true(got >= prev, "monoton steigend (%.0f px)" % width)
		assert_true(got < width * 0.5, "Tippen bleibt erreichbar (%.0f px)" % width)
		prev = got


func test_star_intro_gates_sim_then_runs() -> void:
	var ctx := MinigameCtx.new()
	ctx.game_id = "starHopper"
	ctx.difficulty = "normal"
	ctx.run_seed = 5
	var game: MinigameBase = (load(STAR_SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	# Während des Beats wartet die Sim: elapsed/traveled bleiben exakt 0.
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_almost(float(game.get("traveled")), 0.0, 1e-6, "kein Meter gefahren")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	assert_true(float(game.get("traveled")) > 0.0, "und der Lauf fährt los")
	game.free()


func test_gvz_intro_does_not_block_sim() -> void:
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	var game: MinigameBase = (load(GVZ_SCENE) as PackedScene).instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	game.call("open_level", 1)
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro-Beat gestartet")
	var tick_before := int((game.get("state") as Dictionary)["tick"])
	for _i in 10:
		game._process(0.05)
	# GvZ-Design: der Beat animiert NUR die Kamera — die Sim läuft ungebremst
	# (1. Welle kommt bei t=25 s; Bestandstests erwarten sofortiges Ticken).
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (0,5 s)")
	assert_true(
		int((game.get("state") as Dictionary)["tick"]) > tick_before,
		"Sim tickt WÄHREND des Intro-Beats"
	)
	game.free()


func test_star_flash_wraps_on_narrow_view() -> void:
	# W21 (Befund SH-2): Im Querformat-Fenster steht der Hochkant-Viewport
	# nur ~289–303 px breit (_ui-Floor 0,75) — der alte Ein-Zeilen-Draw
	# riss den Intro-Text an den Kanten ab (Playtest w21_mg_star_hopper,
	# Schritt 038). NEGATIVPROBE (Vorher-Rechnung): bei der natürlichen
	# Größe 30·_ui = 22 px war die EINE Zeile breiter als der Viewport.
	# W21/P5: der Flash läuft jetzt über den Kit-Banner-Standard — der
	# Wrap-Vertrag lebt in MgHudKit.banner_wrap_width (gleiche Garantie).
	var text := I18nService.t("mg.starHopper.intro")
	var font := ThemeService.font(800)
	var view_w := 289.0
	var ui := clampf(view_w / 390.0, 0.75, 3.0)
	var natural_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(30.0 * ui))
	assert_true(natural_w.x > view_w, "Vorher-Repro: Zeile (%.0f px) ragt raus" % natural_w.x)
	var wrap_w := MgHudKit.banner_wrap_width(view_w, ui)
	assert_true(wrap_w <= view_w, "Umbruch-Breite bleibt im Viewport")
	var wrapped := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, MgHudKit.font_px(MgHudKit.BANNER_FONT_D, ui)
	)
	assert_true(wrapped.x <= wrap_w + 1.0, "jede umbrochene Zeile bleibt im Bild")
	# Und auf dem Leitformat-Hochkant (breiter Viewport) bleibt Luft.
	assert_true(MgHudKit.banner_wrap_width(390.0, 1.0) <= 390.0)


func test_star_hint_fades_and_has_plate() -> void:
	# W21 (Befund SH-1): Hinweis bekam Milchglas-Plate (deliveryRush-Muster)
	# + M6-Fade — vorher stand blasse Lavendel-Schrift die GANZE Runde
	# direkt auf den hellblauen Bahnen. Fade-Fenster = identische Formel
	# wie deliveryRush Feel.hint_alpha: voll bis 5,8 s, 0 ab 7,0 s.
	assert_almost(Star.hint_alpha_at(0.0), 1.0, 1e-6, "Rundenstart: voll sichtbar")
	assert_almost(Star.hint_alpha_at(5.8), 1.0, 1e-6, "bis Fade-Beginn voll da")
	assert_almost(Star.hint_alpha_at(6.4), 0.5, 1e-6, "Fade halb")
	assert_almost(Star.hint_alpha_at(7.0), 0.0, 1e-6, "ab HINT_FADE_SEC weg")
	var ctx := MinigameCtx.new()
	ctx.game_id = "starHopper"
	ctx.difficulty = "normal"
	ctx.run_seed = 5
	var game: MinigameBase = (load(STAR_SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	var label: Label = game.get("_hint_label")
	var plate: StyleBoxFlat = game.get("_hint_plate")
	assert_true(plate != null, "Milchglas-Plate existiert")
	assert_true(
		label.get_theme_color("font_color").v < 0.6,
		"Hinweis-Tinte ist dunkel (auf Milchglas lesbar)"
	)
	assert_true(label.get_theme_constant("outline_size") >= 4, "heller Saum wie deliveryRush")
	game.free()


func test_memory_hint_stays_inside_viewport() -> void:
	# W21 (Befund MM-1, Playtest w21_mg_memory_quer Schritt 021): der
	# Hinweis bricht auf schmalen Hochkant-Viewports in 2 Zeilen um; die
	# feste 40-px-Höhe bei y−52 schob „Paare!" unter die Viewport-Kante.
	# NEGATIVPROBE (Vorher-Geometrie) + neuer Vertrag: Label-Unterkante
	# bleibt in JEDER geprüften Größe im Bild, die gemessene Umbruch-Höhe
	# passt ins Label, und die Milchglas-Plate existiert.
	var scene: PackedScene = load("res://scripts/minigames/games/memory_match/memory_match.tscn")
	for view: Vector2 in [Vector2(289, 630), Vector2(390, 844), Vector2(844, 390)]:
		var ctx := MinigameCtx.new()
		ctx.game_id = "memoryMatch"
		ctx.difficulty = "normal"
		ctx.run_seed = 5
		var game: MinigameBase = scene.instantiate()
		tree.root.add_child(game)
		game.setup(ctx)
		game.apply_view(view)
		var label: Label = game.get("_hint_label")
		var ui: float = game.get("_ui")
		var font_size := label.get_theme_font_size("font_size")
		var needed := MemoryScene.hint_height(
			label.get_theme_font("font"), label.text, label.size.x, font_size
		)
		# Vorher-Repro auf der schmalen Größe: 2 Zeilen brauchen mehr als
		# die alten 40·_ui px — genau deshalb ragte die zweite Zeile raus.
		if view.x < 320.0:
			assert_true(needed > 40.0 * ui, "Vorher-Repro: Umbruch sprengt die alte Fix-Höhe")
		assert_true(label.size.y >= needed - 0.5, "Label fasst den Umbruch (%s)" % view)
		var vp := game.get_viewport_rect().size
		assert_true(
			label.position.y + label.size.y <= vp.y + 0.5,
			"Hinweis-Unterkante bleibt im Bild (%s)" % view
		)
		assert_true(game.get("_hint_plate") != null, "Milchglas-Plate existiert")
		assert_true(
			label.get_theme_color("font_color").v < 0.6, "Tinte dunkel (auf Milchglas lesbar)"
		)
		game.free()


func test_hint_first_layout_not_giant() -> void:
	# W21 (Befund DR-1, Playtest w21: leere Milchglas-Plate am unteren Rand
	# von deliveryRush): set_size klemmt an der GECACHTEN Umbruch-Mindest-
	# höhe — beim ERSTEN Layout (Label-Breite ~0) heißt das „jedes Zeichen
	# eine Zeile", das Label wurde ~3400 px hoch und der ZENTRIERTE Text
	# stand unsichtbar weit UNTER dem Bild; nur die Plate ragte noch rein.
	# Ein zweites apply_view heilte es (der Font-Override invalidiert den
	# Cache) — darum sahen Headless-Probes gesund aus, der Host (EIN
	# Layout) nicht. Vertrag: schon NACH setup() trägt das Label die echte
	# Umbruch-Höhe (HintFeel.clamp_size); star/memory teilen den Aufbau.
	var faelle: Array = [
		["res://scripts/minigames/games/delivery_rush/delivery_rush.tscn", "deliveryRush"],
		["res://scripts/minigames/games/star_hopper/star_hopper.tscn", "starHopper"],
		["res://scripts/minigames/games/memory_match/memory_match.tscn", "memoryMatch"],
	]
	for fall: Array in faelle:
		var id := str(fall[1])
		var ctx := MinigameCtx.new()
		ctx.game_id = id
		ctx.difficulty = "normal"
		ctx.run_seed = 5
		var game: MinigameBase = (load(str(fall[0])) as PackedScene).instantiate()
		tree.root.add_child(game)
		game.setup(ctx)
		var label: Label = game.get("_hint_label")
		var font := label.get_theme_font("font")
		var fs := label.get_theme_font_size("font_size")
		var wrap_h := (
			font
			. get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, fs)
			. y
		)
		assert_true(
			label.size.y <= wrap_h + font.get_height(fs) + 8.0,
			(
				"%s: schon das ERSTE Layout misst die echte Umbruch-Höhe (size=%s, wrap=%.0f)"
				% [id, label.size, wrap_h]
			)
		)
		var vp := game.get_viewport_rect().size
		assert_true(
			label.position.y + label.size.y <= vp.y + 0.5,
			"%s: Unterkante im Bild (pos=%s size=%s vp=%s)" % [id, label.position, label.size, vp]
		)
		game.free()


func test_ranch_hints_have_plate_and_fade() -> void:
	# W21 (Befund RH-1, Playtest w21_mg_ranch_quer/062): der Herde-Hinweis
	# stand als heller SoftLabel-Text DIREKT auf dem hellgrünen Gras (kein
	# Backing, kein Fade, feste 360-px-Breite) — Parcours teilte denselben
	# nackten Aufbau. Beide tragen jetzt das deliveryRush-Muster: dunkle
	# Tinte + Milchglas-Plate + M6-Fade, Breite an den Viewport geklemmt.
	# Fade-Kurve = deliveryRush Feel.hint_alpha (voll bis 5,8 s, 0 ab 7 s).
	assert_almost(HintFeel.hint_alpha_at(0.0), 1.0, 1e-6, "Level-Start: voll sichtbar")
	assert_almost(HintFeel.hint_alpha_at(5.8), 1.0, 1e-6, "bis Fade-Beginn voll da")
	assert_almost(HintFeel.hint_alpha_at(6.4), 0.5, 1e-6, "Fade halb")
	assert_almost(HintFeel.hint_alpha_at(7.0), 0.0, 1e-6, "ab HINT_FADE_SEC weg")
	var faelle: Array = [
		["res://scripts/minigames/games/ranch_herde/herde_game.tscn", "ranchHerde"],
		["res://scripts/minigames/games/ranch_parcours/parcours_game.tscn", "ranchParcours"],
	]
	for fall: Array in faelle:
		var id := str(fall[1])
		var ctx := MinigameCtx.new()
		ctx.game_id = id
		ctx.difficulty = "normal"
		ctx.run_seed = 5
		var game: MinigameBase = (load(str(fall[0])) as PackedScene).instantiate()
		tree.root.add_child(game)
		game.setup(ctx)
		game.start()
		game.call("_on_level_chosen", 1)
		var label: Label = game.get("_hint_label")
		assert_true(label != null, "%s: Hinweis-Label steht nach Level-Start" % id)
		assert_true(game.get("_hint_plate") != null, "%s: Milchglas-Plate existiert" % id)
		assert_true(
			label.get_theme_color("font_color").v < 0.6,
			"%s: Tinte dunkel (auf Milchglas lesbar)" % id
		)
		assert_true(label.get_theme_constant("outline_size") >= 4, "%s: heller Saum" % id)
		# Breiten-Klemme: auf schmalen Hochkant-Viewports bleibt das Label im
		# Bild (braucht Autowrap — sonst klemmt die Mindestbreite bei der
		# vollen Textbreite und `size` ginge nie unter den Viewport).
		# NEGATIVPROBE der Erstfassung: EIN set_size klemmte die Höhe an der
		# Mindesthöhe der ALTEN Breite (~0) → „jedes Wort eine Zeile", das
		# Label wurde ~2300 px hoch (Plate deckte den Schirm). clamp_size
		# setzt Breite-zuerst-doppelt und liefert die echte Umbruch-Höhe.
		game.apply_view(Vector2(289, 630))
		var geo := "%s pos=%s size=%s" % [id, label.position, label.size]
		assert_true(label.position.x >= 0.0, "%s: Label-Linke im Bild" % geo)
		assert_true(label.position.x + label.size.x <= 289.5, "%s: Label-Rechte im Bild" % geo)
		assert_true(label.position.y >= 0.0, "%s: Label-Oberkante im Bild" % geo)
		assert_true(label.position.y + label.size.y <= 630.5, "%s: Label-Unterkante im Bild" % geo)
		var font := label.get_theme_font("font")
		var fs := label.get_theme_font_size("font_size")
		var wrap_h := (
			font
			. get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, fs)
			. y
		)
		assert_true(
			label.size.y <= wrap_h + font.get_height(fs),
			"%s: Höhe = echte Umbruch-Höhe (%.0f px), kein Riese" % [geo, wrap_h]
		)
		game.free()


func test_delivery_landmark_ball_clears_portrait_camera() -> void:
	var world: Node3D = DeliveryWorld.new()
	tree.root.add_child(world)
	world.call("_build_landmarks")
	var cam_height := float(Delivery.CAM_LIFT) + float(Delivery.CAM_PORTRAIT_LIFT)
	var balls := 0
	for child: Node in world.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh:
			balls += 1
			var mesh := (child as MeshInstance3D).mesh as SphereMesh
			var clearance := (child as MeshInstance3D).position.y - mesh.radius
			assert_true(
				clearance > cam_height + 1.0,
				"Leuchtkugel schwebt klar über der Hochkant-Kamera (%.1f m)" % cam_height
			)
	assert_eq(balls, (DeliveryLogic.LANDMARKS as Array).size(), "je Landmarke eine Kugel")
	world.free()
