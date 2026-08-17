extends TestCase
## W21/P5 — Wächter des MG-HUD-Kits (mg_hud_kit.gd) UND der Konsistenz-
## Matrix über die acht umgestellten Spiele (gvz, teaParty, starHopper,
## memoryMatch, ranchHerde, ranchParcours, carrotCatch, goalieGooby).
##
## Kit-Verträge: EIN _ui-Faktor (Kurzkante/390, 0,75–3,0), Typo-MINIMUM
## (kein effektiver HUD-Text unter 14 px — der 9–12-px-Befund), Plate-
## Vertrag (Milchglas-Creme, Chip = Tinte auf Frost OHNE Saum-Krücke),
## Banner-Standard (Ausblendkurve + Umbruch bleibt im Viewport, SH-2) und
## der Feier-Beat (MotionKit-basiert, Reduced-Motion-gated, Anti-Stapeln,
## RNG injizierbar — nie der Sim-Strom).
##
## Konsistenz-Matrix (Befund „sechs eigene Welten" → EINE Familie): alle
## Chip-Spiele tragen denselben Anker, dieselben Wert-/Unterzeilen-Größen
## und die Tinte-auf-Frost-Optik; das passive Chip-HUD bleibt ≤ 6 % der
## Fläche. Die Spiel-LOGIK bleibt unberührt (Web-Paritäts-Goldens decken
## sie separat ab).

const GAMES_DIR := "res://scripts/minigames/games"

## Chip-Spiele der Matrix: [Szene, game_id, Wert-Label, Unterzeile, Ranch?].
## gvz hat kein Label-HUD (draw_string-Zeichner) und wird separat geprüft.
const MATRIX: Array = [
	["tea_party/tea_party", "teaParty", "_time_label", "_streak_label", false],
	["star_hopper/star_hopper", "starHopper", "_dist_label", "_state_label", false],
	["memory_match/memory_match", "memoryMatch", "_time_label", "_miss_label", false],
	["carrot_catch/carrot_catch", "carrotCatch", "_time_label", "_combo_label", false],
	["goalie_gooby/goalie_gooby", "goalieGooby", "_time_label", "_saves_label", false],
	["ranch_herde/herde_game", "ranchHerde", "_zeit_label", "_drin_label", true],
	["ranch_parcours/parcours_game", "ranchParcours", "_zeit_label", "_punkte_label", true],
]


class GameStateDouble:
	extends RefCounted
	var state := {}
	var notified: Array = []

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

	func notify_slice_changed(slice_id: String) -> void:
		notified.append(slice_id)


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func test_ui_skala_kanon() -> void:
	# DER _ui-Faktor: Kurzkante/390, Boden 0,75, Deckel 3,0 — EINE Quelle
	# für alle acht Spiele (vorher rechnete jedes Spiel selbst).
	assert_almost(MgHudKit.ui_scale(Vector2(390.0, 844.0)), 1.0, 1e-6, "Phone-Hochkant = 1")
	assert_almost(MgHudKit.ui_scale(Vector2(844.0, 390.0)), 1.0, 1e-6, "Querformat: Kurzkante")
	assert_almost(
		MgHudKit.ui_scale(Vector2(834.0, 1194.0)), 834.0 / 390.0, 1e-6, "iPad: Kurzkante/390"
	)
	assert_almost(MgHudKit.ui_scale(Vector2(200.0, 400.0)), 0.75, 1e-6, "Boden bei 0,75")
	assert_almost(MgHudKit.ui_scale(Vector2(9999.0, 9999.0)), 3.0, 1e-6, "Deckel bei 3,0")


func test_typo_minimum() -> void:
	# Kein effektiver HUD-Text unter 14 px (Befund TP-1: 9-px-Bodenhinweis,
	# 9–12 px im Letterbox) — font_px bodenlost JEDE Kit-Schriftgröße.
	assert_eq(MgHudKit.FONT_MIN_PX, 14, "Typo-Minimum ist 14 px")
	for design: float in [9.0, 12.0, 15.0, 20.0]:
		assert_true(
			MgHudKit.font_px(design, MgHudKit.UI_MIN) >= 14,
			"%.0f px Entwurf unterm 0,75er-Boden nie unter 14 px" % design
		)
	# Oberhalb des Bodens gilt die AcTokens-px-Rundung unverändert.
	assert_eq(MgHudKit.font_px(26.0, 2.0), AcTokens.px(26.0, 2.0), "Skala×f wie AcTokens.px")
	assert_eq(MgHudKit.font_px(34.0, 1.0), 34, "Faktor 1 bleibt Entwurfsgröße")


func test_plate_und_chip_vertrag() -> void:
	# Milchglas-Kanon: warme Creme, EINE Quelle für Banner/Hinweis-Plates.
	var plate := MgHudKit.plate_color()
	assert_almost(plate.a, MgHudKit.PLATE_ALPHA, 1e-6, "Plate-Alpha aus dem Kit")
	assert_true(plate.r >= 0.99 and plate.b < plate.r, "warme Creme (kein kaltes Weiß)")
	# Chip-Vertrag: Wert = Tinte auf Frost OHNE Saum (der Saum war die
	# Krücke nackter Labels), Unterzeile weicher; Anker im Kit-Raster.
	var value := Label.new()
	var caption := Label.new()
	tree.root.add_child(value)
	tree.root.add_child(caption)
	MgHudKit.style_chip(value, caption, 1.0)
	MgHudKit.layout_chip(value, caption, 1.0)
	assert_eq(
		value.get_theme_font_size("font_size"),
		MgHudKit.font_px(MgHudKit.CHIP_VALUE_D, 1.0),
		"Wert-Zeile = Kit-Größe (SIZE_BUTTON)"
	)
	assert_eq(
		caption.get_theme_font_size("font_size"),
		MgHudKit.font_px(MgHudKit.CHIP_CAPTION_D, 1.0),
		"Unterzeile = Kit-Größe (SIZE_CAPTION)"
	)
	assert_eq(value.get_theme_color("font_color"), AcTokens.INK, "Wert = Tinte")
	assert_eq(value.get_theme_constant("outline_size"), 0, "kein Saum auf der Pille")
	assert_eq(value.position, MgHudKit.CHIP_ORIGIN_D, "Anker oben links (16, 10)")
	assert_eq(
		caption.position,
		MgHudKit.CHIP_ORIGIN_D + Vector2(0.0, MgHudKit.CHIP_ROW_STEP_D),
		"Unterzeile im festen Raster"
	)
	# Pillen-Rect: Wert + Unterzeile + Padding auf BEIDEN Seiten.
	value.text = "60 s"
	caption.text = "Serie ×3"
	await wait_frames(1)
	var rect := MgHudKit.chip_rect(value, caption, 1.0)
	assert_almost(rect.position.x, 16.0 - MgHudKit.CHIP_PAD_D.x, 1e-4, "Pad links")
	assert_true(
		rect.size.x >= maxf(value.size.x, caption.size.x) + MgHudKit.CHIP_PAD_D.x * 2.0 - 1e-4,
		"Pille fasst beide Zeilen + Pad"
	)
	value.free()
	caption.free()


func test_banner_kurve_und_umbruch() -> void:
	# Ausblendkurve = die etablierte tea/memory/carrot-Kurve (t·1,4).
	assert_almost(MgHudKit.banner_alpha(0.0), 0.0, 1e-6, "abgelaufen = unsichtbar")
	assert_almost(MgHudKit.banner_alpha(0.5), 0.7, 1e-6, "halbe Restzeit = 0,7")
	assert_almost(MgHudKit.banner_alpha(2.0), 1.0, 1e-6, "frisch = voll da")
	# Umbruch-Vertrag (SH-2): jede Zeile bleibt im Viewport — auch im
	# schmalen Letterbox-Hochkant (~289 px, _ui am 0,75er-Boden).
	for view_w: float in [289.0, 390.0, 844.0, 1194.0]:
		var ui := MgHudKit.ui_scale(Vector2(view_w, view_w * 2.0))
		var w := MgHudKit.banner_wrap_width(view_w, ui)
		assert_true(w <= view_w * 0.92 + 1e-4, "%.0f px: Breite bleibt im Bild" % view_w)
		assert_true(w <= MgHudKit.BANNER_W_D * ui + 1e-4, "%.0f px: Deckel 460×ui" % view_w)


func test_progress_vertrag() -> void:
	# EINE Balkenhöhe für alle Spiel-Fortschritte (AcTokens.BAR_H × ui).
	assert_almost(MgHudKit.bar_h(1.0), float(AcTokens.BAR_H), 1e-6, "Faktor 1 = Token")
	assert_almost(
		MgHudKit.bar_h(2.0), float(AcTokens.px(float(AcTokens.BAR_H), 2.0)), 1e-6, "skaliert ×f"
	)
	var plate := MgHudKit.progress_plate()
	assert_true(plate.bg_color.a < 0.6, "Track ist Milchglas (liest sich über 3D)")


func test_feier_beat_rm_gated() -> void:
	# Reduced Motion: Endzustand SOFORT (keine Feder, keine Flöckchen) —
	# der Beat bleibt sichtbar, nur die Bewegung entfällt (MotionKit-Kanon).
	var rm_vorher := _set_reduced_motion(true)
	var host := Control.new()
	tree.root.add_child(host)
	var beat := MgHudKit.feier_beat(host, Vector2(844.0, 390.0), 1.0, "Feier!")
	assert_true(beat != null and beat.is_inside_tree(), "Beat hängt am Host")
	assert_true(beat.scale.is_equal_approx(Vector2.ONE), "RM: sofort in Ruhelage")
	assert_almost(beat.modulate.a, 1.0, 1e-6, "RM: sofort voll sichtbar")
	var flocken := 0
	for kind: Node in beat.get_children():
		if kind is ColorRect:
			flocken += 1
	assert_eq(flocken, 0, "RM: kein Papier-Sparkle")
	var label := beat.get_node(^"Plate/Text") as Label
	assert_true(
		label.get_theme_font_size("font_size") >= MgHudKit.FONT_MIN_PX,
		"Beat-Text hält das Typo-Minimum"
	)
	# Ohne RM: Pop-In läuft, Sparkle streut aus dem INJIZIERTEN RNG (Tests)
	# — Spiele lassen ihn null, der Sim-Strom (GoobyRng) bleibt unberührt.
	_set_reduced_motion(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var beat2 := MgHudKit.feier_beat(host, Vector2(844.0, 390.0), 1.0, "Nochmal!", rng)
	assert_true(beat.is_queued_for_deletion(), "Anti-Stapeln: neuer Beat ersetzt den alten")
	flocken = 0
	for kind: Node in beat2.get_children():
		if kind is ColorRect:
			flocken += 1
	assert_eq(flocken, MotionKit.PUFF_TEILE, "Sparkle = MotionKit-Flöckchenzahl")
	assert_true(beat2.modulate.a < 1.0, "ohne RM federt der Pop-In (startet transparent)")
	host.free()
	_set_reduced_motion(rm_vorher)


func test_konsistenz_matrix_chips() -> void:
	# „Sechs eigene Welten" → EINE Familie: alle Chip-Spiele tragen exakt
	# denselben Anker, dieselben Schriftgrößen und die Tinte-auf-Frost-
	# Optik; das passive Chip-HUD bleibt ≤ 6 % der Fläche (Abnahme §8/P5).
	var view := Vector2(844.0, 390.0)
	for fall: Array in MATRIX:
		var id := str(fall[1])
		var ctx := MinigameCtx.new()
		ctx.game_id = id
		ctx.difficulty = "normal"
		ctx.run_seed = 5
		var scene: PackedScene = load("%s/%s.tscn" % [GAMES_DIR, fall[0]])
		var game: MinigameBase = scene.instantiate()
		tree.root.add_child(game)
		game.setup(ctx)
		game.start()
		if bool(fall[4]):
			game.call("_on_level_chosen", 1)
		game.apply_view(view)
		var ui := MgHudKit.ui_scale(view)
		var value: Label = game.get(str(fall[2]))
		var caption: Label = game.get(str(fall[3]))
		assert_true(value != null and caption != null, "%s: Chip-Labels stehen" % id)
		assert_eq(value.position, MgHudKit.CHIP_ORIGIN_D * ui, "%s: Kit-Anker" % id)
		assert_eq(
			value.get_theme_font_size("font_size"),
			MgHudKit.font_px(MgHudKit.CHIP_VALUE_D, ui),
			"%s: Wert-Größe aus dem Kit" % id
		)
		assert_eq(
			caption.get_theme_font_size("font_size"),
			MgHudKit.font_px(MgHudKit.CHIP_CAPTION_D, ui),
			"%s: Unterzeilen-Größe aus dem Kit" % id
		)
		assert_eq(value.get_theme_color("font_color"), AcTokens.INK, "%s: Tinte auf Frost" % id)
		assert_eq(value.get_theme_constant("outline_size"), 0, "%s: kein Saum-Klotz mehr" % id)
		await wait_frames(1)
		var rect := MgHudKit.chip_rect(value, caption, ui)
		var anteil := rect.get_area() / (view.x * view.y)
		assert_true(anteil <= 0.06, "%s: Chip-HUD ≤ 6%% Fläche (ist %.1f%%)" % [id, anteil * 100.0])
		game.free()


func test_gvz_hud_folgt_dem_kit() -> void:
	# gvz zeichnet sein Gefechts-HUD direkt (GvzHud, kein Label-Chip) — der
	# Skalierungs-Faktor kommt trotzdem aus DERSELBEN Kit-Quelle, und ein
	# echter Draw-Durchlauf (Karten, Zähler, Banner) läuft fehlerfrei.
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	var game: MinigameBase = (
		(load("res://scripts/minigames/games/gvz/gvz_game.tscn") as PackedScene).instantiate()
	)
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	game.call("open_level", 1)
	var hud: RefCounted = game.get("_hud")
	var vp: Vector2 = game.get_viewport_rect().size
	assert_almost(
		float(hud.call("ui")), MgHudKit.ui_scale(vp), 1e-6, "gvz-HUD skaliert mit dem Kit-Faktor"
	)
	# Kartenleiste hängt an der Kit-Skala (die Fix-Pixel-Schuld GVZ-1).
	var dims: Vector2 = game.call("_card_dims")
	assert_true(dims.x > 0.0 and dims.y > 0.0, "Karten haben Maße")
	hud.call("show_banner", I18nService.t("gvz.hud.wave", {"n": 1}), "wave")
	await wait_frames(2)
	assert_true(is_instance_valid(game), "Draw-Durchlauf (Chip/Karten/Banner) ohne Fehler")
	game.free()


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_hudkit.json")
	var en := _flat_keys("res://strings/en/mg_hudkit.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	for key: String in ["beat_paar", "beat_schaf", "beat_welle", "beat_gold", "beat_perfekt"]:
		assert_true(de.has("mg.hudkit.%s" % key), "Feier-Key %s vorhanden" % key)
	assert_ne(
		I18nService.t("mg.hudkit.beat_welle"),
		"mg.hudkit.beat_welle",
		"Loader mergt die neue Domain-Datei flach"
	)


func _flat_keys(path: String) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_true(file != null, "%s fehlt" % path)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	var out: Array[String] = []
	_collect_keys("", data, out)
	out.sort()
	return out


func _collect_keys(prefix: String, node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			var path := key if prefix.is_empty() else "%s.%s" % [prefix, key]
			_collect_keys(path, node[key], out)
		return
	out.append(prefix)
